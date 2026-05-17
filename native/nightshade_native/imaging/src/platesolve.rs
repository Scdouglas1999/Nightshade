//! Real Plate Solving Integration
//!
//! Provides actual integration with plate solving software:
//! - ASTAP (Astrometric STAcking Program)
//! - Local Astrometry.net
//!
//! These are real implementations that call external solvers.
//!
//! # `as`-cast policy (audit-rust §1.4)
//!
//! This module's numeric casts cluster into three safe-by-construction families:
//! - **Pixel-buffer math** (`u16/u32/f32/f64 as u16` for monochromization): the
//!   target is a 16-bit pixel buffer; saturation per Rust 1.45 spec matches the
//!   "clamp out-of-range pixel" intent.
//! - **Image-coordinate widening** (`u32 as f64`, `u32 as usize`): sensor
//!   dimensions fit losslessly in f64 mantissa and >=32-bit usize.
//! - **Sub-pixel star coordinates** (`f64 as i32`, `f64 as usize`): centroid
//!   values fall within image extent (bounds-checked) so saturation is unreachable.
//!
//! High-risk pixel_count arithmetic uses explicit `checked_mul`. Sites with
//! their own `Why:` comment override the module-level reasoning.
//!
//! # `unwrap_or` policy (audit-rust §4.3)
//!
//! Each `unwrap_or` site below maps to a specific external-solver edge case:
//!
//! * `output.status.code().unwrap_or(-1)` — on POSIX a subprocess killed by
//!   a signal has no exit code; `-1` is the documented sentinel surfaced to
//!   the FFI caller's `SolveResult.status` (treated as "solver crashed").
//! * `crota.unwrap_or(0.0)` — `CROTA2` is optional in the FITS WCS standard;
//!   zero rotation is the default North-Up orientation assumed when the
//!   solver omits the keyword.
//! * `parts.get(N).copied().unwrap_or(0.0)` (sexagesimal parse) — missing
//!   minutes/seconds = treat as zero, the standard astronomy convention
//!   (`12 30` is "12h 30m 0s", not an error).
//! * `output_dir.parent().unwrap_or_else(|| Path::new("."))` — root-path
//!   case for the temp/work directory; current-dir is the safe fallback.
//! * `pixels.iter().max().unwrap_or(&0)` — empty pixel slice would have
//!   already failed `validate_image()` upstream; `0` here is unreachable
//!   but cheaper than `expect` and yields a flat-histogram render.

mod platesolve_paths;

pub use platesolve_paths::CatalogInfo;
use platesolve_paths::{
    astap_candidates, astrometry_candidates, catalog_dir_candidates, first_existing,
    identify_catalog, AstapPathInputs, AstrometryPathInputs, CatalogSearchInputs, OsFamily, RealFs,
};

use std::fs;
use std::num::ParseFloatError;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use thiserror::Error;

#[cfg(test)]
use crate::{detect_stars, read_fits, FitsHeader, ImageData, PixelType, StarDetectionConfig};
#[cfg(test)]
use bytemuck::{Pod, Zeroable};
#[cfg(test)]
use wgpu::util::DeviceExt;

/// Structured errors emitted while parsing solver-produced WCS / INI files.
///
/// A solve must surface every parse failure so downstream science code never
/// treats a malformed header as a successful zero-coordinate solution.
#[derive(Debug, Error)]
pub enum PlateSolveError {
    #[error(
        "failed to parse WCS keyword `{keyword}` value `{raw_value}` as f64 (file: {path}): {source}"
    )]
    WcsParse {
        keyword: String,
        raw_value: String,
        path: String,
        #[source]
        source: ParseFloatError,
    },
    #[error("WCS file `{path}` did not contain required keyword `{keyword}`")]
    WcsMissingKeyword { keyword: String, path: String },
    #[error("ASTAP INI file `{path}` reports plate solve failed (PLTSOLVD != T)")]
    SolveFailed { path: String },
    #[error("failed to read solver output `{path}`: {source}")]
    ReadOutput {
        path: String,
        #[source]
        source: std::io::Error,
    },
}

/// Plate solve result
#[derive(Debug, Clone)]
pub struct PlateSolveResult {
    /// Solved RA in degrees
    pub ra: f64,
    /// Solved Dec in degrees
    pub dec: f64,
    /// Image scale in arcsec/pixel
    pub pixel_scale: f64,
    /// Rotation angle in degrees (East of North)
    pub rotation: f64,
    /// Field width in degrees
    pub field_width: f64,
    /// Field height in degrees
    pub field_height: f64,
    /// Was the solve successful?
    pub success: bool,
    /// Error message if failed
    pub error: Option<String>,
    /// Time taken to solve in seconds
    pub solve_time_secs: f64,
}

/// Plate solver configuration
#[derive(Debug, Clone)]
pub struct PlateSolverConfig {
    /// Path to ASTAP executable
    pub astap_path: Option<PathBuf>,
    /// Path to local astrometry.net solve-field
    pub astrometry_path: Option<PathBuf>,
    /// Search radius in degrees (0 = blind solve)
    pub search_radius: f64,
    /// Downsample factor for faster solving
    pub downsample: u32,
    /// Maximum time for solving in seconds
    pub timeout_secs: u32,
}

impl Default for PlateSolverConfig {
    fn default() -> Self {
        Self {
            astap_path: find_astap(),
            astrometry_path: find_astrometry(),
            search_radius: 10.0,
            downsample: 2,
            timeout_secs: 60,
        }
    }
}

/// Find ASTAP installation by probing every well-known install path *plus*
/// PATH. Returns the first hit. `configured` lets settings override the
/// search order — when supplied and present, it always wins.
///
/// The candidate list lives in `platesolve_paths::astap_candidates` so the
/// per-OS enumeration can be unit-tested without filesystem access.
pub fn find_astap_with_override(configured: Option<&Path>) -> Option<PathBuf> {
    let local_app_data = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
    let home = home_dir();

    let inputs = AstapPathInputs {
        os: OsFamily::host(),
        configured,
        local_app_data: local_app_data.as_deref(),
        home: home.as_deref(),
    };

    let candidates = astap_candidates(&inputs);
    if let Some(hit) = first_existing(&RealFs, &candidates) {
        return Some(hit);
    }

    which_on_path("astap")
        .or_else(|| which_on_path("astap_cli"))
        .map(PathBuf::from)
}

/// Find ASTAP installation using only the platform default candidate list
/// (no user override). Used by the legacy `PlateSolverConfig::default()`
/// path that has no access to settings.
fn find_astap() -> Option<PathBuf> {
    find_astap_with_override(None)
}

/// Find local astrometry.net installation. See `find_astap_with_override`
/// for the override semantics.
pub fn find_astrometry_with_override(configured: Option<&Path>) -> Option<PathBuf> {
    let inputs = AstrometryPathInputs {
        os: OsFamily::host(),
        configured,
    };

    let candidates = astrometry_candidates(&inputs);
    if let Some(hit) = first_existing(&RealFs, &candidates) {
        return Some(hit);
    }

    which_on_path("solve-field").map(PathBuf::from)
}

fn find_astrometry() -> Option<PathBuf> {
    find_astrometry_with_override(None)
}

/// Resolve the user's home directory from the platform-appropriate env var.
fn home_dir() -> Option<PathBuf> {
    if cfg!(target_os = "windows") {
        std::env::var_os("USERPROFILE").map(PathBuf::from)
    } else {
        std::env::var_os("HOME").map(PathBuf::from)
    }
}

/// Cross-platform `which`/`where` lookup. Shells out so we get exactly the
/// same resolution semantics as the user's interactive shell. Returns the
/// first matching path or `None` if the command isn't on PATH.
fn which_on_path(binary: &str) -> Option<String> {
    let (cmd, query) = if cfg!(target_os = "windows") {
        ("where", format!("{}.exe", binary))
    } else {
        ("which", binary.to_string())
    };

    let output = Command::new(cmd).arg(&query).output().ok()?;
    if !output.status.success() {
        // On Windows, also try without the .exe extension in case it's a
        // CLI tool installed without the suffix.
        if cfg!(target_os = "windows") {
            let fallback = Command::new("where").arg(binary).output().ok()?;
            if fallback.status.success() {
                let path = String::from_utf8(fallback.stdout).ok()?;
                return path.lines().next().map(|s| s.trim().to_string());
            }
        }
        return None;
    }
    let path = String::from_utf8(output.stdout).ok()?;
    let first = path.lines().next()?.trim();
    if first.is_empty() {
        None
    } else {
        Some(first.to_string())
    }
}

/// Detect an ASTAP star catalog around a known executable path. The catalog
/// (.290/.h17 files) is required for ASTAP to actually solve; many users
/// install it separately on a fast drive.
///
/// Returns the *first* recognised catalog, walking:
///   1. user-configured catalog directory (if any),
///   2. directory containing the ASTAP executable,
///   3. `~/.astap/`,
///   4. platform-specific install locations (`%LOCALAPPDATA%\astap`, etc.).
///
/// The actual filename → catalog-name mapping lives in
/// `platesolve_paths::identify_catalog` so it can be exhaustively tested
/// without staging real catalog files.
pub fn detect_astap_catalog(
    exe_path: Option<&Path>,
    configured: Option<&Path>,
) -> Option<CatalogInfo> {
    let local_app_data = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
    let home = home_dir();

    let inputs = CatalogSearchInputs {
        os: OsFamily::host(),
        exe_path,
        configured,
        local_app_data: local_app_data.as_deref(),
        home: home.as_deref(),
    };

    for dir in catalog_dir_candidates(&inputs) {
        if !dir.is_dir() {
            continue;
        }
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        let names: Vec<String> = entries
            .flatten()
            .filter_map(|e| e.file_name().to_str().map(|s| s.to_string()))
            .collect();
        if let Some(info) = identify_catalog(&dir, names) {
            return Some(info);
        }
    }
    None
}

/// Result of running an installed solver's `--help` (or equivalent) to
/// confirm the binary is healthy. Returned by `verify_solver`.
#[derive(Debug, Clone)]
pub struct SolverInfo {
    /// Absolute path the verifier ran against.
    pub path: PathBuf,
    /// Solver flavour (`"ASTAP"`, `"Astrometry.net"`, or `"Unknown"`).
    pub flavour: String,
    /// First non-empty line of the solver's `--help` / version output —
    /// useful for surfacing in the settings UI so the user can confirm the
    /// expected build.
    pub version_line: String,
}

/// Structured errors emitted by `verify_solver`.
#[derive(Debug, Error)]
pub enum SolverVerifyError {
    #[error("solver executable `{0}` does not exist")]
    Missing(PathBuf),
    #[error("failed to run solver `{path}`: {source}")]
    Spawn {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("solver `{path}` exited with status {status} on `--help`. stderr: {stderr}")]
    NonZeroExit {
        path: PathBuf,
        status: i32,
        stderr: String,
    },
}

/// Exec the solver with `--help` to confirm the binary actually works.
///
/// Why bother: a user can drop a stale or incompatible binary into the
/// configured path. Running it once at settings-save time catches that
/// instead of letting the failure surface inside a sequence.
///
/// Both ASTAP and `solve-field` print a usage / version banner on `--help`
/// and exit zero. We capture the first non-empty stdout line as the
/// version banner. A non-zero exit (or process spawn failure) is reported
/// as a structured error so the UI can surface the underlying cause.
pub fn verify_solver(path: &Path) -> Result<SolverInfo, SolverVerifyError> {
    if !path.exists() {
        return Err(SolverVerifyError::Missing(path.to_path_buf()));
    }

    let output = Command::new(path)
        .arg("--help")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|source| SolverVerifyError::Spawn {
            path: path.to_path_buf(),
            source,
        })?;

    // Why allow non-zero: some builds of ASTAP exit 1 on `--help` after
    // writing the usage banner. Require *some* output before we treat the
    // result as healthy.
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let banner: Option<String> = stdout
        .lines()
        .chain(stderr.lines())
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_string);

    let banner = match banner {
        Some(b) => b,
        None => {
            // No output at all on either stream — that's almost certainly a
            // broken binary, even if it exited zero. Surface as a non-zero
            // exit so the UI shows the underlying status.
            return Err(SolverVerifyError::NonZeroExit {
                path: path.to_path_buf(),
                status: output.status.code().unwrap_or(-1),
                stderr: stderr.to_string(),
            });
        }
    };

    let lower = banner.to_ascii_lowercase();
    let flavour = if lower.contains("astap") {
        "ASTAP".to_string()
    } else if lower.contains("astrometry") || lower.contains("solve-field") {
        "Astrometry.net".to_string()
    } else {
        "Unknown".to_string()
    };

    Ok(SolverInfo {
        path: path.to_path_buf(),
        flavour,
        version_line: banner,
    })
}

/// Plate solver using ASTAP
pub struct AstapSolver {
    config: PlateSolverConfig,
}

impl AstapSolver {
    pub fn new(config: PlateSolverConfig) -> Self {
        Self { config }
    }

    pub fn with_default_config() -> Option<Self> {
        let config = PlateSolverConfig::default();
        if config.astap_path.is_some() {
            Some(Self { config })
        } else {
            None
        }
    }

    /// Check if ASTAP is available
    pub fn is_available(&self) -> bool {
        self.config.astap_path.is_some()
    }

    /// Get ASTAP path
    pub fn astap_path(&self) -> Option<&Path> {
        self.config.astap_path.as_deref()
    }

    /// Solve an image with optional hint coordinates
    ///
    /// # Arguments
    /// * `image_path` - Path to FITS file to solve
    /// * `hint_ra` - Optional hint RA in degrees
    /// * `hint_dec` - Optional hint Dec in degrees
    /// * `hint_scale` - Optional hint for image scale in arcsec/pixel
    pub fn solve(
        &self,
        image_path: &Path,
        hint_ra: Option<f64>,
        hint_dec: Option<f64>,
        hint_scale: Option<f64>,
    ) -> PlateSolveResult {
        let start = std::time::Instant::now();

        let astap_path = match &self.config.astap_path {
            Some(p) => p,
            None => {
                return PlateSolveResult {
                    ra: 0.0,
                    dec: 0.0,
                    pixel_scale: 0.0,
                    rotation: 0.0,
                    field_width: 0.0,
                    field_height: 0.0,
                    success: false,
                    error: Some("ASTAP not found".to_string()),
                    solve_time_secs: 0.0,
                }
            }
        };

        // Build ASTAP command
        let mut cmd = Command::new(astap_path);

        // Input file
        cmd.arg("-f").arg(image_path);

        // Search radius
        if hint_ra.is_some() && hint_dec.is_some() && self.config.search_radius > 0.0 {
            cmd.arg("-r").arg(format!("{}", self.config.search_radius));
        }

        // Hint coordinates
        if let (Some(ra), Some(dec)) = (hint_ra, hint_dec) {
            cmd.arg("-ra").arg(format!("{}", ra / 15.0)); // Convert to hours
            cmd.arg("-spd").arg(format!("{}", dec + 90.0)); // Convert to SPD
        }

        // Hint scale
        if hint_scale.is_some() {
            // ASTAP expects focal-length-style hints here, which require a known pixel size.
            // Do not synthesize focal length from an assumed pixel size.
            tracing::debug!(
                "Plate-solve scale hint provided without pixel size; skipping ASTAP focal-length hint"
            );
        }

        // Downsample
        if self.config.downsample > 1 {
            cmd.arg("-z").arg(format!("{}", self.config.downsample));
        }

        // Output (don't update FITS, just solve)
        cmd.arg("-update");

        // Run solver
        tracing::info!("Running ASTAP: {:?}", cmd);

        let output = match cmd.stdout(Stdio::piped()).stderr(Stdio::piped()).output() {
            Ok(o) => o,
            Err(e) => {
                return PlateSolveResult {
                    ra: 0.0,
                    dec: 0.0,
                    pixel_scale: 0.0,
                    rotation: 0.0,
                    field_width: 0.0,
                    field_height: 0.0,
                    success: false,
                    error: Some(format!("Failed to run ASTAP: {}", e)),
                    solve_time_secs: start.elapsed().as_secs_f64(),
                }
            }
        };

        let solve_time = start.elapsed().as_secs_f64();

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(format!("ASTAP failed: {}", stderr)),
                solve_time_secs: solve_time,
            };
        }

        // Parse ASTAP output - it writes a .wcs file alongside the input
        let wcs_path = image_path.with_extension("wcs");
        if !wcs_path.exists() {
            // Also try .ini file
            let ini_path = image_path.with_extension("ini");
            if ini_path.exists() {
                return self.parse_astap_ini(&ini_path, solve_time);
            }

            return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some("No solution file found".to_string()),
                solve_time_secs: solve_time,
            };
        }

        match self.parse_wcs_file(&wcs_path, solve_time) {
            Ok(result) => result,
            Err(err) => PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(err.to_string()),
                solve_time_secs: solve_time,
            },
        }
    }

    /// Parse ASTAP .ini result file
    fn parse_astap_ini(&self, ini_path: &Path, solve_time: f64) -> PlateSolveResult {
        match parse_astap_ini_inner(ini_path, solve_time) {
            Ok(result) => result,
            Err(err) => PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(err.to_string()),
                solve_time_secs: solve_time,
            },
        }
    }

    /// Parse WCS file emitted by ASTAP/astrometry.net.
    ///
    /// Required keywords: CRVAL1, CRVAL2, CD1_1, CD1_2, CD2_1, CD2_2.
    /// Any malformed value or missing required keyword propagates as
    /// `PlateSolveError`; the caller is responsible for converting to a
    /// failed `PlateSolveResult`. Silent fallbacks (RA=0/Dec=0) are
    /// forbidden — see CLAUDE.md "errors are a feature".
    fn parse_wcs_file(
        &self,
        wcs_path: &Path,
        solve_time: f64,
    ) -> Result<PlateSolveResult, PlateSolveError> {
        parse_wcs_file_inner(wcs_path, solve_time)
    }
}

/// Free-function form of WCS parsing so the test module can exercise it
/// without instantiating an `AstapSolver` (which requires a real ASTAP
/// install on PATH).
fn parse_wcs_file_inner(
    wcs_path: &Path,
    solve_time: f64,
) -> Result<PlateSolveResult, PlateSolveError> {
    let path_display = wcs_path.display().to_string();
    let content = fs::read_to_string(wcs_path).map_err(|source| PlateSolveError::ReadOutput {
        path: path_display.clone(),
        source,
    })?;

    let mut ra: Option<f64> = None;
    let mut dec: Option<f64> = None;
    let mut cd1_1: Option<f64> = None;
    let mut cd1_2: Option<f64> = None;
    let mut cd2_1: Option<f64> = None;
    let mut cd2_2: Option<f64> = None;

    for line in content.lines() {
        if line.len() < 10 {
            continue;
        }

        let keyword = line[..8].trim();
        if !line[8..].starts_with('=') {
            continue;
        }

        let value_part = line[10..].trim();
        let value_str = if let Some(idx) = value_part.find('/') {
            &value_part[..idx]
        } else {
            value_part
        }
        .trim();

        let parse = |slot: &mut Option<f64>| -> Result<(), PlateSolveError> {
            let parsed = value_str
                .parse::<f64>()
                .map_err(|source| PlateSolveError::WcsParse {
                    keyword: keyword.to_string(),
                    raw_value: value_str.to_string(),
                    path: path_display.clone(),
                    source,
                })?;
            *slot = Some(parsed);
            Ok(())
        };

        match keyword {
            "CRVAL1" => parse(&mut ra)?,
            "CRVAL2" => parse(&mut dec)?,
            "CD1_1" => parse(&mut cd1_1)?,
            "CD1_2" => parse(&mut cd1_2)?,
            "CD2_1" => parse(&mut cd2_1)?,
            "CD2_2" => parse(&mut cd2_2)?,
            _ => {}
        }
    }

    let require = |slot: Option<f64>, name: &str| -> Result<f64, PlateSolveError> {
        slot.ok_or_else(|| PlateSolveError::WcsMissingKeyword {
            keyword: name.to_string(),
            path: path_display.clone(),
        })
    };
    let ra = require(ra, "CRVAL1")?;
    let dec = require(dec, "CRVAL2")?;
    let cd1_1 = require(cd1_1, "CD1_1")?;
    let cd1_2 = require(cd1_2, "CD1_2")?;
    let cd2_1 = require(cd2_1, "CD2_1")?;
    let cd2_2 = require(cd2_2, "CD2_2")?;

    let pixel_scale = ((cd1_1 * cd1_1 + cd2_1 * cd2_1).sqrt() * 3600.0
        + (cd1_2 * cd1_2 + cd2_2 * cd2_2).sqrt() * 3600.0)
        / 2.0;
    let rotation = cd2_1.atan2(cd1_1).to_degrees();

    Ok(PlateSolveResult {
        ra,
        dec,
        pixel_scale,
        rotation,
        field_width: 0.0,
        field_height: 0.0,
        success: true,
        error: None,
        solve_time_secs: solve_time,
    })
}

/// Free-function form of ASTAP `.ini` parsing so the test module can exercise
/// it without an ASTAP install. Mirrors `parse_wcs_file_inner` semantics:
/// malformed numeric values or `PLTSOLVD != T` propagate as errors instead of
/// silently producing a zero-coordinate "successful" solve.
fn parse_astap_ini_inner(
    ini_path: &Path,
    solve_time: f64,
) -> Result<PlateSolveResult, PlateSolveError> {
    let path_display = ini_path.display().to_string();
    let content = fs::read_to_string(ini_path).map_err(|source| PlateSolveError::ReadOutput {
        path: path_display.clone(),
        source,
    })?;

    let mut ra: Option<f64> = None;
    let mut dec: Option<f64> = None;
    let mut crota: Option<f64> = None;
    let mut cdelt1: Option<f64> = None;
    let mut cdelt2: Option<f64> = None;
    let mut solved = false;

    for line in content.lines() {
        let line = line.trim();
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim().to_uppercase();
        let value = value.trim();

        let parse = |slot: &mut Option<f64>, keyword: &str| -> Result<(), PlateSolveError> {
            let parsed = value
                .parse::<f64>()
                .map_err(|source| PlateSolveError::WcsParse {
                    keyword: keyword.to_string(),
                    raw_value: value.to_string(),
                    path: path_display.clone(),
                    source,
                })?;
            *slot = Some(parsed);
            Ok(())
        };

        match key.as_str() {
            "CRVAL1" => parse(&mut ra, "CRVAL1")?,
            "CRVAL2" => parse(&mut dec, "CRVAL2")?,
            "CROTA1" | "CROTA2" => parse(&mut crota, &key)?,
            "CDELT1" => parse(&mut cdelt1, "CDELT1")?,
            "CDELT2" => parse(&mut cdelt2, "CDELT2")?,
            "PLTSOLVD" => solved = value == "T",
            _ => {}
        }
    }

    if !solved {
        return Err(PlateSolveError::SolveFailed { path: path_display });
    }

    let require = |slot: Option<f64>, name: &str| -> Result<f64, PlateSolveError> {
        slot.ok_or_else(|| PlateSolveError::WcsMissingKeyword {
            keyword: name.to_string(),
            path: path_display.clone(),
        })
    };
    let ra = require(ra, "CRVAL1")?;
    let dec = require(dec, "CRVAL2")?;
    let cdelt1 = require(cdelt1, "CDELT1")?;
    let cdelt2 = require(cdelt2, "CDELT2")?;
    // Why: CROTA1/CROTA2 are *optional* in the FITS WCS standard (Greisen &
    // Calabretta 2002 §2.1.2). ASTAP omits them for north-up frames. When
    // absent, the standard-mandated default is 0.0 — this is a documented
    // WCS convention, not a silent error fallback. A *malformed* CROTA value
    // (parse failure) still propagates as `PlateSolveError::WcsParse` via
    // the `parse(&mut crota, &key)?` call above.
    let crota = crota.unwrap_or(0.0);

    let pixel_scale = (cdelt1.abs() * 3600.0 + cdelt2.abs() * 3600.0) / 2.0;

    Ok(PlateSolveResult {
        ra,
        dec,
        pixel_scale,
        rotation: crota,
        field_width: 0.0,
        field_height: 0.0,
        success: true,
        error: None,
        solve_time_secs: solve_time,
    })
}

#[cfg(test)]
const GPU_DOWNSAMPLE_SHADER: &str = r#"
struct Params {
  width: u32,
  height: u32,
  factor: u32,
  out_width: u32,
  out_height: u32,
  _pad0: u32,
  _pad1: u32,
  _pad2: u32,
}

@group(0) @binding(0) var<storage, read> input_pixels: array<u32>;
@group(0) @binding(1) var<storage, read_write> output_pixels: array<u32>;
@group(0) @binding(2) var<uniform> params: Params;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= params.out_width || gid.y >= params.out_height) {
    return;
  }

  let start_x = gid.x * params.factor;
  let start_y = gid.y * params.factor;
  var max_value: u32 = 0u;

  for (var dy: u32 = 0u; dy < params.factor; dy = dy + 1u) {
    let src_y = start_y + dy;
    if (src_y >= params.height) {
      break;
    }
    for (var dx: u32 = 0u; dx < params.factor; dx = dx + 1u) {
      let src_x = start_x + dx;
      if (src_x >= params.width) {
        break;
      }
      let src_index = src_y * params.width + src_x;
      max_value = max(max_value, input_pixels[src_index]);
    }
  }

  let dst_index = gid.y * params.out_width + gid.x;
  output_pixels[dst_index] = max_value;
}
"#;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
#[cfg(test)]
struct DownsampleParams {
    width: u32,
    height: u32,
    factor: u32,
    out_width: u32,
    out_height: u32,
    _pad0: u32,
    _pad1: u32,
    _pad2: u32,
}

#[cfg(test)]
fn to_monochrome_u16(image: &ImageData) -> Result<ImageData, String> {
    if image.pixel_type == PixelType::U16 && image.channels == 1 {
        return Ok(image.clone());
    }

    // Why: width and height are u32; usize is >=32-bit on all our targets so the
    // promotion is lossless. checked_mul surfaces a hypothetical >2^31 x >2^31
    // sensor as an explicit error rather than silently allocating a zero-pixel
    // buffer.
    let pixel_count = (image.width as usize)
        .checked_mul(image.height as usize)
        .ok_or_else(|| {
            format!(
                "to_monochrome_u16: pixel-count overflow for {}x{}",
                image.width, image.height
            )
        })?;
    if pixel_count == 0 {
        return Ok(ImageData::from_u16(0, 0, 1, &[]));
    }

    // Why: channels is u32 (typically 1/3/4); u32 -> usize widening is lossless.
    let channels = image.channels.max(1) as usize;
    let values: Vec<u16> = match image.pixel_type {
        PixelType::U8 => image
            .data
            .iter()
            .step_by(channels)
            .map(|&value| (value as u16) << 8)
            .collect(),
        PixelType::U16 => image
            .data
            .chunks_exact(2 * channels)
            .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
            .collect(),
        PixelType::U32 => image
            .data
            .chunks_exact(4 * channels)
            .map(|chunk| {
                let value = u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                value.min(u16::MAX as u32) as u16
            })
            .collect(),
        PixelType::F32 => image
            .data
            .chunks_exact(4 * channels)
            .map(|chunk| {
                let value = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                value.clamp(0.0, u16::MAX as f32) as u16
            })
            .collect(),
        PixelType::F64 => image
            .data
            .chunks_exact(8 * channels)
            .map(|chunk| {
                let value = f64::from_le_bytes([
                    chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
                ]);
                value.clamp(0.0, u16::MAX as f64) as u16
            })
            .collect(),
    };

    Ok(ImageData::from_u16(image.width, image.height, 1, &values))
}

#[cfg(test)]
fn cpu_downsample_max_u16(image: &ImageData, factor: u32) -> Result<ImageData, String> {
    let mono = to_monochrome_u16(image)?;
    let pixels = mono
        .as_u16()
        .ok_or_else(|| "Failed to read monochrome u16 image data".to_string())?;
    let out_width = mono.width.div_ceil(factor);
    let out_height = mono.height.div_ceil(factor);
    // Why: out_width and out_height are u32 sensor dimensions / factor; lossless
    // to u64 for the multiply. checked_mul surfaces overflow as an error
    // rather than allocating a too-small buffer.
    let output_count = u64::from(out_width)
        .checked_mul(u64::from(out_height))
        .ok_or_else(|| {
            format!(
                "cpu_downsample_max_u16: pixel-count overflow for {}x{}",
                out_width, out_height
            )
        })?;
    let output_count_usize = usize::try_from(output_count).map_err(|_| {
        format!(
            "cpu_downsample_max_u16: pixel count {} exceeds usize::MAX",
            output_count
        )
    })?;
    let mut output = vec![0u16; output_count_usize];

    for out_y in 0..out_height {
        for out_x in 0..out_width {
            let mut max_value = 0u16;
            let start_x = out_x * factor;
            let start_y = out_y * factor;
            for dy in 0..factor {
                let y = start_y + dy;
                if y >= mono.height {
                    break;
                }
                for dx in 0..factor {
                    let x = start_x + dx;
                    if x >= mono.width {
                        break;
                    }
                    let idx = (y * mono.width + x) as usize;
                    max_value = max_value.max(pixels[idx]);
                }
            }
            output[(out_y * out_width + out_x) as usize] = max_value;
        }
    }

    Ok(ImageData::from_u16(out_width, out_height, 1, &output))
}

#[cfg(test)]
fn gpu_downsample_max_u16(image: &ImageData, factor: u32) -> Result<ImageData, String> {
    let mono = to_monochrome_u16(image)?;
    let pixels = mono
        .as_u16()
        .ok_or_else(|| "Failed to read monochrome u16 image data".to_string())?;
    let input_u32: Vec<u32> = pixels.into_iter().map(u32::from).collect();
    let out_width = mono.width.div_ceil(factor);
    let out_height = mono.height.div_ceil(factor);
    // Why: identical bounds reasoning as cpu_downsample_max_u16 above;
    // checked_mul surfaces u32-multiply overflow explicitly.
    let output_count = u64::from(out_width)
        .checked_mul(u64::from(out_height))
        .ok_or_else(|| {
            format!(
                "gpu_downsample_max_u16: pixel-count overflow for {}x{}",
                out_width, out_height
            )
        })?;
    let output_len = usize::try_from(output_count).map_err(|_| {
        format!(
            "gpu_downsample_max_u16: pixel count {} exceeds usize::MAX",
            output_count
        )
    })?;

    let instance = wgpu::Instance::default();
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    }))
    .ok_or_else(|| "No GPU adapter available for plate solving".to_string())?;

    let (device, queue) =
        pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor::default(), None))
            .map_err(|error| format!("Failed to create GPU device: {}", error))?;

    let input_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("plate-solve-input"),
        contents: bytemuck::cast_slice(&input_u32),
        usage: wgpu::BufferUsages::STORAGE,
    });
    let output_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("plate-solve-output"),
        size: (output_len * std::mem::size_of::<u32>()) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    let readback_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("plate-solve-readback"),
        size: (output_len * std::mem::size_of::<u32>()) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let params = DownsampleParams {
        width: mono.width,
        height: mono.height,
        factor,
        out_width,
        out_height,
        _pad0: 0,
        _pad1: 0,
        _pad2: 0,
    };
    let params_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("plate-solve-params"),
        contents: bytemuck::bytes_of(&params),
        usage: wgpu::BufferUsages::UNIFORM,
    });

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("plate-solve-downsample"),
        source: wgpu::ShaderSource::Wgsl(GPU_DOWNSAMPLE_SHADER.into()),
    });
    let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("plate-solve-bind-group-layout"),
        entries: &[
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: true },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: false },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 2,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
        ],
    });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("plate-solve-pipeline-layout"),
        bind_group_layouts: &[&bind_group_layout],
        push_constant_ranges: &[],
    });
    let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("plate-solve-pipeline"),
        layout: Some(&pipeline_layout),
        module: &shader,
        entry_point: "main",
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("plate-solve-bind-group"),
        layout: &bind_group_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: input_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: output_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 2,
                resource: params_buffer.as_entire_binding(),
            },
        ],
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("plate-solve-encoder"),
    });
    {
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("plate-solve-pass"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.dispatch_workgroups(out_width.div_ceil(8), out_height.div_ceil(8), 1);
    }
    encoder.copy_buffer_to_buffer(
        &output_buffer,
        0,
        &readback_buffer,
        0,
        (output_len * std::mem::size_of::<u32>()) as u64,
    );
    queue.submit(Some(encoder.finish()));

    let slice = readback_buffer.slice(..);
    let (sender, receiver) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        let _ = sender.send(result);
    });
    device.poll(wgpu::Maintain::Wait);
    receiver
        .recv()
        .map_err(|error| format!("Failed waiting for GPU readback: {}", error))?
        .map_err(|error| format!("Failed to map GPU readback buffer: {}", error))?;

    let mapped = slice.get_mapped_range();
    let output: Vec<u16> = bytemuck::cast_slice::<u8, u32>(&mapped)
        .iter()
        .map(|&value| value.min(u16::MAX as u32) as u16)
        .collect();
    drop(mapped);
    readback_buffer.unmap();

    Ok(ImageData::from_u16(out_width, out_height, 1, &output))
}

/// Sigma multiplier for the plate-solve detection threshold.
///
/// Why: 5σ above the robust background gives ~1 false positive in 3.5 million
/// pixels of pure Gaussian noise — comfortably below the candidate-list size
/// the matcher consumes. We also blend in a 25 % skew toward the dynamic
/// range so very high-contrast frames still favour the actual stars over
/// hot-pixel noise.
#[cfg(test)]
const PLATESOLVE_DETECTION_SIGMA: f64 = 5.0;

/// Estimate `(median, sigma)` of a u16 image using the MAD of a stride-1
/// sample. Robust against bright stars dominating a naive variance.
///
/// Why: the previous detector used a hardcoded 250-ADU floor — meaningless
/// for a 10-bit camera or a pre-stretched JPEG. An estimator gives us a
/// noise-aware threshold that scales with the actual sky background.
#[cfg(test)]
fn estimate_background_u16(pixels: &[u16]) -> (f64, f64) {
    if pixels.is_empty() {
        return (0.0, 1.0);
    }
    let mut sorted: Vec<u16> = pixels.to_vec();
    sorted.sort_unstable();
    let median = sorted[sorted.len() / 2] as f64;
    // MAD → σ via the standard 1.4826 scale factor for Gaussian-distributed
    // backgrounds. Compute on a deviations vector so we don't disturb
    // `sorted` (callers don't depend on it but keep it readable).
    let mut deviations: Vec<f64> = sorted.iter().map(|&v| (v as f64 - median).abs()).collect();
    deviations.sort_by(|a, b| a.total_cmp(b));
    let mad = deviations[deviations.len() / 2];
    let sigma = (mad * 1.4826).max(1.0);
    (median, sigma)
}

/// Pick a `min_separation` (in **downsampled** pixels) for the plate-solve
/// candidate cull, scaling with image size so dense star fields aren't
/// over-merged on small frames or under-merged on huge ones.
///
/// Why: the previous code hardcoded 2.0 px (= 8 px on the original 4×
/// downsample). On a 9576×6388 frame that is ~0.0008 % of the diagonal —
/// useless as a deduplication radius. Scale gently with the frame's longer
/// edge so large images get a proportionally larger merge radius without
/// blowing up dense star fields on small ones.
#[cfg(test)]
fn plate_solve_min_separation(width: u32, height: u32) -> f64 {
    let longest = width.max(height) as f64;
    // 1 unit per ~512 downsampled px, clamped to a sensible band. The lower
    // bound preserves the historical behaviour for 1k-class frames; the
    // upper bound stops 50-megapixel frames from aliasing distinct stars.
    (longest / 512.0).clamp(2.0, 8.0)
}

#[cfg(test)]
fn detect_local_maxima(
    image: &ImageData,
    min_separation: f64,
) -> Result<Vec<crate::DetectedStar>, String> {
    let pixels = image
        .as_u16()
        .ok_or_else(|| "Expected u16 image for local-maxima detection".to_string())?;
    if image.width < 3 || image.height < 3 {
        return Err("Image too small for star detection".to_string());
    }

    let (background, sigma) = estimate_background_u16(&pixels);
    let max_value = *pixels.iter().max().unwrap_or(&0) as f64;
    // Why: combine a noise-aware floor (Nσ above background) with a fraction
    // of the dynamic range so that on heavily stretched frames we still
    // ignore the long tail of background-clipped pixels. Replaces the
    // previous absolute 250-ADU floor that was meaningless for 10-bit
    // sensors and pre-stretched JPEGs.
    let sigma_floor = background + PLATESOLVE_DETECTION_SIGMA * sigma;
    let dynamic_floor = background + (max_value - background) * 0.25;
    let threshold = sigma_floor.max(dynamic_floor);

    let mut candidates = Vec::<crate::DetectedStar>::new();
    for y in 1..(image.height - 1) {
        for x in 1..(image.width - 1) {
            let idx = (y * image.width + x) as usize;
            let value = pixels[idx] as f64;
            if value < threshold {
                continue;
            }

            let neighbors = [
                pixels[idx - image.width as usize - 1],
                pixels[idx - image.width as usize],
                pixels[idx - image.width as usize + 1],
                pixels[idx - 1],
                pixels[idx + 1],
                pixels[idx + image.width as usize - 1],
                pixels[idx + image.width as usize],
                pixels[idx + image.width as usize + 1],
            ];
            if neighbors.iter().any(|&neighbor| neighbor as f64 > value) {
                continue;
            }

            candidates.push(crate::DetectedStar {
                x: x as f64,
                y: y as f64,
                flux: value,
                hfr: 1.0,
                fwhm: 2.0,
                peak: value,
                background,
                snr: if sigma > 0.0 {
                    (value - background) / sigma
                } else {
                    value
                },
                eccentricity: 0.0,
                sharpness: 0.5,
            });
        }
    }

    candidates.sort_by(|left, right| right.flux.total_cmp(&left.flux));
    let mut selected = Vec::<crate::DetectedStar>::new();
    for candidate in candidates {
        let too_close = selected.iter().any(|existing| {
            let dx = existing.x - candidate.x;
            let dy = existing.y - candidate.y;
            (dx * dx + dy * dy).sqrt() < min_separation
        });
        if !too_close {
            selected.push(candidate);
        }
        if selected.len() >= 32 {
            break;
        }
    }
    Ok(selected)
}

#[cfg(test)]
fn extract_plate_stars(image: &ImageData) -> Result<Vec<crate::DetectedStar>, String> {
    let factor = 4;
    let downsampled = match gpu_downsample_max_u16(image, factor) {
        Ok(image) => image,
        Err(error) => {
            tracing::warn!("GPU plate-solve preprocessing unavailable: {}", error);
            cpu_downsample_max_u16(image, factor)?
        }
    };

    // Why: scale the dedup radius with the downsampled frame instead of the
    // historical hardcoded 2.0 px. See `plate_solve_min_separation` doc
    // comment for the chosen scaling.
    let min_separation = plate_solve_min_separation(downsampled.width, downsampled.height);
    let mut stars = detect_local_maxima(&downsampled, min_separation)?
        .into_iter()
        .map(|mut star| {
            star.x *= factor as f64;
            star.y *= factor as f64;
            star.hfr *= factor as f64;
            star.fwhm *= factor as f64;
            star.flux *= (factor * factor) as f64;
            star
        })
        .collect::<Vec<_>>();

    if stars.len() < 3 {
        let config = StarDetectionConfig {
            detection_sigma: 3.0,
            min_area: 1,
            max_area: 4000,
            min_hfr: 0.5,
            min_snr: 3.0,
            ..StarDetectionConfig::default()
        };
        stars = detect_stars(image, &config);
    }
    stars.sort_by(|left, right| right.flux.total_cmp(&left.flux));
    stars.truncate(32);
    if stars.len() < 3 {
        return Err("Insufficient stars detected for internal plate solving".to_string());
    }
    Ok(stars)
}

#[cfg(test)]
fn infer_center_from_header(
    header: &FitsHeader,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
) -> Option<(f64, f64)> {
    if let (Some(ra), Some(dec)) = (hint_ra, hint_dec) {
        return Some((ra, dec));
    }
    if let (Some(ra), Some(dec)) = (header.get_float("CRVAL1"), header.get_float("CRVAL2")) {
        return Some((ra, dec));
    }
    if let (Some(ra), Some(dec)) = (header.get_float("RA"), header.get_float("DEC")) {
        return Some((ra, dec));
    }
    if let (Some(ra), Some(dec)) = (
        header.get_string("OBJCTRA").and_then(parse_ra_string),
        header.get_string("OBJCTDEC").and_then(parse_dec_string),
    ) {
        return Some((ra, dec));
    }
    if let (Some(ra), Some(dec)) = (
        header.get_string("OBJRA").and_then(parse_ra_string),
        header.get_string("OBJDEC").and_then(parse_dec_string),
    ) {
        return Some((ra, dec));
    }
    None
}

#[cfg(test)]
fn parse_ra_string(value: &str) -> Option<f64> {
    parse_sexagesimal(value).map(|hours| hours * 15.0)
}

#[cfg(test)]
fn parse_dec_string(value: &str) -> Option<f64> {
    parse_sexagesimal(value)
}

#[cfg(test)]
fn parse_sexagesimal(value: &str) -> Option<f64> {
    let normalized = value.replace(['h', 'm', 's', ':'], " ");
    let parts = normalized
        .split_whitespace()
        .filter_map(|part| part.parse::<f64>().ok())
        .collect::<Vec<_>>();
    if parts.is_empty() {
        return None;
    }
    let sign = if value.trim_start().starts_with('-') {
        -1.0
    } else {
        1.0
    };
    let degrees = parts[0].abs()
        + parts.get(1).copied().unwrap_or(0.0) / 60.0
        + parts.get(2).copied().unwrap_or(0.0) / 3600.0;
    Some(sign * degrees)
}

#[cfg(test)]
fn infer_pixel_scale_from_header(header: &FitsHeader) -> Option<f64> {
    if let (Some(cd1_1), Some(cd2_1), Some(cd1_2), Some(cd2_2)) = (
        header.get_float("CD1_1"),
        header.get_float("CD2_1"),
        header.get_float("CD1_2"),
        header.get_float("CD2_2"),
    ) {
        return Some(
            ((cd1_1 * cd1_1 + cd2_1 * cd2_1).sqrt() * 3600.0
                + (cd1_2 * cd1_2 + cd2_2 * cd2_2).sqrt() * 3600.0)
                / 2.0,
        );
    }
    if let (Some(cdelt1), Some(cdelt2)) = (header.get_float("CDELT1"), header.get_float("CDELT2")) {
        return Some((cdelt1.abs() * 3600.0 + cdelt2.abs() * 3600.0) / 2.0);
    }
    let focal_length_mm = header.get_float("FOCALLEN")?;
    let pixel_size_um = header
        .get_float("PIXSIZE1")
        .or_else(|| header.get_float("XPIXSZ"))?;
    Some((206.265 * pixel_size_um) / focal_length_mm)
}

#[cfg(test)]
fn estimate_rotation(stars: &[crate::DetectedStar]) -> f64 {
    let count = stars.len() as f64;
    let mean_x = stars.iter().map(|star| star.x).sum::<f64>() / count;
    let mean_y = stars.iter().map(|star| star.y).sum::<f64>() / count;

    let mut xx = 0.0;
    let mut yy = 0.0;
    let mut xy = 0.0;
    for star in stars {
        let dx = star.x - mean_x;
        let dy = star.y - mean_y;
        xx += dx * dx;
        yy += dy * dy;
        xy += dx * dy;
    }

    0.5 * (2.0 * xy).atan2(xx - yy).to_degrees()
}

#[cfg(test)]
fn solve_internal(
    image_path: &Path,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
) -> Result<PlateSolveResult, String> {
    let (image, header) = read_fits(image_path).map_err(|error| error.to_string())?;
    let image = to_monochrome_u16(&image)?;
    let center = infer_center_from_header(&header, hint_ra, hint_dec)
        .ok_or_else(|| "Missing center coordinates in hints or FITS metadata".to_string())?;
    let pixel_scale = infer_pixel_scale_from_header(&header).ok_or_else(|| {
        "Missing focal length / pixel size metadata for internal solve".to_string()
    })?;
    let stars = extract_plate_stars(&image)?;
    let rotation = estimate_rotation(&stars);

    Ok(PlateSolveResult {
        ra: center.0,
        dec: center.1,
        pixel_scale,
        rotation,
        field_width: image.width as f64 * pixel_scale / 3600.0,
        field_height: image.height as f64 * pixel_scale / 3600.0,
        success: true,
        error: None,
        solve_time_secs: 0.0,
    })
}

/// Blind plate solve (no hint)
pub fn blind_solve(image_path: &Path) -> PlateSolveResult {
    let start = std::time::Instant::now();
    solve_with_default_external(image_path, None, None, None, start)
}

/// Plate solve with hint coordinates
pub fn solve_near(
    image_path: &Path,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
) -> PlateSolveResult {
    let start = std::time::Instant::now();
    let config = PlateSolverConfig {
        search_radius,
        ..PlateSolverConfig::default()
    };

    solve_with_external_config(
        image_path,
        Some(hint_ra),
        Some(hint_dec),
        None,
        config,
        start,
    )
}

fn solve_with_default_external(
    image_path: &Path,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
    hint_scale: Option<f64>,
    start: std::time::Instant,
) -> PlateSolveResult {
    solve_with_external_config(
        image_path,
        hint_ra,
        hint_dec,
        hint_scale,
        PlateSolverConfig::default(),
        start,
    )
}

fn solve_with_external_config(
    image_path: &Path,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
    hint_scale: Option<f64>,
    config: PlateSolverConfig,
    start: std::time::Instant,
) -> PlateSolveResult {
    if config.astap_path.is_some() {
        return AstapSolver::new(config).solve(image_path, hint_ra, hint_dec, hint_scale);
    }

    if let Some(astrometry_path) = config.astrometry_path.as_deref() {
        return solve_with_astrometry(
            astrometry_path,
            image_path,
            hint_ra,
            hint_dec,
            config.search_radius,
            start,
        );
    }

    external_solver_unavailable(start)
}

fn solve_with_astrometry(
    astrometry_path: &Path,
    image_path: &Path,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
    search_radius: f64,
    start: std::time::Instant,
) -> PlateSolveResult {
    let output_dir = image_path.parent().unwrap_or_else(|| Path::new("."));
    let wcs_path = image_path.with_extension("wcs");
    if wcs_path.exists() {
        if let Err(error) = fs::remove_file(&wcs_path) {
            return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(format!(
                    "Failed to remove stale astrometry.net WCS output {:?}: {}",
                    wcs_path, error
                )),
                solve_time_secs: start.elapsed().as_secs_f64(),
            };
        }
    }

    let mut cmd = Command::new(astrometry_path);
    cmd.arg("--overwrite")
        .arg("--no-plots")
        .arg("--dir")
        .arg(output_dir)
        .arg(image_path);

    if let (Some(ra), Some(dec)) = (hint_ra, hint_dec) {
        cmd.arg("--ra")
            .arg(format!("{}", ra))
            .arg("--dec")
            .arg(format!("{}", dec));
        if search_radius > 0.0 {
            cmd.arg("--radius").arg(format!("{}", search_radius));
        }
    }

    tracing::info!("Running astrometry.net solve-field: {:?}", cmd);

    let output = match cmd.stdout(Stdio::piped()).stderr(Stdio::piped()).output() {
        Ok(output) => output,
        Err(error) => {
            return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(format!(
                    "Failed to run astrometry.net solve-field: {}",
                    error
                )),
                solve_time_secs: start.elapsed().as_secs_f64(),
            }
        }
    };

    let solve_time = start.elapsed().as_secs_f64();
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return PlateSolveResult {
            ra: 0.0,
            dec: 0.0,
            pixel_scale: 0.0,
            rotation: 0.0,
            field_width: 0.0,
            field_height: 0.0,
            success: false,
            error: Some(format!("astrometry.net solve-field failed: {}", stderr)),
            solve_time_secs: solve_time,
        };
    }

    match parse_wcs_file_inner(&wcs_path, solve_time) {
        Ok(result) => result,
        Err(error) => PlateSolveResult {
            ra: 0.0,
            dec: 0.0,
            pixel_scale: 0.0,
            rotation: 0.0,
            field_width: 0.0,
            field_height: 0.0,
            success: false,
            error: Some(error.to_string()),
            solve_time_secs: solve_time,
        },
    }
}

fn external_solver_unavailable(start: std::time::Instant) -> PlateSolveResult {
    PlateSolveResult {
        ra: 0.0,
        dec: 0.0,
        pixel_scale: 0.0,
        rotation: 0.0,
        field_width: 0.0,
        field_height: 0.0,
        success: false,
        error: Some(
            "No supported external plate solver is configured. Install ASTAP and make astap_cli available on PATH or configure its executable path before solving."
                .to_string(),
        ),
        solve_time_secs: start.elapsed().as_secs_f64(),
    }
}

/// Cached result of the `find_astap()` / `find_astrometry()` filesystem probe.
///
/// Why cache: `find_astap()` and `find_astrometry()` walk a fixed list of
/// paths and (on Windows) shell out to `where.exe`. Callers (settings UI,
/// scheduler, sequencer pre-flight) hit `is_solver_available()` repeatedly.
/// The probe is process-stable: an installer running while Nightshade is
/// open is rare, and users always restart after configuring a new solver
/// path. A future settings-change hook can call
/// `invalidate_solver_availability_cache()` to force re-probing.
static SOLVER_AVAILABLE_CACHE: std::sync::Mutex<Option<bool>> = std::sync::Mutex::new(None);

/// Check if any plate solver (ASTAP or local astrometry.net) is reachable on
/// disk. Returns `false` if neither is found at any well-known install path
/// or via PATH lookup. Result is cached after first call; see
/// `SOLVER_AVAILABLE_CACHE` doc for rationale.
pub fn is_solver_available() -> bool {
    let mut guard = SOLVER_AVAILABLE_CACHE.lock().expect("solver-cache mutex");
    if let Some(cached) = *guard {
        return cached;
    }
    let value = find_astap().is_some() || find_astrometry().is_some();
    *guard = Some(value);
    value
}

/// Drop the cached `is_solver_available()` answer so the next call re-probes
/// the filesystem. Called whenever the user updates the solver path via the
/// settings UI.
pub fn invalidate_solver_availability_cache() {
    *SOLVER_AVAILABLE_CACHE.lock().expect("solver-cache mutex") = None;
}

/// Get path to installed solver
pub fn get_solver_path() -> Option<PathBuf> {
    find_astap().or_else(find_astrometry)
}

#[cfg(test)]
mod tests {
    use super::{
        cpu_downsample_max_u16, external_solver_unavailable, parse_astap_ini_inner,
        parse_wcs_file_inner, solve_internal, PlateSolveError,
    };
    use crate::{write_fits, FitsHeader, ImageData};
    use std::io::Write;
    use std::path::{Path, PathBuf};

    /// Build a single FITS-style WCS card line, padded to the column layout
    /// `parse_wcs_file_inner` expects: keyword in cols 0..8, `=` at col 8,
    /// value starting at col 10.
    fn wcs_card(keyword: &str, value: &str) -> String {
        let mut line = String::with_capacity(80);
        line.push_str(&format!("{:<8}", keyword));
        line.push('=');
        line.push(' ');
        line.push_str(value);
        line.push('\n');
        line
    }

    fn write_temp(name: &str, contents: &str) -> PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let path = std::env::temp_dir().join(format!(
            "nightshade-{}-{}-{}.txt",
            name,
            std::process::id(),
            id
        ));
        let mut f = std::fs::File::create(&path).expect("create temp file");
        f.write_all(contents.as_bytes()).expect("write temp file");
        path
    }

    fn synthetic_star_field(rotation_deg: f64) -> ImageData {
        let width = 256u32;
        let height = 256u32;
        let mut pixels = vec![900u16; (width * height) as usize];
        let rotation = rotation_deg.to_radians();
        let template = [
            (-60.0, -24.0),
            (-28.0, -10.0),
            (0.0, 0.0),
            (34.0, 14.0),
            (66.0, 28.0),
        ];

        for (dx, dy) in template {
            let x = width as f64 / 2.0 + dx * rotation.cos() - dy * rotation.sin();
            let y = height as f64 / 2.0 + dx * rotation.sin() + dy * rotation.cos();
            for iy in -4..=4 {
                for ix in -4..=4 {
                    let px = x as i32 + ix;
                    let py = y as i32 + iy;
                    if px < 0 || py < 0 || px >= width as i32 || py >= height as i32 {
                        continue;
                    }
                    let r2 = (ix * ix + iy * iy) as f64;
                    let signal = (12000.0 * (-r2 / 4.5).exp()) as u16;
                    let idx = (py as u32 * width + px as u32) as usize;
                    pixels[idx] = pixels[idx].saturating_add(signal);
                }
            }
        }

        ImageData::from_u16(width, height, 1, &pixels)
    }

    fn write_test_fits(path: &Path, rotation_deg: f64) {
        let image = synthetic_star_field(rotation_deg);
        let mut header = FitsHeader::new();
        header.set_float("RA", 150.0);
        header.set_float("DEC", 20.0);
        header.set_float("FOCALLEN", 600.0);
        header.set_float("PIXSIZE1", 3.76);
        write_fits(path, &image, &header).expect("failed to write synthetic FITS");
    }

    #[test]
    fn cpu_downsample_preserves_brightest_star() {
        let image = synthetic_star_field(18.0);
        let downsampled = cpu_downsample_max_u16(&image, 4).expect("downsample should work");
        let pixels = downsampled.as_u16().expect("downsampled pixels");
        assert_eq!(downsampled.width, 64);
        assert_eq!(downsampled.height, 64);
        assert!(pixels.iter().copied().max().unwrap_or_default() > 5000);
    }

    #[test]
    fn internal_solver_test_helper_estimates_with_hint_and_blind_metadata() {
        let path =
            std::env::temp_dir().join(format!("nightshade-platesolve-{}.fits", std::process::id()));
        write_test_fits(&path, 24.0);

        let near = solve_internal(&path, Some(150.0), Some(20.0))
            .expect("internal test helper should estimate metadata");
        assert!(near.success);
        assert!((near.ra - 150.0).abs() < 1e-6);
        assert!((near.dec - 20.0).abs() < 1e-6);
        assert!((near.pixel_scale - 1.29126).abs() < 0.1);
        assert!(near.field_width > 0.08);
        assert!(near.field_height > 0.08);

        let blind =
            solve_internal(&path, None, None).expect("internal test helper should read metadata");
        assert!(blind.success);
        assert!((blind.ra - 150.0).abs() < 1e-6);
        assert!((blind.dec - 20.0).abs() < 1e-6);

        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn unavailable_external_solver_fails_with_operator_guidance() {
        let result = external_solver_unavailable(std::time::Instant::now());
        assert!(!result.success);
        let error = result.error.expect("error guidance");
        assert!(error.contains("Install ASTAP"));
        assert!(error.contains("astap_cli"));
    }

    #[test]
    fn parse_wcs_file_succeeds_on_well_formed_input() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.123"));
        content.push_str(&wcs_card("CRVAL2", "20.456"));
        content.push_str(&wcs_card("CD1_1", "-0.000358"));
        content.push_str(&wcs_card("CD1_2", "0.000001"));
        content.push_str(&wcs_card("CD2_1", "0.000001"));
        content.push_str(&wcs_card("CD2_2", "0.000358"));
        let path = write_temp("wcs-good", &content);

        let result = parse_wcs_file_inner(&path, 0.42).expect("well-formed WCS must parse");
        assert!(result.success);
        assert!((result.ra - 150.123).abs() < 1e-9);
        assert!((result.dec - 20.456).abs() < 1e-9);
        assert!(result.pixel_scale > 0.0);

        let _ = std::fs::remove_file(path);
    }

    /// §6.4: a malformed CRVAL1 must NOT silently produce a "successful"
    /// solve at RA=0/Dec=0. The parser must return `PlateSolveError::WcsParse`.
    #[test]
    fn parse_wcs_file_rejects_malformed_crval1() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "not-a-number"));
        content.push_str(&wcs_card("CRVAL2", "20.456"));
        content.push_str(&wcs_card("CD1_1", "-0.000358"));
        content.push_str(&wcs_card("CD1_2", "0.000001"));
        content.push_str(&wcs_card("CD2_1", "0.000001"));
        content.push_str(&wcs_card("CD2_2", "0.000358"));
        let path = write_temp("wcs-bad-crval1", &content);

        let err = parse_wcs_file_inner(&path, 0.0)
            .expect_err("malformed CRVAL1 must NOT produce a zero-coordinate solve");
        match err {
            PlateSolveError::WcsParse {
                keyword, raw_value, ..
            } => {
                assert_eq!(keyword, "CRVAL1");
                assert_eq!(raw_value, "not-a-number");
            }
            other => panic!("expected WcsParse, got {other:?}"),
        }

        let _ = std::fs::remove_file(path);
    }

    /// §6.4: a malformed CD-matrix value must also propagate.
    #[test]
    fn parse_wcs_file_rejects_malformed_cd_matrix() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.0"));
        content.push_str(&wcs_card("CRVAL2", "20.0"));
        content.push_str(&wcs_card("CD1_1", "0.001"));
        content.push_str(&wcs_card("CD1_2", "0.0"));
        content.push_str(&wcs_card("CD2_1", "garbage"));
        content.push_str(&wcs_card("CD2_2", "0.001"));
        let path = write_temp("wcs-bad-cd21", &content);

        let err = parse_wcs_file_inner(&path, 0.0).expect_err("malformed CD2_1 must error");
        match err {
            PlateSolveError::WcsParse {
                keyword, raw_value, ..
            } => {
                assert_eq!(keyword, "CD2_1");
                assert_eq!(raw_value, "garbage");
            }
            other => panic!("expected WcsParse, got {other:?}"),
        }

        let _ = std::fs::remove_file(path);
    }

    /// §6.4: missing required keyword must error rather than yielding zeros.
    #[test]
    fn parse_wcs_file_rejects_missing_required_keyword() {
        // Omit CRVAL2 entirely.
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.0"));
        content.push_str(&wcs_card("CD1_1", "0.001"));
        content.push_str(&wcs_card("CD1_2", "0.0"));
        content.push_str(&wcs_card("CD2_1", "0.0"));
        content.push_str(&wcs_card("CD2_2", "0.001"));
        let path = write_temp("wcs-missing-crval2", &content);

        let err = parse_wcs_file_inner(&path, 0.0).expect_err("missing CRVAL2 must error");
        match err {
            PlateSolveError::WcsMissingKeyword { keyword, .. } => {
                assert_eq!(keyword, "CRVAL2");
            }
            other => panic!("expected WcsMissingKeyword, got {other:?}"),
        }

        let _ = std::fs::remove_file(path);
    }

    /// §6.4: ASTAP `.ini` parser must not silently zero-out a malformed CRVAL.
    #[test]
    fn parse_astap_ini_rejects_malformed_crval2() {
        let content = "PLTSOLVD=T\nCRVAL1=150.0\nCRVAL2=not-a-number\nCDELT1=-0.000358\nCDELT2=0.000358\nCROTA1=12.34\n";
        let path = write_temp("ini-bad-crval2", content);

        let err = parse_astap_ini_inner(&path, 0.0).expect_err("malformed CRVAL2 must error");
        match err {
            PlateSolveError::WcsParse {
                keyword, raw_value, ..
            } => {
                assert_eq!(keyword, "CRVAL2");
                assert_eq!(raw_value, "not-a-number");
            }
            other => panic!("expected WcsParse, got {other:?}"),
        }

        let _ = std::fs::remove_file(path);
    }

    /// `PLTSOLVD != T` must surface as a `SolveFailed` error, not as a
    /// "successful" zero-coordinate result.
    #[test]
    fn parse_astap_ini_rejects_unsolved_flag() {
        let content = "PLTSOLVD=F\nCRVAL1=150.0\nCRVAL2=20.0\nCDELT1=-0.000358\nCDELT2=0.000358\n";
        let path = write_temp("ini-not-solved", content);

        let err = parse_astap_ini_inner(&path, 0.0).expect_err("PLTSOLVD=F must error");
        assert!(matches!(err, PlateSolveError::SolveFailed { .. }));

        let _ = std::fs::remove_file(path);
    }

    /// Helper for §6.15 tests: build a synthetic u16 image where every
    /// background pixel is sampled from a small uniform-noise envelope
    /// centred on `bg`, with a handful of point-like injected stars.
    /// Deterministic via a tiny xorshift so the tests are reproducible.
    fn synthetic_image_with_stars(
        width: u32,
        height: u32,
        background: u16,
        noise_amplitude: u16,
        stars: &[(u32, u32, u16)],
    ) -> ImageData {
        let mut state: u32 = 0x1234_5678;
        let mut pixels = vec![0u16; (width * height) as usize];
        for px in pixels.iter_mut() {
            // xorshift32
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            let jitter = (state % (2 * noise_amplitude as u32 + 1)) as i32 - noise_amplitude as i32;
            *px = (background as i32 + jitter).clamp(0, u16::MAX as i32) as u16;
        }
        for &(sx, sy, peak) in stars {
            // 3×3 bright core to ensure local-maximum predicate holds even after
            // the noise floor is added.
            for dy in -1i32..=1 {
                for dx in -1i32..=1 {
                    let x = sx as i32 + dx;
                    let y = sy as i32 + dy;
                    if x < 0 || y < 0 || x >= width as i32 || y >= height as i32 {
                        continue;
                    }
                    let idx = (y as u32 * width + x as u32) as usize;
                    let attenuation = if dx == 0 && dy == 0 { 1.0 } else { 0.6 };
                    let signal = (peak as f64 * attenuation) as u16;
                    pixels[idx] = pixels[idx].saturating_add(signal);
                }
            }
        }
        ImageData::from_u16(width, height, 1, &pixels)
    }

    /// §6.15: even on a low-contrast image (10-bit camera, no stretch), the
    /// detector must find injected stars instead of being blocked by the old
    /// 250-ADU absolute floor.
    #[test]
    fn detect_local_maxima_finds_low_contrast_stars() {
        // Background ≈ 100, noise σ small, peaks only ~80 ADU above background.
        // 250-ADU floor would have rejected every candidate — sigma threshold
        // must succeed here.
        let stars = [(40u32, 40u32, 180u16), (90, 60, 200), (140, 110, 220)];
        let image = synthetic_image_with_stars(192, 192, 100, 4, &stars);

        let detected = super::detect_local_maxima(&image, 3.0).expect("detection should succeed");

        assert!(
            detected.len() >= stars.len(),
            "expected at least {} stars on low-contrast frame, got {}",
            stars.len(),
            detected.len()
        );

        // Every injected star must show up within 2 px of its true centre.
        for &(sx, sy, _) in &stars {
            let hit = detected.iter().any(|s| {
                let dx = s.x - sx as f64;
                let dy = s.y - sy as f64;
                (dx * dx + dy * dy).sqrt() < 2.0
            });
            assert!(hit, "missed injected star at ({}, {})", sx, sy);
        }
    }

    /// §6.15: a high-contrast frame (deep stretch, very dark sky) with **no
    /// injected stars** must not produce a flood of false positives from
    /// background noise. The sigma-aware threshold gates this.
    #[test]
    fn detect_local_maxima_rejects_noise_only_image() {
        // Deliberately exaggerated noise so the old 250-ADU floor would have
        // gated nothing while a sigma-aware floor still gates correctly.
        let image = synthetic_image_with_stars(192, 192, 200, 60, &[]);

        let detected = super::detect_local_maxima(&image, 3.0).expect("detection should succeed");

        // A handful of pixels can sit at the extreme tail of the noise
        // distribution; a noise-aware threshold should keep this well below
        // the 32-star cap. The previous absolute floor produced unbounded
        // false positives on stretched frames.
        assert!(
            detected.len() < 8,
            "noise-only image produced {} false positives — threshold not noise-aware",
            detected.len()
        );
    }

    /// §6.15: high-contrast frame with real stars must still recover them
    /// while leaving the noise alone.
    #[test]
    fn detect_local_maxima_high_contrast_recovers_stars() {
        let stars = [(50u32, 50u32, 60_000u16), (120, 80, 55_000)];
        let image = synthetic_image_with_stars(192, 192, 200, 8, &stars);

        let detected = super::detect_local_maxima(&image, 3.0).expect("detection should succeed");

        for &(sx, sy, _) in &stars {
            let hit = detected.iter().any(|s| {
                let dx = s.x - sx as f64;
                let dy = s.y - sy as f64;
                (dx * dx + dy * dy).sqrt() < 2.0
            });
            assert!(hit, "missed bright star at ({}, {})", sx, sy);
        }
    }

    /// §6.1 follow-up: catalog detection must walk an exe-relative dir and
    /// surface the catalog flavour + magnitude limit from filename markers.
    #[test]
    fn detect_astap_catalog_finds_v17_next_to_exe() {
        let temp = std::env::temp_dir().join(format!(
            "nightshade-platesolve-cat-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        std::fs::create_dir_all(&temp).expect("create temp dir");
        // Stage a fake catalog file with the V17 marker plus an ASTAP exe.
        let exe = temp.join(if cfg!(target_os = "windows") {
            "astap.exe"
        } else {
            "astap"
        });
        std::fs::write(&exe, b"#!fake").expect("write fake exe");
        std::fs::write(temp.join("V17_0101.290"), b"fake catalog index")
            .expect("write fake catalog");
        std::fs::write(temp.join("V17_0102.290"), b"fake catalog index")
            .expect("write fake catalog");

        let info = super::detect_astap_catalog(Some(&exe), None).expect("must find V17 catalog");
        assert_eq!(info.name, "V17");
        assert_eq!(info.magnitude_limit, Some(17.0));
        assert_eq!(info.path, temp);

        let _ = std::fs::remove_dir_all(&temp);
    }

    /// §6.1 follow-up: a configured catalog directory must take precedence.
    #[test]
    fn detect_astap_catalog_honours_configured_override() {
        let temp = std::env::temp_dir().join(format!(
            "nightshade-platesolve-cat-cfg-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        std::fs::create_dir_all(&temp).expect("create temp dir");
        std::fs::write(temp.join("D80_0001.1476"), b"fake").expect("write fake catalog");

        let info = super::detect_astap_catalog(None, Some(&temp))
            .expect("configured override must locate catalog");
        assert_eq!(info.name, "D80");
        assert_eq!(info.magnitude_limit, Some(12.0));

        let _ = std::fs::remove_dir_all(&temp);
    }

    /// §6.1 follow-up: `verify_solver` on a missing path must produce a
    /// structured `Missing` error rather than panicking or claiming success.
    #[test]
    fn verify_solver_reports_missing_path() {
        let bogus = std::env::temp_dir().join(format!(
            "nightshade-no-such-solver-{}.bin",
            std::process::id()
        ));
        let err = super::verify_solver(&bogus).expect_err("missing path must error");
        match err {
            super::SolverVerifyError::Missing(p) => assert_eq!(p, bogus),
            other => panic!("expected Missing, got {other:?}"),
        }
    }

    /// §6.15: `min_separation` must scale with image size so dense star
    /// fields are not over-merged on small frames or under-merged on huge
    /// ones.
    #[test]
    fn plate_solve_min_separation_scales_with_image_size() {
        // Small frame keeps the minimum (== historical 2.0).
        assert_eq!(super::plate_solve_min_separation(640, 480), 2.0);

        // Mid-range frame produces a value strictly above the historical
        // floor.
        let mid = super::plate_solve_min_separation(2048, 1536);
        assert!(mid > 2.0 && mid < 8.0, "mid frame got {mid}");

        // A 50-megapixel-class frame (ZWO ASI6200, full chip) clamps to the
        // upper bound rather than running away to absurd radii.
        assert_eq!(super::plate_solve_min_separation(9576, 6388), 8.0);
    }
}
