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
            // Default for other devices (guiders, switches, cover calibrators)
            _ => HeartbeatConfig::default(),
        }
    }

    /// Perform a health check for a specific device
    /// Returns Ok(true) if healthy, Ok(false) if not responding, Err for connection errors
    async fn perform_health_check(
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
                // Native devices maintain their own connection state
                Ok(true)
            }
            DriverType::Simulator => Err("Simulator devices are disabled".to_string()),
        }
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
        let mut reconnect_attempts = 0u32;
        let mut is_reconnecting = false;

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
                    if consecutive_failures > 0 || is_reconnecting {
                        tracing::info!(
                            "Heartbeat recovered for device {} after {} failures{}",
                            device_id_clone,
                            consecutive_failures,
                            if is_reconnecting {
                                " (reconnected)"
                            } else {
                                ""
                            }
                        );

                        // Emit HeartbeatStatusChanged event for recovery
                        if is_reconnecting {
                            app_state.publish_equipment_event(
                                EquipmentEvent::HeartbeatReconnected {
                                    device_type: device_type_str.clone(),
                                    device_id: device_id_clone.clone(),
                                    after_attempts: reconnect_attempts,
                                },
                                EventSeverity::Info,
                            );
                        }

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
                    reconnect_attempts = 0;
                    is_reconnecting = false;
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

                    // Emit degraded status if we have failures but not yet at threshold
                    if consecutive_failures < config.failure_threshold {
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

                    // Check if we've exceeded failure threshold
                    if consecutive_failures >= config.failure_threshold {
                        tracing::error!(
                            "Heartbeat failed {} times for device {} - marking disconnected",
                            consecutive_failures,
                            device_id_clone
                        );

                        // Update device state
                        {
                            let mut devices = manager.devices.write().await;
                            if let Some(device) = devices.get_mut(&device_id_clone) {
                                device.connection_state = ConnectionState::Error;
                                device.last_error = Some(format!(
                                    "Unresponsive after {} heartbeat failures",
                                    consecutive_failures
                                ));
                            }
                        }

                        // Emit disconnected status via HeartbeatStatusChanged
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
                            EquipmentEvent::Disconnected {
                                device_type: device_type_str.clone(),
                                device_id: device_id_clone.clone(),
                            },
                            EventSeverity::Warning,
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

                        // Handle auto-reconnect if enabled
                        if config.auto_reconnect {
                            let max_reconnects = config.max_reconnect_attempts;
                            let should_try =
                                max_reconnects == 0 || reconnect_attempts < max_reconnects;

                            if should_try {
                                reconnect_attempts += 1;
                                is_reconnecting = true;

                                tracing::info!(
                                    "Attempting auto-reconnect for device {} (attempt {}/{})",
                                    device_id_clone,
                                    reconnect_attempts,
                                    if max_reconnects == 0 {
                                        "unlimited".to_string()
                                    } else {
                                        max_reconnects.to_string()
                                    }
                                );

                                // Emit reconnecting status
                                app_state.publish_equipment_event(
                                    EquipmentEvent::HeartbeatStatusChanged {
                                        device_type: device_type_str.clone(),
                                        device_id: device_id_clone.clone(),
                                        status: crate::event::HeartbeatStatus::Reconnecting,
                                        consecutive_failures,
                                        last_rtt_ms: None,
                                    },
                                    EventSeverity::Info,
                                );

                                app_state.publish_equipment_event(
                                    EquipmentEvent::HeartbeatReconnecting {
                                        device_type: device_type_str.clone(),
                                        device_id: device_id_clone.clone(),
                                        attempt: reconnect_attempts,
                                        max_attempts: max_reconnects,
                                    },
                                    EventSeverity::Info,
                                );

                                app_state.publish_equipment_event(
                                    EquipmentEvent::Connecting {
                                        device_type: device_type_str.clone(),
                                        device_id: device_id_clone.clone(),
                                    },
                                    EventSeverity::Info,
                                );

                                // Wait before reconnection attempt
                                // Why (audit-rust §1.4): `reconnect_attempts`
                                // is u32; u32 → u64 widening exact. The
                                // multiplication uses u64 arithmetic so
                                // a runaway attempt count saturates at
                                // u64::MAX (~584 billion years).
                                let reconnect_delay = Duration::from_secs(
                                    config.reconnect_delay_secs * u64::from(reconnect_attempts),
                                );
                                tokio::time::sleep(reconnect_delay).await;

                                // Reset failure counter for reconnect monitoring
                                consecutive_failures = 0;
                                current_interval = Duration::from_secs(config.base_interval_secs);

                                // Continue monitoring - if connection recovers, we'll see it
                                continue;
                            } else {
                                tracing::error!(
                                    "Max reconnection attempts ({}) reached for device {}",
                                    max_reconnects,
                                    device_id_clone
                                );

                                app_state.publish_equipment_event(
                                    EquipmentEvent::Error {
                                        device_type: device_type_str.clone(),
                                        device_id: device_id_clone.clone(),
                                        message: format!(
                                            "Auto-reconnect failed after {} attempts",
                                            reconnect_attempts
                                        ),
                                    },
                                    EventSeverity::Error,
                                );
                            }
                        }

                        // Stop heartbeat monitoring
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
    pub async fn stop_heartbeat(&self, device_id: &str) -> Result<(), String> {
        // Get device type for the event before removing task
        let device_type_str = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.device_type.as_str().to_string())
        };

        // Remove and abort the task
        let task = {
            let mut tasks = self.heartbeat_tasks.write().await;
            tasks.remove(device_id)
        };

        if let Some(task) = task {
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
