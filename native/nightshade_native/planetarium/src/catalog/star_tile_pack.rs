//! HEALPix star-tile pack opened from a verified on-disk catalog directory.

use std::borrow::Cow;
use std::collections::BTreeMap;
use std::fs::File;
use std::path::{Path, PathBuf};

use memmap2::Mmap;

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

struct TileBlob {
    _file: File,
    stars: Vec<StarRecord>,
    lod_entries: Vec<LodEntry>,
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
    u64::from_str_radix(name, 16).map_err(|_| {
        PackError::InvalidManifest("tile filename healpix id is not valid hex")
    })
}

fn load_tile_file(path: &Path, rel: &str) -> Result<(TileHeader, TileBlob), PackError> {
    let file = File::open(path).map_err(|source| PackError::Io {
        context: "open star tile",
        source,
    })?;
    // SAFETY: pack integrity verified; tiles are read-only for the pack lifetime.
    let mmap = unsafe { Mmap::map(&file) }.map_err(|source| PackError::Io {
        context: "mmap star tile",
        source,
    })?;
    let parsed = parse_tile(&mmap).map_err(|source| PackError::InvalidTile {
        path: rel.to_string(),
        source,
    })?;
    Ok((
        *parsed.header,
        TileBlob {
            _file: file,
            stars: parsed.stars.to_vec(),
            lod_entries: parsed.lod_entries.to_vec(),
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
            .map(|t| Cow::Borrowed(t.stars.as_slice()))
    }

    fn lod_entries_for_pixel(&self, healpix_id: u64) -> Option<Cow<'_, [LodEntry]>> {
        self.tiles
            .get(&healpix_id)
            .map(|t| Cow::Borrowed(t.lod_entries.as_slice()))
    }

    fn build_hit_index(&self) -> HitIndex {
        let mut idx = HitIndex::new(self.nside);
        for tile in self.tiles.values() {
            for &star in &tile.stars {
                idx.insert_star(star)
                    .expect("tile stars must index at pack nside");
            }
        }
        idx
    }
}
