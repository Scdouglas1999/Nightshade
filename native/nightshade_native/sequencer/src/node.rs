//! Behavior tree node definitions and execution

use crate::{
    device_ops::{NullDeviceOps, SharedDeviceOps},
    instructions::*,
    AutofocusConfig, AutofocusMethod, ConditionalCheck, ConditionalConfig, ExposureConfig,
    LoopCondition, LoopConfig, NodeDefinition, NodeId, NodeStatus, NodeType, ParallelConfig,
    RecoveryAction, RecoveryConfig, SafetyFailMode, TargetHeaderConfig, TriggerAction,
    TriggerCondition,
};
use async_trait::async_trait;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::RwLock;

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
        // Set paused flag
        self.is_paused.store(true, Ordering::Relaxed);
        tracing::info!("Execution paused, waiting for resume...");

        // Wait for either resume or cancellation
        loop {
            tokio::select! {
                _ = self.resume_notify.notified() => {
                    if !self.is_paused.load(Ordering::Relaxed) {
                        tracing::info!("Execution resumed");
                        return true; // Successfully resumed
                    }
                }
                _ = tokio::time::sleep(std::time::Duration::from_millis(100)) => {
                    // Check if cancelled while paused
                    if self.is_cancelled.load(Ordering::Relaxed) {
                        tracing::info!("Cancelled while paused");
                        return false;
                    }
                    // Check if externally resumed (e.g., by executor)
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

        // Get current time
        let now = chrono::Utc::now();

        // Calculate Julian Day
        let jd = julian_day(&now);

        // Calculate Local Sidereal Time
        let lst = local_sidereal_time(jd, lon);

        // Calculate Hour Angle
        let ha = lst - ra_hours;
        let ha_rad = (ha * 15.0).to_radians(); // Convert hours to degrees, then to radians
        let dec_rad = dec_degrees.to_radians();
        let lat_rad = lat.to_radians();

        // Calculate altitude
        let sin_alt = lat_rad.sin() * dec_rad.sin() + lat_rad.cos() * dec_rad.cos() * ha_rad.cos();
        Some(sin_alt.asin().to_degrees())
    }

    /// Calculate separation between target and moon in degrees
    pub fn calculate_moon_separation(&self) -> Option<f64> {
        let target_ra = self.target_ra?;
        let target_dec = self.target_dec?;

        // Calculate approximate moon position
        let now = chrono::Utc::now();
        let jd = julian_day(&now);
        let days = jd - 2451545.0;

        // Simplified lunar position calculation
        let moon_longitude = (218.32 + 13.176396 * days) % 360.0;
        let moon_anomaly = (134.9 + 13.064993 * days) % 360.0;
        let moon_node = (93.3 + 13.229350 * days) % 360.0;

        // Approximate ecliptic latitude and longitude
        let ecl_lon = moon_longitude + 6.29 * moon_anomaly.to_radians().sin()
            - 1.27 * (2.0 * moon_node.to_radians() - moon_anomaly.to_radians()).sin();
        let ecl_lat = 5.13 * moon_node.to_radians().sin();

        // Convert to equatorial coordinates
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

        // Calculate angular separation using spherical law of cosines
        let target_ra_rad = (target_ra * 15.0).to_radians(); // Hours to degrees to radians
        let target_dec_rad = target_dec.to_radians();
        let moon_ra_rad = (moon_ra * 15.0).to_radians();
        let moon_dec_rad = moon_dec.to_radians();

        let cos_sep = target_dec_rad.sin() * moon_dec_rad.sin()
            + target_dec_rad.cos() * moon_dec_rad.cos() * (target_ra_rad - moon_ra_rad).cos();

        Some(cos_sep.acos().to_degrees())
    }

    /// Check if it's currently dark (astronomical twilight has ended)
    pub fn is_dark(&self) -> Option<bool> {
        // Calculate sun altitude
        let lat = self.latitude?;
        let lon = self.longitude?;

        let now = chrono::Utc::now();
        let jd = julian_day(&now);

        let days_since_j2000 = jd - 2451545.0;
        let (sun_ra, sun_dec) = approximate_sun_equatorial_coords(days_since_j2000);

        // Calculate sun altitude
        let lst = local_sidereal_time(jd, lon);
        let ha = lst - sun_ra;
        let ha_rad = (ha * 15.0).to_radians();
        let dec_rad = sun_dec.to_radians();
        let lat_rad = lat.to_radians();

        let sun_alt = (lat_rad.sin() * dec_rad.sin()
            + lat_rad.cos() * dec_rad.cos() * ha_rad.cos())
        .asin()
        .to_degrees();

        // Astronomical twilight is when sun is below -18 degrees
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

        // Get current HFR if available
        let current_hfr = result.hfr_values.last().copied();

        // Get guiding RMS from trigger state
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

        drop(trigger_state); // Release read lock

        // Check each trigger
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
                    // Get drift from trigger state
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

                // Execute trigger action
                match &trigger.action {
                    TriggerAction::PauseAndRecalibrate => {
                        // Pause and wait for manual intervention
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

                        // Request pause and wait
                        let resumed = context.pause_and_wait_for_resume().await;
                        if !resumed {
                            tracing::info!("Cancelled while paused for trigger");
                            return;
                        }
                    }
                    TriggerAction::Autofocus => {
                        // Run autofocus immediately
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

                        // Create autofocus config
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
                        // Pass None for progress callback in trigger-based autofocus
                        let af_result = execute_autofocus(&af_config, &ctx, None).await;

                        if af_result.status == NodeStatus::Success {
                            // Update trigger state with new HFR baseline
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

                        // Set cancelled flag
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

                // Track total integration time after exposure sequence completes
                if result.status == NodeStatus::Success {
                    let total_exposure_time = duration_secs * total_count as f64;
                    {
                        let mut counter = context.completed_integration_secs.write().await;
                        *counter += total_exposure_time;
                    }

                    // Update trigger state with HFR values and exposure counts
                    if let Some(trigger_state_lock) = &context.trigger_state {
                        let mut trigger_state = trigger_state_lock.write().await;
                        if let Some(median_hfr) = compute_hfr_median(&result.hfr_values) {
                            trigger_state.update_hfr(median_hfr);
                            tracing::debug!("Updated trigger state HFR: {:.2}", median_hfr);
                        }

                        // Increment exposure count for periodic triggers
                        for _ in 0..total_count {
                            trigger_state.increment_exposure_count();
                        }
                        tracing::debug!(
                            "Updated trigger state exposure count: {}",
                            trigger_state.completed_exposures
                        );
                    }

                    // Check exposure triggers defined in config
                    self.check_exposure_triggers(config, &result, context).await;

                    // Also send a progress update with the completed exposure time
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
                    // Log failure message so it's not silently discarded
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

                // Update trigger state after autofocus completes
                if result.status == NodeStatus::Success {
                    if let Some(trigger_state_lock) = &context.trigger_state {
                        let mut trigger_state = trigger_state_lock.write().await;
                        // Update HFR baseline after successful autofocus
                        if let Some(best_hfr) = result.hfr_values.first() {
                            trigger_state.update_hfr(*best_hfr);
                            trigger_state.reset_baseline_hfr();
                            tracing::debug!(
                                "Reset HFR baseline to {:.2} after autofocus",
                                best_hfr
                            );
                        }

                        // Mark that autofocus was performed
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

                // Update trigger state after dither completes
                if result.status == NodeStatus::Success {
                    if let Some(trigger_state_lock) = &context.trigger_state {
                        let mut trigger_state = trigger_state_lock.write().await;
                        // Mark that dither was performed
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
            // Propagate to children
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

        // Set target context for child nodes
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

        // Check time constraints
        let now = chrono::Utc::now().timestamp();

        // Check start_after constraint
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

        // Check end_before constraint
        if let Some(end_before) = config.end_before {
            if now >= end_before {
                tracing::warn!(
                    "Target {} has passed its end_before time, skipping",
                    display_name
                );
                return NodeStatus::Skipped;
            }
        }

        // Update trigger state with target coordinates for drift detection
        if let Some(trigger_state_lock) = &context.trigger_state {
            let mut trigger_state = trigger_state_lock.write().await;
            let target_ra_degrees = config.ra_hours * 15.0; // Convert hours to degrees
            trigger_state.set_target(target_ra_degrees, config.dec_degrees);
            trigger_state.set_meridian_target(display_name.clone());
            tracing::debug!(
                "Updated trigger state with target: RA={:.4}°, Dec={:.4}°",
                target_ra_degrees,
                config.dec_degrees
            );
        }

        // Calculate and update meridian flip time for trigger system
        if let (Some(_lat), Some(lon)) = (context.latitude, context.longitude) {
            let now = chrono::Utc::now();
            let meridian_crossing =
                crate::meridian::calculate_meridian_crossing(config.ra_hours, lon, now);

            tracing::debug!(
                "Target {} meridian crossing at {}",
                display_name,
                meridian_crossing
            );

            // Store as Unix timestamp for trigger comparison
            context
                .set_next_meridian_flip_time(Some(meridian_crossing.timestamp()))
                .await;
        }

        // Check altitude if configured
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

        // Execute children in sequence
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

        // Determine max iterations based on condition
        let max_iterations = match config.condition {
            LoopCondition::Count => config.iterations.unwrap_or(1),
            _ => u32::MAX, // Other conditions are checked dynamically
        };

        loop {
            if context.is_cancelled().await {
                return NodeStatus::Cancelled;
            }
            if context.is_skip_to_next_target_requested() {
                return NodeStatus::Skipped;
            }

            // Check loop condition
            let should_continue = match config.condition {
                LoopCondition::Count => self.current_iteration < max_iterations,
                LoopCondition::UntilTime => {
                    if let Some(until) = config.condition_value {
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
                        // Get actual completed integration time from context
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
                LoopCondition::Count => Some(max_iterations as usize),
                _ => None,
            };

            context.send_progress(ProgressUpdate {
                node_id: self.id().clone(),
                status: NodeStatus::Running,
                message: Some(format!("Loop iteration {}", self.current_iteration)),
                current_frame: None,
                total_frames: None,
                current_child: Some(self.current_iteration as usize),
                total_children,
                completed_exposure_secs: None,
            });

            // Reset children for this iteration
            tracing::info!(
                "Resetting {} children for iteration {}",
                self.children.len(),
                self.current_iteration
            );
            for child in &mut self.children {
                child.reset();
            }
            tracing::info!("Children reset complete");

            // Execute children
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

        let required = config.required_successes.unwrap_or(total_children);
        let node_id = self.id().clone();

        // Send initial progress
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

        // Create shared state for tracking results
        let success_count = Arc::new(AtomicUsize::new(0));
        let cancelled = Arc::new(AtomicBool::new(false));

        // Take ownership of children and wrap in Mutex for concurrent access
        let children = std::mem::take(&mut self.children);
        let children: Vec<Arc<TokioMutex<Box<dyn Node>>>> = children
            .into_iter()
            .map(|c| Arc::new(TokioMutex::new(c)))
            .collect();

        // Create shared context values
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
        let trigger_state = context.trigger_state.clone();
        let filter_focus_offsets = context.filter_focus_offsets.clone();

        // Spawn tasks for each child
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
                let trigger_state = trigger_state.clone();
                let filter_focus_offsets = filter_focus_offsets.clone();

                tokio::spawn(async move {
                    // Check for cancellation before starting
                    if is_cancelled.load(Ordering::Relaxed) || cancelled.load(Ordering::Relaxed) {
                        return (i, NodeStatus::Cancelled);
                    }

                    // Create branch-specific context
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
                    };

                    // Execute the child with mutex guard
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

        // Wait for all tasks to complete
        let _results: Vec<_> = futures::future::join_all(handles)
            .await
            .into_iter()
            .filter_map(|r| r.ok())
            .collect();

        // Restore children from mutex wrappers
        // All spawned tasks have completed, so Arc::try_unwrap should succeed
        let mut restored_children = Vec::with_capacity(children.len());
        for child_mutex in children {
            match Arc::try_unwrap(child_mutex) {
                Ok(mutex) => {
                    restored_children.push(mutex.into_inner());
                }
                Err(_) => {
                    // This should never happen since all tasks completed
                    tracing::error!(
                        "Failed to restore child from parallel execution - this is a bug"
                    );
                    // Can't recover the child, leave it out
                }
            }
        }
        self.children = restored_children;

        // Check for cancellation
        if is_cancelled.load(Ordering::Relaxed) || cancelled.load(Ordering::Relaxed) {
            return NodeStatus::Cancelled;
        }

        // Check results
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
                // Get guiding RMS from PHD2
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
            ConditionalCheck::WeatherSafe => {
                // Check weather/safety monitor for safe conditions
                // Uses the device_ops interface to query connected weather/safety devices
                match context.device_ops.safety_is_safe(None).await {
                    Ok(is_safe) => {
                        if !is_safe {
                            tracing::warn!("Weather safety check failed - conditions unsafe");
                        }
                        is_safe
                    }
                    Err(e) => {
                        // Strict production behavior: safety read errors are always unsafe.
                        match context.safety_fail_mode {
                            SafetyFailMode::FailOpen => {
                                tracing::warn!(
                                    "Weather safety check error: {} - fail_open requested but strict fail-closed is enforced",
                                    e
                                );
                                false
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
                                    "Weather safety check error: {} - warn_only requested but strict fail-closed is enforced",
                                    e
                                );
                                false
                            }
                        }
                    }
                }
            }
            ConditionalCheck::MoonSeparationAbove(degrees) => {
                // Calculate moon separation from target
                let Some(separation) = context.calculate_moon_separation() else {
                    tracing::error!("Conditional MoonSeparationAbove requires target coordinates");
                    return NodeStatus::Failure;
                };
                separation > *degrees
            }
            ConditionalCheck::SafetyMonitorSafe => {
                // Check dedicated safety monitor device
                // Pass None to check the default/profile safety monitor
                match context.device_ops.safety_is_safe(None).await {
                    Ok(is_safe) => {
                        if !is_safe {
                            tracing::warn!("Safety monitor reports unsafe conditions");
                        }
                        is_safe
                    }
                    Err(e) => {
                        // Strict production behavior: safety read errors are always unsafe.
                        match context.safety_fail_mode {
                            SafetyFailMode::FailOpen => {
                                tracing::warn!(
                                    "Safety monitor check error: {} - fail_open requested but strict fail-closed is enforced",
                                    e
                                );
                                false
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
                                    "Safety monitor check error: {} - warn_only requested but strict fail-closed is enforced",
                                    e
                                );
                                false
                            }
                        }
                    }
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

            // Reset children
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
                        let ctx = context.to_instruction_context().await;
                        let park_result = execute_park(&ctx).await;
                        if park_result.status != NodeStatus::Success {
                            tracing::error!(
                                "ParkAndAbort recovery: park failed: {:?}. Mount may be in an unsafe position!",
                                park_result.message
                            );
                        }
                        NodeStatus::Failure
                    }
                    _ => NodeStatus::Failure,
                };
            }

            // Exponential backoff before retry: 1s, 2s, 4s, 8s, ...
            // (attempts is 1-based and we've already completed attempt N, so
            //  the delay before the next attempt uses exponent = attempts - 1)
            let backoff_secs = 1u64 << (attempts - 1).min(6); // Cap at 64s
            tracing::info!(
                "Waiting {}s before retry attempt {}/{}",
                backoff_secs,
                attempts + 1,
                max_attempts
            );

            // Check for cancellation during backoff
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

            // Execute recovery action
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
                    // Wait for user to resume execution
                    if !context.pause_and_wait_for_resume().await {
                        // Cancelled while paused
                        return NodeStatus::Cancelled;
                    }
                    // Resumed - continue with retry
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

        let sleep_secs = (target_timestamp - now).min(1) as u64;
        tokio::time::sleep(std::time::Duration::from_secs(sleep_secs.max(1))).await;
    }
}

// ============================================================================
// Astronomical Helper Functions
// ============================================================================

/// Calculate Julian Day from a chrono DateTime
pub fn julian_day(dt: &chrono::DateTime<chrono::Utc>) -> f64 {
    use chrono::{Datelike, Timelike};
    let year = dt.year();
    let month = dt.month();
    let day = dt.day();
    let hour = dt.hour();
    let minute = dt.minute();
    let second = dt.second();

    let (y, m) = if month <= 2 {
        (year - 1, month + 12)
    } else {
        (year, month)
    };

    let a = y / 100;
    let b = 2 - a + a / 4;

    let jd = (365.25 * (y as f64 + 4716.0)).floor()
        + (30.6001 * (m as f64 + 1.0)).floor()
        + day as f64
        + b as f64
        - 1524.5;

    let time_fraction = (hour as f64 + minute as f64 / 60.0 + second as f64 / 3600.0) / 24.0;

    jd + time_fraction
}

pub fn local_sidereal_time(jd: f64, longitude: f64) -> f64 {
    let t = (jd - 2451545.0) / 36525.0;

    // Greenwich Mean Sidereal Time in degrees
    let gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t
        - t * t * t / 38710000.0;

    let lst = (gmst + longitude) % 360.0;
    if lst < 0.0 {
        (lst + 360.0) / 15.0
    } else {
        lst / 15.0
    }
}

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
            let (sun_ra, sun_dec) = approximate_sun_equatorial_coords(days_since_j2000 as f64);
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
        assert_eq!(
            final_state.completed_exposures,
            WRITERS as u32,
            "every concurrent writer's increment must be observed; missing {} writes",
            WRITERS as u32 - final_state.completed_exposures
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
