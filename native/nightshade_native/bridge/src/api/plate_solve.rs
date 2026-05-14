// CQ-W3-API-RS: split from monolithic api.rs (audit-rust §9 / audit-arch §1.2)
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs (audit-rust §9).
use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
use crate::filter_matching::find_filter_match;
use crate::state::*;
use crate::storage::{AppSettings, ObserverLocation};
use crate::unified_device_ops::create_unified_device_ops;
use nightshade_imaging::{
    calculate_airmass, validate_fits_header, validate_image, write_fits, BayerPattern,
    DebayerAlgorithm, FitsHeader, ImageData,
};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::sync::RwLock;
// Sibling-module items via the parent's pub use re-exports.
use super::*;

// =============================================================================
// REAL PLATE SOLVING
// =============================================================================

/// Plate solve result
#[derive(Debug, Clone)]
pub struct PlateSolveResult {
    pub success: bool,
    pub ra: f64,           // degrees
    pub dec: f64,          // degrees
    pub pixel_scale: f64,  // arcsec/pixel
    pub rotation: f64,     // degrees, East of North
    pub field_width: f64,  // degrees
    pub field_height: f64, // degrees
    pub solve_time_secs: f64,
    pub error: Option<String>,
}

/// Check if a plate solver is available
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_plate_solver_available() -> bool {
    nightshade_imaging::is_solver_available()
}

/// Get the path to the installed plate solver
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_plate_solver_path() -> Option<String> {
    nightshade_imaging::get_solver_path().map(|p| p.to_string_lossy().to_string())
}

/// Plate solve an image file (blind solve)
pub async fn api_plate_solve_blind(file_path: String) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Blind plate solving: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Run actual plate solve using ASTAP
    let result = nightshade_imaging::blind_solve(path);

    Ok(PlateSolveResult {
        success: result.success,
        ra: result.ra,
        dec: result.dec,
        pixel_scale: result.pixel_scale,
        rotation: result.rotation,
        field_width: result.field_width,
        field_height: result.field_height,
        solve_time_secs: result.solve_time_secs,
        error: result.error,
    })
}

/// Plate solve an image with hint coordinates
pub async fn api_plate_solve_near(
    file_path: String,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!(
        "Plate solving near RA:{:.2}°, Dec:{:.2}°: {}",
        hint_ra,
        hint_dec,
        file_path
    );

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Run actual plate solve using ASTAP with hints
    let result = nightshade_imaging::solve_near(path, hint_ra, hint_dec, search_radius);

    Ok(PlateSolveResult {
        success: result.success,
        ra: result.ra,
        dec: result.dec,
        pixel_scale: result.pixel_scale,
        rotation: result.rotation,
        field_width: result.field_width,
        field_height: result.field_height,
        solve_time_secs: result.solve_time_secs,
        error: result.error,
    })
}

// =============================================================================
// PLATE SOLVER UX (detection / verification / config)
// =============================================================================

/// Detection snapshot returned to the settings UI. Contains everything
/// needed to render the "ASTAP detected at /path/to/astap.exe (catalog: V17
/// to mag 17)" status banner without further FFI round-trips.
#[derive(Debug, Clone)]
pub struct PlateSolverDetection {
    /// Detected ASTAP executable path. `None` when ASTAP is not installed.
    pub astap_path: Option<String>,
    /// Detected `solve-field` path. `None` when astrometry.net is not
    /// installed.
    pub astrometry_path: Option<String>,
    /// Detected ASTAP star catalog. `None` when ASTAP was detected but no
    /// catalog could be located (the user must point us at one).
    pub catalog_name: Option<String>,
    /// Approximate magnitude limit the detected catalog covers (e.g. 17.0
    /// for V17). `None` when the catalog flavour isn't recognised.
    pub catalog_magnitude_limit: Option<f32>,
    /// Directory containing the detected catalog.
    pub catalog_path: Option<String>,
}

/// Detailed information about a verified solver binary. See
/// `api_platesolve_verify`.
#[derive(Debug, Clone)]
pub struct PlateSolverInfo {
    /// Absolute path of the verified binary.
    pub path: String,
    /// `"ASTAP"`, `"Astrometry.net"`, or `"Unknown"`.
    pub flavour: String,
    /// First non-empty line of the binary's `--help` output, useful for
    /// surfacing the build version in the settings UI.
    pub version_line: String,
}

/// Persisted plate-solver UX configuration. Mirrors `storage::PlateSolverPreference`
/// 1:1; lives in this module so flutter_rust_bridge can generate Dart
/// bindings without exporting the storage internals.
#[derive(Debug, Clone)]
pub struct PlateSolverConfigPayload {
    pub astap_path: String,
    pub astrometry_path: String,
    pub catalog_path: String,
    pub solver_choice: String,
}

impl PlateSolverConfigPayload {
    fn into_pref(self) -> crate::storage::PlateSolverPreference {
        crate::storage::PlateSolverPreference {
            astap_path: self.astap_path,
            astrometry_path: self.astrometry_path,
            catalog_path: self.catalog_path,
            solver_choice: self.solver_choice,
        }
    }
}

impl From<crate::storage::PlateSolverPreference> for PlateSolverConfigPayload {
    fn from(pref: crate::storage::PlateSolverPreference) -> Self {
        Self {
            astap_path: pref.astap_path,
            astrometry_path: pref.astrometry_path,
            catalog_path: pref.catalog_path,
            solver_choice: pref.solver_choice,
        }
    }
}

/// Detect installed plate solvers and catalogs. Honours the user-configured
/// override paths from the persisted plate-solver preference, if any. Does
/// not run the binaries — that's `api_platesolve_verify`.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_detect() -> Result<PlateSolverDetection, NightshadeError> {
    use std::path::Path;

    // Why: first-run / no-saved-prefs is the dominant case — return defaults
    // so detection still scans standard install paths. A storage IO error
    // here is non-fatal because the only state read is overlay-on-defaults;
    // the user can still set explicit paths in the Plate Solving settings.
    let pref = crate::state::get_platesolver_preference()
        .unwrap_or_else(|_| crate::storage::PlateSolverPreference::default());

    let configured_astap = if pref.astap_path.is_empty() {
        None
    } else {
        Some(pref.astap_path.clone())
    };
    let configured_astrometry = if pref.astrometry_path.is_empty() {
        None
    } else {
        Some(pref.astrometry_path.clone())
    };
    let configured_catalog = if pref.catalog_path.is_empty() {
        None
    } else {
        Some(pref.catalog_path.clone())
    };

    // Probing involves filesystem reads which are fast but blocking. The
    // function is sync — callers can wrap it if they need it off the UI
    // isolate.
    nightshade_imaging::invalidate_solver_availability_cache();

    let astap_path = nightshade_imaging::find_astap_with_override(
        configured_astap.as_deref().map(Path::new),
    );
    let astrometry_path = nightshade_imaging::find_astrometry_with_override(
        configured_astrometry.as_deref().map(Path::new),
    );

    let catalog = nightshade_imaging::detect_astap_catalog(
        astap_path.as_deref(),
        configured_catalog.as_deref().map(Path::new),
    );

    Ok(PlateSolverDetection {
        astap_path: astap_path.map(|p| p.to_string_lossy().to_string()),
        astrometry_path: astrometry_path.map(|p| p.to_string_lossy().to_string()),
        catalog_name: catalog.as_ref().and_then(|c| {
            if c.name.is_empty() {
                None
            } else {
                Some(c.name.clone())
            }
        }),
        catalog_magnitude_limit: catalog.as_ref().and_then(|c| c.magnitude_limit),
        catalog_path: catalog.as_ref().map(|c| c.path.to_string_lossy().to_string()),
    })
}

/// Run the supplied solver binary with `--help` to confirm it's healthy.
/// Returns a `PlateSolverInfo` with the detected flavour and version banner,
/// or a `NightshadeError` if the binary is missing / fails to spawn / exits
/// with non-zero status and empty output.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_verify(executable_path: String) -> Result<PlateSolverInfo, NightshadeError> {
    use std::path::Path;
    let path = Path::new(&executable_path);
    match nightshade_imaging::verify_solver(path) {
        Ok(info) => Ok(PlateSolverInfo {
            path: info.path.to_string_lossy().to_string(),
            flavour: info.flavour,
            version_line: info.version_line,
        }),
        Err(e) => Err(NightshadeError::OperationFailed(e.to_string())),
    }
}

/// Read the persisted plate-solver configuration. Falls back to defaults if
/// the storage was never written.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_get_config() -> Result<PlateSolverConfigPayload, NightshadeError> {
    let pref = crate::state::get_platesolver_preference()
        .map_err(NightshadeError::OperationFailed)?;
    Ok(pref.into())
}

/// Persist a new plate-solver configuration. Invalidates the solver
/// availability cache so the next `api_is_plate_solver_available()` call
/// re-probes the filesystem with the new paths.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_set_config(
    config: PlateSolverConfigPayload,
) -> Result<(), NightshadeError> {
    let pref = config.into_pref();
    crate::state::save_platesolver_preference(&pref).map_err(NightshadeError::OperationFailed)?;
    nightshade_imaging::invalidate_solver_availability_cache();
    Ok(())
}