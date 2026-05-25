//! HEALPix star-catalog tiles (mmap-friendly binary layout).
//!
//! On-disk layout: [`TileHeader`] + [`LodEntry`] index + [`StarRecord`] blob.
//! See `docs/plans/2026-05-25-planetarium-v2-design.md` §6.2.

pub mod constellation_lines;
pub mod healpix;
mod tile;

pub use constellation_lines::{
    find_by_abbreviation, icrs_dir_from_j2000, line_vertex_count, ConstellationLines,
    ConstellationSegment, CONSTELLATION_COUNT, CONSTELLATIONS, LINE_SEGMENT_COUNT,
    LINE_VERTEX_COUNT,
};
pub use healpix::{
    bounding_pixels_for_fov, depth_for_nside, fov_cap_radius_rad, pixel_for_direction,
    pixels_in_cone, HealpixError,
};
pub use tile::{
    LodEntry, ParsedTile, StarRecord, TileHeader, TileParseError, TILE_HEADER_LEN, TILE_MAGIC,
    encode_tile, parse_tile, tile_byte_len,
};
