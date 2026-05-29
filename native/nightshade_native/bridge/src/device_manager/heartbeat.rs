//! Device heartbeat monitoring loop and lifecycle.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::{DeviceManager, HeartbeatConfig};
use crate::event::*;
use crate::state::SharedAppState;
use std::sync::Arc;
use std::time::Duration;

/// The user-facing event(s) a single failed heartbeat poll should emit.
///
/// Extracted as a value type so the stateful de-dup logic in
/// [`heartbeat_events_for_poll`] can be unit-tested without spinning up a
/// device manager, tokio task, or real driver. The loop translates these
/// into concrete `EquipmentEvent`s (it owns the device id/type strings and
/// the disconnect side-effect gate).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum HeartbeatEventKind {
    /// `HeartbeatStatusChanged { status: Degraded }` — emitted exactly
    /// once on the healthy->degraded transition (latched), not per poll.
    Degraded,
    /// The device crossed the failure threshold: emit
    /// `HeartbeatStatusChanged { status: Disconnected }` followed by an
    /// `Error` carrying the human-readable reason. These two travel
    /// together and replace the old (redundant) standalone `Disconnected`
    /// event so the disconnect surfaces exactly one user-facing toast.
    DisconnectedAndError,
}

/// Pure decision for one failed heartbeat poll.
///
/// Given the previous one-shot Degraded latch (`prev_was_degraded`), the
/// post-increment `consecutive_failures`, and the configured `threshold`,
/// returns the events to publish for this poll and the new latch value.
///
/// Invariants this encodes (and that the unit tests pin):
/// * below threshold + latch clear  -> exactly one `Degraded`, latch set;
/// * below threshold + latch set     -> no events, latch stays set;
/// * at/above threshold              -> exactly one `DisconnectedAndError`
///   (never a standalone Degraded *and* a disconnect on the same poll, and
///   never a standalone `Disconnected` event — that was the duplicate toast
///   removed in the polish pass). The latch value is irrelevant past the
///   threshold because the loop terminates after a disconnect.
///
/// Note: this function does NOT decide healthy/recovery transitions; those
/// re-arm the latch (`was_degraded = false`) directly in the loop's `Ok(true)`
/// arm. It is only invoked on a failing poll.
pub(crate) fn heartbeat_events_for_poll(
    prev_was_degraded: bool,
    consecutive_failures: u32,
    threshold: u32,
) -> (Vec<HeartbeatEventKind>, bool) {
    if consecutive_failures >= threshold {
        // Crossing (or already past) the threshold disconnects the device.
        // The latch is meaningless here since the loop breaks afterward, but
        // we report it unchanged for determinism.
        (
            vec![HeartbeatEventKind::DisconnectedAndError],
            prev_was_degraded,
        )
    } else if !prev_was_degraded {
        // First failing poll of this degradation episode: announce Degraded
        // once and arm the latch so subsequent sub-threshold failures stay
        // quiet.
        (vec![HeartbeatEventKind::Degraded], true)
    } else {
        // Already degraded and still below threshold: emit nothing.
        (Vec::new(), true)
    }
}

impl DeviceManager {
    // =========================================================================
    // Heartbeat Monitoring
    // =========================================================================

    /// Configuration for heartbeat monitoring per device type
    /// Uses optimized presets for each device type based on operational characteristics
    pub(crate) fn get_heartbeat_config(device_type: &DeviceType) -> HeartbeatConfig {
        match device_type {
            DeviceType::Camera => HeartbeatConfig::for_camera(),
            DeviceType::Mount => HeartbeatConfig::for_mount(),
            DeviceType::Focuser => HeartbeatConfig::for_focuser(),
            DeviceType::FilterWheel => HeartbeatConfig::for_filter_wheel(),
            DeviceType::Dome => HeartbeatConfig::for_dome(),
            DeviceType::Rotator => HeartbeatConfig::for_rotator(),
            DeviceType::Weather => HeartbeatConfig::for_weather(),
            DeviceType::SafetyMonitor => HeartbeatConfig::for_safety_monitor(),
            DeviceType::Guider => HeartbeatConfig::for_guider(),
            DeviceType::Switch => HeartbeatConfig::for_switch(),
            DeviceType::CoverCalibrator => HeartbeatConfig::for_cover_calibrator(),
        }
    }

    /// Perform a health check for a specific device
    /// Returns Ok(true) if healthy, Ok(false) if not responding, Err for connection errors
    ///
    /// Visibility note: `pub(super)` so the in-module tests in
    /// `device_manager::tests` (one level up) can call it directly to verify
    /// the Simulator branch without spinning up the full heartbeat task.
    pub(super) async fn perform_health_check(
        &self,
        device_id: &str,
        device_type: &DeviceType,
        driver_type: &DriverType,
    ) -> Result<bool, String> {
        match driver_type {
            DriverType::Alpaca => {
                self.perform_alpaca_health_check(device_id, device_type)
                    .await
            }
            #[cfg(windows)]
            DriverType::Ascom => {
                self.perform_ascom_health_check(device_id, device_type)
                    .await
            }
            #[cfg(not(windows))]
            DriverType::Ascom => Err("ASCOM is not supported on this platform".to_string()),
            DriverType::Indi => self.perform_indi_health_check(device_id).await,
            DriverType::Native => {
                self.perform_native_health_check(device_id, device_type)
                    .await
            }
            DriverType::Simulator => {
                Self::perform_simulator_health_check(device_id, device_type).await
            }
        }
    }

    /// Health check for a simulator device.
    ///
    /// Reads the `connected` field from the matching `simulation.rs`
    /// singleton instead of trivially returning `Ok(true)`. If
    /// `connect_simulator` or `disconnect_simulator` has not been called for
    /// the device (or the device is disconnected out-of-band by flipping the
    /// singleton state), the heartbeat correctly reports `Ok(false)` and the
    /// surrounding loop in `run_heartbeat_loop` escalates to a Disconnected
    /// event after `failure_threshold` consecutive misses.
    ///
    /// Errors (Err) are reserved for unrecognized device ids / unsupported
    /// device types — those indicate a programming bug, not a transient
    /// outage, so we surface them loudly instead of silently treating them
    /// as `false` (CLAUDE.md: "errors are a feature").
    async fn perform_simulator_health_check(
        device_id: &str,
        device_type: &DeviceType,
    ) -> Result<bool, String> {
        if !device_id.starts_with("sim_") {
            return Err(format!(
                "simulator health check: device id '{}' is not a simulator id",
                device_id
            ));
        }

        use crate::api::devices::simulation::{
            get_sim_camera, get_sim_filterwheel, get_sim_focuser, get_sim_mount, get_sim_rotator,
        };

        let connected = match device_type {
            DeviceType::Camera => get_sim_camera().read().await.status.connected,
            DeviceType::Mount => get_sim_mount().read().await.status.connected,
            DeviceType::Focuser => get_sim_focuser().read().await.status.connected,
            DeviceType::FilterWheel => get_sim_filterwheel().read().await.status.connected,
            DeviceType::Rotator => get_sim_rotator().read().await.status.connected,
            other => {
                return Err(format!(
                    "simulator health check: no simulator implementation for device type {:?} (id '{}')",
                    other, device_id
                ));
            }
        };

        Ok(connected)
    }

    // perform_alpaca_health_check / perform_ascom_health_check /
    // perform_indi_health_check moved to crate::dispatch::{alpaca,ascom,indi}.

    /// Start heartbeat monitoring for a device with default configuration
    ///
    /// This spawns a background task that periodically checks if the device
    /// is still responding. If the device fails to respond after multiple
    /// attempts with exponential backoff, a Disconnected event is emitted.
    ///
    /// Uses device-type specific defaults for heartbeat configuration.
    /// If `interval` is non-zero, it overrides the device-type default interval.
    pub async fn start_heartbeat(&self, device_id: &str, interval: Duration) -> Result<(), String> {
        // Check if device exists and get its info
        let (device_type, _device_type_str, _driver_type) = {
            let devices = self.devices.read().await;
            match devices.get(device_id) {
                Some(device) => (
                    device.info.device_type.clone(),
                    device.info.device_type.as_str().to_string(),
                    device.info.driver_type.clone(),
                ),
                None => return Err(format!("Device {} not found", device_id)),
            }
        };

        // Get device-type specific heartbeat configuration
        let mut config = Self::get_heartbeat_config(&device_type);

        // Allow interval override if provided (non-zero)
        if !interval.is_zero() {
            config.base_interval_secs = interval.as_secs();
        }

        // Use the configurable version
        self.start_heartbeat_with_config(device_id, config).await
    }

    /// Start heartbeat monitoring with custom configuration
    ///
    /// Allows full control over heartbeat parameters including:
    /// - Check interval and backoff behavior
    /// - Failure threshold before marking as disconnected
    /// - Auto-reconnect settings
    pub async fn start_heartbeat_with_config(
        &self,
        device_id: &str,
        config: HeartbeatConfig,
    ) -> Result<(), String> {
        // Check if device exists and get its info
        let (device_type, device_type_str, driver_type) = {
            let devices = self.devices.read().await;
            match devices.get(device_id) {
                Some(device) => (
                    device.info.device_type.clone(),
                    device.info.device_type.as_str().to_string(),
                    device.info.driver_type.clone(),
                ),
                None => return Err(format!("Device {} not found", device_id)),
            }
        };

        // Stop any existing heartbeat for this device
        self.stop_heartbeat(device_id).await?;

        tracing::info!(
            "Starting heartbeat for device {} (type: {}, driver: {:?}): interval={}s, threshold={}, auto_reconnect={}",
            device_id,
            device_type_str,
            driver_type,
            config.base_interval_secs,
            config.failure_threshold,
            config.auto_reconnect
        );

        // Emit heartbeat started event
        self.app_state.publish_equipment_event(
            EquipmentEvent::HeartbeatStarted {
                device_type: device_type_str.clone(),
                device_id: device_id.to_string(),
                interval_secs: config.base_interval_secs,
            },
            EventSeverity::Info,
        );

        // Mark heartbeat as active
        {
            let mut devices = self.devices.write().await;
            if let Some(device) = devices.get_mut(device_id) {
                device.heartbeat_active = true;
                device.last_successful_comm = Some(chrono::Utc::now().timestamp_millis());
            }
        }

        // Spawn heartbeat task under panic supervision. Discovery and device
        // heartbeats are critical: a silent panic here means the user thinks
        // the device is fine while it's actually unmonitored. Restart on
        // panic with exponential backoff so a transient driver fault doesn't
        // kill heartbeat for the whole session.
        let device_id_clone = device_id.to_string();
        let app_state = self.app_state.clone();
        // We need a reference to perform health checks - clone Arc pointer from the global singleton
        let manager = crate::api::get_device_manager().clone();

        let give_up_app_state = app_state.clone();
        let give_up_device_type_str = device_type_str.clone();
        let give_up_device_id = device_id_clone.clone();
        let task = crate::util::supervisor::spawn_supervised_restart(
            "device_heartbeat",
            crate::util::supervisor::RestartPolicy::DEFAULT,
            move || {
                let device_id_clone = device_id_clone.clone();
                let app_state = app_state.clone();
                let manager = manager.clone();
                let device_type_str = device_type_str.clone();
                async move {
                    DeviceManager::run_heartbeat_loop(
                        device_id_clone,
                        device_type,
                        device_type_str,
                        driver_type,
                        config,
                        app_state,
                        manager,
                    )
                    .await;
                }
            },
            Some(move |panic_msg: &str| {
                tracing::error!(
                    target: "supervisor",
                    "device_heartbeat for {} exhausted restart budget; device is no longer monitored. Last panic: {panic_msg}",
                    give_up_device_id
                );
                give_up_app_state.publish_equipment_event(
                    EquipmentEvent::Error {
                        device_type: give_up_device_type_str,
                        device_id: give_up_device_id,
                        message: format!(
                            "Heartbeat supervisor gave up after repeated panics: {panic_msg}"
                        ),
                    },
                    EventSeverity::Error,
                );
            }),
        );

        // Store the task handle
        {
            let mut tasks = self.heartbeat_tasks.write().await;
            tasks.insert(device_id.to_string(), task);
        }

        Ok(())
    }

    /// Inner heartbeat loop body, factored out of `start_heartbeat_with_config`
    /// so the panic supervisor can re-invoke it on every restart.
    #[allow(clippy::too_many_arguments)]
    async fn run_heartbeat_loop(
        device_id_clone: String,
        device_type: DeviceType,
        device_type_str: String,
        driver_type: DriverType,
        config: HeartbeatConfig,
        app_state: SharedAppState,
        manager: Arc<DeviceManager>,
    ) {
        let mut current_interval = Duration::from_secs(config.base_interval_secs);
        let max_interval = Duration::from_secs(config.max_interval_secs);
        let mut consecutive_failures = 0u32;
        // Tracks whether we have already published a Degraded event for the
        // current healthy->degraded transition, so Degraded fires exactly once
        // per episode instead of on every failing poll (avoids toast spam).
        let mut was_degraded = false;
        loop {
            // Wait for interval
            tokio::time::sleep(current_interval).await;

            // Perform health check using the actual driver-specific implementation
            let health_check_result = manager
                .perform_health_check(&device_id_clone, &device_type, &driver_type)
                .await;

            match health_check_result {
                Ok(true) => {
                    // Device is healthy - reset failure counter and interval
                    if consecutive_failures > 0 {
                        tracing::info!(
                            "Heartbeat recovered for device {} after {} failures",
                            device_id_clone,
                            consecutive_failures,
                        );

                        app_state.publish_equipment_event(
                            EquipmentEvent::HeartbeatStatusChanged {
                                device_type: device_type_str.clone(),
                                device_id: device_id_clone.clone(),
                                status: crate::event::HeartbeatStatus::Healthy,
                                consecutive_failures: 0,
                                last_rtt_ms: None, // RTT not available for generic health check
                            },
                            EventSeverity::Info,
                        );
                    }
                    consecutive_failures = 0;
                    // Recovered: re-arm the one-shot Degraded latch so a future
                    // degradation episode emits its own single Degraded event.
                    was_degraded = false;
                    current_interval = Duration::from_secs(config.base_interval_secs);

                    // Update last successful communication time
                    {
                        let mut devices = manager.devices.write().await;
                        if let Some(device) = devices.get_mut(&device_id_clone) {
                            device.last_successful_comm =
                                Some(chrono::Utc::now().timestamp_millis());
                        }
                    }

                    tracing::trace!("Heartbeat OK for device: {}", device_id_clone);
                }
                Ok(false) | Err(_) => {
                    // Health check failed
                    consecutive_failures += 1;
                    let error_msg = match &health_check_result {
                        Err(e) => e.clone(),
                        _ => "Device not responding".to_string(),
                    };

                    tracing::warn!(
                        "Heartbeat failure {}/{} for device {}: {}",
                        consecutive_failures,
                        config.failure_threshold,
                        device_id_clone,
                        error_msg
                    );

                    // Apply exponential backoff
                    let new_interval = Duration::from_secs_f64(
                        current_interval.as_secs_f64() * config.backoff_multiplier,
                    );
                    current_interval = new_interval.min(max_interval);

                    // Decide which events this failing poll should emit. The
                    // stateful de-dup (Degraded-once-per-episode latch +
                    // two-events-on-disconnect rule) lives in the pure
                    // `heartbeat_events_for_poll` so it can be unit-tested
                    // without a live device/task.
                    let (event_kinds, new_was_degraded) = heartbeat_events_for_poll(
                        was_degraded,
                        consecutive_failures,
                        config.failure_threshold,
                    );
                    was_degraded = new_was_degraded;

                    let mut disconnected = false;
                    for kind in event_kinds {
                        match kind {
                            HeartbeatEventKind::Degraded => {
                                app_state.publish_equipment_event(
                                    EquipmentEvent::HeartbeatStatusChanged {
                                        device_type: device_type_str.clone(),
                                        device_id: device_id_clone.clone(),
                                        status: crate::event::HeartbeatStatus::Degraded,
                                        consecutive_failures,
                                        last_rtt_ms: None,
                                    },
                                    EventSeverity::Warning,
                                );
                            }
                            HeartbeatEventKind::DisconnectedAndError => {
                                disconnected = true;
                                tracing::error!(
                                    "Heartbeat failed {} times for device {} - marking disconnected",
                                    consecutive_failures,
                                    device_id_clone
                                );

                                if manager
                                    .handle_heartbeat_lost(
                                        &device_id_clone,
                                        config.auto_reconnect,
                                        consecutive_failures,
                                        &error_msg,
                                    )
                                    .await
                                    .is_some()
                                {
                                    // De-dupe: emit exactly two events on
                                    // disconnect — one canonical status change
                                    // (drives the UI/health state) plus one
                                    // Error carrying the human message (drives
                                    // the notification toast). The standalone
                                    // EquipmentEvent::Disconnected was redundant
                                    // with the HeartbeatStatusChanged{Disconnected}
                                    // status and produced a third, duplicate
                                    // user-facing toast.
                                    app_state.publish_equipment_event(
                                        EquipmentEvent::HeartbeatStatusChanged {
                                            device_type: device_type_str.clone(),
                                            device_id: device_id_clone.clone(),
                                            status: crate::event::HeartbeatStatus::Disconnected,
                                            consecutive_failures,
                                            last_rtt_ms: None,
                                        },
                                        EventSeverity::Error,
                                    );

                                    app_state.publish_equipment_event(
                                        EquipmentEvent::Error {
                                            device_type: device_type_str.clone(),
                                            device_id: device_id_clone.clone(),
                                            message: format!(
                                                "Device unresponsive after {} heartbeat failures: {}",
                                                consecutive_failures, error_msg
                                            ),
                                        },
                                        EventSeverity::Error,
                                    );

                                    if config.auto_reconnect {
                                        tracing::info!(
                                            "Device {} marked for reconnection via reconnection_loop (heartbeat auto_reconnect)",
                                            device_id_clone
                                        );
                                    }
                                }
                            }
                        }
                    }

                    if disconnected {
                        // Stop heartbeat monitoring; `reconnection_loop` performs real reconnects.
                        break;
                    }
                }
            }
        }

        tracing::debug!("Heartbeat task ended for device: {}", device_id_clone);

        // Mark heartbeat as inactive when task ends
        {
            let mut devices = manager.devices.write().await;
            if let Some(device) = devices.get_mut(&device_id_clone) {
                device.heartbeat_active = false;
            }
        }
    }

    /// Stop heartbeat monitoring for a device
    ///
    /// Why (DEV-P1-6): `start_heartbeat_with_config` calls this defensively
    /// before starting a new heartbeat. On a fresh connect there is no task
    /// to stop, so we must NOT emit a spurious `HeartbeatStopped` event in
    /// that case — the UI treats every such event as a real stop and the
    /// noise made every connect look like a stop-then-start cycle. The
    /// event must only fire when a real heartbeat was actually torn down.
    pub async fn stop_heartbeat(&self, device_id: &str) -> Result<(), String> {
        // Remove and abort the task. If no task existed, return early
        // BEFORE publishing any event or touching device state — there was
        // no heartbeat to stop, so there is nothing to announce.
        let task = {
            let mut tasks = self.heartbeat_tasks.write().await;
            tasks.remove(device_id)
        };

        let Some(task) = task else {
            return Ok(());
        };

        // Get device type for the event now that we know a real heartbeat
        // existed.
        let device_type_str = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.device_type.as_str().to_string())
        };

        // Abort the task (gracefully cancels via the select!)
        task.abort();

        // Wait briefly for clean shutdown
        match tokio::time::timeout(Duration::from_millis(100), task).await {
            Ok(_) => tracing::debug!("Heartbeat task stopped cleanly for {}", device_id),
            Err(_) => tracing::debug!("Heartbeat task aborted for {}", device_id),
        }

        // Emit heartbeat stopped event
        if let Some(device_type) = device_type_str {
            self.app_state.publish_equipment_event(
                EquipmentEvent::HeartbeatStopped {
                    device_type,
                    device_id: device_id.to_string(),
                },
                EventSeverity::Info,
            );
        }

        // Mark heartbeat as inactive
        {
            let mut devices = self.devices.write().await;
            if let Some(device) = devices.get_mut(device_id) {
                device.heartbeat_active = false;
            }
        }

        Ok(())
    }

    /// Stop all heartbeat tasks (call during shutdown)
    pub async fn stop_all_heartbeats(&self) {
        let tasks: Vec<(String, tokio::task::JoinHandle<()>)> = {
            let mut tasks = self.heartbeat_tasks.write().await;
            std::mem::take(&mut *tasks).into_iter().collect()
        };

        for (device_id, task) in tasks {
            task.abort();
            tracing::debug!("Aborted heartbeat for device: {}", device_id);
        }

        // Mark all heartbeats as inactive
        {
            let mut devices = self.devices.write().await;
            for device in devices.values_mut() {
                device.heartbeat_active = false;
            }
        }
    }

    /// Get device health status
    ///
    /// Returns (last_successful_timestamp_ms, is_healthy)
    pub async fn get_device_health(&self, device_id: &str) -> Result<(i64, bool), String> {
        let devices = self.devices.read().await;

        if let Some(device) = devices.get(device_id) {
            // Why (audit-rust §4.3): device-not-yet-communicated → 0
            // (epoch). Paired with the `is_healthy = false` branch below
            // that explicitly checks `is_none()` — so the (0, false)
            // result distinguishes "never talked" from "talked, healthy
            // or not" without needing a tri-state in the FFI return.
            let last_comm = device.last_successful_comm.unwrap_or(0);
            let now = chrono::Utc::now().timestamp_millis();

            // Consider device unhealthy if no communication in last 30 seconds
            let is_healthy = if let Some(last) = device.last_successful_comm {
                (now - last) < 30_000
            } else {
                false
            };

            Ok((last_comm, is_healthy))
        } else {
            Err(format!("Device {} not found", device_id))
        }
    }

    /// Update last successful communication timestamp for a device
    ///
    /// This should be called by device operations when they successfully
    /// communicate with the device.
    pub async fn update_device_communication(&self, device_id: &str) {
        let mut devices = self.devices.write().await;
        if let Some(device) = devices.get_mut(device_id) {
            device.last_successful_comm = Some(chrono::Utc::now().timestamp_millis());
        }
    }

    /// Check if heartbeat is active for a device
    pub async fn is_heartbeat_active(&self, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        // Why (audit-rust §4.3): unregistered device → "no heartbeat
        // active". The UI uses this to decide whether to show the
        // heartbeat-pulse indicator; absence-of-device = no indicator
        // is the correct visual state.
        devices
            .get(device_id)
            .map(|d| d.heartbeat_active)
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod heartbeat_event_tests {
    use super::{heartbeat_events_for_poll, HeartbeatEventKind};

    const THRESHOLD: u32 = 5;

    /// (a) The first failing poll of an episode emits exactly one Degraded
    /// and arms the latch.
    #[test]
    fn first_failure_below_threshold_emits_one_degraded() {
        let (events, was_degraded) = heartbeat_events_for_poll(false, 1, THRESHOLD);
        assert_eq!(events, vec![HeartbeatEventKind::Degraded]);
        assert!(was_degraded, "latch must arm after first Degraded");
    }

    /// (b) Subsequent sub-threshold failures emit nothing while the latch
    /// is set — this is the whole point of the de-dup (no toast spam).
    #[test]
    fn subsequent_failures_below_threshold_emit_nothing() {
        for failures in 2..THRESHOLD {
            let (events, was_degraded) = heartbeat_events_for_poll(true, failures, THRESHOLD);
            assert!(
                events.is_empty(),
                "failure {failures} should emit no event while latched"
            );
            assert!(was_degraded, "latch stays set below threshold");
        }
    }

    /// (c) Recovery re-arms the latch (the loop sets was_degraded=false on
    /// Ok(true)); a later degradation episode therefore emits Degraded
    /// again. We model that here by passing prev_was_degraded=false again.
    #[test]
    fn recovery_re_arms_latch_so_next_episode_emits_degraded() {
        // Episode 1: first failure -> Degraded, latch set.
        let (events1, latch1) = heartbeat_events_for_poll(false, 1, THRESHOLD);
        assert_eq!(events1, vec![HeartbeatEventKind::Degraded]);
        assert!(latch1);

        // ... recovery happens in the loop: was_degraded reset to false ...

        // Episode 2: first failure again -> Degraded emitted again.
        let (events2, latch2) = heartbeat_events_for_poll(false, 1, THRESHOLD);
        assert_eq!(events2, vec![HeartbeatEventKind::Degraded]);
        assert!(latch2);
    }

    /// (d) Crossing the threshold emits exactly one DisconnectedAndError
    /// (which the loop expands to StatusChanged{Disconnected}+Error — two
    /// events, no standalone Disconnected). It never also emits a Degraded
    /// on the same poll.
    #[test]
    fn crossing_threshold_emits_disconnect_and_error_only() {
        // From an unlatched state (e.g. threshold == 1) and from a latched
        // state (the normal case) the result is identical.
        for prev_latched in [false, true] {
            let (events, _) = heartbeat_events_for_poll(prev_latched, THRESHOLD, THRESHOLD);
            assert_eq!(
                events,
                vec![HeartbeatEventKind::DisconnectedAndError],
                "at threshold (prev_latched={prev_latched}) must emit exactly one disconnect kind"
            );
            assert!(
                !events.contains(&HeartbeatEventKind::Degraded),
                "must not emit a Degraded on the disconnect poll"
            );
        }
    }

    /// Above the threshold (defensive: the loop breaks at threshold, but
    /// the function must remain correct if called with a higher count).
    #[test]
    fn above_threshold_still_emits_disconnect_only() {
        let (events, _) = heartbeat_events_for_poll(true, THRESHOLD + 3, THRESHOLD);
        assert_eq!(events, vec![HeartbeatEventKind::DisconnectedAndError]);
    }

    /// A threshold of 1 means the very first failure disconnects with no
    /// preceding Degraded — verifies the at-threshold branch wins over the
    /// first-failure branch.
    #[test]
    fn threshold_of_one_disconnects_on_first_failure() {
        let (events, _) = heartbeat_events_for_poll(false, 1, 1);
        assert_eq!(events, vec![HeartbeatEventKind::DisconnectedAndError]);
    }
}
