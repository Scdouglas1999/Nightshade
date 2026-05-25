//! HEALPix star-catalog tiles (mmap-friendly binary layout).
//!
//! On-disk layout: [`TileHeader`] + [`LodEntry`] index + [`StarRecord`] blob.
//! See `docs/plans/2026-05-25-planetarium-v2-design.md` §6.2.

mod tile;

pub use tile::{
    LodEntry, ParsedTile, StarRecord, TileHeader, TileParseError, TILE_HEADER_LEN, TILE_MAGIC,
    encode_tile, parse_tile, tile_byte_len,
};
