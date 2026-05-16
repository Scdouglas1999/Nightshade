//! Device connection lifecycle: register, connect, disconnect, auto-reconnect.
//!
//! Methods in this module are additional impl blocks on `DeviceManager` and
//! contain the cross-driver lifecycle logic. Driver-specific `connect_*`
//! helpers continue to live in `crate::dispatch::{ascom,alpaca,indi,native}`
//! (also split-impl-block) and are invoked from `connect_device_internal`
//! below. No behavior or signature has changed relative to the previous
//! monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::{DeviceManager, ManagedDevice};
use crate::event::*;
use nightshade_native::traits::NativeDevice;
use std::time::Duration;
use tokio::time::interval;

impl DeviceManager {
    /// Background task for automatic reconnection
    pub(crate) async fn reconnection_loop(&self) {
        let mut check_interval = interval(Duration::from_secs(5));

        loop {
            check_interval.tick().await;

            // Check if we should stop
            if *self.stop_reconnect.read().await {
                break;
            }

            if !self.reconnect_config.enabled {
                continue;
            }

            // Find devices that need reconnection
            let devices_to_reconnect: Vec<(String, ManagedDevice)> = {
                let devices = self.devices.read().await;
                devices
                    .iter()
                    .filter(|(_, dev)| {
                        dev.auto_reconnect
                            && dev.connection_state == ConnectionState::Error
                            && (self.reconnect_config.max_attempts == 0
                                || dev.reconnect_attempts < self.reconnect_config.max_attempts)
                    })
                    .map(|(id, dev)| (id.clone(), dev.clone()))
                    .collect()
            };

            // Attempt reconnection for each device
            for (device_id, device) in devices_to_reconnect {
                tracing::info!(
                    "Attempting reconnection for {} (attempt {})",
                    device_id,
                    device.reconnect_attempts + 1
                );

                // Calculate backoff delay
                let delay = self.calculate_backoff_delay(device.reconnect_attempts);
                tokio::time::sleep(Duration::from_secs(delay)).await;

                // Attempt reconnection
                if let Err(e) = self.connect_device_internal(&device.info).await {
                    tracing::warn!("Reconnection failed for {}: {}", device_id, e);

                    // Update attempt counter
                    let mut devices = self.devices.write().await;
                    if let Some(dev) = devices.get_mut(&device_id) {
                        dev.reconnect_attempts += 1;
                        dev.last_error = Some(e.clone());

                        // Publish reconnection failed event
                        self.app_state.publish_equipment_event(
                            EquipmentEvent::Error {
                                device_type: dev.info.device_type.as_str().to_string(),
                                device_id: device_id.clone(),
                                message: format!(
                                    "Reconnection attempt {} failed: {}",
                                    dev.reconnect_attempts, e
                                ),
                            },
                            EventSeverity::Warning,
                        );
                    }
                } else {
                    tracing::info!("Reconnection successful for {}", device_id);

                    // Reset attempt counter on success
                    let mut devices = self.devices.write().await;
                    if let Some(dev) = devices.get_mut(&device_id) {
                        dev.reconnect_attempts = 0;
                        dev.last_error = None;
                    }
                }
            }
        }
    }

    /// Calculate backoff delay for reconnection
    pub(crate) fn calculate_backoff_delay(&self, attempts: u32) -> u64 {
        // Why (audit-rust §1.4): u64 (initial_delay_secs) → f64 has bounded
        // precision loss for any realistic config (seconds, not nanoseconds).
        // u32 → i32 for `powi` saturates at i32::MAX (~2B retries) which is
        // unreachable; the result is then clamped by `min(max_delay_secs)`.
        // f64 → u64 uses Rust 1.45+ saturating semantics for the final cast.
        let delay = (self.reconnect_config.initial_delay_secs as f64)
            * self
                .reconnect_config
                .backoff_multiplier
                .powi(i32::try_from(attempts).unwrap_or(i32::MAX));

        (delay as u64).min(self.reconnect_config.max_delay_secs)
    }

    /// Register a device for management
    pub async fn register_device(&self, info: DeviceInfo, auto_reconnect: bool) {
        let mut devices = self.devices.write().await;
        devices.insert(
            info.id.clone(),
            ManagedDevice {
                info,
                connection_state: ConnectionState::Disconnected,
                last_error: None,
                reconnect_attempts: 0,
                auto_reconnect,
                last_successful_comm: None,
                heartbeat_active: false,
                api_version: None,
            },
        );
    }

    /// Check if a device is registered
    pub async fn is_device_registered(&self, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        devices.contains_key(device_id)
    }

    /// Get the display name for a registered device, if it exists.
    pub async fn get_device_display_name(&self, device_id: &str) -> Option<String> {
        let devices = self.devices.read().await;
        devices.get(device_id).map(|d| d.info.display_name.clone())
    }

    /// Connect to a device
    pub async fn connect_device(&self, device_id: &str) -> Result<(), String> {
        let device_info = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?
        };

        self.connect_device_internal(&device_info).await
    }

    /// Internal connection logic
    pub(crate) async fn connect_device_internal(&self, info: &DeviceInfo) -> Result<(), String> {
        let device_id = &info.id;

        // Update state to connecting
        {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                dev.connection_state = ConnectionState::Connecting;
            }
        }

        // Publish connecting event
        self.app_state.publish_equipment_event(
            EquipmentEvent::Connecting {
                device_type: info.device_type.as_str().to_string(),
                device_id: device_id.clone(),
            },
            EventSeverity::Info,
        );

        // Perform actual connection based on driver type
        let result = match info.driver_type {
            DriverType::Simulator => self.connect_simulator(info).await,
            DriverType::Ascom => self.connect_ascom(info).await,
            DriverType::Alpaca => self.connect_alpaca(info).await,
            DriverType::Indi => self.connect_indi(info).await,
            DriverType::Native => self.connect_native(info).await,
        };

        // Update state based on result
        {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                match &result {
                    Ok(_) => {
                        dev.connection_state = ConnectionState::Connected;
                        dev.last_error = None;
                        dev.reconnect_attempts = 0;
                    }
                    Err(e) => {
                        dev.connection_state = ConnectionState::Error;
                        dev.last_error = Some(e.clone());
                    }
                }
            }
        }

        // Publish result event
        match &result {
            Ok(_) => {
                self.app_state.publish_equipment_event(
                    EquipmentEvent::Connected {
                        device_type: info.device_type.as_str().to_string(),
                        device_id: device_id.clone(),
                    },
                    EventSeverity::Info,
                );

                // Also register in app state
                self.app_state
                    .register_device(info.clone(), ConnectionState::Connected)
                    .await;

                // Auto-start heartbeat monitoring for the connected device
                let heartbeat_config = Self::get_heartbeat_config(&info.device_type);
                if let Err(e) = self
                    .start_heartbeat_with_config(device_id, heartbeat_config)
                    .await
                {
                    tracing::warn!("Failed to start heartbeat for {}: {}", device_id, e);
                } else {
                    tracing::info!("Auto-started heartbeat for device {}", device_id);
                }
            }
            Err(e) => {
                self.app_state.publish_equipment_event(
                    EquipmentEvent::Error {
                        device_type: info.device_type.as_str().to_string(),
                        device_id: device_id.clone(),
                        message: e.clone(),
                    },
                    EventSeverity::Error,
                );
            }
        }

        result
    }

    /// Connect to a simulator device - DISABLED
    pub(crate) async fn connect_simulator(&self, _info: &DeviceInfo) -> Result<(), String> {
        Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
    }

    /// Disconnect a device
    pub async fn disconnect_device(&self, device_id: &str) -> Result<(), String> {
        // Stop heartbeat monitoring first to prevent false disconnect events
        let _ = self.stop_heartbeat(device_id).await;

        let device_info = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?
        };

        // Update state
        {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                dev.connection_state = ConnectionState::Disconnected;
                dev.auto_reconnect = false; // Disable auto-reconnect on manual disconnect
            }
        }

        // Clean up device from driver-specific storage based on driver type and device type
        if device_info.id == crate::builtin_guider::device_id() {
            let _ = crate::builtin_guider::disconnect().await;
        }
        match device_info.driver_type {
            DriverType::Native => {
                // Remove from generic native_devices map
                let mut native_devices = self.native_devices.write().await;
                if let Some(mut device) = native_devices.remove(device_id) {
                    let _ = device.disconnect().await;
                }

                // Also remove from typed native storage maps
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.native_cameras.write().await;
                        if let Some(mut camera) = cameras.remove(device_id) {
                            let _ = camera.disconnect().await;
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.native_mounts.write().await;
                        if let Some(mut mount) = mounts.remove(device_id) {
                            let _ = mount.disconnect().await;
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.native_focusers.write().await;
                        if let Some(mut focuser) = focusers.remove(device_id) {
                            let _ = focuser.disconnect().await;
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.native_filter_wheels.write().await;
                        if let Some(mut fw) = fws.remove(device_id) {
                            let _ = fw.disconnect().await;
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.native_rotators.write().await;
                        if let Some(mut rotator) = rotators.remove(device_id) {
                            let _ = rotator.disconnect().await;
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.native_domes.write().await;
                        if let Some(mut dome) = domes.remove(device_id) {
                            let _ = dome.disconnect().await;
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.native_weather.write().await;
                        if let Some(mut w) = weather.remove(device_id) {
                            let _ = w.disconnect().await;
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety = self.native_safety_monitors.write().await;
                        if let Some(mut s) = safety.remove(device_id) {
                            let _ = s.disconnect().await;
                        }
                    }
                    _ => {} // Guider, Switch, CoverCalibrator - no typed native storage
                }
            }
            DriverType::Alpaca => {
                // Remove from Alpaca storage based on device type
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.alpaca_cameras.write().await;
                        if let Some(camera) = cameras.remove(device_id) {
                            let _ = camera.disconnect().await;
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.alpaca_mounts.write().await;
                        if let Some(mount) = mounts.remove(device_id) {
                            let _ = mount.disconnect().await;
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.alpaca_focusers.write().await;
                        if let Some(focuser) = focusers.remove(device_id) {
                            let _ = focuser.disconnect().await;
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.alpaca_filter_wheels.write().await;
                        if let Some(fw) = fws.remove(device_id) {
                            let _ = fw.disconnect().await;
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.alpaca_rotators.write().await;
                        if let Some(rotator) = rotators.remove(device_id) {
                            let _ = rotator.disconnect().await;
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.alpaca_domes.write().await;
                        if let Some(dome) = domes.remove(device_id) {
                            let _ = dome.disconnect().await;
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.alpaca_weather.write().await;
                        if let Some(w) = weather.remove(device_id) {
                            let _ = w.disconnect().await;
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety = self.alpaca_safety_monitors.write().await;
                        if let Some(s) = safety.remove(device_id) {
                            let _ = s.disconnect().await;
                        }
                    }
                    DeviceType::Switch => {
                        let mut switches = self.alpaca_switches.write().await;
                        if let Some(sw) = switches.remove(device_id) {
                            let _ = sw.disconnect().await;
                        }
                    }
                    DeviceType::CoverCalibrator => {
                        let mut covers = self.alpaca_cover_calibrators.write().await;
                        if let Some(cover) = covers.remove(device_id) {
                            let _ = cover.disconnect().await;
                        }
                    }
                    DeviceType::Guider => {} // Alpaca guider devices are not currently managed here
                }
            }
            #[cfg(windows)]
            DriverType::Ascom => {
                // Remove from ASCOM storage based on device type
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.ascom_cameras.write().await;
                        if let Some(camera) = cameras.remove(device_id) {
                            let mut cam = camera.write().await;
                            let _ = cam.disconnect().await;
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.ascom_mounts.write().await;
                        if let Some(mount) = mounts.remove(device_id) {
                            let mut m = mount.write().await;
                            let _ = m.disconnect().await;
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.ascom_focusers.write().await;
                        if let Some(focuser) = focusers.remove(device_id) {
                            let mut f = focuser.write().await;
                            let _ = f.disconnect().await;
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.ascom_filter_wheels.write().await;
                        if let Some(fw) = fws.remove(device_id) {
                            let mut f = fw.write().await;
                            let _ = f.disconnect().await;
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.ascom_rotators.write().await;
                        if let Some(rotator) = rotators.remove(device_id) {
                            let mut r = rotator.write().await;
                            let _ = r.disconnect().await;
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.ascom_domes.write().await;
                        if let Some(dome) = domes.remove(device_id) {
                            let mut d = dome.write().await;
                            let _ = d.disconnect().await;
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.ascom_weather.write().await;
                        if let Some(device) = weather.remove(device_id) {
                            let mut w = device.write().await;
                            let _ = w.disconnect().await;
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety_monitors = self.ascom_safety_monitors.write().await;
                        if let Some(monitor) = safety_monitors.remove(device_id) {
                            let mut sm = monitor.write().await;
                            let _ = sm.disconnect().await;
                        }
                    }
                    DeviceType::Switch => {
                        let mut switches = self.ascom_switches.write().await;
                        if let Some(sw) = switches.remove(device_id) {
                            let mut s = sw.write().await;
                            let _ = s.disconnect().await;
                        }
                    }
                    DeviceType::CoverCalibrator => {
                        let mut covers = self.ascom_cover_calibrators.write().await;
                        if let Some(cover) = covers.remove(device_id) {
                            let mut c = cover.write().await;
                            let _ = c.disconnect().await;
                        }
                    }
                    _ => {}
                }
            }
            #[cfg(not(windows))]
            DriverType::Ascom => {
                // ASCOM not available on non-Windows platforms
            }
            DriverType::Indi => {
                // INDI cleanup handled separately through INDI client
                // The client manages device connections internally
            }
            DriverType::Simulator => {
                // Simulators should never be connected - connection is disabled
                // No cleanup needed even if this is somehow reached
            }
        }

        // Publish event
        self.app_state.publish_equipment_event(
            EquipmentEvent::Disconnected {
                device_type: device_info.device_type.as_str().to_string(),
                device_id: device_id.to_string(),
            },
            EventSeverity::Info,
        );

        // Update app state
        self.app_state
            .remove_device(device_info.device_type, device_id)
            .await;

        Ok(())
    }

    /// Enable or disable auto-reconnect for a device
    pub async fn set_auto_reconnect(&self, device_id: &str, enabled: bool) {
        let mut devices = self.devices.write().await;
        if let Some(dev) = devices.get_mut(device_id) {
            dev.auto_reconnect = enabled;
        }
    }

    /// Report a connection error (triggers auto-reconnect if enabled)
    pub async fn report_error(&self, device_id: &str, error: String) {
        let mut devices = self.devices.write().await;
        if let Some(dev) = devices.get_mut(device_id) {
            dev.connection_state = ConnectionState::Error;
            dev.last_error = Some(error.clone());

            self.app_state.publish_equipment_event(
                EquipmentEvent::Error {
                    device_type: dev.info.device_type.as_str().to_string(),
                    device_id: device_id.to_string(),
                    message: error,
                },
                EventSeverity::Error,
            );
        }
    }

    /// Stop the reconnection background task
    pub async fn shutdown(&self) {
        *self.stop_reconnect.write().await = true;
    }

    /// Unregister a device
    pub async fn unregister_device(&self, device_id: &str) {
        let mut devices = self.devices.write().await;
        devices.remove(device_id);
    }
}
