//! Catalog pack manifest (`pack.json`) load and SHA-256 integrity verification.
//!
//! Each installed pack directory contains a manifest listing every payload file
//! with its expected digest. [`load_and_verify_pack`] fails loudly on missing
//! files, parse errors, or hash mismatches — no silent repair or skip.

use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use sha2::{Digest, Sha256};
use thiserror::Error;

use super::tile::TileParseError;

/// Filename of the pack manifest inside a pack directory.
pub const PACK_MANIFEST_NAME: &str = "pack.json";

/// Errors while loading or verifying a catalog pack.
#[derive(Debug, Error)]
pub enum PackError {
    /// Manifest or payload file I/O failed.
    #[error("{context}: {source}")]
    Io {
        /// Human-readable stage.
        context: &'static str,
        /// Underlying OS error.
        #[source]
        source: std::io::Error,
    },
    /// `pack.json` is not valid JSON for [`PackManifest`].
    #[error("invalid pack manifest JSON: {0}")]
    InvalidJson(#[from] serde_json::Error),
    /// A required manifest field is missing or empty.
    #[error("invalid pack manifest: {0}")]
    InvalidManifest(&'static str),
    /// A `files` entry has a digest that is not 64 lowercase/uppercase hex digits.
    #[error("invalid sha256 for {path}: {digest}")]
    InvalidSha256 {
        /// Manifest-relative path key.
        path: String,
        /// Value from the manifest.
        digest: String,
    },
    /// Manifest lists a file that is not present under the pack directory.
    #[error("pack file missing: {path}")]
    MissingFile {
        /// Manifest-relative path (POSIX separators).
        path: String,
    },
    /// On-disk file digest does not match the manifest.
    #[error("pack integrity check failed for {path}: expected {expected}, got {actual}")]
    HashMismatch {
        /// Manifest-relative path (POSIX separators).
        path: String,
        /// Expected SHA-256 hex from `pack.json`.
        expected: String,
        /// Computed SHA-256 hex.
        actual: String,
    },
    /// Manifest lists no `tiles/*.bin` HEALPix star tiles.
    #[error("pack has no HEALPix star tiles (expected tiles/*.bin in manifest)")]
    NoStarTiles,
    /// A star tile blob failed parse/validation.
    #[error("tile {path}: {source}")]
    InvalidTile {
        /// Manifest-relative path.
        path: String,
        /// Parse error.
        #[source]
        source: TileParseError,
    },
    /// Tile filename healpix id does not match the tile header.
    #[error("tile {path}: filename id {filename_id} != header {header_id}")]
    HealpixIdMismatch {
        /// Manifest-relative path.
        path: String,
        /// Id parsed from `tiles/{id:012x}.bin`.
        filename_id: u64,
        /// [`super::tile::TileHeader::healpix_id`].
        header_id: u64,
    },
    /// Tiles in one pack disagree on HEALPix `nside`.
    #[error("tile {path}: nside {nside} != pack nside {expected}")]
    NsideMismatch {
        /// Manifest-relative path.
        path: String,
        /// `nside` in the offending tile header.
        nside: u32,
        /// `nside` established by the first tile.
        expected: u32,
    },
}

impl PackError {
    fn io(context: &'static str, source: std::io::Error) -> Self {
        Self::Io { context, source }
    }
}

/// On-disk `pack.json` schema (design §6.1).
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct PackManifest {
    /// Stable pack identifier (directory name, e.g. `stars-hyg-v1`).
    pub id: String,
    /// Human-readable title.
    pub name: String,
    /// Pack format / content version string.
    pub version: String,
    /// Other pack ids that must be installed first (may be empty).
    #[serde(default, rename = "depends_on")]
    pub depends_on: Vec<String>,
    /// Manifest-relative paths (POSIX `/`) → lowercase SHA-256 hex digest.
    pub files: HashMap<String, String>,
}

impl PackManifest {
    /// Parse and validate manifest JSON (does not read payload files).
    pub fn from_json(json: &str) -> Result<Self, PackError> {
        let manifest: Self = serde_json::from_str(json)?;
        manifest.validate_schema()?;
        Ok(manifest)
    }

    /// Read `pack.json` from `pack_dir` and validate schema only.
    pub fn load(pack_dir: &Path) -> Result<Self, PackError> {
        let path = pack_dir.join(PACK_MANIFEST_NAME);
        let json =
            std::fs::read_to_string(&path).map_err(|e| PackError::io("read pack manifest", e))?;
        Self::from_json(&json)
    }

    /// Verify every listed file exists under `pack_dir` and matches its SHA-256.
    pub fn verify_integrity(&self, pack_dir: &Path) -> Result<(), PackError> {
        let mut mismatches = Vec::new();
        let mut missing = Vec::new();

        for (rel, expected_hex) in &self.files {
            let path = pack_dir.join(from_posix(rel));
            if !path.is_file() {
                missing.push(rel.clone());
                continue;
            }
            let actual = sha256_file(&path)?;
            if !actual.eq_ignore_ascii_case(expected_hex) {
                mismatches.push(PackError::HashMismatch {
                    path: rel.clone(),
                    expected: expected_hex.clone(),
                    actual,
                });
            }
        }

        if !missing.is_empty() {
            // Fail on the first missing file with a dedicated variant.
            let path = missing.into_iter().min().expect("non-empty missing");
            return Err(PackError::MissingFile { path });
        }

        if let Some(err) = mismatches.into_iter().next() {
            return Err(err);
        }

        Ok(())
    }
}

/// Load `pack.json` from `pack_dir` and verify all listed files (fail loud).
pub fn load_and_verify_pack(pack_dir: &Path) -> Result<PackManifest, PackError> {
    let manifest = PackManifest::load(pack_dir)?;
    manifest.verify_integrity(pack_dir)?;
    Ok(manifest)
}

impl PackManifest {
    fn validate_schema(&self) -> Result<(), PackError> {
        if self.id.trim().is_empty() {
            return Err(PackError::InvalidManifest("id must be non-empty"));
        }
        if self.name.trim().is_empty() {
            return Err(PackError::InvalidManifest("name must be non-empty"));
        }
        if self.version.trim().is_empty() {
            return Err(PackError::InvalidManifest("version must be non-empty"));
        }
        if self.files.is_empty() {
            return Err(PackError::InvalidManifest(
                "files must list at least one entry",
            ));
        }
        for (rel, digest) in &self.files {
            if rel.trim().is_empty() {
                return Err(PackError::InvalidManifest("files key must be non-empty"));
            }
            if rel.contains('\\') {
                return Err(PackError::InvalidManifest(
                    "files keys must use POSIX forward slashes",
                ));
            }
            if !is_valid_sha256_hex(digest) {
                return Err(PackError::InvalidSha256 {
                    path: rel.clone(),
                    digest: digest.clone(),
                });
            }
        }
        Ok(())
    }
}

fn is_valid_sha256_hex(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit())
}

fn sha256_file(path: &Path) -> Result<String, PackError> {
    let mut file = File::open(path).map_err(|e| PackError::io("open file for sha256", e))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file
            .read(&mut buf)
            .map_err(|e| PackError::io("read file for sha256", e))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex_encode(&hasher.finalize()))
}

/// SHA-256 hex digest of bytes (tests and manifest generation).
#[must_use]
pub fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex_encode(&hasher.finalize())
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push(nibble((b >> 4) & 0xF));
        s.push(nibble(b & 0xF));
    }
    s
}

fn nibble(n: u8) -> char {
    match n {
        0..=9 => (b'0' + n) as char,
        10..=15 => (b'a' + n - 10) as char,
        _ => unreachable!(),
    }
}

fn from_posix(s: &str) -> PathBuf {
    PathBuf::from(s.replace('/', std::path::MAIN_SEPARATOR_STR))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_invalid_sha256_in_manifest() {
        let json = r#"{
            "id": "x",
            "name": "X",
            "version": "1",
            "files": { "a.bin": "not-a-hash" }
        }"#;
        let err = PackManifest::from_json(json).expect_err("bad digest");
        assert!(matches!(err, PackError::InvalidSha256 { .. }));
    }
}
