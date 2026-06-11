//! Dual-rig / multi-camera synchronized imaging — bridge API.
//!
//! Exposes the secondary (piggyback) capture loop + its dither-coordination
//! barrier to Dart. The heavy lifting lives in
//! [`nightshade_sequencer::dual_rig`]; this module is the process-wide manager
//! that:
//!
//!   * owns the single active [`SecondaryRig`] handle + its
//!     [`DitherBarrier`] (installed into the sequencer's process-wide slot so
//!     the primary's dither call sites coordinate with it);
//!   * reuses [`create_unified_device_ops`] so the secondary camera is driven
//!     through the SAME `DeviceManager` path as everything else — no duplicated
//!     driver code, no second camera "slot" concept. The device layer already
//!     stores cameras in an id-keyed map, so a second connected camera id is
//!     all that is needed.
//!
//! v1 scope (see `dual_rig.rs` for the full non-goals list): same mount,
//! secondary has no own guiding/dither/plate-solve/autofocus.

use crate::error::NightshadeError;
use crate::unified_device_ops::create_unified_device_ops;
use nightshade_sequencer::dual_rig::{
    self, DitherBarrier, InFlightDitherPolicy, SecondaryFrameMeta, SecondaryRig,
    SecondaryRigConfig, DEFAULT_DITHER_MAX_WAIT_SECS,
};
use std::sync::Arc;

/// Process-wide manager state for the single active secondary rig.
struct SecondaryRigManager {
    rig: Option<SecondaryRig>,
}

fn manager() -> &'static parking_lot::Mutex<SecondaryRigManager> {
    static MGR: std::sync::OnceLock<parking_lot::Mutex<SecondaryRigManager>> =
        std::sync::OnceLock::new();
    MGR.get_or_init(|| parking_lot::Mutex::new(SecondaryRigManager { rig: None }))
}

/// FRB-facing configuration for arming the secondary rig. Mirrors
/// [`SecondaryRigConfig`] plus the dither-coordination policy + frame metadata.
#[derive(Debug, Clone)]
pub struct SecondaryRigConfigApi {
    /// Device id of the secondary camera. MUST be a second, already-connected
    /// camera distinct from the primary's.
    pub camera_id: String,
    pub exposure_secs: f64,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub bin_x: i32,
    pub bin_y: i32,
    /// `None` => run until the primary sequence ends (stopped via `api_*_stop`).
    pub frame_count: Option<u32>,
    pub filter_name: Option<String>,
    pub target_temp_c: Option<f64>,
    /// Human label for the rig, used in the save sub-folder + `NS-RIG` keyword.
    pub rig_label: String,
    pub camera_make: Option<String>,
    pub camera_model: Option<String>,
    pub telescope_name: Option<String>,
    pub telescope_focal_length_mm: Option<f64>,
    pub telescope_aperture_mm: Option<f64>,
    /// Max seconds the primary waits for the secondary to clear before
    /// dithering anyway (bounded so a stuck secondary never stalls the primary).
    pub dither_max_wait_secs: f64,
    /// "complete_if_short" (default) or "abort_immediately".
    pub in_flight_policy: String,
    /// Base directory frames are saved into. The secondary writes into a
    /// `<base>/<rig_label>/` subfolder. `None` => current working directory.
    pub save_base_path: Option<String>,
    /// Target name inherited from the primary (stamped into FITS `OBJECT`).
    pub target_name: Option<String>,
    pub target_ra_hours: Option<f64>,
    pub target_dec_degrees: Option<f64>,
    pub observer_name: Option<String>,
    pub site_latitude_deg: Option<f64>,
    pub site_longitude_deg: Option<f64>,
    pub site_elevation_m: Option<f64>,
}

/// FRB-facing live status snapshot of the secondary rig.
#[derive(Debug, Clone)]
pub struct SecondaryRigStatusApi {
    pub armed: bool,
    pub running: bool,
    pub camera_id: Option<String>,
    pub rig_label: String,
    pub frames_captured: u32,
    pub frames_aborted: u32,
    pub planned_frames: Option<u32>,
    pub waiting_for_dither: bool,
    pub exposing: bool,
    pub dither_pending: bool,
    pub forced_proceeds: u32,
    pub last_error: Option<String>,
}

impl Default for SecondaryRigStatusApi {
    fn default() -> Self {
        Self {
            armed: false,
            running: false,
            camera_id: None,
            rig_label: String::new(),
            frames_captured: 0,
            frames_aborted: 0,
            planned_frames: None,
            waiting_for_dither: false,
            exposing: false,
            dither_pending: false,
            forced_proceeds: 0,
            last_error: None,
        }
    }
}

/// Arm + start the secondary capture loop. Installs the dither barrier into the
/// sequencer's process-wide slot so the primary coordinates with it; if a
/// sequence is already running the executor will pick up the barrier on its
/// next dither (it reads `active_barrier()` at `start()` — see note below).
///
/// Best practice: arm the secondary BEFORE starting the primary sequence so the
/// barrier is installed when the executor builds its context. Arming mid-run
/// still coordinates the *secondary* side (it gates on `dither_pending`), but
/// the *primary* only consults the barrier it captured at start; a future
/// enhancement could push a live barrier into the running executor.
pub async fn api_secondary_rig_start(config: SecondaryRigConfigApi) -> Result<(), NightshadeError> {
    if config.exposure_secs <= 0.0 {
        return Err(NightshadeError::InvalidParameter(
            "exposure_secs must be positive".to_string(),
        ));
    }
    if config.camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id must not be empty".to_string(),
        ));
    }

    let policy = InFlightDitherPolicy::from_str_opt(&config.in_flight_policy).unwrap_or_default();
    let max_wait = if config.dither_max_wait_secs > 0.0 {
        config.dither_max_wait_secs
    } else {
        DEFAULT_DITHER_MAX_WAIT_SECS
    };

    let rig_config = SecondaryRigConfig {
        camera_id: config.camera_id.clone(),
        exposure_secs: config.exposure_secs,
        gain: config.gain,
        offset: config.offset,
        bin_x: config.bin_x.max(1),
        bin_y: config.bin_y.max(1),
        frame_count: config.frame_count,
        filter_name: config.filter_name.clone(),
        target_temp_c: config.target_temp_c,
        rig_label: if config.rig_label.trim().is_empty() {
            "Secondary".to_string()
        } else {
            config.rig_label.clone()
        },
        camera_make: config.camera_make.clone(),
        camera_model: config.camera_model.clone(),
        telescope_name: config.telescope_name.clone(),
        telescope_focal_length_mm: config.telescope_focal_length_mm,
        telescope_aperture_mm: config.telescope_aperture_mm,
    };

    let meta = SecondaryFrameMeta {
        session_id: new_secondary_session_id(),
        target_name: config.target_name.clone(),
        target_id: None,
        target_ra_hours: config.target_ra_hours,
        target_dec_degrees: config.target_dec_degrees,
        observer_name: config.observer_name.clone(),
        site_latitude_deg: config.site_latitude_deg,
        site_longitude_deg: config.site_longitude_deg,
        site_elevation_m: config.site_elevation_m,
        save_base: config.save_base_path.as_ref().map(std::path::PathBuf::from),
    };

    // Reuse the unified device-ops path: the secondary camera is driven through
    // the same DeviceManager as everything else (no duplicated driver code).
    let device_ops = create_unified_device_ops();
    let barrier = Arc::new(DitherBarrier::new(max_wait, policy));

    // Stop any previously-armed secondary first (one mount, one barrier).
    if let Some(prev) = manager().lock().rig.take() {
        let _ = prev.stop();
    }

    // Install the barrier into the sequencer's process-wide slot BEFORE
    // spawning the loop so the executor (if it starts now) sees it.
    dual_rig::install_active_barrier(barrier.clone());

    let rig = SecondaryRig::start(rig_config, device_ops, barrier, meta);
    manager().lock().rig = Some(rig);

    tracing::info!(
        "Secondary rig armed: camera={}, exp={}s, max_wait={}s, policy={}",
        config.camera_id,
        config.exposure_secs,
        max_wait,
        policy.as_str(),
    );
    Ok(())
}

/// Stop the secondary capture loop and tear down the barrier. Idempotent.
pub async fn api_secondary_rig_stop() -> Result<(), NightshadeError> {
    let rig = manager().lock().rig.take();
    if let Some(rig) = rig {
        let handle = rig.stop();
        // Await teardown so a subsequent re-arm doesn't race the old loop's
        // final camera abort.
        let _ = handle.await;
    }
    dual_rig::clear_active_barrier();
    tracing::info!("Secondary rig stopped");
    Ok(())
}

/// Live status snapshot of the secondary rig (for UI / headless monitoring).
pub async fn api_secondary_rig_get_status() -> SecondaryRigStatusApi {
    let mgr = manager().lock();
    let Some(rig) = mgr.rig.as_ref() else {
        return SecondaryRigStatusApi::default();
    };
    let s = rig.status();
    let (dither_pending, forced) = dual_rig::active_barrier()
        .map(|b| (b.is_dither_pending(), b.forced_proceed_count()))
        .unwrap_or((false, 0));
    SecondaryRigStatusApi {
        armed: true,
        running: s.running,
        camera_id: s.camera_id,
        rig_label: s.rig_label,
        frames_captured: s.frames_captured,
        frames_aborted: s.frames_aborted,
        planned_frames: s.planned_frames,
        waiting_for_dither: s.waiting_for_dither,
        exposing: s.exposing,
        dither_pending,
        forced_proceeds: forced,
        last_error: s.last_error,
    }
}

/// Whether a secondary rig is currently armed.
pub async fn api_secondary_rig_is_armed() -> bool {
    manager().lock().rig.is_some()
}

/// Generate a unique-enough session id for a secondary run without pulling in a
/// uuid dependency. Nanosecond timestamp + a monotonic counter + the process id
/// is unique in practice for this purpose (it only links a rig's subs together).
fn new_secondary_session_id() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("secondary-{}-{}-{}", std::process::id(), ts, n)
}
