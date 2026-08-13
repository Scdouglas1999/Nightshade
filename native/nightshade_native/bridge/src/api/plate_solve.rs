// split from monolithic api.rs
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs.
use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
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

/// Process-wide admission gate shared by UI, headless HTTP, sequencer, and
/// recovery callers. External solvers write sibling `.ini`/`.wcs` artifacts;
/// allowing overlapping runs can mix or delete another solve's result.
static PLATE_SOLVE_GATE: OnceLock<Mutex<()>> = OnceLock::new();
const DEFAULT_SOLVER_TIMEOUT_SECS: u32 = 60;
const MAX_SOLVER_TIMEOUT_SECS: u32 = 3600;

fn plate_solve_gate() -> &'static Mutex<()> {
    PLATE_SOLVE_GATE.get_or_init(|| Mutex::new(()))
}

fn validate_solver_timeout(timeout_secs: Option<u32>) -> Result<u32, NightshadeError> {
    let timeout = timeout_secs.unwrap_or(DEFAULT_SOLVER_TIMEOUT_SECS);
    if timeout == 0 || timeout > MAX_SOLVER_TIMEOUT_SECS {
        return Err(NightshadeError::InvalidParameter(format!(
            "Plate-solve timeout must be between 1 and {MAX_SOLVER_TIMEOUT_SECS} seconds"
        )));
    }
    Ok(timeout)
}

// =============================================================================
// SOLVER HINTS
// =============================================================================

/// The field-scale facts a solve can be told up front.
///
/// A solver given no scale has to find one. ASTAP sweeps its field-of-view
/// ladder downward from ~9.5°, and on a narrow field that sweep is the
/// difference between a 0.3 s solve and five consecutive failures on the same
/// frames, same catalogs, same sensor. Both numbers here are measured rather
/// than assumed — the focal length is the operator's own profile entry and the
/// pitch is what the camera reports — so a rig that reports neither contributes
/// no card and the solver behaves exactly as it did before.
///
/// Gather once per solve with [`gather_solve_hints`] and hand the result to
/// whichever writer stamps the frame the solver will read: the solver never
/// sees these values as flags, it reads them out of the FITS header.
#[derive(Debug, Clone)]
pub(crate) struct SolveHints {
    /// Telescope focal length in millimetres (FITS `FOCALLEN`).
    pub(crate) focal_length_mm: Option<f64>,
    /// UNBINNED sensor pixel pitch in microns, `(x, y)` (FITS `PIXSIZE1/2`).
    pub(crate) pixel_size_um: Option<(f64, f64)>,
    /// Binning the frame was taken at. `XPIXSZ`/`YPIXSZ` are the pitch scaled
    /// by it, which is what a solver needs to derive the plate scale.
    pub(crate) binning: (i32, i32),
}

impl Default for SolveHints {
    fn default() -> Self {
        Self {
            focal_length_mm: None,
            pixel_size_um: None,
            // Unbinned, so a caller that never learned the binning still
            // stamps a truthful pitch rather than zeroing it.
            binning: (1, 1),
        }
    }
}

impl SolveHints {
    /// Stamp the scale cards onto a FITS header, using the same keywords and
    /// the same binning convention as a saved capture
    /// (`api::imaging::write_fits_with_header`), so a solver cannot tell a
    /// solve frame from a light frame.
    pub(crate) fn apply_to_fits_header(&self, header: &mut nightshade_imaging::FitsHeader) {
        if let Some(focal) = self.focal_length_mm {
            header.set_float("FOCALLEN", focal);
        }
        if let Some((pitch_x, pitch_y)) = self.pixel_size_um {
            header.set_float("PIXSIZE1", pitch_x);
            header.set_float("PIXSIZE2", pitch_y);
            header.set_float("XPIXSZ", pitch_x * f64::from(self.binning.0));
            header.set_float("YPIXSZ", pitch_y * f64::from(self.binning.1));
        }
        header.set_int("XBINNING", i64::from(self.binning.0));
        header.set_int("YBINNING", i64::from(self.binning.1));
    }

    /// A blind scale sweep is not an error and logs no warning of its own, so
    /// without this line the fast reliable case and the slow unreliable one
    /// look identical afterwards.
    pub(crate) fn log_scale(&self, context: &str) {
        match (self.focal_length_mm, self.pixel_size_um) {
            (Some(focal), Some((pitch_x, _))) => tracing::info!(
                "{} scale hint: focal length {:.1} mm, pixel pitch {:.2} um \
                 ({:.2}\"/px unbinned)",
                context,
                focal,
                pitch_x,
                206.264_806 * pitch_x / focal
            ),
            _ => tracing::warn!(
                "{} has no field-scale hint (focal length {}, pixel pitch {}); the \
                 solver must search for the scale, which is slower and can fail on a field it \
                 would otherwise solve. Set the telescope focal length on the active equipment \
                 profile.",
                context,
                self.focal_length_mm
                    .map_or_else(|| "unknown".to_string(), |v| format!("{v:.1} mm")),
                self.pixel_size_um
                    .map_or_else(|| "unknown".to_string(), |(x, _)| format!("{x:.2} um")),
            ),
        }
    }
}

/// Read the active profile's optics and the active camera's pixel pitch so a
/// solve can be told the field scale.
///
/// Shared by every production solve path — the sequencer/imaging solve in
/// `unified_device_ops::plate_solve` and the polar-alignment frames — so none
/// of them can quietly go back to solving blind. A camera that cannot be
/// queried is logged and skipped, never guessed at.
pub(crate) async fn gather_solve_hints() -> SolveHints {
    gather_solve_hints_for_camera(None).await
}

/// As [`gather_solve_hints`], but for a caller that is imaging through a
/// camera of its own rather than the profile's imaging camera.
///
/// The pitch has to come from the camera that took the frame: stamping the
/// profile camera's pitch onto a frame from a different sensor would hand the
/// solver a confidently wrong scale, which is worse than handing it none.
pub(crate) async fn gather_solve_hints_for_camera(camera_id: Option<&str>) -> SolveHints {
    let mut hints = SolveHints::default();

    let Some(profile) = crate::get_state().get_profile().await else {
        return hints;
    };

    hints.focal_length_mm =
        Some(profile.telescope_focal_length).filter(|focal| focal.is_finite() && *focal > 0.0);

    let camera_id = match camera_id {
        Some(id) => id,
        None => {
            let Some(id) = profile.camera_id.as_deref() else {
                return hints;
            };
            id
        }
    };

    match crate::api::devices::camera::get_camera_status(camera_id.to_string()).await {
        Ok(status) => {
            // 0.0 is a driver saying "I don't know", not a pitch.
            if status.pixel_size_x > 0.0 && status.pixel_size_y > 0.0 {
                hints.pixel_size_um = Some((status.pixel_size_x, status.pixel_size_y));
            }
            if status.bin_x > 0 && status.bin_y > 0 {
                hints.binning = (status.bin_x, status.bin_y);
            }
        }
        Err(e) => tracing::debug!(
            "Plate solve: camera '{}' status unavailable ({}); solving without a \
             pixel-scale hint",
            camera_id,
            e
        ),
    }

    hints
}

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
    pub cd1_1: f64, // raw CD matrix, deg/pixel
    pub cd1_2: f64,
    pub cd2_1: f64,
    pub cd2_2: f64,
    pub sip_a_order: u32, // SIP forward distortion, 0 when absent
    pub sip_b_order: u32,
    pub sip_a_coeffs: Vec<f64>, // row-major (i, j): index i * (order + 1) + j
    pub sip_b_coeffs: Vec<f64>,
    pub sip_ap_order: u32, // SIP inverse distortion, 0 when absent
    pub sip_bp_order: u32,
    pub sip_ap_coeffs: Vec<f64>,
    pub sip_bp_coeffs: Vec<f64>,
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

/// Apply the persisted plate-solver preference to the imaging crate's
/// process-global before each solve. This ensures that paths saved in
/// Settings → Plate Solving are honoured even if the app was restarted
/// or `set_solver_preference` was never called at startup.
///
/// Why call it here rather than only at `api_platesolve_set_config` time:
/// the imaging crate is a separate compilation unit; its global resets to
/// "no override" on every cold launch. Calling this here makes each solve
/// self-healing without requiring a separate startup hook.
fn apply_saved_preference_to_imaging() {
    // If storage is not initialised (headless / test mode), treat as no-op.
    let pref = match crate::state::get_platesolver_preference() {
        Ok(p) => p,
        Err(e) => {
            tracing::warn!(
                "Could not load plate-solver preference before solve (storage not ready?): {}",
                e
            );
            return;
        }
    };
    nightshade_imaging::set_solver_preference(
        if pref.astap_path.is_empty() {
            None
        } else {
            Some(pref.astap_path.as_str())
        },
        if pref.astrometry_path.is_empty() {
            None
        } else {
            Some(pref.astrometry_path.as_str())
        },
        if pref.catalog_path.is_empty() {
            None
        } else {
            Some(pref.catalog_path.as_str())
        },
        Some(pref.solver_choice.as_str()),
    );
}

/// Plate solve an image file (blind solve)
pub async fn api_plate_solve_blind(
    file_path: String,
    timeout_secs: Option<u32>,
) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Blind plate solving: {}", file_path);
    let _solve_guard = plate_solve_gate().lock().await;

    // Ensure the imaging crate sees the user's configured paths before
    // PlateSolverConfig::default() is called inside blind_solve.
    apply_saved_preference_to_imaging();

    let timeout_secs = validate_solver_timeout(timeout_secs)?;
    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // External solvers are blocking subprocesses. Keep them off the async
    // runtime worker and pass the UI/headless timeout through to the process
    // runner, which kills and reaps the child on expiry.
    let owned_path = path.to_path_buf();
    let result = tokio::task::spawn_blocking(move || {
        nightshade_imaging::blind_solve_with_timeout(&owned_path, timeout_secs)
    })
    .await
    .map_err(|error| {
        NightshadeError::OperationFailed(format!("Plate-solve task failed: {error}"))
    })?;

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
        cd1_1: result.cd1_1,
        cd1_2: result.cd1_2,
        cd2_1: result.cd2_1,
        cd2_2: result.cd2_2,
        sip_a_order: result.a_order,
        sip_b_order: result.b_order,
        sip_a_coeffs: result.a_coeffs,
        sip_b_coeffs: result.b_coeffs,
        sip_ap_order: result.ap_order,
        sip_bp_order: result.bp_order,
        sip_ap_coeffs: result.ap_coeffs,
        sip_bp_coeffs: result.bp_coeffs,
    })
}

/// Plate solve an image with hint coordinates
pub async fn api_plate_solve_near(
    file_path: String,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
    timeout_secs: Option<u32>,
) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!(
        "Plate solving near RA:{:.2}°, Dec:{:.2}°: {}",
        hint_ra,
        hint_dec,
        file_path
    );
    let _solve_guard = plate_solve_gate().lock().await;

    // Ensure the imaging crate sees the user's configured paths before
    // PlateSolverConfig::default() is called inside solve_near.
    apply_saved_preference_to_imaging();

    let timeout_secs = validate_solver_timeout(timeout_secs)?;
    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    let owned_path = path.to_path_buf();
    let result = tokio::task::spawn_blocking(move || {
        nightshade_imaging::solve_near_with_timeout(
            &owned_path,
            hint_ra,
            hint_dec,
            search_radius,
            timeout_secs,
        )
    })
    .await
    .map_err(|error| {
        NightshadeError::OperationFailed(format!("Plate-solve task failed: {error}"))
    })?;

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
        cd1_1: result.cd1_1,
        cd1_2: result.cd1_2,
        cd2_1: result.cd2_1,
        cd2_2: result.cd2_2,
        sip_a_order: result.a_order,
        sip_b_order: result.b_order,
        sip_a_coeffs: result.a_coeffs,
        sip_b_coeffs: result.b_coeffs,
        sip_ap_order: result.ap_order,
        sip_bp_order: result.bp_order,
        sip_ap_coeffs: result.ap_coeffs,
        sip_bp_coeffs: result.bp_coeffs,
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

    let astap_path =
        nightshade_imaging::find_astap_with_override(configured_astap.as_deref().map(Path::new));
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
        catalog_path: catalog
            .as_ref()
            .map(|c| c.path.to_string_lossy().to_string()),
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
    let pref =
        crate::state::get_platesolver_preference().map_err(NightshadeError::OperationFailed)?;
    Ok(pref.into())
}

/// Persist a new plate-solver configuration. Immediately propagates the new
/// paths into the imaging crate's process-global so subsequent solves (blind
/// or near, from any call site including the sequencer) use the updated paths
/// without requiring a restart. Also invalidates the solver availability
/// cache so the next `api_is_plate_solver_available()` call re-probes the
/// filesystem with the new paths.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_set_config(config: PlateSolverConfigPayload) -> Result<(), NightshadeError> {
    // Push the new paths into the imaging crate before saving, so the
    // preference is live immediately even if the subsequent storage write
    // fails (the user just configured the paths; honour them in this session).
    nightshade_imaging::set_solver_preference(
        if config.astap_path.is_empty() {
            None
        } else {
            Some(config.astap_path.as_str())
        },
        if config.astrometry_path.is_empty() {
            None
        } else {
            Some(config.astrometry_path.as_str())
        },
        if config.catalog_path.is_empty() {
            None
        } else {
            Some(config.catalog_path.as_str())
        },
        Some(config.solver_choice.as_str()),
    );

    let pref = config.into_pref();
    crate::state::save_platesolver_preference(&pref).map_err(NightshadeError::OperationFailed)?;
    nightshade_imaging::invalidate_solver_availability_cache();
    Ok(())
}

#[cfg(test)]
mod solve_hint_tests {
    use super::SolveHints;
    use nightshade_imaging::FitsHeader;

    /// `XPIXSZ` is the *binned* pitch — that is the number a solver turns into
    /// a plate scale. Stamping the unbinned pitch on a 2x2 frame would tell it
    /// the field is twice as wide as it is.
    #[test]
    fn xpixsz_is_the_pitch_the_frame_was_actually_taken_at() {
        let hints = SolveHints {
            focal_length_mm: Some(416.0),
            pixel_size_um: Some((3.76, 3.76)),
            binning: (2, 2),
        };
        let mut header = FitsHeader::new();
        hints.apply_to_fits_header(&mut header);

        assert_eq!(header.get_float("FOCALLEN"), Some(416.0));
        assert_eq!(header.get_float("PIXSIZE1"), Some(3.76));
        assert_eq!(header.get_float("XPIXSZ"), Some(7.52));
        assert_eq!(header.get_float("YPIXSZ"), Some(7.52));
        assert_eq!(header.get_int("XBINNING"), Some(2));
    }

    /// The default must be *unbinned*, not zeroed: a derived `Default` would
    /// give binning (0, 0) and multiply every pitch to 0.0 um, which is a
    /// confidently wrong scale rather than an absent one.
    #[test]
    fn default_hints_are_unbinned_and_stamp_no_scale_cards() {
        let hints = SolveHints::default();
        assert_eq!(hints.binning, (1, 1));

        let mut header = FitsHeader::new();
        hints.apply_to_fits_header(&mut header);
        assert_eq!(header.get_float("FOCALLEN"), None);
        assert_eq!(header.get_float("XPIXSZ"), None);
    }
}
