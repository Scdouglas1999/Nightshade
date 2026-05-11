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
        match self.status {
            NodeStatus::Failure => {
                if let Some(msg) = &self.message {
                    tracing::error!("{} failed: {}", node_name, msg);
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

    tracing::info!("Slewing to RA: {:.4}h, Dec: {:.4}Ã‚Â°", ra, dec);

    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Slewing to RA: {:.2}h, Dec: {:.1}Ã‚Â°", ra, dec),
        );
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
                                        "Slew completed. Target: RA={:.4}h, Dec={:.4}Ã‚Â°, Actual: RA={:.4}h, Dec={:.4}Ã‚Â°",
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
        "Centering on RA: {:.4}Ã‚Â°, Dec: {:.4}Ã‚Â° (accuracy: {:.1}\")",
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

        let attempt_progress = ((attempt - 1) as f64 / config.max_attempts as f64) * 100.0;
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
                "Updated trigger state with plate solve: RA={:.4}Ã‚Â°, Dec={:.4}Ã‚Â°, scale={:.2}\"/px",
                solve_result.ra_degrees, solve_result.dec_degrees, solve_result.pixel_scale
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
                attempt_progress + 50.0 / config.max_attempts as f64,
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
                attempt_progress + 75.0 / config.max_attempts as f64,
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

/// Execute an exposure instruction
pub async fn execute_exposure(
    config: &ExposureConfig,
    ctx: &InstructionContext,
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
            } else if let Some(filter) = &config.filter {
                tracing::info!("Changing to filter by name: {}", filter);
                if let Err(e) = ctx
                    .device_ops
                    .filterwheel_set_filter_by_name(fw_id, filter)
                    .await
                {
                    return InstructionResult::failure(format!("Failed to change filter: {}", e));
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
        let image_data = tokio::select! {
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

        // Per-frame HFR feeds the HfrDegraded / FocusDrift triggers; computing
        // it here (rather than only on autofocus) gives the triggers real-time
        // visibility into focus health between AF runs.
        match ctx.device_ops.calculate_image_hfr(&image_data).await {
            Ok(Some(hfr)) => {
                tracing::info!("Frame {}/{} HFR: {:.2} pixels", frame, config.count, hfr);
                hfr_values.push(hfr);
            }
            Ok(None) => {
                tracing::warn!(
                    "Frame {}/{} - no stars detected for HFR calculation",
                    frame,
                    config.count
                );
            }
            Err(e) => {
                tracing::warn!(
                    "Frame {}/{} - HFR calculation failed: {}",
                    frame,
                    config.count,
                    e
                );
            }
        }

        let save_path = config
            .save_to
            .as_ref()
            .map(PathBuf::from)
            .or_else(|| ctx.save_path.clone());

        if let Some(base_path) = save_path {
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
            let filename = format!("{}_{}_{:04}.fits", target_label, filter_label, frame);
            let full_path = ensure_unique_save_path(base_path.join(&filename));

            if let Err(e) = ctx
                .device_ops
                .save_fits(
                    &image_data,
                    full_path.to_str().unwrap_or(&filename),
                    ctx.target_name.as_deref(),
                    config.filter.as_deref(),
                    ctx.target_ra,
                    ctx.target_dec,
                )
                .await
            {
                tracing::warn!("Failed to save image: {}", e);
            } else {
                tracing::info!("Saved: {}", full_path.display());
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
            return InstructionResult::failure(format!("Autofocus curve fitting failed: {}", e));
        }
    };

    let best_position = af_result.best_position;
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
    let imaging_data = nightshade_imaging::ImageData::from_u16(
        image.width,
        image.height,
        1,
        &image.data,
    );

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

            if let Some(cb) = progress_callback {
                cb(100.0, "Guiding active".to_string());
            }
            InstructionResult::success_with_message("Guiding started and verified active")
        }
        Err(e) => InstructionResult::failure(format!("Failed to start guiding: {}", e)),
    }
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
    let timeout = Duration::from_secs(
        config
            .timeout_secs
            .map(|s| s as u64)
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
                apply_filter_focus_offset(&config.filter_name, ctx, progress_callback).await;
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
            apply_filter_focus_offset(&config.filter_name, ctx, progress_callback).await;
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
) {
    let offset = match ctx.filter_focus_offsets.get(filter_name) {
        Some(&o) if o != 0 => o,
        _ => return,
    };

    let focuser_id = match ctx.focuser_id.as_deref() {
        Some(id) if !id.is_empty() => id,
        _ => return,
    };

    tracing::info!(
        "Applying focus offset for filter \"{}\": {} steps",
        filter_name,
        offset
    );

    if let Some(cb) = progress_callback {
        cb(60.0, format!("Applying focus offset: {} steps", offset));
    }

    let current_pos = match ctx.device_ops.focuser_get_position(focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            tracing::error!("Failed to read focuser position for filter offset: {}", e);
            return;
        }
    };

    let target_pos = current_pos + offset;
    tracing::info!(
        "Focus offset: {} + {} = {} (current + offset = target)",
        current_pos,
        offset,
        target_pos
    );

    if let Err(e) = ctx.device_ops.focuser_move_to(focuser_id, target_pos).await {
        tracing::error!(
            "Failed to apply focus offset for filter \"{}\": {}",
            filter_name,
            e
        );
        return;
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
                tracing::warn!("Error checking focuser movement: {}", e);
                return;
            }
        }
    }

    if !reached_target {
        tracing::warn!(
            "Focus offset move for filter \"{}\" did not report completion before the timeout window",
            filter_name
        );
        return;
    }

    let final_pos = match ctx.device_ops.focuser_get_position(focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            tracing::warn!(
                "Failed to verify final focuser position after applying filter offset for \"{}\": {}",
                filter_name,
                e
            );
            return;
        }
    };

    if final_pos != target_pos {
        tracing::warn!(
            "Filter offset for \"{}\" could not be verified (target {}, actual {})",
            filter_name,
            target_pos,
            final_pos
        );
        return;
    }

    if let Some(cb) = progress_callback {
        cb(
            80.0,
            format!(
                "Focus offset applied: {} -> {} ({:+} steps)",
                current_pos, final_pos, offset
            ),
        );
    }

    tracing::info!(
        "Focus offset for filter \"{}\" applied: {} -> {}",
        filter_name,
        current_pos,
        final_pos
    );
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

    tracing::info!("Cooling camera to {}Ã‚Â°C", config.target_temp);

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
            "At target: {:.1}Ã‚Â°C ({:.0}% power)",
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
            format!(
                "Starting: {:.1}Ã‚Â°C Ã¢â€ â€™ {:.1}Ã‚Â°C",
                start_temp, target_temp
            ),
        );
    }

    // If duration specified, wait for cooling
    if let Some(duration_mins) = config.duration_mins {
        // 6 polls per minute = 10 s cadence; fast enough that the UI feels
        // responsive, slow enough that a 20-min cool-down does not flood
        // logs with hundreds of poll lines.
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
            let time_progress = step as f64 / steps as f64 * 100.0;

            let progress = temp_progress.max(time_progress);

            tracing::debug!(
                "Cooling progress: {:.1}%, current temp: {:.1}Ã‚Â°C, power: {:.0}%",
                progress,
                current_temp,
                cooler_power
            );

            if let Some(cb) = progress_callback {
                cb(
                    progress,
                    format!(
                        "Cooling: {:.1}Ã‚Â°C Ã¢â€ â€™ {:.1}Ã‚Â°C ({:.0}% power)",
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
                    "Target reached: {:.1}Ã‚Â°C ({:.0}% power)",
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
        cb(100.0, format!("Cooling to {}Ã‚Â°C initiated", target_temp));
    }

    InstructionResult::success_with_message(format!("Camera cooling set to {}Ã‚Â°C", target_temp))
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

    tracing::info!("Warming camera at {}Ã‚Â°C/min", config.rate_per_min);

    let start_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
        Ok(value) => value,
        Err(e) => {
            return InstructionResult::failure(format!("Failed to read camera temperature: {}", e))
        }
    };
    let target_temp = config.target_temp.unwrap_or(20.0);
    let temp_range = target_temp - start_temp;
    let duration_mins = temp_range / config.rate_per_min;
    let steps = (duration_mins * 6.0).max(1.0) as u32;

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!(
                "Warming: {:.1}Ã‚Â°C Ã¢â€ â€™ {:.1}Ã‚Â°C",
                start_temp, target_temp
            ),
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

        let progress_temp = start_temp + (temp_range * step as f64 / steps as f64);
        let progress_percent = (step as f64 / steps as f64) * 100.0;

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
                format!(
                    "Warming: {:.1}Ã‚Â°C Ã¢â€ â€™ {:.1}Ã‚Â°C",
                    progress_temp, target_temp
                ),
            );
        }

        tracing::debug!("Warming progress: {:.1}Ã‚Â°C", progress_temp);
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

    match ctx.device_ops.mount_park(&mount_id).await {
        Ok(_) => InstructionResult::success_with_message("Mount parked"),
        Err(e) => InstructionResult::failure(format!("Park failed: {}", e)),
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
    status_callback: impl Fn(String, Option<f64>),
    image_callback: impl Fn(crate::polar_align::PolarAlignmentImageData),
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
            let total_wait_secs = (until - now) as u64;
            let wait_until_str = chrono::DateTime::from_timestamp(until, 0)
                .map(|dt| dt.format("%H:%M:%S").to_string())
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
            let total_wait_secs = (twilight_time - now) as u64;
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

    let total_steps = (config.seconds * 10.0) as u64;
    for step in 0..total_steps {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }

        // Emit progress every second (10 steps)
        if step % 10 == 0 {
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
        .send_notification(level, &config.title, &config.message)
        .await
    {
        tracing::warn!("Failed to send notification: {}", e);
    }

    InstructionResult::success()
}

// =============================================================================
// SCRIPT INSTRUCTION
// =============================================================================

/// Execute script
pub async fn execute_script(config: &ScriptConfig, ctx: &InstructionContext) -> InstructionResult {
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

    // Add environment variables with session context
    if let Some(target) = &ctx.target_name {
        cmd.env("NIGHTSHADE_TARGET", target);
    }
    if let Some(ra) = ctx.target_ra {
        cmd.env("NIGHTSHADE_TARGET_RA", ra.to_string());
    }
    if let Some(dec) = ctx.target_dec {
        cmd.env("NIGHTSHADE_TARGET_DEC", dec.to_string());
    }
    if let Some(filter) = &ctx.current_filter {
        cmd.env("NIGHTSHADE_FILTER", filter);
    }

    // Set timeout
    let timeout = match config.timeout_secs {
        Some(v) if v > 0 => v as u64,
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
            format!("Meridian flip failed: {} (action taken: {:?})", error, action_taken),
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

/// Execute mosaic panel iteration
/// This is a container instruction that iterates through mosaic panels
/// The actual panel calculation is done in the mosaic module
pub async fn execute_mosaic(
    config: &crate::MosaicConfig,
    _ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Starting mosaic".to_string());
    }

    tracing::info!(
        "Starting mosaic: {}x{} panels, {:.1}% overlap",
        config.panels_horizontal,
        config.panels_vertical,
        config.overlap_percent
    );

    // Emit progress for calculating panels
    if let Some(cb) = progress_callback {
        cb(30.0, "Calculating panel positions".to_string());
    }

    // Calculate all panel positions
    let panels = crate::mosaic::calculate_mosaic_panels(config);
    let total_panels = panels.len();

    tracing::info!("Mosaic contains {} panels", total_panels);

    // Note: The actual execution of visiting each panel will be handled by the
    // node execution logic which will create child slew/center/expose nodes
    // for each panel. This instruction just validates the configuration.

    // Emit final progress
    if let Some(cb) = progress_callback {
        cb(100.0, format!("Mosaic configured: {} panels", total_panels));
    }

    InstructionResult {
        status: NodeStatus::Success,
        message: Some(format!("Mosaic configured: {} panels", total_panels)),
        data: Some(serde_json::json!({
            "total_panels": total_panels,
            "panels_horizontal": config.panels_horizontal,
            "panels_vertical": config.panels_vertical,
            "overlap_percent": config.overlap_percent,
            "total_area_arcmin2": crate::mosaic::calculate_mosaic_area(config),
        })),
        hfr_values: Vec::new(),
    }
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
    let timeout = Duration::from_secs(config.timeout_secs as u64);
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
    let timeout = Duration::from_secs(config.timeout_secs as u64);
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
    let timeout = Duration::from_secs(config.timeout_secs as u64);
    match wait_for_calibrator_state(&device_id, 3, ctx, timeout).await {
        Ok(_) => {
            // Verify brightness is set correctly
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
    let timeout = Duration::from_secs(config.timeout_secs as u64);
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
}
