//! Minor-body catalog: MPCORB parse, binary round-trip, Kepler propagation.

use nightshade_planetarium::astrometry::kepler::{geocentric_equatorial_j2000, OrbitalElements};
use nightshade_planetarium::catalog::{
    encode_minor_body_catalog, minor_body_catalog_byte_len, parse_minor_body_catalog,
    parse_mpc_orbit_line, parse_mpcorb_dat, unpack_packed_epoch, MappedMinorBodyCatalog,
    MinorBodyKind, MPC_CATALOG_ID, MPC_PACK_VERSION,
};

/// Write `value` into 1-based inclusive MPC columns `[start_col, end_col]`.
fn write_mpc_field(buf: &mut [u8], start_col: usize, end_col: usize, value: &str) {
    let start = start_col - 1;
    let width = end_col - start_col + 1;
    let bytes = value.as_bytes();
    let len = bytes.len().min(width);
    let offset = start + width.saturating_sub(len);
    buf[offset..offset + len].copy_from_slice(&bytes[bytes.len() - len..]);
}

/// Column-aligned MPC export line for 1 Ceres (epoch K2411.0 = JD 2460310.5).
fn ceres_mpc_line() -> String {
    let mut buf = vec![b' '; 103];
    write_mpc_field(&mut buf, 1, 7, "    1");
    write_mpc_field(&mut buf, 9, 13, " 3.34");
    write_mpc_field(&mut buf, 15, 19, " 0.12");
    write_mpc_field(&mut buf, 21, 25, "K2411");
    write_mpc_field(&mut buf, 27, 35, "60.07000");
    write_mpc_field(&mut buf, 38, 46, " 73.59700");
    write_mpc_field(&mut buf, 49, 57, " 80.39400");
    write_mpc_field(&mut buf, 60, 68, " 10.59400");
    write_mpc_field(&mut buf, 71, 79, " 0.0760000");
    write_mpc_field(&mut buf, 81, 91, "  0.21458947");
    write_mpc_field(&mut buf, 93, 103, "  2.7670000");
    String::from_utf8(buf).expect("ascii line")
}

#[test]
fn packed_epoch_matches_v1_ceres_epoch() {
    let jd = unpack_packed_epoch("K2411.0").expect("epoch");
    assert!((jd - 2_460_310.5).abs() < 1e-6);
}

#[test]
fn mpcorb_dat_parses_ceres_fixture() {
    let line = ceres_mpc_line();
    assert_eq!(line.len(), 103, "MPC export line must be 103 columns");
    let mut text = String::from("# MPCORB sample\n");
    text.push_str(&line);
    text.push('\n');
    let parsed: Vec<_> = parse_mpcorb_dat(&text)
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .expect("all lines ok");
    assert_eq!(parsed.len(), 1);
    assert_eq!(parsed[0].kind, MinorBodyKind::Asteroid);
    assert!((parsed[0].elements.semi_major_axis_au - 2.767).abs() < 1e-3);
}

#[test]
fn binary_catalog_round_trip_and_mmap() {
    let entry = parse_mpc_orbit_line(&ceres_mpc_line()).expect("line");
    let string_len = entry.designation.len();
    let bytes = encode_minor_body_catalog(&[entry]);
    assert_eq!(bytes.len(), minor_body_catalog_byte_len(1, string_len));

    let parsed = parse_minor_body_catalog(&bytes).expect("parse");
    assert_eq!(parsed.header.catalog_id, MPC_CATALOG_ID);
    assert_eq!(parsed.header.pack_version, MPC_PACK_VERSION);
    assert_eq!(parsed.records.len(), 1);
    assert_eq!(parsed.designation(&parsed.records[0]).unwrap(), "1");

    let path = std::env::temp_dir().join("nightshade_mpc_fixture.bin");
    std::fs::write(&path, &bytes).expect("write");
    let mapped = MappedMinorBodyCatalog::open(&path).expect("mmap");
    let view = mapped.parsed().expect("view");
    assert_eq!(view.records.len(), 1);
    let _ = std::fs::remove_file(path);
}

#[test]
fn ceres_geocentric_matches_kepler_reference() {
    let entry = parse_mpc_orbit_line(&ceres_mpc_line()).unwrap();
    let bytes = encode_minor_body_catalog(&[entry]);
    let parsed = parse_minor_body_catalog(&bytes).unwrap();
    let geo = parsed.records[0].geocentric_at(2_460_310.5);
    let expected = geocentric_equatorial_j2000(
        &OrbitalElements {
            epoch_jd: 2_460_310.5,
            semi_major_axis_au: 2.7670,
            eccentricity: 0.0760,
            inclination_deg: 10.594,
            longitude_ascending_node_deg: 80.394,
            argument_perihelion_deg: 73.597,
            mean_anomaly_deg: 60.070,
        },
        2_460_310.5,
    );
    assert!((geo.ra_hours - expected.ra_hours).abs() < 1e-4);
    assert!((geo.dec_deg - expected.dec_deg).abs() < 1e-3);
}
