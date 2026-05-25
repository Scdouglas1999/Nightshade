//! HEALPix star-tile pack opened from a verified on-disk catalog directory.
//!
//! Tiles are memory-mapped and accessed in place via [`zerocopy`] — no heap copy
//! of the per-tile star or LOD arrays is performed. Per the planetarium-v2 design
//! (§6.2) a single 768-tile HYG pack with ~3k stars/tile keeps ~64 MiB resident as
//! file-backed virtual memory rather than as anonymous heap, so cold-cache tile
//! loads page in on demand and warm tiles share OS file cache across processes.

use std::borrow::Cow;
use std::collections::BTreeMap;
use std::fs::File;
use std::ops::Range;
use std::path::{Path, PathBuf};

use memmap2::Mmap;
use zerocopy::FromBytes;

use super::hit_index::HitIndex;
use super::pack::{load_and_verify_pack, PackError, PackManifest};
use super::set::StarPack;
use super::tile::{parse_tile, LodEntry, StarRecord, TileHeader};

const TILES_PREFIX: &str = "tiles/";
const TILE_SUFFIX: &str = ".bin";

/// HEALPix star tiles mmap'd from a verified pack directory (`pack.json` + `tiles/*.bin`).
struct StarTilePack {
    pack_id: String,
    nside: u32,
    tiles: BTreeMap<u64, TileBlob>,
}

/// One tile's backing storage.
///
/// Invariants (established at construction by [`load_tile_file`]):
///
/// * `mmap[lod_range]` is exactly `lod_count * size_of::<LodEntry>()` bytes and
///   starts at an offset that satisfies `LodEntry`'s alignment.
/// * `mmap[stars_range]` is exactly `star_count * size_of::<StarRecord>()` bytes
///   and starts at an offset that satisfies `StarRecord`'s alignment.
/// * Both ranges have already been validated by [`parse_tile`] (size, LOD bounds,
///   magic) — accessors may slice without re-checking.
///
/// The mapping is held for the lifetime of the catalog handle; dropping a
/// [`StarTilePack`] unmaps every tile file.
struct TileBlob {
    /// Page-aligned read-only mapping of the tile file. Held alive so the
    /// `&[StarRecord]` / `&[LodEntry]` slices returned by the accessors remain
    /// valid for as long as this `TileBlob` exists.
    _file: File,
    mmap: Mmap,
    lod_range: Range<usize>,
    stars_range: Range<usize>,
}

impl TileBlob {
    /// Zero-copy view of the tile's LOD index, borrowed from the mapping.
    fn lod_entries(&self) -> &[LodEntry] {
        // SAFETY of unwraps: the byte range was validated by `parse_tile` at
        // construction. A subsequent unmap is not possible because `mmap` is
        // owned by `self`.
        LodEntry::slice_from(&self.mmap[self.lod_range.clone()])
            .expect("lod range validated at load")
    }

    /// Zero-copy view of the tile's star records, borrowed from the mapping.
    fn stars(&self) -> &[StarRecord] {
        StarRecord::slice_from(&self.mmap[self.stars_range.clone()])
            .expect("stars range validated at load")
    }
}

/// Load and verify `pack_dir`, then open all `tiles/*.bin` entries as a [`StarPack`].
pub fn open_star_tile_pack(pack_dir: &Path) -> Result<Box<dyn StarPack>, PackError> {
    let manifest = load_and_verify_pack(pack_dir)?;
    Ok(Box::new(StarTilePack::from_manifest(pack_dir, manifest)?))
}

impl StarTilePack {
    fn from_manifest(pack_dir: &Path, manifest: PackManifest) -> Result<Self, PackError> {
        let mut tile_paths: Vec<String> = manifest
            .files
            .keys()
            .filter(|rel| is_star_tile_path(rel))
            .cloned()
            .collect();
        if tile_paths.is_empty() {
            return Err(PackError::NoStarTiles);
        }
        tile_paths.sort();

        let mut tiles = BTreeMap::new();
        let mut nside: Option<u32> = None;

        for rel in tile_paths {
            let filename_id = parse_tile_filename_id(&rel)?;
            let path = pack_dir.join(from_posix(&rel));
            let (header, tile) = load_tile_file(&path, &rel)?;
            if header.healpix_id != filename_id {
                return Err(PackError::HealpixIdMismatch {
                    path: rel.clone(),
                    filename_id,
                    header_id: header.healpix_id,
                });
            }
            match nside {
                None => nside = Some(header.nside),
                Some(expected) if header.nside != expected => {
                    return Err(PackError::NsideMismatch {
                        path: rel,
                        nside: header.nside,
                        expected,
                    });
                }
                _ => {}
            }
            let healpix_id = header.healpix_id;
            if tiles.insert(healpix_id, tile).is_some() {
                return Err(PackError::InvalidManifest(
                    "duplicate healpix tile id in manifest",
                ));
            }
        }

        Ok(Self {
            pack_id: manifest.id,
            nside: nside.expect("at least one tile"),
            tiles,
        })
    }
}

fn is_star_tile_path(rel: &str) -> bool {
    rel.starts_with(TILES_PREFIX)
        && rel.ends_with(TILE_SUFFIX)
        && rel.len() > TILES_PREFIX.len() + TILE_SUFFIX.len()
}

fn parse_tile_filename_id(rel: &str) -> Result<u64, PackError> {
    let name = rel
        .strip_prefix(TILES_PREFIX)
        .and_then(|s| s.strip_suffix(TILE_SUFFIX))
        .ok_or(PackError::InvalidManifest("malformed tiles/*.bin path"))?;
    if name.len() != 12 || !name.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(PackError::InvalidManifest(
            "tile filename must be tiles/{healpix_id:012x}.bin",
        ));
    }
    u64::from_str_radix(name, 16)
        .map_err(|_| PackError::InvalidManifest("tile filename healpix id is not valid hex"))
}

fn load_tile_file(path: &Path, rel: &str) -> Result<(TileHeader, TileBlob), PackError> {
    let file = File::open(path).map_err(|source| PackError::Io {
        context: "open star tile",
        source,
    })?;
    // SAFETY: pack integrity verified by `load_and_verify_pack`; tiles are
    // read-only for the pack lifetime. We never hand out `&mut` aliases into the
    // mapping and never call `Mmap::map_mut`.
    let mmap = unsafe { Mmap::map(&file) }.map_err(|source| PackError::Io {
        context: "mmap star tile",
        source,
    })?;
    let parsed = parse_tile(&mmap).map_err(|source| PackError::InvalidTile {
        path: rel.to_string(),
        source,
    })?;
    let header = *parsed.header;
    let base = mmap.as_ptr() as usize;
    let lod_start = (parsed.lod_entries.as_ptr() as usize)
        .checked_sub(base)
        .expect("lod slice within mmap");
    let lod_end = lod_start + std::mem::size_of_val(parsed.lod_entries);
    let stars_start = (parsed.stars.as_ptr() as usize)
        .checked_sub(base)
        .expect("stars slice within mmap");
    let stars_end = stars_start + std::mem::size_of_val(parsed.stars);
    debug_assert!(lod_end <= stars_start, "LOD must precede stars in v1 tiles");
    debug_assert!(stars_end <= mmap.len(), "stars range within mmap");

    Ok((
        header,
        TileBlob {
            _file: file,
            mmap,
            lod_range: lod_start..lod_end,
            stars_range: stars_start..stars_end,
        },
    ))
}

fn from_posix(s: &str) -> PathBuf {
    PathBuf::from(s.replace('/', std::path::MAIN_SEPARATOR_STR))
}

impl StarPack for StarTilePack {
    fn pack_id(&self) -> &str {
        &self.pack_id
    }

    fn nside(&self) -> u32 {
        self.nside
    }

    fn stars_in_pixel(&self, healpix_id: u64) -> Option<Cow<'_, [StarRecord]>> {
        self.tiles
            .get(&healpix_id)
            .map(|t| Cow::Borrowed(t.stars()))
    }

    fn lod_entries_for_pixel(&self, healpix_id: u64) -> Option<Cow<'_, [LodEntry]>> {
        self.tiles
            .get(&healpix_id)
            .map(|t| Cow::Borrowed(t.lod_entries()))
    }

    fn build_hit_index(&self) -> HitIndex {
        let mut idx = HitIndex::new(self.nside);
        for tile in self.tiles.values() {
            for &star in tile.stars() {
                idx.insert_star(star)
                    .expect("tile stars must index at pack nside");
            }
        }
        idx
    }
}
