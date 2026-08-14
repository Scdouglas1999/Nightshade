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

/// Solves currently running, keyed by the frame they are solving.
///
/// The admission gate above serialises solves; it does not stop two callers
/// from solving the *same frame twice in a row*. Live evidence (ND-E2): a
/// single snapshot produced a hinted solve and, 4 ms later, a second BLIND
/// solve of the same file — two `astap_cli` processes counted concurrently by
/// a 5 ms poller — and the blind one threw away the position hint the first
/// one had. One frame has one answer, so the second caller waits for the
/// first caller's result instead of launching a solver of its own.
type SolveOutcome = Result<PlateSolveResult, String>;
type SolveBroadcast = tokio::sync::broadcast::Sender<Arc<SolveOutcome>>;
static IN_FLIGHT_SOLVES: OnceLock<std::sync::Mutex<HashMap<String, SolveBroadcast>>> =
    OnceLock::new();

fn in_flight_solves() -> &'static std::sync::Mutex<HashMap<String, SolveBroadcast>> {
    IN_FLIGHT_SOLVES.get_or_init(|| std::sync::Mutex::new(HashMap::new()))
}

/// What a caller brings to a solve of the same frame.
///
/// WF-SN-N2: coalescing stopped the two concurrent solver processes but left
/// WHICH of them leads to a race. The live log shows both outcomes for the same
/// button 103 s apart: once the blind caller led and the hinted one waited,
/// once the reverse. On the simulator a blind solve costs 0.04 s so the
/// coin-flip is invisible; on a real rig a blind ASTAP run is tens of seconds
/// against a few for a hinted one, and it is the case that can lock onto the
/// wrong field — so half the annotate/centering solves would pay the blind
/// cost while a good position hint sat unused in the other caller.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum SolvePreference {
    /// The caller knows roughly where the telescope is pointing (and/or the
    /// field scale). Always leads.
    Hinted,
    /// The caller knows nothing about the field. Yields the lead briefly so a
    /// hinted caller for the same frame can take it.
    Blind,
}

/// How long a blind caller waits for a hinted caller to claim the same frame.
///
/// The two live requests for one snapshot arrived 4 ms and 11 ms apart. This is
/// an order of magnitude above that and an order of magnitude below the cost it
/// avoids; a blind solve that really is alone pays it once and is otherwise
/// unaffected.
const BLIND_YIELD_WINDOW: Duration = Duration::from_millis(150);
const BLIND_YIELD_POLL: Duration = Duration::from_millis(5);

fn solve_in_flight(key: &str) -> bool {
    in_flight_solves()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .contains_key(key)
}

/// Removes the in-flight entry even if the solve future is dropped or panics,
/// so one abandoned solve cannot wedge every later solve of that frame.
struct InFlightGuard(String);

impl Drop for InFlightGuard {
    fn drop(&mut self) {
        if let Ok(mut map) = in_flight_solves().lock() {
            map.remove(&self.0);
        }
    }
}

/// Run `solve` for `file_path`, or — if that exact frame is already being
/// solved — wait for the running solve and return its result.
///
/// `label` names the caller in the log so the two callers of a coalesced pair
/// are identifiable afterwards; that log line is the only way the double-solve
/// showed up at all.
pub(crate) async fn coalesced_solve<F, Fut>(
    file_path: &str,
    label: &str,
    preference: SolvePreference,
    solve: F,
) -> Result<PlateSolveResult, NightshadeError>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<PlateSolveResult, NightshadeError>>,
{
    // Canonicalise so `./frame.fits` and `/tmp/frame.fits` are one frame. A
    // path that cannot be canonicalised (not yet written, odd mount) keys on
    // its own spelling rather than failing the solve.
    let key = std::fs::canonicalize(file_path)
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| file_path.to_string());

    // A blind caller offers the lead to a hinted caller for the same frame
    // before claiming it. Nothing is skipped either way: whoever leads,
    // exactly one solver runs and both callers get its answer.
    if preference == SolvePreference::Blind && !solve_in_flight(&key) {
        let deadline = Instant::now() + BLIND_YIELD_WINDOW;
        let mut yielded = false;
        while Instant::now() < deadline {
            tokio::time::sleep(BLIND_YIELD_POLL).await;
            if solve_in_flight(&key) {
                yielded = true;
                break;
            }
        }
        if yielded {
            tracing::info!(
                "Plate solve ({label}): a hinted solve of {key} took the lead; \
                 waiting for it rather than solving blind"
            );
        }
    }

    let (leader_tx, follower_rx) = {
        let mut map = in_flight_solves()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match map.get(&key) {
            Some(tx) => (None, Some(tx.subscribe())),
            None => {
                let (tx, _rx) = tokio::sync::broadcast::channel(1);
                map.insert(key.clone(), tx.clone());
                (Some(tx), None)
            }
        }
    };

    if let Some(mut rx) = follower_rx {
        tracing::info!(
            "Plate solve ({label}): {key} is already being solved; waiting for that \
             result instead of starting a second solver process"
        );
        match rx.recv().await {
            Ok(outcome) => return (*outcome).clone().map_err(NightshadeError::OperationFailed),
            Err(e) => {
                tracing::warn!(
                    "Plate solve ({label}): the solve of {key} we were waiting on ended \
                     without publishing a result ({e}); solving it here instead"
                );
                return solve().await;
            }
        }
    }

    let _guard = InFlightGuard(key);
    let result = solve().await;
    if let Some(tx) = leader_tx {
        // Publish before the guard removes the entry: a follower that is
        // already subscribed gets the answer, and any caller arriving after
        // this starts a fresh solve.
        let _ = tx.send(Arc::new(
            result
                .as_ref()
                .map(Clone::clone)
                .map_err(ToString::to_string),
        ));
    }
    result
}

/// Take the admission gate, saying so when the caller has to wait.
///
/// A solve that queues behind another solve looks, from the outside, exactly
/// like a slow solve. Naming the wait is what turns "the solver is slow"
/// into "two callers are solving at once".
async fn acquire_solve_gate(label: &str) -> tokio::sync::MutexGuard<'static, ()> {
    let gate = plate_solve_gate();
    match gate.try_lock() {
        Ok(guard) => guard,
        Err(_) => {
            let waited = Instant::now();
            let guard = gate.lock().await;
            tracing::info!(
                "Plate solve ({label}): waited {:.1}s for another solve to finish \
                 (one solver process at a time)",
                waited.elapsed().as_secs_f64()
            );
            guard
        }
    }
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

    /// The plate scale these hints describe, in arcsec per pixel **of the
    /// frame as taken** — pitch scaled by binning, which is the number a
    /// solver turns into a field size.
    ///
    /// This is the value the solver is handed as `-fov`. It stayed unused for
    /// three waves: the wizard computed it, logged it in [`log_scale`], and
    /// then called a solve that took no scale argument.
    ///
    /// [`log_scale`]: SolveHints::log_scale
    pub(crate) fn arcsec_per_px(&self) -> Option<f64> {
        let focal = self.focal_length_mm.filter(|f| f.is_finite() && *f > 0.0)?;
        let (pitch_x, _) = self.pixel_size_um?;
        let binned_pitch = pitch_x * f64::from(self.binning.0.max(1));
        let scale = 206.264_806 * binned_pitch / focal;
        scale.is_finite().then_some(scale).filter(|s| *s > 0.0)
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

/// The field scale to hand a solve of `path`, in arcsec/pixel.
///
/// Order of authority:
/// 1. what the caller measured for this exact frame (`explicit`),
/// 2. what the frame's own header declares — right even for an imported frame
///    shot on somebody else's rig,
/// 3. the active profile's optics and the active camera's pitch.
///
/// A rig that supplies none of the three solves exactly as it did before: no
/// `-fov`, blind scale ladder, and the warning [`SolveHints::log_scale`]
/// already emits.
pub(crate) async fn resolve_solve_scale(
    path: &std::path::Path,
    explicit: Option<f64>,
) -> Option<f64> {
    if let Some(scale) = explicit.filter(|s| s.is_finite() && *s > 0.0) {
        return Some(scale);
    }
    if let Some(scale) = nightshade_imaging::fits_scale_arcsec_per_px(path) {
        tracing::debug!(
            "Plate solve: field scale {:.2}\"/px read from the frame's own header",
            scale
        );
        return Some(scale);
    }
    let scale = gather_solve_hints().await.arcsec_per_px();
    if let Some(scale) = scale {
        tracing::debug!(
            "Plate solve: field scale {:.2}\"/px from the active profile (the frame \
             carries no FOCALLEN/XPIXSZ)",
            scale
        );
    }
    scale
}

/// Plate solve an image file (blind solve)
///
/// FFI entry point; its signature is fixed by the generated bridge. Rust
/// callers that already measured the field scale call
/// [`plate_solve_blind_scaled`] instead of re-deriving it.
pub async fn api_plate_solve_blind(
    file_path: String,
    timeout_secs: Option<u32>,
) -> Result<PlateSolveResult, NightshadeError> {
    plate_solve_blind_scaled(file_path, timeout_secs, None).await
}

/// Blind (position-unknown) solve that is still told the field scale.
pub(crate) async fn plate_solve_blind_scaled(
    file_path: String,
    timeout_secs: Option<u32>,
    hint_scale: Option<f64>,
) -> Result<PlateSolveResult, NightshadeError> {
    coalesced_solve(&file_path, "blind", SolvePreference::Blind, || {
        plate_solve_blind_inner(&file_path, timeout_secs, hint_scale)
    })
    .await
}

async fn plate_solve_blind_inner(
    file_path: &str,
    timeout_secs: Option<u32>,
    hint_scale: Option<f64>,
) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Blind plate solving: {}", file_path);
    let _solve_guard = acquire_solve_gate("blind").await;

    // Ensure the imaging crate sees the user's configured paths before
    // PlateSolverConfig::default() is called inside blind_solve.
    apply_saved_preference_to_imaging();

    let timeout_secs = validate_solver_timeout(timeout_secs)?;
    let path = Path::new(file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Blind is about POSITION. The scale is still known and still sent.
    let hint_scale = resolve_solve_scale(path, hint_scale).await;

    // External solvers are blocking subprocesses. Keep them off the async
    // runtime worker and pass the UI/headless timeout through to the process
    // runner, which kills and reaps the child on expiry.
    let owned_path = path.to_path_buf();
    let result = tokio::task::spawn_blocking(move || {
        nightshade_imaging::blind_solve_with_timeout(&owned_path, timeout_secs, hint_scale)
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
///
/// FFI entry point; its signature is fixed by the generated bridge. Rust
/// callers with a measured field scale call [`plate_solve_near_scaled`].
pub async fn api_plate_solve_near(
    file_path: String,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
    timeout_secs: Option<u32>,
) -> Result<PlateSolveResult, NightshadeError> {
    plate_solve_near_scaled(
        file_path,
        hint_ra,
        hint_dec,
        search_radius,
        timeout_secs,
        None,
    )
    .await
}

/// Near solve that is told the field scale as well as the position.
pub(crate) async fn plate_solve_near_scaled(
    file_path: String,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
    timeout_secs: Option<u32>,
    hint_scale: Option<f64>,
) -> Result<PlateSolveResult, NightshadeError> {
    coalesced_solve(&file_path, "near", SolvePreference::Hinted, || {
        plate_solve_near_inner(
            &file_path,
            hint_ra,
            hint_dec,
            search_radius,
            timeout_secs,
            hint_scale,
        )
    })
    .await
}

async fn plate_solve_near_inner(
    file_path: &str,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
    timeout_secs: Option<u32>,
    hint_scale: Option<f64>,
) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!(
        "Plate solving near RA:{:.2}°, Dec:{:.2}°: {}",
        hint_ra,
        hint_dec,
        file_path
    );
    let _solve_guard = acquire_solve_gate("near").await;

    // Ensure the imaging crate sees the user's configured paths before
    // PlateSolverConfig::default() is called inside solve_near.
    apply_saved_preference_to_imaging();

    let timeout_secs = validate_solver_timeout(timeout_secs)?;
    let path = Path::new(file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // A position hint says WHERE, not HOW WIDE: without this a near solve
    // still climbs down ASTAP's blind field-of-view ladder.
    let hint_scale = resolve_solve_scale(path, hint_scale).await;

    let owned_path = path.to_path_buf();
    let result = tokio::task::spawn_blocking(move || {
        nightshade_imaging::solve_near_with_timeout(
            &owned_path,
            hint_ra,
            hint_dec,
            search_radius,
            timeout_secs,
            hint_scale,
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

/// One frame, one solve (ND-E2).
#[cfg(test)]
mod solve_coalescing_tests {
    use super::{coalesced_solve, PlateSolveResult, SolvePreference};
    use crate::error::NightshadeError;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    fn result_at(ra: f64) -> PlateSolveResult {
        PlateSolveResult {
            success: true,
            ra,
            dec: 0.0,
            pixel_scale: 1.29,
            rotation: 0.0,
            field_width: 0.0,
            field_height: 0.0,
            solve_time_secs: 0.0,
            error: None,
            cd1_1: 0.0,
            cd1_2: 0.0,
            cd2_1: 0.0,
            cd2_2: 0.0,
            sip_a_order: 0,
            sip_b_order: 0,
            sip_a_coeffs: Vec::new(),
            sip_b_coeffs: Vec::new(),
            sip_ap_order: 0,
            sip_bp_order: 0,
            sip_ap_coeffs: Vec::new(),
            sip_bp_coeffs: Vec::new(),
        }
    }

    /// The live shape: two callers hit the same snapshot 4 ms apart and two
    /// `astap_cli` processes ran at once, the second one blind. The second
    /// caller now waits for the first caller's answer.
    #[tokio::test]
    async fn two_callers_on_one_frame_run_one_solver() {
        let runs = Arc::new(AtomicUsize::new(0));
        let path = "/tmp/nightshade-coalesce-one-frame.fits";

        let solve = |runs: Arc<AtomicUsize>| async move {
            runs.fetch_add(1, Ordering::SeqCst);
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
            Ok::<_, NightshadeError>(result_at(42.0))
        };

        let (first, second) = tokio::join!(
            coalesced_solve(path, "near", SolvePreference::Hinted, || solve(
                runs.clone()
            )),
            async {
                // The follower arrives while the leader is still solving.
                tokio::time::sleep(std::time::Duration::from_millis(5)).await;
                coalesced_solve(path, "blind", SolvePreference::Blind, || {
                    solve(runs.clone())
                })
                .await
            }
        );

        assert_eq!(runs.load(Ordering::SeqCst), 1, "a second solver ran");
        assert_eq!(first.unwrap().ra, 42.0);
        assert_eq!(
            second.unwrap().ra,
            42.0,
            "the follower must get the leader's answer, not a blind re-solve"
        );
    }

    /// WF-SN-N2: coalescing left the LEAD to a race. Same snapshot, same
    /// button: at 04:06:37 the blind caller led and the hinted one waited; at
    /// 04:08:20 the reverse. The one that leads is the one whose hints the
    /// solver gets, so half the solves threw away a good position hint and ran
    /// the slow, mis-lockable blind path instead.
    #[tokio::test]
    async fn a_hinted_caller_leads_even_when_the_blind_one_arrives_first() {
        let runs = Arc::new(AtomicUsize::new(0));
        let path = "/tmp/nightshade-coalesce-hint-wins.fits";

        // Each closure reports WHICH caller ran the solver, via the RA.
        let solve = |runs: Arc<AtomicUsize>, ra: f64| async move {
            runs.fetch_add(1, Ordering::SeqCst);
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
            Ok::<_, NightshadeError>(result_at(ra))
        };

        let (blind, hinted) = tokio::join!(
            coalesced_solve(path, "blind", SolvePreference::Blind, || solve(
                runs.clone(),
                1.0
            )),
            async {
                // The live pair arrived 4-11 ms apart.
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                coalesced_solve(path, "near", SolvePreference::Hinted, || {
                    solve(runs.clone(), 2.0)
                })
                .await
            }
        );

        assert_eq!(runs.load(Ordering::SeqCst), 1, "two solvers ran");
        assert_eq!(
            hinted.unwrap().ra,
            2.0,
            "the hinted caller must be the one that runs the solver"
        );
        assert_eq!(
            blind.unwrap().ra,
            2.0,
            "the blind caller takes the hinted answer"
        );
    }

    /// The blind caller must not wait forever for a hinted caller that never
    /// comes — the common case is a blind solve that is genuinely alone.
    #[tokio::test]
    async fn a_lone_blind_caller_still_solves() {
        let runs = Arc::new(AtomicUsize::new(0));
        let path = "/tmp/nightshade-coalesce-lone-blind.fits";
        let solve = |runs: Arc<AtomicUsize>| async move {
            runs.fetch_add(1, Ordering::SeqCst);
            Ok::<_, NightshadeError>(result_at(9.0))
        };

        let started = std::time::Instant::now();
        let result = coalesced_solve(path, "blind", SolvePreference::Blind, || {
            solve(runs.clone())
        })
        .await;

        assert_eq!(runs.load(Ordering::SeqCst), 1);
        assert_eq!(result.unwrap().ra, 9.0);
        assert!(
            started.elapsed() < std::time::Duration::from_millis(1000),
            "the yield window must be a short offer, not a stall"
        );
    }

    /// Coalescing is per frame, not a global one-solve-per-process rule.
    #[tokio::test]
    async fn two_frames_still_get_two_solves() {
        let runs = Arc::new(AtomicUsize::new(0));
        let solve = |runs: Arc<AtomicUsize>| async move {
            runs.fetch_add(1, Ordering::SeqCst);
            Ok::<_, NightshadeError>(result_at(1.0))
        };

        let _ = coalesced_solve(
            "/tmp/nightshade-coalesce-a.fits",
            "near",
            SolvePreference::Hinted,
            || solve(runs.clone()),
        )
        .await;
        let _ = coalesced_solve(
            "/tmp/nightshade-coalesce-b.fits",
            "near",
            SolvePreference::Hinted,
            || solve(runs.clone()),
        )
        .await;

        assert_eq!(runs.load(Ordering::SeqCst), 2);
    }

    /// A finished solve must release its frame, or the first solve of a file
    /// would be the only solve of that file for the life of the process —
    /// re-solving after a re-point would silently return the old answer.
    #[tokio::test]
    async fn a_finished_solve_releases_its_frame() {
        let runs = Arc::new(AtomicUsize::new(0));
        let path = "/tmp/nightshade-coalesce-sequential.fits";
        let solve = |runs: Arc<AtomicUsize>| async move {
            runs.fetch_add(1, Ordering::SeqCst);
            Ok::<_, NightshadeError>(result_at(7.0))
        };

        let _ = coalesced_solve(path, "near", SolvePreference::Hinted, || {
            solve(runs.clone())
        })
        .await;
        let _ = coalesced_solve(path, "near", SolvePreference::Hinted, || {
            solve(runs.clone())
        })
        .await;

        assert_eq!(runs.load(Ordering::SeqCst), 2);
    }
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

    /// The scale handed to the solver is the scale of the frame as taken.
    /// 600 mm at 3.76 um is 1.29"/px unbinned and 2.59"/px at 2x2 — one of
    /// those two numbers describes the pixels ASTAP is about to measure.
    #[test]
    fn the_solver_scale_is_the_binned_sampling() {
        let unbinned = SolveHints {
            focal_length_mm: Some(600.0),
            pixel_size_um: Some((3.76, 3.76)),
            binning: (1, 1),
        };
        assert!((unbinned.arcsec_per_px().unwrap() - 1.292_59).abs() < 1e-4);

        let binned = SolveHints {
            binning: (2, 2),
            ..unbinned.clone()
        };
        assert!((binned.arcsec_per_px().unwrap() - 2.585_18).abs() < 1e-4);
    }

    /// A rig that reports no optics gets no hint — the solver searches, as it
    /// always did. A fabricated scale would be worse than none.
    #[test]
    fn missing_optics_produce_no_scale_rather_than_a_guess() {
        assert_eq!(SolveHints::default().arcsec_per_px(), None);
        assert_eq!(
            SolveHints {
                focal_length_mm: Some(600.0),
                pixel_size_um: None,
                binning: (1, 1),
            }
            .arcsec_per_px(),
            None
        );
        assert_eq!(
            SolveHints {
                focal_length_mm: Some(0.0),
                pixel_size_um: Some((3.76, 3.76)),
                binning: (1, 1),
            }
            .arcsec_per_px(),
            None
        );
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
