//! HEALPix star-catalog tiles (mmap-friendly binary layout).
//!
//! On-disk layout: [`TileHeader`] + [`LodEntry`] index + [`StarRecord`] blob.
//! See `docs/plans/2026-05-25-planetarium-v2-design.md` §6.2.

pub mod constellation_lines;
pub mod healpix;
pub mod hit_index;
pub mod hyg_build;
mod pack;
mod set;
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
pub use hit_index::{HitIndex, HitPick};
pub use pack::{
    load_and_verify_pack, sha256_hex, PackError, PackManifest, PACK_MANIFEST_NAME,
};
pub use set::{CatalogHit, CatalogSet, StarPack};
pub use hyg_build::{
    build_hyg_tiles, build_lod_entries, default_hyg_csv_path, default_output_dir, find_repo_root,
    hyg_row_to_star, HygBuildError, HygBuildResult, HygBuildStats, HYG_CATALOG_ID, HYG_CSV_REL_PATH,
    HYG_FLAG_VARIABLE, HYG_LOD_MAG_THRESHOLDS, HYG_MAG_LIMIT, HYG_NSIDE, HYG_OUTPUT_REL_DIR,
    HYG_PACK_VERSION, HYG_V42_EXPECTED_STARS, HYG_V42_EXPECTED_TILES,
};
pub use tile::{
    encode_tile, parse_tile, tile_byte_len, LodEntry, ParsedTile, StarRecord, TileHeader,
    TileParseError, TILE_HEADER_LEN, TILE_MAGIC,
};
