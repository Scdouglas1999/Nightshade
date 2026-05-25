//! HYG → HEALPix tile converter: fixture build + golden counts for hyg_v42.

use std::fs;
use std::path::PathBuf;

use nightshade_planetarium::catalog::{
    build_hyg_tiles, default_hyg_csv_path, find_repo_root, parse_tile, HYG_NSIDE,
    HYG_V42_EXPECTED_STARS, HYG_V42_EXPECTED_TILES,
};

fn repo_root() -> PathBuf {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    find_repo_root(&manifest).expect("repository root from planetarium crate dir")
}

#[test]
fn fixture_build_writes_one_tile_with_one_star() {
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/hyg_mini.csv");
    let out = std::env::temp_dir().join("nightshade_hyg_fixture_tiles");
    if out.exists() {
        fs::remove_dir_all(&out).expect("clean temp out");
    }

    let result = build_hyg_tiles(&fixture, &out).expect("build fixture tiles");
    assert_eq!(result.stats.tiles_written, 1);
    assert_eq!(result.stats.stars_written, 1);

    let tiles_dir = out.join("tiles");
    let entries: Vec<_> = fs::read_dir(&tiles_dir)
        .expect("read tiles dir")
        .filter_map(Result::ok)
        .collect();
    assert_eq!(entries.len(), 1);

    let bytes = fs::read(entries[0].path()).expect("read tile");
    let parsed = parse_tile(&bytes).expect("parse tile");
    assert_eq!(parsed.header.nside, HYG_NSIDE);
    assert_eq!(parsed.header.star_count, 1);
    assert_eq!(parsed.stars[0].hip_id, 11767);

    let _ = fs::remove_dir_all(&out);
}

#[test]
fn hyg_v42_golden_tile_and_star_counts() {
    let csv = default_hyg_csv_path(repo_root());
    if !csv.is_file() {
        eprintln!("skip hyg_v42_golden_tile_and_star_counts: missing {}", csv.display());
        return;
    }

    let out = std::env::temp_dir().join("nightshade_hyg_v42_golden");
    if out.exists() {
        fs::remove_dir_all(&out).expect("clean temp out");
    }

    let result = build_hyg_tiles(&csv, &out).expect("build hyg_v42 tiles");
    assert_eq!(
        result.stats.tiles_written,
        HYG_V42_EXPECTED_TILES,
        "tile count mismatch for hyg_v42 at nside=8"
    );
    assert_eq!(
        result.stats.stars_written,
        HYG_V42_EXPECTED_STARS,
        "star count mismatch for hyg_v42 (mag <= 15)"
    );

    let _ = fs::remove_dir_all(&out);
}
