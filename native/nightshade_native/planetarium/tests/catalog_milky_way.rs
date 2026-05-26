//! Milky Way intensity raster: procedural build, parse, and GPU upload.

use std::fs;
use std::path::PathBuf;

use nightshade_planetarium::catalog::{
    build_milky_way_asset, build_milky_way_map, default_mw_asset_path, encode_milky_way_map,
    equatorial_to_galactic_deg, find_repo_root, galactic_intensity, galactic_to_equatorial_deg,
    load_milky_way_map, parse_milky_way_map, MilkyWayError, MILKY_WAY_FILE_LEN, MILKY_WAY_HEIGHT,
    MILKY_WAY_WIDTH,
};
use nightshade_planetarium::renderer::assets::{
    load_mw_texture_from_bytes, upload_procedural_mw_texture,
};

fn repo_root() -> PathBuf {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    find_repo_root(&manifest).expect("repository root from planetarium crate dir")
}

#[test]
fn procedural_map_dimensions_and_file_len() {
    let map = build_milky_way_map();
    assert_eq!(map.header.width, MILKY_WAY_WIDTH);
    assert_eq!(map.header.height, MILKY_WAY_HEIGHT);
    assert_eq!(
        map.pixels.len(),
        (MILKY_WAY_WIDTH as usize) * (MILKY_WAY_HEIGHT as usize)
    );

    let bytes = encode_milky_way_map(&map);
    assert_eq!(bytes.len(), MILKY_WAY_FILE_LEN);
    let parsed = parse_milky_way_map(&bytes).expect("roundtrip parse");
    assert_eq!(parsed, map);
}

#[test]
fn galactic_center_is_bright_galactic_pole_is_dark() {
    let map = build_milky_way_map();
    let center = map.intensity_at_equatorial_deg(266.4168, -29.0078);
    assert!(center > 0.5, "galactic center {center}");

    let (ra, dec) = galactic_to_equatorial_deg(0.0, 90.0);
    let pole = map.intensity_at_equatorial_deg(ra, dec);
    assert!(pole < 0.05, "galactic north pole {pole}");
}

#[test]
fn galactic_equatorial_roundtrip_at_plane_center() {
    let (ra, dec) = galactic_to_equatorial_deg(0.0, 0.0);
    let (l, b) = equatorial_to_galactic_deg(ra, dec);
    assert!(
        l.rem_euclid(360.0) < 2.0 || l.rem_euclid(360.0) > 358.0,
        "galactic longitude roundtrip, got {l}"
    );
    assert!(b.abs() < 2.0, "galactic latitude roundtrip, got {b}");
    assert!(galactic_intensity(l, b) > 0.5);

    let (l_sgr, b_sgr) = equatorial_to_galactic_deg(266.4168, -29.0078);
    assert!(
        galactic_intensity(l_sgr, b_sgr) > 0.5,
        "Sagittarius A* region is bright"
    );
}

#[test]
fn corrupted_magic_fails_loudly() {
    let mut bytes = encode_milky_way_map(&build_milky_way_map());
    bytes[0] = b'X';
    let err = parse_milky_way_map(&bytes).expect_err("bad magic");
    assert!(matches!(err, MilkyWayError::BadMagic));
}

#[test]
fn truncated_blob_fails_loudly() {
    let bytes = encode_milky_way_map(&build_milky_way_map());
    let err = parse_milky_way_map(&bytes[..32]).expect_err("truncated");
    assert!(matches!(err, MilkyWayError::TruncatedHeader { .. }));
}

#[test]
fn build_asset_writes_expected_size() {
    let out = std::env::temp_dir().join("nightshade_mw_intensity_v1.bin");
    if out.exists() {
        fs::remove_file(&out).expect("clean temp");
    }

    let result = build_milky_way_asset(&out).expect("build asset");
    assert_eq!(result.byte_len, MILKY_WAY_FILE_LEN);
    assert!(result.nonzero_pixels > 100_000);

    let loaded = load_milky_way_map(&out).expect("load written asset");
    assert_eq!(loaded.header.width, MILKY_WAY_WIDTH);

    let _ = fs::remove_file(&out);
}

#[test]
fn gpu_upload_from_bytes() {
    let bytes = encode_milky_way_map(&build_milky_way_map());
    let (device, queue) = pollster::block_on(nightshade_planetarium::renderer::offscreen_device());
    let tex = load_mw_texture_from_bytes(&device, &queue, &bytes).expect("gpu upload");
    assert_eq!(tex.width(), MILKY_WAY_WIDTH);
    assert_eq!(tex.height(), MILKY_WAY_HEIGHT);
}

#[test]
fn bundled_asset_load_when_present() {
    let path = default_mw_asset_path(repo_root());
    if !path.is_file() {
        eprintln!(
            "skip bundled_asset_load_when_present: run `cargo run -p nightshade_planetarium --bin build_milky_way` first"
        );
        return;
    }

    let map = load_milky_way_map(&path).expect("load bundled asset");
    assert_eq!(map.byte_len(), MILKY_WAY_FILE_LEN);

    let (device, queue) = pollster::block_on(nightshade_planetarium::renderer::offscreen_device());
    let _tex = upload_procedural_mw_texture(&device, &queue).expect("upload");
}
