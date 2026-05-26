//! HEALPix tile binary format (zerocopy).
//!
//! File layout per design §6.2:
//! ```text
//! [TileHeader — 64 B][LodEntry × lod_levels — 16 B each][StarRecord × star_count]
//! ```

use zerocopy::{AsBytes, FromBytes, FromZeroes};

/// Magic bytes identifying a planetarium star tile (`"NSPLNT01"`).
pub const TILE_MAGIC: &[u8; 8] = b"NSPLNT01";

/// Fixed header size (bytes).
pub const TILE_HEADER_LEN: usize = 64;

/// Per-LOD index entry size (bytes).
pub const LOD_ENTRY_LEN: usize = 16;

/// Errors while parsing or validating a tile blob.
#[derive(Debug, thiserror::Error)]
pub enum TileParseError {
    /// Buffer shorter than the fixed header.
    #[error("tile truncated: need at least {TILE_HEADER_LEN} bytes, got {actual}")]
    TruncatedHeader {
        /// Bytes available.
        actual: usize,
    },
    /// Magic does not match [`TILE_MAGIC`].
    #[error("invalid tile magic (expected NSPLNT01)")]
    BadMagic,
    /// Total byte length does not match header fields.
    #[error("tile size mismatch: expected {expected} bytes, got {actual}")]
    SizeMismatch {
        /// Expected length from header.
        expected: usize,
        /// Actual buffer length.
        actual: usize,
    },
    /// A LOD entry references stars outside `star_count`.
    #[error(
        "LOD entry {index}: start_offset {start} + count {count} exceeds star_count {star_count}"
    )]
    LodRange {
        /// Index of the offending LOD entry.
        index: usize,
        /// `start_offset` field.
        start: u32,
        /// `count` field.
        count: u32,
        /// Header `star_count`.
        star_count: u32,
    },
    /// `star_count` does not equal the number of star records in the buffer.
    #[error("star_count {declared} does not match {actual} star records in blob")]
    StarCountMismatch {
        /// Value in header.
        declared: u32,
        /// Records parsed from tail.
        actual: usize,
    },
}

/// 64-byte tile header (design §6.2).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, FromZeroes, FromBytes, AsBytes)]
pub struct TileHeader {
    /// Must equal [`TILE_MAGIC`].
    pub magic: [u8; 8],
    /// Pack-local catalog identifier.
    pub catalog_id: u32,
    /// Pack format version.
    pub pack_version: u32,
    /// HEALPix `nside` for this tile set.
    pub nside: u32,
    /// Padding so `healpix_id` is 8-byte aligned (keeps header exactly 64 B, no implicit padding).
    _pad_before_healpix: u32,
    /// HEALPix pixel index (nested or ring — pack-defined; stored as opaque id).
    pub healpix_id: u64,
    /// Number of [`StarRecord`] entries following the LOD table.
    pub star_count: u32,
    /// Number of [`LodEntry`] records immediately after this header.
    pub lod_levels: u32,
    /// Reserved; must be zero in v1 tiles.
    pub reserved: [u8; 24],
}

impl TileHeader {
    /// Build a header with magic and reserved fields zeroed.
    #[must_use]
    pub fn new(
        catalog_id: u32,
        pack_version: u32,
        nside: u32,
        healpix_id: u64,
        star_count: u32,
        lod_levels: u32,
    ) -> Self {
        Self {
            magic: *TILE_MAGIC,
            catalog_id,
            pack_version,
            nside,
            _pad_before_healpix: 0,
            healpix_id,
            star_count,
            lod_levels,
            reserved: [0; 24],
        }
    }

    /// Returns `true` when `magic` matches [`TILE_MAGIC`].
    #[must_use]
    pub fn magic_valid(&self) -> bool {
        &self.magic == TILE_MAGIC
    }
}

/// Magnitude-band index entry (16 bytes).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, FromZeroes, FromBytes, AsBytes)]
pub struct LodEntry {
    /// Apparent magnitude threshold for this band (inclusive upper bound for the band).
    pub mag_threshold: f32,
    /// Index of the first star in this band within the tile's star array.
    pub start_offset: u32,
    /// Number of stars in this band.
    pub count: u32,
    /// Reserved; must be zero in v1 tiles.
    pub reserved: u32,
}

/// Packed on-disk star record (sorted brightest-first within each tile).
///
/// Field order matches the GPU star-instance layout (design §5.2: `icrs_dir`, `mag`,
/// `bv`, `flags`), plus `hip_id` for hit testing.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, FromZeroes, FromBytes, AsBytes)]
pub struct StarRecord {
    /// Hipparcos catalog id (`0` if unknown).
    pub hip_id: u32,
    /// Bit flags: variable, double, etc. (renderer-specific).
    pub flags: u32,
    /// Unit direction in ICRS (J2000).
    pub icrs_dir: [f32; 3],
    /// Apparent V magnitude.
    pub mag: f32,
    /// B−V color index; use `f32::NAN` when unknown.
    pub bv: f32,
}

impl StarRecord {
    /// Construct a record from spherical coordinates (radians) and magnitude.
    #[must_use]
    pub fn from_radec(
        hip_id: u32,
        ra_rad: f32,
        dec_rad: f32,
        mag: f32,
        bv: f32,
        flags: u32,
    ) -> Self {
        let (sin_dec, cos_dec) = dec_rad.sin_cos();
        let (sin_ra, cos_ra) = ra_rad.sin_cos();
        Self {
            hip_id,
            flags,
            icrs_dir: [cos_dec * cos_ra, cos_dec * sin_ra, sin_dec],
            mag,
            bv,
        }
    }
}

/// Borrowed view of a validated tile blob.
#[derive(Debug, Clone, Copy)]
pub struct ParsedTile<'a> {
    /// Tile header (first 64 bytes).
    pub header: &'a TileHeader,
    /// LOD index table.
    pub lod_entries: &'a [LodEntry],
    /// Star records (brightest first).
    pub stars: &'a [StarRecord],
}

/// Total on-disk size for a tile with the given counts.
#[must_use]
pub fn tile_byte_len(lod_levels: usize, star_count: usize) -> usize {
    TILE_HEADER_LEN + lod_levels * LOD_ENTRY_LEN + star_count * core::mem::size_of::<StarRecord>()
}

/// Serialize header, LOD table, and stars into a single little-endian blob.
#[must_use]
pub fn encode_tile(header: &TileHeader, lod_entries: &[LodEntry], stars: &[StarRecord]) -> Vec<u8> {
    assert_eq!(
        header.lod_levels as usize,
        lod_entries.len(),
        "lod_levels must match lod_entries.len()"
    );
    assert_eq!(
        header.star_count as usize,
        stars.len(),
        "star_count must match stars.len()"
    );

    let mut out = Vec::with_capacity(tile_byte_len(lod_entries.len(), stars.len()));
    out.extend_from_slice(header.as_bytes());
    for entry in lod_entries {
        out.extend_from_slice(entry.as_bytes());
    }
    for star in stars {
        out.extend_from_slice(star.as_bytes());
    }
    out
}

/// Parse and validate a tile from an in-memory byte slice.
pub fn parse_tile(bytes: &[u8]) -> Result<ParsedTile<'_>, TileParseError> {
    if bytes.len() < TILE_HEADER_LEN {
        return Err(TileParseError::TruncatedHeader {
            actual: bytes.len(),
        });
    }

    let header = TileHeader::ref_from_prefix(bytes).ok_or(TileParseError::TruncatedHeader {
        actual: bytes.len(),
    })?;
    if !header.magic_valid() {
        return Err(TileParseError::BadMagic);
    }

    let lod_count = header.lod_levels as usize;
    let star_count = header.star_count as usize;
    let expected = tile_byte_len(lod_count, star_count);
    if bytes.len() != expected {
        return Err(TileParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        });
    }

    let mut rest = &bytes[TILE_HEADER_LEN..];
    let lod_entries = LodEntry::slice_from_prefix(rest, lod_count)
        .map(|(s, r)| {
            rest = r;
            s
        })
        .ok_or(TileParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        })?;

    let stars = StarRecord::slice_from_prefix(rest, star_count)
        .map(|(s, r)| {
            rest = r;
            s
        })
        .ok_or(TileParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        })?;

    if !rest.is_empty() {
        return Err(TileParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        });
    }

    for (index, lod) in lod_entries.iter().enumerate() {
        let end = lod.start_offset.saturating_add(lod.count);
        if end > header.star_count {
            return Err(TileParseError::LodRange {
                index,
                start: lod.start_offset,
                count: lod.count,
                star_count: header.star_count,
            });
        }
    }

    if stars.len() != star_count {
        return Err(TileParseError::StarCountMismatch {
            declared: header.star_count,
            actual: stars.len(),
        });
    }

    Ok(ParsedTile {
        header,
        lod_entries,
        stars,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn struct_sizes_match_spec() {
        assert_eq!(core::mem::size_of::<TileHeader>(), TILE_HEADER_LEN);
        assert_eq!(core::mem::size_of::<LodEntry>(), LOD_ENTRY_LEN);
        assert_eq!(core::mem::size_of::<StarRecord>(), 28);
    }
}
