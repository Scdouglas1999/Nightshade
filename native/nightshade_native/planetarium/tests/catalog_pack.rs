//! Pack manifest load + SHA-256 integrity verification.

use std::fs;
use std::io::Write;
use std::path::Path;

use nightshade_planetarium::catalog::{
    load_and_verify_pack, sha256_hex, PackError, PackManifest, PACK_MANIFEST_NAME,
};

fn write_fixture_pack(dir: &Path, payload: &[u8], corrupt_digest: bool) -> String {
    fs::create_dir_all(dir.join("data")).expect("fixture data dir");
    let payload_path = dir.join("data").join("hello.bin");
    fs::write(&payload_path, payload).expect("write payload");

    let good_digest = sha256_hex(payload);
    let digest = if corrupt_digest {
        "0000000000000000000000000000000000000000000000000000000000000000".to_string()
    } else {
        good_digest
    };

    let manifest = format!(
        r#"{{
  "id": "test-pack-v1",
  "name": "Test Pack",
  "version": "1",
  "depends_on": [],
  "files": {{
    "data/hello.bin": "{digest}"
  }}
}}"#
    );
    fs::write(dir.join(PACK_MANIFEST_NAME), manifest).expect("write pack.json");
    digest
}

#[test]
fn load_and_verify_valid_pack() {
    let dir = std::env::temp_dir().join("nightshade_planarium_pack_ok");
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");

    let payload = b"nightshade catalog pack fixture";
    write_fixture_pack(&dir, payload, false);

    let manifest = load_and_verify_pack(&dir).expect("valid pack loads");
    assert_eq!(manifest.id, "test-pack-v1");
    assert_eq!(manifest.name, "Test Pack");
    assert_eq!(manifest.version, "1");
    assert_eq!(manifest.files.len(), 1);

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn corrupted_file_fails_integrity_check() {
    let dir = std::env::temp_dir().join("nightshade_planarium_pack_bad_hash");
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");

    write_fixture_pack(&dir, b"original bytes", true);

    let err = load_and_verify_pack(&dir).expect_err("corrupt digest must fail");
    match err {
        PackError::HashMismatch { path, expected, actual } => {
            assert_eq!(path, "data/hello.bin");
            assert_eq!(
                expected,
                "0000000000000000000000000000000000000000000000000000000000000000"
            );
            assert_eq!(actual, sha256_hex(b"original bytes"));
        }
        other => panic!("expected HashMismatch, got {other:?}"),
    }

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn missing_listed_file_fails_loudly() {
    let dir = std::env::temp_dir().join("nightshade_planarium_pack_missing");
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");

    let digest = sha256_hex(b"ghost");
    let manifest = format!(
        r#"{{
  "id": "test-pack-v1",
  "name": "Test Pack",
  "version": "1",
  "files": {{ "missing.bin": "{digest}" }}
}}"#
    );
    fs::write(dir.join(PACK_MANIFEST_NAME), manifest).expect("manifest only");

    let manifest = PackManifest::load(&dir).expect("parse manifest");
    let err = manifest.verify_integrity(&dir).expect_err("missing file");
    assert!(matches!(err, PackError::MissingFile { path } if path == "missing.bin"));

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn invalid_json_fails_parse() {
    let dir = std::env::temp_dir().join("nightshade_planarium_pack_bad_json");
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");

    let mut f = fs::File::create(dir.join(PACK_MANIFEST_NAME)).expect("create");
    f.write_all(b"{ not json").expect("write");

    let err = PackManifest::load(&dir).expect_err("bad json");
    assert!(matches!(err, PackError::InvalidJson(_)));

    let _ = fs::remove_dir_all(&dir);
}
