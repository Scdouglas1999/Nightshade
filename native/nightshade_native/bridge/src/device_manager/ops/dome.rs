//! Dome operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.
//!
//! # `unwrap_or` policy (audit-rust §4.3)
//!
//! Every `unwrap_or(false)` in this file probes an INDI / ASCOM optional
//! switch (`DOME_SHUTTER/SHUTTER_OPEN`, `DOME_AUTOSYNC/ENABLE`, …). The
//! ASCOM-Alpaca and INDI specifications both treat undeclared switches as
//! "feature not exposed"; treating the absence as `false` is the documented
//! cross-driver mapping used by the equipment-compatibility matrix UI.
//! Hard connection failures (driver not found, device disconnected) still
//! return `Err(String)` from the outer dispatch helper.

use crate::device::*;
use crate::device_manager::DeviceManager;
use tracing::warn;

impl DeviceManager {
    // =========================================================================
    // Dome Control
    // =========================================================================

    /// Open dome shutter
    pub async fn dome_open_shutter(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.open_shutter().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.open_shutter().await.map_err(|e| {
                            format!("Failed to open ASCOM dome shutter on {}: {}", device_id, e)
                        });
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_switch(&device_name, "DOME_SHUTTER", "SHUTTER_OPEN", true).await.map_err(|e| e.to_string());
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_domes = self.native_domes.write().await;
                if let Some(dome) = native_domes.get_mut(device_id) {
                    return dome.open_shutter().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Close dome shutter
    pub async fn dome_close_shutter(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.close_shutter().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.close_shutter().await.map_err(|e| {
                            format!("Failed to close ASCOM dome shutter on {}: {}", device_id, e)
                        });
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_switch(&device_name, "DOME_SHUTTER", "SHUTTER_CLOSE", true).await.map_err(|e| e.to_string());
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_domes = self.native_domes.write().await;
                if let Some(dome) = native_domes.get_mut(device_id) {
                    return dome.close_shutter().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Slew dome to azimuth
    pub async fn dome_slew_to_azimuth(&self, device_id: &str, azimuth: f64) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.slew_to_azimuth(azimuth).await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked
                        .set_number(&device_name, "ABS_DOME_POSITION", "DOME_ABSOLUTE_POSITION", azimuth)
                        .await
                        .map_err(|e| {
                            format!("Failed to slew INDI dome {} to azimuth {:.2}: {}", device_name, azimuth, e)
                        });
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.slew_to_azimuth(azimuth).await;
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_domes = self.native_domes.write().await;
                if let Some(dome) = native_domes.get_mut(device_id) {
                    return dome.slew_to_azimuth(azimuth).await.map_err(|e| {
                        format!("Failed to slew native dome {} to azimuth {:.2}: {}", device_id, azimuth, e)
                    });
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Get dome azimuth
    pub async fn dome_get_azimuth(&self, device_id: &str) -> Result<f64, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.azimuth().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    if let Some(az) = locked.get_number(&device_name, "ABS_DOME_POSITION", "DOME_ABSOLUTE_POSITION").await {
                        return Ok(az);
                    }
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.azimuth().await;
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Native) => {
                let native_domes = self.native_domes.read().await;
                if let Some(dome) = native_domes.get(device_id) {
                    return dome.get_azimuth().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Get dome shutter status
    pub async fn dome_get_shutter_status(&self, device_id: &str) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    let status = dome.shutter_status().await?;
                    // Why (audit-rust §1.4): `ShutterState` is a C-like
                    // ASCOM enum with values {0..4} (Open, Closed, Opening,
                    // Closing, Error); `as i32` extracts the discriminant.
                    return Ok(status as i32);
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.shutter_status().await;
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    // Check INDI shutter switches: 0=Open, 1=Closed, 4=Unknown
                    if locked.get_switch(&device_name, "DOME_SHUTTER", "SHUTTER_OPEN").await.unwrap_or(false) {
                        return Ok(0); // Open
                    } else if locked.get_switch(&device_name, "DOME_SHUTTER", "SHUTTER_CLOSE").await.unwrap_or(false) {
                        return Ok(1); // Closed
                    }
                }
                Ok(4) // Unknown/Error
            }
            Some(DriverType::Native) => {
                let native_domes = self.native_domes.read().await;
                if let Some(dome) = native_domes.get(device_id) {
                    let status = dome.get_shutter_status().await.map_err(|e| e.to_string())?;
                    // Convert ShutterState enum to i32: Open=0, Closed=1, Opening=2, Closing=3, Error=4, Unknown=5
                    let code = match status {
                        nightshade_native::traits::ShutterState::Open => 0,
                        nightshade_native::traits::ShutterState::Closed => 1,
                        nightshade_native::traits::ShutterState::Opening => 2,
                        nightshade_native::traits::ShutterState::Closing => 3,
                        nightshade_native::traits::ShutterState::Error => 4,
                        nightshade_native::traits::ShutterState::Unknown => 5,
                    };
                    return Ok(code);
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Park dome
    pub async fn dome_park(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.park().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.park().await.map_err(|e| e.to_string());
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_switch(&device_name, "DOME_PARK", "PARK", true).await.map_err(|e| e.to_string());
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_domes = self.native_domes.write().await;
                if let Some(dome) = native_domes.get_mut(device_id) {
                    return dome.park().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Check if dome is slewing
    pub async fn dome_is_slewing(&self, device_id: &str) -> Result<bool, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.slewing().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.slewing().await.map_err(|e| e.to_string());
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    let az_busy = locked
                        .is_property_busy(&device_name, "ABS_DOME_POSITION")
                        .await;
                    let shutter_busy = locked.is_property_busy(&device_name, "DOME_SHUTTER").await;
                    return Ok(az_busy || shutter_busy);
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let native_domes = self.native_domes.read().await;
                if let Some(dome) = native_domes.get(device_id) {
                    return dome.is_slewing().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Get comprehensive dome status
    pub async fn dome_get_status(
        &self,
        device_id: &str,
    ) -> Result<crate::device::DomeStatus, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    // Get status from Alpaca dome
                    let alpaca_status = dome.get_status().await?;

                    // Query capabilities
                    let can_set_altitude = dome.can_set_altitude().await.map_err(|e| {
                        format!(
                            "Failed to query Alpaca dome can_set_altitude for {}: {}",
                            device_id, e
                        )
                    })?;
                    let can_set_azimuth = dome.can_set_azimuth().await.map_err(|e| {
                        format!(
                            "Failed to query Alpaca dome can_set_azimuth for {}: {}",
                            device_id, e
                        )
                    })?;
                    let can_set_shutter = dome.can_set_shutter().await.map_err(|e| {
                        format!(
                            "Failed to query Alpaca dome can_set_shutter for {}: {}",
                            device_id, e
                        )
                    })?;
                    let can_slave = dome.can_slave().await.map_err(|e| {
                        format!("Failed to query Alpaca dome can_slave for {}: {}", device_id, e)
                    })?;

                    return Ok(crate::device::DomeStatus {
                        connected: true,
                        azimuth: alpaca_status.azimuth,
                        altitude: alpaca_status.altitude,
                        shutter_status: match alpaca_status.shutter_status {
                            nightshade_alpaca::ShutterStatus::Open => crate::device::ShutterState::Open,
                            nightshade_alpaca::ShutterStatus::Closed => crate::device::ShutterState::Closed,
                            nightshade_alpaca::ShutterStatus::Opening => crate::device::ShutterState::Opening,
                            nightshade_alpaca::ShutterStatus::Closing => crate::device::ShutterState::Closing,
                            nightshade_alpaca::ShutterStatus::Error => crate::device::ShutterState::Error,
                        },
                        slewing: alpaca_status.slewing,
                        at_home: alpaca_status.at_home,
                        at_park: alpaca_status.at_park,
                        can_set_altitude,
                        can_set_azimuth,
                        can_set_shutter,
                        can_slave,
                        is_slaved: alpaca_status.slaved,
                    });
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;

                        // Query all dome properties from ASCOM driver
                        let shutter_status_code = match dome_guard.shutter_status().await {
                            Ok(s) => s,
                            Err(e) => {
                                warn!("Failed to read ASCOM dome shutter_status for {}: {}. Using error code 4.", device_id, e);
                                4 // Error state
                            }
                        };
                        let slewing = dome_guard.slewing().await.map_err(|e| {
                            format!("Failed to read ASCOM dome slewing for {}: {}", device_id, e)
                        })?;
                        let at_park = dome_guard.at_park().await.map_err(|e| {
                            format!("Failed to read ASCOM dome at_park for {}: {}", device_id, e)
                        })?;

                        // Map ASCOM shutter status codes to ShutterState
                        let shutter_status = match shutter_status_code {
                            0 => crate::device::ShutterState::Open,
                            1 => crate::device::ShutterState::Closed,
                            2 => crate::device::ShutterState::Opening,
                            3 => crate::device::ShutterState::Closing,
                            4 => crate::device::ShutterState::Error,
                            _ => crate::device::ShutterState::Unknown,
                        };

                        return Ok(crate::device::DomeStatus {
                            connected: true,
                            azimuth: 0.0, // ASCOM domes don't always expose azimuth
                            altitude: None, // ASCOM domes typically don't have altitude
                            shutter_status,
                            slewing,
                            at_home: false, // ASCOM dome interface doesn't have at_home
                            at_park,
                            can_set_altitude: false,
                            can_set_azimuth: false, // Could query CanSetAzimuth if needed
                            can_set_shutter: true, // All ASCOM domes have shutter control
                            can_slave: false,
                            is_slaved: false,
                        });
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;

                    let azimuth = locked
                        .get_number(&device_name, "ABS_DOME_POSITION", "DOME_ABSOLUTE_POSITION")
                        .await
                        .ok_or_else(|| format!("Failed to read INDI dome azimuth for {}", device_id))?;
                    let can_set_azimuth = true;

                    let shutter_open = locked
                        .get_switch(&device_name, "DOME_SHUTTER", "SHUTTER_OPEN")
                        .await;
                    let shutter_close = locked
                        .get_switch(&device_name, "DOME_SHUTTER", "SHUTTER_CLOSE")
                        .await;
                    let shutter_busy = locked.is_property_busy(&device_name, "DOME_SHUTTER").await;

                    let shutter_status = match (shutter_open, shutter_close, shutter_busy) {
                        (Some(true), Some(false), true) => crate::device::ShutterState::Opening,
                        (Some(false), Some(true), true) => crate::device::ShutterState::Closing,
                        (Some(true), Some(false), false) => crate::device::ShutterState::Open,
                        (Some(false), Some(true), false) => crate::device::ShutterState::Closed,
                        _ => crate::device::ShutterState::Unknown,
                    };

                    let azimuth_busy = locked
                        .is_property_busy(&device_name, "ABS_DOME_POSITION")
                        .await;
                    let slewing = azimuth_busy || shutter_busy;

                    let at_home = locked
                        .get_switch(&device_name, "DOME_GOTO", "DOME_HOME")
                        .await
                        .unwrap_or(false);
                    let at_park = locked
                        .get_switch(&device_name, "DOME_PARK", "PARK")
                        .await
                        .unwrap_or(false)
                        || locked
                            .get_switch(&device_name, "DOME_GOTO", "DOME_PARK")
                            .await
                            .unwrap_or(false);

                    let can_set_shutter = shutter_open.is_some() || shutter_close.is_some();

                    let autosync_enable = locked
                        .get_switch(&device_name, "DOME_AUTOSYNC", "DOME_AUTOSYNC_ENABLE")
                        .await;
                    let autosync_disable = locked
                        .get_switch(&device_name, "DOME_AUTOSYNC", "DOME_AUTOSYNC_DISABLE")
                        .await;
                    let can_slave = autosync_enable.is_some() || autosync_disable.is_some();
                    let is_slaved = autosync_enable.unwrap_or(false);

                    return Ok(crate::device::DomeStatus {
                        connected: true,
                        azimuth,
                        altitude: None,
                        shutter_status,
                        slewing,
                        at_home,
                        at_park,
                        can_set_altitude: false,
                        can_set_azimuth,
                        can_set_shutter,
                        can_slave,
                        is_slaved,
                    });
                }

                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let native_domes = self.native_domes.read().await;
                if let Some(dome) = native_domes.get(device_id) {
                    // Query all native dome properties
                    let azimuth = dome.get_azimuth().await.map_err(|e| {
                        format!("Failed to read native dome azimuth for {}: {}", device_id, e)
                    })?;
                    let altitude = dome.get_altitude().await.ok().flatten();
                    let shutter_state_native = match dome.get_shutter_status().await {
                        Ok(s) => s,
                        Err(nightshade_native::traits::NativeError::NotSupported) => {
                            nightshade_native::traits::ShutterState::Unknown
                        }
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome shutter status for {}: {}",
                                device_id, e
                            ));
                        }
                    };
                    let shutter_status = match shutter_state_native {
                        nightshade_native::traits::ShutterState::Open => crate::device::ShutterState::Open,
                        nightshade_native::traits::ShutterState::Closed => crate::device::ShutterState::Closed,
                        nightshade_native::traits::ShutterState::Opening => crate::device::ShutterState::Opening,
                        nightshade_native::traits::ShutterState::Closing => crate::device::ShutterState::Closing,
                        nightshade_native::traits::ShutterState::Error => crate::device::ShutterState::Error,
                        nightshade_native::traits::ShutterState::Unknown => crate::device::ShutterState::Unknown,
                    };
                    let slewing = match dome.is_slewing().await {
                        Ok(s) => s,
                        Err(nightshade_native::traits::NativeError::NotSupported) => false,
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome slewing for {}: {}",
                                device_id, e
                            ));
                        }
                    };
                    let at_home = match dome.is_at_home().await {
                        Ok(h) => h,
                        Err(nightshade_native::traits::NativeError::NotSupported) => false,
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome is_at_home for {}: {}",
                                device_id, e
                            ));
                        }
                    };
                    let at_park = match dome.is_parked().await {
                        Ok(p) => p,
                        Err(nightshade_native::traits::NativeError::NotSupported) => false,
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome is_parked for {}: {}",
                                device_id, e
                            ));
                        }
                    };
                    let is_slaved = match dome.is_slaved().await {
                        Ok(s) => s,
                        Err(nightshade_native::traits::NativeError::NotSupported) => false,
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome is_slaved for {}: {}",
                                device_id, e
                            ));
                        }
                    };

                    return Ok(crate::device::DomeStatus {
                        connected: true,
                        azimuth,
                        altitude,
                        shutter_status,
                        slewing,
                        at_home,
                        at_park,
                        can_set_altitude: dome.can_set_altitude(),
                        can_set_azimuth: dome.can_set_azimuth(),
                        can_set_shutter: dome.can_set_shutter(),
                        can_slave: dome.can_slave(),
                        is_slaved,
                    });
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }
}
