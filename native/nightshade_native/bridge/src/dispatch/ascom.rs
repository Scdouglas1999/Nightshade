//! ASCOM (Windows COM) driver dispatch helpers.
//!
//! Methods in this module are additional impl blocks on `DeviceManager` and
//! provide ASCOM-only logic for `connect_*`, `query_*_api_version`, and
//! `perform_*_health_check`. They are invoked from the dispatcher methods in
//! `crate::devices`. No behavior or signature has changed relative to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::devices::DeviceManager;
// NativeDevice / NativeMount required so the trait methods `connect`,
// `disconnect`, `get_tracking` — which the ASCOM wrappers implement via the
// trait — are resolvable here.
use nightshade_native::traits::{NativeDevice, NativeMount};
use std::sync::Arc;
use tokio::sync::RwLock;

impl DeviceManager {
    /// Connect to an ASCOM device
    #[cfg(windows)]
    pub(crate) async fn connect_ascom(&self, info: &DeviceInfo) -> Result<(), String> {
        let prog_id = info
            .id
            .strip_prefix("ascom:")
            .ok_or_else(|| "Invalid ASCOM device ID".to_string())?;

        match info.device_type {
            DeviceType::Camera => {
                use crate::ascom_wrapper::AscomCameraWrapper;
                let mut camera = AscomCameraWrapper::new(prog_id.to_string())?;
                // Let user select the specific camera/config via ASCOM SetupDialog before connecting
                camera.setup_dialog().await.map_err(|e| e.to_string())?;
                camera.connect().await.map_err(|e| e.to_string())?;

                // Store in typed map for camera-specific operations, wrapped in Arc<RwLock>
                let mut ascom_cameras = self.ascom_cameras.write().await;
                ascom_cameras.insert(info.id.clone(), Arc::new(RwLock::new(camera)));
            }
            DeviceType::Mount => {
                use crate::ascom_wrapper_mount::AscomMountWrapper;
                let mut mount = AscomMountWrapper::new(prog_id.to_string())?;
                mount.connect().await.map_err(|e| e.to_string())?;

                let mut ascom_mounts = self.ascom_mounts.write().await;
                ascom_mounts.insert(info.id.clone(), Arc::new(RwLock::new(mount)));
            }
            DeviceType::Focuser => {
                use crate::ascom_wrapper_focuser::AscomFocuserWrapper;
                let mut focuser = AscomFocuserWrapper::new(prog_id.to_string())?;
                focuser.connect().await.map_err(|e| e.to_string())?;

                let mut ascom_focusers = self.ascom_focusers.write().await;
                ascom_focusers.insert(info.id.clone(), Arc::new(RwLock::new(focuser)));
            }
            DeviceType::FilterWheel => {
                use crate::ascom_wrapper_filterwheel::AscomFilterWheelWrapper;

                // Disconnect and remove old wrapper BEFORE creating new one.
                // If we don't, the old wrapper's Drop will disconnect the COM device
                // after the new wrapper has already connected to it, killing the connection.
                {
                    let mut ascom_filter_wheels = self.ascom_filter_wheels.write().await;
                    if let Some(old_fw) = ascom_filter_wheels.remove(&info.id) {
                        let mut old = old_fw.write().await;
                        let _ = old.disconnect().await;
                        drop(old);
                        drop(old_fw);
                        tracing::info!(
                            "Disconnected old ASCOM filter wheel wrapper for {}",
                            info.id
                        );
                    }
                }

                let mut fw = AscomFilterWheelWrapper::new(prog_id.to_string())?;
                fw.connect().await.map_err(|e| e.to_string())?;

                let mut ascom_filter_wheels = self.ascom_filter_wheels.write().await;
                ascom_filter_wheels.insert(info.id.clone(), Arc::new(RwLock::new(fw)));
            }
            DeviceType::Rotator => {
                use crate::ascom_wrapper_rotator::AscomRotatorWrapper;

                {
                    let mut ascom_rotators = self.ascom_rotators.write().await;
                    if let Some(old_rotator) = ascom_rotators.remove(&info.id) {
                        let mut old = old_rotator.write().await;
                        let _ = old.disconnect().await;
                    }
                }

                let mut rotator = AscomRotatorWrapper::new(prog_id.to_string())?;
                rotator.connect().await?;

                let mut ascom_rotators = self.ascom_rotators.write().await;
                ascom_rotators.insert(info.id.clone(), Arc::new(RwLock::new(rotator)));
            }
            DeviceType::Dome => {
                use crate::ascom_wrapper_dome::AscomDomeWrapper;
                let mut dome = AscomDomeWrapper::new(prog_id.to_string())?;
                dome.connect().await?;

                let mut ascom_domes = self.ascom_domes.write().await;
                ascom_domes.insert(info.id.clone(), Arc::new(RwLock::new(dome)));
            }
            DeviceType::Switch => {
                use crate::ascom_wrapper_switch::AscomSwitchWrapper;
                let mut sw = AscomSwitchWrapper::new(prog_id.to_string())?;
                sw.connect().await.map_err(|e| e.to_string())?;

                let mut ascom_switches = self.ascom_switches.write().await;
                ascom_switches.insert(info.id.clone(), Arc::new(RwLock::new(sw)));
            }
            DeviceType::Weather => {
                use crate::ascom_wrapper_weather::AscomObservingConditionsWrapper;

                {
                    let mut ascom_weather = self.ascom_weather.write().await;
                    if let Some(old_weather) = ascom_weather.remove(&info.id) {
                        let mut old = old_weather.write().await;
                        let _ = old.disconnect().await;
                    }
                }

                let mut weather = AscomObservingConditionsWrapper::new(prog_id.to_string())?;
                weather.connect().await?;

                let mut ascom_weather = self.ascom_weather.write().await;
                ascom_weather.insert(info.id.clone(), Arc::new(RwLock::new(weather)));
            }
            DeviceType::SafetyMonitor => {
                use crate::ascom_wrapper_safetymonitor::AscomSafetyMonitorWrapper;

                {
                    let mut ascom_safety_monitors = self.ascom_safety_monitors.write().await;
                    if let Some(old_monitor) = ascom_safety_monitors.remove(&info.id) {
                        let mut old = old_monitor.write().await;
                        let _ = old.disconnect().await;
                    }
                }

                let mut safety = AscomSafetyMonitorWrapper::new(prog_id.to_string())?;
                safety.connect().await?;

                let mut ascom_safety_monitors = self.ascom_safety_monitors.write().await;
                ascom_safety_monitors.insert(info.id.clone(), Arc::new(RwLock::new(safety)));
            }
            DeviceType::CoverCalibrator => {
                use crate::ascom_wrapper_covercalibrator::AscomCoverCalibratorWrapper;
                let mut cover_cal = AscomCoverCalibratorWrapper::new(prog_id.to_string())?;
                cover_cal.connect().await?;

                let mut ascom_cover_cals = self.ascom_cover_calibrators.write().await;
                ascom_cover_cals.insert(info.id.clone(), Arc::new(RwLock::new(cover_cal)));
            }
            _ => {
                return Err(format!(
                    "ASCOM {} is not supported in this DeviceManager path",
                    info.device_type.as_str()
                ));
            }
        }

        Ok(())
    }

    #[cfg(not(windows))]
    pub(crate) async fn connect_ascom(&self, _info: &DeviceInfo) -> Result<(), String> {
        Err("ASCOM is only available on Windows".to_string())
    }

    /// Query API version for an ASCOM device (Windows only)
    #[cfg(windows)]
    pub async fn query_ascom_api_version(
        &self,
        device_id: &str,
    ) -> Result<DeviceApiVersion, String> {
        // Get the device info
        let device_info = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.clone())
        };

        let info = device_info.ok_or_else(|| format!("Device not found: {}", device_id))?;

        if info.driver_type != DriverType::Ascom {
            return Err(format!("Device {} is not an ASCOM device", device_id));
        }

        // Query version info based on device type
        let version = match info.device_type {
            DeviceType::Camera => {
                let cameras = self.ascom_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    let camera_guard = camera.read().await;
                    let interface_version = camera_guard.interface_version().await.ok();
                    let driver_version = camera_guard.driver_version().await.ok();
                    let driver_info = camera_guard.driver_info().await.ok();
                    let supported_actions =
                        camera_guard.supported_actions().await.unwrap_or_default();
                    DeviceApiVersion::from_ascom(
                        device_id.to_string(),
                        interface_version.unwrap_or(1),
                        driver_version,
                        driver_info,
                        supported_actions,
                    )
                } else {
                    return Err(format!("ASCOM camera {} not connected", device_id));
                }
            }
            DeviceType::Mount => {
                let mounts = self.ascom_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    let mount_guard = mount.read().await;
                    let interface_version = mount_guard.interface_version().await.ok();
                    let driver_version = mount_guard.driver_version().await.ok();
                    let driver_info = mount_guard.driver_info().await.ok();
                    let supported_actions =
                        mount_guard.supported_actions().await.unwrap_or_default();
                    DeviceApiVersion::from_ascom(
                        device_id.to_string(),
                        interface_version.unwrap_or(1),
                        driver_version,
                        driver_info,
                        supported_actions,
                    )
                } else {
                    return Err(format!("ASCOM mount {} not connected", device_id));
                }
            }
            DeviceType::Focuser => {
                let focusers = self.ascom_focusers.read().await;
                if let Some(focuser) = focusers.get(device_id) {
                    let focuser_guard = focuser.read().await;
                    let interface_version = focuser_guard.interface_version().await.ok();
                    let driver_version = focuser_guard.driver_version().await.ok();
                    let driver_info = focuser_guard.driver_info().await.ok();
                    let supported_actions =
                        focuser_guard.supported_actions().await.unwrap_or_default();
                    DeviceApiVersion::from_ascom(
                        device_id.to_string(),
                        interface_version.unwrap_or(1),
                        driver_version,
                        driver_info,
                        supported_actions,
                    )
                } else {
                    return Err(format!("ASCOM focuser {} not connected", device_id));
                }
            }
            DeviceType::FilterWheel => {
                let filter_wheels = self.ascom_filter_wheels.read().await;
                if let Some(fw) = filter_wheels.get(device_id) {
                    let fw_guard = fw.read().await;
                    let interface_version = fw_guard.interface_version().await.ok();
                    let driver_version = fw_guard.driver_version().await.ok();
                    let driver_info = fw_guard.driver_info().await.ok();
                    let supported_actions = fw_guard.supported_actions().await.unwrap_or_default();
                    DeviceApiVersion::from_ascom(
                        device_id.to_string(),
                        interface_version.unwrap_or(1),
                        driver_version,
                        driver_info,
                        supported_actions,
                    )
                } else {
                    return Err(format!("ASCOM filter wheel {} not connected", device_id));
                }
            }
            DeviceType::Dome => {
                let domes = self.ascom_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    let dome_guard = dome.read().await;
                    let interface_version = dome_guard.interface_version().await.ok();
                    let driver_version = dome_guard.driver_version().await.ok();
                    let driver_info = dome_guard.driver_info().await.ok();
                    let supported_actions =
                        dome_guard.supported_actions().await.unwrap_or_default();
                    DeviceApiVersion::from_ascom(
                        device_id.to_string(),
                        interface_version.unwrap_or(1),
                        driver_version,
                        driver_info,
                        supported_actions,
                    )
                } else {
                    return Err(format!("ASCOM dome {} not connected", device_id));
                }
            }
            DeviceType::Switch => {
                let switches = self.ascom_switches.read().await;
                if let Some(switch) = switches.get(device_id) {
                    let switch_guard = switch.read().await;
                    let interface_version = switch_guard.interface_version().await.ok();
                    let driver_version = switch_guard.driver_version().await.ok();
                    let driver_info = switch_guard.driver_info().await.ok();
                    let supported_actions =
                        switch_guard.supported_actions().await.unwrap_or_default();
                    DeviceApiVersion::from_ascom(
                        device_id.to_string(),
                        interface_version.unwrap_or(1),
                        driver_version,
                        driver_info,
                        supported_actions,
                    )
                } else {
                    return Err(format!("ASCOM switch {} not connected", device_id));
                }
            }
            DeviceType::CoverCalibrator => {
                let covers = self.ascom_cover_calibrators.read().await;
                if let Some(cover) = covers.get(device_id) {
                    let cover_guard = cover.read().await;
                    let interface_version = cover_guard.interface_version().await.ok();
                    let driver_version = cover_guard.driver_version().await.ok();
                    let driver_info = cover_guard.driver_info().await.ok();
                    let supported_actions =
                        cover_guard.supported_actions().await.unwrap_or_default();
                    DeviceApiVersion::from_ascom(
                        device_id.to_string(),
                        interface_version.unwrap_or(1),
                        driver_version,
                        driver_info,
                        supported_actions,
                    )
                } else {
                    return Err(format!(
                        "ASCOM cover calibrator {} not connected",
                        device_id
                    ));
                }
            }
            _ => {
                return Err(format!(
                    "Unsupported ASCOM device type: {:?}",
                    info.device_type
                ));
            }
        };

        // Cache the version
        self.set_device_api_version(device_id, version.clone())
            .await;
        tracing::info!(
            "Queried API version for {}: interface_version={:?}, driver_version={:?}",
            device_id,
            version.interface_version,
            version.driver_version
        );

        Ok(version)
    }

    /// Perform health check for ASCOM devices (Windows only)
    #[cfg(windows)]
    pub(crate) async fn perform_ascom_health_check(
        &self,
        device_id: &str,
        device_type: &DeviceType,
    ) -> Result<bool, String> {
        match device_type {
            DeviceType::Camera => {
                let cameras = self.ascom_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    match camera.read().await.heartbeat().await {
                        Ok(health) => {
                            let is_healthy = matches!(
                                health,
                                crate::ascom_wrapper::CameraConnectionHealth::Healthy
                                    | crate::ascom_wrapper::CameraConnectionHealth::Unknown
                            );
                            tracing::trace!("ASCOM camera {} heartbeat: {:?}", device_id, health);
                            Ok(is_healthy)
                        }
                        Err(e) => {
                            tracing::debug!("ASCOM camera {} heartbeat failed: {:?}", device_id, e);
                            Ok(false)
                        }
                    }
                } else {
                    Err(format!("ASCOM camera {} not found", device_id))
                }
            }
            DeviceType::Mount => {
                let mounts = self.ascom_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    // Send a lightweight COM command through the worker thread to verify
                    // the mount is actually responding, not just reading an AtomicBool flag
                    let mount_guard = mount.read().await;
                    match mount_guard.get_tracking().await {
                        Ok(_) => {
                            tracing::trace!("ASCOM mount {} heartbeat: healthy", device_id,);
                            Ok(true)
                        }
                        Err(e) => {
                            tracing::debug!("ASCOM mount {} heartbeat failed: {:?}", device_id, e);
                            Ok(false)
                        }
                    }
                } else {
                    Err(format!("ASCOM mount {} not found", device_id))
                }
            }
            DeviceType::Focuser => {
                let focusers = self.ascom_focusers.read().await;
                if let Some(focuser) = focusers.get(device_id) {
                    let connected = focuser.read().await.is_connected();
                    tracing::trace!(
                        "ASCOM focuser {} heartbeat: connected={}",
                        device_id,
                        connected
                    );
                    Ok(connected)
                } else {
                    Err(format!("ASCOM focuser {} not found", device_id))
                }
            }
            DeviceType::FilterWheel => {
                let filter_wheels = self.ascom_filter_wheels.read().await;
                if let Some(fw) = filter_wheels.get(device_id) {
                    let connected = fw.read().await.is_connected();
                    tracing::trace!(
                        "ASCOM filter wheel {} heartbeat: connected={}",
                        device_id,
                        connected
                    );
                    Ok(connected)
                } else {
                    Err(format!("ASCOM filter wheel {} not found", device_id))
                }
            }
            DeviceType::Dome => {
                let domes = self.ascom_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    let connected = dome.read().await.is_connected();
                    tracing::trace!(
                        "ASCOM dome {} heartbeat: connected={}",
                        device_id,
                        connected
                    );
                    Ok(connected)
                } else {
                    Err(format!("ASCOM dome {} not found", device_id))
                }
            }
            _ => Err(format!(
                "No ASCOM heartbeat implementation for device {} ({:?})",
                device_id, device_type
            )),
        }
    }
}
