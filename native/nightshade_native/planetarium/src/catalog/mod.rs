//! HEALPix star-catalog tiles (mmap-friendly binary layout).
//!
//! On-disk layout: [`TileHeader`] + [`LodEntry`] index + [`StarRecord`] blob.
//! See `docs/plans/2026-05-25-planetarium-v2-design.md` §6.2.

pub mod healpix;
mod tile;

pub use healpix::{
    bounding_pixels_for_fov, depth_for_nside, fov_cap_radius_rad, pixel_for_direction,
    pixels_in_cone, HealpixError,
};
pub use tile::{
    LodEntry, ParsedTile, StarRecord, TileHeader, TileParseError, TILE_HEADER_LEN, TILE_MAGIC,
    encode_tile, parse_tile, tile_byte_len,
};
