//! Instruction execution implementations
//!
//! These functions implement the actual device control for sequencer instructions.
//! They use the DeviceOps trait to communicate with real or simulated hardware.

use crate::device_ops::{ImageData, SharedDeviceOps};
use crate::*;
use chrono::NaiveDate;
use std::path::PathBuf;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::sleep;

/// Result of an instruction execution
pub struct InstructionResult {
    pub status: NodeStatus,
    pub message: Option<String>,
    pub data: Option<serde_json::Value>,
    /// HFR values from exposures (for trigger monitoring)
    pub hfr_values: Vec<f64>,
}

impl InstructionResult {
    pub fn success() -> Self {
        Self {
            status: NodeStatus::Success,
            message: None,
            data: None,
            hfr_values: Vec::new(),
        }
    }

    pub fn success_with_message(message: impl Into<String>) -> Self {
        Self {
            status: NodeStatus::Success,
            message: Some(message.into()),
            data: None,
            hfr_values: Vec::new(),
        }
    }

    pub fn failure(message: impl Into<String>) -> Self {
        Self {
            status: NodeStatus::Failure,
            message: Some(message.into()),
            data: None,
            hfr_values: Vec::new(),
        }
    }

    /// Create a failure result with a recovery code that the UI can use to offer recovery options
    pub fn failure_with_recovery(
        message: impl Into<String>,
        recovery_code: impl Into<String>,
    ) -> Self {
        Self {
            status: NodeStatus::Failure,
            message: Some(message.into()),
            data: Some(serde_json::json!({"recovery_code": recovery_code.into()})),
            hfr_values: Vec::new(),
        }
    }

    pub fn cancelled(message: impl Into<String>) -> Self {
        Self {
            status: NodeStatus::Cancelled,
            message: Some(message.into()),
            data: None,
            hfr_values: Vec::new(),
        }
    }

    /// Get the status, logging any failure or cancellation message.
    /// This ensures error messages are not silently discarded.
    pub fn log_and_get_status(self, node_name: &str) -> NodeStatus {
        self.log_and_get_status_with_recovery(node_name, None)
    }

    /// Get the status, logging failures and promoting disconnected-device
    /// failures to the executor recovery loop when the live context exposes
    /// a recovery request channel.
    pub fn log_and_get_status_with_context(
        self,
        node_name: &str,
        ctx: &InstructionContext,
    ) -> NodeStatus {
        self.log_and_get_status_with_recovery(node_name, ctx.recovery_request_tx.as_ref())
    }

    fn log_and_get_status_with_recovery(
        self,
        node_name: &str,
        recovery_request_tx: Option<&mpsc::Sender<crate::recovery::RecoveryCause>>,
    ) -> NodeStatus {
        match self.status {
            NodeStatus::Failure => {
                if let Some(msg) = &self.message {
                    tracing::error!("{} failed: {}", node_name, msg);
                    if is_device_disconnected_message(msg) {
                        request_device_disconnected_recovery(node_name, msg, recovery_request_tx);
                    }
                } else {
                    tracing::error!("{} failed (no details)", node_name);
                }
            }
            NodeStatus::Cancelled => {
                if let Some(msg) = &self.message {
                    tracing::warn!("{} cancelled: {}", node_name, msg);
                }
            }
            _ => {}
        }
        self.status
    }
}

pub(crate) fn is_device_disconnected_message(message: &str) -> bool {
    let lower = message.to_ascii_lowercase();
    if lower.contains("please reconnect") {
        return true;
    }
    if lower.contains("device") && lower.contains("not connected") {
        return true;
    }

    const DEVICE_PREFIXES: &[&str] = &[
        "camera",
        "mount",
        "focuser",
        "filter wheel",
        "filterwheel",
        "rotator",
        "dome",
        "cover calibrator",
        "flat panel",
    ];
    DEVICE_PREFIXES.iter().any(|prefix| {
        lower.contains(&format!("no {prefix} connected"))
            || lower.contains(&format!("{prefix} is not connected"))
            || lower.contains(&format!("{prefix} not connected"))
    })
}

fn request_device_disconnected_recovery(
    node_name: &str,
    message: &str,
    recovery_request_tx: Option<&mpsc::Sender<crate::recovery::RecoveryCause>>,
) {
    let Some(tx) = recovery_request_tx else {
        tracing::warn!(
            "[RECOVERY] {} detected a device disconnect but no recovery channel is installed: {}",
            node_name,
            message
        );
        return;
    };

    match tx.try_send(crate::recovery::RecoveryCause::DeviceDisconnected) {
        Ok(()) => tracing::warn!(
            "[RECOVERY] {} promoted device disconnect to recovery: {}",
            node_name,
            message
        ),
        Err(tokio::sync::mpsc::error::TrySendError::Full(_)) => tracing::warn!(
            "[RECOVERY] Recovery channel full; dropping duplicate device-disconnect request from {}: {}",
            node_name,
            message
        ),
        Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => tracing::warn!(
            "[RECOVERY] Recovery channel closed; {} device-disconnect failure cannot enter recovery: {}",
            node_name,
            message
        ),
    }
}

/// Context for instruction execution
/// Contains the current imaging session state and cancellation flag
pub struct InstructionContext {
    /// Target RA in hours
    pub target_ra: Option<f64>,
    /// Target Dec in degrees
    pub target_dec: Option<f64>,
    /// Target name
    pub target_name: Option<String>,
    /// Current filter
    pub current_filter: Option<String>,
    /// Current binning
    pub current_binning: Binning,
    /// Cancellation token
    pub cancellation_token: Arc<AtomicBool>,
    /// Connected camera device ID
    pub camera_id: Option<String>,
    /// Connected mount device ID
    pub mount_id: Option<String>,
    /// Connected focuser device ID
    pub focuser_id: Option<String>,
    /// Connected filter wheel device ID
    pub filterwheel_id: Option<String>,
    /// Connected rotator device ID
    pub rotator_id: Option<String>,
    /// Connected dome device ID
    pub dome_id: Option<String>,
    /// Connected cover calibrator (flat panel) device ID
    pub cover_calibrator_id: Option<String>,
    /// Base path for saving images
    pub save_path: Option<PathBuf>,
    /// Observer's latitude (degrees)
    pub latitude: Option<f64>,
    /// Observer's longitude (degrees)
    pub longitude: Option<f64>,
    /// Device operations handler
    pub device_ops: SharedDeviceOps,
    /// Trigger state (for updating during execution)
    pub trigger_state: Option<Arc<tokio::sync::RwLock<crate::triggers::TriggerState>>>,
    /// Filter focus offsets from the equipment profile (filter_name -> offset_steps).
    /// When a filter change occurs, the focuser is moved by the offset relative to
    /// the current position. A positive offset means move outward.
    pub filter_focus_offsets: std::collections::HashMap<String, i32>,
    /// Optional broadcast handle so instruction code can emit ExecutorEvents
    /// directly to subscribers (UI, logging, etc.). Used to surface
    /// instruction-level failures that must be visible beyond the
    /// InstructionResult return value — e.g. FITS-save failures (see
    /// `execute_exposure`). `None` outside the live executor; instructions
    /// must use `if let Some(tx) = ...` and ignore send errors (no subscribers
    /// is a benign case for headless runs).
    pub event_tx: Option<tokio::sync::broadcast::Sender<crate::executor::ExecutorEvent>>,
    /// Recovery request channel for first-class recoverable instruction failures.
    pub recovery_request_tx: Option<mpsc::Sender<crate::recovery::RecoveryCause>>,
    // -------------------------------------------------------------------
    // Wave 3 Image Grading: FITS-header metadata propagated from
    // ExecutionContext so `execute_exposure` can assemble a FrameContext
    // for save_fits.
    // -------------------------------------------------------------------
    pub session_id: String,
    pub target_id: Option<String>,
    pub mosaic_panel: Option<crate::MosaicPanelInfo>,
    pub current_filter_index: Option<i32>,
    pub set_temp_c: Option<f64>,
    pub bayer_pattern: Option<String>,
    pub observer_name: Option<String>,
    pub site_elevation_m: Option<f64>,
    pub camera_make: Option<String>,
    pub camera_model: Option<String>,
    pub telescope_name: Option<String>,
    pub telescope_focal_length_mm: Option<f64>,
    pub telescope_aperture_mm: Option<f64>,
    /// Shared handle to last plate-solve result (set by CenterTarget).
    pub last_plate_solve: Arc<tokio::sync::RwLock<Option<crate::device_ops::PlateSolveResult>>>,
    // -------------------------------------------------------------------
    // Wave 3 Image Grading: per-run grading state, shared via Arc with
    // ExecutionContext so progress events carry consistent totals across
    // the entire sequence.
    // -------------------------------------------------------------------
    pub hfr_baseline: Arc<tokio::sync::RwLock<Option<f64>>>,
    pub hfr_baseline_samples: Arc<tokio::sync::RwLock<Vec<f64>>>,
    pub consecutive_rejects: Arc<std::sync::atomic::AtomicU32>,
    pub frames_accepted: Arc<std::sync::atomic::AtomicU32>,
    pub frames_rejected: Arc<std::sync::atomic::AtomicU32>,
    /// Global default image-quality thresholds. Used as the fallback when
    /// `ExposureConfig.quality_check` is None.
    pub default_quality_check: Option<crate::quality::ImageQualityCheck>,
    /// Optional reject-folder override (relative to save_path or absolute).
    /// None => use `<save_path>/Reject/`.
    pub reject_folder_path: Option<String>,
    /// Wave 7 Agent 3 — per-frame defect-map application state. Cloned
    /// from `ExecutionContext::defect_map_apply` at instruction-context
    /// construction time. Pre-loading is bridge-side, so a `Some(...)`
    /// value carries the parsed `DefectMap` ready for per-frame
    /// `correct_u16_slice` application.
    pub defect_map_apply: Arc<tokio::sync::RwLock<Option<crate::executor::DefectMapApplyState>>>,
    // -------------------------------------------------------------------
    // Wave 8 — Frame-Failure Forensics.
    //
    // `emit_grade_progress` snapshots live env values, looks at the
    // rolling history, classifies the rejection, then pushes the new
    // sample into the history. All five Arcs are shared with
    // ExecutionContext so other instructions can keep mutating them.
    // -------------------------------------------------------------------
    /// Rolling buffer of the last `FORENSIC_HISTORY_LEN` frame samples.
    pub forensics_history:
        Arc<tokio::sync::RwLock<std::collections::VecDeque<crate::quality::RecentFrameSample>>>,
    /// Sky brightness reading (mag/arcsec²) shared with the adaptive
    /// exposure adapter.
    pub current_sky_brightness_mag: Arc<tokio::sync::RwLock<Option<f64>>>,
    /// Cloud motion snapshot pushed by the Dart weather pipeline.
    pub cloud_motion_snapshot: Arc<tokio::sync::RwLock<crate::node::context::CloudMotionSnapshot>>,
    /// Current wind speed (km/h).
    pub current_wind_kph: Arc<tokio::sync::RwLock<Option<f64>>>,
    /// Current sensor temperature (°C).
    pub current_sensor_temp_c: Arc<tokio::sync::RwLock<Option<f64>>>,
    /// Wave 8 Replay Debug — broadcast handle for [`crate::decision::DecisionEvent`]s
    /// (FrameAccepted / FrameRejected emit from `emit_grade_progress`,
    /// AdaptiveSwap emit from the adaptive-exposure path, BudgetMet from
    /// the budget tracker, PluginNodeInvoked from the plugin instruction).
    /// `None` outside the live executor (test contexts / one-shot bridge
    /// calls); emission is a no-op then.
    pub decision_tx: Option<crate::decision::DecisionSender>,
    /// Wave 8 Replay Debug — active sequence_runs.id, populated for every
    /// emitted DecisionEvent so persistence can write the FK without
    /// re-joining on wall-clock windows.
    pub active_sequence_run_id: Arc<parking_lot::RwLock<Option<i64>>>,
}

impl InstructionContext {
    pub fn check_cancelled(&self) -> Option<InstructionResult> {
        if self.cancellation_token.load(Ordering::Relaxed) {
            Some(InstructionResult::cancelled("Operation cancelled"))
        } else {
            None
        }
    }

    /// Get camera ID or error
    pub fn camera_id(&self) -> Result<&str, InstructionResult> {
        self.camera_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No camera connected"))
    }

    /// Get mount ID or error
    pub fn mount_id(&self) -> Result<&str, InstructionResult> {
        self.mount_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No mount connected"))
    }

    /// Get focuser ID or error
    pub fn focuser_id(&self) -> Result<&str, InstructionResult> {
        self.focuser_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No focuser connected"))
    }

    /// Get filter wheel ID or error
    pub fn filterwheel_id(&self) -> Result<&str, InstructionResult> {
        self.filterwheel_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No filter wheel connected"))
    }

    /// Get rotator ID or error  
    pub fn rotator_id(&self) -> Result<&str, InstructionResult> {
        self.rotator_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No rotator connected"))
    }

    /// Get dome ID or error
    pub fn dome_id(&self) -> Result<&str, InstructionResult> {
        self.dome_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No dome connected"))
    }

    /// Get cover calibrator ID or error
    pub fn cover_calibrator_id(&self) -> Result<&str, InstructionResult> {
        self.cover_calibrator_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No cover calibrator (flat panel) connected"))
    }

    /// Wave 8 Replay Debug — emit a structured decision into the
    /// broadcast channel. No-op when `decision_tx` is `None` (one-shot
    /// instruction sites, unit tests). Stamps the active sequence_run_id
    /// before forwarding so the persistence layer has the FK.
    pub fn emit_decision(&self, mut event: crate::decision::DecisionEvent) {
        let Some(tx) = self.decision_tx.as_ref() else {
            return;
        };
        if event.sequence_run_id.is_none() {
            event.sequence_run_id = *self.active_sequence_run_id.read();
        }
        let _ = tx.send(event);
    }
}

// =============================================================================
// SLEW INSTRUCTION
// =============================================================================

/// Default tolerance for slew position validation in degrees (1 arcminute = 1/60 degree)
const SLEW_POSITION_TOLERANCE_DEG: f64 = 1.0 / 60.0;

/// Normalize RA difference to account for wraparound at 24 hours
/// Returns the shortest angular distance between two RA values in hours
fn normalize_ra_diff_hours(diff: f64) -> f64 {
    // Normalize to [-12, +12] h so the sign of the result is the shortest
    // signed angular distance — necessary because a raw 23 h difference is
    // physically a -1 h move, not a 23 h move.
    let mut wrapped = diff % 24.0;
    if wrapped > 12.0 {
        wrapped -= 24.0;
    } else if wrapped < -12.0 {
        wrapped += 24.0;
    }
    wrapped
}

/// Validate that mount reached the target position within tolerance
/// ra_target and ra_actual are in hours, dec_target and dec_actual are in degrees
/// tolerance_deg is the maximum allowed difference in degrees
fn validate_slew_position(
    ra_target: f64,
    dec_target: f64,
    ra_actual: f64,
    dec_actual: f64,
    tolerance_deg: f64,
) -> Result<(), String> {
    let ra_diff_hours = normalize_ra_diff_hours(ra_actual - ra_target);
    let ra_diff_deg = ra_diff_hours * 15.0;

    // Dec is bounded to [-90, +90] so there is no wraparound to handle; a
    // raw subtraction is the signed angular distance directly.
    let dec_diff_deg = dec_actual - dec_target;

    if ra_diff_deg.abs() > tolerance_deg || dec_diff_deg.abs() > tolerance_deg {
        return Err(format!(
            "Mount slew did not reach target position. Expected RA={:.4}h, Dec={:.4}deg, \
             got RA={:.4}h, Dec={:.4}deg (diff: RA={:.2}', Dec={:.2}')",
            ra_target,
            dec_target,
            ra_actual,
            dec_actual,
            ra_diff_deg * 60.0, // Convert to arcminutes for readability
            dec_diff_deg * 60.0
        ));
    }

    Ok(())
}

/// Execute a slew instruction
pub async fn execute_slew(
    config: &SlewConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let mount_id = match ctx.mount_id() {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Slewing a parked mount on most drivers either silently no-ops or
    // errors deep in the slew loop; surfacing the precondition here gives
    // the user a clean error with a recovery hint (unpark) before any
    // long-running motion is attempted.
    match ctx.device_ops.mount_is_parked(mount_id).await {
        Ok(true) => {
            tracing::warn!("Mount is parked, cannot slew. Please unpark the mount first.");
            return InstructionResult::failure_with_recovery(
                "Mount is parked. Please unpark the mount before slewing.",
                "MOUNT_PARKED",
            );
        }
        Ok(false) => {
            tracing::debug!("Mount is not parked, proceeding with slew");
        }
        Err(e) => {
            // Old INDI drivers and some serial mounts lack park-status reporting.
            // Treat the query failure as "unknown" rather than "parked" so we do
            // not block slewing on mounts that genuinely cannot tell us.
            tracing::debug!("Could not check mount park status: {}", e);
        }
    }

    let (ra, dec) = if config.use_target_coords {
        match (ctx.target_ra, ctx.target_dec) {
            (Some(ra), Some(dec)) => (ra, dec),
            _ => return InstructionResult::failure("No target coordinates available"),
        }
    } else {
        match (config.custom_ra, config.custom_dec) {
            (Some(ra), Some(dec)) => (ra, dec),
            _ => return InstructionResult::failure("No custom coordinates specified"),
        }
    };

    tracing::info!("Slewing to RA: {:.4}h, Dec: {:.4}°", ra, dec);

    if let Some(cb) = progress_callback {
        cb(0.0, format!("Slewing to RA: {:.2}h, Dec: {:.1}°", ra, dec));
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    tokio::select! {
        result = ctx.device_ops.mount_slew_to_coordinates(mount_id, ra, dec) => {
            match result {
                Ok(_) => {
                    // 1800 s = 30 min handles the longest realistic slew on
                    // weight-belt direct-drives doing a full-sky move; tighter
                    // would false-alarm on heavily loaded mounts.
                    match wait_for_mount_idle_with_progress(mount_id, ctx, Duration::from_secs(1800), progress_callback).await {
                        Ok(_) => {
                            // The mount reports "not slewing" before its
                            // axes have fully settled on some drivers, so we
                            // re-read coordinates and validate against the
                            // target before declaring success — silent
                            // mis-pointing would feed bad data downstream.
                            match ctx.device_ops.mount_get_coordinates(mount_id).await {
                                Ok((actual_ra, actual_dec)) => {
                                    tracing::debug!(
                                        "Slew completed. Target: RA={:.4}h, Dec={:.4}°, Actual: RA={:.4}h, Dec={:.4}°",
                                        ra, dec, actual_ra, actual_dec
                                    );

                                    if let Err(e) = validate_slew_position(
                                        ra, dec, actual_ra, actual_dec,
                                        SLEW_POSITION_TOLERANCE_DEG,
                                    ) {
                                        tracing::warn!("Slew position validation failed: {}", e);
                                        return InstructionResult::failure_with_recovery(
                                            &e,
                                            "SLEW_POSITION_MISMATCH",
                                        );
                                    }

                                    if let Some(cb) = progress_callback {
                                        cb(100.0, format!("Arrived at RA: {:.2}h, Dec: {:.1} deg", actual_ra, actual_dec));
                                    }
                                    InstructionResult::success_with_message(format!(
                                        "Slewed to RA: {:.4}h, Dec: {:.4} deg (verified)",
                                        actual_ra, actual_dec
                                    ))
                                }
                                Err(e) => {
                                    tracing::warn!(
                                        "Slew completed but position verification failed: {}. \
                                         Failing closed because final mount coordinates are unknown.",
                                        e
                                    );
                                    if let Some(cb) = progress_callback {
                                        cb(
                                            100.0,
                                            format!(
                                                "Slew reached command target but verification failed: {}",
                                                e
                                            ),
                                        );
                                    }
                                    InstructionResult::failure_with_recovery(
                                        format!(
                                            "Slew completed but mount position verification failed: {}",
                                            e
                                        ),
                                        "SLEW_UNVERIFIED_POSITION",
                                    )
                                }
                            }
                        }
                        Err(e) => InstructionResult::failure(e),
                    }
                }
                Err(e) => InstructionResult::failure(format!("Slew failed: {}", e)),
            }
        }
        _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
            tracing::info!("Slew cancelled, aborting...");
            let _ = ctx.device_ops.mount_abort_slew(mount_id).await;
            InstructionResult::cancelled("Slew cancelled")
        }
    }
}

/// Wait for mount to stop slewing with timeout.
///
/// Audit §1.6: previously the only caller was the inline execute_meridian_flip
/// body that has been replaced by a thin `MeridianFlipExecutor` wrapper.
/// Kept as a public-style helper with `#[allow(dead_code)]` so future
/// instruction-level slew helpers do not have to re-implement the polling
/// loop.
#[allow(dead_code)]
async fn wait_for_mount_idle(
    mount_id: &str,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    wait_for_mount_idle_with_progress(mount_id, ctx, timeout, None).await
}

/// Wait for mount to stop slewing with timeout and progress updates
async fn wait_for_mount_idle_with_progress(
    mount_id: &str,
    ctx: &InstructionContext,
    timeout: Duration,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    let mut poll_count = 0u32;

    loop {
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            let _ = ctx.device_ops.mount_abort_slew(mount_id).await;
            return Err("Operation cancelled".to_string());
        }

        match ctx.device_ops.mount_is_slewing(mount_id).await {
            Ok(is_slewing) => {
                if !is_slewing {
                    tracing::debug!("Mount reached target position");
                    return Ok(());
                }
            }
            Err(e) => {
                // Transient query failures are common during slews on serial
                // mounts; we keep polling so a one-off error does not abort
                // an otherwise healthy slew.
                tracing::warn!("Error checking slew status: {}", e);
            }
        }

        // Slew progress lacks a real percentage from drivers, so we synthesize
        // a 0–95% estimate from elapsed time using the typical 30–60 s slew
        // duration. Capped at 95% so the user does not see "100%" before the
        // mount actually reports idle.
        poll_count += 1;
        if poll_count.is_multiple_of(4) {
            let elapsed_secs = start.elapsed().as_secs();
            // Why: elapsed_secs is a u64 wall-clock; even months of elapsed time fit
            // in f64's 53-bit mantissa. Lossless for any plausible slew duration.
            let progress = ((elapsed_secs as f64 / 60.0) * 100.0).min(95.0);
            if let Some(cb) = progress_callback {
                cb(progress, format!("Slewing... ({:.0}s)", elapsed_secs));
            }
        }

        if start.elapsed() > timeout {
            return Err(format!(
                "Mount slew timed out after {} seconds",
                timeout.as_secs()
            ));
        }

        // 500 ms balances responsiveness against driver query cost on serial
        // mounts (where each poll round-trips through USB-to-serial).
        sleep(Duration::from_millis(500)).await;
    }
}

/// Wait for focuser to stop moving with timeout
async fn wait_for_focuser_idle(
    focuser_id: &str,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    loop {
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            // A bare cancel without halting can leave the focuser to overshoot
            // the original target; halt + wait-for-stop guarantees the user's
            // next instruction (e.g. autofocus restart) sees a stationary motor.
            tracing::info!("Cancellation detected during focuser move, halting focuser");
            if let Err(e) = ctx.device_ops.focuser_halt(focuser_id).await {
                tracing::warn!("Failed to halt focuser during cancellation: {}", e);
            }
            wait_for_focuser_stop_after_halt(focuser_id, &ctx.device_ops, Duration::from_secs(10))
                .await;
            return Err("Operation cancelled".to_string());
        }

        match ctx.device_ops.focuser_is_moving(focuser_id).await {
            Ok(is_moving) => {
                if !is_moving {
                    // 100 ms settle absorbs motor backlash on stepper focusers
                    // — the driver reports "stopped" before the gear train
                    // physically settles, and a subsequent exposure would catch
                    // the tail-end vibration.
                    sleep(Duration::from_millis(100)).await;
                    tracing::debug!("Focuser reached target position");
                    return Ok(());
                }
            }
            Err(e) => {
                tracing::warn!("Error checking focuser status: {}", e);
            }
        }

        if start.elapsed() > timeout {
            return Err(format!(
                "Focuser move timed out after {} seconds",
                timeout.as_secs()
            ));
        }

        // 100 ms (vs 500 ms for mount) — focusers complete moves in seconds,
        // not minutes, so a coarser cadence would lose alignment precision.
        sleep(Duration::from_millis(100)).await;
    }
}

/// Wait for focuser to stop moving after a halt command (ignores cancellation token).
/// This is used during cancellation handling to ensure the focuser has actually stopped
/// before returning control. The timeout is shorter since we're just waiting for halt.
pub async fn wait_for_focuser_stop_after_halt(
    focuser_id: &str,
    device_ops: &crate::device_ops::SharedDeviceOps,
    timeout: Duration,
) {
    let start = std::time::Instant::now();
    loop {
        match device_ops.focuser_is_moving(focuser_id).await {
            Ok(is_moving) => {
                if !is_moving {
                    tracing::debug!("Focuser stopped after halt");
                    return;
                }
            }
            Err(e) => {
                tracing::warn!("Error checking focuser status after halt: {}", e);
            }
        }

        if start.elapsed() > timeout {
            tracing::warn!(
                "Focuser did not stop within {} seconds after halt",
                timeout.as_secs()
            );
            return;
        }

        sleep(Duration::from_millis(100)).await;
    }
}

/// Wait for filter wheel to reach target position with timeout
async fn wait_for_filterwheel_idle(
    fw_id: &str,
    target_position: i32,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();

    // Some filter wheels (notably ZWO EFW) still report the old position for
    // ~50 ms after issuing a move command; polling immediately would treat
    // the "already at target" reading as success and return before the wheel
    // has even started turning.
    sleep(Duration::from_millis(100)).await;

    loop {
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            return Err("Operation cancelled".to_string());
        }

        match ctx.device_ops.filterwheel_get_position(fw_id).await {
            Ok(current_pos) => {
                if current_pos == target_position {
                    tracing::debug!("Filter wheel reached target position {}", target_position);
                    return Ok(());
                }
                tracing::trace!(
                    "Filter wheel at position {}, waiting for {}",
                    current_pos,
                    target_position
                );
            }
            Err(e) => {
                tracing::warn!("Error checking filter wheel position: {}", e);
            }
        }

        if start.elapsed() > timeout {
            return Err(format!(
                "Filter wheel move timed out after {} seconds (target: {})",
                timeout.as_secs(),
                target_position
            ));
        }

        sleep(Duration::from_millis(200)).await;
    }
}

fn ensure_unique_save_path(path: PathBuf) -> PathBuf {
    if !path.exists() {
        return path;
    }

    // Audit §1.15: parent and stem fallbacks here are defensive — by the time
    // we enter this function the caller has already passed a fully-formed
    // path. If the parent is None (file at filesystem root) we keep using an
    // empty PathBuf so `.join()` writes into the cwd; that mirrors the
    // pre-audit behaviour but is now explicit. If the stem is missing we
    // fall back to "image" but log so the operator can audit how a stemless
    // path was constructed.
    let parent = match path.parent() {
        Some(p) => p.to_path_buf(),
        None => {
            tracing::warn!(
                "[FS] ensure_unique_save_path: path has no parent component ({}). \
                 Suffixed candidates will be written to the current working directory.",
                path.display()
            );
            PathBuf::new()
        }
    };
    let stem = match path.file_stem().and_then(|v| v.to_str()) {
        Some(s) if !s.is_empty() => s.to_string(),
        _ => {
            tracing::warn!(
                "[FS] ensure_unique_save_path: path has no usable file stem ({}); \
                 falling back to \"image\" for suffix generation.",
                path.display()
            );
            "image".to_string()
        }
    };
    let extension = path.extension().and_then(|value| value.to_str());

    let mut suffix = 1;
    loop {
        let candidate_name = match extension {
            Some(ext) if !ext.is_empty() => format!("{}_{:03}.{}", stem, suffix, ext),
            _ => format!("{}_{:03}", stem, suffix),
        };
        let candidate = parent.join(candidate_name);
        if !candidate.exists() {
            return candidate;
        }
        suffix += 1;
    }
}

async fn wait_for_cancellation(token: Arc<AtomicBool>) {
    loop {
        if token.load(Ordering::Relaxed) {
            return;
        }
        sleep(Duration::from_millis(100)).await;
    }
}

// =============================================================================
// CENTER INSTRUCTION (Plate Solve + Sync + Slew Loop)
// =============================================================================

/// Execute a center instruction (plate solve + sync + slew loop)
pub async fn execute_center(
    config: &CenterConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let mount_id = match ctx.mount_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    let (target_ra_hours, target_dec) = if config.use_target_coords {
        match (ctx.target_ra, ctx.target_dec) {
            (Some(ra), Some(dec)) => (ra, dec),
            _ => return InstructionResult::failure("No target coordinates available"),
        }
    } else if let (Some(ra), Some(dec)) = (config.custom_ra, config.custom_dec) {
        (ra, dec)
    } else {
        match ctx.device_ops.mount_get_coordinates(&mount_id).await {
            Ok((ra, dec)) => (ra, dec),
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Custom center coordinates were not provided and current mount coordinates could not be read: {}",
                    e
                ))
            }
        }
    };
    let target_ra_deg = target_ra_hours * 15.0;

    tracing::info!(
        "Centering on RA: {:.4}°, Dec: {:.4}° (accuracy: {:.1}\")",
        target_ra_deg,
        target_dec,
        config.accuracy_arcsec
    );

    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Centering (target: {:.1}\")", config.accuracy_arcsec),
        );
    }

    for attempt in 1..=config.max_attempts {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }

        // Why: attempt is a u32 loop counter bounded by max_attempts (also u32);
        // both lossless to f64.
        let attempt_progress = (f64::from(attempt - 1) / f64::from(config.max_attempts)) * 100.0;
        tracing::info!("Center attempt {}/{}", attempt, config.max_attempts);

        if let Some(cb) = progress_callback {
            cb(
                attempt_progress,
                format!("Attempt {}/{}: Capturing...", attempt, config.max_attempts),
            );
        }

        let image_data = tokio::select! {
            // Full resolution + 1x1 binning gives the plate solver the highest
            // possible star count; binning would reduce SNR enough to fail on
            // sparse fields.
            result = ctx.device_ops.camera_start_exposure(
                &camera_id,
                config.exposure_duration,
                None,
                None,
                1, 1,
            ) => {
                match result {
                    Ok(data) => {
                tracing::info!("[SEQ] Exposure completed: {}x{} image ({} pixels)", data.width, data.height, data.data.len());
                data
            }
                    Err(e) => return InstructionResult::failure(format!("Failed to capture image: {}", e)),
                }
            }
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                tracing::info!("Center cancelled during exposure, aborting...");
                let _ = ctx.device_ops.camera_abort_exposure(&camera_id).await;
                return InstructionResult::cancelled("Center cancelled");
            }
        };

        let solve_result = tokio::select! {
            result = ctx.device_ops.plate_solve(
                &image_data,
                Some(target_ra_deg),
                Some(target_dec),
                None,
            ) => {
                match result {
                    Ok(result) if result.success => result,
                    Ok(_) => {
                        tracing::warn!("Plate solve failed on attempt {}", attempt);
                        continue;
                    }
                    Err(e) => {
                        tracing::warn!("Plate solve error on attempt {}: {}", attempt, e);
                        continue;
                    }
                }
            }
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                tracing::info!("Center cancelled during plate solve");
                return InstructionResult::cancelled("Center cancelled");
            }
        };

        // Feeding the solve back into trigger state is what enables the
        // DriftLimit trigger (§1.11) to detect cumulative drift across
        // exposures without re-solving on every frame.
        if let Some(trigger_state_lock) = &ctx.trigger_state {
            let mut trigger_state = trigger_state_lock.write().await;
            trigger_state.update_plate_solve(
                solve_result.ra_degrees,
                solve_result.dec_degrees,
                solve_result.pixel_scale,
            );
            tracing::debug!(
                "Updated trigger state with plate solve: RA={:.4}°, Dec={:.4}°, scale={:.2}\"/px",
                solve_result.ra_degrees,
                solve_result.dec_degrees,
                solve_result.pixel_scale
            );
        }

        let separation_arcsec = calculate_separation_arcsec(
            target_ra_deg,
            target_dec,
            solve_result.ra_degrees,
            solve_result.dec_degrees,
        );
        tracing::info!("Current separation: {:.1}\" from target", separation_arcsec);

        if let Some(cb) = progress_callback {
            cb(
                // Why: config.max_attempts is u32; lossless to f64.
                attempt_progress + 50.0 / f64::from(config.max_attempts),
                format!(
                    "Attempt {}/{}: {:.1}\" off",
                    attempt, config.max_attempts, separation_arcsec
                ),
            );
        }

        if separation_arcsec <= config.accuracy_arcsec {
            if let Some(cb) = progress_callback {
                cb(100.0, format!("Centered: {:.1}\"", separation_arcsec));
            }
            return InstructionResult::success_with_message(format!(
                "Centered within {:.1}\" after {} attempt(s)",
                separation_arcsec, attempt
            ));
        }

        // Sync corrects the mount's internal model to the plate-solved truth
        // before re-slewing; without it, the next slew would land at the same
        // wrong spot (the mount thinks it's already at target).
        if let Err(e) = ctx
            .device_ops
            .mount_sync(
                &mount_id,
                solve_result.ra_degrees / 15.0,
                solve_result.dec_degrees,
            )
            .await
        {
            return InstructionResult::failure(format!(
                "Mount sync failed during centering on attempt {}: {}",
                attempt, e
            ));
        }

        tracing::info!("Slewing to correct position...");
        if let Some(cb) = progress_callback {
            cb(
                // Why: config.max_attempts is u32; lossless to f64.
                attempt_progress + 75.0 / f64::from(config.max_attempts),
                format!("Attempt {}/{}: Correcting...", attempt, config.max_attempts),
            );
        }

        tokio::select! {
            result = ctx.device_ops.mount_slew_to_coordinates(&mount_id, target_ra_deg / 15.0, target_dec) => {
                if let Err(e) = result {
                    tracing::warn!("Correction slew failed: {}", e);
                }
            }
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                tracing::info!("Center cancelled during correction slew, aborting...");
                let _ = ctx.device_ops.mount_abort_slew(&mount_id).await;
                return InstructionResult::cancelled("Center cancelled");
            }
        }

        // Wait for the correction slew to ACTUALLY FINISH before settling and
        // re-imaging. The slew command above returns as soon as it is issued
        // (ASCOM/Alpaca async slews, INDI set-coords) — it does NOT block until
        // the mount stops. Without this poll the next plate-solve exposure
        // fires ~2 s later while the mount is still moving (real offsets take
        // 10-60+ s), so the frame is motion-blurred / off-target, the solve
        // mis-corrects or fails, and the loop burns all attempts without
        // converging. Mirrors the meridian-flip slew-completion poll.
        {
            let slew_deadline = tokio::time::Instant::now() + Duration::from_secs(300);
            loop {
                if let Some(result) = ctx.check_cancelled() {
                    let _ = ctx.device_ops.mount_abort_slew(&mount_id).await;
                    return result;
                }
                match ctx.device_ops.mount_is_slewing(&mount_id).await {
                    Ok(false) => break,
                    Ok(true) => {}
                    Err(e) => {
                        // Do not proceed to image on an unknown slew state;
                        // keep polling until the deadline so a persistent
                        // failure ends the attempt rather than capturing
                        // mid-slew.
                        tracing::warn!("Centering: slew-state read failed ({}); retrying", e);
                    }
                }
                if tokio::time::Instant::now() > slew_deadline {
                    let _ = ctx.device_ops.mount_abort_slew(&mount_id).await;
                    return InstructionResult::failure(
                        "Centering correction slew did not complete within 300s".to_string(),
                    );
                }
                sleep(Duration::from_millis(500)).await;
            }
        }

        // 2 s post-slew settle absorbs mount oscillation before the next
        // plate-solve exposure; without it, the solve sees motion-blurred
        // stars and the iteration produces a noisy correction vector.
        sleep(Duration::from_secs(2)).await;
    }

    InstructionResult::failure(format!(
        "Failed to center within {:.1}\" after {} attempts",
        config.accuracy_arcsec, config.max_attempts
    ))
}

/// Calculate separation between two coordinates in arcseconds
fn calculate_separation_arcsec(ra1_deg: f64, dec1_deg: f64, ra2_deg: f64, dec2_deg: f64) -> f64 {
    let dec1_rad = dec1_deg.to_radians();
    let dec2_rad = dec2_deg.to_radians();
    let delta_ra = (ra2_deg - ra1_deg).to_radians();
    let delta_dec = (dec2_deg - dec1_deg).to_radians();

    // Haversine (not law-of-cosines) — at sub-arcsecond centering tolerances
    // the LoC formula loses precision near zero separation due to acos(~1.0)
    // rounding to 1.0 exactly.
    let a = (delta_dec / 2.0).sin().powi(2)
        + dec1_rad.cos() * dec2_rad.cos() * (delta_ra / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().asin();

    c.to_degrees() * 3600.0
}

// =============================================================================
// EXPOSURE INSTRUCTION
// =============================================================================

/// Per-frame save-path renderer. Wave 4 added interpolation to the
/// `ExposureConfig.save_to` template; the renderer is built once in the
/// expose-instruction wrapper (which has ExecutionContext access) and
/// invoked per-frame so the same engine can resolve `${frame:04}` and
/// `${exposure.duration:.0f}`.
///
/// Returns `Ok((dir, filename))` where:
/// * `dir` is the directory portion (absolute, with any user-specified
///   sub-directories from the template already expanded), and
/// * `filename` is the rendered file-name portion.
///
/// Errors surface as `InstructionResult::failure` from the caller — a
/// broken save-path template must abort the exposure rather than silently
/// drop frames into the wrong place.
pub type FrameSavePathRenderer =
    Box<dyn Fn(u32, u32) -> Result<(PathBuf, String), String> + Send + Sync>;

/// Execute an exposure instruction.
///
/// `path_renderer` is `Some` when a Wave-4-aware caller (the `ExposeInstruction`
/// node wrapper) has built a save-path renderer from the active
/// ExecutionContext. When `None`, the function falls back to the legacy
/// hardcoded `<target>_<filter>_<NNNN>.fits` layout — keeping pre-Wave-4
/// call sites (tests, direct invocations) working without modification.
pub async fn execute_exposure(
    config: &ExposureConfig,
    ctx: &InstructionContext,
    progress_callback: impl Fn(u32, u32),
) -> InstructionResult {
    execute_exposure_with_renderer(config, ctx, None, progress_callback).await
}

/// Wave 4 entry point that accepts a save-path renderer. Use this from
/// the expose-instruction node wrapper so user templates in
/// `ExposureConfig.save_to` (including hierarchical paths and per-frame
/// placeholders) take effect.
pub async fn execute_exposure_with_renderer(
    config: &ExposureConfig,
    ctx: &InstructionContext,
    path_renderer: Option<FrameSavePathRenderer>,
    progress_callback: impl Fn(u32, u32),
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Audit §1.15: log "(no filter set)" instead of substituting a filter
    // name like "unfiltered". The substituted token used to look like a
    // valid filter in operator logs.
    tracing::info!(
        "Starting {} {} x {:.1}s exposures",
        config.count,
        match config.filter.as_deref() {
            Some(name) if !name.is_empty() => name.to_string(),
            _ => "(no filter set)".to_string(),
        },
        config.duration_secs
    );

    // Position-index is preferred over name because filter names are
    // user-editable strings that can drift between profile and device
    // (e.g. "Ha" vs "H-alpha"); the position is the wheel's stable
    // hardware addressing.
    if config.filter.is_some() || config.filter_index.is_some() {
        if let Some(fw_id) = &ctx.filterwheel_id {
            if let Some(index) = config.filter_index {
                tracing::info!(
                    "Changing to filter position: {} (name: {:?})",
                    index,
                    config.filter
                );
                if let Err(e) = ctx.device_ops.filterwheel_set_position(fw_id, index).await {
                    return InstructionResult::failure(format!("Failed to change filter: {}", e));
                }
                let filter_name = match config.filter.as_deref() {
                    Some(name) if !name.is_empty() => Some(name.to_string()),
                    _ if !ctx.filter_focus_offsets.is_empty() => {
                        match ctx.device_ops.filterwheel_get_names(fw_id).await {
                            Ok(names) if index >= 0 => match names.get(index as usize) {
                                Some(name) => Some(name.clone()),
                                None => {
                                    return InstructionResult::failure(format!(
                                    "Filter position {} has no configured filter name for focus offset lookup",
                                    index
                                ));
                                }
                            },
                            Ok(_) => {
                                return InstructionResult::failure(format!(
                                    "Invalid negative filter position {} for focus offset lookup",
                                    index
                                ));
                            }
                            Err(e) => {
                                return InstructionResult::failure(format!(
                                    "Failed to read filter names for focus offset lookup: {}",
                                    e
                                ));
                            }
                        }
                    }
                    _ => None,
                };
                if let Some(filter_name) = filter_name {
                    if let Err(e) = apply_filter_focus_offset(&filter_name, ctx, None).await {
                        return InstructionResult::failure(format!(
                            "Focus offset failed for filter \"{}\": {}",
                            filter_name, e
                        ));
                    }
                }
            } else if let Some(filter) = &config.filter {
                tracing::info!("Changing to filter by name: {}", filter);
                if let Err(e) = ctx
                    .device_ops
                    .filterwheel_set_filter_by_name(fw_id, filter)
                    .await
                {
                    return InstructionResult::failure(format!("Failed to change filter: {}", e));
                }
                if let Err(e) = apply_filter_focus_offset(filter, ctx, None).await {
                    return InstructionResult::failure(format!(
                        "Focus offset failed for filter \"{}\": {}",
                        filter, e
                    ));
                }
            }
        }
    }

    let (bin_x, bin_y) = match config.binning {
        Binning::One => (1, 1),
        Binning::Two => (2, 2),
        Binning::Three => (3, 3),
        Binning::Four => (4, 4),
    };

    let mut completed_exposures = 0u32;
    let mut hfr_values = Vec::new();

    // Wave 3 Image Grading: local bindings for the per-frame grading state.
    // All these are Arc<_> handles shared with ExecutionContext so the
    // dashboard sees consistent totals across instruction boundaries.
    let frame_baseline_handle = ctx.hfr_baseline.clone();
    let frame_baseline_samples_handle = ctx.hfr_baseline_samples.clone();
    let consecutive_rejects_handle = ctx.consecutive_rejects.clone();
    let frames_accepted_handle = ctx.frames_accepted.clone();
    let frames_rejected_handle = ctx.frames_rejected.clone();
    let quality_check_default = ctx.default_quality_check.clone();
    let reject_folder_override = ctx.reject_folder_path.clone();

    for frame in 1..=config.count {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }

        tracing::info!(
            "Capturing frame {}/{} ({:.1}s)",
            frame,
            config.count,
            config.duration_secs
        );

        // tokio::select! is the only way to honour cancellation during a
        // blocking exposure without driver support; the abort branch tells
        // the camera to stop so it does not continue exposing in the
        // background after we abandon the future.
        let mut image_data = tokio::select! {
            result = ctx.device_ops.camera_start_exposure(
                &camera_id,
                config.duration_secs,
                config.gain,
                config.offset,
                bin_x,
                bin_y,
            ) => {
                match result {
                    Ok(data) => {
                        tracing::info!(
                            "[SEQ] Exposure completed: {}x{} image ({} pixels)",
                            data.width,
                            data.height,
                            data.data.len()
                        );
                        data
                    }
                    Err(e) => return InstructionResult::failure(format!("Exposure failed: {}", e)),
                }
            }
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                tracing::info!("Exposure cancelled, aborting camera...");
                let _ = ctx.device_ops.camera_abort_exposure(&camera_id).await;
                return InstructionResult::cancelled("Exposure cancelled");
            }
        };

        // Wave 7 Agent 3 — per-frame defect-map application.
        //
        // The capture path applies the pre-loaded defect map (pushed in
        // via `ExecutorCommand::UpdateDefectMap`) before HFR / grading
        // / FITS save. We deliberately run BEFORE star detection so the
        // grader doesn't reject frames over hot-pixel-induced false
        // stars; HFR / detection costs are unaffected because the map
        // is sparse (~10k of 26M pixels for typical CMOS sensors) and
        // the correction is O(defects · kernel_area).
        //
        // Mismatches (camera id changed, sensor size changed) are
        // surfaced as warn-level logs and the correction is skipped —
        // applying a map built for a different sensor would silently
        // poison the data, but failing the burst would over-react to
        // an operator hot-swapping cameras. The user sees the warn
        // and the frame's FITS HISTORY card records that no correction
        // ran.
        //
        // When `save_original = true` we snapshot the pre-correction
        // pixels here so the Raw/ archive step can save them alongside
        // the corrected frame later. A pre-clone is a ~50 MB heap
        // copy per 26 MP frame, so we only do it when the user
        // explicitly opted in — opt-out users pay zero.
        let mut original_pixels_snapshot: Option<Vec<u16>> = None;
        let should_snapshot_original = {
            let guard = ctx.defect_map_apply.read().await;
            guard.as_ref().map(|s| s.save_original).unwrap_or(false)
        };
        if should_snapshot_original {
            original_pixels_snapshot = Some(image_data.data.clone());
        }
        let defect_map_outcome =
            apply_defect_map_if_configured(ctx, &camera_id, &mut image_data, frame).await;
        // Drop the snapshot if no correction actually happened — saving a
        // verbatim copy of an uncorrected frame would just duplicate the
        // canonical save and waste disk space.
        if !matches!(defect_map_outcome, DefectMapOutcome::Applied { .. }) {
            original_pixels_snapshot = None;
        }

        // Per-frame HFR feeds the HfrDegraded / FocusDrift triggers; computing
        // it here (rather than only on autofocus) gives the triggers real-time
        // visibility into focus health between AF runs.
        let measured_hfr = match ctx.device_ops.calculate_image_hfr(&image_data).await {
            Ok(Some(hfr)) => {
                tracing::info!("Frame {}/{} HFR: {:.2} pixels", frame, config.count, hfr);
                hfr_values.push(hfr);
                Some(hfr)
            }
            Ok(None) => {
                tracing::warn!(
                    "Frame {}/{} - no stars detected for HFR calculation",
                    frame,
                    config.count
                );
                None
            }
            Err(e) => {
                tracing::warn!(
                    "Frame {}/{} - HFR calculation failed: {}",
                    frame,
                    config.count,
                    e
                );
                None
            }
        };

        // Wave 3 Image Grading: derive star count from the star detector
        // (cheap because the detector ran inside calculate_image_hfr and is
        // cached) so the grading check can apply the star_count_min floor.
        // Eccentricity is not yet measured by the existing star detector; left
        // as `None` until that path is added in a follow-on (the grading
        // logic treats None as "unknown, don't reject").
        let measured_star_count = match ctx.device_ops.detect_stars_in_image(&image_data).await {
            Ok(stars) => Some(stars.len() as u32),
            Err(e) => {
                tracing::debug!(
                    "Frame {}/{} - star detection failed for grading: {}",
                    frame,
                    config.count,
                    e
                );
                None
            }
        };
        let metrics = crate::quality::FrameMetrics {
            hfr: measured_hfr,
            eccentricity: None,
            star_count: measured_star_count,
        };

        // Wave 4 — Pick the (base_path, filename) pair. When a path_renderer
        // is supplied (the normal in-sequence case) it owns interpolation of
        // the `ExposureConfig.save_to` template and produces a fully resolved
        // directory + filename; an error from the renderer is fatal because
        // a broken template silently writing to the wrong place would be a
        // data-integrity disaster.
        //
        // When no renderer is supplied (legacy direct invocations from
        // tests), we fall back to the pre-Wave-4 hardcoded layout: base
        // path from `ctx.save_path`, filename `<target>_<filter>_<NNNN>.fits`.
        let (base_path, filename_template) = if let Some(renderer) = path_renderer.as_ref() {
            match renderer(frame, config.count) {
                Ok((dir, name)) => (Some(dir), Some(name)),
                Err(msg) => {
                    let error_message = format!(
                        "Save-path template render failed for frame {}/{}: {}. \
                         Aborting exposure — silently saving to the wrong path \
                         would corrupt the session's data integrity.",
                        frame, config.count, msg
                    );
                    tracing::error!("{}", error_message);
                    if let Some(event_tx) = &ctx.event_tx {
                        let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                            message: error_message.clone(),
                        });
                    }
                    return InstructionResult::failure(error_message);
                }
            }
        } else {
            (ctx.save_path.clone(), None)
        };

        if let Some(base_path) = base_path {
            // Audit §1.15: never silently substitute target name or filter.
            // A missing target name during normal imaging is a configuration
            // bug — emitting `image_L_0001.fits` hides which session the
            // frame belongs to and cannot be undone after the fact.
            // A missing filter labelled `L` mis-labels narrowband captures
            // as luminance.
            //
            // We log at warn! and use distinct synthetic placeholders that
            // are obvious in directory listings so an operator can audit
            // the run. If both fields are present this code path is silent.
            let filename = if let Some(name) = filename_template {
                name
            } else {
                // Legacy renderer-less fallback retained verbatim from the
                // pre-Wave-4 contract.
                let target_label = match ctx.target_name.as_deref() {
                    Some(name) if !name.is_empty() => name.to_string(),
                    _ => {
                        tracing::warn!(
                            "[CAPTURE] Saving frame with no target name — using synthetic label \"untargeted\". \
                             This indicates the sequence was started without a TargetHeader/TargetGroup; review the configuration."
                        );
                        "untargeted".to_string()
                    }
                };
                let filter_label = match config.filter.as_deref() {
                    Some(name) if !name.is_empty() => name.to_string(),
                    _ => {
                        tracing::warn!(
                            "[CAPTURE] Saving frame with no filter set — using synthetic label \"nofilter\" (NOT \"L\"). \
                             A missing filter for narrowband/RGB captures would mis-label the frame as luminance."
                        );
                        "nofilter".to_string()
                    }
                };
                format!("{}_{}_{:04}.fits", target_label, filter_label, frame)
            };

            // Wave 3 Image Grading: decide accept/reject BEFORE picking the
            // final path — rejects go to a sibling Reject/ folder. The
            // grading honours the per-burst override (`config.quality_check`)
            // first, then falls back to the global default from runtime_config
            // (set by the executor at start time). If neither is configured
            // the frame is accepted unconditionally and the path stays the
            // canonical capture folder.
            let active_check = config
                .quality_check
                .as_ref()
                .or(quality_check_default.as_ref());
            let (grade, save_dir, was_graded) = if let Some(qc) = active_check {
                // Read baseline (None until the warmup window fills).
                let baseline = { *frame_baseline_handle.read().await };
                let g = crate::quality::grade_frame(qc, &metrics, baseline);
                match g {
                    crate::quality::FrameGrade::Pass => {
                        // Update the rolling baseline with this accepted HFR.
                        {
                            let mut baseline_guard = frame_baseline_handle.write().await;
                            let mut samples_guard = frame_baseline_samples_handle.write().await;
                            crate::quality::update_hfr_baseline(
                                &mut baseline_guard,
                                &mut samples_guard,
                                measured_hfr,
                            );
                        }
                        (g, base_path.clone(), true)
                    }
                    crate::quality::FrameGrade::Reject { .. } => {
                        let dir = resolve_reject_dir(&base_path, reject_folder_override.as_deref());
                        (g, dir, true)
                    }
                }
            } else {
                (crate::quality::FrameGrade::Pass, base_path.clone(), false)
            };

            // Ensure reject dir exists if grading routed us there. The dir
            // create error is fatal because writing into a non-existent path
            // would be a data-loss event identical to the FITS save failure
            // below.
            if grade.is_reject() {
                if let Err(e) = std::fs::create_dir_all(&save_dir) {
                    let error_message = format!(
                        "Reject folder '{}' could not be created: {}. \
                         Frame {}/{} not saved; sequence aborted.",
                        save_dir.display(),
                        e,
                        frame,
                        config.count
                    );
                    tracing::error!("{}", error_message);
                    if let Some(event_tx) = &ctx.event_tx {
                        let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                            message: error_message.clone(),
                        });
                    }
                    return InstructionResult::failure(error_message);
                }
            }

            let full_path = ensure_unique_save_path(save_dir.join(&filename));

            // Wave 7 Agent 3 — archive the uncorrected frame to
            // `<save_dir>/Raw/` BEFORE the canonical save if the user
            // opted in. The raw is written via a minimal FITS header
            // (no defect-map history, IMAGETYP=Light) so re-runs of
            // the correction or independent calibration workflows can
            // re-derive results from the original pixels.
            if matches!(
                defect_map_outcome,
                DefectMapOutcome::Applied {
                    save_original: true,
                    ..
                }
            ) {
                if let Some(original) = &original_pixels_snapshot {
                    if let Err(e) = save_uncorrected_raw_frame(
                        &save_dir,
                        &filename,
                        image_data.width,
                        image_data.height,
                        original,
                    )
                    .await
                    {
                        // Save-original failure is non-fatal — we still
                        // want the corrected frame to land. Log at warn
                        // so the operator sees the partial outcome.
                        tracing::warn!(
                            "[DEFECT] Raw/ archive save failed for frame {}/{}: {}. \
                             The corrected frame will still be saved.",
                            frame,
                            config.count,
                            e,
                        );
                    }
                } else {
                    // Defensive: snapshot is taken only when
                    // save_original was true at correction time, so an
                    // Applied{save_original:true} without snapshot
                    // means an ordering bug in this function.
                    tracing::error!(
                        "[DEFECT] save_original requested but no pre-correction snapshot \
                         exists for frame {}/{}; Raw/ archive skipped.",
                        frame,
                        config.count,
                    );
                }
            }

            // Wave 3 Image Grading: build the per-frame FITS-header bundle
            // from InstructionContext (session-static + per-target fields)
            // plus live device telemetry (sensor temp, focuser position,
            // rotator angle, guide RMS). Each field is best-effort — a
            // device that fails to report its position simply omits that
            // FITS keyword (silent fallbacks would lie about the data).
            //
            // Wave 7 Agent 3: thread the defect-map application outcome
            // so the FITS HISTORY card records the correction provenance.
            let frame_ctx = build_frame_context_for_save(
                ctx,
                config,
                &image_data,
                frame,
                defect_map_outcome.clone(),
            )
            .await;

            if let Err(e) = ctx
                .device_ops
                .save_fits(
                    &image_data,
                    // Why (audit-rust §4.3): `PathBuf::to_str()` returns None only when the
                    // path is not valid UTF-8 — on Windows our save paths are always
                    // platform-default (UTF-16 → UTF-8) and on Unix the user's home dir is
                    // the root, both ASCII-safe in practice. Falling back to the bare
                    // filename keeps the save call going against the platform's CWD; the
                    // FITS writer downstream will surface any path-resolution error.
                    full_path.to_str().unwrap_or(&filename),
                    &frame_ctx,
                )
                .await
            {
                // Trust-patch §4: a FITS save failure is data loss — the
                // exposure is already complete and the image bytes are in
                // RAM, so a failed write means that frame is gone. The
                // previous warn-and-continue was the audit-flagged silent
                // fallback: the user would discover the missing frame hours
                // later when checking captures, with no surfaced error.
                //
                // Policy: log at ERROR, emit an ExecutorEvent::Error so the
                // UI sees it, and return InstructionResult::failure so the
                // sequence stops and the user can intervene (out-of-disk,
                // permission denied, drive disconnected — every cause needs
                // human action).
                let error_message = format!(
                    "FITS save failed for frame {}/{} at '{}': {}. \
                     Image data has been lost. Sequence aborted to preserve \
                     remaining storage and surface the issue.",
                    frame,
                    config.count,
                    full_path.display(),
                    e
                );
                tracing::error!("{}", error_message);
                if let Some(event_tx) = &ctx.event_tx {
                    // Why: a closed receiver (no UI subscribers) is benign —
                    // headless / API runs may have no listeners. The log line
                    // above is the durable record.
                    let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                        message: error_message.clone(),
                    });
                }
                return InstructionResult::failure(error_message);
            }
            tracing::info!("Saved: {}", full_path.display());

            // Wave 3 Image Grading: emit Accepted / Rejected progress event
            // so the dashboard quality panel updates + Agent 3's budget
            // tracker can skip rejected frames.
            if was_graded {
                emit_grade_progress(
                    ctx,
                    grade,
                    &metrics,
                    frame,
                    config.count,
                    &full_path,
                    &frames_accepted_handle,
                    &frames_rejected_handle,
                    &consecutive_rejects_handle,
                    active_check
                        .map(|c| c.max_consecutive_rejects)
                        .unwrap_or(u32::MAX),
                )
                .await;
            }
        }

        completed_exposures += 1;

        progress_callback(frame, config.count);

        // `frame < config.count` skips the dither after the final frame:
        // dithering after the last exposure of a burst leaves the mount
        // off-target for the next instruction (and wastes time).
        if let Some(dither_every) = config.dither_every {
            if dither_every > 0 && frame % dither_every == 0 && frame < config.count {
                tracing::info!("Dithering...");
                if let Err(e) = ctx
                    .device_ops
                    .guider_dither(
                        config.dither_pixels,
                        config.dither_settle_pixels,
                        config.dither_settle_time,
                        config.dither_settle_timeout,
                        config.dither_ra_only,
                    )
                    .await
                {
                    tracing::warn!("Dither failed: {}", e);
                }
            }
        }
    }

    InstructionResult {
        status: NodeStatus::Success,
        message: Some(format!("Completed {} exposures", completed_exposures)),
        data: Some(serde_json::json!({
            "completed": completed_exposures,
            "total": config.count,
        })),
        hfr_values,
    }
}

// =============================================================================
// IMAGE-GRADING HELPERS (Wave 3 Image Grading)
// =============================================================================

// =============================================================================
// DEFECT-MAP HELPERS (Wave 7 Agent 3)
// =============================================================================

/// Outcome of the per-frame defect-map application step. Threaded into
/// the FITS HISTORY card emitter so the saved frame carries provenance
/// of the correction (or its skip reason).
#[derive(Debug, Clone)]
pub(crate) enum DefectMapOutcome {
    /// No defect map is configured for the current run. Common case
    /// for users who haven't opted in to defect correction.
    Disabled,
    /// A map was configured but the connected camera id did not match
    /// the map's camera id, OR the map's dimensions did not match the
    /// frame's. In either case the frame is left as-is and a warn line
    /// is logged so the operator sees the skip.
    ///
    /// `reason` is constructed at the call sites (with the specific
    /// mismatch detail) and surfaced in the warn log line emitted there
    /// — keeping the field in the enum means future code paths that
    /// need to inspect or re-emit the reason (e.g. a richer skip event)
    /// can do so without changing the shape.
    SkippedMismatch {
        #[allow(dead_code)]
        reason: String,
    },
    /// The map matched and was applied. The corrected pixel count may
    /// be smaller than the map's defective_count when some defects had
    /// no healthy neighbours inside the expanded kernel.
    Applied {
        camera_id: String,
        defect_count: u32,
        corrected_count: u32,
        kernel_diameter: u8,
        method: &'static str,
        save_original: bool,
    },
}

impl DefectMapOutcome {
    /// Convert to a FrameContext-side record. Returns `None` when no
    /// correction was actually applied — callers must not emit a
    /// HISTORY card claiming a correction happened when one did not.
    fn into_record(self) -> Option<crate::scheduling::DefectMapCorrectionRecord> {
        match self {
            DefectMapOutcome::Applied {
                camera_id,
                defect_count,
                corrected_count,
                kernel_diameter,
                method,
                save_original: _,
            } => Some(crate::scheduling::DefectMapCorrectionRecord {
                camera_id,
                defect_count,
                corrected_count,
                kernel_diameter,
                method: method.to_string(),
            }),
            DefectMapOutcome::Disabled | DefectMapOutcome::SkippedMismatch { .. } => None,
        }
    }
}

/// Apply the per-frame defect map to the just-captured image data, in
/// place. Returns the outcome (disabled / skipped / applied) so the
/// FITS HISTORY card emitter and the Raw/ archival step know what
/// happened.
///
/// Pre-conditions / safety:
/// * Camera id mismatch returns `SkippedMismatch` rather than
///   silently applying a map built for a different sensor — that
///   would poison the data with the wrong hot-pixel coordinates.
/// * Dimension mismatch returns `SkippedMismatch` for the same
///   reason; the map's bitmap is sized to the sensor it was built
///   against and applying it to a different frame size would write
///   neighbour medians at coordinates that don't correspond to real
///   defects.
///
/// Why a separate helper: keeping the borrow of
/// `defect_map_apply` to a short read-guard scope means the rest of
/// the capture loop is unaffected. Cloning the inner `Arc<DefectMap>`
/// is cheap (refcount bump) and lets us drop the guard before doing
/// the actual O(defects × kernel) correction work.
pub(crate) async fn apply_defect_map_if_configured(
    ctx: &InstructionContext,
    camera_id: &str,
    image_data: &mut crate::device_ops::ImageData,
    frame_idx: u32,
) -> DefectMapOutcome {
    let snapshot = {
        let guard = ctx.defect_map_apply.read().await;
        guard.clone()
    };
    let Some(state) = snapshot else {
        return DefectMapOutcome::Disabled;
    };

    if state.camera_id != camera_id {
        tracing::warn!(
            "[DEFECT] Frame {} skipping defect-map correction: connected camera id `{}` \
             does not match map's camera id `{}`. The map was built for a different \
             sensor and applying it would poison the data.",
            frame_idx,
            camera_id,
            state.camera_id,
        );
        return DefectMapOutcome::SkippedMismatch {
            reason: format!(
                "camera mismatch: map=`{}`, frame=`{}`",
                state.camera_id, camera_id
            ),
        };
    }

    if state.map.width != image_data.width || state.map.height != image_data.height {
        tracing::warn!(
            "[DEFECT] Frame {} skipping defect-map correction: map dimensions {}x{} do not \
             match frame dimensions {}x{}. A subframe / ROI change has invalidated the map; \
             rebuild it at the new sensor crop.",
            frame_idx,
            state.map.width,
            state.map.height,
            image_data.width,
            image_data.height,
        );
        return DefectMapOutcome::SkippedMismatch {
            reason: format!(
                "size mismatch: map={}x{}, frame={}x{}",
                state.map.width, state.map.height, image_data.width, image_data.height,
            ),
        };
    }

    if state.map.defective_count() == 0 {
        // Empty map = no work, but emit a HISTORY card so the operator
        // sees the map was selected (this catches "I built the map but
        // it has zero defects so nothing happened" confusion).
        return DefectMapOutcome::Applied {
            camera_id: state.camera_id.clone(),
            defect_count: 0,
            corrected_count: 0,
            kernel_diameter: state.kernel.diameter(),
            method: state.method.as_str(),
            save_original: state.save_original,
        };
    }

    let pixels_slice = image_data.data.as_mut_slice();
    let width = image_data.width;
    let height = image_data.height;
    // The sequencer's ImageData is mono u16 (camera output before
    // debayering). channels = 1 is enforced by the capture-side
    // contract; if a driver ever returns a multi-channel buffer we
    // skip correction rather than slice into the wrong storage.
    let channels = 1u32;
    let expected_len = (width as usize) * (height as usize) * (channels as usize);
    if pixels_slice.len() != expected_len {
        tracing::warn!(
            "[DEFECT] Frame {} skipping defect-map correction: pixel buffer length \
             {} does not match {}x{}x{} = {} expected u16 samples.",
            frame_idx,
            pixels_slice.len(),
            width,
            height,
            channels,
            expected_len,
        );
        return DefectMapOutcome::SkippedMismatch {
            reason: format!(
                "buffer length {} != expected {}",
                pixels_slice.len(),
                expected_len
            ),
        };
    }

    let start = std::time::Instant::now();
    let result = nightshade_imaging::defect_map::correct_u16_slice(
        pixels_slice,
        width,
        height,
        channels,
        &state.map,
        state.method,
        state.kernel,
    );
    let elapsed = start.elapsed();
    match result {
        Ok(corrected) => {
            tracing::info!(
                "[DEFECT] Frame {} corrected {} of {} defective pixels in {:.1}ms (kernel={}x{}, method={})",
                frame_idx,
                corrected,
                state.map.defective_count(),
                elapsed.as_secs_f64() * 1000.0,
                state.kernel.diameter(),
                state.kernel.diameter(),
                state.method.as_str(),
            );
            DefectMapOutcome::Applied {
                camera_id: state.camera_id.clone(),
                defect_count: state.map.defective_count(),
                corrected_count: corrected,
                kernel_diameter: state.kernel.diameter(),
                method: state.method.as_str(),
                save_original: state.save_original,
            }
        }
        Err(e) => {
            // Defensive: the slice-level corrector validates dimensions
            // before mutating, so we should never reach this branch
            // given the earlier checks. Surface the error rather than
            // silently swallowing it.
            tracing::error!(
                "[DEFECT] Frame {} defect-map correction failed: {}",
                frame_idx,
                e,
            );
            DefectMapOutcome::SkippedMismatch {
                reason: format!("corrector returned error: {}", e),
            }
        }
    }
}

/// Archive the uncorrected (pre-defect-map) pixels to `<save_dir>/Raw/`.
///
/// We use a minimal FITS writer here that only writes width/height +
/// the u16 sample data — the canonical FITS header (with target,
/// telescope, observer, etc.) is reserved for the corrected frame.
/// This keeps the Raw/ folder a literal "what the sensor produced"
/// archive that a re-stacking workflow can pull through a different
/// correction pipeline without having to subtract out the previous
/// Nightshade correction.
///
/// Why this writer (and not a DeviceOps call): the device-ops
/// `save_fits` writes the full FrameContext header. We deliberately
/// want a bare-bones FITS here so the raw archive can be replayed
/// through external calibration with no Nightshade-specific keywords
/// already on it.
pub(crate) async fn save_uncorrected_raw_frame(
    save_dir: &std::path::Path,
    filename: &str,
    width: u32,
    height: u32,
    pixels: &[u16],
) -> Result<(), String> {
    let raw_dir = save_dir.join("Raw");
    std::fs::create_dir_all(&raw_dir).map_err(|e| {
        format!(
            "could not create Raw/ directory `{}`: {}",
            raw_dir.display(),
            e
        )
    })?;
    let raw_path = raw_dir.join(filename);

    // We rely on the imaging crate's FITS writer for consistency with
    // the rest of the save pipeline. Constructing the ImageData here
    // is a u16→bytes shuffle — for a 26 MP frame that's ~50 MB but
    // it happens off-thread inside spawn_blocking so the capture loop
    // is not blocked.
    let pixels = pixels.to_vec();
    let raw_path_clone = raw_path.clone();
    let join = tokio::task::spawn_blocking(move || {
        let image = nightshade_imaging::ImageData::from_u16(width, height, 1, &pixels);
        let mut header = nightshade_imaging::FitsHeader::new();
        header.set_string("IMAGETYP", "LIGHT");
        header.set_string(
            "COMMENT",
            "Nightshade uncorrected raw (defect map not yet applied)",
        );
        nightshade_imaging::write_fits(&raw_path_clone, &image, &header)
            .map_err(|e| format!("write_fits failed: {}", e))
    })
    .await;
    match join {
        Ok(Ok(())) => {
            tracing::info!("[DEFECT] Raw archive written: {}", raw_path.display());
            Ok(())
        }
        Ok(Err(e)) => Err(e),
        Err(e) => Err(format!("spawn_blocking join failed: {}", e)),
    }
}

/// Resolve the directory where rejected frames go.
///
/// * `override_path = None`: use `<base>/Reject/`.
/// * `override_path = Some(absolute)`: use that path verbatim.
/// * `override_path = Some(relative)`: resolve against `base`.
pub fn resolve_reject_dir(base: &std::path::Path, override_path: Option<&str>) -> PathBuf {
    match override_path {
        Some(p) => {
            let candidate = std::path::Path::new(p);
            if candidate.is_absolute() {
                candidate.to_path_buf()
            } else {
                base.join(candidate)
            }
        }
        None => base.join("Reject"),
    }
}

/// Wave 8 forensics — snapshot the live environmental telemetry into a
/// single `EnvironmentSnapshot`. Each field is read independently with
/// `try_read()` semantics emulated by an `await`; the analyzer treats
/// `None` honestly (no fabrication of stand-ins).
async fn build_environment_snapshot(
    ctx: &InstructionContext,
) -> crate::quality::EnvironmentSnapshot {
    let sky_brightness_mag = *ctx.current_sky_brightness_mag.read().await;
    let cloud_cover_percent = ctx.cloud_motion_snapshot.read().await.current_cover_percent;
    let wind_kph = *ctx.current_wind_kph.read().await;
    // Guide RMS — pull the most recent sample from the trigger state's
    // rolling guide-RMS history. The history is a `Vec<(Instant, f64)>`
    // already maintained for the GuidingFailed trigger evaluator.
    let guide_rms_arcsec = if let Some(trigger_state_lock) = &ctx.trigger_state {
        let state = trigger_state_lock.read().await;
        state
            .guiding_rms_history
            .as_ref()
            .and_then(|h| h.last())
            .map(|(_, rms)| *rms)
    } else {
        None
    };
    let sensor_temp_c = *ctx.current_sensor_temp_c.read().await;
    crate::quality::EnvironmentSnapshot {
        sky_brightness_mag,
        cloud_cover_percent,
        wind_kph,
        guide_rms_arcsec,
        sensor_temp_c,
    }
}

/// Wave 8 forensics — append a sample to the rolling history, enforcing
/// the [`crate::quality::FORENSIC_HISTORY_LEN`] bound. Lock window is
/// minimal (one write_lock acquisition per frame) and the push is
/// guaranteed O(1) regardless of run length.
async fn push_forensic_sample(ctx: &InstructionContext, sample: crate::quality::RecentFrameSample) {
    let mut history = ctx.forensics_history.write().await;
    history.push_back(sample);
    while history.len() > crate::quality::FORENSIC_HISTORY_LEN {
        history.pop_front();
    }
}

/// Emit a structured FrameAccepted / FrameRejected progress event and (on
/// reject) update the consecutive-rejects atomic. Escalates to an
/// `ExecutorEvent::Error` once the consecutive-rejects threshold is hit —
/// Wave 1.5 Pack C's critical-event banner picks that up automatically.
///
/// Wave 8 — Frame-Failure Forensics: in addition to the existing event,
/// this function:
///
/// 1. Snapshots live environmental telemetry (sky brightness, cloud cover,
///    wind, guide RMS, sensor temperature) from the shared
///    `ExecutionContext` Arcs.
/// 2. On reject, consults [`crate::quality::analyze_rejection`] with the
///    rolling history to classify the rejection (`LikelyCause`) and
///    produce an evidence-bullet list.
/// 3. Pushes the new frame sample (accepted or rejected) onto the rolling
///    history so subsequent rejects have full context.
#[allow(clippy::too_many_arguments)]
async fn emit_grade_progress(
    ctx: &InstructionContext,
    grade: crate::quality::FrameGrade,
    metrics: &crate::quality::FrameMetrics,
    frame: u32,
    total: u32,
    full_path: &std::path::Path,
    frames_accepted: &Arc<std::sync::atomic::AtomicU32>,
    frames_rejected: &Arc<std::sync::atomic::AtomicU32>,
    consecutive_rejects: &Arc<std::sync::atomic::AtomicU32>,
    max_consecutive: u32,
) {
    use std::sync::atomic::Ordering;
    // Wave 8 forensics — snapshot the environment once up-front so the
    // values reported in the event match the values fed to the
    // classifier. (Two separate reads could race against the
    // ExecutorCommand::UpdateCloudMotion / UpdateSkyBrightness handlers.)
    let env_snapshot = build_environment_snapshot(ctx).await;
    match &grade {
        crate::quality::FrameGrade::Pass => {
            let accepted = frames_accepted.fetch_add(1, Ordering::Relaxed) + 1;
            consecutive_rejects.store(0, Ordering::Relaxed);
            let rejected = frames_rejected.load(Ordering::Relaxed);
            // Wave 8 forensics: log the accepted sample so subsequent
            // rejects can compare against it. We capture the env
            // snapshot too — the SeeingSpike / FocusDrift heuristics
            // require trailing accepted frames to have HFR populated.
            push_forensic_sample(
                ctx,
                crate::quality::RecentFrameSample {
                    unix_secs: chrono::Utc::now().timestamp() as f64,
                    accepted: true,
                    hfr: metrics.hfr,
                    eccentricity: metrics.eccentricity,
                    star_count: metrics.star_count,
                    sky_brightness_mag: env_snapshot.sky_brightness_mag,
                    cloud_cover_percent: env_snapshot.cloud_cover_percent,
                    wind_kph: env_snapshot.wind_kph,
                    guide_rms_arcsec: env_snapshot.guide_rms_arcsec,
                    sensor_temp_c: env_snapshot.sensor_temp_c,
                },
            )
            .await;
            // Pack H: emit a structured `ProgressDetail::FrameAccepted` so
            // the bridge can dispatch the typed `SequencerEvent::FrameAccepted`
            // variant. The legacy `detail` string is still populated from
            // `ProgressDetail::detail_text()` so any subscriber that hasn't
            // migrated keeps working. The metrics come from `_metrics` (the
            // `FrameMetrics` computed by the grader) because `FrameGrade::Pass`
            // is a unit variant.
            let structured = crate::node::ProgressDetail::FrameAccepted {
                frame,
                total,
                hfr: metrics.hfr,
                eccentricity: metrics.eccentricity,
                star_count: metrics.star_count,
                accepted_total: accepted,
                rejected_total: rejected,
                // Wave 6 Pack P — surface the on-disk save path so the
                // Wave 6 thumbnail strip can render an inline preview of
                // accepted frames the same way it already does for
                // rejected ones via `FrameRejected.reject_path`. The
                // path is the resolved FITS file we just wrote (so the
                // strip's path resolver can hand it straight to the
                // image-loader without further translation).
                save_path: Some(full_path.display().to_string()),
            };
            let detail_text = structured.detail_text();
            if let Some(event_tx) = &ctx.event_tx {
                let _ = event_tx.send(crate::executor::ExecutorEvent::NodeProgress {
                    node_id: String::new(),
                    instruction: "Exposure".to_string(),
                    progress_percent: 100.0 * frame as f64 / total.max(1) as f64,
                    detail: detail_text,
                    structured_detail: Some(Box::new(structured)),
                });
            }
            // Wave 8 Replay Debug — record a FrameAccepted decision so
            // the replay timeline surfaces every accepted frame next
            // to the rejected ones. We hand the path through too so
            // the replay UI can cross-link to the captured-image row.
            ctx.emit_decision(crate::decision::DecisionEvent::new(
                crate::decision::DecisionCategory::FrameAccepted,
                format!(
                    "Frame {}/{} accepted{}",
                    frame,
                    total,
                    metrics
                        .hfr
                        .map(|h| format!(" (HFR {:.2})", h))
                        .unwrap_or_default(),
                ),
                serde_json::json!({
                    "frame": frame,
                    "total": total,
                    "hfr": metrics.hfr,
                    "eccentricity": metrics.eccentricity,
                    "star_count": metrics.star_count,
                    "save_path": full_path.display().to_string(),
                    "accepted_total": accepted,
                    "rejected_total": rejected,
                }),
            ));
        }
        crate::quality::FrameGrade::Reject {
            reason,
            hfr,
            eccentricity,
            star_count,
        } => {
            let rejected = frames_rejected.fetch_add(1, Ordering::Relaxed) + 1;
            let accepted = frames_accepted.load(Ordering::Relaxed);
            let consecutive = consecutive_rejects.fetch_add(1, Ordering::Relaxed) + 1;

            tracing::warn!(
                "[GRADE] Frame {}/{} REJECTED ({}× consecutive): {} (HFR={:?}, ecc={:?}, stars={:?}, path={})",
                frame,
                total,
                consecutive,
                reason,
                hfr,
                eccentricity,
                star_count,
                full_path.display()
            );

            // Wave 8 forensics — read the rolling history (cheap clone of
            // VecDeque -> Vec since only the analyzer needs a contiguous
            // slice) and consult the classifier. The history read MUST
            // happen before `push_forensic_sample` below so the current
            // frame doesn't classify against itself. We snapshot the HFR
            // baseline from the shared Arc the grader already uses, so
            // the classifier sees the same "what counts as elevated"
            // anchor.
            let history_snapshot: Vec<crate::quality::RecentFrameSample> = {
                let lock = ctx.forensics_history.read().await;
                lock.iter().cloned().collect()
            };
            let baseline_snapshot = *ctx.hfr_baseline.read().await;
            let verdict = crate::quality::analyze_rejection(&crate::quality::ForensicInputs {
                hfr: *hfr,
                eccentricity: *eccentricity,
                star_count: *star_count,
                hfr_baseline: baseline_snapshot,
                environment: env_snapshot.clone(),
                recent_frames: &history_snapshot,
                grader_reason: reason.as_str(),
            });
            tracing::info!(
                "[FORENSICS] Frame {}/{} cause={} evidence={:?}",
                frame,
                total,
                verdict.likely_cause.map(|c| c.label()).unwrap_or("none"),
                verdict.evidence,
            );

            // Pack H: structured FrameRejected payload mirrors what the
            // bridge needs to dispatch SequencerEvent::FrameRejected; the
            // legacy detail string remains for back-compat. Wave 8
            // forensics fields are populated from the verdict + the
            // pre-classification environment snapshot.
            let structured = crate::node::ProgressDetail::FrameRejected {
                frame,
                total,
                reason: reason.clone(),
                hfr: *hfr,
                eccentricity: *eccentricity,
                star_count: *star_count,
                reject_path: full_path.display().to_string(),
                consecutive_rejects: consecutive,
                accepted_total: accepted,
                rejected_total: rejected,
                likely_cause: verdict.likely_cause,
                evidence: verdict.evidence.clone(),
                sky_brightness_at_capture: env_snapshot.sky_brightness_mag,
                cloud_cover_at_capture: env_snapshot.cloud_cover_percent,
                wind_at_capture: env_snapshot.wind_kph,
                guide_rms_at_capture: env_snapshot.guide_rms_arcsec,
                sensor_temp_at_capture: env_snapshot.sensor_temp_c,
            };
            // Append the rejected sample to the history AFTER
            // classification so the next reject sees this one in its
            // neighbour cluster.
            push_forensic_sample(
                ctx,
                crate::quality::RecentFrameSample {
                    unix_secs: chrono::Utc::now().timestamp() as f64,
                    accepted: false,
                    hfr: *hfr,
                    eccentricity: *eccentricity,
                    star_count: *star_count,
                    sky_brightness_mag: env_snapshot.sky_brightness_mag,
                    cloud_cover_percent: env_snapshot.cloud_cover_percent,
                    wind_kph: env_snapshot.wind_kph,
                    guide_rms_arcsec: env_snapshot.guide_rms_arcsec,
                    sensor_temp_c: env_snapshot.sensor_temp_c,
                },
            )
            .await;
            let detail_text = structured.detail_text();
            if let Some(event_tx) = &ctx.event_tx {
                let _ = event_tx.send(crate::executor::ExecutorEvent::NodeProgress {
                    node_id: String::new(),
                    instruction: "Exposure".to_string(),
                    progress_percent: 100.0 * frame as f64 / total.max(1) as f64,
                    detail: detail_text,
                    structured_detail: Some(Box::new(structured)),
                });
            }
            // Wave 8 Replay Debug — record a FrameRejected decision so
            // the replay timeline carries the verdict + forensics
            // payload alongside the consecutive-rejects escalation.
            // Cross-links to forensics via the `reject_path` field
            // which the replay UI uses to deep-link.
            ctx.emit_decision(crate::decision::DecisionEvent::new(
                crate::decision::DecisionCategory::FrameRejected,
                format!(
                    "Frame {}/{} REJECTED: {}{}",
                    frame,
                    total,
                    reason,
                    if consecutive > 1 {
                        format!(" ({}× consecutive)", consecutive)
                    } else {
                        String::new()
                    },
                ),
                serde_json::json!({
                    "frame": frame,
                    "total": total,
                    "reason": reason,
                    "hfr": hfr,
                    "eccentricity": eccentricity,
                    "star_count": star_count,
                    "reject_path": full_path.display().to_string(),
                    "consecutive_rejects": consecutive,
                    "accepted_total": accepted,
                    "rejected_total": rejected,
                }),
            ));

            // Escalation: max_consecutive_rejects in a row => emit Error
            // (Wave 1.5 Pack C critical-event banner) and pause the
            // sequence. We do NOT cancel — the user may want to inspect
            // the rejects and resume.
            if consecutive >= max_consecutive && max_consecutive > 0 {
                let escalation = format!(
                    "Image grading: {} consecutive rejects (limit {}). \
                     Sequence paused for inspection. Frame {}/{}, last reason: {}. \
                     Most recent reject: {}. Accepted so far: {}, rejected: {}.",
                    consecutive,
                    max_consecutive,
                    frame,
                    total,
                    reason,
                    full_path.display(),
                    accepted,
                    rejected,
                );
                tracing::error!("{}", escalation);
                if let Some(event_tx) = &ctx.event_tx {
                    let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                        message: escalation,
                    });
                }
                // The executor watches its own pause flag separately; we
                // can't reach across into ExecutionContext from here, so we
                // signal via Error which Pack C handles as critical.
            }
            // _ silence — used only for tracing above.
            let _ = (hfr, eccentricity, star_count);
        }
    }
}

// =============================================================================
// FRAME CONTEXT BUILDER (Wave 3 Image Grading)
// =============================================================================

/// Build the per-frame FITS-header bundle for the current capture.
///
/// Reads everything the FITS writer needs:
/// - session-static fields from `InstructionContext` (session_id, observer,
///   equipment ID, site coords)
/// - per-target fields from `InstructionContext` (target_name/id, mosaic_panel)
/// - exposure settings from the active `ExposureConfig`
/// - live device telemetry by querying the connected focuser / rotator /
///   guider via `DeviceOps`. Each query is best-effort: a device that fails
///   to report its state simply omits the corresponding FITS keyword. We
///   never substitute sentinel values (the audit's silent-fallback rule).
/// - the most recent plate-solve result, if CenterTarget ran for this target
///
/// The live-telemetry reads are bounded: the focuser/rotator/guide queries
/// are simple status reads (no motion commands) and the existing DeviceOps
/// implementations cache the values, so this adds <10 ms of overhead per
/// frame — negligible compared to the multi-second exposure.
async fn build_frame_context_for_save(
    ctx: &InstructionContext,
    config: &ExposureConfig,
    image_data: &ImageData,
    frame_index: u32,
    defect_map_outcome: DefectMapOutcome,
) -> crate::scheduling::FrameContext {
    let (bin_x, bin_y) = match config.binning {
        Binning::One => (1u32, 1u32),
        Binning::Two => (2, 2),
        Binning::Three => (3, 3),
        Binning::Four => (4, 4),
    };

    let mut frame_ctx = crate::scheduling::FrameContext::new_light(
        ctx.session_id.clone(),
        bin_x,
        bin_y,
        config.duration_secs,
        frame_index,
    );

    frame_ctx.total_planned_frames = Some(config.count);

    // Target identification — use the running target from the executor (not
    // the synthesized "untargeted" label used for the filename, which is a
    // legitimate operator-visible signal but should not pollute the FITS
    // OBJECT keyword).
    frame_ctx.target_id = ctx.target_id.clone();
    frame_ctx.target_name = ctx.target_name.clone();
    frame_ctx.target_ra_hours = ctx.target_ra;
    frame_ctx.target_dec_degrees = ctx.target_dec;

    // Filter.
    frame_ctx.filter_name = config.filter.clone().or_else(|| ctx.current_filter.clone());
    frame_ctx.filter_index = config.filter_index.or(ctx.current_filter_index);

    // Camera settings (already on ImageData from the capture).
    frame_ctx.gain = image_data.gain.or(config.gain);
    frame_ctx.offset = image_data.offset.or(config.offset);
    frame_ctx.sensor_temp_c = image_data.temperature;
    frame_ctx.set_temp_c = ctx.set_temp_c;

    // Bayer pattern — prefer the camera-reported sensor type over a stale
    // ExecutionContext value. A camera reporting "Monochrome" overrides any
    // stale "RGGB" left from a previous (different-camera) session.
    frame_ctx.bayer_pattern = match image_data.sensor_type.as_deref() {
        Some(s) if s.eq_ignore_ascii_case("Monochrome") || s.eq_ignore_ascii_case("Mono") => None,
        _ => ctx.bayer_pattern.clone(),
    };

    // Mosaic panel.
    frame_ctx.mosaic_panel = ctx.mosaic_panel.clone();

    // Observer / site.
    frame_ctx.observer_name = ctx.observer_name.clone();
    frame_ctx.site_latitude_deg = ctx.latitude;
    frame_ctx.site_longitude_deg = ctx.longitude;
    frame_ctx.site_elevation_m = ctx.site_elevation_m;

    // Equipment identification.
    frame_ctx.camera_make = ctx.camera_make.clone();
    frame_ctx.camera_model = ctx.camera_model.clone();
    frame_ctx.telescope_name = ctx.telescope_name.clone();
    frame_ctx.telescope_focal_length_mm = ctx.telescope_focal_length_mm;
    frame_ctx.telescope_aperture_mm = ctx.telescope_aperture_mm;

    // Live focuser telemetry. We use match arms so a driver error just
    // omits the keyword — never overrides with a fake value. The focuser
    // temperature is `Option<f64>` even on success because not every
    // focuser model has a thermistor.
    if let Some(focuser_id) = &ctx.focuser_id {
        match ctx.device_ops.focuser_get_position(focuser_id).await {
            Ok(pos) => frame_ctx.focuser_position = Some(pos),
            Err(e) => tracing::debug!(
                "[CAPTURE] focuser_get_position failed; FOCUSPOS omitted: {}",
                e
            ),
        }
        match ctx.device_ops.focuser_get_temperature(focuser_id).await {
            Ok(temp) => frame_ctx.focuser_temperature_c = temp,
            Err(e) => tracing::debug!(
                "[CAPTURE] focuser_get_temperature failed; FOCTEMP omitted: {}",
                e
            ),
        }
    }

    // Live rotator telemetry.
    if let Some(rotator_id) = &ctx.rotator_id {
        match ctx.device_ops.rotator_get_angle(rotator_id).await {
            Ok(angle) => frame_ctx.rotator_angle_deg = Some(angle),
            Err(e) => tracing::debug!(
                "[CAPTURE] rotator_get_angle failed; ROTATPOS omitted: {}",
                e
            ),
        }
    }

    // Live guide RMS (PHD2 / built-in guider). The guider may be off (no
    // guiding for short subs), in which case the keyword is omitted.
    match ctx.device_ops.guider_get_status().await {
        Ok(status) if status.is_guiding => {
            frame_ctx.guide_rms_arcsec = Some(status.rms_total);
        }
        Ok(_) => {
            // Guider connected but not currently guiding — omit the keyword.
        }
        Err(e) => tracing::debug!(
            "[CAPTURE] guider_get_status failed; GUIDERMS omitted: {}",
            e
        ),
    }

    // Plate-solve result (only available once CenterTarget has run for
    // this target). Stored as Arc<RwLock<_>> so the executor and exposure
    // share state without cloning.
    {
        let solve_guard = ctx.last_plate_solve.read().await;
        if let Some(solve) = solve_guard.as_ref() {
            // PlateSolveResult stores RA in DEGREES; convert to hours for
            // the SOLVED-RA keyword (which is FITS-standard in degrees).
            // Wait — read the spec: api_save_fits writes RA in HOURS for
            // the RA keyword. Stay consistent: SOLVED-RA in HOURS too.
            frame_ctx.plate_solve_ra_hours = Some(solve.ra_degrees / 15.0);
            frame_ctx.plate_solve_dec_degrees = Some(solve.dec_degrees);
            frame_ctx.plate_solve_pixel_scale_arcsec = Some(solve.pixel_scale);
            frame_ctx.plate_solve_rotation_deg = Some(solve.rotation);
        }
    }

    // Wave 7 Agent 3 — defect-map correction provenance. Only set when
    // the correction actually ran; skipped / disabled outcomes leave
    // the field None and no HISTORY card is emitted by the FITS writer.
    frame_ctx.defect_map_correction = defect_map_outcome.into_record();

    frame_ctx
}

// =============================================================================
// AUTOFOCUS INSTRUCTION
// =============================================================================

/// Execute autofocus using V-curve or curve fitting
pub async fn execute_autofocus(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };
    let focuser_id = match ctx.focuser_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!(
        "Starting autofocus: {:?} method, {} steps, step size {}",
        config.method,
        config.steps_out,
        config.step_size
    );

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(0.0, "Starting autofocus...".to_string());
    }

    // Sweep positions are calculated from the current position outward;
    // failing the read here is fatal because the alternative is to sweep
    // from a guessed origin and land somewhere unrelated to focus.
    tracing::debug!("Getting focuser position for focuser_id: {}", focuser_id);
    let current_position = match ctx.device_ops.focuser_get_position(&focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            tracing::error!("Autofocus failed: Could not get focuser position: {}", e);
            return InstructionResult::failure(format!("Failed to get focuser position: {}", e));
        }
    };

    tracing::info!("Current focuser position: {}", current_position);

    let af_config: crate::autofocus::AutofocusConfig = config.into();

    let af_start_time = std::time::Instant::now();
    let af_timeout = Duration::from_secs_f64(config.max_duration_secs);

    let af_engine = crate::autofocus::VCurveAutofocus::new(af_config.clone());
    let backlash = crate::autofocus::BacklashCompensation::new(af_config.backlash_compensation);

    let positions = af_engine.calculate_positions(current_position);
    let total_points = positions.len();
    let start_position = positions[0];

    let mut focus_data: Vec<crate::autofocus::FocusDataPoint> = Vec::with_capacity(total_points);

    if let Some(cb) = progress_callback {
        cb(5.0, format!("Moving to start position: {}", start_position));
    }

    if backlash.is_needed(current_position, start_position) {
        let (intermediate, final_pos) =
            backlash.calculate_approach(current_position, start_position);

        if let Some(overshoot) = intermediate {
            tracing::info!(
                "Applying backlash compensation: {} -> {} -> {}",
                current_position,
                overshoot,
                final_pos
            );

            if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, overshoot).await {
                return InstructionResult::failure(format!(
                    "Failed to move focuser (backlash): {}",
                    e
                ));
            }
            if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await
            {
                return InstructionResult::failure(e);
            }
        }

        if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, final_pos).await {
            return InstructionResult::failure(format!("Failed to move focuser: {}", e));
        }
    } else {
        tracing::info!("Moving to start position: {}", start_position);
        if let Err(e) = ctx
            .device_ops
            .focuser_move_to(&focuser_id, start_position)
            .await
        {
            return InstructionResult::failure(format!("Failed to move focuser: {}", e));
        }
    }

    if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(300)).await {
        return InstructionResult::failure(e);
    }

    let (bin_x, bin_y) = match config.binning {
        Binning::One => (1, 1),
        Binning::Two => (2, 2),
        Binning::Three => (3, 3),
        Binning::Four => (4, 4),
    };

    // Audit §1.21: minimum star count is now `config.min_star_count`
    // (default 10 from `default_af_min_star_count`); previously a hardcoded
    // local const. A user with a fast/dim setup can lower it without
    // patching the binary.
    let min_star_count: u32 = config.min_star_count.max(1);
    // 1.0 px² is the noise floor: a V-curve with smaller HFR variance is
    // indistinguishable from flat noise and the fit would extrapolate to
    // nonsense.
    const MIN_HFR_VARIANCE: f64 = 1.0;
    // R²<0.5 means the curve fit is worse than a horizontal line; accepting
    // such a fit would produce a "best" focus that has no physical meaning.
    const MIN_R_SQUARED: f64 = 0.5;

    let mut low_star_count_warnings = 0;

    for point in 0..total_points {
        // Check timeout
        if af_start_time.elapsed() > af_timeout {
            tracing::warn!(
                "Autofocus timed out after {:.0}s (limit: {:.0}s), returning focuser to original position",
                af_start_time.elapsed().as_secs_f64(),
                config.max_duration_secs,
            );
            let _ = ctx.device_ops.focuser_halt(&focuser_id).await;
            wait_for_focuser_stop_after_halt(&focuser_id, &ctx.device_ops, Duration::from_secs(10))
                .await;
            let _ = ctx
                .device_ops
                .focuser_move_to(&focuser_id, current_position)
                .await;
            return InstructionResult::failure(format!(
                "Autofocus timed out after {:.0}s (max duration: {:.0}s)",
                af_start_time.elapsed().as_secs_f64(),
                config.max_duration_secs,
            ));
        }

        if let Some(result) = ctx.check_cancelled() {
            // Halting + stop-wait guarantees the motor is stationary before
            // we issue the return-to-original move; otherwise the second
            // move command could race the in-flight sweep move.
            tracing::info!("Autofocus cancelled, halting focuser");
            let _ = ctx.device_ops.focuser_halt(&focuser_id).await;
            wait_for_focuser_stop_after_halt(&focuser_id, &ctx.device_ops, Duration::from_secs(10))
                .await;
            // Fire-and-forget the return move: the user cancelled, so we
            // don't want to block them with a 30 s wait; if the move
            // succeeds, great, if not, the next instruction will re-park.
            let _ = ctx
                .device_ops
                .focuser_move_to(&focuser_id, current_position)
                .await;
            return result;
        }

        let position = positions[point];

        // 10-90% covers the V-curve sample loop; the remaining 10% is the
        // final move + settle + curve fit, which is the noticeable wait the
        // user sees after the last sample is taken.
        // Why: point and total_points are usize bounded by sweep size (<=50 in UI);
        // lossless to f64.
        let point_progress = 10.0 + (point as f64 / total_points as f64 * 80.0);

        tracing::info!(
            "Focus point {}/{} at position {}",
            point + 1,
            total_points,
            position
        );
        if let Some(cb) = progress_callback {
            cb(
                point_progress,
                format!("Point {}/{}: pos {}", point + 1, total_points, position),
            );
        }

        if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, position).await {
            return InstructionResult::failure(format!("Failed to move focuser: {}", e));
        }

        if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await {
            return InstructionResult::failure(e);
        }

        let image_data = match ctx
            .device_ops
            .camera_start_exposure(
                &camera_id,
                config.exposure_duration,
                None,
                None,
                bin_x,
                bin_y,
            )
            .await
        {
            Ok(data) => {
                tracing::info!(
                    "[SEQ] Exposure completed: {}x{} image ({} pixels)",
                    data.width,
                    data.height,
                    data.data.len()
                );
                data
            }
            Err(e) => {
                return InstructionResult::failure(format!("Autofocus exposure failed: {}", e))
            }
        };

        let measurement = calculate_hfr_with_crops(&image_data);

        tracing::info!(
            "Position {} HFR: {:.2}, Stars: {}",
            position,
            measurement.hfr,
            measurement.star_count
        );

        if measurement.star_count < min_star_count {
            low_star_count_warnings += 1;
            tracing::warn!(
                "Low star count at position {}: {} stars (minimum: {})",
                position,
                measurement.star_count,
                min_star_count
            );

            // >50% of sweep points failing star detection means seeing /
            // clouds / pointing has degraded so badly that no fit will be
            // meaningful; failing fast saves the user the rest of the sweep
            // and a useless curve-fit error.
            if low_star_count_warnings > total_points / 2 {
                let _ = ctx.device_ops.focuser_halt(&focuser_id).await;
                wait_for_focuser_stop_after_halt(
                    &focuser_id,
                    &ctx.device_ops,
                    Duration::from_secs(10),
                )
                .await;
                let _ = ctx
                    .device_ops
                    .focuser_move_to(&focuser_id, current_position)
                    .await;
                return InstructionResult::failure(format!(
                    "Autofocus failed: Insufficient stars detected. Only {} stars found (minimum: {}). \
                     This may indicate clouds, poor seeing, or incorrect camera settings.",
                    measurement.star_count, min_star_count
                ));
            }
        }

        focus_data.push(crate::autofocus::FocusDataPoint {
            position,
            hfr: measurement.hfr,
            fwhm: None,
            star_count: measurement.star_count,
        });

        let progress_json = serde_json::json!({
            "type": "autofocus_progress",
            "point": point + 1,
            "total_points": total_points,
            "hfr": measurement.hfr,
            "star_count": measurement.star_count,
            "focus_range": {
                "min": positions[0],
                "max": positions[total_points - 1]
            },
            "vcurve_points": focus_data.iter().map(|point| {
                serde_json::json!({"position": point.position, "hfr": point.hfr})
            }).collect::<Vec<_>>(),
            "star_crops": measurement.star_crops.iter().map(|crop| {
                serde_json::json!({
                    "pixels_base64": crop.pixels_base64,
                    "width": crop.width,
                    "height": crop.height,
                    "hfr": crop.hfr,
                    "snr": crop.snr
                })
            }).collect::<Vec<_>>()
        });

        if let Some(cb) = progress_callback {
            cb(point_progress, progress_json.to_string());
        }
    }

    if let Some(cb) = progress_callback {
        cb(92.0, "Validating focus data...".to_string());
    }

    // A flat HFR curve (variance < MIN_HFR_VARIANCE) is not a V-curve to fit
    // — it usually means clouds rolled in, the focuser is far outside the
    // critical zone, or the sensor is misreporting. Fitting anyway would
    // produce a meaningless "best focus" position.
    let hfr_values: Vec<f64> = focus_data.iter().map(|point| point.hfr).collect();
    let min_hfr = hfr_values.iter().cloned().fold(f64::INFINITY, f64::min);
    let max_hfr = hfr_values.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let hfr_variance = max_hfr - min_hfr;

    tracing::info!(
        "HFR variance: {:.2} (min: {:.2}, max: {:.2})",
        hfr_variance,
        min_hfr,
        max_hfr
    );

    if hfr_variance < MIN_HFR_VARIANCE {
        // Defensive halt: the focuser *should* be idle here (we waited at
        // each sweep point), but a transient driver error could leave it
        // moving; halting before the return-to-original prevents a queued
        // move from racing the recovery move.
        let _ = ctx.device_ops.focuser_halt(&focuser_id).await;
        wait_for_focuser_stop_after_halt(&focuser_id, &ctx.device_ops, Duration::from_secs(10))
            .await;
        let _ = ctx
            .device_ops
            .focuser_move_to(&focuser_id, current_position)
            .await;
        return InstructionResult::failure(format!(
            "Autofocus failed: No valid V-curve detected. HFR variance is only {:.2} (minimum: {:.1}). \
             The HFR is not changing with focus position, which may indicate: \
             - Clouds or obstructions blocking the sky \
             - Hot pixels being detected instead of real stars \
             - Focus range is too narrow or too far from true focus \
             - Camera is not properly connected or imaging",
            hfr_variance, MIN_HFR_VARIANCE
        ));
    }

    let af_result = match af_engine.find_best_focus(focus_data) {
        Ok(mut result) => {
            result.temperature_celsius = ctx
                .device_ops
                .focuser_get_temperature(&focuser_id)
                .await
                .ok()
                .flatten();
            result
        }
        Err(e) => {
            // Curve fit failed (too many outliers, singular matrix, parabola
            // with no minimum — all reachable under clouds/poor seeing). At
            // this point the focuser sits at the OUTWARD sweep extreme, so
            // leaving it there would strand focus hundreds of steps off and
            // make any retry sweep around the wrong origin. Restore the pre-AF
            // position before failing — mirroring the timeout / cancel /
            // low-star / flat-variance handlers above (which all already do
            // this). Without it the focuser is left parked at the extreme.
            tracing::warn!(
                "Autofocus curve fit failed ({}); returning focuser to original position {}",
                e,
                current_position
            );
            let _ = ctx.device_ops.focuser_halt(&focuser_id).await;
            wait_for_focuser_stop_after_halt(&focuser_id, &ctx.device_ops, Duration::from_secs(10))
                .await;
            let _ = ctx
                .device_ops
                .focuser_move_to(&focuser_id, current_position)
                .await;
            let _ = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await;
            return InstructionResult::failure(format!("Autofocus curve fitting failed: {}", e));
        }
    };

    // Clamp the fitted best-focus position to the swept range. The parabolic
    // and hyperbolic fits return the analytic vertex, which for a poor-quality
    // (low-R²) curve can land far outside the sampled bracket — an
    // extrapolation that is by definition untrustworthy and, on a permissive
    // driver, would drive the focuser wildly out of position. A vertex outside
    // the bracket means true focus was not bracketed; clamping bounds the move
    // to the sampled window (worst case: a sweep endpoint near where we
    // started) instead of an arbitrary extrapolated step.
    let sweep_lo = positions[0].min(positions[total_points - 1]);
    let sweep_hi = positions[0].max(positions[total_points - 1]);
    let best_position = {
        let raw = af_result.best_position;
        let clamped = raw.clamp(sweep_lo, sweep_hi);
        if clamped != raw {
            tracing::warn!(
                "Autofocus best-focus vertex {} fell outside the swept range [{}, {}]; \
                 clamping to {}. The curve minimum was an extrapolation (poor fit) — \
                 true focus may lie outside the sweep window.",
                raw,
                sweep_lo,
                sweep_hi,
                clamped
            );
        }
        clamped
    };
    let best_hfr = af_result.best_hfr;
    let r_squared = af_result.curve_fit_quality;

    // We warn (not fail) on low R² because some legitimate setups produce
    // marginal fits (very sparse star fields) and a "best guess" focus is
    // still better than aborting; the user sees the warning in the log.
    if r_squared < MIN_R_SQUARED {
        tracing::warn!(
            "Low curve fit quality: R²={:.3} (minimum: {:.1}). Proceeding with caution.",
            r_squared,
            MIN_R_SQUARED
        );
    }

    tracing::info!(
        "Best focus at position {}, HFR: {:.2}, R²: {:.3}",
        best_position,
        best_hfr,
        r_squared
    );

    if let Some(cb) = progress_callback {
        cb(95.0, format!("Moving to best focus: {}", best_position));
    }

    let last_position = positions[positions.len() - 1];
    if backlash.is_needed(last_position, best_position) {
        let (intermediate, final_pos) = backlash.calculate_approach(last_position, best_position);

        if let Some(overshoot) = intermediate {
            tracing::info!(
                "Final move with backlash: overshoot to {}, then {}",
                overshoot,
                final_pos
            );

            if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, overshoot).await {
                return InstructionResult::failure(format!(
                    "Failed to move focuser (final backlash): {}",
                    e
                ));
            }
            if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await
            {
                return InstructionResult::failure(e);
            }
        }

        if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, final_pos).await {
            return InstructionResult::failure(format!("Failed to move to best focus: {}", e));
        }
    } else if let Err(e) = ctx
        .device_ops
        .focuser_move_to(&focuser_id, best_position)
        .await
    {
        return InstructionResult::failure(format!("Failed to move to best focus: {}", e));
    }

    if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await {
        return InstructionResult::failure(format!("Failed to settle at best focus: {}", e));
    }

    if let Some(cb) = progress_callback {
        cb(
            100.0,
            format!(
                "Complete: pos {}, HFR {:.2}, R² {:.3}",
                best_position, best_hfr, r_squared
            ),
        );
    }

    InstructionResult {
        status: NodeStatus::Success,
        message: Some(format!(
            "Autofocus complete: position {}, HFR {:.2}, R² {:.3}",
            best_position, best_hfr, r_squared
        )),
        data: serde_json::to_value(&af_result).ok(),
        hfr_values: vec![best_hfr],
    }
}

/// Enhanced HFR measurement with star crops for UI display
struct HfrMeasurementWithCrops {
    hfr: f64,
    star_count: u32,
    /// Base64-encoded star crops (80x80 grayscale), up to 5 brightest stars
    star_crops: Vec<StarCropInfo>,
}

/// Star crop info for UI display
struct StarCropInfo {
    /// Base64-encoded grayscale pixels
    pixels_base64: String,
    width: u32,
    height: u32,
    hfr: f64,
    snr: f64,
}

/// Calculate HFR from image data, returning HFR, star count, and star crops
fn calculate_hfr_with_crops(image: &ImageData) -> HfrMeasurementWithCrops {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
    use nightshade_imaging::{
        detect_stars_with_stats, extract_top_star_crops, StarDetectionConfig,
    };

    // 1 channel = monochrome; raw imager output is treated as mono for HFR
    // regardless of Bayer pattern, because debayering before star detection
    // would smear PSFs and inflate HFR.
    let imaging_data =
        nightshade_imaging::ImageData::from_u16(image.width, image.height, 1, &image.data);

    let config = StarDetectionConfig::default();
    let result = detect_stars_with_stats(&imaging_data, &config);

    // 20.0 px is the "no valid focus" sentinel: an HFR this high is far
    // beyond any realistic well-focused setup, so the V-curve fit will
    // treat the point as the extreme of the curve (or reject as outlier).
    let hfr = if result.median_hfr > 0.0 && result.star_count > 0 {
        result.median_hfr
    } else {
        20.0
    };

    // 5 crops @ 80 px is the upper bound the autofocus UI displays; more
    // would saturate the operator's view and inflate the JSON payload sent
    // over the FRB bridge.
    let crops = extract_top_star_crops(&imaging_data, &result.stars, 5, 80);

    let star_crops: Vec<StarCropInfo> = crops
        .into_iter()
        .map(|crop| StarCropInfo {
            pixels_base64: BASE64.encode(&crop.pixels),
            width: crop.width,
            height: crop.height,
            hfr: crop.hfr,
            snr: crop.snr,
        })
        .collect();

    HfrMeasurementWithCrops {
        hfr,
        star_count: result.star_count,
        star_crops,
    }
}

// =============================================================================
// DITHER INSTRUCTION
// =============================================================================

/// Execute dither
pub async fn execute_dither(
    config: &DitherConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, "Starting dither".to_string());
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    let (dither_pixels, ra_only) = match config.pattern {
        crate::DitherPattern::Random => {
            tracing::info!("Dithering {} pixels (random)", config.pixels);
            (config.pixels, config.ra_only)
        }
        crate::DitherPattern::Grid => {
            // Grid pattern requires trigger state because the next position
            // must be sticky across calls — without it we cannot walk the
            // NxN cells in order and would loop the same cell.
            if let Some(ref trigger_state) = ctx.trigger_state {
                let (ra_offset, dec_offset) = {
                    let mut state = trigger_state.write().await;
                    let offset = state.next_grid_dither_offset(config.grid_size, config.pixels);
                    tracing::info!(
                        "Grid dither: position {}/{} -> RA={:.1}px, Dec={:.1}px",
                        state.grid_dither_index,
                        config.grid_size * config.grid_size,
                        offset.0,
                        offset.1
                    );
                    offset
                };

                // guider_dither takes a single magnitude scalar, so we
                // collapse the 2D grid offset into its Euclidean magnitude.
                // The guider then performs a random-direction dither of that
                // magnitude, which is acceptable because the grid algorithm
                // already enforces spatial coverage at the planning layer.
                let magnitude = (ra_offset * ra_offset + dec_offset * dec_offset).sqrt();
                if magnitude < 0.01 {
                    // The (0,0) cell is the original target position — a
                    // dither of 0 px would still trigger a settle wait for no
                    // benefit. Returning a synthetic Success keeps the grid
                    // cadence intact (next call advances to the next cell).
                    tracing::info!("Grid dither at center position, skipping");
                    if let Some(cb) = progress_callback {
                        cb(100.0, "Grid dither at center - skipping".to_string());
                    }
                    return InstructionResult::success_with_message(
                        "Grid dither at center position (no move needed)",
                    );
                }

                // Audit §1.13: previously we collapsed grid-mode to RA-only
                // when `dec_offset.abs() < 0.01`, a magic threshold that
                // surreptitiously changed user-requested 2D grid behaviour
                // into 1D dithering for any cell whose Dec component happened
                // to round near zero. Grid mode now passes the user's
                // explicit `ra_only` flag through unchanged so the next grid
                // cell's RA *and* Dec offsets are honoured by the guider.
                (magnitude, config.ra_only)
            } else {
                tracing::warn!(
                    "Grid dither requested but no trigger state available, falling back to random"
                );
                (config.pixels, config.ra_only)
            }
        }
    };

    if let Some(cb) = progress_callback {
        cb(30.0, "Sending dither command to guider".to_string());
    }

    // guider_dither blocks until the move + settle completes. We can only
    // emit synthetic progress points around it; the device-ops layer does
    // not expose sub-step progress, so the UI shows discrete checkpoints
    // rather than a smooth bar during this phase.
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for dither to complete".to_string());
    }

    // Last cancellation check before a potentially 60+ s blocking call —
    // there is no way to interrupt guider_dither once it's running.
    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(70.0, "Waiting for guiding to settle".to_string());
    }

    match ctx
        .device_ops
        .guider_dither(
            dither_pixels,
            config.settle_pixels,
            config.settle_time,
            config.settle_timeout,
            ra_only,
        )
        .await
    {
        Ok(_) => {
            if let Some(cb) = progress_callback {
                cb(100.0, "Dither complete".to_string());
            }
            let pattern_name = match config.pattern {
                crate::DitherPattern::Random => "random",
                crate::DitherPattern::Grid => "grid",
            };
            InstructionResult::success_with_message(format!(
                "Dither ({}) and settle complete",
                pattern_name
            ))
        }
        Err(e) => InstructionResult::failure(format!("Dither failed: {}", e)),
    }
}

// =============================================================================
// GUIDING START/STOP INSTRUCTIONS
// =============================================================================

/// Execute start guiding - starts PHD2 guiding and waits for settle
pub async fn execute_start_guiding(
    config: &StartGuidingConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    tracing::info!(
        "Starting guiding with settle threshold {} px",
        config.settle_pixels
    );

    if let Some(cb) = progress_callback {
        cb(0.0, "Starting guiding".to_string());
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(20.0, "Connecting to guider".to_string());
    }

    // Pre-flight status read serves two purposes: surface connection
    // problems before issuing a guider_start (which has worse error
    // diagnostics), and seed the log with the pre-state so post-start
    // RMS readings can be compared to the baseline.
    match ctx.device_ops.guider_get_status().await {
        Ok(status) => {
            tracing::debug!(
                "Guider status: is_guiding={}, rms_total={:.2}",
                status.is_guiding,
                status.rms_total
            );
        }
        Err(e) => {
            // Some guiders (PHD2 in calibration) cannot answer status
            // queries but still accept Start; treat the read failure as a
            // soft warning rather than abort the sequence.
            tracing::warn!("Could not get guider status: {}", e);
        }
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(40.0, "Starting guide camera loop".to_string());
    }

    if let Some(cb) = progress_callback {
        cb(60.0, "Waiting for guiding to stabilize".to_string());
    }

    match ctx
        .device_ops
        .guider_start(
            config.settle_pixels,
            config.settle_time,
            config.settle_timeout,
        )
        .await
    {
        Ok(_) => {
            // ENG-F10: Validate that guiding actually reached "guiding" state.
            // guider_start() may return Ok without the guider truly locking on.
            // Poll status with a timeout to confirm guiding is active.
            if let Some(cb) = progress_callback {
                cb(80.0, "Verifying guiding is active".to_string());
            }

            // Why: settle_timeout is f64 seconds (UI-bounded 0..3600 typical).
            // f64 -> u64 saturates per Rust 1.45 spec; negatives clamp to 0
            // which Duration::from_secs treats as "no wait" — surfaces as an
            // immediate timeout, not a silent hang.
            let verification_timeout = Duration::from_secs(config.settle_timeout as u64);
            let poll_interval = Duration::from_secs(2);
            let deadline = tokio::time::Instant::now() + verification_timeout;
            let mut guiding_confirmed = false;

            while tokio::time::Instant::now() < deadline {
                if let Some(result) = ctx.check_cancelled() {
                    return result;
                }

                match ctx.device_ops.guider_get_status().await {
                    Ok(status) if status.is_guiding => {
                        tracing::info!(
                            "Guiding confirmed active: RMS total={:.2}\"",
                            status.rms_total
                        );
                        guiding_confirmed = true;
                        break;
                    }
                    Ok(status) => {
                        tracing::debug!(
                            "Guiding not yet active (is_guiding={}), waiting...",
                            status.is_guiding
                        );
                    }
                    Err(e) => {
                        tracing::warn!("Guider status poll failed: {}", e);
                    }
                }

                sleep(poll_interval).await;
            }

            if !guiding_confirmed {
                return InstructionResult::failure(format!(
                    "Guiding did not reach active state within {:.0}s timeout. \
                     The guider may have failed to calibrate or lock onto a star.",
                    config.settle_timeout
                ));
            }

            // P3-7: post-start calibration quality validation. A guider can
            // report `is_guiding == true` and still be hopelessly miscalibrated
            // — wrong axis directions, mirror-flipped pulses, near-singular
            // matrix. The audit specifically flagged that bad calibrations
            // were "slipping through" the existing is_guiding poll, so this
            // gate is fail-closed (errors fail the StartGuiding instruction
            // rather than letting the night drift away silently).
            if config.validate_calibration {
                if let Some(cb) = progress_callback {
                    cb(90.0, "Validating calibration quality".to_string());
                }

                // Step 1: axis geometry — fetch calibration data and check
                // that the reported axis angles are reasonably perpendicular.
                match ctx.device_ops.guider_get_calibration().await {
                    Ok(calib) => {
                        if let Err(reason) = validate_calibration_quality(&calib, config) {
                            return InstructionResult::failure(reason);
                        }
                    }
                    Err(e) => {
                        // Driver doesn't expose calibration angles (some Alpaca
                        // backends): warn but don't fail — the RMS check below
                        // is the safety net.
                        tracing::warn!(
                            "Skipping calibration-axis validation: {} \
                             (driver does not report calibration data)",
                            e
                        );
                    }
                }

                // Step 2: post-settle RMS sanity — sample over a short window
                // to catch calibrations whose RMS only blows up after the
                // initial settle (drift / over-correction).
                let rms_samples: u32 = 3;
                let rms_interval = Duration::from_secs(2);
                let mut max_rms: f64 = 0.0;
                let mut sample_count: u32 = 0;
                for _ in 0..rms_samples {
                    if let Some(result) = ctx.check_cancelled() {
                        return result;
                    }
                    sleep(rms_interval).await;
                    match ctx.device_ops.guider_get_status().await {
                        Ok(status) => {
                            max_rms = max_rms.max(status.rms_total);
                            sample_count += 1;
                        }
                        Err(e) => {
                            tracing::warn!("RMS sample failed during validation: {}", e);
                        }
                    }
                }
                if sample_count > 0 && max_rms > config.max_post_settle_rms_pixels {
                    return InstructionResult::failure(format!(
                        "Post-settle guiding RMS too high: {:.2}px peak across {} sample(s) \
                         over {}s (limit {:.2}px). Calibration looks poor — \
                         recalibrate the guider before continuing.",
                        max_rms,
                        sample_count,
                        rms_samples as u64 * rms_interval.as_secs(),
                        config.max_post_settle_rms_pixels
                    ));
                }
                tracing::info!(
                    "Calibration validation passed: peak RMS {:.2}px over {}s window",
                    max_rms,
                    rms_samples as u64 * rms_interval.as_secs()
                );
            }

            // Arm the GuideStarLost trigger now that guiding is confirmed
            // active. Without this the trigger's `guiding_enabled` gate stays
            // false and a lost star is never detected — the sequence would
            // silently take unguided subs until dawn. The executor poll also
            // latches this from live status, but setting it here closes the
            // window between StartGuiding completing and the next poll tick.
            if let Some(trigger_state_lock) = &ctx.trigger_state {
                trigger_state_lock.write().await.set_guiding_enabled(true);
            }

            if let Some(cb) = progress_callback {
                cb(100.0, "Guiding active".to_string());
            }
            InstructionResult::success_with_message("Guiding started and verified active")
        }
        Err(e) => InstructionResult::failure(format!("Failed to start guiding: {}", e)),
    }
}

/// P3-7: pure validation function over a `GuidingCalibration` snapshot.
/// Extracted from `execute_start_guiding` so it can be unit-tested without
/// spinning up a full device stack.
///
/// Returns `Err(reason)` with a user-facing message if calibration looks
/// broken; `Ok(())` if it should proceed.
pub fn validate_calibration_quality(
    calib: &crate::GuidingCalibration,
    config: &StartGuidingConfig,
) -> Result<(), String> {
    if !calib.is_calibrated {
        return Err(
            "Guider reports it is not calibrated after StartGuiding completed. \
             This usually means calibration was cancelled or failed silently."
                .to_string(),
        );
    }

    if let (Some(ra), Some(dec)) = (calib.ra_angle_deg, calib.dec_angle_deg) {
        // The axes should be ~90° apart (modulo 180°, since either axis
        // could be the "positive" direction). Compute the deviation from
        // perpendicularity in degrees in [0, 90].
        let raw_diff = (ra - dec).abs() % 180.0;
        let perpendicularity_error = (raw_diff - 90.0).abs();
        if perpendicularity_error > config.max_calibration_axis_error_deg {
            return Err(format!(
                "Calibration axes look broken: RA angle {:.1}°, Dec angle {:.1}° \
                 — off-perpendicular by {:.1}° (limit {:.1}°). \
                 The guider may have miscalibrated; recalibrate before continuing.",
                ra, dec, perpendicularity_error, config.max_calibration_axis_error_deg
            ));
        }
    }

    Ok(())
}

/// Execute stop guiding - stops PHD2 guiding
pub async fn execute_stop_guiding(
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    tracing::info!("Stopping guiding");

    if let Some(cb) = progress_callback {
        cb(0.0, "Stopping guiding".to_string());
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(50.0, "Sending stop command".to_string());
    }

    match ctx.device_ops.guider_stop().await {
        Ok(_) => {
            // Disarm the GuideStarLost trigger on an intentional stop, so the
            // subsequent is_guiding==false does not get misread as a lost star
            // (which would request recovery for a deliberately-stopped guider).
            if let Some(trigger_state_lock) = &ctx.trigger_state {
                let mut tstate = trigger_state_lock.write().await;
                tstate.set_guiding_enabled(false);
                tstate.set_guide_star_lost(false);
            }
            if let Some(cb) = progress_callback {
                cb(100.0, "Guiding stopped".to_string());
            }
            InstructionResult::success_with_message("Guiding stopped")
        }
        Err(e) => InstructionResult::failure(format!("Failed to stop guiding: {}", e)),
    }
}

// =============================================================================
// FILTER CHANGE INSTRUCTION
// =============================================================================

/// Default timeout for filter wheel change operations (in seconds)
const DEFAULT_FILTER_WHEEL_TIMEOUT_SECS: u64 = 120;

/// Execute filter change
pub async fn execute_filter_change(
    config: &FilterConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let fw_id = match ctx.filterwheel_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Per-filter timeout overrides the global default to accommodate slow
    // wheels (motorized covers, many-position wheels) that legitimately
    // need longer than 120 s; configuring None preserves the safe default.
    // Why (audit-rust §4.3): `timeout_secs: Option<u32>` is the explicit
    // user-override slot — None means "use the documented default".
    let timeout = Duration::from_secs(
        config
            .timeout_secs
            // Why: u32 -> u64 widening is lossless.
            .map(u64::from)
            .unwrap_or(DEFAULT_FILTER_WHEEL_TIMEOUT_SECS),
    );

    tracing::info!(
        "Changing filter to: {} (timeout: {:?})",
        config.filter_name,
        timeout
    );

    if let Some(cb) = progress_callback {
        cb(0.0, format!("Changing to {}", config.filter_name));
    }

    // Index path is preferred over name (see execute_exposure rationale).
    if let Some(index) = config.filter_index {
        match ctx.device_ops.filterwheel_set_position(&fw_id, index).await {
            Ok(_) => {
                if let Some(cb) = progress_callback {
                    cb(30.0, format!("Moving to position {}", index));
                }
                if let Err(e) = wait_for_filterwheel_idle(&fw_id, index, ctx, timeout).await {
                    return InstructionResult::failure(e);
                }
                // Filter-specific focus offsets compensate for the differing
                // optical path length of each filter glass; applying them
                // here keeps the focus point usable for the next exposure
                // without forcing the user to run autofocus after every
                // filter change.
                if let Err(e) =
                    apply_filter_focus_offset(&config.filter_name, ctx, progress_callback).await
                {
                    return InstructionResult::failure(format!(
                        "Focus offset failed for filter \"{}\": {}",
                        config.filter_name, e
                    ));
                }
                if let Some(cb) = progress_callback {
                    cb(100.0, format!("Filter {}", index));
                }
                return InstructionResult::success_with_message(format!(
                    "Changed to filter position: {}",
                    index
                ));
            }
            Err(e) => return InstructionResult::failure(format!("Filter change failed: {}", e)),
        }
    }

    match ctx
        .device_ops
        .filterwheel_set_filter_by_name(&fw_id, &config.filter_name)
        .await
    {
        Ok(pos) => {
            if let Some(cb) = progress_callback {
                cb(30.0, format!("Moving to {}", config.filter_name));
            }
            if let Err(e) = wait_for_filterwheel_idle(&fw_id, pos, ctx, timeout).await {
                return InstructionResult::failure(e);
            }
            if let Err(e) =
                apply_filter_focus_offset(&config.filter_name, ctx, progress_callback).await
            {
                return InstructionResult::failure(format!(
                    "Focus offset failed for filter \"{}\": {}",
                    config.filter_name, e
                ));
            }
            if let Some(cb) = progress_callback {
                cb(100.0, format!("Filter: {}", config.filter_name));
            }
            InstructionResult::success_with_message(format!(
                "Changed to filter: {} (pos {})",
                config.filter_name, pos
            ))
        }
        Err(e) => InstructionResult::failure(format!("Filter change failed: {}", e)),
    }
}

/// Apply the focus offset configured for a given filter after a filter change.
///
/// Looks up the offset in `ctx.filter_focus_offsets` and moves the focuser
/// by that amount relative to its current position. If the offset is zero,
/// no focuser is connected, or no offset is configured, this is a no-op.
/// Errors are logged but do not fail the filter change.
async fn apply_filter_focus_offset(
    filter_name: &str,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> Result<(), String> {
    let focuser_id = match ctx.focuser_id.as_deref() {
        Some(id) if !id.is_empty() => id,
        _ => return Ok(()),
    };

    // Filter focus offsets are stored RELATIVE to the reference filter
    // (offset = optimal_focus[filter] - optimal_focus[reference]); the
    // reference filter and any unconfigured filter have offset 0.
    let offset_new = ctx
        .filter_focus_offsets
        .get(filter_name)
        .copied()
        .unwrap_or(0);

    // The focuser already carries the offset applied for the PREVIOUS filter.
    // Applying `offset_new` as an absolute shift from the current position
    // would stack offsets and walk focus off across an LRGB/SHO night
    // (e.g. L->R = +30, then R->G would land at reference+40 instead of
    // reference+10, and re-selecting a filter would re-add its offset every
    // time). Move by the DELTA between the new offset and the one currently
    // embodied so the focuser always lands at reference_focus + offset_new.
    let last_applied = match &ctx.trigger_state {
        Some(ts) => ts.read().await.last_applied_filter_offset,
        None => 0,
    };
    let delta = offset_new - last_applied;

    if delta == 0 {
        // Already at the correct offset for this filter (re-selecting the same
        // filter, or selecting the reference filter when nothing is applied).
        tracing::debug!(
            "Filter \"{}\": focus offset {} already embodied; no focuser move needed",
            filter_name,
            offset_new
        );
        return Ok(());
    }

    tracing::info!(
        "Applying focus offset for filter \"{}\": embodied {} -> {} ({:+} step delta)",
        filter_name,
        last_applied,
        offset_new,
        delta
    );

    if let Some(cb) = progress_callback {
        cb(60.0, format!("Applying focus offset: {:+} steps", delta));
    }

    let current_pos = match ctx.device_ops.focuser_get_position(focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            return Err(format!("failed to read focuser position: {}", e));
        }
    };

    let target_pos = current_pos + delta;
    tracing::info!(
        "Focus offset: {} + {} = {} (current + delta = target; filter offset {})",
        current_pos,
        delta,
        target_pos,
        offset_new
    );

    if let Err(e) = ctx.device_ops.focuser_move_to(focuser_id, target_pos).await {
        return Err(format!("failed to move focuser: {}", e));
    }

    // 60 polls × 500 ms = 30 s — enough for typical filter-offset moves
    // (which are tens of steps), but short enough that a stuck focuser does
    // not block the next exposure. Real verification of `final_pos ==
    // target_pos` happens after the wait so we catch slow-but-completing
    // moves as well as outright failures.
    let mut reached_target = false;
    for _ in 0..60 {
        sleep(Duration::from_millis(500)).await;
        match ctx.device_ops.focuser_is_moving(focuser_id).await {
            Ok(false) => {
                reached_target = true;
                break;
            }
            Ok(true) => continue,
            Err(e) => {
                return Err(format!("failed while checking focuser movement: {}", e));
            }
        }
    }

    if !reached_target {
        return Err("focuser did not report completion before the timeout window".to_string());
    }

    let final_pos = match ctx.device_ops.focuser_get_position(focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            return Err(format!("failed to verify final focuser position: {}", e));
        }
    };

    if final_pos != target_pos {
        return Err(format!(
            "target focuser position {} but actual position is {}",
            target_pos, final_pos
        ));
    }

    // Record the offset now embodied in the focuser position so the NEXT
    // filter change moves only by the delta (and re-selecting this filter is a
    // no-op). Without this the offsets accumulate across the night.
    if let Some(ts) = &ctx.trigger_state {
        ts.write().await.set_last_applied_filter_offset(offset_new);
    }

    if let Some(cb) = progress_callback {
        cb(
            80.0,
            format!(
                "Focus offset applied: {} -> {} ({:+} steps)",
                current_pos, final_pos, delta
            ),
        );
    }

    tracing::info!(
        "Focus offset for filter \"{}\" applied: {} -> {} (embodied offset now {})",
        filter_name,
        current_pos,
        final_pos,
        offset_new
    );
    Ok(())
}

// =============================================================================
// CAMERA COOLING/WARMING INSTRUCTIONS
// =============================================================================

/// Execute camera cooling
pub async fn execute_cool_camera(
    config: &CoolConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => {
            tracing::error!("CoolCamera failed: No camera connected");
            return e;
        }
    };

    tracing::info!("Cooling camera to {}°C", config.target_temp);

    // Initial temperature anchors the progress percentage: the user sees
    // "30% cooled" as halfway between start and target rather than a raw
    // °C count that means nothing without context.
    let start_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
        Ok(value) => value,
        Err(e) => {
            return InstructionResult::failure(format!("Failed to read camera temperature: {}", e))
        }
    };
    let target_temp = config.target_temp;
    let temp_range = (start_temp - target_temp).abs();

    // 0.5 °C tolerance covers typical cooler noise on TEC-equipped cameras
    // (ZWO/QHY/PlayerOne all report jitter in the ±0.3 °C range when
    // settled); tighter would force a fake "cooling" loop on a camera
    // that is already where we want it.
    let already_at_target = (start_temp - target_temp).abs() < 0.5;

    if let Err(e) = ctx
        .device_ops
        .camera_set_cooler(&camera_id, true, target_temp)
        .await
    {
        return InstructionResult::failure(format!("Failed to enable cooler: {}", e));
    }

    if already_at_target {
        let cooler_power = match ctx.device_ops.camera_get_cooler_power(&camera_id).await {
            Ok(value) => value,
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Failed to read camera cooler power: {}",
                    e
                ))
            }
        };
        let msg = format!(
            "At target: {:.1}°C ({:.0}% power)",
            start_temp, cooler_power
        );
        tracing::info!("Camera already at target temperature: {}", msg);
        if let Some(cb) = progress_callback {
            cb(100.0, msg.clone());
        }
        return InstructionResult::success_with_message(msg);
    }

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Starting: {:.1}°C → {:.1}°C", start_temp, target_temp),
        );
    }

    // If duration specified, wait for cooling
    if let Some(duration_mins) = config.duration_mins {
        // 6 polls per minute = 10 s cadence; fast enough that the UI feels
        // responsive, slow enough that a 20-min cool-down does not flood
        // logs with hundreds of poll lines.
        // Why: duration_mins is user-config f64 minutes (UI-bounded ~0..120);
        // *6.0 in same range. f64 -> u32 saturates per Rust 1.45 spec; negatives
        // clamp to 0 yielding an immediate exit from the cooling loop.
        let steps = (duration_mins * 6.0) as u32;

        for step in 0..steps {
            if let Some(result) = ctx.check_cancelled() {
                return result;
            }

            let current_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
                Ok(value) => value,
                Err(e) => {
                    return InstructionResult::failure(format!(
                        "Failed to read camera temperature during cooling: {}",
                        e
                    ))
                }
            };
            let cooler_power = match ctx.device_ops.camera_get_cooler_power(&camera_id).await {
                Ok(value) => value,
                Err(e) => {
                    return InstructionResult::failure(format!(
                        "Failed to read camera cooler power: {}",
                        e
                    ))
                }
            };

            // Direction-agnostic progress: (current - start) / (target -
            // start). Works for both cooling and warming because both
            // numerator and denominator carry the same sign convention.
            // Clamped to [0, 100] so transient temperature wobbles do not
            // produce nonsensical progress jumps in the UI.
            let temp_progress = if temp_range > 0.1 {
                let raw = (current_temp - start_temp) / (target_temp - start_temp) * 100.0;
                raw.clamp(0.0, 100.0)
            } else {
                100.0
            };

            // Time-based progress is the floor: even if the camera fails
            // to cool, the bar advances toward 100% as the user-configured
            // duration runs out, signalling that the wait is finite.
            // Why: step and steps are u32 bounded by the cooling-loop config
            // (UI-bound minutes * 6); lossless to f64.
            let time_progress = f64::from(step) / f64::from(steps) * 100.0;

            let progress = temp_progress.max(time_progress);

            tracing::debug!(
                "Cooling progress: {:.1}%, current temp: {:.1}°C, power: {:.0}%",
                progress,
                current_temp,
                cooler_power
            );

            if let Some(cb) = progress_callback {
                cb(
                    progress,
                    format!(
                        "Cooling: {:.1}°C → {:.1}°C ({:.0}% power)",
                        current_temp, target_temp, cooler_power
                    ),
                );
            }

            if (current_temp - target_temp).abs() < 0.5 {
                let final_power = match ctx.device_ops.camera_get_cooler_power(&camera_id).await {
                    Ok(value) => value,
                    Err(e) => {
                        return InstructionResult::failure(format!(
                            "Failed to read camera cooler power: {}",
                            e
                        ))
                    }
                };
                let msg = format!(
                    "Target reached: {:.1}°C ({:.0}% power)",
                    current_temp, final_power
                );
                if let Some(cb) = progress_callback {
                    cb(100.0, msg.clone());
                }
                return InstructionResult::success_with_message(msg);
            }

            sleep(Duration::from_secs(10)).await;
        }
    }

    if let Some(cb) = progress_callback {
        cb(100.0, format!("Cooling to {}°C initiated", target_temp));
    }

    InstructionResult::success_with_message(format!("Camera cooling set to {}°C", target_temp))
}

/// Execute camera warming
pub async fn execute_warm_camera(
    config: &WarmConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!("Warming camera at {}°C/min", config.rate_per_min);

    let start_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
        Ok(value) => value,
        Err(e) => {
            return InstructionResult::failure(format!("Failed to read camera temperature: {}", e))
        }
    };
    // Why (audit-rust §4.3): `target_temp: Option<f64>` is a user-override on the
    // WarmCamera instruction; None means "use the conventional ambient-warming default
    // of 20°C", which is the safe shutdown-prep temperature for every cooled-sensor
    // chip in our supported matrix.
    let target_temp = config.target_temp.unwrap_or(20.0);
    let temp_range = target_temp - start_temp;
    let duration_mins = temp_range / config.rate_per_min;
    // Why: duration_mins is a computed temperature ramp; `.max(1.0)` ensures
    // at least one iteration. f64 -> u32 saturates per Rust 1.45 spec.
    let steps = (duration_mins * 6.0).max(1.0) as u32;

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Warming: {:.1}°C → {:.1}°C", start_temp, target_temp),
        );
    }

    for step in 0..steps {
        if let Some(result) = ctx.check_cancelled() {
            // Turn off cooler on cancel
            let _ = ctx
                .device_ops
                .camera_set_cooler(&camera_id, false, 20.0)
                .await;
            return result;
        }

        // Why: step and steps are u32 bounded by the warming-loop config; lossless to f64.
        let progress_temp = start_temp + (temp_range * f64::from(step) / f64::from(steps));
        let progress_percent = (f64::from(step) / f64::from(steps)) * 100.0;

        // Gradually increase target temperature
        if let Err(e) = ctx
            .device_ops
            .camera_set_cooler(&camera_id, true, progress_temp)
            .await
        {
            tracing::warn!("Failed to update cooler target: {}", e);
        }

        // Emit progress
        if let Some(cb) = progress_callback {
            cb(
                progress_percent,
                format!("Warming: {:.1}°C → {:.1}°C", progress_temp, target_temp),
            );
        }

        tracing::debug!("Warming progress: {:.1}°C", progress_temp);
        sleep(Duration::from_secs(10)).await;
    }

    // Turn off cooler
    let _ = ctx
        .device_ops
        .camera_set_cooler(&camera_id, false, 20.0)
        .await;

    // Emit final progress
    if let Some(cb) = progress_callback {
        cb(100.0, "Warmed to ambient".to_string());
    }

    InstructionResult::success_with_message("Camera warmed to ambient")
}

// =============================================================================
// ROTATOR INSTRUCTION
// =============================================================================

/// Execute rotator move
pub async fn execute_rotator_move(
    config: &RotatorConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let rotator_id = match ctx.rotator_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!(
        "Moving rotator to {} (relative: {})",
        config.target_angle,
        config.relative
    );

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, format!("Moving to {:.1}", config.target_angle));
    }

    let result = if config.relative {
        ctx.device_ops
            .rotator_move_relative(&rotator_id, config.target_angle)
            .await
    } else {
        ctx.device_ops
            .rotator_move_to(&rotator_id, config.target_angle)
            .await
    };

    match result {
        Ok(_) => {
            if let Some(cb) = progress_callback {
                cb(100.0, format!("At {:.1}", config.target_angle));
            }
            InstructionResult::success_with_message(format!("Rotator at {}", config.target_angle))
        }
        Err(e) => InstructionResult::failure(format!("Rotator move failed: {}", e)),
    }
}

// =============================================================================
// PARK/UNPARK INSTRUCTIONS
// =============================================================================

/// Execute park
pub async fn execute_park(ctx: &InstructionContext) -> InstructionResult {
    let mount_id = match ctx.mount_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!("Parking mount");

    if let Err(e) = ctx.device_ops.mount_park(&mount_id).await {
        return InstructionResult::failure(format!("Park failed: {}", e));
    }

    // mount_park only ISSUES the park on most drivers (ASCOM/Alpaca/INDI return
    // as soon as the command is acknowledged); a park slew takes 30-90 s.
    // Returning success immediately would let an automated end-of-night
    // shutdown advance to the next step (close dome / cut power) while the OTA
    // is still swinging, and would report success even for a park the driver
    // silently rejected (e.g. CanPark=false). Wait for the mount to report
    // PARKED — the authoritative completion signal across all driver types
    // (mount_is_slewing is unreliable for INDI parking, which uses a separate
    // property) — and fail closed if it never does.
    let park_deadline = tokio::time::Instant::now() + Duration::from_secs(300);
    loop {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }
        match ctx.device_ops.mount_is_parked(&mount_id).await {
            Ok(true) => {
                return InstructionResult::success_with_message("Mount parked");
            }
            Ok(false) => {
                // Still parking.
            }
            Err(e) => {
                tracing::warn!("Park: is_parked read failed ({}); retrying", e);
            }
        }
        if tokio::time::Instant::now() > park_deadline {
            return InstructionResult::failure(
                "Mount did not report parked within 300s of issuing Park. The driver may not \
                 support Park (CanPark=false), the park was rejected, or the mount is stuck \
                 mid-slew — NOT safe to assume parked."
                    .to_string(),
            );
        }
        sleep(Duration::from_millis(500)).await;
    }
}

/// Execute unpark
pub async fn execute_unpark(ctx: &InstructionContext) -> InstructionResult {
    let mount_id = match ctx.mount_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!("Unparking mount");

    match ctx.device_ops.mount_unpark(&mount_id).await {
        Ok(_) => InstructionResult::success_with_message("Mount unparked"),
        Err(e) => InstructionResult::failure(format!("Unpark failed: {}", e)),
    }
}

// =============================================================================
// POLAR ALIGNMENT INSTRUCTION
// =============================================================================

/// Execute polar alignment
pub async fn execute_polar_alignment(
    config: &PolarAlignConfig,
    ctx: &InstructionContext,
    status_callback: impl Fn(String, Option<f64>) + Send + Sync,
    image_callback: impl Fn(crate::polar_align::PolarAlignmentImageData) + Send + Sync,
) -> InstructionResult {
    crate::polar_align::perform_polar_alignment(config, ctx, status_callback, image_callback).await
}

// =============================================================================
// WAIT TIME INSTRUCTION
// =============================================================================

/// Execute wait for time
pub async fn execute_wait_time(
    config: &WaitTimeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    // Wait until specific time
    if let Some(until) = config.wait_until {
        let now = chrono::Utc::now().timestamp();
        if now < until {
            // Why: `now < until` is checked above, so `until - now` is positive
            // i64 (no two-complement wrap risk). i64 -> u64 is then lossless for
            // any positive value.
            let total_wait_secs = u64::try_from(until - now).unwrap_or(0);
            let wait_until_str = chrono::DateTime::from_timestamp(until, 0)
                .map(|dt| dt.format("%H:%M:%S").to_string())
                // Why (audit-rust §4.3): `from_timestamp` only fails for out-of-range
                // i64 seconds (year ±5_400_000); user input here is bounded by the UI
                // datetime picker. Raw epoch seconds as the display fallback preserves
                // log traceability if a hypothetical extreme value sneaks in.
                .unwrap_or_else(|| until.to_string());

            tracing::info!(
                "Waiting until {} ({} seconds)",
                wait_until_str,
                total_wait_secs
            );

            // Emit initial progress
            if let Some(cb) = progress_callback {
                cb(0.0, format!("Waiting until {}", wait_until_str));
            }

            // Wait in 1-second increments to allow cancellation
            for elapsed in 0..total_wait_secs {
                if let Some(result) = ctx.check_cancelled() {
                    return result;
                }

                // Emit progress every 10 seconds
                if elapsed % 10 == 0 {
                    // Why: u64 -> f64. Wait durations under ~285k years fit
                    // losslessly in f64's 53-bit mantissa.
                    let progress = (elapsed as f64 / total_wait_secs as f64) * 100.0;
                    let remaining = total_wait_secs - elapsed;
                    if let Some(cb) = progress_callback {
                        cb(progress, format!("{}s remaining", remaining));
                    }
                }

                sleep(Duration::from_secs(1)).await;
            }

            if let Some(cb) = progress_callback {
                cb(100.0, "Target time reached".to_string());
            }
        }
        return InstructionResult::success_with_message("Wait time reached");
    }

    // Wait for twilight
    if let Some(twilight) = &config.wait_for_twilight {
        tracing::info!("Waiting for {:?} twilight", twilight);

        // Calculate twilight time based on observer location
        let observer_location = match (ctx.latitude, ctx.longitude) {
            (Some(lat), Some(lon)) => Some((lat, lon)),
            _ => ctx.device_ops.get_observer_location(),
        };
        let (lat, lon) = match observer_location {
            Some(loc) => loc,
            None => {
                return InstructionResult::failure(
                    "Cannot evaluate twilight trigger: observer location is unavailable. Set site latitude/longitude in settings.",
                );
            }
        };
        let twilight_time = calculate_twilight_time(lat, lon, twilight);

        let now = chrono::Utc::now().timestamp();
        if twilight_time == i64::MAX {
            return InstructionResult::failure(format!(
                "{:?} twilight does not occur at latitude {:.3} and longitude {:.3} for the current date. \
Sequence cannot wait for an unreachable twilight state.",
                twilight, lat, lon
            ));
        }
        if now < twilight_time {
            // Why: `now < twilight_time` is checked above, so the difference is
            // positive i64. i64 -> u64 is then lossless via try_from.
            let total_wait_secs = u64::try_from(twilight_time - now).unwrap_or(0);
            tracing::info!(
                "Waiting {} seconds for {:?} twilight",
                total_wait_secs,
                twilight
            );

            // Emit initial progress
            if let Some(cb) = progress_callback {
                cb(0.0, format!("Waiting for {:?} twilight", twilight));
            }

            for elapsed in 0..total_wait_secs {
                if let Some(result) = ctx.check_cancelled() {
                    return result;
                }

                // Emit progress every 30 seconds
                if elapsed % 30 == 0 {
                    // Why: u64 -> f64. Twilight wait durations (~hours) fit
                    // losslessly in f64's 53-bit mantissa.
                    let progress = (elapsed as f64 / total_wait_secs as f64) * 100.0;
                    let remaining_mins = (total_wait_secs - elapsed) / 60;
                    if let Some(cb) = progress_callback {
                        cb(
                            progress,
                            format!("{:?}: {}m remaining", twilight, remaining_mins),
                        );
                    }
                }

                sleep(Duration::from_secs(1)).await;
            }

            if let Some(cb) = progress_callback {
                cb(100.0, format!("{:?} twilight reached", twilight));
            }
        }

        return InstructionResult::success_with_message(format!("{:?} twilight reached", twilight));
    }

    InstructionResult::success()
}

/// Calculate twilight time for a given location using proper solar position algorithms
fn calculate_twilight_time(latitude: f64, longitude: f64, twilight_type: &TwilightType) -> i64 {
    // Sun altitude threshold for each twilight type (degrees below horizon)
    let altitude_threshold: f64 = match twilight_type {
        TwilightType::Civil => -6.0,
        TwilightType::Nautical => -12.0,
        TwilightType::Astronomical => -18.0,
    };

    let now = chrono::Utc::now();
    let today = now.date_naive();

    // Calculate Julian Day. Audit §1.6: reuse `crate::meridian::julian_day`
    // instead of the previous local duplicate.
    let jd = crate::meridian::julian_day(&now);

    // Calculate solar position
    let (solar_dec, equation_of_time) = calculate_solar_position(jd);

    // Convert to radians
    let lat_rad = latitude.to_radians();
    let dec_rad = solar_dec.to_radians();
    let alt_rad = altitude_threshold.to_radians();

    // Calculate hour angle when sun is at the given altitude
    // cos(H) = (sin(alt) - sin(lat) * sin(dec)) / (cos(lat) * cos(dec))
    let cos_h = (alt_rad.sin() - lat_rad.sin() * dec_rad.sin()) / (lat_rad.cos() * dec_rad.cos());

    // Polar handling: avoid fabricated fallback times.
    if cos_h > 1.0 {
        // Sun never reaches this altitude threshold today (e.g. polar day).
        return i64::MAX;
    }
    if cos_h < -1.0 {
        // Sun is already below this threshold all day (e.g. polar night).
        return now.timestamp();
    }

    let hour_angle = cos_h.acos().to_degrees();

    // Calculate local solar noon
    let solar_noon_utc = 12.0 - longitude / 15.0 - equation_of_time / 60.0;

    // Evening twilight occurs when sun sets past the altitude threshold
    // Time after solar noon when sun reaches threshold
    let hours_after_noon = hour_angle / 15.0;
    let twilight_hour_utc = solar_noon_utc + hours_after_noon;

    // Convert to timestamp
    let twilight_hour = twilight_hour_utc.rem_euclid(24.0);
    // Why: twilight_hour is bounded by rem_euclid(24.0) above; .fract()*60.0 is
    // in [0, 60). f64 -> u32 saturates per Rust 1.45 spec.
    let twilight_minutes = (twilight_hour.fract() * 60.0) as u32;
    let twilight_hour = twilight_hour as u32;

    let twilight_datetime =
        build_utc_naive_time_or_fallback(today, twilight_hour, twilight_minutes, (23, 59, 0));

    let twilight_timestamp =
        chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(twilight_datetime, chrono::Utc)
            .timestamp();

    // If the calculated twilight is in the past, it's tomorrow's twilight
    if twilight_timestamp < now.timestamp() {
        return twilight_timestamp + 86400; // Add 24 hours
    }

    twilight_timestamp
}

// Audit §1.6: the local `calculate_julian_day` was deleted; use
// `crate::meridian::julian_day(&dt)` — same formula, single source of truth.

fn build_utc_naive_time_or_fallback(
    date: NaiveDate,
    hour: u32,
    minute: u32,
    fallback: (u32, u32, u32),
) -> chrono::NaiveDateTime {
    // Why (audit-rust §4.3): `and_hms_opt` only returns None for invalid (h,m,s) tuples
    // (h>=24, m>=60, s>=60). The caller passes solar-calculation results that may
    // saturate at exactly 24:00:00 in edge equation-of-time cases — `fallback` is the
    // tuple from the documented sunset-convention default. If both fail (impossible
    // unless `fallback` itself is invalid), midnight is the safe last-resort
    // representable time for the same calendar date.
    date.and_hms_opt(hour, minute, 0)
        .or_else(|| date.and_hms_opt(fallback.0, fallback.1, fallback.2))
        .unwrap_or_else(|| date.and_time(chrono::NaiveTime::MIN))
}

/// Calculate solar declination and equation of time
/// Returns (declination in degrees, equation of time in minutes)
fn calculate_solar_position(jd: f64) -> (f64, f64) {
    // Days since J2000.0
    let n = jd - 2451545.0;

    // Mean longitude of the sun (degrees)
    let l = (280.460 + 0.9856474 * n) % 360.0;

    // Mean anomaly of the sun (degrees)
    let g = (357.528 + 0.9856003 * n) % 360.0;
    let g_rad = g.to_radians();

    // Ecliptic longitude of the sun (degrees)
    let lambda = l + 1.915 * g_rad.sin() + 0.020 * (2.0 * g_rad).sin();
    let lambda_rad = lambda.to_radians();

    // Obliquity of the ecliptic (degrees)
    let epsilon = 23.439 - 0.0000004 * n;
    let epsilon_rad = epsilon.to_radians();

    // Solar declination
    let declination = (epsilon_rad.sin() * lambda_rad.sin()).asin().to_degrees();

    // Equation of time (minutes)
    // Simplified formula
    let y = (epsilon_rad / 2.0).tan().powi(2);
    let l_rad = l.to_radians();
    let eot = 4.0
        * (y * (2.0 * l_rad).sin() - 2.0 * 0.0167 * g_rad.sin()
            + 4.0 * 0.0167 * y * g_rad.sin() * (2.0 * l_rad).cos()
            - 0.5 * y * y * (4.0 * l_rad).sin()
            - 1.25 * 0.0167 * 0.0167 * (2.0 * g_rad).sin())
        .to_degrees();

    (declination, eot)
}

// =============================================================================
// DELAY INSTRUCTION
// =============================================================================

/// Execute delay
pub async fn execute_delay(
    config: &DelayConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    tracing::info!("Delaying for {:.1} seconds", config.seconds);

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, format!("{:.0}s delay", config.seconds));
    }

    // Why: config.seconds is f64 user-config delay (UI-bounded). f64 -> u64
    // saturates per Rust 1.45 spec; negatives clamp to 0 yielding no-wait.
    let total_steps = (config.seconds * 10.0) as u64;
    for step in 0..total_steps {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }

        // Emit progress every second (10 steps)
        if step % 10 == 0 {
            // Why: u64 step -> f64 lossless under any plausible delay length
            // (years of seconds fit in 53-bit mantissa).
            let elapsed_secs = step as f64 / 10.0;
            let remaining_secs = config.seconds - elapsed_secs;
            let progress = (elapsed_secs / config.seconds) * 100.0;
            if let Some(cb) = progress_callback {
                cb(progress, format!("{:.0}s remaining", remaining_secs));
            }
        }

        sleep(Duration::from_millis(100)).await;
    }

    if let Some(cb) = progress_callback {
        cb(100.0, "Delay complete".to_string());
    }

    InstructionResult::success_with_message(format!("Delayed {:.1} seconds", config.seconds))
}

// =============================================================================
// NOTIFICATION INSTRUCTION
// =============================================================================

/// Execute notification
pub async fn execute_notification(
    config: &NotificationConfig,
    ctx: &InstructionContext,
) -> InstructionResult {
    let level = match config.level {
        NotificationLevel::Info => "info",
        NotificationLevel::Warning => "warning",
        NotificationLevel::Error => "error",
        NotificationLevel::Success => "success",
    };

    tracing::info!(
        "[{}] {}: {}",
        level.to_uppercase(),
        config.title,
        config.message
    );

    if let Err(e) = ctx
        .device_ops
        .send_notification(
            level,
            &config.title,
            &config.message,
            config.explicit_transports.as_deref(),
        )
        .await
    {
        tracing::warn!("Failed to send notification: {}", e);
    }

    InstructionResult::success()
}

// =============================================================================
// SCRIPT INSTRUCTION
// =============================================================================

/// Execute script. Wave 4 expanded the env-var contract: every variable
/// declared in `expressions::catalog` is exposed as `NIGHTSHADE_<NAME>`
/// where `NAME` is the dotted variable converted to UPPER_SNAKE
/// (e.g. `target.alt` → `NIGHTSHADE_TARGET_ALT`). Variables that fail to
/// resolve are simply omitted (a missing env var is a normal "no data"
/// signal to a shell script, unlike a `${...}` template inside an
/// argument which is a hard failure).
pub async fn execute_script(
    config: &ScriptConfig,
    ctx: &InstructionContext,
    exec_ctx: &crate::node::context::ExecutionContext,
    frame: &crate::expressions::EvaluationFrame,
) -> InstructionResult {
    tracing::info!(
        "Running script: {} {:?}",
        config.script_path,
        config.arguments
    );

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Build the command
    let mut cmd = tokio::process::Command::new(&config.script_path);
    cmd.args(&config.arguments);

    // Expose every catalog variable as an env var. Anything that does not
    // resolve (e.g. `target.alt` without an observer location) is silently
    // skipped — the script can detect missing data via `env -u` semantics.
    // We deliberately do NOT propagate InterpolationError here: an env-var
    // contract is "this MAY be present", whereas an argument template's
    // contract is "this MUST resolve".
    for entry in crate::expressions::variable_catalog() {
        if let Ok(value) = crate::expressions::resolve_variable(entry.name, 0, exec_ctx, frame) {
            let env_name = format!(
                "NIGHTSHADE_{}",
                crate::expressions::catalog_name_to_env(entry.name)
            );
            cmd.env(
                env_name,
                crate::expressions::format_variable_for_env(&value),
            );
        }
    }

    // Set timeout
    let timeout = match config.timeout_secs {
        // Why: u32 -> u64 widening is lossless.
        Some(v) if v > 0 => u64::from(v),
        Some(_) => {
            return InstructionResult::failure(
                "Script timeout_secs must be greater than zero".to_string(),
            )
        }
        None => {
            return InstructionResult::failure(
                "Script timeout_secs is required in fail-closed mode".to_string(),
            )
        }
    };

    // Run the script with timeout
    let result = tokio::time::timeout(Duration::from_secs(timeout), cmd.output()).await;

    match result {
        Ok(Ok(output)) => {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                tracing::info!("Script output: {}", stdout);
                InstructionResult {
                    status: NodeStatus::Success,
                    message: Some(format!("Script {} completed", config.script_path)),
                    data: Some(serde_json::json!({
                        "stdout": stdout.to_string(),
                        "stderr": String::from_utf8_lossy(&output.stderr).to_string(),
                        "exit_code": output.status.code(),
                    })),
                    hfr_values: Vec::new(),
                }
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                InstructionResult::failure(format!("Script failed: {}", stderr))
            }
        }
        Ok(Err(e)) => InstructionResult::failure(format!("Failed to run script: {}", e)),
        Err(_) => InstructionResult::failure(format!("Script timed out after {} seconds", timeout)),
    }
}

// =============================================================================
// MERIDIAN FLIP INSTRUCTION
// =============================================================================

/// Execute a meridian flip via the canonical [`MeridianFlipExecutor`].
///
/// Audit §1.6: this used to be a 394-line second implementation that diverged
/// from the executor on timeouts, post-flip altitude check, autofocus
/// parameters, settle behaviour, plate-solve failure handling, pier-side
/// telemetry fallback, and abort-during-flip semantics. The single-source-
/// of-truth executor lives in `crate::meridian_flip_executor`. This wrapper
/// builds a [`FlipContext`] from the instruction context and calls
/// `executor.execute()`. The cancellation token, the trigger-state flip
/// bookkeeping, the cover-state pre-check (audit §1.19), and the
/// configurable autofocus parameters all flow through the FlipContext.
pub async fn execute_meridian_flip(
    config: &MeridianFlipConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    // Surface a "starting" progress immediately so UI shows activity even
    // before the executor begins emitting its own events. The executor uses
    // its event channel for granular per-step progress so we do not wire
    // through that channel here — the explicit instruction node has its own
    // progress reporter (the callback we received) and a brief
    // 0%/100% bracket is sufficient.
    if let Some(cb) = progress_callback {
        cb(0.0, "Starting meridian flip".to_string());
    }

    let mount_id = match ctx.mount_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    let target_ra = match ctx.target_ra {
        Some(ra) => ra,
        None => return InstructionResult::failure("No target RA available for meridian flip"),
    };

    let target_dec = match ctx.target_dec {
        Some(dec) => dec,
        None => {
            return InstructionResult::failure("No target declination available for meridian flip")
        }
    };

    // Why (audit-rust §4.3): target name is a display/log label for meridian-flip
    // status events; the load-bearing inputs (target_ra, target_dec) are already
    // validated as Some above and return failure when missing. "Unknown" is the
    // documented UI fallback when the user starts a sequence without a named target.
    let target_name = ctx
        .target_name
        .clone()
        .unwrap_or_else(|| "Unknown".to_string());

    // Pre-flight: do not invoke the executor when no flip is actually needed
    // — its altitude/cover/pier-side preflight assume the flip is required
    // and would otherwise emit confusing "Aborted" events for routine
    // pre-meridian sequence runs.
    let (_lat, lon) = match ctx.device_ops.get_observer_location() {
        Some((lat, lon)) => (lat, lon),
        None => {
            return InstructionResult::failure(
                "Observer location not configured. Meridian flip requires location for calculations."
            );
        }
    };

    let now = chrono::Utc::now();
    let should_flip =
        crate::meridian::should_flip_now(target_ra, lon, now, config.minutes_past_meridian);
    if !should_flip {
        let ha = crate::meridian::hour_angle(
            target_ra,
            crate::meridian::local_sidereal_time(crate::meridian::julian_day(&now), lon),
        );
        tracing::info!(
            "Meridian flip not yet required (HA={:.4}h, threshold={:.2} min)",
            ha,
            config.minutes_past_meridian
        );
        if let Some(cb) = progress_callback {
            cb(100.0, "Flip not yet required".to_string());
        }
        return InstructionResult::success_with_message("Meridian flip not yet required");
    }

    let flip_ctx = crate::meridian_flip_executor::FlipContext {
        target_name,
        target_ra_hours: target_ra,
        target_dec_degrees: target_dec,
        mount_id,
        camera_id: ctx.camera_id.clone(),
        focuser_id: ctx.focuser_id.clone(),
        cover_calibrator_id: ctx.cover_calibrator_id.clone(),
        cancellation_token: Some(ctx.cancellation_token.clone()),
        trigger_state: ctx.trigger_state.clone(),
        // §1.6 backport: post-flip refocus pulls user-tuned autofocus
        // parameters from the equipment profile rather than the executor's
        // hardcoded constants. The instruction-side has no profile reference
        // here; pass None and let the executor fall back to
        // AutofocusConfig::default() (which reflects the user's
        // serde-default values).
        autofocus_config: None,
    };

    let mut flip_executor = crate::meridian_flip_executor::MeridianFlipExecutor::new(
        config.clone(),
        ctx.device_ops.clone(),
    );
    // Wave 1.5 Pack A: forward the live executor event channel so the
    // post-flip refocus emits its instruction-level failures to UI
    // subscribers (FITS-save errors during the test exposure, etc.).
    // When the instruction runs outside a live executor (unit tests),
    // ctx.event_tx is None and the chain remains silent.
    if let Some(event_tx) = ctx.event_tx.clone() {
        flip_executor = flip_executor.with_executor_event_tx(event_tx);
    }

    match flip_executor.execute(&flip_ctx).await {
        crate::meridian_flip_executor::FlipResult::Success {
            new_pier_side,
            duration_secs,
        } => {
            tracing::info!(
                "Meridian flip complete (pier side: {:?}, took {:.1}s)",
                new_pier_side,
                duration_secs
            );
            if let Some(cb) = progress_callback {
                cb(100.0, "Flip complete".to_string());
            }
            // §1.6: mark_flip_performed is invoked inside the executor on
            // success when trigger_state is supplied; the instruction-path
            // populates trigger_state via the FlipContext above so the same
            // bookkeeping happens regardless of caller.
            InstructionResult::success_with_message(format!(
                "Meridian flip completed successfully (pier side: {:?})",
                new_pier_side
            ))
        }
        crate::meridian_flip_executor::FlipResult::Failed {
            error,
            action_taken,
        } => InstructionResult::failure_with_recovery(
            format!(
                "Meridian flip failed: {} (action taken: {:?})",
                error, action_taken
            ),
            "FLIP_FAILED",
        ),
        crate::meridian_flip_executor::FlipResult::Aborted { reason } => {
            InstructionResult::cancelled(reason)
        }
    }
}

// =============================================================================
// DOME INSTRUCTIONS
// =============================================================================

/// Execute open dome
pub async fn execute_open_dome(
    config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let dome_id = match ctx.dome_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Opening dome shutter".to_string());
    }

    tracing::info!("Opening dome shutter...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for shutter to open".to_string());
    }

    if let Err(e) = ctx.device_ops.dome_open(&dome_id).await {
        return InstructionResult::failure(format!("Failed to open dome: {}", e));
    }

    if !config.shutter_only {
        // DeviceOps does not currently expose dome_unpark.
        // Operators must ensure dome park state is compatible with opening.
    }

    // Report completion
    if let Some(cb) = progress_callback {
        cb(100.0, "Dome shutter open".to_string());
    }

    InstructionResult::success_with_message("Dome shutter opened")
}

/// Execute close dome
pub async fn execute_close_dome(
    _config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let dome_id = match ctx.dome_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Closing dome shutter".to_string());
    }

    tracing::info!("Closing dome shutter...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for shutter to close".to_string());
    }

    if let Err(e) = ctx.device_ops.dome_close(&dome_id).await {
        return InstructionResult::failure(format!("Failed to close dome: {}", e));
    }

    // Report completion
    if let Some(cb) = progress_callback {
        cb(100.0, "Dome shutter closed".to_string());
    }

    InstructionResult::success_with_message("Dome shutter closed")
}

/// Execute park dome
pub async fn execute_park_dome(
    config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let dome_id = match ctx.dome_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Parking dome".to_string());
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if !config.shutter_only {
        // Report waiting progress BEFORE the async call
        if let Some(cb) = progress_callback {
            cb(50.0, "Waiting for dome to reach park position".to_string());
        }

        tracing::info!("Parking dome...");
        if let Err(e) = ctx.device_ops.dome_park(&dome_id).await {
            return InstructionResult::failure(format!("Failed to park dome: {}", e));
        }
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Usually parking involves closing shutter too
    tracing::info!("Closing shutter (park sequence)...");
    let _ = ctx.device_ops.dome_close(&dome_id).await;

    // Report completion
    if let Some(cb) = progress_callback {
        cb(100.0, "Dome parked".to_string());
    }

    InstructionResult::success_with_message("Dome parked")
}

// =============================================================================
// MOSAIC INSTRUCTION
// =============================================================================

/// Execute mosaic panel iteration. Delegates to [`crate::mosaic::run_mosaic_wizard`]
/// which drives a [`crate::wizard::Wizard`] for per-panel checkpoint
/// support. Behavior is byte-identical to the pre-refactor monolithic
/// implementation.
pub async fn execute_mosaic(
    config: &crate::MosaicConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    crate::mosaic::run_mosaic_wizard(config, ctx, progress_callback).await
}

// =============================================================================
// COVER CALIBRATOR (FLAT PANEL / DUST COVER) INSTRUCTIONS
// =============================================================================

/// Execute open cover (unpark dust cap)
pub async fn execute_open_cover(
    config: &crate::CoverCalibratorConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let device_id = match ctx.cover_calibrator_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Opening cover".to_string());
    }

    tracing::info!("Opening cover...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for cover to open".to_string());
    }

    // Start opening the cover
    if let Err(e) = ctx.device_ops.cover_calibrator_open_cover(&device_id).await {
        return InstructionResult::failure(format!("Failed to open cover: {}", e));
    }

    // Wait for cover to reach open state with timeout
    // Why: u32 timeout_secs -> u64 widening is lossless.
    let timeout = Duration::from_secs(u64::from(config.timeout_secs));
    match wait_for_cover_state(&device_id, 3, ctx, timeout).await {
        Ok(_) => {
            // Report completion
            if let Some(cb) = progress_callback {
                cb(100.0, "Cover open".to_string());
            }
            InstructionResult::success_with_message("Cover opened")
        }
        Err(e) => InstructionResult::failure(e),
    }
}

/// Execute close cover (park dust cap)
pub async fn execute_close_cover(
    config: &crate::CoverCalibratorConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let device_id = match ctx.cover_calibrator_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Closing cover".to_string());
    }

    tracing::info!("Closing cover...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for cover to close".to_string());
    }

    // Start closing the cover
    if let Err(e) = ctx
        .device_ops
        .cover_calibrator_close_cover(&device_id)
        .await
    {
        return InstructionResult::failure(format!("Failed to close cover: {}", e));
    }

    // Wait for cover to reach closed state with timeout
    // Why: u32 timeout_secs -> u64 widening is lossless.
    let timeout = Duration::from_secs(u64::from(config.timeout_secs));
    match wait_for_cover_state(&device_id, 1, ctx, timeout).await {
        Ok(_) => {
            // Report completion
            if let Some(cb) = progress_callback {
                cb(100.0, "Cover closed".to_string());
            }
            InstructionResult::success_with_message("Cover closed")
        }
        Err(e) => InstructionResult::failure(e),
    }
}

/// Execute calibrator on (turn on flat panel light)
pub async fn execute_calibrator_on(
    config: &crate::CalibratorOnConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let device_id = match ctx.cover_calibrator_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Turning on calibrator".to_string());
    }

    tracing::info!(
        "Turning calibrator on at brightness {}...",
        config.brightness
    );

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(
            50.0,
            format!("Adjusting brightness to {}%", config.brightness),
        );
    }

    // Turn on the calibrator at specified brightness
    if let Err(e) = ctx
        .device_ops
        .cover_calibrator_calibrator_on(&device_id, config.brightness)
        .await
    {
        return InstructionResult::failure(format!("Failed to turn on calibrator: {}", e));
    }

    // Wait for calibrator to reach ready state with timeout
    // Why: u32 timeout_secs -> u64 widening is lossless.
    let timeout = Duration::from_secs(u64::from(config.timeout_secs));
    match wait_for_calibrator_state(&device_id, 3, ctx, timeout).await {
        Ok(_) => {
            // Verify brightness is set correctly
            // Why (audit-rust §4.3): post-set verification readback; an Err here would mean
            // the driver dropped the cover-calibrator session between SetBrightness and
            // GetBrightness — falling back to the requested value `config.brightness`
            // simply trusts the SetBrightness call that already returned success above
            // (it propagated via `?`). The successful "wait for state 3" check
            // (`wait_for_calibrator_state`) is the load-bearing readiness signal.
            let actual_brightness = ctx
                .device_ops
                .cover_calibrator_get_brightness(&device_id)
                .await
                .unwrap_or(config.brightness);
            // Report completion
            if let Some(cb) = progress_callback {
                cb(
                    100.0,
                    format!("Calibrator on at brightness {}", actual_brightness),
                );
            }
            InstructionResult::success_with_message(format!(
                "Calibrator on at brightness {}",
                actual_brightness
            ))
        }
        Err(e) => InstructionResult::failure(e),
    }
}

/// Execute calibrator off (turn off flat panel light)
pub async fn execute_calibrator_off(
    config: &crate::CoverCalibratorConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let device_id = match ctx.cover_calibrator_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Turning off calibrator".to_string());
    }

    tracing::info!("Turning calibrator off...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for calibrator to turn off".to_string());
    }

    // Turn off the calibrator
    if let Err(e) = ctx
        .device_ops
        .cover_calibrator_calibrator_off(&device_id)
        .await
    {
        return InstructionResult::failure(format!("Failed to turn off calibrator: {}", e));
    }

    // Wait for calibrator to reach off state with timeout
    // Why: u32 timeout_secs -> u64 widening is lossless.
    let timeout = Duration::from_secs(u64::from(config.timeout_secs));
    match wait_for_calibrator_state(&device_id, 1, ctx, timeout).await {
        Ok(_) => {
            // Report completion
            if let Some(cb) = progress_callback {
                cb(100.0, "Calibrator off".to_string());
            }
            InstructionResult::success_with_message("Calibrator off")
        }
        Err(e) => InstructionResult::failure(e),
    }
}

/// Wait for cover to reach target state with timeout
/// States: 0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error
async fn wait_for_cover_state(
    device_id: &str,
    target_state: i32,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    let state_name = match target_state {
        0 => "NotPresent",
        1 => "Closed",
        2 => "Moving",
        3 => "Open",
        4 => "Unknown",
        5 => "Error",
        _ => "Unknown",
    };

    loop {
        // Check cancellation
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            // Try to halt cover movement
            let _ = ctx.device_ops.cover_calibrator_halt_cover(device_id).await;
            return Err("Operation cancelled".to_string());
        }

        // Check current state
        match ctx
            .device_ops
            .cover_calibrator_get_cover_state(device_id)
            .await
        {
            Ok(state) => {
                if state == target_state {
                    tracing::debug!("Cover reached {} state", state_name);
                    return Ok(());
                }
                if state == 5 {
                    return Err("Cover reported error state".to_string());
                }
                tracing::trace!("Cover state: {}, waiting for {}", state, state_name);
            }
            Err(e) => {
                tracing::warn!("Error checking cover state: {}", e);
                // Continue polling - transient error
            }
        }

        // Check timeout
        if start.elapsed() > timeout {
            return Err(format!(
                "Cover did not reach {} state within {} seconds",
                state_name,
                timeout.as_secs()
            ));
        }

        // Poll every 500ms
        sleep(Duration::from_millis(500)).await;
    }
}

/// Wait for calibrator to reach target state with timeout
/// States: 0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error
async fn wait_for_calibrator_state(
    device_id: &str,
    target_state: i32,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    let state_name = match target_state {
        0 => "NotPresent",
        1 => "Off",
        2 => "NotReady",
        3 => "Ready",
        4 => "Unknown",
        5 => "Error",
        _ => "Unknown",
    };

    loop {
        // Check cancellation
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            let _ = ctx
                .device_ops
                .cover_calibrator_calibrator_off(device_id)
                .await;
            let _ = ctx.device_ops.cover_calibrator_halt_cover(device_id).await;
            return Err("Operation cancelled".to_string());
        }

        // Check current state
        match ctx
            .device_ops
            .cover_calibrator_get_calibrator_state(device_id)
            .await
        {
            Ok(state) => {
                if state == target_state {
                    tracing::debug!("Calibrator reached {} state", state_name);
                    return Ok(());
                }
                if state == 5 {
                    return Err("Calibrator reported error state".to_string());
                }
                tracing::trace!("Calibrator state: {}, waiting for {}", state, state_name);
            }
            Err(e) => {
                tracing::warn!("Error checking calibrator state: {}", e);
                // Continue polling - transient error
            }
        }

        // Check timeout
        if start.elapsed() > timeout {
            let _ = ctx.device_ops.cover_calibrator_halt_cover(device_id).await;
            return Err(format!(
                "Calibrator did not reach {} state within {} seconds",
                state_name,
                timeout.as_secs()
            ));
        }

        // Poll every 200ms (calibrator state can change quickly)
        sleep(Duration::from_millis(200)).await;
    }
}

// =============================================================================
// TESTS
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_ra_diff_hours_no_wrap() {
        // Simple cases with no wraparound
        assert!((normalize_ra_diff_hours(1.0) - 1.0).abs() < 0.0001);
        assert!((normalize_ra_diff_hours(-1.0) - (-1.0)).abs() < 0.0001);
        assert!((normalize_ra_diff_hours(11.0) - 11.0).abs() < 0.0001);
        assert!((normalize_ra_diff_hours(-11.0) - (-11.0)).abs() < 0.0001);
    }

    #[test]
    fn test_normalize_ra_diff_hours_wraparound() {
        // Wraparound cases: 23h to 1h should be 2h diff, not 22h
        assert!((normalize_ra_diff_hours(22.0) - (-2.0)).abs() < 0.0001);
        assert!((normalize_ra_diff_hours(-22.0) - 2.0).abs() < 0.0001);

        // 13 hours should wrap to -11 hours (shorter path)
        assert!((normalize_ra_diff_hours(13.0) - (-11.0)).abs() < 0.0001);
        assert!((normalize_ra_diff_hours(-13.0) - 11.0).abs() < 0.0001);

        // Edge case: exactly 12 hours
        assert!((normalize_ra_diff_hours(12.0).abs() - 12.0).abs() < 0.0001);
    }

    #[test]
    fn test_validate_slew_position_success() {
        // Exact match
        assert!(validate_slew_position(12.0, 45.0, 12.0, 45.0, 1.0 / 60.0).is_ok());

        // Within tolerance (less than 1 arcminute = 1/60 degree)
        let small_diff = 0.5 / 60.0; // 0.5 arcminute
        let ra_diff_hours = small_diff / 15.0; // Convert degrees to hours
        assert!(validate_slew_position(
            12.0,
            45.0,
            12.0 + ra_diff_hours,
            45.0 + small_diff,
            1.0 / 60.0
        )
        .is_ok());
    }

    #[test]
    fn test_validate_slew_position_ra_failure() {
        // RA exceeds tolerance (2 arcminutes when tolerance is 1)
        let large_diff_hours = (2.0 / 60.0) / 15.0; // 2 arcminutes in hours
        let result = validate_slew_position(12.0, 45.0, 12.0 + large_diff_hours, 45.0, 1.0 / 60.0);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("did not reach target"));
    }

    #[test]
    fn test_validate_slew_position_dec_failure() {
        // Dec exceeds tolerance
        let large_diff_deg = 2.0 / 60.0; // 2 arcminutes
        let result = validate_slew_position(12.0, 45.0, 12.0, 45.0 + large_diff_deg, 1.0 / 60.0);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("did not reach target"));
    }

    #[test]
    fn test_validate_slew_position_ra_wraparound() {
        // Test RA wraparound: target at 0.1h, actual at 23.9h should be 0.2h diff = 3 degrees
        // This is well within tolerance (we'll use a generous tolerance for this test)
        let tolerance = 5.0; // 5 degrees
        assert!(validate_slew_position(0.1, 45.0, 23.9, 45.0, tolerance).is_ok());

        // With 1 arcminute tolerance, 0.2h = 3 degrees should fail
        let result = validate_slew_position(0.1, 45.0, 23.9, 45.0, 1.0 / 60.0);
        assert!(result.is_err());
    }

    // -------------------------------------------------------------------
    // P3-7: post-start calibration quality validation
    // -------------------------------------------------------------------

    fn _cfg() -> StartGuidingConfig {
        StartGuidingConfig::default()
    }

    #[test]
    fn validate_calibration_rejects_uncalibrated_guider() {
        let calib = crate::GuidingCalibration {
            is_calibrated: false,
            ra_angle_deg: Some(0.0),
            dec_angle_deg: Some(90.0),
        };
        let result = validate_calibration_quality(&calib, &_cfg());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not calibrated"));
    }

    #[test]
    fn validate_calibration_accepts_perpendicular_axes() {
        let calib = crate::GuidingCalibration {
            is_calibrated: true,
            ra_angle_deg: Some(0.0),
            dec_angle_deg: Some(90.0),
        };
        assert!(validate_calibration_quality(&calib, &_cfg()).is_ok());
    }

    #[test]
    fn validate_calibration_accepts_perpendicular_axes_modulo_180() {
        // Same physical geometry as (0°, 90°) — either axis could be the
        // "positive" pulse direction. The validator must not penalise this.
        let calib = crate::GuidingCalibration {
            is_calibrated: true,
            ra_angle_deg: Some(180.0),
            dec_angle_deg: Some(90.0),
        };
        assert!(validate_calibration_quality(&calib, &_cfg()).is_ok());
    }

    #[test]
    fn validate_calibration_accepts_axes_within_tolerance() {
        // 15° off perpendicular — under the 20° default ceiling.
        let calib = crate::GuidingCalibration {
            is_calibrated: true,
            ra_angle_deg: Some(0.0),
            dec_angle_deg: Some(75.0),
        };
        assert!(validate_calibration_quality(&calib, &_cfg()).is_ok());
    }

    #[test]
    fn validate_calibration_rejects_grossly_non_perpendicular_axes() {
        // Axes parallel — calibration was almost certainly broken (mount
        // pulsed in the same direction for both axes).
        let calib = crate::GuidingCalibration {
            is_calibrated: true,
            ra_angle_deg: Some(0.0),
            dec_angle_deg: Some(0.0),
        };
        let result = validate_calibration_quality(&calib, &_cfg());
        assert!(result.is_err());
        let msg = result.unwrap_err();
        assert!(msg.contains("off-perpendicular"), "got: {}", msg);
    }

    #[test]
    fn validate_calibration_passes_when_angles_missing() {
        // Driver didn't report angles — we can't validate geometry, but the
        // is_calibrated flag is true so we let it through. The RMS sampling
        // step is the safety net for this case.
        let calib = crate::GuidingCalibration {
            is_calibrated: true,
            ra_angle_deg: None,
            dec_angle_deg: None,
        };
        assert!(validate_calibration_quality(&calib, &_cfg()).is_ok());
    }

    #[test]
    fn validate_calibration_honours_custom_tolerance() {
        // 25° off perpendicular — over default 20° ceiling but under custom 30°.
        let calib = crate::GuidingCalibration {
            is_calibrated: true,
            ra_angle_deg: Some(0.0),
            dec_angle_deg: Some(65.0),
        };
        let strict = StartGuidingConfig::default();
        assert!(validate_calibration_quality(&calib, &strict).is_err());

        let lax = StartGuidingConfig {
            max_calibration_axis_error_deg: 30.0,
            ..StartGuidingConfig::default()
        };
        assert!(validate_calibration_quality(&calib, &lax).is_ok());
    }

    // -------------------------------------------------------------------
    // Wave 3 Image Grading: reject folder resolution
    // -------------------------------------------------------------------

    #[test]
    fn reject_dir_defaults_to_reject_subfolder_of_save_path() {
        let base = std::path::Path::new("/captures/M31/L");
        let dir = resolve_reject_dir(base, None);
        assert_eq!(dir, std::path::Path::new("/captures/M31/L/Reject"));
    }

    #[test]
    fn reject_dir_relative_override_resolves_against_save_path() {
        let base = std::path::Path::new("/captures/M31/L");
        let dir = resolve_reject_dir(base, Some("BadFrames"));
        assert_eq!(dir, std::path::Path::new("/captures/M31/L/BadFrames"));
    }

    #[test]
    fn reject_dir_absolute_override_used_verbatim() {
        // Use platform-appropriate absolute path.
        #[cfg(windows)]
        let abs = r"C:\nightshade\rejects";
        #[cfg(not(windows))]
        let abs = "/var/nightshade/rejects";

        let base = std::path::Path::new("/captures/M31/L");
        let dir = resolve_reject_dir(base, Some(abs));
        assert_eq!(dir, std::path::Path::new(abs));
    }

    #[test]
    fn device_disconnect_messages_are_classified_narrowly() {
        assert!(is_device_disconnected_message("No camera connected"));
        assert!(is_device_disconnected_message(
            "Device 'cam1' is not connected. Cannot perform: exposure. Please reconnect the device first."
        ));
        assert!(is_device_disconnected_message(
            "Filter wheel is not connected"
        ));

        assert!(!is_device_disconnected_message(
            "No target coordinates available"
        ));
        assert!(!is_device_disconnected_message(
            "Plate solve returned no solution"
        ));
        assert!(!is_device_disconnected_message("Script exited with code 1"));
    }

    #[test]
    fn disconnected_instruction_failure_posts_recovery_request() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let (tx, mut rx) = tokio::sync::mpsc::channel(1);
            let result = InstructionResult::failure("No camera connected");
            let status = result.log_and_get_status_with_recovery("Exposure", Some(&tx));

            assert_eq!(status, NodeStatus::Failure);
            assert_eq!(
                rx.recv().await,
                Some(crate::recovery::RecoveryCause::DeviceDisconnected)
            );
        });
    }
}
