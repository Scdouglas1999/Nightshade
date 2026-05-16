//! Mount operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.
//!
//! # `unwrap_or` policy (audit-rust §4.3)
//!
//! Two patterns:
//!
//! * `availability.get(field).cloned().unwrap_or(FieldAvailability::Available)`
//!   — when ALTITUDE was probed earlier in the function, we mirror its
//!   availability onto AZIMUTH (they share a single ASCOM round-trip).
//!   `Available` is the safe default — both fields ARE available if the
//!   underlying probe succeeded; the only way the lookup misses is if
//!   the upstream code raced, in which case AZIMUTH appearing as
//!   "Available" matches the actual mount state.
//! * `mount.can_set_tracking().await.unwrap_or(false)` — ASCOM optional
//!   `CanSetTracking` probe; absence means "cannot set tracking rate",
//!   the safe assumption (UI hides the tracking-rate dropdown).

use crate::device::*;
use crate::device_manager::DeviceManager;
use nightshade_native::traits::NativeMount;
use std::collections::HashMap;
use std::time::Duration;
use tracing::warn;

impl DeviceManager {
    // =========================================================================
    // Mount Control
    // =========================================================================

    pub async fn mount_slew(&self, device_id: &str, ra: f64, dec: f64) -> Result<(), String> {
        tracing::debug!(
            "mount_slew called: device_id={}, ra={}, dec={}",
            device_id,
            ra,
            dec
        );

        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| {
                tracing::error!("mount_slew: Device not found in devices map: {}", device_id);
                format!("Device not found: {}", device_id)
            })?;

        tracing::debug!(
            "mount_slew: Found device with driver_type={:?}",
            info.driver_type
        );

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    tracing::debug!("mount_slew: ascom_mounts contains {} entries", mounts.len());
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.slew_to_coordinates(ra, dec).await.map_err(|e| {
                            tracing::error!("mount_slew ASCOM error: {}", e);
                            e.to_string()
                        });
                    } else {
                        tracing::error!("mount_slew: Mount {} not found in ascom_mounts. Available: {:?}",
                            device_id, mounts.keys().collect::<Vec<_>>());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    tracing::debug!("mount_slew: Calling Alpaca slew_to_coordinates_async");
                    return mount.slew_to_coordinates_async(ra, dec).await.map_err(|e| {
                        tracing::error!("mount_slew Alpaca error: {}", e);
                        e
                    });
                }
                tracing::error!("mount_slew: Alpaca mount {} not connected", device_id);
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        tracing::debug!("mount_slew: Creating INDI mount wrapper for {}", device_name);
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.slew_to_coordinates(ra, dec).await.map_err(|e| {
                            tracing::error!("mount_slew INDI error: {}", e);
                            e.to_string()
                        });
                    }
                    tracing::error!("mount_slew: INDI client not connected for {}", server_key);
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.slew_to_coordinates(ra, dec).await.map_err(|e| {
                        tracing::error!("mount_slew Native error: {}", e);
                        e.to_string()
                    });
                }
                tracing::error!("mount_slew: Native mount {} not connected", device_id);
                Err("Native mount not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_sync(&self, device_id: &str, ra: f64, dec: f64) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.sync_to_coordinates(ra, dec).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.sync_to_coordinates(ra, dec).await;
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.sync_to_coordinates(ra, dec).await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.sync_to_coordinates(ra, dec).await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_park(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.park().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.park().await;
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.park().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.park().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_unpark(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.unpark().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.unpark().await;
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.unpark().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.unpark().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_slew_alt_az(
        &self,
        device_id: &str,
        altitude: f64,
        azimuth: f64,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.write().await;
                        return mount.slew_to_alt_az(altitude, azimuth).await.map_err(|e| {
                            tracing::error!("mount_slew_alt_az ASCOM error: {}", e);
                            e.to_string()
                        });
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.slew_to_alt_az_async(altitude, azimuth).await.map_err(|e| {
                        tracing::error!("mount_slew_alt_az Alpaca error: {}", e);
                        e
                    });
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.slew_to_alt_az(altitude, azimuth).await.map_err(|e| {
                            tracing::error!("mount_slew_alt_az INDI error: {}", e);
                            e.to_string()
                        });
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                // Native mounts (SkyWatcher, iOptron, etc.) are equatorial; alt/az slew is not
                // natively supported. Return an error rather than silently failing.
                Err("Alt/Az slew is not supported for native serial mounts".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_find_home(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.write().await;
                        return mount.find_home().await.map_err(|e| {
                            tracing::error!("mount_find_home ASCOM error: {}", e);
                            e.to_string()
                        });
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.find_home().await.map_err(|e| {
                        tracing::error!("mount_find_home Alpaca error: {}", e);
                        e
                    });
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.find_home().await.map_err(|e| {
                            tracing::error!("mount_find_home INDI error: {}", e);
                            e.to_string()
                        });
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                // Native serial mounts don't have a standardized find-home command
                Err("Find home is not supported for native serial mounts".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_get_coordinates(&self, device_id: &str) -> Result<(f64, f64), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.get_coordinates().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    return mount.get_coordinates().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    let ra = mount.right_ascension().await.map_err(|e| e.to_string())?;
                    let dec = mount.declination().await.map_err(|e| e.to_string())?;
                    return Ok((ra, dec));
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.get_coordinates().await;
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_abort(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.abort_slew().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.abort_slew().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.abort_slew().await.map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.abort_slew().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_stop(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.stop().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.abort_slew().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.abort_slew().await.map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.abort_slew().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_set_tracking(&self, device_id: &str, enabled: bool) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.set_tracking(enabled).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.set_tracking(enabled).await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.set_tracking(enabled).await.map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.set_tracking(enabled).await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_pulse_guide(
        &self,
        device_id: &str,
        direction: String,
        duration_ms: u32,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        let direction_lower = direction.to_lowercase();
        let dir = match direction_lower.as_str() {
            "north" | "n" => nightshade_native::traits::GuideDirection::North,
            "south" | "s" => nightshade_native::traits::GuideDirection::South,
            "east" | "e" => nightshade_native::traits::GuideDirection::East,
            "west" | "w" => nightshade_native::traits::GuideDirection::West,
            _ => return Err(format!("Invalid direction: {}", direction)),
        };

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.pulse_guide(dir, duration_ms).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.pulse_guide(dir, duration_ms).await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    let alpaca_dir = match dir {
                        nightshade_native::traits::GuideDirection::North => 0,
                        nightshade_native::traits::GuideDirection::South => 1,
                        nightshade_native::traits::GuideDirection::East => 2,
                        nightshade_native::traits::GuideDirection::West => 3,
                    };
                    // Why (audit-rust §1.4): Alpaca PulseGuide takes i32 ms;
                    // u32 > i32::MAX is ~24.8 days of pulse which is
                    // physically impossible for guiding. Saturating
                    // try_from rejects the impossible-but-defined case.
                    let duration_i32 = i32::try_from(duration_ms).map_err(|_| {
                        format!(
                            "Alpaca pulse_guide duration {}ms exceeds i32::MAX",
                            duration_ms
                        )
                    })?;
                    return mount
                        .pulse_guide(alpaca_dir, duration_i32)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        match dir {
                            nightshade_native::traits::GuideDirection::North => {
                                mount.move_north(true).await.map_err(|e| e.to_string())?;
                                // Why (audit-rust §1.4): u32 → u64 widening for sleep duration, exact.
                                tokio::time::sleep(Duration::from_millis(u64::from(duration_ms))).await;
                                mount.move_north(false).await.map_err(|e| e.to_string())?;
                            }
                            nightshade_native::traits::GuideDirection::South => {
                                mount.move_south(true).await.map_err(|e| e.to_string())?;
                                // Why (audit-rust §1.4): u32 → u64 widening for sleep duration, exact.
                                tokio::time::sleep(Duration::from_millis(u64::from(duration_ms))).await;
                                mount.move_south(false).await.map_err(|e| e.to_string())?;
                            }
                            nightshade_native::traits::GuideDirection::East => {
                                mount.move_east(true).await.map_err(|e| e.to_string())?;
                                // Why (audit-rust §1.4): u32 → u64 widening for sleep duration, exact.
                                tokio::time::sleep(Duration::from_millis(u64::from(duration_ms))).await;
                                mount.move_east(false).await.map_err(|e| e.to_string())?;
                            }
                            nightshade_native::traits::GuideDirection::West => {
                                mount.move_west(true).await.map_err(|e| e.to_string())?;
                                // Why (audit-rust §1.4): u32 → u64 widening for sleep duration, exact.
                                tokio::time::sleep(Duration::from_millis(u64::from(duration_ms))).await;
                                mount.move_west(false).await.map_err(|e| e.to_string())?;
                            }
                        }
                        return Ok(());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_can_park(&self, device_id: &str) -> Result<bool, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.can_park().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    return match mount.is_parked().await {
                        Ok(_) => Ok(true),
                        Err(nightshade_native::traits::NativeError::NotSupported) => Ok(false),
                        Err(e) => Err(format!(
                            "Failed to determine native mount park capability for {}: {}",
                            device_id, e
                        )),
                    };
                }
                Err(format!("Native mount {} not connected", device_id))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.can_park().await.map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let locked = client.read().await;
                        let supports_park = locked
                            .get_switch(&device_name, "TELESCOPE_PARK", "PARK")
                            .await
                            .is_some()
                            || locked
                                .get_switch(&device_name, "TELESCOPE_PARK", "UNPARK")
                                .await
                                .is_some();
                        return Ok(supports_park);
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_get_status(&self, device_id: &str) -> Result<MountStatus, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;

                        // Required fields propagate read failures — these are not optional.
                        let (ra, dec) = mount.get_coordinates().await.map_err(|e| e.to_string())?;
                        let tracking = mount.get_tracking().await.map_err(|e| e.to_string())?;
                        let slewing = mount.is_slewing().await.map_err(|e| e.to_string())?;
                        let parked = mount.is_parked().await.map_err(|e| e.to_string())?;

                        let mut availability: HashMap<String, FieldAvailability> = HashMap::new();

                        // Optional fields: the ASCOM wrapper currently does not surface a
                        // distinct "not supported" error so any failure is recorded as Error.
                        let (alt_opt, az_opt) = match mount.get_alt_az().await {
                            Ok((a, z)) => (Some(a), Some(z)),
                            Err(e) => {
                                let msg = e.to_string();
                                availability.insert(
                                    mount_status_field::ALTITUDE.to_string(),
                                    FieldAvailability::Error(msg.clone()),
                                );
                                availability.insert(
                                    mount_status_field::AZIMUTH.to_string(),
                                    FieldAvailability::Error(msg),
                                );
                                (None, None)
                            }
                        };
                        if alt_opt.is_some() {
                            availability.insert(
                                mount_status_field::ALTITUDE.to_string(),
                                FieldAvailability::Available,
                            );
                            availability.insert(
                                mount_status_field::AZIMUTH.to_string(),
                                FieldAvailability::Available,
                            );
                        }

                        let side_of_pier_opt = Self::availability_from_native_result(
                            mount.get_side_of_pier().await,
                            mount_status_field::SIDE_OF_PIER,
                            &mut availability,
                        )
                        .map(Self::pier_side_from_native);

                        let sidereal_time_opt = Self::availability_from_native_result(
                            mount.get_sidereal_time().await,
                            mount_status_field::SIDEREAL_TIME,
                            &mut availability,
                        );

                        // ASCOM wrapper does not yet expose AtHome — record as Unsupported
                        // rather than fabricating false. Driver work tracked separately.
                        availability.insert(
                            mount_status_field::AT_HOME.to_string(),
                            FieldAvailability::Unsupported,
                        );

                        let capabilities = match mount.get_capabilities().await {
                            Ok(caps) => caps,
                            Err(err) => {
                                warn!(
                                    "Failed to query ASCOM mount capabilities for {}: {}. Marking capabilities unavailable.",
                                    device_id, err
                                );
                                crate::ascom_wrapper_mount::AscomMountCapabilities::default()
                            }
                        };

                        let (tracking_rate_opt, can_set_tracking_rate) = match mount
                            .get_tracking_rate()
                            .await
                        {
                            Ok(rate) => {
                                availability.insert(
                                    mount_status_field::TRACKING_RATE.to_string(),
                                    FieldAvailability::Available,
                                );
                                (Some(Self::tracking_rate_from_native(rate)), true)
                            }
                            Err(nightshade_native::traits::NativeError::NotSupported) => {
                                availability.insert(
                                    mount_status_field::TRACKING_RATE.to_string(),
                                    FieldAvailability::Unsupported,
                                );
                                (None, false)
                            }
                            Err(err) => {
                                availability.insert(
                                    mount_status_field::TRACKING_RATE.to_string(),
                                    FieldAvailability::Error(err.to_string()),
                                );
                                (None, false)
                            }
                        };

                        return Ok(MountStatus {
                            connected: true,
                            tracking,
                            slewing,
                            parked,
                            at_home: None,
                            side_of_pier: side_of_pier_opt,
                            right_ascension: ra,
                            declination: dec,
                            altitude: alt_opt,
                            azimuth: az_opt,
                            sidereal_time: sidereal_time_opt,
                            tracking_rate: tracking_rate_opt,
                            can_park: capabilities.can_park,
                            can_slew: capabilities.can_slew,
                            can_sync: capabilities.can_sync,
                            can_pulse_guide: capabilities.can_pulse_guide,
                            can_set_tracking_rate,
                            availability,
                        });
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    // Required fields propagate read failures — these are not optional.
                    let (ra, dec) = mount.get_coordinates().await.map_err(|e| e.to_string())?;
                    let tracking = mount.get_tracking().await.map_err(|e| e.to_string())?;
                    let slewing = mount.is_slewing().await.map_err(|e| e.to_string())?;
                    let (parked, can_park) = match mount.is_parked().await {
                        Ok(p) => (p, true),
                        Err(nightshade_native::traits::NativeError::NotSupported) => (false, false),
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native mount parked state for {}: {}",
                                device_id, e
                            ));
                        }
                    };

                    let mut availability: HashMap<String, FieldAvailability> = HashMap::new();

                    // get_side_of_pier on `NativeMount` returns Unknown rather than Err
                    // for unsupported mounts (e.g. SkyWatcher), so distinguish here:
                    // Unknown → Unsupported availability; East/West → Available.
                    let side_of_pier_opt = match mount.get_side_of_pier().await {
                        Ok(nightshade_native::traits::PierSide::Unknown) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Ok(other) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Available,
                            );
                            Some(Self::pier_side_from_native(other))
                        }
                        Err(nightshade_native::traits::NativeError::NotSupported) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Err(e) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Error(e.to_string()),
                            );
                            None
                        }
                    };

                    // Native drivers report Err(NotSupported) explicitly for alt/az and
                    // sidereal time on protocols that lack them (e.g. SkyWatcher, LX200).
                    let alt_az_pair = Self::availability_from_native_result(
                        mount.get_alt_az().await,
                        // Use ALTITUDE as primary key; AZIMUTH mirror is set below.
                        mount_status_field::ALTITUDE,
                        &mut availability,
                    );
                    // Mirror availability onto the AZIMUTH key — they share a single call.
                    let alt_avail = availability
                        .get(mount_status_field::ALTITUDE)
                        .cloned()
                        .unwrap_or(FieldAvailability::Available);
                    availability
                        .insert(mount_status_field::AZIMUTH.to_string(), alt_avail);
                    let (alt_opt, az_opt) = match alt_az_pair {
                        Some((a, z)) => (Some(a), Some(z)),
                        None => (None, None),
                    };

                    let sidereal_time_opt = Self::availability_from_native_result(
                        mount.get_sidereal_time().await,
                        mount_status_field::SIDEREAL_TIME,
                        &mut availability,
                    );

                    // Native mount trait does not currently surface AtHome.
                    availability.insert(
                        mount_status_field::AT_HOME.to_string(),
                        FieldAvailability::Unsupported,
                    );

                    let tracking_rate_opt = Self::availability_from_native_result(
                        mount.get_tracking_rate().await,
                        mount_status_field::TRACKING_RATE,
                        &mut availability,
                    )
                    .map(Self::tracking_rate_from_native);

                    return Ok(MountStatus {
                        connected: true,
                        tracking,
                        slewing,
                        parked,
                        at_home: None,
                        side_of_pier: side_of_pier_opt,
                        right_ascension: ra,
                        declination: dec,
                        altitude: alt_opt,
                        azimuth: az_opt,
                        sidereal_time: sidereal_time_opt,
                        tracking_rate: tracking_rate_opt,
                        can_park,
                        can_slew: mount.can_slew(),
                        can_sync: mount.can_sync(),
                        can_pulse_guide: mount.can_pulse_guide(),
                        can_set_tracking_rate: mount.can_set_tracking_rate(),
                        availability,
                    });
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    // Required fields propagate read failures.
                    let ra = mount.right_ascension().await.map_err(|e| {
                        format!("Failed to read Alpaca mount RA for {}: {}", device_id, e)
                    })?;
                    let dec = mount.declination().await.map_err(|e| {
                        format!("Failed to read Alpaca mount Dec for {}: {}", device_id, e)
                    })?;
                    let tracking = mount.tracking().await.map_err(|e| {
                        format!("Failed to read Alpaca mount tracking for {}: {}", device_id, e)
                    })?;
                    let slewing = mount.slewing().await.map_err(|e| {
                        format!("Failed to read Alpaca mount slewing for {}: {}", device_id, e)
                    })?;
                    let parked = mount.at_park().await.map_err(|e| {
                        format!("Failed to read Alpaca mount at_park for {}: {}", device_id, e)
                    })?;

                    let mut availability: HashMap<String, FieldAvailability> = HashMap::new();

                    // Alpaca returns Result<_, String>; we cannot reliably distinguish
                    // "PropertyNotImplemented" from a transient HTTP failure without
                    // parsing the error message. Treat all failures as Error so callers
                    // see the underlying reason verbatim. UI can match on the prefix
                    // "PropertyNotImplemented" if it wants to render Unsupported.
                    let alt_opt = Self::availability_from_string_result(
                        mount.altitude().await,
                        mount_status_field::ALTITUDE,
                        &mut availability,
                    );
                    let az_opt = Self::availability_from_string_result(
                        mount.azimuth().await,
                        mount_status_field::AZIMUTH,
                        &mut availability,
                    );
                    let at_home_opt = Self::availability_from_string_result(
                        mount.at_home().await,
                        mount_status_field::AT_HOME,
                        &mut availability,
                    );
                    let sidereal_time_opt = Self::availability_from_string_result(
                        mount.sidereal_time().await,
                        mount_status_field::SIDEREAL_TIME,
                        &mut availability,
                    );

                    let side_of_pier_opt = match mount.side_of_pier().await {
                        Ok(nightshade_alpaca::PierSide::Unknown) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Ok(other) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Available,
                            );
                            Some(match other {
                                nightshade_alpaca::PierSide::East => crate::device::PierSide::East,
                                nightshade_alpaca::PierSide::West => crate::device::PierSide::West,
                                nightshade_alpaca::PierSide::Unknown => {
                                    crate::device::PierSide::Unknown
                                }
                            })
                        }
                        Err(e) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Error(e),
                            );
                            None
                        }
                    };

                    let (can_park, can_slew, can_sync, can_pulse_guide) =
                        match mount.get_capabilities().await {
                            Ok(caps) => (
                                caps.can_park,
                                caps.can_slew,
                                caps.can_sync,
                                caps.can_pulse_guide,
                            ),
                            Err(e) => {
                                warn!(
                                    "Failed to query Alpaca mount capabilities for {}: {}. Marking capabilities unsupported.",
                                    device_id, e
                                );
                                (false, false, false, false)
                            }
                        };
                    let can_set_tracking_rate = mount.can_set_tracking().await.unwrap_or(false);

                    let tracking_rate_opt = match mount.tracking_rate().await {
                        Ok(rate) => {
                            availability.insert(
                                mount_status_field::TRACKING_RATE.to_string(),
                                FieldAvailability::Available,
                            );
                            Some(match rate {
                                nightshade_alpaca::DriveRate::Sidereal => TrackingRate::Sidereal,
                                nightshade_alpaca::DriveRate::Lunar => TrackingRate::Lunar,
                                nightshade_alpaca::DriveRate::Solar => TrackingRate::Solar,
                                nightshade_alpaca::DriveRate::King => TrackingRate::King,
                            })
                        }
                        Err(e) => {
                            availability.insert(
                                mount_status_field::TRACKING_RATE.to_string(),
                                FieldAvailability::Error(e),
                            );
                            None
                        }
                    };

                    return Ok(MountStatus {
                        connected: true,
                        tracking,
                        slewing,
                        parked,
                        at_home: at_home_opt,
                        side_of_pier: side_of_pier_opt,
                        right_ascension: ra,
                        declination: dec,
                        altitude: alt_opt,
                        azimuth: az_opt,
                        sidereal_time: sidereal_time_opt,
                        tracking_rate: tracking_rate_opt,
                        can_park,
                        can_slew,
                        can_sync,
                        can_pulse_guide,
                        can_set_tracking_rate,
                        availability,
                    });
                }
                Err("Alpaca mount not connected".to_string())
            }
            DriverType::Indi => {
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                    let (ra, dec) = mount.get_coordinates().await.map_err(|e| {
                        format!(
                            "Failed to read INDI mount coordinates for {}: {}",
                            device_id, e
                        )
                    })?;
                    let tracking = mount.try_is_tracking().await.map_err(|e| {
                        format!("Failed to read INDI mount tracking for {}: {}", device_id, e)
                    })?;
                    let slewing = mount.try_is_slewing().await.map_err(|e| {
                        format!("Failed to read INDI mount slewing for {}: {}", device_id, e)
                    })?;
                    let parked = mount.try_is_parked().await.map_err(|e| {
                        format!("Failed to read INDI mount parked state for {}: {}", device_id, e)
                    })?;

                    let mut availability: HashMap<String, FieldAvailability> = HashMap::new();

                    let (alt_opt, az_opt) = match mount.get_horizontal_coordinates().await {
                        Ok((a, z)) => {
                            availability.insert(
                                mount_status_field::ALTITUDE.to_string(),
                                FieldAvailability::Available,
                            );
                            availability.insert(
                                mount_status_field::AZIMUTH.to_string(),
                                FieldAvailability::Available,
                            );
                            (Some(a), Some(z))
                        }
                        Err(e) => {
                            availability.insert(
                                mount_status_field::ALTITUDE.to_string(),
                                FieldAvailability::Error(e.clone()),
                            );
                            availability.insert(
                                mount_status_field::AZIMUTH.to_string(),
                                FieldAvailability::Error(e),
                            );
                            (None, None)
                        }
                    };

                    let locked = client.read().await;
                    let (can_park, can_slew, can_sync, can_pulse_guide) = {
                        let can_park = locked
                            .get_switch(&device_name, "TELESCOPE_PARK", "PARK")
                            .await
                            .is_some()
                            || locked
                                .get_switch(&device_name, "TELESCOPE_PARK", "UNPARK")
                                .await
                                .is_some();
                        let can_slew = locked
                            .get_switch(&device_name, "ON_COORD_SET", "SLEW")
                            .await
                            .is_some();
                        let can_sync = locked
                            .get_switch(&device_name, "ON_COORD_SET", "SYNC")
                            .await
                            .is_some();
                        let can_pulse_guide = locked
                            .get_switch(&device_name, "TELESCOPE_MOTION_NS", "MOTION_NORTH")
                            .await
                            .is_some()
                            && locked
                                .get_switch(
                                    &device_name,
                                    "TELESCOPE_MOTION_NS",
                                    "MOTION_SOUTH",
                                )
                                .await
                                .is_some()
                            && locked
                                .get_switch(&device_name, "TELESCOPE_MOTION_WE", "MOTION_EAST")
                                .await
                                .is_some()
                            && locked
                                .get_switch(&device_name, "TELESCOPE_MOTION_WE", "MOTION_WEST")
                                .await
                                .is_some();
                        (can_park, can_slew, can_sync, can_pulse_guide)
                    };
                    let (tracking_rate_native, can_set_tracking_rate) =
                        Self::indi_mount_tracking_rate(&locked, &device_name).await;
                    let tracking_rate_opt = if can_set_tracking_rate {
                        availability.insert(
                            mount_status_field::TRACKING_RATE.to_string(),
                            FieldAvailability::Available,
                        );
                        Some(tracking_rate_native)
                    } else {
                        // INDI helper currently signals "no tracking-rate property" by
                        // returning false for the second tuple element; treat that as
                        // Unsupported rather than asserting Sidereal.
                        availability.insert(
                            mount_status_field::TRACKING_RATE.to_string(),
                            FieldAvailability::Unsupported,
                        );
                        None
                    };

                    // INDI does not standardise an at-home property, and TIME_LST is
                    // optional — record both as Unsupported until per-driver support
                    // can be added.
                    availability.insert(
                        mount_status_field::AT_HOME.to_string(),
                        FieldAvailability::Unsupported,
                    );
                    availability.insert(
                        mount_status_field::SIDEREAL_TIME.to_string(),
                        FieldAvailability::Unsupported,
                    );
                    // Pier side recovery from INDI requires per-driver heuristics; mark
                    // Unsupported for now so the sequencer refuses meridian flips.
                    availability.insert(
                        mount_status_field::SIDE_OF_PIER.to_string(),
                        FieldAvailability::Unsupported,
                    );

                    return Ok(MountStatus {
                        connected: true,
                        tracking,
                        slewing,
                        parked,
                        at_home: None,
                        side_of_pier: None,
                        right_ascension: ra,
                        declination: dec,
                        altitude: alt_opt,
                        azimuth: az_opt,
                        sidereal_time: None,
                        tracking_rate: tracking_rate_opt,
                        can_park,
                        can_slew,
                        can_sync,
                        can_pulse_guide,
                        can_set_tracking_rate,
                        availability,
                    });
                }
                Err(format!("INDI client not connected for {}", server_key))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    /// Convert a `Result<T, NativeError>` into `(Option<T>, FieldAvailability)`,
    /// inserting the availability entry under `field` and returning the value.
    ///
    /// Used by `mount_get_status` so each per-field branch shrinks to one call
    /// instead of duplicating the same availability/log scaffolding.
    fn availability_from_native_result<T>(
        result: Result<T, nightshade_native::traits::NativeError>,
        field: &'static str,
        availability: &mut HashMap<String, FieldAvailability>,
    ) -> Option<T> {
        match result {
            Ok(v) => {
                availability.insert(field.to_string(), FieldAvailability::Available);
                Some(v)
            }
            Err(nightshade_native::traits::NativeError::NotSupported) => {
                availability.insert(field.to_string(), FieldAvailability::Unsupported);
                None
            }
            Err(e) => {
                availability.insert(field.to_string(), FieldAvailability::Error(e.to_string()));
                None
            }
        }
    }

    /// Same shape as `availability_from_native_result` but for drivers that
    /// surface errors as plain `String` (Alpaca, INDI). Without a typed
    /// "unsupported" variant we always classify failures as `Error(reason)`.
    fn availability_from_string_result<T>(
        result: Result<T, String>,
        field: &'static str,
        availability: &mut HashMap<String, FieldAvailability>,
    ) -> Option<T> {
        match result {
            Ok(v) => {
                availability.insert(field.to_string(), FieldAvailability::Available);
                Some(v)
            }
            Err(e) => {
                availability.insert(field.to_string(), FieldAvailability::Error(e));
                None
            }
        }
    }

    fn pier_side_from_native(side: nightshade_native::traits::PierSide) -> crate::device::PierSide {
        match side {
            nightshade_native::traits::PierSide::East => crate::device::PierSide::East,
            nightshade_native::traits::PierSide::West => crate::device::PierSide::West,
            nightshade_native::traits::PierSide::Unknown => crate::device::PierSide::Unknown,
        }
    }

    fn tracking_rate_from_native(rate: nightshade_native::traits::TrackingRate) -> TrackingRate {
        match rate {
            nightshade_native::traits::TrackingRate::Sidereal => TrackingRate::Sidereal,
            nightshade_native::traits::TrackingRate::Lunar => TrackingRate::Lunar,
            nightshade_native::traits::TrackingRate::Solar => TrackingRate::Solar,
            nightshade_native::traits::TrackingRate::King => TrackingRate::King,
            nightshade_native::traits::TrackingRate::Custom => TrackingRate::Custom,
        }
    }

    pub async fn mount_set_tracking_rate(&self, device_id: &str, rate: i32) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount
                            .set_tracking_rate_raw(rate)
                            .await
                            .map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    // Convert i32 rate to TrackingRate enum
                    let tracking_rate = match rate {
                        0 => nightshade_native::traits::TrackingRate::Sidereal,
                        1 => nightshade_native::traits::TrackingRate::Lunar,
                        2 => nightshade_native::traits::TrackingRate::Solar,
                        3 => nightshade_native::traits::TrackingRate::King,
                        4 => nightshade_native::traits::TrackingRate::Custom,
                        _ => return Err(format!("Invalid tracking rate: {}", rate)),
                    };
                    return mount
                        .set_tracking_rate(tracking_rate)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            _ => Err("Setting tracking rate is not supported by this driver type".to_string()),
        }
    }

    pub async fn mount_get_tracking_rate(&self, device_id: &str) -> Result<i32, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount
                            .get_tracking_rate_raw()
                            .await
                            .map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    let rate = mount.get_tracking_rate().await.map_err(|e| e.to_string())?;
                    // Why (audit-rust §1.4): `TrackingRate` is a C-like enum
                    // (Sidereal=0, Lunar=1, Solar=2, King=3); `as i32`
                    // extracts the discriminant — SAFE narrowing.
                    return Ok(rate as i32);
                }
                Err("Native mount not connected".to_string())
            }
            _ => Err("Getting tracking rate is not supported by this driver type".to_string()),
        }
    }

    /// Move an axis at the specified rate (degrees/second)
    /// axis: 0=RA/Azimuth (primary), 1=Dec/Altitude (secondary)
    /// rate: degrees per second (positive = N/E, negative = S/W), 0 to stop
    pub async fn mount_move_axis(
        &self,
        device_id: &str,
        axis: i32,
        rate: f64,
    ) -> Result<(), String> {
        tracing::debug!(
            "mount_move_axis called: device_id={}, axis={}, rate={}",
            device_id,
            axis,
            rate
        );

        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| {
                tracing::error!(
                    "mount_move_axis: Device not found in devices map: {}",
                    device_id
                );
                format!("Device not found: {}", device_id)
            })?;

        tracing::debug!(
            "mount_move_axis: Found device with driver_type={:?}",
            info.driver_type
        );

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    tracing::debug!("mount_move_axis: ascom_mounts contains {} entries", mounts.len());
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.move_axis(axis, rate).await.map_err(|e| {
                            tracing::error!("mount_move_axis ASCOM error: {}", e);
                            e.to_string()
                        });
                    } else {
                        tracing::error!("mount_move_axis: Mount {} not found in ascom_mounts. Available: {:?}",
                            device_id, mounts.keys().collect::<Vec<_>>());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    tracing::debug!("mount_move_axis: Calling Alpaca move_axis");
                    return mount.move_axis(axis, rate).await.map_err(|e| {
                        tracing::error!("mount_move_axis Alpaca error: {}", e);
                        e
                    });
                }
                tracing::error!("mount_move_axis: Alpaca mount {} not connected", device_id);
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                // INDI uses directional movement (NSEW) instead of axis rates
                // We need to map axis/rate to directional commands
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);

                        // Convert axis/rate to directional movement
                        // axis 0 = RA/Az (East/West), axis 1 = Dec/Alt (North/South)
                        // rate > 0 = North/East, rate < 0 = South/West, rate = 0 = stop
                        if axis == 0 {
                            // RA/Azimuth axis
                            if rate > 0.0 {
                                return mount.move_east(true).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (move east): {}", e);
                                    e.to_string()
                                });
                            } else if rate < 0.0 {
                                return mount.move_west(true).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (move west): {}", e);
                                    e.to_string()
                                });
                            } else {
                                // Stop both directions
                                let _ = mount.move_east(false).await;
                                return mount.move_west(false).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (stop RA): {}", e);
                                    e.to_string()
                                });
                            }
                        } else {
                            // Dec/Altitude axis
                            if rate > 0.0 {
                                return mount.move_north(true).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (move north): {}", e);
                                    e.to_string()
                                });
                            } else if rate < 0.0 {
                                return mount.move_south(true).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (move south): {}", e);
                                    e.to_string()
                                });
                            } else {
                                // Stop both directions
                                let _ = mount.move_north(false).await;
                                return mount.move_south(false).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (stop Dec): {}", e);
                                    e.to_string()
                                });
                            }
                        }
                    }
                    tracing::error!("mount_move_axis: INDI client not connected for {}", server_key);
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                tracing::warn!("mount_move_axis: Native SDK does not support mount axis movement");
                Err("Native SDK does not support mount axis movement".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }
}
