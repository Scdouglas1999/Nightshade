//! HEALPix star-catalog tiles (mmap-friendly binary layout).
//!
//! On-disk layout: [`TileHeader`] + [`LodEntry`] index + [`StarRecord`] blob.
//! OpenNGC DSOs use a single mmap catalog ([`dso::DsoCatalogHeader`] + [`dso::DsoRecord`]).
//! See `docs/plans/2026-05-25-planetarium-v2-design.md` §6.2.

pub mod constellation_lines;
pub mod dso;
pub mod minor_body;
pub mod satellite;
pub mod variable_stars;
pub mod healpix;
pub mod hit_index;
pub mod hyg_build;
pub mod opengnc_build;
mod pack;
mod residency;
mod set;
pub mod tile;

pub use constellation_lines::{
    find_by_abbreviation, icrs_dir_from_j2000, line_vertex_count, ConstellationLines,
    ConstellationSegment, CONSTELLATION_COUNT, CONSTELLATIONS, LINE_SEGMENT_COUNT,
    LINE_VERTEX_COUNT,
};
pub use variable_stars::{
    brighter_than, by_constellation, by_kind, estimate_magnitude, find_by_name, icrs_dir,
    julian_date_from_utc, mag_range, search as search_variable_stars, stars as variable_stars,
    VariableStar, VariableStarKind, STAR_COUNT as VARIABLE_STAR_COUNT,
};
pub use healpix::{
    bounding_pixels_for_fov, depth_for_nside, fov_cap_radius_rad, pixel_for_direction,
    pixels_in_cone, HealpixError,
};
pub use hit_index::{HitIndex, HitPick};
pub use residency::{HealpixId, ResidentTile, ResidencySync, TileResidency};
pub use pack::{
    load_and_verify_pack, sha256_hex, PackError, PackManifest, PACK_MANIFEST_NAME,
};
pub use set::{CatalogHit, CatalogSet, StarPack};
pub use minor_body::{
    catalog_byte_len as minor_body_catalog_byte_len, encode_catalog as encode_minor_body_catalog,
    parse_catalog as parse_minor_body_catalog, parse_mpc_orbit_line, parse_mpcorb_dat,
    unpack_packed_epoch, MappedMinorBodyCatalog, MinorBodyCatalogHeader, MinorBodyKind,
    MinorBodyParseError, MinorBodyRecord, MpcOrbitEntry, MpcParseError, ParsedMinorBodyCatalog,
    MINOR_BODY_CATALOG_MAGIC, MINOR_BODY_FLAG_HAS_NAME, MINOR_BODY_HEADER_LEN,
    MINOR_BODY_RECORD_LEN, MPC_CATALOG_ID, MPC_ORBIT_LINE_MIN_LEN, MPC_PACK_VERSION,
};
pub use satellite::{
    catalog_byte_len as satellite_tle_catalog_byte_len,
    encode_catalog as encode_satellite_tle_catalog,
    encode_catalog_from_text, parse_catalog as parse_satellite_tle_catalog, parse_tle_text,
    MappedSatelliteTleCatalog, SatelliteTleCatalog, SatelliteTleHeader, SatelliteTleParseError,
    SatelliteTleRecord, TleEntry, TleTextParseError, ParsedSatelliteTleCatalog,
    SATELLITE_TLE_CATALOG_ID, SATELLITE_TLE_CATALOG_MAGIC, SATELLITE_TLE_HEADER_LEN,
    SATELLITE_TLE_PACK_VERSION, SATELLITE_TLE_RECORD_LEN, TLE_LINE_WIDTH,
};
pub use dso::{
    catalog_byte_len, encode_catalog, parse_catalog, type_id_from_opengnc, DsoCatalogHeader,
    DsoParseError, DsoRecord, MappedDsoCatalog, ParsedDsoCatalog, DSO_CATALOG_MAGIC,
    DSO_FLAG_HAS_MAG, DSO_FLAG_MESSIER, DSO_HEADER_LEN, DSO_RECORD_LEN, OPENNGC_CATALOG_ID,
    OPENNGC_PACK_VERSION, dso_type,
};
pub use hyg_build::{
    build_hyg_tiles, build_lod_entries, default_hyg_csv_path, default_output_dir, find_repo_root,
    hyg_row_to_star, HygBuildError, HygBuildResult, HygBuildStats, HYG_CATALOG_ID, HYG_CSV_REL_PATH,
    HYG_FLAG_VARIABLE, HYG_LOD_MAG_THRESHOLDS, HYG_MAG_LIMIT, HYG_NSIDE, HYG_OUTPUT_REL_DIR,
    HYG_PACK_VERSION, HYG_V42_EXPECTED_STARS, HYG_V42_EXPECTED_TILES,
};
pub use opengnc_build::{
    build_opengnc_catalog, default_opengnc_csv_path, default_output_path,
    find_repo_root as find_repo_root_opengnc, opengnc_row_to_record, OpenNgcBuildError,
    OpenNgcBuildResult, OpenNgcBuildStats, OPENNGC_CSV_REL_PATH, OPENNGC_MAG_LIMIT,
    OPENNGC_OUTPUT_REL_PATH, OPENNGC_V1_EXPECTED_RECORDS,
};
pub use tile::{
    encode_tile, parse_tile, tile_byte_len, LodEntry, ParsedTile, StarRecord, TileHeader,
    TileParseError, TILE_HEADER_LEN, TILE_MAGIC,
};
