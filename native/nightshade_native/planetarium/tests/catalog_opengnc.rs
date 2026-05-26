//! OpenNGC CSV → mmap DSO catalog: fixture build + golden counts.

use std::fs;
use std::path::PathBuf;

use nightshade_planetarium::catalog::{
    build_opengnc_catalog, default_opengnc_csv_path, dso_type, find_repo_root, parse_catalog,
    MappedDsoCatalog, DSO_FLAG_HAS_MAG, DSO_FLAG_MESSIER, OPENNGC_CATALOG_ID, OPENNGC_PACK_VERSION,
    OPENNGC_V1_EXPECTED_RECORDS,
};

fn repo_root() -> PathBuf {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    find_repo_root(&manifest).expect("repository root from planetarium crate dir")
}

#[test]
fn fixture_build_writes_single_record_m31() {
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/ngc_mini.csv");
    let out = std::env::temp_dir().join("nightshade_opengnc_fixture.bin");
    if out.exists() {
        fs::remove_file(&out).expect("clean temp out");
    }

    let result = build_opengnc_catalog(&fixture, &out).expect("build fixture catalog");
    assert_eq!(result.stats.records_written, 1);

    let mapped = MappedDsoCatalog::open(&out).expect("mmap");
    let parsed = mapped.parsed().expect("parse");
    assert_eq!(parsed.header.catalog_id, OPENNGC_CATALOG_ID);
    assert_eq!(parsed.header.pack_version, OPENNGC_PACK_VERSION);
    assert_eq!(parsed.records.len(), 1);

    let dso = &parsed.records[0];
    assert_eq!(dso.ngc_id, 224);
    assert_eq!(dso.messier_num, 31);
    assert_eq!(dso.type_id, dso_type::GALAXY);
    assert_eq!(dso.flags, DSO_FLAG_HAS_MAG | DSO_FLAG_MESSIER);
    assert!((dso.surface_mag - 3.44).abs() < 0.01);

    let bytes = fs::read(&out).expect("read bin");
    let parsed2 = parse_catalog(&bytes).expect("parse bytes");
    assert_eq!(parsed2.records[0].ngc_id, 224);

    let _ = fs::remove_file(&out);
}

#[test]
fn opengnc_v1_golden_record_count() {
    let csv = default_opengnc_csv_path(repo_root());
    if !csv.is_file() {
        eprintln!(
            "skip opengnc_v1_golden_record_count: missing {}",
            csv.display()
        );
        return;
    }

    let out = std::env::temp_dir().join("nightshade_opengnc_v1_golden.bin");
    if out.exists() {
        fs::remove_file(&out).expect("clean temp out");
    }

    let result = build_opengnc_catalog(&csv, &out).expect("build opengnc v1");
    assert_eq!(
        result.stats.records_written, OPENNGC_V1_EXPECTED_RECORDS,
        "record count mismatch for NGC.csv at mag <= 20"
    );

    let _ = fs::remove_file(&out);
}
