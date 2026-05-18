//! Behavior tree node definitions and execution

use crate::{
    device_ops::{NullDeviceOps, SharedDeviceOps},
    executor::ExecutorEvent,
    instructions::*,
    AutofocusConfig, AutofocusMethod, ConditionalCheck, ConditionalConfig, ExposureConfig,
    LoopCondition, LoopConfig, NodeDefinition, NodeId, NodeStatus, NodeType, ParallelConfig,
    RecoveryAction, RecoveryConfig, SafetyFailMode, TargetHeaderConfig, TriggerAction,
    TriggerCondition,
};
use async_trait::async_trait;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

/// Context passed to nodes during execution
pub struct ExecutionContext {
    /// ID of the node being executed
    pub node_id: NodeId,
    /// Current target information (propagated from TargetGroup)
    pub target_ra: Option<f64>,
    pub target_dec: Option<f64>,
    pub target_name: Option<String>,
    pub target_rotation: Option<f64>,
    /// Current filter
    pub current_filter: Option<String>,
    /// Current binning
    pub current_binning: crate::Binning,
    /// Cancellation flag
    pub is_cancelled: Arc<AtomicBool>,
    /// Pause flag - set by recovery nodes, cleared by executor on resume
    pub is_paused: Arc<AtomicBool>,
    /// Skip current target request - set by trigger monitor and consumed by target header.
    pub skip_to_next_target: Arc<AtomicBool>,
    /// Trust-patch §7: SkipToNode target. When `Some(node_id)`, the executor
    /// is in "skip until we reach this node" mode: container nodes mark
    /// children whose subtree does NOT contain the target as Skipped, and
    /// unwrap the request once the target's own subtree is entered. Cleared
    /// to None once consumed. Read-frequently / written-rarely (typically
    /// once per SkipToNode command), so a `parking_lot::RwLock` keeps the
    /// read path lock-free under no contention.
    pub skip_to_node: Arc<parking_lot::RwLock<Option<NodeId>>>,
    /// Resume notifier - signaled when execution should resume after pause
    pub resume_notify: Arc<tokio::sync::Notify>,
    /// Progress callback
    pub progress_callback: Option<Box<dyn Fn(ProgressUpdate) + Send + Sync>>,
    /// Polar alignment image callback (for sending live images to UI)
    pub polar_align_image_callback:
        Option<Box<dyn Fn(crate::polar_align::PolarAlignmentImageData) + Send + Sync>>,
    /// Connected device IDs
    pub camera_id: Option<String>,
    pub mount_id: Option<String>,
    pub focuser_id: Option<String>,
    pub filterwheel_id: Option<String>,
    pub rotator_id: Option<String>,
    pub dome_id: Option<String>,
    pub cover_calibrator_id: Option<String>,
    /// Base save path for images
    pub save_path: Option<std::path::PathBuf>,
    /// Observer location
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    /// Device operations handler
    pub device_ops: SharedDeviceOps,
    /// Completed integration time in seconds (shared counter)
    pub completed_integration_secs: Arc<RwLock<f64>>,
    /// Trigger state (for updating during execution)
    pub trigger_state: Option<Arc<RwLock<crate::triggers::TriggerState>>>,
    /// Safety fail mode - determines behavior when safety devices fail or are unavailable
    pub safety_fail_mode: SafetyFailMode,
    /// Filter focus offsets from equipment profile (filter_name -> offset_steps)
    pub filter_focus_offsets: std::collections::HashMap<String, i32>,
    /// Optional broadcast handle so instruction code can emit ExecutorEvents
    /// directly (used for surfacing FITS-save failures and other instruction-
    /// level errors that the UI must see, beyond the InstructionResult flow).
    /// `None` outside the live executor (e.g. unit tests / direct invocations).
    pub event_tx: Option<broadcast::Sender<ExecutorEvent>>,
}

/// Progress update sent during execution
#[derive(Debug, Clone)]
pub struct ProgressUpdate {
    pub node_id: NodeId,
    pub status: NodeStatus,
    pub message: Option<String>,
    pub current_frame: Option<u32>,
    pub total_frames: Option<u32>,
    pub current_child: Option<usize>,
    pub total_children: Option<usize>,
    /// Exposure time just completed (seconds)
    pub completed_exposure_secs: Option<f64>,
}

impl ExecutionContext {
    pub fn new(node_id: NodeId) -> Self {
        Self {
            node_id,
            target_ra: None,
            target_dec: None,
            target_name: None,
            target_rotation: None,
            current_filter: None,
            current_binning: crate::Binning::One,
            is_cancelled: Arc::new(AtomicBool::new(false)),
            is_paused: Arc::new(AtomicBool::new(false)),
            skip_to_next_target: Arc::new(AtomicBool::new(false)),
            skip_to_node: Arc::new(parking_lot::RwLock::new(None)),
            resume_notify: Arc::new(tokio::sync::Notify::new()),
            progress_callback: None,
            polar_align_image_callback: None,
            camera_id: None,
            mount_id: None,
            focuser_id: None,
            filterwheel_id: None,
            rotator_id: None,
            dome_id: None,
            cover_calibrator_id: None,
            save_path: None,
            latitude: None,
            longitude: None,
            device_ops: Arc::new(NullDeviceOps),
            completed_integration_secs: Arc::new(RwLock::new(0.0)),
            trigger_state: None,
            safety_fail_mode: SafetyFailMode::default(),
            filter_focus_offsets: std::collections::HashMap::new(),
            event_tx: None,
        }
    }

    pub fn with_safety_fail_mode(mut self, mode: SafetyFailMode) -> Self {
        self.safety_fail_mode = mode;
        self
    }

    pub fn with_device_ops(mut self, ops: SharedDeviceOps) -> Self {
        self.device_ops = ops;
        self
    }

    pub fn with_target(mut self, name: String, ra: f64, dec: f64, rotation: Option<f64>) -> Self {
        self.target_name = Some(name);
        self.target_ra = Some(ra);
        self.target_dec = Some(dec);
        self.target_rotation = rotation;
        self
    }

    pub async fn is_cancelled(&self) -> bool {
        self.is_cancelled.load(Ordering::Relaxed)
    }

    /// Check if currently paused
    pub fn is_paused(&self) -> bool {
        self.is_paused.load(Ordering::Relaxed)
    }

    /// Request pause and wait for resume
    /// Returns false if cancelled while waiting
    pub async fn pause_and_wait_for_resume(&self) -> bool {
        self.is_paused.store(true, Ordering::Relaxed);
        tracing::info!("Execution paused, waiting for resume...");

        loop {
            tokio::select! {
                _ = self.resume_notify.notified() => {
                    if !self.is_paused.load(Ordering::Relaxed) {
                        tracing::info!("Execution resumed");
                        return true;
                    }
                }
                // Belt-and-suspenders: notify_waiters() and is_paused are not
                // atomically coupled, so a stale notify could fire just before
                // is_paused flips. The 100 ms tick lets us re-check both
                // is_cancelled and is_paused even if no wake-up arrives.
                _ = tokio::time::sleep(std::time::Duration::from_millis(100)) => {
                    if self.is_cancelled.load(Ordering::Relaxed) {
                        tracing::info!("Cancelled while paused");
                        return false;
                    }
                    if !self.is_paused.load(Ordering::Relaxed) {
                        tracing::info!("Execution resumed");
                        return true;
                    }
                }
            }
        }
    }

    /// Resume execution (called by executor)
    pub fn resume(&self) {
        self.is_paused.store(false, Ordering::Relaxed);
        self.resume_notify.notify_waiters();
    }

    /// Request that execution skips the current target and advances to the next one.
    pub fn request_skip_to_next_target(&self) {
        self.skip_to_next_target.store(true, Ordering::Relaxed);
    }

    /// Check whether a skip-to-next-target request is pending.
    pub fn is_skip_to_next_target_requested(&self) -> bool {
        self.skip_to_next_target.load(Ordering::Relaxed)
    }

    /// Clear a pending skip-to-next-target request.
    pub fn clear_skip_to_next_target_request(&self) {
        self.skip_to_next_target.store(false, Ordering::Relaxed);
    }

    /// Trust-patch §7: read the current SkipToNode target, if any.
    /// Returns the target node id when the executor is in "skip until we
    /// reach this node" mode; None otherwise.
    pub fn skip_to_node_target(&self) -> Option<NodeId> {
        self.skip_to_node.read().clone()
    }

    /// Trust-patch §7: clear the SkipToNode request, signalling that we
    /// have reached (or recursed into) the target subtree and normal
    /// execution should resume.
    pub fn clear_skip_to_node_request(&self) {
        *self.skip_to_node.write() = None;
    }

    /// Trust-patch §7: set the SkipToNode request from outside the tree
    /// walk (called by the executor command handler).
    pub fn set_skip_to_node_request(&self, node_id: NodeId) {
        *self.skip_to_node.write() = Some(node_id);
    }

    pub fn send_progress(&self, update: ProgressUpdate) {
        // Why: integration time is no longer tracked here. The canonical update
        // happens on the awaiting path in `TakeExposure` (see the
        // `completed_integration_secs.write().await` block in
        // `Node::execute -> NodeType::TakeExposure`). Previously this function
        // also called `try_write` on the same counter, which either silently
        // dropped the increment on contention or — when uncontended —
        // double-counted the exposure duration. Both behaviours are bugs.
        // `send_progress` is intentionally sync because it is invoked from
        // synchronous progress callbacks supplied to instruction code; keeping
        // it sync avoids forcing every callback caller into an async context.
        if let Some(callback) = &self.progress_callback {
            callback(update);
        }
    }

    /// Get the current completed integration time in seconds
    pub async fn get_completed_integration_secs(&self) -> f64 {
        *self.completed_integration_secs.read().await
    }

    /// Calculate current altitude of target based on RA/Dec and observer location
    pub fn calculate_altitude(&self) -> Option<f64> {
        let ra_hours = self.target_ra?;
        let dec_degrees = self.target_dec?;
        let lat = self.latitude?;
        let lon = self.longitude?;

        let now = chrono::Utc::now();
        let jd = julian_day(&now);
        let lst = local_sidereal_time(jd, lon);

        let ha = lst - ra_hours;
        let ha_rad = (ha * 15.0).to_radians(); // RA is stored in hours; 1 h = 15°
        let dec_rad = dec_degrees.to_radians();
        let lat_rad = lat.to_radians();

        // Standard astronomy formula: sin(alt) = sin(lat)·sin(dec) + cos(lat)·cos(dec)·cos(HA)
        let sin_alt = lat_rad.sin() * dec_rad.sin() + lat_rad.cos() * dec_rad.cos() * ha_rad.cos();
        Some(sin_alt.asin().to_degrees())
    }

    /// Calculate separation between target and moon in degrees
    pub fn calculate_moon_separation(&self) -> Option<f64> {
        let target_ra = self.target_ra?;
        let target_dec = self.target_dec?;

        // Low-precision lunar ephemeris adequate for moon-avoidance: the
        // ConditionalCheck::MoonSeparationAbove threshold is typically tens of
        // degrees, so the ~0.1° error this approximation incurs is irrelevant
        // and avoids pulling in a full ephemeris dependency.
        let now = chrono::Utc::now();
        let jd = julian_day(&now);
        let days = jd - 2451545.0;

        // Mean longitude, mean anomaly, ascending-node longitude (Meeus low-precision).
        let moon_longitude = (218.32 + 13.176396 * days) % 360.0;
        let moon_anomaly = (134.9 + 13.064993 * days) % 360.0;
        let moon_node = (93.3 + 13.229350 * days) % 360.0;

        // Two largest periodic terms only (evection + variation analogues).
        let ecl_lon = moon_longitude + 6.29 * moon_anomaly.to_radians().sin()
            - 1.27 * (2.0 * moon_node.to_radians() - moon_anomaly.to_radians()).sin();
        let ecl_lat = 5.13 * moon_node.to_radians().sin();

        let obliquity = 23.439f64;
        let ecl_lon_rad = ecl_lon.to_radians();
        let ecl_lat_rad = ecl_lat.to_radians();
        let obl_rad = obliquity.to_radians();

        let moon_ra = ((ecl_lon_rad.sin() * obl_rad.cos() - ecl_lat_rad.tan() * obl_rad.sin())
            .atan2(ecl_lon_rad.cos()))
        .to_degrees()
            / 15.0; // Convert to hours
        let moon_dec = (ecl_lat_rad.sin() * obl_rad.cos()
            + ecl_lat_rad.cos() * obl_rad.sin() * ecl_lon_rad.sin())
        .asin()
        .to_degrees();

        // Spherical law of cosines: cos(sep) = sin(d1)sin(d2) + cos(d1)cos(d2)cos(Δra).
        // Adequate for moon avoidance — haversine's small-angle precision is
        // unnecessary at the tens-of-degrees thresholds users configure.
        let target_ra_rad = (target_ra * 15.0).to_radians();
        let target_dec_rad = target_dec.to_radians();
        let moon_ra_rad = (moon_ra * 15.0).to_radians();
        let moon_dec_rad = moon_dec.to_radians();

        let cos_sep = target_dec_rad.sin() * moon_dec_rad.sin()
            + target_dec_rad.cos() * moon_dec_rad.cos() * (target_ra_rad - moon_ra_rad).cos();

        Some(cos_sep.acos().to_degrees())
    }

    /// Check if it's currently dark (astronomical twilight has ended)
    pub fn is_dark(&self) -> Option<bool> {
        let lat = self.latitude?;
        let lon = self.longitude?;

        let now = chrono::Utc::now();
        let jd = julian_day(&now);

        let days_since_j2000 = jd - 2451545.0;
        let (sun_ra, sun_dec) = approximate_sun_equatorial_coords(days_since_j2000);

        let lst = local_sidereal_time(jd, lon);
        let ha = lst - sun_ra;
        let ha_rad = (ha * 15.0).to_radians();
        let dec_rad = sun_dec.to_radians();
        let lat_rad = lat.to_radians();

        let sun_alt = (lat_rad.sin() * dec_rad.sin()
            + lat_rad.cos() * dec_rad.cos() * ha_rad.cos())
        .asin()
        .to_degrees();

        // Astronomical twilight ends when the sun is more than 18° below the
        // horizon — the IAU-adopted definition; deep-sky imaging targets this
        // boundary because any brighter sky elevates the background floor.
        Some(sun_alt < -18.0)
    }

    /// Set the next meridian flip time in the trigger state (if available)
    /// If trigger state is not accessible, the timestamp is skipped.
    pub async fn set_next_meridian_flip_time(&self, timestamp: Option<i64>) {
        if let Some(trigger_state_lock) = &self.trigger_state {
            let mut trigger_state = trigger_state_lock.write().await;
            trigger_state.next_meridian_flip_time = timestamp;
        } else if let Some(ts) = timestamp {
            tracing::debug!(
                "Meridian flip timestamp {} calculated but trigger state is unavailable",
                ts
            );
        }
    }

    /// Build an InstructionContext from this ExecutionContext
    pub async fn to_instruction_context(&self) -> InstructionContext {
        InstructionContext {
            target_ra: self.target_ra,
            target_dec: self.target_dec,
            target_name: self.target_name.clone(),
            current_filter: self.current_filter.clone(),
            current_binning: self.current_binning,
            cancellation_token: self.is_cancelled.clone(),
            camera_id: self.camera_id.clone(),
            mount_id: self.mount_id.clone(),
            focuser_id: self.focuser_id.clone(),
            filterwheel_id: self.filterwheel_id.clone(),
            rotator_id: self.rotator_id.clone(),
            dome_id: self.dome_id.clone(),
            cover_calibrator_id: self.cover_calibrator_id.clone(),
            save_path: self.save_path.clone(),
            latitude: self.latitude,
            longitude: self.longitude,
            device_ops: self.device_ops.clone(),
            trigger_state: self.trigger_state.clone(),
            filter_focus_offsets: self.filter_focus_offsets.clone(),
            event_tx: self.event_tx.clone(),
        }
    }
}

fn approximate_sun_equatorial_coords(days_since_j2000: f64) -> (f64, f64) {
    let mean_longitude = (280.46 + 0.9856474 * days_since_j2000).rem_euclid(360.0);
    let mean_anomaly = (357.528 + 0.9856003 * days_since_j2000).rem_euclid(360.0);

    let ecliptic_longitude = mean_longitude
        + 1.915 * mean_anomaly.to_radians().sin()
        + 0.020 * (2.0 * mean_anomaly.to_radians()).sin();

    let obliquity = 23.439 - 0.0000004 * days_since_j2000;
    let ecliptic_longitude_rad = ecliptic_longitude.to_radians();
    let obliquity_rad = obliquity.to_radians();
    let sun_dec = (obliquity_rad.sin() * ecliptic_longitude_rad.sin())
        .asin()
        .to_degrees();
    let sun_ra = (ecliptic_longitude_rad.sin() * obliquity_rad.cos())
        .atan2(ecliptic_longitude_rad.cos())
        .to_degrees()
        .rem_euclid(360.0)
        / 15.0;

    (sun_ra, sun_dec)
}

/// Compute the true median of a slice of HFR (half-flux radius) measurements.
///
/// Filters out `NaN` values and any non-positive measurements (HFR <= 0 is
/// physically impossible; it indicates a measurement failure such as a frame
/// with no detected stars). Returns `None` if no valid samples remain.
///
/// For an odd-length sorted slice the middle value is returned; for an
/// even-length slice the average of the two central values is returned. f64
/// comparison uses `partial_cmp`, so the filter step is essential — sorting a
/// slice containing `NaN` would otherwise produce undefined ordering.
///
/// Why a function (not an inline closure): HFR-degraded triggers fire on a
/// single noisy frame if the central-tendency estimator is biased, so the
/// estimator deserves direct unit tests. The previous inline implementation
/// (`fold` with `(a + val) / 2.0`) was an exponentially-weighted moving
/// average that gave the latest frame ½ weight, the previous frame ¼, etc.
fn compute_hfr_median(values: &[f64]) -> Option<f64> {
    let mut filtered: Vec<f64> = values
        .iter()
        .copied()
        .filter(|v| !v.is_nan() && *v > 0.0)
        .collect();
    if filtered.is_empty() {
        return None;
    }
    filtered.sort_by(|a, b| {
        a.partial_cmp(b)
            .expect("NaN values were filtered out above; partial_cmp must succeed")
    });
    let len = filtered.len();
    let median = if len % 2 == 1 {
        filtered[len / 2]
    } else {
        (filtered[len / 2 - 1] + filtered[len / 2]) / 2.0
    };
    Some(median)
}

/// Base trait for all behavior tree nodes
#[async_trait]
pub trait Node: Send + Sync {
    /// Get the unique ID of this node
    fn id(&self) -> &NodeId;

    /// Get the display name of this node
    fn name(&self) -> &str;

    /// Get the node type
    fn node_type(&self) -> &NodeType;

    /// Is this node enabled?
    fn is_enabled(&self) -> bool;

    /// Execute the node and return its status
    async fn execute(&mut self, context: &mut ExecutionContext) -> NodeStatus;

    /// Reset the node to its initial state
    fn reset(&mut self);

    /// Abort the node if it's running
    async fn abort(&mut self);

    /// Get child nodes (for container nodes)
    fn children(&self) -> &[Box<dyn Node>];

    /// Get mutable children (for container nodes)
    fn children_mut(&mut self) -> &mut Vec<Box<dyn Node>>;

    /// Mark a node as completed (for crash recovery resume)
    /// If node_id matches this node, marks it as Success.
    /// Otherwise, propagates to children.
    fn mark_completed(&mut self, node_id: &NodeId);

    /// Trust-patch §7: does this subtree contain `node_id`?
    ///
    /// Used by the SkipToNode command path so the executor can mark
    /// preceding siblings as Skipped and recurse only into the subtree
    /// containing the target. Default implementation walks `id()` and
    /// `children()` so RuntimeNode does not need to override it.
    fn contains_node(&self, node_id: &NodeId) -> bool {
        if self.id() == node_id {
            return true;
        }
        for child in self.children() {
            if child.contains_node(node_id) {
                return true;
            }
        }
        false
    }
}

/// A runtime node instance created from a NodeDefinition
pub struct RuntimeNode {
    pub definition: NodeDefinition,
    pub children: Vec<Box<dyn Node>>,
    pub status: NodeStatus,
    pub current_iteration: u32,
}

impl RuntimeNode {
    pub fn from_definition(def: NodeDefinition) -> Self {
        Self {
            definition: def,
            children: Vec::new(),
            status: NodeStatus::Pending,
            current_iteration: 0,
        }
    }

    pub fn add_child(&mut self, child: Box<dyn Node>) {
        self.children.push(child);
    }

    fn configured_recovery_autofocus(&self) -> Option<crate::AutofocusConfig> {
        self.children.iter().find_map(|child| {
            if !child.is_enabled() {
                return None;
            }

            match child.node_type() {
                NodeType::Autofocus(config) => Some(config.clone()),
                _ => None,
            }
        })
    }

    /// Check exposure-level triggers (per-exposure monitoring)
    /// These are different from the global TriggerManager triggers -
    /// these are checked immediately after exposures complete
    async fn check_exposure_triggers(
        &self,
        config: &ExposureConfig,
        result: &InstructionResult,
        context: &mut ExecutionContext,
    ) {
        if config.triggers.is_empty() {
            return;
        }

        // HFR triggers compare against the most recent frame's HFR; older
        // frames in `hfr_values` belong to earlier exposures in the burst and
        // have already been considered.
        let current_hfr = result.hfr_values.last().copied();

        let trigger_state_lock = match &context.trigger_state {
            Some(lock) => lock,
            None => return,
        };

        let trigger_state = trigger_state_lock.read().await;
        let latest_guiding_rms = trigger_state
            .guiding_rms_history
            .as_ref()
            .and_then(|history| history.last())
            .map(|(_, rms)| *rms);

        // Release the read lock before the trigger loop because DriftAbove
        // re-acquires it inside the match arm, and tokio's RwLock is not
        // re-entrant — holding it across an .await would deadlock.
        drop(trigger_state);

        for trigger in &config.triggers {
            let should_fire = match &trigger.condition {
                TriggerCondition::HfrAbove(threshold) => {
                    if let Some(hfr) = current_hfr {
                        hfr > *threshold
                    } else {
                        false
                    }
                }
                TriggerCondition::GuidingRmsAbove(threshold) => {
                    if let Some(rms) = latest_guiding_rms {
                        rms > *threshold
                    } else {
                        false
                    }
                }
                TriggerCondition::DriftAbove { ra_px, dec_px } => {
                    let trigger_state = trigger_state_lock.read().await;

                    match trigger_state.calculate_drift_pixels() {
                        Some((drift_ra_px, drift_dec_px)) => {
                            let drift_exceeds = drift_ra_px > *ra_px || drift_dec_px > *dec_px;
                            if drift_exceeds {
                                tracing::warn!(
                                    "Drift detected: RA={:.2}px (threshold={:.2}px), Dec={:.2}px (threshold={:.2}px)",
                                    drift_ra_px, ra_px, drift_dec_px, dec_px
                                );
                            }
                            drift_exceeds
                        }
                        None => {
                            tracing::debug!(
                                "Drift trigger check skipped - insufficient plate solve data (thresholds: ra_px={}, dec_px={})",
                                ra_px, dec_px
                            );
                            false
                        }
                    }
                }
            };

            if should_fire {
                tracing::warn!(
                    "Exposure trigger fired: {:?} - action: {:?}",
                    trigger.condition,
                    trigger.action
                );

                match &trigger.action {
                    TriggerAction::PauseAndRecalibrate => {
                        tracing::info!("Pausing sequence due to exposure trigger");
                        context.send_progress(ProgressUpdate {
                            node_id: self.id().clone(),
                            status: NodeStatus::Running,
                            message: Some(format!(
                                "Trigger fired: {:?} - Paused for recalibration",
                                trigger.condition
                            )),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });

                        let resumed = context.pause_and_wait_for_resume().await;
                        if !resumed {
                            tracing::info!("Cancelled while paused for trigger");
                            return;
                        }
                    }
                    TriggerAction::Autofocus => {
                        tracing::info!("Running autofocus due to exposure trigger");
                        context.send_progress(ProgressUpdate {
                            node_id: self.id().clone(),
                            status: NodeStatus::Running,
                            message: Some(format!(
                                "Trigger fired: {:?} - Running autofocus",
                                trigger.condition
                            )),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });

                        // Why: spread `..AutofocusConfig::default()` so the engine-tuning
                        // fields added by audit §1.7 (backlash_compensation, outlier_rejection_sigma,
                        // use_temperature_prediction, max_star_count_change) take their defaults.
                        let af_config = AutofocusConfig {
                            method: AutofocusMethod::VCurve,
                            step_size: 100,
                            steps_out: 7,
                            exposure_duration: 3.0,
                            filter: context.current_filter.clone(),
                            binning: config.binning,
                            max_duration_secs: 600.0,
                            ..AutofocusConfig::default()
                        };

                        let ctx = context.to_instruction_context().await;
                        // Trigger-driven autofocus does not report its sub-step
                        // progress to the parent node — the exposure that armed
                        // the trigger has already finished, so there is no UI
                        // progress bar to update.
                        let af_result = execute_autofocus(&af_config, &ctx, None).await;

                        if af_result.status == NodeStatus::Success {
                            if let Some(best_hfr) = af_result.hfr_values.first() {
                                let mut trigger_state = trigger_state_lock.write().await;
                                trigger_state.update_hfr(*best_hfr);
                                trigger_state.reset_baseline_hfr();
                                trigger_state.mark_autofocus_performed();
                                tracing::info!(
                                    "Autofocus complete, reset HFR baseline to {:.2}",
                                    best_hfr
                                );
                            }
                        } else {
                            tracing::warn!(
                                "Autofocus triggered by exposure failed: {:?}",
                                af_result.status
                            );
                        }
                    }
                    TriggerAction::Abort => {
                        tracing::error!("Aborting sequence due to exposure trigger");
                        context.send_progress(ProgressUpdate {
                            node_id: self.id().clone(),
                            status: NodeStatus::Failure,
                            message: Some(format!(
                                "Trigger fired: {:?} - Aborting sequence",
                                trigger.condition
                            )),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });

                        context.is_cancelled.store(true, Ordering::Relaxed);
                        return;
                    }
                }
            }
        }
    }
}

#[async_trait]
impl Node for RuntimeNode {
    fn id(&self) -> &NodeId {
        &self.definition.id
    }

    fn name(&self) -> &str {
        &self.definition.name
    }

    fn node_type(&self) -> &NodeType {
        &self.definition.node_type
    }

    fn is_enabled(&self) -> bool {
        self.definition.enabled
    }

    async fn execute(&mut self, context: &mut ExecutionContext) -> NodeStatus {
        if !self.definition.enabled {
            self.status = NodeStatus::Skipped;
            return NodeStatus::Skipped;
        }

        self.status = NodeStatus::Running;
        context.send_progress(ProgressUpdate {
            node_id: self.id().clone(),
            status: NodeStatus::Running,
            message: Some(format!("Executing: {}", self.name())),
            current_frame: None,
            total_frames: None,
            current_child: None,
            total_children: None,
            completed_exposure_secs: None,
        });

        let result = match &self.definition.node_type {
            // Container/Logic nodes
            NodeType::TargetHeader(config) | NodeType::TargetGroup(config) => {
                self.execute_target_header(config.clone(), context).await
            }
            NodeType::Loop(config) => self.execute_loop(config.clone(), context).await,
            NodeType::Parallel(config) => self.execute_parallel(config.clone(), context).await,
            NodeType::Conditional(config) => {
                self.execute_conditional(config.clone(), context).await
            }
            NodeType::Recovery(config) => self.execute_recovery(config.clone(), context).await,

            // Instruction nodes
            NodeType::SlewToTarget(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Slew: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_slew(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Slew")
            }
            NodeType::CenterTarget(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Center: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_center(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Center Target")
            }
            NodeType::TakeExposure(config) => {
                let previous_binning = context.current_binning;
                context.current_binning = config.binning;
                let mut ctx = context.to_instruction_context().await;
                ctx.current_binning = config.binning;
                if previous_binning != config.binning {
                    tracing::warn!(
                        "Exposure binning changed from {:?} to {:?}; invalidating autofocus baseline",
                        previous_binning,
                        config.binning
                    );
                    if let Some(trigger_state_lock) = &context.trigger_state {
                        let mut trigger_state = trigger_state_lock.write().await;
                        trigger_state.invalidate_autofocus(format!(
                            "binning changed from {:?} to {:?}",
                            previous_binning, config.binning
                        ));
                    }
                }
                let node_id = self.id().clone();
                let duration_secs = config.duration_secs;
                let total_count = config.count;
                let progress_cb = context.progress_callback.as_ref();

                let result = execute_exposure(config, &ctx, |current, total| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Frame {}/{}", current, total)),
                            current_frame: Some(current),
                            total_frames: Some(total),
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None, // Will track total after completion
                        });
                    }
                })
                .await;

                // Canonical integration accounting (see audit §1.1 / send_progress
                // rustdoc): the entire burst's exposure time is added here in one
                // shot. Per-frame updates would race with the synchronous
                // progress callbacks and double-count under contention.
                if result.status == NodeStatus::Success {
                    // Why: total_count is u32 frame count (config.count); lossless to f64.
                    let total_exposure_time = duration_secs * f64::from(total_count);
                    {
                        let mut counter = context.completed_integration_secs.write().await;
                        *counter += total_exposure_time;
                    }

                    if let Some(trigger_state_lock) = &context.trigger_state {
                        let mut trigger_state = trigger_state_lock.write().await;
                        if let Some(median_hfr) = compute_hfr_median(&result.hfr_values) {
                            trigger_state.update_hfr(median_hfr);
                            tracing::debug!("Updated trigger state HFR: {:.2}", median_hfr);
                        }

                        // AutofocusInterval / DitherInterval triggers fire every
                        // N frames; we must bump the counter once per actual
                        // frame, not once per burst, or the cadence drifts when
                        // counts > 1.
                        for _ in 0..total_count {
                            trigger_state.increment_exposure_count();
                        }
                        tracing::debug!(
                            "Updated trigger state exposure count: {}",
                            trigger_state.completed_exposures
                        );
                    }

                    self.check_exposure_triggers(config, &result, context).await;

                    // Final progress event carries `completed_exposure_secs` so the
                    // executor's progress callback adds it to the global counter
                    // exactly once — per-frame events deliberately leave it None.
                    context.send_progress(ProgressUpdate {
                        node_id: self.id().clone(),
                        status: NodeStatus::Success,
                        message: Some(format!(
                            "Completed {} exposures ({:.0}s)",
                            total_count, total_exposure_time
                        )),
                        current_frame: Some(total_count),
                        total_frames: Some(total_count),
                        current_child: None,
                        total_children: None,
                        completed_exposure_secs: Some(total_exposure_time),
                    });
                } else if result.status == NodeStatus::Failure {
                    // Surface failure detail on its own log line — the
                    // InstructionResult is consumed by the match arm and the
                    // message would otherwise vanish into the void.
                    if let Some(msg) = &result.message {
                        tracing::error!("Exposure failed: {}", msg);
                    }
                }

                result.status
            }
            NodeType::Autofocus(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Autofocus: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                let result = execute_autofocus(config, &ctx, Some(&progress_fn)).await;

                if result.status == NodeStatus::Success {
                    if let Some(trigger_state_lock) = &context.trigger_state {
                        let mut trigger_state = trigger_state_lock.write().await;
                        // After a successful autofocus, the HFR baseline must reset
                        // to the new best-focus value — otherwise HfrDegraded would
                        // immediately re-fire comparing the new HFR against the
                        // stale (pre-AF) baseline that triggered this run.
                        if let Some(best_hfr) = result.hfr_values.first() {
                            trigger_state.update_hfr(*best_hfr);
                            trigger_state.reset_baseline_hfr();
                            tracing::debug!(
                                "Reset HFR baseline to {:.2} after autofocus",
                                best_hfr
                            );
                        }

                        // AutofocusInterval uses this marker to know when its
                        // every-N-frames clock should restart.
                        trigger_state.mark_autofocus_performed();
                        tracing::debug!(
                            "Marked autofocus performed at exposure {}",
                            trigger_state.completed_exposures
                        );
                    }
                } else if result.status == NodeStatus::Failure {
                    if let Some(msg) = &result.message {
                        tracing::error!("Autofocus failed: {}", msg);
                    }
                }

                result.status
            }
            NodeType::TemperatureCompensation(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Temp Comp: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                crate::temperature_compensation::execute_temperature_compensation(
                    config,
                    &ctx,
                    Some(&progress_fn),
                )
                .await
                .log_and_get_status("Temperature Compensation")
            }
            NodeType::Dither(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Dither: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                let result = execute_dither(config, &ctx, Some(&progress_fn)).await;

                if result.status == NodeStatus::Success {
                    if let Some(trigger_state_lock) = &context.trigger_state {
                        let mut trigger_state = trigger_state_lock.write().await;
                        // DitherInterval (every-N-frames cadence) resets here so
                        // the next firing window starts from the just-completed
                        // dither, not from the previous one.
                        trigger_state.mark_dither_performed();
                        tracing::debug!(
                            "Marked dither performed at exposure {}",
                            trigger_state.completed_exposures
                        );
                    }
                } else if result.status == NodeStatus::Failure {
                    if let Some(msg) = &result.message {
                        tracing::error!("Dither failed: {}", msg);
                    }
                }

                result.status
            }
            NodeType::StartGuiding(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Start Guiding: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_start_guiding(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Start Guiding")
            }
            NodeType::StopGuiding => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Stop Guiding: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_stop_guiding(&ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Stop Guiding")
            }
            NodeType::ChangeFilter(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Filter: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                let result = execute_filter_change(config, &ctx, Some(&progress_fn)).await;
                if result.status == NodeStatus::Success {
                    context.current_filter = Some(config.filter_name.clone());
                    if let Some(trigger_state_lock) = &context.trigger_state {
                        let mut trigger_state = trigger_state_lock.write().await;
                        trigger_state.set_filter(config.filter_name.clone());
                    }
                } else if result.status == NodeStatus::Failure {
                    if let Some(msg) = &result.message {
                        tracing::error!("Change Filter failed: {}", msg);
                    }
                }
                result.status
            }
            NodeType::CoolCamera(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Cool Camera: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_cool_camera(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Cool Camera")
            }
            NodeType::WarmCamera(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Warm Camera: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_warm_camera(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Warm Camera")
            }
            NodeType::MoveRotator(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Move Rotator: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_rotator_move(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Move Rotator")
            }
            NodeType::Park => {
                let ctx = context.to_instruction_context().await;
                execute_park(&ctx).await.log_and_get_status("Park")
            }
            NodeType::Unpark => {
                let ctx = context.to_instruction_context().await;
                execute_unpark(&ctx).await.log_and_get_status("Unpark")
            }
            NodeType::WaitForTime(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Wait: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_wait_time(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Wait For Time")
            }
            NodeType::Delay(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Delay: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_delay(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Delay")
            }
            NodeType::Notification(config) => {
                let ctx = context.to_instruction_context().await;
                execute_notification(config, &ctx)
                    .await
                    .log_and_get_status("Notification")
            }
            NodeType::RunScript(config) => {
                let ctx = context.to_instruction_context().await;
                execute_script(config, &ctx)
                    .await
                    .log_and_get_status("Run Script")
            }
            NodeType::PolarAlignment(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();
                let image_cb = context.polar_align_image_callback.as_ref();

                execute_polar_alignment(
                    config,
                    &ctx,
                    |msg, _progress| {
                        if let Some(cb) = progress_cb {
                            cb(ProgressUpdate {
                                node_id: node_id.clone(),
                                status: NodeStatus::Running,
                                message: Some(msg),
                                current_frame: None,
                                total_frames: None,
                                current_child: None,
                                total_children: None,
                                completed_exposure_secs: None,
                            });
                        }
                    },
                    |image_data| {
                        if let Some(cb) = image_cb {
                            cb(image_data);
                        }
                    },
                )
                .await
                .log_and_get_status("Polar Alignment")
            }
            NodeType::MeridianFlip(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Meridian Flip: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_meridian_flip(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Meridian Flip")
            }
            NodeType::OpenDome(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Open Dome: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_open_dome(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Open Dome")
            }
            NodeType::CloseDome(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Close Dome: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_close_dome(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Close Dome")
            }
            NodeType::ParkDome(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Park Dome: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_park_dome(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Park Dome")
            }
            NodeType::Mosaic(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Mosaic: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_mosaic(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Mosaic")
            }
            NodeType::FlatWizard(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Flat Wizard: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                crate::flat_wizard::execute_flat_wizard(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Flat Wizard")
            }
            NodeType::OpenCover(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Open Cover: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_open_cover(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Open Cover")
            }
            NodeType::CloseCover(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Close Cover: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_close_cover(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Close Cover")
            }
            NodeType::CalibratorOn(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Calibrator On: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_calibrator_on(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Calibrator On")
            }
            NodeType::CalibratorOff(config) => {
                let ctx = context.to_instruction_context().await;
                let node_id = self.id().clone();
                let progress_cb = context.progress_callback.as_ref();

                let progress_fn = |progress: f64, detail: String| {
                    if let Some(cb) = progress_cb {
                        cb(ProgressUpdate {
                            node_id: node_id.clone(),
                            status: NodeStatus::Running,
                            message: Some(format!("Calibrator Off: {} ({:.0}%)", detail, progress)),
                            current_frame: None,
                            total_frames: None,
                            current_child: None,
                            total_children: None,
                            completed_exposure_secs: None,
                        });
                    }
                };

                execute_calibrator_off(config, &ctx, Some(&progress_fn))
                    .await
                    .log_and_get_status("Calibrator Off")
            }
        };

        self.status = result;
        context.send_progress(ProgressUpdate {
            node_id: self.id().clone(),
            status: result,
            message: Some(format!("Completed: {}", self.name())),
            current_frame: None,
            total_frames: None,
            current_child: None,
            total_children: None,
            completed_exposure_secs: None,
        });

        result
    }

    fn reset(&mut self) {
        self.status = NodeStatus::Pending;
        self.current_iteration = 0;
        for child in &mut self.children {
            child.reset();
        }
    }

    async fn abort(&mut self) {
        self.status = NodeStatus::Cancelled;
        for child in &mut self.children {
            child.abort().await;
        }
    }

    fn children(&self) -> &[Box<dyn Node>] {
        &self.children
    }

    fn children_mut(&mut self) -> &mut Vec<Box<dyn Node>> {
        &mut self.children
    }

    fn mark_completed(&mut self, node_id: &NodeId) {
        if self.id() == node_id {
            self.status = NodeStatus::Success;
        } else {
            for child in &mut self.children {
                child.mark_completed(node_id);
            }
        }
    }
}

impl RuntimeNode {
    /// Execute a target header node (root node for each target)
    async fn execute_target_header(
        &mut self,
        config: TargetHeaderConfig,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        if context.is_skip_to_next_target_requested() {
            context.clear_skip_to_next_target_request();
            tracing::info!(
                "Skipping target '{}' due to pending next-target request",
                config.display_name()
            );
            return NodeStatus::Skipped;
        }

        // Stamping the target onto the context propagates these values down
        // the tree so child instructions (Slew, Center, Autofocus) all share
        // a single source of truth instead of carrying duplicate copies.
        context.target_name = Some(config.target_name.clone());
        context.target_ra = Some(config.ra_hours);
        context.target_dec = Some(config.dec_degrees);
        context.target_rotation = config.rotation;

        let display_name = config.display_name();
        tracing::info!(
            "Starting target: {} (RA: {:.4}h, Dec: {:.4}°)",
            display_name,
            config.ra_hours,
            config.dec_degrees
        );

        let now = chrono::Utc::now().timestamp();

        if let Some(start_after) = config.start_after {
            if now < start_after {
                let wait_secs = start_after - now;
                tracing::info!(
                    "Target {} has start_after constraint, waiting {} seconds",
                    display_name,
                    wait_secs
                );
                match wait_until_timestamp_or_cancel(context, start_after).await {
                    NodeStatus::Success => {}
                    other => return other,
                }
            }
        }

        if let Some(end_before) = config.end_before {
            if now >= end_before {
                tracing::warn!(
                    "Target {} has passed its end_before time, skipping",
                    display_name
                );
                return NodeStatus::Skipped;
            }
        }

        // DriftLimit and MeridianFlip both need the target's RA/Dec stamped
        // into the trigger state. The state stores RA in degrees (so it can
        // match plate-solve outputs directly) while the executor uses hours;
        // hence the *15 conversion at this boundary.
        if let Some(trigger_state_lock) = &context.trigger_state {
            let mut trigger_state = trigger_state_lock.write().await;
            let target_ra_degrees = config.ra_hours * 15.0;
            trigger_state.set_target(target_ra_degrees, config.dec_degrees);
            trigger_state.set_meridian_target(display_name.clone());
            tracing::debug!(
                "Updated trigger state with target: RA={:.4}°, Dec={:.4}°",
                target_ra_degrees,
                config.dec_degrees
            );
        }

        // The MeridianFlip trigger compares now() against the next crossing
        // timestamp; pre-computing it here (once per target) avoids each
        // trigger evaluation recomputing the same sidereal-time math.
        if let (Some(_lat), Some(lon)) = (context.latitude, context.longitude) {
            let now = chrono::Utc::now();
            let meridian_crossing =
                crate::meridian::calculate_meridian_crossing(config.ra_hours, lon, now);

            tracing::debug!(
                "Target {} meridian crossing at {}",
                display_name,
                meridian_crossing
            );

            context
                .set_next_meridian_flip_time(Some(meridian_crossing.timestamp()))
                .await;
        }

        if let Some(min_alt) = config.min_altitude {
            let Some(current_alt) = context.calculate_altitude() else {
                tracing::error!(
                    "Target {} has altitude constraints but missing target coordinates or observer location",
                    display_name
                );
                return NodeStatus::Failure;
            };
            if current_alt < min_alt {
                tracing::warn!(
                    "Target {} is below minimum altitude ({:.1}° < {:.1}°)",
                    display_name,
                    current_alt,
                    min_alt
                );
                return NodeStatus::Skipped;
            }
        }

        if let Some(max_alt) = config.max_altitude {
            let Some(current_alt) = context.calculate_altitude() else {
                tracing::error!(
                    "Target {} has altitude constraints but missing target coordinates or observer location",
                    display_name
                );
                return NodeStatus::Failure;
            };
            if current_alt > max_alt {
                tracing::warn!(
                    "Target {} is above maximum altitude ({:.1}° > {:.1}°)",
                    display_name,
                    current_alt,
                    max_alt
                );
                return NodeStatus::Skipped;
            }
        }

        let result = self.execute_children_sequential(context).await;
        if result == NodeStatus::Skipped && context.is_skip_to_next_target_requested() {
            context.clear_skip_to_next_target_request();
            tracing::info!(
                "Target '{}' interrupted by next-target request",
                display_name
            );
            return NodeStatus::Skipped;
        }

        result
    }

    /// Execute a loop node
    async fn execute_loop(
        &mut self,
        config: LoopConfig,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        self.current_iteration = 0;

        // Count-based loops have an explicit upper bound; condition-based loops
        // (UntilTime, AltitudeBelow, WhileDark, etc.) terminate via runtime
        // checks inside the loop body, so the bound stays effectively infinite.
        let max_iterations = match config.condition {
            // Why (audit-rust §4.3): `iterations: Option<u32>` — semantically REQUIRED
            // when condition == Count, optional otherwise. UI builder enforces this; the
            // `unwrap_or(1)` is a safety floor to prevent an infinite loop on a
            // legacy/corrupt sequence file where Count was selected without iterations.
            // A single execution is the safest interpretation of "Count with no count".
            LoopCondition::Count => config.iterations.unwrap_or(1),
            _ => u32::MAX,
        };

        loop {
            if context.is_cancelled().await {
                return NodeStatus::Cancelled;
            }
            if context.is_skip_to_next_target_requested() {
                return NodeStatus::Skipped;
            }

            let should_continue = match config.condition {
                LoopCondition::Count => self.current_iteration < max_iterations,
                LoopCondition::UntilTime => {
                    if let Some(until) = config.condition_value {
                        // Why: condition_value is f64 carrying a Unix timestamp;
                        // year 2038 is ~2.1e9 (< 2^31), still 1000x below f64
                        // precision limit. f64 -> i64 saturates per Rust 1.45 spec.
                        chrono::Utc::now().timestamp() < (until as i64)
                    } else {
                        false
                    }
                }
                LoopCondition::AltitudeBelow => {
                    if let Some(threshold) = config.condition_value {
                        let Some(current_alt) = context.calculate_altitude() else {
                            tracing::error!(
                                "Loop condition AltitudeBelow requires target coordinates and observer location"
                            );
                            return NodeStatus::Failure;
                        };
                        current_alt >= threshold
                    } else {
                        false
                    }
                }
                LoopCondition::AltitudeAbove => {
                    if let Some(threshold) = config.condition_value {
                        let Some(current_alt) = context.calculate_altitude() else {
                            tracing::error!(
                                "Loop condition AltitudeAbove requires target coordinates and observer location"
                            );
                            return NodeStatus::Failure;
                        };
                        current_alt <= threshold
                    } else {
                        false
                    }
                }
                LoopCondition::IntegrationTime => {
                    if let Some(target_secs) = config.condition_value {
                        let integrated_secs = context.get_completed_integration_secs().await;
                        integrated_secs < target_secs
                    } else {
                        false
                    }
                }
                LoopCondition::Forever => true,
                LoopCondition::WhileDark => {
                    let Some(is_dark) = context.is_dark() else {
                        tracing::error!(
                            "Loop condition WhileDark requires observer latitude/longitude"
                        );
                        return NodeStatus::Failure;
                    };
                    is_dark
                }
            };

            if !should_continue {
                break;
            }

            self.current_iteration += 1;
            tracing::info!("=== LOOP ITERATION {} STARTING ===", self.current_iteration);
            tracing::info!("Loop has {} children", self.children.len());
            for (i, child) in self.children.iter().enumerate() {
                tracing::info!("  Child {}: '{}' (id={})", i, child.name(), child.id());
            }

            let total_children = match config.condition {
                // Why: max_iterations is u32 -> usize widening (lossless on >=32-bit platforms).
                LoopCondition::Count => Some(max_iterations as usize),
                _ => None,
            };

            context.send_progress(ProgressUpdate {
                node_id: self.id().clone(),
                status: NodeStatus::Running,
                message: Some(format!("Loop iteration {}", self.current_iteration)),
                current_frame: None,
                total_frames: None,
                // Why: current_iteration is u32 -> usize widening (lossless).
                current_child: Some(self.current_iteration as usize),
                total_children,
                completed_exposure_secs: None,
            });

            // Children retain Success/Failure from the previous iteration and
            // would short-circuit on the next pass; resetting them per-iter is
            // what makes a Loop actually re-execute its body rather than just
            // re-walking the same completed nodes.
            tracing::info!(
                "Resetting {} children for iteration {}",
                self.children.len(),
                self.current_iteration
            );
            for child in &mut self.children {
                child.reset();
            }
            tracing::info!("Children reset complete");

            tracing::info!(
                "Starting execute_children_sequential for iteration {}",
                self.current_iteration
            );
            let result = self.execute_children_sequential(context).await;
            tracing::info!(
                "execute_children_sequential completed with result: {:?}",
                result
            );
            if result == NodeStatus::Skipped && context.is_skip_to_next_target_requested() {
                return NodeStatus::Skipped;
            }
            if result == NodeStatus::Failure || result == NodeStatus::Cancelled {
                return result;
            }
        }

        NodeStatus::Success
    }

    /// Execute a parallel node with true concurrent execution
    async fn execute_parallel(
        &mut self,
        config: ParallelConfig,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        use std::sync::atomic::AtomicUsize;
        use tokio::sync::Mutex as TokioMutex;

        let total_children = self.children.len();
        if total_children == 0 {
            return NodeStatus::Success;
        }

        // Why (audit-rust §4.3): `required_successes: Option<u32>` — the documented
        // semantics on the config field are "None means all children must succeed",
        // which matches the parallel-AND default. `total_children` is the documented
        // default value for this case.
        let required = config.required_successes.unwrap_or(total_children);
        let node_id = self.id().clone();

        context.send_progress(ProgressUpdate {
            node_id: node_id.clone(),
            status: NodeStatus::Running,
            message: Some(format!("Running {} parallel branches", total_children)),
            current_frame: None,
            total_frames: None,
            current_child: Some(0),
            total_children: Some(total_children),
            completed_exposure_secs: None,
        });

        let success_count = Arc::new(AtomicUsize::new(0));
        let cancelled = Arc::new(AtomicBool::new(false));

        // Children are owned by &mut self but the spawned tasks need 'static
        // lifetimes; wrapping each in Arc<Mutex<_>> lets them survive a
        // join_all without cloning the underlying Node. They are unwrapped
        // back into the children Vec below after every task completes.
        let children = std::mem::take(&mut self.children);
        let children: Vec<Arc<TokioMutex<Box<dyn Node>>>> = children
            .into_iter()
            .map(|c| Arc::new(TokioMutex::new(c)))
            .collect();

        let is_cancelled = context.is_cancelled.clone();
        let is_paused = context.is_paused.clone();
        let resume_notify = context.resume_notify.clone();
        let device_ops = context.device_ops.clone();
        let completed_integration = context.completed_integration_secs.clone();
        let target_ra = context.target_ra;
        let target_dec = context.target_dec;
        let target_name = context.target_name.clone();
        let target_rotation = context.target_rotation;
        let current_filter = context.current_filter.clone();
        let current_binning = context.current_binning;
        let camera_id = context.camera_id.clone();
        let mount_id = context.mount_id.clone();
        let focuser_id = context.focuser_id.clone();
        let filterwheel_id = context.filterwheel_id.clone();
        let rotator_id = context.rotator_id.clone();
        let dome_id = context.dome_id.clone();
        let cover_calibrator_id = context.cover_calibrator_id.clone();
        let save_path = context.save_path.clone();
        let latitude = context.latitude;
        let longitude = context.longitude;
        let safety_fail_mode = context.safety_fail_mode;
        let skip_to_next_target = context.skip_to_next_target.clone();
        let skip_to_node = context.skip_to_node.clone();
        let trigger_state = context.trigger_state.clone();
        let filter_focus_offsets = context.filter_focus_offsets.clone();
        let event_tx = context.event_tx.clone();

        let handles: Vec<_> = children
            .iter()
            .enumerate()
            .map(|(i, child)| {
                let child = child.clone();
                let success_count = success_count.clone();
                let cancelled = cancelled.clone();
                let is_cancelled = is_cancelled.clone();
                let is_paused = is_paused.clone();
                let resume_notify = resume_notify.clone();
                let device_ops = device_ops.clone();
                let completed_integration = completed_integration.clone();
                let node_id = node_id.clone();
                let target_name = target_name.clone();
                let current_filter = current_filter.clone();
                let camera_id = camera_id.clone();
                let mount_id = mount_id.clone();
                let focuser_id = focuser_id.clone();
                let filterwheel_id = filterwheel_id.clone();
                let rotator_id = rotator_id.clone();
                let dome_id = dome_id.clone();
                let cover_calibrator_id = cover_calibrator_id.clone();
                let save_path = save_path.clone();
                let skip_to_next_target = skip_to_next_target.clone();
                let skip_to_node = skip_to_node.clone();
                let trigger_state = trigger_state.clone();
                let filter_focus_offsets = filter_focus_offsets.clone();
                let event_tx = event_tx.clone();

                tokio::spawn(async move {
                    if is_cancelled.load(Ordering::Relaxed) || cancelled.load(Ordering::Relaxed) {
                        return (i, NodeStatus::Cancelled);
                    }

                    // Each branch gets a fresh ExecutionContext clone with the
                    // branch index in node_id; this isolates per-branch state
                    // (e.g. instruction-level node_id strings) while still
                    // sharing the parent's atomic flags and trigger state.
                    let mut branch_context = ExecutionContext {
                        node_id: format!("{}_branch_{}", node_id, i),
                        target_ra,
                        target_dec,
                        target_name,
                        target_rotation,
                        current_filter,
                        current_binning,
                        is_cancelled: is_cancelled.clone(),
                        is_paused,
                        skip_to_next_target,
                        skip_to_node,
                        resume_notify,
                        progress_callback: None,
                        polar_align_image_callback: None,
                        camera_id,
                        mount_id,
                        focuser_id,
                        filterwheel_id,
                        rotator_id,
                        dome_id,
                        cover_calibrator_id,
                        save_path,
                        latitude,
                        longitude,
                        device_ops,
                        completed_integration_secs: completed_integration,
                        trigger_state,
                        safety_fail_mode,
                        filter_focus_offsets,
                        event_tx,
                    };

                    let mut child_guard = child.lock().await;
                    let result = child_guard.execute(&mut branch_context).await;

                    match result {
                        NodeStatus::Success => {
                            success_count.fetch_add(1, Ordering::Relaxed);
                        }
                        NodeStatus::Cancelled => {
                            cancelled.store(true, Ordering::Relaxed);
                        }
                        _ => {}
                    }

                    (i, result)
                })
            })
            .collect();

        let _results: Vec<_> = futures::future::join_all(handles)
            .await
            .into_iter()
            .filter_map(|r| r.ok())
            .collect();

        // Restore children from mutex wrappers.
        //
        // Audit §1.12: `Arc::try_unwrap` failure here means another task
        // somewhere is still holding a clone of the child Arc — i.e. the
        // parallel-execution invariant ("all tasks completed before we
        // restore") has been violated. Previously we silently dropped the
        // unrecovered child, which corrupted the node tree without telling
        // the user. Now we surface the violation by returning Failure,
        // matching the audit's "errors are a feature" rule. The unrecovered
        // children are replaced with placeholder Failed nodes so subsequent
        // walks of `self.children` still see a structurally valid tree
        // (length and order preserved) and the next execute() call cannot
        // misindex.
        let mut restored_children = Vec::with_capacity(children.len());
        let mut unrecovered = 0usize;
        for child_mutex in children {
            match Arc::try_unwrap(child_mutex) {
                Ok(mutex) => {
                    restored_children.push(mutex.into_inner());
                }
                Err(_arc) => {
                    // Why: see audit §1.12. We cannot un-Arc a still-shared
                    // child without ub'ing — the only safe choice is to
                    // (a) record the failure for the caller and (b) leave
                    // a stand-in so tree shape stays valid.
                    tracing::error!(
                        "[NODE_TREE] Failed to reclaim child from parallel execution; a spawned task is still holding the Arc. \
                         This is a logical-impossibility violation — returning Failure so the user is told."
                    );
                    unrecovered += 1;
                    let placeholder_def = NodeDefinition {
                        id: format!("__unrecovered_child_{}", unrecovered),
                        name: "Unrecovered parallel child".to_string(),
                        // Why: a unit-variant NodeType keeps the placeholder
                        // small and unambiguous. Park is a no-op for the
                        // walker; the surrounding NodeStatus::Failure return
                        // is the actual signal to the caller.
                        node_type: NodeType::Park,
                        enabled: false,
                        children: Vec::new(),
                    };
                    let placeholder = RuntimeNode::from_definition(placeholder_def);
                    restored_children.push(Box::new(placeholder));
                }
            }
        }
        self.children = restored_children;
        if unrecovered > 0 {
            return NodeStatus::Failure;
        }

        if is_cancelled.load(Ordering::Relaxed) || cancelled.load(Ordering::Relaxed) {
            return NodeStatus::Cancelled;
        }

        let successes = success_count.load(Ordering::Relaxed);

        context.send_progress(ProgressUpdate {
            node_id: node_id.clone(),
            status: if successes >= required {
                NodeStatus::Success
            } else {
                NodeStatus::Failure
            },
            message: Some(format!(
                "{}/{} branches succeeded",
                successes, total_children
            )),
            current_frame: None,
            total_frames: None,
            current_child: Some(total_children),
            total_children: Some(total_children),
            completed_exposure_secs: None,
        });

        if successes >= required {
            NodeStatus::Success
        } else {
            tracing::warn!(
                "Parallel node: only {}/{} branches succeeded, required {}",
                successes,
                total_children,
                required
            );
            NodeStatus::Failure
        }
    }

    /// Execute a conditional node
    async fn execute_conditional(
        &mut self,
        config: ConditionalConfig,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        let condition_met = match &config.condition {
            ConditionalCheck::Always => true,
            ConditionalCheck::AltitudeAbove(min_alt) => {
                let Some(current_alt) = context.calculate_altitude() else {
                    tracing::error!(
                        "Conditional AltitudeAbove requires target coordinates and observer location"
                    );
                    return NodeStatus::Failure;
                };
                current_alt > *min_alt
            }
            ConditionalCheck::TimeAfter(after) => chrono::Utc::now().timestamp() > *after,
            ConditionalCheck::GuidingRmsBelow(threshold) => {
                match context.device_ops.guider_get_status().await {
                    Ok(status) => status.rms_total < *threshold,
                    Err(e) => {
                        tracing::warn!(
                            "Guiding RMS condition check failed (threshold {:.2}): {}",
                            threshold,
                            e
                        );
                        false
                    }
                }
            }
            ConditionalCheck::HfrBelow(threshold) => {
                let current_hfr = if let Some(trigger_state_lock) = &context.trigger_state {
                    let trigger_state = trigger_state_lock.read().await;
                    trigger_state.current_hfr
                } else {
                    None
                };

                match current_hfr {
                    Some(hfr) => hfr < *threshold,
                    None => {
                        tracing::warn!(
                            "HFR condition check requested but no current HFR sample is available"
                        );
                        false
                    }
                }
            }
            ConditionalCheck::WeatherSafe => match context.device_ops.safety_is_safe(None).await {
                Ok(is_safe) => {
                    if !is_safe {
                        tracing::warn!("Weather safety check failed - conditions unsafe");
                    }
                    is_safe
                }
                Err(e) => match context.safety_fail_mode {
                    SafetyFailMode::FailOpen => {
                        tracing::warn!(
                            "Weather safety check error: {} - treating as safe (fail-open)",
                            e
                        );
                        true
                    }
                    SafetyFailMode::FailClosed => {
                        tracing::warn!(
                            "Weather safety check error: {} - treating as unsafe (fail-closed)",
                            e
                        );
                        false
                    }
                    SafetyFailMode::WarnOnly => {
                        tracing::warn!(
                                    "Weather safety check error: {} - treating as safe with warning (warn-only)",
                                    e
                                );
                        true
                    }
                },
            },
            ConditionalCheck::MoonSeparationAbove(degrees) => {
                let Some(separation) = context.calculate_moon_separation() else {
                    tracing::error!("Conditional MoonSeparationAbove requires target coordinates");
                    return NodeStatus::Failure;
                };
                separation > *degrees
            }
            ConditionalCheck::SafetyMonitorSafe => {
                // Passing None routes the check to the profile-configured
                // safety monitor; individual safety_id targeting is reserved
                // for future multi-monitor configurations.
                match context.device_ops.safety_is_safe(None).await {
                    Ok(is_safe) => {
                        if !is_safe {
                            tracing::warn!("Safety monitor reports unsafe conditions");
                        }
                        is_safe
                    }
                    Err(e) => match context.safety_fail_mode {
                        SafetyFailMode::FailOpen => {
                            tracing::warn!(
                                "Safety monitor check error: {} - treating as safe (fail-open)",
                                e
                            );
                            true
                        }
                        SafetyFailMode::FailClosed => {
                            tracing::warn!(
                                "Safety monitor check error: {} - treating as unsafe (fail-closed)",
                                e
                            );
                            false
                        }
                        SafetyFailMode::WarnOnly => {
                            tracing::warn!(
                                    "Safety monitor check error: {} - treating as safe with warning (warn-only)",
                                    e
                                );
                            true
                        }
                    },
                }
            }
        };

        if condition_met {
            self.execute_children_sequential(context).await
        } else {
            tracing::info!("Conditional check failed, skipping children");
            NodeStatus::Skipped
        }
    }

    /// Execute a recovery node
    ///
    /// Retries child nodes up to `max_retries` times with exponential backoff
    /// (1s, 2s, 4s, 8s, ...) between attempts. After exhausting all retries,
    /// the configured recovery action determines the final outcome.
    async fn execute_recovery(
        &mut self,
        config: RecoveryConfig,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        let mut attempts = 0;
        let max_attempts = config.max_retries.max(1);

        loop {
            attempts += 1;
            tracing::info!("Execution attempt {}/{}", attempts, max_attempts);

            // Like Loop, each retry needs a fresh slate — keeping stale
            // Success/Failure on children would let a flaky middle child
            // short-circuit on the second attempt before its real cause was
            // actually retried.
            for child in &mut self.children {
                child.reset();
            }

            let result = self.execute_children_sequential(context).await;

            if result == NodeStatus::Success || result == NodeStatus::Cancelled {
                return result;
            }

            if attempts >= max_attempts {
                tracing::warn!(
                    "Max recovery attempts ({}) reached, propagating failure",
                    max_attempts
                );
                return match config.recovery_action {
                    RecoveryAction::Continue => NodeStatus::Success,
                    RecoveryAction::NextTarget => NodeStatus::Skipped,
                    RecoveryAction::ParkAndAbort => {
                        // Trust-patch §8: both ParkAndAbort recovery paths
                        // (here and in executor.rs) now route through
                        // `device_ops::try_park_with_retry` so park behaviour
                        // is consistent. The retry parameters match the
                        // executor's policy (1 retry, 2s delay) — both call
                        // sites can be tuned together if the operator profile
                        // ever exposes them.
                        //
                        // The previous `execute_park` instruction was a
                        // single-attempt fire-and-forget; using the helper
                        // turns the recovery into a structured "park retried,
                        // park failed" event the UI can surface.
                        if let Some(mount_id) = &context.mount_id {
                            tracing::warn!(
                                "Recovery::ParkAndAbort: parking mount '{}' (max_retries=1, retry_delay=2s)",
                                mount_id
                            );
                            let park_outcome =
                                crate::device_ops::try_park_with_retry(
                                    &context.device_ops,
                                    mount_id,
                                    1,
                                    2.0,
                                )
                                .await;
                            if !park_outcome.success {
                                let park_error = format!(
                                    "Recovery::ParkAndAbort: mount park FAILED after {} attempt(s): {}. \
                                     Mount may be in an unsafe position — manual intervention required.",
                                    park_outcome.attempts_made,
                                    park_outcome
                                        .last_error
                                        .clone()
                                        .unwrap_or_else(|| "unknown error".to_string()),
                                );
                                tracing::error!("{}", park_error);
                                if let Some(tx) = &context.event_tx {
                                    let _ = tx.send(ExecutorEvent::Error {
                                        message: park_error,
                                    });
                                }
                            }
                        } else {
                            tracing::error!(
                                "Recovery::ParkAndAbort fired but no mount is configured; the rig cannot be parked automatically."
                            );
                            if let Some(tx) = &context.event_tx {
                                let _ = tx.send(ExecutorEvent::Error {
                                    message: "Recovery::ParkAndAbort fired but no mount is configured; the rig cannot be parked automatically.".to_string(),
                                });
                            }
                        }
                        NodeStatus::Failure
                    }
                    _ => NodeStatus::Failure,
                };
            }

            // Exponential backoff (1, 2, 4, 8, …, 64 s) gives transient device
            // faults — driver reconnects, USB hiccups — a chance to clear while
            // capping the wait so the user does not stare at a frozen sequence.
            // `attempts - 1` because attempts is 1-based and the first retry
            // should wait the minimum 1 s, not 2 s.
            let backoff_secs = 1u64 << (attempts - 1).min(6);
            tracing::info!(
                "Waiting {}s before retry attempt {}/{}",
                backoff_secs,
                attempts + 1,
                max_attempts
            );

            // The backoff sleep must remain cancellable — a 64 s wait that
            // ignores Stop would leave the user staring at a "stopping…" UI.
            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_secs(backoff_secs)) => {}
                _ = async {
                    loop {
                        if context.is_cancelled.load(Ordering::Relaxed) {
                            return;
                        }
                        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                    }
                } => {
                    tracing::info!("Recovery cancelled during backoff wait");
                    return NodeStatus::Cancelled;
                }
            }

            match &config.recovery_action {
                RecoveryAction::Retry { .. } => {
                    tracing::info!("Retrying...");
                }
                RecoveryAction::Autofocus => {
                    let autofocus_config = match self.configured_recovery_autofocus() {
                        Some(config) => config,
                        None => {
                            tracing::error!(
                                "Recovery action requested autofocus but no enabled autofocus child is configured"
                            );
                            return NodeStatus::Failure;
                        }
                    };
                    tracing::info!("Running recovery autofocus...");
                    let ctx = context.to_instruction_context().await;
                    let autofocus_result = execute_autofocus(&autofocus_config, &ctx, None).await;
                    match autofocus_result.status {
                        NodeStatus::Success => {}
                        NodeStatus::Cancelled => return NodeStatus::Cancelled,
                        _ => return autofocus_result.log_and_get_status("Recovery autofocus"),
                    }
                }
                RecoveryAction::Pause => {
                    tracing::info!("Pausing for manual intervention...");
                    if !context.pause_and_wait_for_resume().await {
                        return NodeStatus::Cancelled;
                    }
                    tracing::info!("Resumed after pause, retrying...");
                }
                _ => {}
            }
        }
    }

    /// Execute children in sequence
    async fn execute_children_sequential(&mut self, context: &mut ExecutionContext) -> NodeStatus {
        let total = self.children.len();
        let node_id = self.id().clone();

        tracing::debug!(
            "execute_children_sequential: node {} has {} children",
            node_id,
            total
        );

        if total == 0 {
            tracing::warn!("Node {} has no children to execute", node_id);
            return NodeStatus::Success;
        }

        tracing::info!("About to enter for loop with {} children", total);

        for (i, child) in self.children.iter_mut().enumerate() {
            tracing::info!("FOR LOOP ENTERED: iteration {} of {}", i, total);

            if context.is_cancelled().await {
                tracing::debug!("Execution cancelled before child {}", i);
                return NodeStatus::Cancelled;
            }
            if context.is_skip_to_next_target_requested() {
                tracing::info!(
                    "Skipping remaining children in node {} due to next-target request",
                    node_id
                );
                return NodeStatus::Skipped;
            }

            // Trust-patch §7: if a SkipToNode request is active, mark this
            // child as Skipped unless its subtree contains the target. When
            // the child IS the target (or contains it), the request stays
            // pending so deeper recursion can keep skipping siblings; we
            // only clear it when the executor reaches the target node
            // itself (handled by the early-return below).
            if let Some(ref target_id) = context.skip_to_node_target() {
                if child.id() == target_id {
                    // We reached the target node — clear the request and
                    // let normal execution take over from here.
                    tracing::info!(
                        "[SKIP_TO_NODE] Reached target '{}'; clearing request and resuming normal execution",
                        target_id
                    );
                    context.clear_skip_to_node_request();
                    // Fall through to normal child.execute below.
                } else if !child.contains_node(target_id) {
                    tracing::info!(
                        "[SKIP_TO_NODE] Skipping child '{}' (id={}) — target '{}' is not in this subtree",
                        child.name(),
                        child.id(),
                        target_id
                    );
                    context.send_progress(ProgressUpdate {
                        node_id: child.id().clone(),
                        status: NodeStatus::Skipped,
                        message: Some(format!(
                            "Skipped by SkipToNode request (target: {})",
                            target_id
                        )),
                        current_frame: None,
                        total_frames: None,
                        current_child: Some(i),
                        total_children: Some(total),
                        completed_exposure_secs: None,
                    });
                    continue;
                }
                // else: the target is somewhere INSIDE this child's
                // subtree, but is not this child itself. Fall through to
                // execute the child normally — the recursive skip logic
                // inside the child will keep filtering siblings until the
                // target is reached.
            }

            tracing::info!(
                "Executing child {}/{}: '{}' (id={})",
                i + 1,
                total,
                child.name(),
                child.id()
            );

            context.send_progress(ProgressUpdate {
                node_id: node_id.clone(),
                status: NodeStatus::Running,
                message: Some(format!("Step {}/{}: {}", i + 1, total, child.name())),
                current_frame: None,
                total_frames: None,
                current_child: Some(i),
                total_children: Some(total),
                completed_exposure_secs: None,
            });

            let result = child.execute(context).await;

            tracing::info!(
                "Child '{}' completed with status: {:?}",
                child.name(),
                result
            );

            if result == NodeStatus::Skipped && context.is_skip_to_next_target_requested() {
                return NodeStatus::Skipped;
            }
            if result == NodeStatus::Failure || result == NodeStatus::Cancelled {
                return result;
            }
        }

        NodeStatus::Success
    }
}

async fn wait_until_timestamp_or_cancel(
    context: &ExecutionContext,
    target_timestamp: i64,
) -> NodeStatus {
    loop {
        if context.is_cancelled.load(Ordering::Relaxed) {
            tracing::info!("Cancelled while waiting for scheduled start time");
            return NodeStatus::Cancelled;
        }
        if context.is_skip_to_next_target_requested() {
            tracing::info!("Skip requested while waiting for scheduled start time");
            return NodeStatus::Skipped;
        }

        let now = chrono::Utc::now().timestamp();
        if now >= target_timestamp {
            return NodeStatus::Success;
        }

        // Why: `.min(1)` clamps to [_, 1] i64; the `now >= target_timestamp`
        // check above guarantees the difference is positive, so i64 -> u64 is
        // lossless. The clamp keeps the wait granular for cancellation polling.
        let sleep_secs = u64::try_from((target_timestamp - now).min(1)).unwrap_or(0);
        tokio::time::sleep(std::time::Duration::from_secs(sleep_secs.max(1))).await;
    }
}

// ============================================================================
// Astronomical Helper Functions
// ============================================================================

// Audit §1.6: deleted `julian_day` and `local_sidereal_time` duplicates.
// Re-exported from `crate::meridian` so existing call sites
// (`crate::node::julian_day`, `crate::node::local_sidereal_time`) keep
// working with a single source of truth.
pub use crate::meridian::{julian_day, local_sidereal_time};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        AutofocusConfig, NodeDefinition, RecoveryAction, RecoveryConfig, TargetHeaderConfig,
    };

    #[test]
    fn test_execution_context_creation() {
        let ctx = ExecutionContext::new("test_node".to_string());
        assert_eq!(ctx.node_id, "test_node");
        assert!(ctx.target_ra.is_none());
        assert!(ctx.target_dec.is_none());
        assert!(ctx.camera_id.is_none());
    }

    /// Trust-patch §7: ExecutionContext exposes SkipToNode plumbing via
    /// `set_skip_to_node_request` / `skip_to_node_target` /
    /// `clear_skip_to_node_request`. The slot must round-trip and the
    /// clear must take effect.
    #[test]
    fn trust_patch_7_skip_to_node_request_roundtrip() {
        let ctx = ExecutionContext::new("root".to_string());
        assert!(ctx.skip_to_node_target().is_none());
        ctx.set_skip_to_node_request("target_node".to_string());
        assert_eq!(ctx.skip_to_node_target().as_deref(), Some("target_node"));
        ctx.clear_skip_to_node_request();
        assert!(ctx.skip_to_node_target().is_none());
    }

    /// Trust-patch §7: `Node::contains_node` (default impl on the trait)
    /// reports whether the subtree rooted at `self` contains `node_id`.
    /// Verified against a small two-level tree built from NodeDefinition.
    #[test]
    fn trust_patch_7_contains_node_walks_subtree() {
        use crate::{DelayConfig, NodeId, NodeType};

        let leaf = NodeDefinition {
            id: "leaf".to_string(),
            name: "Leaf".to_string(),
            node_type: NodeType::Delay(DelayConfig::default()),
            enabled: true,
            children: vec![],
        };
        let root = NodeDefinition {
            id: "root".to_string(),
            name: "Root".to_string(),
            node_type: NodeType::Delay(DelayConfig::default()),
            enabled: true,
            children: vec![],
        };

        let mut root_node = RuntimeNode::from_definition(root);
        root_node.add_child(Box::new(RuntimeNode::from_definition(leaf)));

        let leaf_id: NodeId = "leaf".to_string();
        let root_id: NodeId = "root".to_string();
        let missing_id: NodeId = "missing".to_string();

        assert!(root_node.contains_node(&root_id));
        assert!(root_node.contains_node(&leaf_id));
        assert!(!root_node.contains_node(&missing_id));
    }

    #[test]
    fn test_execution_context_with_target() {
        let ctx = ExecutionContext::new("test_node".to_string()).with_target(
            "M31".to_string(),
            10.68,
            41.27,
            Some(45.0),
        );

        assert_eq!(ctx.target_name, Some("M31".to_string()));
        assert_eq!(ctx.target_ra, Some(10.68));
        assert_eq!(ctx.target_dec, Some(41.27));
        assert_eq!(ctx.target_rotation, Some(45.0));
    }

    #[test]
    fn test_execution_context_cancellation() {
        let ctx = ExecutionContext::new("test_node".to_string());

        assert!(!ctx.is_cancelled.load(Ordering::Relaxed));
        ctx.is_cancelled.store(true, Ordering::Relaxed);
        assert!(ctx.is_cancelled.load(Ordering::Relaxed));
    }

    #[test]
    fn test_execution_context_pause() {
        let ctx = ExecutionContext::new("test_node".to_string());

        assert!(!ctx.is_paused.load(Ordering::Relaxed));
        ctx.is_paused.store(true, Ordering::Relaxed);
        assert!(ctx.is_paused.load(Ordering::Relaxed));
    }

    #[test]
    fn test_progress_update_creation() {
        let update = ProgressUpdate {
            node_id: "node1".to_string(),
            status: NodeStatus::Running,
            message: Some("Capturing frame".to_string()),
            current_frame: Some(5),
            total_frames: Some(10),
            current_child: None,
            total_children: None,
            completed_exposure_secs: Some(60.0),
        };

        assert_eq!(update.node_id, "node1");
        assert_eq!(update.status, NodeStatus::Running);
        assert_eq!(update.current_frame, Some(5));
        assert_eq!(update.total_frames, Some(10));
        assert_eq!(update.completed_exposure_secs, Some(60.0));
    }

    #[test]
    fn test_julian_day_calculation() {
        // Test J2000 epoch: January 1, 2000 at 12:00 UT
        use chrono::{TimeZone, Utc};

        let dt = Utc.with_ymd_and_hms(2000, 1, 1, 12, 0, 0).unwrap();

        let jd = julian_day(&dt);
        // J2000 epoch should be exactly 2451545.0
        assert!((jd - 2451545.0).abs() < 0.001);
    }

    #[test]
    fn test_julian_day_another_epoch() {
        // Test another known date
        use chrono::{TimeZone, Utc};

        let dt = Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap();

        let jd = julian_day(&dt);
        // JD for Jan 1, 2024 at 0:00 UT should be approximately 2460310.5
        assert!((jd - 2460310.5).abs() < 0.1);
    }

    #[test]
    fn test_local_sidereal_time() {
        // At J2000 epoch at Greenwich (longitude 0), GMST should be close to 18.697 hours
        let jd = 2451545.0;
        let lst = local_sidereal_time(jd, 0.0);

        // LST at J2000 at Greenwich should be approximately 18.697 hours
        assert!(lst > 18.0 && lst < 19.0);
    }

    #[test]
    fn test_local_sidereal_time_with_longitude() {
        let jd = 2451545.0;

        // LST should increase eastward
        let lst_greenwich = local_sidereal_time(jd, 0.0);
        let lst_east = local_sidereal_time(jd, 15.0); // 15 degrees east = 1 hour difference

        // East should be about 1 hour ahead (difference should be ~1 hour)
        let diff = lst_east - lst_greenwich;
        assert!((diff - 1.0).abs() < 0.1 || (diff + 23.0).abs() < 0.1); // Handle wrap
    }

    #[test]
    fn recovery_autofocus_uses_configured_child() {
        let mut recovery_node = RuntimeNode::from_definition(NodeDefinition {
            id: "recovery".to_string(),
            name: "Recovery".to_string(),
            node_type: NodeType::Recovery(RecoveryConfig {
                recovery_action: RecoveryAction::Autofocus,
                ..RecoveryConfig::default()
            }),
            enabled: true,
            children: vec![],
        });
        recovery_node.add_child(Box::new(RuntimeNode::from_definition(NodeDefinition {
            id: "autofocus".to_string(),
            name: "Autofocus".to_string(),
            node_type: NodeType::Autofocus(AutofocusConfig {
                step_size: 321,
                exposure_duration: 7.5,
                ..AutofocusConfig::default()
            }),
            enabled: true,
            children: vec![],
        })));

        let autofocus = recovery_node
            .configured_recovery_autofocus()
            .expect("recovery node should find autofocus child");

        assert_eq!(autofocus.step_size, 321);
        assert_eq!(autofocus.exposure_duration, 7.5);
    }

    #[test]
    fn wait_until_timestamp_or_cancel_stops_on_skip_request() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let ctx = ExecutionContext::new("test_node".to_string());
            ctx.request_skip_to_next_target();

            let result =
                wait_until_timestamp_or_cancel(&ctx, chrono::Utc::now().timestamp() + 60).await;

            assert_eq!(result, NodeStatus::Skipped);
        });
    }

    #[test]
    fn target_header_wait_is_cancellable() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let mut node = RuntimeNode::from_definition(NodeDefinition {
                id: "target".to_string(),
                name: "Target".to_string(),
                node_type: NodeType::TargetHeader(TargetHeaderConfig {
                    target_name: "M31".to_string(),
                    ra_hours: 1.0,
                    dec_degrees: 2.0,
                    start_after: Some(chrono::Utc::now().timestamp() + 60),
                    ..TargetHeaderConfig::default()
                }),
                enabled: true,
                children: vec![],
            });
            let mut ctx = ExecutionContext::new("target".to_string());
            ctx.is_cancelled.store(true, Ordering::Relaxed);

            let result = node.execute(&mut ctx).await;
            assert_eq!(result, NodeStatus::Cancelled);
        });
    }

    #[test]
    fn sun_ra_helper_stays_finite_and_normalized() {
        for days_since_j2000 in (-3650..=3650).step_by(137) {
            // Why: test fixture; days_since_j2000 is i32 in (-3650, 3650), lossless to f64.
            let (sun_ra, sun_dec) = approximate_sun_equatorial_coords(f64::from(days_since_j2000));
            assert!(sun_ra.is_finite());
            assert!(sun_dec.is_finite());
            assert!((0.0..24.0).contains(&sun_ra));
        }
    }

    // §1.2 — Verify the HFR median computation is a true median, not the
    // exponentially-weighted moving average the previous code computed.
    #[test]
    fn hfr_median_returns_true_central_value() {
        let values = [1.5, 1.6, 1.7, 1.8, 5.0];
        let median = compute_hfr_median(&values).expect("expected Some median for non-empty input");
        // The previous EMA implementation returned ~3.2 for this input
        // ((((1.5 + 1.6) / 2 + 1.7) / 2 + 1.8) / 2 + 5.0) / 2 ≈ 3.181), so this
        // assertion both pins the new behaviour and guards against a regression
        // back to the EMA formula.
        assert!(
            (median - 1.7).abs() < f64::EPSILON,
            "expected 1.7, got {median}"
        );
    }

    // §1.2 — Verify NaN and non-positive values are filtered before the median
    // is computed; sorting with `partial_cmp` requires no NaNs in the slice.
    #[test]
    fn hfr_median_filters_nan_and_non_positive() {
        // Empty / all-invalid input → None.
        assert_eq!(compute_hfr_median(&[]), None);
        assert_eq!(compute_hfr_median(&[f64::NAN, 0.0, -1.0]), None);

        // Mixed input: 0.0, NaN, and a negative reading must be discarded
        // before sorting. Remaining values are [2.0, 3.0, 4.0, 5.0]; for an
        // even-length sequence, the median is (3.0 + 4.0) / 2 = 3.5.
        let values = [2.0, f64::NAN, 0.0, 3.0, 4.0, 5.0, -2.5];
        let median = compute_hfr_median(&values).expect("expected median after filtering");
        assert!(
            (median - 3.5).abs() < f64::EPSILON,
            "expected 3.5, got {median}"
        );

        // Odd-length after filtering: [1.5, 1.7, 2.1] → 1.7.
        let values = [1.7, f64::NAN, 1.5, 2.1];
        let median = compute_hfr_median(&values).expect("expected median after filtering");
        assert!(
            (median - 1.7).abs() < f64::EPSILON,
            "expected 1.7, got {median}"
        );
    }

    // §1.1 — Replacing `try_write` with `write().await` must guarantee that
    // every concurrent instruction-side write to the trigger state is
    // observed, even while a fake trigger monitor task is reading every 10 ms.
    // The previous `try_write` storm dropped writes silently on contention
    // with the monitor, causing lost target-name updates among other
    // critical fields.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn trigger_state_writes_are_never_dropped_under_monitor_contention() {
        use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering as AtomicOrdering};
        use tokio::sync::RwLock as TokioRwLock;
        use tokio::time::{sleep, Duration};

        let trigger_state = Arc::new(TokioRwLock::new(crate::triggers::TriggerState::new()));
        let stop = Arc::new(AtomicBool::new(false));
        let monitor_reads = Arc::new(AtomicUsize::new(0));

        // Spawn the fake monitor: read every 10 ms (mirrors the real
        // sequencer trigger monitor's read-cadence) for the lifetime of the
        // test. The read borrows mimic the real trigger evaluator inspecting
        // current state.
        let monitor_state = trigger_state.clone();
        let monitor_stop = stop.clone();
        let monitor_count = monitor_reads.clone();
        let monitor = tokio::spawn(async move {
            while !monitor_stop.load(AtomicOrdering::Relaxed) {
                {
                    let guard = monitor_state.read().await;
                    let _ = guard.current_target_name.clone();
                    let _ = guard.completed_exposures;
                }
                monitor_count.fetch_add(1, AtomicOrdering::Relaxed);
                sleep(Duration::from_millis(10)).await;
            }
        });

        // Spawn 32 instruction tasks. Each task writes a unique target name
        // and increments the exposure counter. Under the old `try_write`
        // implementation, a meaningful fraction of these writes would be
        // lost whenever the monitor held the read lock.
        const WRITERS: usize = 32;
        let mut writers = Vec::with_capacity(WRITERS);
        for i in 0..WRITERS {
            let state = trigger_state.clone();
            writers.push(tokio::spawn(async move {
                let name = format!("Target-{i:02}");
                let mut guard = state.write().await;
                guard.set_meridian_target(name);
                guard.increment_exposure_count();
            }));
        }

        for handle in writers {
            handle.await.expect("writer task must not panic");
        }

        stop.store(true, AtomicOrdering::Relaxed);
        monitor.await.expect("monitor task must not panic");

        // Sanity-check: the monitor actually ran, so write/read contention
        // was real (not a no-op test).
        let reads = monitor_reads.load(AtomicOrdering::Relaxed);
        assert!(
            reads > 0,
            "monitor must have observed at least one read iteration; got {reads}"
        );

        // All 32 writes must be reflected in the counter — this is what the
        // old `try_write` storm broke. `set_meridian_target` only sets the
        // name when it differs from the current one, but
        // `increment_exposure_count` is unconditional, so the counter is the
        // authoritative measure of "writes observed".
        let final_state = trigger_state.read().await;
        // Why: WRITERS is a const usize = 32; trivially fits in u32.
        let writers_u32 = u32::try_from(WRITERS).expect("WRITERS fits in u32");
        assert_eq!(
            final_state.completed_exposures,
            writers_u32,
            "every concurrent writer's increment must be observed; missing {} writes",
            writers_u32 - final_state.completed_exposures
        );
        // And the final target name must be one of the writers' names — i.e.
        // the last write was not silently dropped.
        let name = final_state
            .current_target_name
            .as_ref()
            .expect("current_target_name must be set by at least one writer");
        assert!(
            name.starts_with("Target-"),
            "expected a Target-NN name, got {name:?}"
        );
    }
}
