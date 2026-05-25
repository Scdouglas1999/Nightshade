//! Pack load: manifest + HEALPix tiles → [`StarPack`] and handle registration.

use std::fs;
use std::path::PathBuf;

use nightshade_planetarium::catalog::{
    build_hyg_tiles, load_and_verify_pack, open_star_tile_pack, sha256_hex, CatalogSet,
    PACK_MANIFEST_NAME,
};
use nightshade_planetarium::{Planetarium, PlanetariumError};

fn write_pack_manifest(pack_dir: &std::path::Path, pack_id: &str) {
    let mut entries = Vec::new();
    for entry in fs::read_dir(pack_dir.join("tiles")).expect("tiles dir") {
        let entry = entry.expect("tile entry");
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("bin") {
            continue;
        }
        let rel = format!(
            "tiles/{}",
            path.file_name().expect("tile name").to_string_lossy()
        );
        let digest = sha256_hex(&fs::read(&path).expect("read tile"));
        entries.push(format!(r#""{rel}": "{digest}""#));
    }
    entries.sort();
    let files = entries.join(",\n    ");
    let manifest = format!(
        r#"{{
  "id": "{pack_id}",
  "name": "HYG fixture",
  "version": "1",
  "depends_on": [],
  "files": {{
    {files}
  }}
}}"#
    );
    fs::write(pack_dir.join(PACK_MANIFEST_NAME), manifest).expect("write pack.json");
}

#[test]
fn open_star_tile_pack_loads_hyg_fixture() {
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/hyg_mini.csv");
    let pack_dir = std::env::temp_dir().join("nightshade_load_pack_fixture");
    if pack_dir.exists() {
        fs::remove_dir_all(&pack_dir).expect("clean");
    }
    build_hyg_tiles(&fixture, &pack_dir).expect("build tiles");
    write_pack_manifest(&pack_dir, "stars-hyg-fixture");

    load_and_verify_pack(&pack_dir).expect("verify");
    let pack = open_star_tile_pack(&pack_dir).expect("open");
    assert_eq!(pack.pack_id(), "stars-hyg-fixture");
    assert_eq!(pack.nside(), 8);

    let mut set = CatalogSet::new();
    set.register(pack);
    assert_eq!(
        set.active_pack_ids().collect::<Vec<_>>(),
        ["stars-hyg-fixture"]
    );

    let _ = fs::remove_dir_all(&pack_dir);
}

#[test]
fn planetarium_load_pack_registers_catalog_for_hit_test() {
    use nightshade_planetarium::types::{SkyProjection, ViewPose};

    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/hyg_mini.csv");
    let pack_dir = std::env::temp_dir().join("nightshade_handle_load_pack");
    if pack_dir.exists() {
        fs::remove_dir_all(&pack_dir).expect("clean");
    }
    build_hyg_tiles(&fixture, &pack_dir).expect("build tiles");
    write_pack_manifest(&pack_dir, "stars-hyg-fixture");

    let planetarium = Planetarium::new(0).expect("create");
    planetarium.load_pack(&pack_dir).expect("load_pack");

    let target_pose = ViewPose {
        ra_rad: 0.662_062,
        dec_rad: 1.557_896,
        fov_rad: 1.5, // wider FOV so the hit-test pick cone is generous
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    planetarium
        .send(nightshade_planetarium::bus::PlanetariumCommand::SetPose(
            target_pose,
        ))
        .expect("set_pose");

    // Wait for the render thread to process SetPose so live_pose (the source
    // hit_test reads from) reflects the new pose; otherwise this races against
    // render-thread scheduling and is flaky.
    let deadline = std::time::Instant::now() + std::time::Duration::from_millis(500);
    while (planetarium.live_pose().ra_rad - target_pose.ra_rad).abs() > 1e-9 {
        if std::time::Instant::now() >= deadline {
            panic!("live_pose did not catch up to target SetPose");
        }
        std::thread::sleep(std::time::Duration::from_millis(2));
    }

    let selected = planetarium
        .hit_test(0.5, 0.5)
        .expect("hit_test")
        .expect("polaris");
    assert_eq!(selected.object_id, 11767);

    let err = planetarium
        .load_pack(PathBuf::from("/nonexistent/nightshade-pack").as_path())
        .expect_err("missing pack");
    assert!(matches!(err, PlanetariumError::CatalogPack(_)));

    let _ = fs::remove_dir_all(&pack_dir);
}
