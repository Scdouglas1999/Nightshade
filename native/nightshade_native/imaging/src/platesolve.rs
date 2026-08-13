//! Real Plate Solving Integration
//!
//! Provides actual integration with plate solving software:
//! - ASTAP (Astrometric STAcking Program)
//! - Local Astrometry.net
//!
//! These are real implementations that call external solvers.
//!
//! # `as`-cast policy
//!
//! This module's numeric casts are all **SIP-coefficient index widening**
//! (`u32 as usize` over an order that `sip_layout` has already bounded), which
//! is lossless on every >=32-bit target. Sites with their own `Why:` comment
//! override the module-level reasoning.
//!
//! # `unwrap_or` policy
//!
//! Each `unwrap_or` site below maps to a specific external-solver edge case:
//!
//! * `output.status.code().unwrap_or(-1)` — on POSIX a subprocess killed by
//!   a signal has no exit code; `-1` is the documented sentinel surfaced to
//!   the FFI caller's `SolveResult.status` (treated as "solver crashed").
//! * `crota.unwrap_or(0.0)` — `CROTA2` is optional in the FITS WCS standard;
//!   zero rotation is the default North-Up orientation assumed when the
//!   solver omits the keyword.
//! * `output_dir.parent().unwrap_or_else(|| Path::new("."))` — root-path
//!   case for the temp/work directory; current-dir is the safe fallback.

mod platesolve_paths;

pub use platesolve_paths::CatalogInfo;
use platesolve_paths::{
    astap_candidates, astrometry_candidates, catalog_dir_candidates, first_existing,
    identify_catalog, AstapPathInputs, AstrometryPathInputs, CatalogSearchInputs, OsFamily, RealFs,
};

use std::fs;
use std::io::Read;
use std::num::ParseFloatError;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use thiserror::Error;
use wait_timeout::ChildExt;

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
#[derive(Debug, Clone, Default)]
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
    /// Raw CD matrix (deg/pixel) as read from the WCS — the full anisotropic
    /// transform. `pixel_scale`/`rotation` above are the isotropic collapse
    /// kept for backward compatibility. Zero when no WCS was parsed.
    pub cd1_1: f64,
    pub cd1_2: f64,
    pub cd2_1: f64,
    pub cd2_2: f64,
    /// SIP forward distortion order (`A_ORDER`/`B_ORDER`). Zero when absent.
    pub a_order: u32,
    pub b_order: u32,
    /// SIP forward coefficients in row-major `(i, j)` order: the slot for term
    /// `A_i_j` is at index `i * (order + 1) + j` (likewise `B_i_j`). Empty when
    /// no SIP keywords were present.
    pub a_coeffs: Vec<f64>,
    pub b_coeffs: Vec<f64>,
    /// SIP inverse distortion order (`AP_ORDER`/`BP_ORDER`). Zero when absent.
    pub ap_order: u32,
    pub bp_order: u32,
    /// SIP inverse coefficients, same row-major `(i, j)` layout as the forward
    /// terms. Empty when the inverse keywords were not present.
    pub ap_coeffs: Vec<f64>,
    pub bp_coeffs: Vec<f64>,
}

/// Plate solver configuration
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum PlateSolverChoice {
    #[default]
    Auto,
    Astap,
    Astrometry,
}

impl PlateSolverChoice {
    fn from_stored(value: Option<&str>) -> Self {
        match value {
            Some("astap") => Self::Astap,
            Some("astrometry") => Self::Astrometry,
            _ => Self::Auto,
        }
    }
}

#[derive(Debug, Clone)]
pub struct PlateSolverConfig {
    /// Path to ASTAP executable
    pub astap_path: Option<PathBuf>,
    /// Path to local astrometry.net solve-field
    pub astrometry_path: Option<PathBuf>,
    /// Directory containing ASTAP star catalog (.290 / .1476 files).
    /// Passed to ASTAP as `-d <dir>`. When `None` ASTAP must find the
    /// catalog in its own install directory; if it can't, it will fail
    /// with "no star database found".
    pub catalog_path: Option<PathBuf>,
    /// Search radius in degrees (0 = blind solve)
    pub search_radius: f64,
    /// Downsample factor for faster solving
    pub downsample: u32,
    /// Maximum time for solving in seconds
    pub timeout_secs: u32,
    /// User-selected solver. Auto tries ASTAP, then astrometry.net.
    pub solver_choice: PlateSolverChoice,
}

impl Default for PlateSolverConfig {
    fn default() -> Self {
        // Consult the process-global preference (set by `set_solver_preference`)
        // so every call site — blind_solve, solve_near, the sequencer, the
        // imaging auto-solve — honours whatever the user configured in Settings
        // → Plate Solving without any caller needing to pass the config
        // explicitly.
        let (configured_catalog, solver_choice) = {
            let pref = ACTIVE_SOLVER_PREF.read().expect("solver-pref RwLock");
            (pref.catalog_path.clone(), pref.solver_choice)
        };

        let discovered = discovered_solvers();

        Self {
            astap_path: discovered.astap,
            astrometry_path: discovered.astrometry,
            catalog_path: configured_catalog,
            search_radius: 10.0,
            downsample: 2,
            timeout_secs: 60,
            solver_choice,
        }
    }
}

/// Process-global solver preference set by `set_solver_preference()`.
///
/// Why a global: every call site that reaches `PlateSolverConfig::default()`
/// (`blind_solve`, `solve_near`, the sequencer centering, the imaging
/// auto-solve) lives deep in the call stack where there is no natural place to
/// thread a config parameter. A process-global is the established pattern for
/// this kind of cross-cutting preference (see `DISCOVERED_SOLVERS` below, which
/// caches what this preference resolves to). The `RwLock` permits concurrent
/// reads (the common case) and serialises the rare write.
#[derive(Default)]
struct SolverPref {
    astap_path: Option<PathBuf>,
    astrometry_path: Option<PathBuf>,
    catalog_path: Option<PathBuf>,
    solver_choice: PlateSolverChoice,
}

static ACTIVE_SOLVER_PREF: std::sync::RwLock<SolverPref> = std::sync::RwLock::new(SolverPref {
    astap_path: None,
    astrometry_path: None,
    catalog_path: None,
    solver_choice: PlateSolverChoice::Auto,
});

/// Update the process-global solver preference from the persisted user
/// settings. Must be called:
///   1. At startup, after loading `platesolver.json`.
///   2. Immediately after `api_platesolve_set_config` saves a new preference.
///
/// Empty strings in the input are treated as "no override" (auto-detect).
/// `catalog_path` is set directly — if the user left it blank the field is
/// `None` and no `-d` flag is passed to ASTAP (ASTAP then looks next to its
/// own binary, which is the correct behaviour when the catalog is co-located).
pub fn set_solver_preference(
    astap_path: Option<&str>,
    astrometry_path: Option<&str>,
    catalog_path: Option<&str>,
    solver_choice: Option<&str>,
) {
    let to_path =
        |s: Option<&str>| -> Option<PathBuf> { s.filter(|p| !p.is_empty()).map(PathBuf::from) };
    {
        let mut pref = ACTIVE_SOLVER_PREF.write().expect("solver-pref RwLock");
        pref.astap_path = to_path(astap_path);
        pref.astrometry_path = to_path(astrometry_path);
        pref.catalog_path = to_path(catalog_path);
        pref.solver_choice = PlateSolverChoice::from_stored(solver_choice);
    }
    // The pref write guard is released first: `discovered_solvers` takes
    // DISCOVERED_SOLVERS then ACTIVE_SOLVER_PREF, so invalidating while still
    // holding the pref lock would invert the order and can deadlock.
    invalidate_solver_availability_cache();
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

/// The resolved solver locations for the current `ACTIVE_SOLVER_PREF`.
#[derive(Clone)]
struct DiscoveredSolvers {
    astap: Option<PathBuf>,
    astrometry: Option<PathBuf>,
}

/// Cached result of the ASTAP / astrometry.net filesystem probe.
///
/// Why cache: a miss stats a per-OS candidate list and, when nothing matches,
/// shells out to `which`/`where` — up to three subprocess spawns on a machine
/// with no solver installed. `PlateSolverConfig::default()` runs on every
/// solve, and `is_solver_available()` / `get_solver_path()` are polled by the
/// settings UI, the scheduler and sequencer pre-flight, so an uncached probe
/// is paid hundreds of times a night. The answer is process-stable: an
/// installer running while Nightshade is open is rare, and the only in-process
/// way to change the inputs is `set_solver_preference`, which invalidates.
/// `invalidate_solver_availability_cache()` forces a re-probe on demand.
static DISCOVERED_SOLVERS: std::sync::Mutex<Option<DiscoveredSolvers>> =
    std::sync::Mutex::new(None);

/// Resolve both solver paths, probing the filesystem only on a cache miss.
///
/// The probe runs while the cache mutex is held so concurrent solves wait for
/// one probe instead of each launching their own.
fn discovered_solvers() -> DiscoveredSolvers {
    // A poisoned cache holds a fully-written `Option`; the guarded region only
    // clones `PathBuf`s, so there is no torn state to recover from and a
    // permanent "no plate solving until restart" panic is the worse outcome.
    let mut guard = DISCOVERED_SOLVERS
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(cached) = guard.as_ref() {
        return cached.clone();
    }

    let (configured_astap, configured_astrometry) = {
        let pref = ACTIVE_SOLVER_PREF.read().expect("solver-pref RwLock");
        (pref.astap_path.clone(), pref.astrometry_path.clone())
    };
    let discovered = DiscoveredSolvers {
        astap: find_astap_with_override(configured_astap.as_deref()),
        astrometry: find_astrometry_with_override(configured_astrometry.as_deref()),
    };
    *guard = Some(discovered.clone());
    discovered
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

    // Fall back to the operator's configured Plate Solving paths when the
    // caller supplies none. Every other entry point into this module already
    // consults `ACTIVE_SOLVER_PREF` for exactly this reason ("without any
    // caller needing to pass the config explicitly"); this one did not, so it
    // only ever searched the default install locations.
    //
    // The visible consequence: on any rig whose ASTAP lives somewhere else,
    // the sequencer's pre-flight check reported "no ASTAP star database found
    // ... target centering in this sequence will fail" as a run-level error,
    // on runs where the catalogs were present and ASTAP was solving to 0.5".
    // A setup warning that fires while the thing it warns about is working is
    // worse than no warning: the next real one gets ignored.
    let pref_exe;
    let pref_catalog;
    let (exe_path, configured) = if exe_path.is_none() && configured.is_none() {
        let pref = ACTIVE_SOLVER_PREF.read().expect("solver-pref RwLock");
        pref_exe = pref.astap_path.clone();
        pref_catalog = pref.catalog_path.clone();
        (pref_exe.as_deref(), pref_catalog.as_deref())
    } else {
        (exe_path, configured)
    };

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
                    success: false,
                    error: Some("ASTAP not found".to_string()),
                    solve_time_secs: 0.0,
                    ..Default::default()
                }
            }
        };

        // Build ASTAP command.
        //
        // Flag reference: https://www.hnsky.org/astap.htm#command_line
        //   -f <file>        : input FITS file (required)
        //   -r <deg>         : search radius in degrees (only with -ra/-spd)
        //   -ra <hours>      : hint RA in hours
        //   -spd <deg>       : hint south-pole distance = Dec + 90°
        //   -z <factor>      : downsample factor (default 0 = auto)
        //   -d <dir>         : star catalog directory (REQUIRED when catalog is
        //                      not co-located with the ASTAP binary)
        //   -wcs             : write WCS solution to a sibling .wcs FITS file
        //                      (used instead of -update which modifies the
        //                      input file and only writes .ini, not .wcs)
        //
        // IMPORTANT: ASTAP exits 0 even on a failed solve. The actual result
        // is only in PLTSOLVD inside the .ini file. Do NOT gate on exit status.
        let mut cmd = Command::new(astap_path);

        // Input file
        cmd.arg("-f").arg(image_path);

        // Hint coordinates — only add when provided (near solve)
        if let (Some(ra), Some(dec)) = (hint_ra, hint_dec) {
            cmd.arg("-ra").arg(format!("{:.6}", ra / 15.0)); // hours
            cmd.arg("-spd").arg(format!("{:.6}", dec + 90.0)); // south-pole distance
                                                               // Search radius only makes sense alongside a position hint
            if self.config.search_radius > 0.0 {
                cmd.arg("-r")
                    .arg(format!("{:.2}", self.config.search_radius));
            }
        }

        // hint_scale: ASTAP expects -fov in degrees (field of view), not
        // arcsec/pixel. We don't have sensor pixel size here, so skip it.
        if hint_scale.is_some() {
            tracing::debug!(
                "Plate-solve scale hint provided without pixel size; skipping ASTAP -fov hint"
            );
        }

        // Downsample: 0 means auto; send explicit value when configured > 1
        if self.config.downsample > 1 {
            cmd.arg("-z").arg(format!("{}", self.config.downsample));
        }

        // Catalog directory: required when the catalog is not in the ASTAP
        // install directory. Without this flag ASTAP reports "no star database
        // found" and PLTSOLVD=F.
        if let Some(cat_dir) = &self.config.catalog_path {
            cmd.arg("-d").arg(cat_dir);
        }

        // Request a standalone WCS output file (.wcs) alongside the input.
        // This does NOT modify the input FITS file (unlike -update which
        // writes the solution into the FITS header). The .wcs file is a
        // FITS file containing CRVAL1/2, CD-matrix keywords; our
        // parse_wcs_file_inner parser reads exactly these.
        //
        // -update is explicitly avoided: it writes only .ini (not .wcs),
        // and modifying the user's capture file as a side effect is
        // undesirable. The .ini file is also produced alongside -wcs, so
        // both parsers remain available.
        cmd.arg("-wcs");

        tracing::info!("Running ASTAP: {:?}", cmd);

        // Enforce timeout using spawn + wait_timeout. Command::output()
        // blocks forever; a stuck ASTAP process (e.g. hung on a network
        // catalog lookup) would stall the sequencer indefinitely.
        let timeout = std::time::Duration::from_secs(u64::from(self.config.timeout_secs));
        let mut child = match cmd.stdout(Stdio::piped()).stderr(Stdio::piped()).spawn() {
            Ok(c) => c,
            Err(e) => {
                return PlateSolveResult {
                    success: false,
                    error: Some(format!("Failed to launch ASTAP at {:?}: {}", astap_path, e)),
                    solve_time_secs: start.elapsed().as_secs_f64(),
                    ..Default::default()
                }
            }
        };

        let child_id = child.id();
        let timeout_secs = self.config.timeout_secs;
        // Drain both pipes concurrently so a chatty solver cannot block on a
        // full OS pipe while this thread retains the Child handle needed to
        // terminate and reap a timed-out solver.
        let mut stdout = child.stdout.take();
        let stdout_reader = std::thread::spawn(move || {
            let mut bytes = Vec::new();
            if let Some(pipe) = stdout.as_mut() {
                let _ = pipe.read_to_end(&mut bytes);
            }
            bytes
        });
        let mut stderr = child.stderr.take();
        let stderr_reader = std::thread::spawn(move || {
            let mut bytes = Vec::new();
            if let Some(pipe) = stderr.as_mut() {
                let _ = pipe.read_to_end(&mut bytes);
            }
            bytes
        });

        let status = match child.wait_timeout(timeout) {
            Ok(Some(status)) => status,
            Ok(None) => {
                tracing::error!(
                    "ASTAP (pid {}) timed out after {} seconds; terminating it",
                    child_id,
                    timeout_secs
                );
                let kill_error = child.kill().err();
                let reap_error = child.wait().err();
                // Do not join the pipe readers on timeout: a solver-spawned
                // descendant may still hold a copied pipe open. The detached
                // readers will exit at EOF without delaying the terminal
                // timeout result after the owned solver process is reaped.
                drop(stdout_reader);
                drop(stderr_reader);
                let cleanup_detail = match (kill_error, reap_error) {
                    (None, None) => String::new(),
                    (kill, reap) => format!(
                        " (cleanup: kill={}, reap={})",
                        kill.map_or_else(|| "ok".to_string(), |e| e.to_string()),
                        reap.map_or_else(|| "ok".to_string(), |e| e.to_string())
                    ),
                };
                return PlateSolveResult {
                    success: false,
                    error: Some(format!(
                        "ASTAP timed out after {} seconds{}",
                        timeout_secs, cleanup_detail
                    )),
                    solve_time_secs: start.elapsed().as_secs_f64(),
                    ..Default::default()
                };
            }
            Err(e) => {
                let _ = child.kill();
                let _ = child.wait();
                drop(stdout_reader);
                drop(stderr_reader);
                return PlateSolveResult {
                    success: false,
                    error: Some(format!("ASTAP wait failed: {}", e)),
                    solve_time_secs: start.elapsed().as_secs_f64(),
                    ..Default::default()
                };
            }
        };

        let stdout_bytes = stdout_reader.join().unwrap_or_default();
        let stderr_bytes = stderr_reader.join().unwrap_or_default();

        let solve_time = start.elapsed().as_secs_f64();

        // Capture ASTAP stdout + stderr for use in failure messages.
        // IMPORTANT: ASTAP exits 0 even when a solve fails. A non-zero exit
        // indicates a launch / argument error (e.g. bad flag, missing file),
        // which is worth surfacing separately. A zero exit with PLTSOLVD=F
        // in the .ini is the normal "not enough stars" failure path.
        let stdout_text = String::from_utf8_lossy(&stdout_bytes).to_string();
        let stderr_text = String::from_utf8_lossy(&stderr_bytes).to_string();
        let exit_code = status.code().unwrap_or(-1);

        if !status.success() {
            // Non-zero exit = argument/launch error, not a solve failure.
            // Surface ASTAP's output verbatim so the user can diagnose.
            let detail = if !stderr_text.trim().is_empty() {
                stderr_text.trim().to_string()
            } else if !stdout_text.trim().is_empty() {
                stdout_text.trim().to_string()
            } else {
                format!("(no output, exit code {})", exit_code)
            };
            tracing::error!(
                "ASTAP exited with non-zero status {}: {}",
                exit_code,
                detail
            );
            return PlateSolveResult {
                success: false,
                error: Some(format!(
                    "ASTAP exited with status {}: {}",
                    exit_code, detail
                )),
                solve_time_secs: solve_time,
                ..Default::default()
            };
        }

        // Parse ASTAP output artifacts. With -wcs, ASTAP writes:
        //   <image>.wcs  — FITS WCS header (CRVAL1/2, CD-matrix)
        //   <image>.ini  — key=value result including PLTSOLVD=T/F
        //
        // The .ini is the authoritative success/failure indicator.
        // The .wcs contains the actual WCS coordinates we need.
        // Parse in this order:
        //   1. Try .ini first to check PLTSOLVD and get an error reason.
        //   2. If PLTSOLVD=T, parse .wcs for the full CD-matrix solution.
        //   3. Fall back to .ini coordinates if .wcs is missing.

        let ini_path = image_path.with_extension("ini");
        let wcs_path = image_path.with_extension("wcs");

        // Check .ini for PLTSOLVD flag — gives us the ASTAP-side result
        // and any error information before attempting to parse coordinates.
        if ini_path.exists() {
            // Read ini to check PLTSOLVD and extract any error message
            match fs::read_to_string(&ini_path) {
                Ok(ini_content) => {
                    let solved = ini_content
                        .lines()
                        .any(|l| l.trim().eq_ignore_ascii_case("PLTSOLVD=T"));

                    if !solved {
                        // Extract ASTAP's error reason from the ini file and
                        // from the stdout/stderr for a diagnostic message.
                        let ini_reason = ini_content
                            .lines()
                            .find(|l| {
                                let u = l.to_ascii_uppercase();
                                u.starts_with("ERROR") || u.starts_with("REASON")
                            })
                            .unwrap_or("PLTSOLVD=F")
                            .trim()
                            .to_string();

                        let extra = [stdout_text.trim(), stderr_text.trim()]
                            .iter()
                            .filter(|s| !s.is_empty())
                            .cloned()
                            .collect::<Vec<_>>()
                            .join(" | ");

                        let msg = if extra.is_empty() {
                            format!("ASTAP could not solve: {}", ini_reason)
                        } else {
                            format!("ASTAP could not solve: {} | {}", ini_reason, extra)
                        };

                        tracing::warn!("{}", msg);
                        // Clean up artifacts
                        let _ = fs::remove_file(&ini_path);
                        let _ = fs::remove_file(&wcs_path);
                        return PlateSolveResult {
                            success: false,
                            error: Some(msg),
                            solve_time_secs: solve_time,
                            ..Default::default()
                        };
                    }
                }
                Err(e) => {
                    tracing::warn!("Could not read ASTAP .ini at {:?}: {}", ini_path, e);
                    // Fall through and attempt .wcs anyway
                }
            }
        }

        // PLTSOLVD=T (or no .ini yet — proceed optimistically).
        // Parse the .wcs file for the full CD-matrix solution.
        if wcs_path.exists() {
            let result = match self.parse_wcs_file(&wcs_path, solve_time) {
                Ok(r) => r,
                Err(err) => {
                    let msg = format!(
                        "ASTAP reported success but .wcs parse failed: {} | stdout: {} | stderr: {}",
                        err,
                        stdout_text.trim(),
                        stderr_text.trim()
                    );
                    tracing::error!("{}", msg);
                    PlateSolveResult {
                        success: false,
                        error: Some(msg),
                        solve_time_secs: solve_time,
                        ..Default::default()
                    }
                }
            };
            // Clean up artifacts
            let _ = fs::remove_file(&ini_path);
            let _ = fs::remove_file(&wcs_path);
            return result;
        }

        // No .wcs — fall back to .ini coordinates (produced by -update;
        // also present with -wcs for some ASTAP versions).
        if ini_path.exists() {
            let result = self.parse_astap_ini(&ini_path, solve_time);
            let _ = fs::remove_file(&ini_path);
            return result;
        }

        // No output artifacts at all — ASTAP produced neither .wcs nor .ini.
        // This typically means ASTAP was given a non-FITS file or the image
        // path contains characters ASTAP can't handle.
        let msg = format!(
            "ASTAP produced no output artifacts (.wcs / .ini missing). \
             stdout: {} | stderr: {}",
            stdout_text.trim(),
            stderr_text.trim()
        );
        tracing::error!("{}", msg);
        PlateSolveResult {
            success: false,
            error: Some(msg),
            solve_time_secs: solve_time,
            ..Default::default()
        }
    }

    /// Parse ASTAP .ini result file
    fn parse_astap_ini(&self, ini_path: &Path, solve_time: f64) -> PlateSolveResult {
        match parse_astap_ini_inner(ini_path, solve_time) {
            Ok(result) => result,
            Err(err) => PlateSolveResult {
                success: false,
                error: Some(err.to_string()),
                solve_time_secs: solve_time,
                ..Default::default()
            },
        }
    }

    /// Parse WCS file emitted by ASTAP/astrometry.net.
    ///
    /// Required keywords: CRVAL1, CRVAL2, CD1_1, CD1_2, CD2_1, CD2_2.
    /// Any malformed value or missing required keyword propagates as
    /// `PlateSolveError`; the caller is responsible for converting to a
    /// failed `PlateSolveResult`. Silent fallbacks (RA=0/Dec=0) are
    /// forbidden — see "errors are a feature".
    fn parse_wcs_file(
        &self,
        wcs_path: &Path,
        solve_time: f64,
    ) -> Result<PlateSolveResult, PlateSolveError> {
        parse_wcs_file_inner(wcs_path, solve_time)
    }
}

/// Length of one FITS header card, fixed by the standard.
const FITS_CARD_LEN: usize = 80;

/// Split a FITS header into its 80-character cards.
///
/// A `.wcs` file is a raw FITS header: fixed-width cards packed end to end
/// with **no line terminators at all**. Iterating it with `str::lines()`
/// therefore yields the whole header as one enormous "line", so only the very
/// first card (`SIMPLE`) is ever inspected and every keyword after it —
/// `CRVAL1`, the CD matrix, `NAXIS1/2` — is invisible. ASTAP would solve, the
/// parse would then report the solution as missing `CRVAL1`, and the caller
/// counted a successful solve as a failed one: `Plate Solve & Center` failed
/// every attempt and took the run down with it.
///
/// Newlines are still honoured first, because some solvers (and this module's
/// own test fixtures) do write one card per line; only segments longer than a
/// single card are split further.
fn fits_header_cards(content: &str) -> Vec<&str> {
    let mut cards = Vec::new();
    for segment in content.lines() {
        if segment.len() <= FITS_CARD_LEN {
            cards.push(segment);
            continue;
        }
        let bytes = segment.as_bytes();
        let mut start = 0;
        while start < bytes.len() {
            let end = (start + FITS_CARD_LEN).min(bytes.len());
            // A FITS header is ASCII, so every card boundary is a char
            // boundary. Anything else is not a header we can card-split;
            // hand back what is left in one piece rather than panicking on a
            // mid-character slice.
            match std::str::from_utf8(&bytes[start..end]) {
                Ok(card) => cards.push(card),
                Err(_) => {
                    cards.push(&segment[start..]);
                    break;
                }
            }
            start = end;
        }
    }
    cards
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
    // Image dimensions in pixels. ASTAP writes NAXIS1/NAXIS2 to its .wcs;
    // astrometry.net writes IMAGEW/IMAGEH. Needed to recover the field size so
    // the reference pixel (CRPIX) lands on the image centre — without it the WCS
    // is anchored to the corner, offsetting every pixel<->sky map by half a field.
    let mut naxis1: Option<f64> = None;
    let mut naxis2: Option<f64> = None;
    let mut a_order: Option<u32> = None;
    let mut b_order: Option<u32> = None;
    let mut ap_order: Option<u32> = None;
    let mut bp_order: Option<u32> = None;
    let mut a_terms: Vec<(u32, u32, f64)> = Vec::new();
    let mut b_terms: Vec<(u32, u32, f64)> = Vec::new();
    let mut ap_terms: Vec<(u32, u32, f64)> = Vec::new();
    let mut bp_terms: Vec<(u32, u32, f64)> = Vec::new();

    for line in fits_header_cards(&content) {
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
        let parse_order = |slot: &mut Option<u32>| -> Result<(), PlateSolveError> {
            let parsed = value_str
                .parse::<f64>()
                .map_err(|source| PlateSolveError::WcsParse {
                    keyword: keyword.to_string(),
                    raw_value: value_str.to_string(),
                    path: path_display.clone(),
                    source,
                })?;
            *slot = Some(parsed as u32);
            Ok(())
        };
        let parse_term = |terms: &mut Vec<(u32, u32, f64)>,
                          body: &str|
         -> Result<(), PlateSolveError> {
            let Some((i, j)) = sip_indices(body) else {
                return Ok(());
            };
            let coeff = value_str
                .parse::<f64>()
                .map_err(|source| PlateSolveError::WcsParse {
                    keyword: keyword.to_string(),
                    raw_value: value_str.to_string(),
                    path: path_display.clone(),
                    source,
                })?;
            terms.push((i, j, coeff));
            Ok(())
        };

        match keyword {
            "CRVAL1" => parse(&mut ra)?,
            "CRVAL2" => parse(&mut dec)?,
            "CD1_1" => parse(&mut cd1_1)?,
            "CD1_2" => parse(&mut cd1_2)?,
            "CD2_1" => parse(&mut cd2_1)?,
            "CD2_2" => parse(&mut cd2_2)?,
            "NAXIS1" | "IMAGEW" => parse(&mut naxis1)?,
            "NAXIS2" | "IMAGEH" => parse(&mut naxis2)?,
            "A_ORDER" => parse_order(&mut a_order)?,
            "B_ORDER" => parse_order(&mut b_order)?,
            "AP_ORDER" => parse_order(&mut ap_order)?,
            "BP_ORDER" => parse_order(&mut bp_order)?,
            k if k.starts_with("AP_") => parse_term(&mut ap_terms, &k[3..])?,
            k if k.starts_with("BP_") => parse_term(&mut bp_terms, &k[3..])?,
            k if k.starts_with("A_") => parse_term(&mut a_terms, &k[2..])?,
            k if k.starts_with("B_") => parse_term(&mut b_terms, &k[2..])?,
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
    // Field rotation, inverse of the CD-from-rotation convention used when the
    // CD matrix must be reconstructed (SipWcs/WcsInfo::from_plate_solve):
    //   cd1_1 = -scale·cos(rot), cd2_1 = scale·sin(rot)
    // so rot = atan2(cd2_1, -cd1_1). Using atan2(cd2_1, cd1_1) here (the old
    // form) reported a north-up frame as 180°, disagreeing with the generator
    // and corrupting any fallback CD rebuilt from the scalar rotation.
    let rotation = cd2_1.atan2(-cd1_1).to_degrees();

    // Field extent in degrees, derived from the image dimensions and pixel
    // scale. Downstream WCS construction divides field_* back by the pixel
    // scale to place CRPIX at the image centre, so a zero here would anchor the
    // reference pixel to the corner. Leave zero only if the solver emitted no
    // dimension keywords at all (older output) — behaviour then matches before.
    let field_width = naxis1.map_or(0.0, |n| n * pixel_scale / 3600.0);
    let field_height = naxis2.map_or(0.0, |n| n * pixel_scale / 3600.0);

    let a_order = a_order.unwrap_or(0);
    let b_order = b_order.unwrap_or(0);
    let ap_order = ap_order.unwrap_or(0);
    let bp_order = bp_order.unwrap_or(0);
    let a_coeffs = sip_layout(a_order, &a_terms);
    let b_coeffs = sip_layout(b_order, &b_terms);
    let ap_coeffs = sip_layout(ap_order, &ap_terms);
    let bp_coeffs = sip_layout(bp_order, &bp_terms);

    Ok(PlateSolveResult {
        ra,
        dec,
        pixel_scale,
        rotation,
        field_width,
        field_height,
        success: true,
        error: None,
        solve_time_secs: solve_time,
        cd1_1,
        cd1_2,
        cd2_1,
        cd2_2,
        a_order,
        b_order,
        a_coeffs,
        b_coeffs,
        ap_order,
        bp_order,
        ap_coeffs,
        bp_coeffs,
    })
}

/// Split a SIP coefficient keyword body (`"2_0"` from `A_2_0`) into its
/// `(i, j)` polynomial indices. Returns `None` for diagnostic siblings like
/// `A_DMAX` so the caller can skip them.
fn sip_indices(body: &str) -> Option<(u32, u32)> {
    let (i, j) = body.split_once('_')?;
    Some((i.parse().ok()?, j.parse().ok()?))
}

/// Pack `(i, j, coeff)` SIP terms into the row-major layout documented on
/// `PlateSolveResult`: index `i * (order + 1) + j`. Missing terms stay 0.0.
/// Returns an empty vec when `order == 0` and no terms were present.
fn sip_layout(order: u32, terms: &[(u32, u32, f64)]) -> Vec<f64> {
    if order == 0 && terms.is_empty() {
        return Vec::new();
    }
    let stride = (order + 1) as usize;
    let mut coeffs = vec![0.0; stride * stride];
    for &(i, j, c) in terms {
        if (i as usize) < stride && (j as usize) < stride {
            coeffs[i as usize * stride + j as usize] = c;
        }
    }
    coeffs
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
        ..Default::default()
    })
}

/// Blind plate solve (no hint)
pub fn blind_solve(image_path: &Path) -> PlateSolveResult {
    let start = std::time::Instant::now();
    solve_with_external_config(
        image_path,
        None,
        None,
        None,
        PlateSolverConfig::default(),
        start,
    )
}

/// Blind plate solve with a caller-selected subprocess timeout.
pub fn blind_solve_with_timeout(image_path: &Path, timeout_secs: u32) -> PlateSolveResult {
    let start = std::time::Instant::now();
    let config = PlateSolverConfig {
        timeout_secs,
        ..PlateSolverConfig::default()
    };
    solve_with_external_config(image_path, None, None, None, config, start)
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

/// Plate solve near coordinates with a caller-selected subprocess timeout.
pub fn solve_near_with_timeout(
    image_path: &Path,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
    timeout_secs: u32,
) -> PlateSolveResult {
    let start = std::time::Instant::now();
    let config = PlateSolverConfig {
        search_radius,
        timeout_secs,
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

fn solve_with_external_config(
    image_path: &Path,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
    hint_scale: Option<f64>,
    config: PlateSolverConfig,
    start: std::time::Instant,
) -> PlateSolveResult {
    match config.solver_choice {
        PlateSolverChoice::Astap => {
            if config.astap_path.is_none() {
                return PlateSolveResult {
                    success: false,
                    error: Some("ASTAP is selected but is not available".to_string()),
                    solve_time_secs: start.elapsed().as_secs_f64(),
                    ..Default::default()
                };
            }
            AstapSolver::new(config).solve(image_path, hint_ra, hint_dec, hint_scale)
        }
        PlateSolverChoice::Astrometry => {
            let Some(astrometry_path) = config.astrometry_path.as_deref() else {
                return PlateSolveResult {
                    success: false,
                    error: Some(
                        "Astrometry.net is selected but solve-field is not available".to_string(),
                    ),
                    solve_time_secs: start.elapsed().as_secs_f64(),
                    ..Default::default()
                };
            };
            solve_with_astrometry(
                astrometry_path,
                image_path,
                hint_ra,
                hint_dec,
                config.search_radius,
                config.timeout_secs,
                start,
            )
        }
        PlateSolverChoice::Auto => {
            if config.astap_path.is_some() {
                let astap_result = AstapSolver::new(config.clone())
                    .solve(image_path, hint_ra, hint_dec, hint_scale);
                if astap_result.success || config.astrometry_path.is_none() {
                    return astap_result;
                }

                tracing::warn!(
                    "ASTAP failed ({}); falling back to astrometry.net",
                    astap_result.error.as_deref().unwrap_or("unknown error")
                );
                let mut astrometry_result = solve_with_astrometry(
                    config
                        .astrometry_path
                        .as_deref()
                        .expect("astrometry path checked above"),
                    image_path,
                    hint_ra,
                    hint_dec,
                    config.search_radius,
                    config.timeout_secs,
                    start,
                );
                if !astrometry_result.success {
                    astrometry_result.error = Some(format!(
                        "ASTAP failed: {}. Astrometry.net failed: {}",
                        astap_result.error.as_deref().unwrap_or("unknown error"),
                        astrometry_result
                            .error
                            .as_deref()
                            .unwrap_or("unknown error")
                    ));
                }
                return astrometry_result;
            }

            if let Some(astrometry_path) = config.astrometry_path.as_deref() {
                return solve_with_astrometry(
                    astrometry_path,
                    image_path,
                    hint_ra,
                    hint_dec,
                    config.search_radius,
                    config.timeout_secs,
                    start,
                );
            }

            external_solver_unavailable(start)
        }
    }
}

struct SolverCommandOutput {
    status: std::process::ExitStatus,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

fn run_solver_command(
    cmd: &mut Command,
    timeout_secs: u32,
    label: &str,
) -> Result<SolverCommandOutput, String> {
    let mut child = cmd
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("Failed to launch {label}: {error}"))?;
    let child_id = child.id();
    let mut stdout = child.stdout.take();
    let stdout_reader = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        if let Some(pipe) = stdout.as_mut() {
            let _ = pipe.read_to_end(&mut bytes);
        }
        bytes
    });
    let mut stderr = child.stderr.take();
    let stderr_reader = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        if let Some(pipe) = stderr.as_mut() {
            let _ = pipe.read_to_end(&mut bytes);
        }
        bytes
    });

    let timeout = std::time::Duration::from_secs(u64::from(timeout_secs));
    let status = match child.wait_timeout(timeout) {
        Ok(Some(status)) => status,
        Ok(None) => {
            tracing::error!(
                "{} (pid {}) timed out after {} seconds; terminating it",
                label,
                child_id,
                timeout_secs
            );
            let kill_error = child.kill().err();
            let reap_error = child.wait().err();
            drop(stdout_reader);
            drop(stderr_reader);
            let cleanup = match (kill_error, reap_error) {
                (None, None) => String::new(),
                (kill, reap) => format!(
                    " (cleanup: kill={}, reap={})",
                    kill.map_or_else(|| "ok".to_string(), |e| e.to_string()),
                    reap.map_or_else(|| "ok".to_string(), |e| e.to_string())
                ),
            };
            return Err(format!(
                "{label} timed out after {timeout_secs} seconds{cleanup}"
            ));
        }
        Err(error) => {
            let _ = child.kill();
            let _ = child.wait();
            drop(stdout_reader);
            drop(stderr_reader);
            return Err(format!("Failed waiting for {label}: {error}"));
        }
    };

    Ok(SolverCommandOutput {
        status,
        stdout: stdout_reader.join().unwrap_or_default(),
        stderr: stderr_reader.join().unwrap_or_default(),
    })
}

fn solve_with_astrometry(
    astrometry_path: &Path,
    image_path: &Path,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
    search_radius: f64,
    timeout_secs: u32,
    start: std::time::Instant,
) -> PlateSolveResult {
    let output_dir = image_path.parent().unwrap_or_else(|| Path::new("."));
    let wcs_path = image_path.with_extension("wcs");
    if wcs_path.exists() {
        if let Err(error) = fs::remove_file(&wcs_path) {
            return PlateSolveResult {
                success: false,
                error: Some(format!(
                    "Failed to remove stale astrometry.net WCS output {:?}: {}",
                    wcs_path, error
                )),
                solve_time_secs: start.elapsed().as_secs_f64(),
                ..Default::default()
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

    let output = match run_solver_command(&mut cmd, timeout_secs, "astrometry.net solve-field") {
        Ok(output) => output,
        Err(error) => {
            return PlateSolveResult {
                success: false,
                error: Some(error),
                solve_time_secs: start.elapsed().as_secs_f64(),
                ..Default::default()
            }
        }
    };

    let solve_time = start.elapsed().as_secs_f64();
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let detail = if !stderr.trim().is_empty() {
            stderr.trim()
        } else if !stdout.trim().is_empty() {
            stdout.trim()
        } else {
            "no solver output"
        };
        return PlateSolveResult {
            success: false,
            error: Some(format!("astrometry.net solve-field failed: {}", detail)),
            solve_time_secs: solve_time,
            ..Default::default()
        };
    }

    match parse_wcs_file_inner(&wcs_path, solve_time) {
        Ok(result) => result,
        Err(error) => PlateSolveResult {
            success: false,
            error: Some(error.to_string()),
            solve_time_secs: solve_time,
            ..Default::default()
        },
    }
}

fn external_solver_unavailable(start: std::time::Instant) -> PlateSolveResult {
    PlateSolveResult {
        success: false,
        error: Some(
            "No supported external plate solver is configured. Install ASTAP and make astap_cli available on PATH or configure its executable path before solving."
                .to_string(),
        ),
        solve_time_secs: start.elapsed().as_secs_f64(),
        ..Default::default()
    }
}

/// Check if any plate solver (ASTAP or local astrometry.net) is reachable on
/// disk. Returns `false` if neither is found at any well-known install path
/// or via PATH lookup. Result is cached after first call; see
/// `DISCOVERED_SOLVERS` doc for rationale.
pub fn is_solver_available() -> bool {
    let discovered = discovered_solvers();
    discovered.astap.is_some() || discovered.astrometry.is_some()
}

/// Drop the cached solver-discovery answer so the next call re-probes the
/// filesystem. Called whenever the user updates the solver path via the
/// settings UI.
pub fn invalidate_solver_availability_cache() {
    *DISCOVERED_SOLVERS
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
}

/// Get path to installed solver
pub fn get_solver_path() -> Option<PathBuf> {
    let discovered = discovered_solvers();
    discovered.astap.or(discovered.astrometry)
}

#[cfg(test)]
mod tests {
    use super::{
        external_solver_unavailable, parse_astap_ini_inner, parse_wcs_file_inner, PlateSolveError,
    };
    use std::io::Write;
    use std::path::PathBuf;

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

    /// One 80-character FITS card, padded, with no line terminator — the way
    /// ASTAP actually writes `.wcs`.
    fn padded_card(keyword: &str, value: &str) -> String {
        let body = format!("{keyword:<8}= {value}");
        format!("{body:<80}")
    }

    /// Regression: a real ASTAP `.wcs` is a stream of fixed 80-character cards
    /// with **no newlines**, and the camera's own metadata pushes the WCS
    /// keywords well past the first card. Parsing it with `str::lines()` saw
    /// only `SIMPLE` and reported the solve as missing `CRVAL1`, so every
    /// `Plate Solve & Center` attempt failed against a solution ASTAP had
    /// already found — and the failure took the whole run with it.
    #[test]
    fn parse_wcs_file_reads_a_newline_free_card_stream() {
        let mut content = padded_card("SIMPLE", "                   T");
        // Instrument metadata ASTAP copies from the source frame, enough of it
        // to push the solution past the first 2880-byte header block.
        for index in 0..40 {
            content.push_str(&padded_card(&format!("NSPAD{index:03}"), "0"));
        }
        content.push_str(&padded_card("CRVAL1", "150.123 / RA of reference pixel"));
        content.push_str(&padded_card("CRVAL2", "20.456 / DEC of reference pixel"));
        content.push_str(&padded_card("CD1_1", "-0.000358"));
        content.push_str(&padded_card("CD1_2", "0.000001"));
        content.push_str(&padded_card("CD2_1", "0.000001"));
        content.push_str(&padded_card("CD2_2", "0.000358"));
        content.push_str(&padded_card("NAXIS1", "1920"));
        content.push_str(&padded_card("NAXIS2", "1080"));
        assert!(!content.contains('\n'), "fixture must have no newlines");

        let path = write_temp("wcs-card-stream", &content);
        let result =
            parse_wcs_file_inner(&path, 0.3).expect("a card-stream .wcs must parse like any other");

        assert!(result.success);
        assert!((result.ra - 150.123).abs() < 1e-9, "ra was {}", result.ra);
        assert!((result.dec - 20.456).abs() < 1e-9, "dec was {}", result.dec);
        assert!(result.pixel_scale > 0.0);

        let _ = std::fs::remove_file(path);
    }

    /// Regression (#3, #13): NAXIS drives the field size so the reconstructed
    /// WCS anchors CRPIX on the image centre (not the corner at 0.5), and a
    /// north-up CD matrix parses back as rotation 0°, not 180°.
    #[test]
    fn parse_wcs_populates_field_size_and_centres_crpix() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.0"));
        content.push_str(&wcs_card("CRVAL2", "20.0"));
        // 1 arcsec/px, north-up east-left (standard sky orientation).
        content.push_str(&wcs_card("CD1_1", "-0.0002777778"));
        content.push_str(&wcs_card("CD1_2", "0.0"));
        content.push_str(&wcs_card("CD2_1", "0.0"));
        content.push_str(&wcs_card("CD2_2", "0.0002777778"));
        content.push_str(&wcs_card("NAXIS1", "1000"));
        content.push_str(&wcs_card("NAXIS2", "800"));
        let path = write_temp("wcs-naxis", &content);

        let r = parse_wcs_file_inner(&path, 0.0).expect("WCS must parse");
        let _ = std::fs::remove_file(&path);

        assert!(
            (r.pixel_scale - 1.0).abs() < 1e-3,
            "scale {}",
            r.pixel_scale
        );
        // field size in degrees = NAXIS * (arcsec/px) / 3600.
        assert!(
            (r.field_width - 1000.0 / 3600.0).abs() < 1e-4,
            "field_width {}",
            r.field_width
        );
        assert!(
            (r.field_height - 800.0 / 3600.0).abs() < 1e-4,
            "field_height {}",
            r.field_height
        );
        // North-up parses back to 0°, not the old 180°.
        assert!(r.rotation.abs() < 1e-6, "rotation {}", r.rotation);

        // Reconstructed reference pixel is the 1-based image centre, not (0.5,0.5).
        let wcs = crate::wcs_sip::SipWcs::from_plate_solve(&r).expect("invertible WCS");
        assert!((wcs.crpix1 - 500.5).abs() < 1e-6, "crpix1 {}", wcs.crpix1);
        assert!((wcs.crpix2 - 400.5).abs() < 1e-6, "crpix2 {}", wcs.crpix2);
    }

    /// Parse round-trip (NOT an on-sky accuracy claim): a WCS carrying the full
    /// anisotropic CD matrix plus a 2nd-order SIP forward/inverse distortion
    /// must read back the four CD terms verbatim and pack the SIP coefficients
    /// into the documented row-major `i * (order + 1) + j` layout.
    #[test]
    fn parse_wcs_file_reads_cd_matrix_and_sip_terms() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.0"));
        content.push_str(&wcs_card("CRVAL2", "20.0"));
        content.push_str(&wcs_card("CD1_1", "-0.000351"));
        content.push_str(&wcs_card("CD1_2", "0.000017"));
        content.push_str(&wcs_card("CD2_1", "0.000019"));
        content.push_str(&wcs_card("CD2_2", "0.000349"));
        content.push_str(&wcs_card("A_ORDER", "2"));
        content.push_str(&wcs_card("A_0_2", "1.1e-6"));
        content.push_str(&wcs_card("A_1_1", "-2.2e-6"));
        content.push_str(&wcs_card("A_2_0", "3.3e-6"));
        content.push_str(&wcs_card("B_ORDER", "2"));
        content.push_str(&wcs_card("B_0_2", "4.4e-6"));
        content.push_str(&wcs_card("B_2_0", "5.5e-6"));
        content.push_str(&wcs_card("AP_ORDER", "1"));
        content.push_str(&wcs_card("AP_1_0", "6.6e-6"));
        content.push_str(&wcs_card("BP_ORDER", "1"));
        content.push_str(&wcs_card("BP_0_1", "7.7e-6"));
        let path = write_temp("wcs-cd-sip", &content);

        let result = parse_wcs_file_inner(&path, 0.0).expect("CD + SIP WCS must parse");
        assert_eq!(result.cd1_1, -0.000351);
        assert_eq!(result.cd1_2, 0.000017);
        assert_eq!(result.cd2_1, 0.000019);
        assert_eq!(result.cd2_2, 0.000349);

        assert_eq!(result.a_order, 2);
        assert_eq!(result.b_order, 2);
        assert_eq!(result.a_coeffs.len(), 9);
        assert_eq!(result.b_coeffs.len(), 9);
        // Row-major (i, j) with order 2 => stride 3: A_0_2 -> 2, A_1_1 -> 4, A_2_0 -> 6.
        assert_eq!(result.a_coeffs[2], 1.1e-6);
        assert_eq!(result.a_coeffs[4], -2.2e-6);
        assert_eq!(result.a_coeffs[6], 3.3e-6);
        assert_eq!(result.b_coeffs[2], 4.4e-6);
        assert_eq!(result.b_coeffs[6], 5.5e-6);
        assert_eq!(result.b_coeffs[4], 0.0);

        assert_eq!(result.ap_order, 1);
        assert_eq!(result.bp_order, 1);
        assert_eq!(result.ap_coeffs.len(), 4);
        assert_eq!(result.ap_coeffs[2], 6.6e-6);
        assert_eq!(result.bp_coeffs[1], 7.7e-6);

        let _ = std::fs::remove_file(path);
    }

    /// SIP is optional: a CD-only WCS must leave the coefficient vectors empty
    /// (NOT zero-filled) and the orders at zero.
    #[test]
    fn parse_wcs_file_leaves_sip_empty_when_absent() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.0"));
        content.push_str(&wcs_card("CRVAL2", "20.0"));
        content.push_str(&wcs_card("CD1_1", "-0.000358"));
        content.push_str(&wcs_card("CD1_2", "0.000001"));
        content.push_str(&wcs_card("CD2_1", "0.000001"));
        content.push_str(&wcs_card("CD2_2", "0.000358"));
        let path = write_temp("wcs-no-sip", &content);

        let result = parse_wcs_file_inner(&path, 0.0).expect("CD-only WCS must parse");
        assert_eq!(result.a_order, 0);
        assert!(result.a_coeffs.is_empty());
        assert!(result.b_coeffs.is_empty());
        assert!(result.ap_coeffs.is_empty());
        assert!(result.bp_coeffs.is_empty());

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

    // =========================================================================
    // Bug-fix regression tests: global preference wiring + catalog -d flag
    // =========================================================================

    /// `ACTIVE_SOLVER_PREF` and the discovery cache are process-global, so the
    /// tests that mutate them must not run concurrently with each other.
    static PREF_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn lock_solver_pref() -> std::sync::MutexGuard<'static, ()> {
        PREF_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Setting the global solver preference via `set_solver_preference` must
    /// make `PlateSolverConfig::default()` resolve the configured ASTAP path
    /// rather than falling through to the system candidate list.
    ///
    /// This is the root bug: before the fix, `blind_solve` / `solve_near`
    /// called `PlateSolverConfig::default()` which called `find_astap()` with
    /// no access to the persisted user preference, so a custom install path
    /// set in Settings → Plate Solving was silently ignored.
    #[test]
    fn set_solver_preference_makes_default_config_resolve_configured_path() {
        use super::{set_solver_preference, PlateSolverConfig};

        let _pref_guard = lock_solver_pref();

        // Use a unique non-existent path so the candidate list cannot
        // accidentally match a real ASTAP install on the test machine.
        let fake_astap = std::env::temp_dir().join(format!(
            "fake-astap-{}-{}.exe",
            std::process::id(),
            "pref-test"
        ));
        // Write a zero-byte file so `Path::exists()` returns true.
        std::fs::write(&fake_astap, b"").expect("write fake astap");

        let fake_catalog = std::env::temp_dir().join(format!(
            "fake-catalog-{}-{}",
            std::process::id(),
            "pref-test"
        ));
        std::fs::create_dir_all(&fake_catalog).expect("create fake catalog dir");

        set_solver_preference(
            Some(fake_astap.to_str().unwrap()),
            None,
            Some(fake_catalog.to_str().unwrap()),
            Some("astap"),
        );

        let config = PlateSolverConfig::default();
        assert_eq!(
            config.astap_path.as_deref(),
            Some(fake_astap.as_path()),
            "PlateSolverConfig::default() must resolve the configured ASTAP path"
        );
        assert_eq!(
            config.catalog_path.as_deref(),
            Some(fake_catalog.as_path()),
            "PlateSolverConfig::default() must include the configured catalog path"
        );
        assert_eq!(config.solver_choice, super::PlateSolverChoice::Astap);

        // Reset global to avoid polluting other tests.
        set_solver_preference(None, None, None, None);
        let _ = std::fs::remove_file(&fake_astap);
        let _ = std::fs::remove_dir_all(&fake_catalog);
    }

    /// Solver discovery must be probed once and then served from the cache:
    /// every `PlateSolverConfig::default()` used to re-stat the whole candidate
    /// list and shell out to `which`/`where`, and `blind_solve`/`solve_near`
    /// each ran that probe twice per solve.
    ///
    /// Observable proof of the cache: delete the file the probe found. An
    /// uncached resolver reports `None` on the next call; a cached one keeps
    /// returning the path until it is invalidated.
    #[test]
    fn solver_discovery_is_cached_until_invalidated() {
        use super::{
            get_solver_path, invalidate_solver_availability_cache, is_solver_available,
            set_solver_preference, PlateSolverConfig,
        };

        let _pref_guard = lock_solver_pref();

        let fake_astap = std::env::temp_dir().join(format!(
            "fake-astap-cache-{}-{}.exe",
            std::process::id(),
            "discovery-test"
        ));
        std::fs::write(&fake_astap, b"").expect("write fake astap");

        // Setting the preference must invalidate, so this resolves the new path.
        set_solver_preference(
            Some(fake_astap.to_str().unwrap()),
            None,
            None,
            Some("astap"),
        );
        assert_eq!(
            PlateSolverConfig::default().astap_path.as_deref(),
            Some(fake_astap.as_path()),
            "set_solver_preference must invalidate the discovery cache"
        );
        assert!(is_solver_available());
        assert_eq!(get_solver_path().as_deref(), Some(fake_astap.as_path()));

        // The filesystem changes underneath us; the cached answer must stand.
        std::fs::remove_file(&fake_astap).expect("remove fake astap");
        assert_eq!(
            PlateSolverConfig::default().astap_path.as_deref(),
            Some(fake_astap.as_path()),
            "second default() re-probed the filesystem instead of using the cache"
        );
        assert_eq!(get_solver_path().as_deref(), Some(fake_astap.as_path()));

        // Explicit invalidation re-probes and now finds nothing at that path.
        invalidate_solver_availability_cache();
        assert_ne!(
            PlateSolverConfig::default().astap_path.as_deref(),
            Some(fake_astap.as_path()),
            "invalidate_solver_availability_cache must force a re-probe"
        );

        set_solver_preference(None, None, None, None);
    }

    /// After `set_solver_preference` is called with an empty string for all
    /// fields (Settings cleared / reset to auto), `PlateSolverConfig::default()`
    /// must not retain the old configured path.
    #[test]
    fn clear_solver_preference_reverts_to_auto_detect() {
        use super::{set_solver_preference, PlateSolverConfig};

        let _pref_guard = lock_solver_pref();

        // Set something, then clear it.
        set_solver_preference(
            Some("/tmp/fake-astap-clear-test"),
            None,
            None,
            Some("astap"),
        );
        // Clear by passing empty / None
        set_solver_preference(None, None, None, None);

        let config = PlateSolverConfig::default();
        assert_eq!(config.solver_choice, super::PlateSolverChoice::Auto);
        // The path `/tmp/fake-astap-clear-test` does not exist, so after
        // clearing, the config should NOT have that path (the candidate list
        // won't find it either since it's a made-up path).
        assert!(
            config
                .astap_path
                .as_deref()
                .map(|p| p.to_str().unwrap_or(""))
                .unwrap_or("")
                != "/tmp/fake-astap-clear-test",
            "cleared preference must not persist the old configured path"
        );
    }

    /// `PlateSolverConfig` must include `catalog_path` and, when the ASTAP
    /// solve command is built, the catalog directory must appear as `-d <dir>`.
    /// This test verifies the struct field is propagated — the actual command
    /// build is not testable without a real binary, but the presence of the
    /// field in the config is the necessary condition.
    #[test]
    fn platesolver_config_has_catalog_path_field() {
        use super::PlateSolverConfig;
        use std::path::PathBuf;

        let cat_dir = PathBuf::from(r"C:\astap\catalogs");
        let config = PlateSolverConfig {
            astap_path: None,
            astrometry_path: None,
            catalog_path: Some(cat_dir.clone()),
            search_radius: 5.0,
            downsample: 2,
            timeout_secs: 60,
            solver_choice: super::PlateSolverChoice::Auto,
        };
        assert_eq!(config.catalog_path.as_deref(), Some(cat_dir.as_path()));
    }

    /// The standard Windows ASTAP install path must appear in the candidate
    /// list produced by `astap_candidates` for the Windows OS family.
    /// This verifies bug #1 detection: if the standard path were missing,
    /// a plain `C:\Program Files\astap\astap.exe` install would be invisible
    /// to the auto-detect path.
    #[test]
    fn astap_candidates_windows_includes_standard_program_files_path() {
        use super::platesolve_paths::{astap_candidates, AstapPathInputs, OsFamily};
        use std::path::PathBuf;

        let candidates = astap_candidates(&AstapPathInputs {
            os: OsFamily::Windows,
            configured: None,
            local_app_data: None,
            home: None,
        });

        assert!(
            candidates.contains(&PathBuf::from(r"C:\Program Files\astap\astap.exe")),
            "standard Windows ASTAP path must be in the candidate list"
        );
        assert!(
            candidates.contains(&PathBuf::from(r"C:\Program Files\astap\astap_cli.exe")),
            "standard Windows ASTAP CLI path must be in the candidate list"
        );
    }

    /// A solved ASTAP .ini with PLTSOLVD=T must parse successfully and
    /// surface CRVAL1/CRVAL2/CDELT1/CDELT2/CROTA correctly.
    #[test]
    fn parse_astap_ini_succeeds_on_solved_frame() {
        let content = concat!(
            "PLTSOLVD=T\n",
            "CRVAL1=150.250\n",
            "CRVAL2=20.500\n",
            "CDELT1=-0.000358\n",
            "CDELT2=0.000358\n",
            "CROTA2=15.3\n",
        );
        let path = write_temp("ini-solved", content);
        let result =
            super::parse_astap_ini_inner(&path, 1.23).expect("solved ASTAP .ini must parse");
        assert!(result.success);
        assert!((result.ra - 150.250).abs() < 1e-6, "RA mismatch");
        assert!((result.dec - 20.500).abs() < 1e-6, "Dec mismatch");
        assert!((result.rotation - 15.3).abs() < 1e-6, "rotation mismatch");
        assert!(result.pixel_scale > 0.0, "pixel scale must be positive");
        assert!((result.solve_time_secs - 1.23).abs() < 1e-9);
        let _ = std::fs::remove_file(path);
    }

    #[cfg(unix)]
    #[test]
    fn explicit_astrometry_choice_does_not_run_available_astap() {
        use super::{solve_with_external_config, PlateSolverChoice, PlateSolverConfig};
        use std::os::unix::fs::PermissionsExt;

        let nonce = format!("{}-choice", std::process::id());
        let dir = std::env::temp_dir().join(format!("nightshade-solver-{nonce}"));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("create solver-choice fixture dir");
        let astap = dir.join("astap.sh");
        let astrometry = dir.join("solve-field.sh");
        let astap_marker = dir.join("astap-ran");
        let astrometry_marker = dir.join("astrometry-ran");
        let image = dir.join("frame.fits");
        std::fs::write(&image, b"fixture").expect("write fake image");
        std::fs::write(
            &astap,
            format!(
                "#!/bin/sh\nprintf ran > '{}'\nexit 1\n",
                astap_marker.display()
            ),
        )
        .expect("write fake ASTAP");
        std::fs::write(
            &astrometry,
            format!(
                "#!/bin/sh\nprintf ran > '{}'\nexit 1\n",
                astrometry_marker.display()
            ),
        )
        .expect("write fake astrometry");
        for executable in [&astap, &astrometry] {
            let mut permissions = std::fs::metadata(executable)
                .expect("solver metadata")
                .permissions();
            permissions.set_mode(0o755);
            std::fs::set_permissions(executable, permissions).expect("make solver executable");
        }

        let result = solve_with_external_config(
            &image,
            Some(150.0),
            Some(42.0),
            None,
            PlateSolverConfig {
                astap_path: Some(astap.clone()),
                astrometry_path: Some(astrometry.clone()),
                catalog_path: None,
                search_radius: 5.0,
                downsample: 0,
                timeout_secs: 5,
                solver_choice: PlateSolverChoice::Astrometry,
            },
            std::time::Instant::now(),
        );

        assert!(!result.success);
        assert!(
            astrometry_marker.exists(),
            "selected astrometry did not run"
        );
        assert!(
            !astap_marker.exists(),
            "ASTAP ran despite explicit astrometry selection"
        );

        std::fs::remove_file(&astrometry_marker).expect("reset astrometry marker");
        let auto_result = solve_with_external_config(
            &image,
            Some(150.0),
            Some(42.0),
            None,
            PlateSolverConfig {
                astap_path: Some(astap),
                astrometry_path: Some(astrometry.clone()),
                catalog_path: None,
                search_radius: 5.0,
                downsample: 0,
                timeout_secs: 5,
                solver_choice: PlateSolverChoice::Auto,
            },
            std::time::Instant::now(),
        );
        assert!(!auto_result.success);
        assert!(astap_marker.exists(), "Auto did not try ASTAP first");
        assert!(
            astrometry_marker.exists(),
            "Auto did not fall back to astrometry after ASTAP failed"
        );
        let combined = auto_result.error.unwrap_or_default();
        assert!(combined.contains("ASTAP failed"));
        assert!(combined.contains("Astrometry.net failed"));

        let late_marker = dir.join("astrometry-late-output");
        std::fs::write(
            &astrometry,
            format!(
                "#!/bin/sh\nsleep 2\nprintf late > '{}'\n",
                late_marker.display()
            ),
        )
        .expect("write hanging astrometry fixture");
        let timeout_result = solve_with_external_config(
            &image,
            Some(150.0),
            Some(42.0),
            None,
            PlateSolverConfig {
                astap_path: None,
                astrometry_path: Some(astrometry),
                catalog_path: None,
                search_radius: 5.0,
                downsample: 0,
                timeout_secs: 1,
                solver_choice: PlateSolverChoice::Astrometry,
            },
            std::time::Instant::now(),
        );
        assert!(!timeout_result.success);
        assert!(timeout_result
            .error
            .as_deref()
            .unwrap_or_default()
            .contains("timed out"));
        std::thread::sleep(std::time::Duration::from_millis(1_500));
        assert!(
            !late_marker.exists(),
            "timed-out astrometry.net continued running"
        );
        let _ = std::fs::remove_dir_all(dir);
    }

    #[cfg(unix)]
    #[test]
    fn timed_out_astap_is_terminated_before_it_can_write_late_output() {
        use super::{AstapSolver, PlateSolverConfig};
        use std::os::unix::fs::PermissionsExt;

        let nonce = format!(
            "{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock after epoch")
                .as_nanos()
        );
        let dir = std::env::temp_dir().join(format!("nightshade-solver-timeout-{nonce}"));
        std::fs::create_dir_all(&dir).expect("create timeout fixture dir");
        let script = dir.join("fake-astap.sh");
        let image = dir.join("frame.fits");
        let marker = dir.join("late-output");
        std::fs::write(&image, b"fixture").expect("write fake image");
        std::fs::write(
            &script,
            format!(
                "#!/bin/sh\nsleep 2\nprintf stale > '{}'\n",
                marker.display()
            ),
        )
        .expect("write fake ASTAP");
        let mut permissions = std::fs::metadata(&script)
            .expect("fake ASTAP metadata")
            .permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&script, permissions).expect("make fake ASTAP executable");

        let solver = AstapSolver::new(PlateSolverConfig {
            astap_path: Some(script),
            astrometry_path: None,
            catalog_path: None,
            search_radius: 5.0,
            downsample: 0,
            timeout_secs: 1,
            solver_choice: super::PlateSolverChoice::Astap,
        });
        let result = solver.solve(&image, None, None, None);
        assert!(!result.success);
        assert!(
            result
                .error
                .as_deref()
                .unwrap_or_default()
                .contains("timed out"),
            "unexpected timeout result: {:?}",
            result.error
        );
        std::thread::sleep(std::time::Duration::from_millis(1_500));
        assert!(
            !marker.exists(),
            "timed-out ASTAP continued running and wrote a late result"
        );

        let _ = std::fs::remove_dir_all(dir);
    }
}
