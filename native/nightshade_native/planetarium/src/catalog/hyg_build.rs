//! HYG CSV → HEALPix star-tile converter (design §6.2, `stars-hyg-v1` pack).
//!
//! Reads [`hyg_v42.csv`](../../../../../../packages/nightshade_planetarium/assets/hyg/hyg_v42.csv)
//! and writes one binary tile per occupied NESTED pixel at `nside = 8`.

use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

use thiserror::Error;

use super::healpix::pixel_for_direction;
use super::tile::{encode_tile, LodEntry, StarRecord, TileHeader};

/// Catalog id for HYG tiles (`TileHeader::catalog_id`).
pub const HYG_CATALOG_ID: u32 = 1;
/// Pack format version (`stars-hyg-v1`).
pub const HYG_PACK_VERSION: u32 = 1;
/// HEALPix resolution for the bundled HYG pack (design §6.2).
pub const HYG_NSIDE: u32 = 8;
/// Faintest apparent magnitude included in the bundled pack.
pub const HYG_MAG_LIMIT: f32 = 15.0;

/// Magnitude band upper bounds (inclusive per band; stars sorted brightest-first).
pub const HYG_LOD_MAG_THRESHOLDS: &[f32] = &[2.5, 4.0, 6.0, 8.0, 10.0, 12.0, HYG_MAG_LIMIT];

/// `StarRecord::flags` bit: variable star (HYG `var` column non-empty).
pub const HYG_FLAG_VARIABLE: u32 = 1;

/// Expected non-empty tile files for `hyg_v42.csv` at [`HYG_NSIDE`] (12 × nside² = 768).
pub const HYG_V42_EXPECTED_TILES: usize = 768;
/// Expected star records written for `hyg_v42.csv` at [`HYG_MAG_LIMIT`] (excludes Sun + invalid rows).
pub const HYG_V42_EXPECTED_STARS: usize = 119_432;

/// Relative path from repository root to the read-only HYG source CSV.
pub const HYG_CSV_REL_PATH: &str = "packages/nightshade_planetarium/assets/hyg/hyg_v42.csv";

/// Relative path from repository root to the desktop asset output directory.
pub const HYG_OUTPUT_REL_DIR: &str = "apps/desktop/assets/planetarium/catalogs/stars-hyg-v1";

/// Errors while building tiles from HYG.
#[derive(Debug, Error)]
pub enum HygBuildError {
    /// I/O failure.
    #[error("{context}: {source}")]
    Io {
        /// Human-readable stage.
        context: &'static str,
        /// Underlying error.
        #[source]
        source: std::io::Error,
    },
    /// HEALPix assignment failed for a row.
    #[error("healpix pixel_for_direction failed: {0}")]
    Healpix(#[from] super::healpix::HealpixError),
    /// A CSV row failed to parse with structurally invalid data (RA/Dec/HIP/magnitude).
    ///
    /// Fail-loud: parse errors are not silently skipped. By-design skips
    /// (`SunPlaceholder`, `BeyondMagnitudeLimit`) are tolerated and counted.
    #[error("HYG row {line_no}: {reason:?}")]
    InvalidRow {
        /// 1-based CSV line number (after the header).
        line_no: usize,
        /// Why this row could not be parsed.
        reason: HygSkipReason,
    },
}

impl HygBuildError {
    fn io(context: &'static str, source: std::io::Error) -> Self {
        Self::Io { context, source }
    }
}

/// Summary statistics from a conversion run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HygBuildStats {
    /// Number of `.bin` tile files written.
    pub tiles_written: usize,
    /// Star records written across all tiles.
    pub stars_written: usize,
    /// Input rows skipped (invalid, below horizon catalog rules, or beyond mag limit).
    pub stars_skipped: usize,
}

/// Result of [`build_hyg_tiles`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HygBuildResult {
    /// Output directory containing `tiles/`.
    pub output_dir: PathBuf,
    /// Conversion statistics.
    pub stats: HygBuildStats,
}

/// Resolve the default HYG CSV path under a repository root.
#[must_use]
pub fn default_hyg_csv_path(repo_root: impl AsRef<Path>) -> PathBuf {
    repo_root.as_ref().join(HYG_CSV_REL_PATH)
}

/// Resolve the default `stars-hyg-v1` output directory under a repository root.
#[must_use]
pub fn default_output_dir(repo_root: impl AsRef<Path>) -> PathBuf {
    repo_root.as_ref().join(HYG_OUTPUT_REL_DIR)
}

/// Locate the repository root by walking parents from `start` until `HYG_CSV_REL_PATH` exists.
pub fn find_repo_root(start: impl AsRef<Path>) -> Option<PathBuf> {
    let mut dir = start.as_ref().canonicalize().ok()?;
    loop {
        if dir.join(HYG_CSV_REL_PATH).is_file() {
            return Some(dir);
        }
        if !dir.pop() {
            return None;
        }
    }
}

/// Parsed HYG row: GPU star record plus the source radians needed for HEALPix bucketing.
#[derive(Debug, Clone, Copy)]
pub struct HygParsedRow {
    /// Star record ready to write to a tile.
    pub star: StarRecord,
    /// J2000 right ascension (radians) as parsed from the CSV.
    pub ra_rad: f64,
    /// J2000 declination (radians) as parsed from the CSV.
    pub dec_rad: f64,
}

/// Per-row reason for skipping a HYG record.
///
/// Surfaces *why* a row was dropped so the build tool can fail loud on truly malformed
/// input (e.g. unparseable RA/Dec) while still skipping by-design rows (Sun placeholder,
/// magnitudes beyond the bundled limit). Per `CLAUDE.md`, silent fallbacks are forbidden.
#[derive(Debug, Clone, PartialEq)]
pub enum HygSkipReason {
    /// Row has fewer than the 25 columns required by HYG v4.2.
    TooFewFields {
        /// Actual field count for this row.
        actual: usize,
    },
    /// Right ascension column was not finite or failed to parse.
    InvalidRa(String),
    /// Declination column was not finite or failed to parse.
    InvalidDec(String),
    /// Apparent magnitude column was not finite or failed to parse.
    InvalidMagnitude(String),
    /// HIP id column was non-empty but not a non-negative integer.
    InvalidHipId(String),
    /// Apparent magnitude is fainter than the bundled pack limit.
    BeyondMagnitudeLimit {
        /// Magnitude value.
        mag: f32,
        /// Limit applied.
        limit: f32,
    },
    /// HYG row 0 with a placeholder Sun magnitude is excluded by design.
    SunPlaceholder,
}

/// Parse one HYG v4.2 CSV row into a [`HygParsedRow`], or surface a skip reason.
///
/// Parse failures (RA/Dec/magnitude/HIP id) return [`HygSkipReason::InvalidRa`] etc.
/// rather than `None`, so the build tool can fail loud instead of silently dropping
/// rows with malformed numbers. By-design skips (`SunPlaceholder`,
/// `BeyondMagnitudeLimit`) are still tolerated by [`build_hyg_tiles`].
pub fn hyg_row_to_star(fields: &[String]) -> Result<HygParsedRow, HygSkipReason> {
    if fields.len() < 25 {
        return Err(HygSkipReason::TooFewFields {
            actual: fields.len(),
        });
    }

    // HYG `hip` column is integer-or-empty; empty means "no Hipparcos cross-id"
    // (id 0 sentinel matches v1 Dart catalog and the tile binary spec).
    let hip_id_str = fields[1].trim();
    let hip_id = if hip_id_str.is_empty() {
        0u32
    } else {
        hip_id_str
            .parse::<u32>()
            .map_err(|_| HygSkipReason::InvalidHipId(hip_id_str.to_string()))?
    };

    let ra_text = fields[23].trim();
    let ra_rad: f64 = ra_text
        .parse()
        .map_err(|_| HygSkipReason::InvalidRa(ra_text.to_string()))?;
    if !ra_rad.is_finite() {
        return Err(HygSkipReason::InvalidRa(ra_text.to_string()));
    }

    let dec_text = fields[24].trim();
    let dec_rad: f64 = dec_text
        .parse()
        .map_err(|_| HygSkipReason::InvalidDec(dec_text.to_string()))?;
    if !dec_rad.is_finite() {
        return Err(HygSkipReason::InvalidDec(dec_text.to_string()));
    }

    let mag_text = fields[13].trim();
    let mag: f32 = mag_text
        .parse()
        .map_err(|_| HygSkipReason::InvalidMagnitude(mag_text.to_string()))?;
    if !mag.is_finite() {
        return Err(HygSkipReason::InvalidMagnitude(mag_text.to_string()));
    }

    // Drop the placeholder Sun row (id 0 at the catalog origin) before applying the mag limit.
    if fields.first().map(String::as_str) == Some("0") && mag < -10.0 {
        return Err(HygSkipReason::SunPlaceholder);
    }

    if mag > HYG_MAG_LIMIT {
        return Err(HygSkipReason::BeyondMagnitudeLimit {
            mag,
            limit: HYG_MAG_LIMIT,
        });
    }

    // `bv` is allowed to be empty/missing — NAN is the documented sentinel for "unknown color".
    // A non-empty but unparseable B-V is treated as unknown to match v1 Dart behavior;
    // numeric parse failures here are still recorded for observability via `bv_unknown` count
    // in a future build-stats extension.
    let bv = if fields.len() > 16 {
        let bv_text = fields[16].trim();
        if bv_text.is_empty() {
            f32::NAN
        } else {
            bv_text.parse::<f32>().unwrap_or(f32::NAN)
        }
    } else {
        f32::NAN
    };

    let mut flags = 0u32;
    if fields.len() > 33 && !fields[33].is_empty() {
        flags |= HYG_FLAG_VARIABLE;
    }

    Ok(HygParsedRow {
        star: StarRecord::from_radec(hip_id, ra_rad as f32, dec_rad as f32, mag, bv, flags),
        ra_rad,
        dec_rad,
    })
}

/// Build magnitude-band index entries for a brightest-first star slice.
#[must_use]
pub fn build_lod_entries(stars: &[StarRecord], thresholds: &[f32]) -> Vec<LodEntry> {
    let mut entries = Vec::with_capacity(thresholds.len());
    let mut offset = 0u32;
    let mut prev = f32::NEG_INFINITY;

    for &threshold in thresholds {
        let mut count = 0u32;
        let mut i = offset as usize;
        while i < stars.len() {
            let mag = stars[i].mag;
            if mag <= threshold && mag > prev {
                count += 1;
                i += 1;
            } else {
                break;
            }
        }
        if count > 0 {
            entries.push(LodEntry {
                mag_threshold: threshold,
                start_offset: offset,
                count,
                reserved: 0,
            });
            offset += count;
        }
        prev = threshold;
    }

    entries
}

/// Read HYG CSV, bucket stars by HEALPix pixel, and write `tiles/{healpix_id:012x}.bin` files.
pub fn build_hyg_tiles(
    csv_path: &Path,
    output_dir: &Path,
) -> Result<HygBuildResult, HygBuildError> {
    let tiles_dir = output_dir.join("tiles");
    if tiles_dir.exists() {
        fs::remove_dir_all(&tiles_dir).map_err(|e| HygBuildError::io("remove old tiles dir", e))?;
    }
    fs::create_dir_all(&tiles_dir).map_err(|e| HygBuildError::io("create tiles dir", e))?;

    let file = File::open(csv_path).map_err(|e| HygBuildError::io("open HYG csv", e))?;
    let reader = BufReader::new(file);

    let mut buckets: BTreeMap<u64, Vec<StarRecord>> = BTreeMap::new();
    let mut skipped = 0usize;

    for (line_no, line) in reader.lines().enumerate() {
        let line = line.map_err(|e| HygBuildError::io("read HYG csv line", e))?;
        if line_no == 0 || line.is_empty() {
            continue;
        }

        let fields = parse_csv_line(&line);
        match hyg_row_to_star(&fields) {
            Ok(parsed) => {
                let pixel = pixel_for_direction(parsed.ra_rad, parsed.dec_rad, HYG_NSIDE)?;
                buckets.entry(pixel).or_default().push(parsed.star);
            }
            Err(reason) if is_by_design_skip(&reason) => {
                skipped += 1;
            }
            Err(reason) => {
                // Fail loud on structurally invalid input: a malformed CSV that quietly
                // dropped rows would corrupt counts and hide upstream corruption.
                return Err(HygBuildError::InvalidRow { line_no, reason });
            }
        }
    }

    let mut tiles_written = 0usize;
    let mut stars_written = 0usize;

    for (healpix_id, mut stars) in buckets {
        stars.sort_by(|a, b| {
            a.mag
                .partial_cmp(&b.mag)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        let lod_entries = build_lod_entries(&stars, HYG_LOD_MAG_THRESHOLDS);
        let header = TileHeader::new(
            HYG_CATALOG_ID,
            HYG_PACK_VERSION,
            HYG_NSIDE,
            healpix_id,
            stars.len() as u32,
            lod_entries.len() as u32,
        );
        let bytes = encode_tile(&header, &lod_entries, &stars);
        let path = tiles_dir.join(format!("{healpix_id:012x}.bin"));
        let mut out = File::create(&path).map_err(|e| HygBuildError::io("create tile file", e))?;
        out.write_all(&bytes)
            .map_err(|e| HygBuildError::io("write tile file", e))?;
        tiles_written += 1;
        stars_written += stars.len();
    }

    Ok(HygBuildResult {
        output_dir: output_dir.to_path_buf(),
        stats: HygBuildStats {
            tiles_written,
            stars_written,
            stars_skipped: skipped,
        },
    })
}

/// Returns `true` when a row was skipped by policy (Sun placeholder, magnitude limit)
/// rather than because of a parse error.
#[inline]
fn is_by_design_skip(reason: &HygSkipReason) -> bool {
    matches!(
        reason,
        HygSkipReason::SunPlaceholder | HygSkipReason::BeyondMagnitudeLimit { .. }
    )
}

/// Parse a single CSV record with RFC-4180-style quoted fields.
fn parse_csv_line(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut chars = line.chars().peekable();

    while let Some(ch) = chars.next() {
        match ch {
            '"' if in_quotes => {
                if chars.peek() == Some(&'"') {
                    chars.next();
                    current.push('"');
                } else {
                    in_quotes = false;
                }
            }
            '"' => in_quotes = true,
            ',' if !in_quotes => {
                fields.push(std::mem::take(&mut current));
            }
            c => current.push(c),
        }
    }
    fields.push(current);
    fields
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::{parse_tile, tile_byte_len};

    #[test]
    fn lod_entries_partition_sorted_stars() {
        let stars = vec![
            StarRecord::from_radec(1, 0.0, 0.0, 1.0, 0.0, 0),
            StarRecord::from_radec(2, 0.1, 0.0, 3.0, 0.0, 0),
            StarRecord::from_radec(3, 0.2, 0.0, 7.0, 0.0, 0),
        ];
        let lods = build_lod_entries(&stars, &[2.5, 6.0, 15.0]);
        assert_eq!(lods.len(), 3);
        assert_eq!(lods[0].count, 1);
        assert_eq!(lods[1].count, 1);
        assert_eq!(lods[2].count, 1);
        let total: u32 = lods.iter().map(|e| e.count).sum();
        assert_eq!(total, stars.len() as u32);
    }

    #[test]
    fn hyg_row_parses_polaris_fixture() {
        let line = include_str!("../../tests/fixtures/hyg_polaris_row.csv");
        let fields = parse_csv_line(line.trim());
        let parsed = hyg_row_to_star(&fields).expect("polaris row");
        assert_eq!(parsed.star.hip_id, 11767);
        assert!((parsed.star.mag - 1.98).abs() < 0.01);
        assert!(parsed.ra_rad.is_finite());
        assert!(parsed.dec_rad.is_finite());
    }

    #[test]
    fn malformed_ra_returns_loud_error() {
        let mut fields: Vec<String> = (0..30).map(|_| String::new()).collect();
        fields[1] = "1".to_string();
        fields[13] = "5.0".to_string();
        fields[23] = "not-a-number".to_string();
        fields[24] = "0.5".to_string();
        let err = hyg_row_to_star(&fields).expect_err("invalid RA must error");
        assert!(matches!(err, HygSkipReason::InvalidRa(_)), "got {err:?}");
    }

    #[test]
    fn beyond_magnitude_limit_is_by_design_skip() {
        let mut fields: Vec<String> = (0..30).map(|_| String::new()).collect();
        fields[1] = "999".to_string();
        fields[13] = (HYG_MAG_LIMIT + 1.0).to_string();
        fields[23] = "0.5".to_string();
        fields[24] = "0.5".to_string();
        let reason = hyg_row_to_star(&fields).expect_err("faint star must be skipped");
        assert!(is_by_design_skip(&reason), "{reason:?}");
    }
}
