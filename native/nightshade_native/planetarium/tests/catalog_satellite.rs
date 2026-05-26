//! Satellite TLE pack: text parse, binary round-trip, SGP4 via catalog loader.

use glam::DVec3;
use nightshade_planetarium::astrometry::sgp4_prop::{
    position_error_km, VERIFICATION_POSITION_TOLERANCE_KM,
};
use nightshade_planetarium::catalog::{
    encode_catalog_from_text, encode_satellite_tle_catalog, parse_satellite_tle_catalog,
    parse_tle_text, MappedSatelliteTleCatalog, SatelliteTleCatalog, SATELLITE_TLE_CATALOG_ID,
};

const VANGUARD_NAME: &str = "VANGUARD 1";
const VANGUARD_LINE1: &str =
    "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753";
const VANGUARD_LINE2: &str =
    "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667";

fn vanguard_tle_text() -> String {
    format!("{VANGUARD_NAME}\n{VANGUARD_LINE1}\n{VANGUARD_LINE2}\n")
}

#[test]
fn tle_text_yields_vanguard_entry() {
    let entries = parse_tle_text(&vanguard_tle_text()).expect("parse");
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].name, VANGUARD_NAME);
    assert_eq!(entries[0].norad_id, 5);
}

#[test]
fn catalog_loader_propagates_canonical_state() {
    let catalog = SatelliteTleCatalog::from_tle_text(&vanguard_tle_text()).expect("load");
    assert_eq!(catalog.len(), 1);
    let state = catalog.propagate(0, 0.0).expect("epoch");
    let expected = DVec3::from_array([7022.46529266, -1400.08296755, 0.03995155]);
    let err = position_error_km(state.position_km, expected);
    assert!(err < VERIFICATION_POSITION_TOLERANCE_KM, "error {err} km");
}

#[test]
fn binary_pack_round_trip_and_mmap() {
    let bytes = encode_catalog_from_text(&vanguard_tle_text()).expect("encode");
    let parsed = parse_satellite_tle_catalog(&bytes).expect("parse");
    assert_eq!(parsed.header.catalog_id, SATELLITE_TLE_CATALOG_ID);
    assert_eq!(parsed.records.len(), 1);

    let loaded = SatelliteTleCatalog::from_bytes(&bytes).expect("loader");
    let state = loaded.propagate(0, 720.0).expect("t+720");
    assert!(state.position_km.length() > 6_000.0);

    let path = std::env::temp_dir().join("nightshade_tle_fixture.bin");
    std::fs::write(&path, &bytes).expect("write");
    let mapped = MappedSatelliteTleCatalog::open(&path).expect("mmap");
    assert_eq!(mapped.parsed().expect("view").records.len(), 1);
    let _ = std::fs::remove_file(path);

    let catalog2 = SatelliteTleCatalog::from_bytes(&bytes).expect("from bytes");
    let bytes2 = encode_satellite_tle_catalog(catalog2.records());
    assert_eq!(bytes.len(), bytes2.len());
}
