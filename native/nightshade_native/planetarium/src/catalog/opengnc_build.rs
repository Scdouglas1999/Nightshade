//! OpenNGC CSV → single mmap DSO catalog (`dso-opengnc-v1.bin`).
//!
//! Reads [`NGC.csv`](../../../../../../packages/nightshade_planetarium/assets/opengnc/NGC.csv)
//! (semicolon-separated, same schema as v1 Dart `OpenNgcDsoCatalog`).

use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

use thiserror::Error;

use super::dso::{
    encode_catalog, type_id_from_opengnc, DsoCatalogHeader, DsoRecord, DSO_FLAG_HAS_MAG,
    DSO_FLAG_MESSIER, OPENNGC_CATALOG_ID, OPENNGC_PACK_VERSION,
};

/// Faintest apparent magnitude included in the bundled OpenNGC pack (matches v1 `complete`).
pub const OPENNGC_MAG_LIMIT: f32 = 20.0;

/// Expected record count for upstream `NGC.csv` at [`OPENNGC_MAG_LIMIT`] (master export).
pub const OPENNGC_V1_EXPECTED_RECORDS: usize = 13_306;

/// Relative path from repository root to the read-only OpenNGC source CSV.
pub const OPENNGC_CSV_REL_PATH: &str = "packages/nightshade_planetarium/assets/opengnc/NGC.csv";

/// Relative path from repository root to the desktop asset output file.
pub const OPENNGC_OUTPUT_REL_PATH: &str =
    "apps/desktop/assets/planetarium/catalogs/core/dso-opengnc-v1.bin";

/// Errors while building the OpenNGC binary catalog.
#[derive(Debug, Error)]
pub enum OpenNgcBuildError {
    /// I/O failure.
    #[error("{context}: {source}")]
    Io {
        /// Human-readable stage.
        context: &'static str,
        /// Underlying error.
        #[source]
        source: std::io::Error,
    },
}

impl OpenNgcBuildError {
    fn io(context: &'static str, source: std::io::Error) -> Self {
        Self::Io { context, source }
    }
}

/// Summary statistics from a conversion run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpenNgcBuildStats {
    /// DSO records written.
    pub records_written: usize,
    /// Input rows skipped (invalid, NonEx/Dup, or beyond mag limit).
    pub records_skipped: usize,
}

/// Result of [`build_opengnc_catalog`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenNgcBuildResult {
    /// Output `.bin` path.
    pub output_path: PathBuf,
    /// Conversion statistics.
    pub stats: OpenNgcBuildStats,
}

/// Resolve the default OpenNGC CSV path under a repository root.
#[must_use]
pub fn default_opengnc_csv_path(repo_root: impl AsRef<Path>) -> PathBuf {
    repo_root.as_ref().join(OPENNGC_CSV_REL_PATH)
}

/// Resolve the default `dso-opengnc-v1.bin` output path under a repository root.
#[must_use]
pub fn default_output_path(repo_root: impl AsRef<Path>) -> PathBuf {
    repo_root.as_ref().join(OPENNGC_OUTPUT_REL_PATH)
}

/// Locate the repository root by walking parents until [`OPENNGC_CSV_REL_PATH`] exists.
pub fn find_repo_root(start: impl AsRef<Path>) -> Option<PathBuf> {
    let mut dir = start.as_ref().canonicalize().ok()?;
    loop {
        if dir.join(OPENNGC_CSV_REL_PATH).is_file() {
            return Some(dir);
        }
        if !dir.pop() {
            return None;
        }
    }
}

/// Parse one OpenNGC semicolon-separated row into a [`DsoRecord`], or `None` if skipped.
pub fn opengnc_row_to_record(fields: &[&str]) -> Option<DsoRecord> {
    if fields.len() < 10 {
        return None;
    }

    let type_code = fields[1].trim();
    if type_code == "NonEx" || type_code == "Dup" {
        return None;
    }

    let ra_rad = parse_ra_hms(fields[2].trim())?;
    let dec_rad = parse_dec_dms(fields[3].trim())?;

    let major_axis = parse_f32_or_zero(fields[5].trim());
    let minor_axis = parse_f32_or_zero(fields[6].trim());
    let pa_deg = fields[7].trim().parse::<f32>().unwrap_or(f32::NAN);

    let b_mag = fields[8]
        .trim()
        .parse::<f32>()
        .ok()
        .filter(|m| m.is_finite());
    let v_mag = fields[9]
        .trim()
        .parse::<f32>()
        .ok()
        .filter(|m| m.is_finite());
    let surface_mag = v_mag.or(b_mag).unwrap_or(f32::NAN);

    if surface_mag.is_finite() && surface_mag > OPENNGC_MAG_LIMIT {
        return None;
    }

    let (ngc_id, ic_id) = catalog_ids_from_name(fields[0].trim());

    let mut messier_num = 0u32;
    if fields.len() > 23 {
        if let Some(n) = fields[23].trim().parse::<u32>().ok() {
            if (1..=110).contains(&n) {
                messier_num = n;
            }
        }
    }

    let mut flags = 0u32;
    if surface_mag.is_finite() {
        flags |= DSO_FLAG_HAS_MAG;
    }
    if messier_num > 0 {
        flags |= DSO_FLAG_MESSIER;
    }

    Some(DsoRecord::from_radec(
        ra_rad,
        dec_rad,
        major_axis,
        minor_axis,
        pa_deg,
        surface_mag,
        type_id_from_opengnc(type_code),
        flags,
        ngc_id,
        ic_id,
        messier_num,
    ))
}

/// Read OpenNGC CSV and write a single mmap-ready `.bin` file.
pub fn build_opengnc_catalog(
    csv_path: &Path,
    output_path: &Path,
) -> Result<OpenNgcBuildResult, OpenNgcBuildError> {
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| OpenNgcBuildError::io("create output dir", e))?;
    }

    let file = File::open(csv_path).map_err(|e| OpenNgcBuildError::io("open OpenNGC csv", e))?;
    let reader = BufReader::new(file);

    let mut records = Vec::new();
    let mut skipped = 0usize;

    for (line_no, line) in reader.lines().enumerate() {
        let line = line.map_err(|e| OpenNgcBuildError::io("read OpenNGC csv line", e))?;
        if line_no == 0 || line.is_empty() {
            continue;
        }

        let fields: Vec<&str> = line.split(';').collect();
        match opengnc_row_to_record(&fields) {
            Some(record) => records.push(record),
            None => skipped += 1,
        }
    }

    records.sort_by(|a, b| cmp_magnitude(a.surface_mag, b.surface_mag));

    let header = DsoCatalogHeader::new(
        OPENNGC_CATALOG_ID,
        OPENNGC_PACK_VERSION,
        records.len() as u32,
        OPENNGC_MAG_LIMIT,
    );
    let bytes = encode_catalog(&header, &records);

    let mut out =
        File::create(output_path).map_err(|e| OpenNgcBuildError::io("create output bin", e))?;
    out.write_all(&bytes)
        .map_err(|e| OpenNgcBuildError::io("write output bin", e))?;

    Ok(OpenNgcBuildResult {
        output_path: output_path.to_path_buf(),
        stats: OpenNgcBuildStats {
            records_written: records.len(),
            records_skipped: skipped,
        },
    })
}

fn cmp_magnitude(a: f32, b: f32) -> std::cmp::Ordering {
    match (a.is_finite(), b.is_finite()) {
        (true, true) => a.partial_cmp(&b).unwrap_or(std::cmp::Ordering::Equal),
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        (false, false) => std::cmp::Ordering::Equal,
    }
}

fn parse_f32_or_zero(s: &str) -> f32 {
    if s.is_empty() {
        0.0
    } else {
        s.parse::<f32>().unwrap_or(0.0)
    }
}

/// Parse RA `HH:MM:SS.ss` to radians.
fn parse_ra_hms(ra_str: &str) -> Option<f32> {
    if ra_str.is_empty() {
        return None;
    }
    let parts: Vec<&str> = ra_str.split(':').collect();
    if parts.len() != 3 {
        return None;
    }
    let h: f64 = parts[0].parse().ok()?;
    let m: f64 = parts[1].parse().ok()?;
    let s: f64 = parts[2].parse().ok()?;
    let hours = h + m / 60.0 + s / 3600.0;
    Some((hours * std::f64::consts::PI / 12.0) as f32)
}

/// Parse Dec `±DD:MM:SS.s` to radians.
fn parse_dec_dms(dec_str: &str) -> Option<f32> {
    if dec_str.is_empty() {
        return None;
    }
    let sign = if dec_str.starts_with('-') { -1.0 } else { 1.0 };
    let clean = dec_str.trim_start_matches(['+', '-']);
    let parts: Vec<&str> = clean.split(':').collect();
    if parts.len() != 3 {
        return None;
    }
    let d: f64 = parts[0].parse().ok()?;
    let m: f64 = parts[1].parse().ok()?;
    let s: f64 = parts[2].parse().ok()?;
    let deg = sign * (d + m / 60.0 + s / 3600.0);
    Some((deg.to_radians()) as f32)
}

/// Normalize `NGC0628` → NGC id 628; `IC0410` → IC id 410.
fn catalog_ids_from_name(name: &str) -> (u32, u32) {
    let normalized = normalize_catalog_name(name);
    if let Some(num) = normalized.strip_prefix("NGC") {
        return (num.parse().unwrap_or(0), 0);
    }
    if let Some(num) = normalized.strip_prefix("IC") {
        return (0, num.parse().unwrap_or(0));
    }
    (0, 0)
}

fn normalize_catalog_name(name: &str) -> String {
    let upper = name.trim().to_uppercase();
    if let Some(rest) = upper.strip_prefix("NGC") {
        let digits: String = rest.chars().filter(|c| c.is_ascii_digit()).collect();
        if let Ok(n) = digits.parse::<u32>() {
            return format!("NGC{n}");
        }
    }
    if let Some(rest) = upper.strip_prefix("IC") {
        let digits: String = rest.chars().filter(|c| c.is_ascii_digit()).collect();
        if let Ok(n) = digits.parse::<u32>() {
            return format!("IC{n}");
        }
    }
    upper
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::{dso_type, DSO_FLAG_HAS_MAG, DSO_FLAG_MESSIER};

    #[test]
    fn opengnc_row_parses_m31_fixture() {
        let line = include_str!("../../tests/fixtures/ngc_m31_row.csv").trim();
        let fields: Vec<&str> = line.split(';').collect();
        let record = opengnc_row_to_record(&fields).expect("M31 row");
        assert_eq!(record.ngc_id, 224);
        assert_eq!(record.messier_num, 31);
        assert_eq!(record.type_id, dso_type::GALAXY);
        assert!((record.surface_mag - 3.44).abs() < 0.01);
        assert_eq!(record.flags, DSO_FLAG_HAS_MAG | DSO_FLAG_MESSIER);
        assert!((record.size_arcmin[0] - 189.1).abs() < 0.1);
    }

    #[test]
    fn normalize_strips_leading_zeros() {
        assert_eq!(normalize_catalog_name("NGC0628"), "NGC628");
        assert_eq!(normalize_catalog_name("IC0410"), "IC410");
    }
}
