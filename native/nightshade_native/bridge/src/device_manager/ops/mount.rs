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
use crate::dispatch::DeviceOpError;
use crate::error::NightshadeError;
use crate::timeout_ops::{mount_slew_with_timeout, with_timeout_str, Timeouts};
use nightshade_native::traits::NativeMount;
use std::collections::HashMap;
use tracing::warn;

impl DeviceManager {
    // =========================================================================
    // Mount Control
    // =========================================================================

    pub async fn mount_slew(&self, device_id: &str, ra: f64, dec: f64) -> Result<(), DeviceOpError> {
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
                DeviceOpError::device_not_found(device_id)
            })?;
        drop(devices);

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
                        return mount_slew_with_timeout(
                            async {
                                mount
                                    .slew_to_coordinates(ra, dec)
                                    .await
                                    .map_err(|e| NightshadeError::OperationFailed(e.to_string()))
                            },
                            device_id,
                            ra,
                            dec,
                            None,
                            None,
                        )
                        .await
                        .map_err(|e| {
                            tracing::error!("mount_slew ASCOM error: {}", e);
                            DeviceOpError::driver(e)
                        });
                    } else {
                        tracing::error!(
                            "mount_slew: Mount {} not found in ascom_mounts. Available: {:?}",
                            device_id,
                            mounts.keys().collect::<Vec<_>>()
                        );
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    tracing::debug!("mount_slew: Calling Alpaca slew_to_coordinates_async");
                    return mount_slew_with_timeout(
                        async {
                            mount
                                .slew_to_coordinates_async(ra, dec)
                                .await
                                .map_err(NightshadeError::OperationFailed)
                        },
                        device_id,
                        ra,
                        dec,
                        None,
                        None,
                    )
                    .await
                    .map_err(|e| {
                        tracing::error!("mount_slew Alpaca error: {}", e);
                        DeviceOpError::driver(e)
                    });
                }
                tracing::error!("mount_slew: Alpaca mount {} not connected", device_id);
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
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
                        tracing::debug!(
                            "mount_slew: Creating INDI mount wrapper for {}",
                            device_name
                        );
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount_slew_with_timeout(
                            async {
                                mount
                                    .slew_to_coordinates(ra, dec)
                                    .await
                                    .map_err(|e| NightshadeError::OperationFailed(e.to_string()))
                            },
                            device_id,
                            ra,
                            dec,
                            None,
                            None,
                        )
                        .await
                        .map_err(|e| {
                            tracing::error!("mount_slew INDI error: {}", e);
                            DeviceOpError::driver(e)
                        });
                    }
                    tracing::error!("mount_slew: INDI client not connected for {}", server_key);
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount_slew_with_timeout(
                        async {
                            mount
                                .slew_to_coordinates(ra, dec)
                                .await
                                .map_err(|e| NightshadeError::OperationFailed(e.to_string()))
                        },
                        device_id,
                        ra,
                        dec,
                        None,
                        None,
                    )
                    .await
                    .map_err(|e| {
                        tracing::error!("mount_slew Native error: {}", e);
                        DeviceOpError::driver(e)
                    });
                }
                tracing::error!("mount_slew: Native mount {} not connected", device_id);
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.right_ascension = ra;
                m.status.declination = dec;
                m.status.parked = false;
                Ok(())
            }
        }
    }

    pub async fn mount_sync(&self, device_id: &str, ra: f64, dec: f64) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.sync_to_coordinates(ra, dec).await.map_err(|e| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "Failed to sync ASCOM mount {} to RA={:.4} Dec={:.4}: {}",
                                device_id, ra, dec, e
                            ))
                        });
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.sync_to_coordinates(ra, dec).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.sync_to_coordinates(ra, dec).await.map_err(|e| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "Failed to sync INDI mount {} to RA={:.4} Dec={:.4}: {}",
                                device_name, ra, dec, e
                            ))
                        });
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.sync_to_coordinates(ra, dec).await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to sync native mount {} to RA={:.4} Dec={:.4}: {}",
                            device_id, ra, dec, e
                        ))
                    });
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.right_ascension = ra;
                m.status.declination = dec;
                Ok(())
            }
        }
    }

    pub async fn mount_park(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.park().await.map_err(|e| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!("Failed to park ASCOM mount {}: {}", device_id, e))
                        });
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.park().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.park().await.map_err(|e| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!("Failed to park INDI mount {}: {}", device_name, e))
                        });
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount
                        .park()
                        .await
                        .map_err(|e| DeviceOpError::hardware(Some(device_id.to_string()), format!("Failed to park native mount {}: {}", device_id, e)));
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.parked = true;
                m.status.tracking = false;
                Ok(())
            }
        }
    }

    pub async fn mount_unpark(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.unpark().await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.unpark().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.unpark().await.map_err(DeviceOpError::driver);
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.unpark().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.parked = false;
                Ok(())
            }
        }
    }

    pub async fn mount_slew_alt_az(
        &self,
        device_id: &str,
        altitude: f64,
        azimuth: f64,
    ) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.write().await;
                        return with_timeout_str(
                            async {
                                mount
                                    .slew_to_alt_az(altitude, azimuth)
                                    .await
                                    .map_err(|e| e.to_string())
                            },
                            Timeouts::long_slew(),
                            device_id,
                            "slew_to_alt_az",
                        )
                        .await
                        .map_err(|e| {
                            tracing::error!("mount_slew_alt_az ASCOM error: {}", e);
                            DeviceOpError::driver(e)
                        });
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return with_timeout_str(
                        mount.slew_to_alt_az_async(altitude, azimuth),
                        Timeouts::long_slew(),
                        device_id,
                        "slew_to_alt_az",
                    )
                    .await
                    .map_err(|e| {
                        tracing::error!("mount_slew_alt_az Alpaca error: {}", e);
                        DeviceOpError::driver(e)
                    });
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
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
                        return with_timeout_str(
                            async {
                                mount
                                    .slew_to_alt_az(altitude, azimuth)
                                    .await
                                    .map_err(|e| e.to_string())
                            },
                            Timeouts::long_slew(),
                            device_id,
                            "slew_to_alt_az",
                        )
                        .await
                        .map_err(|e| {
                            tracing::error!("mount_slew_alt_az INDI error: {}", e);
                            DeviceOpError::driver(e)
                        });
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Native => {
                // Native mounts (SkyWatcher, iOptron, etc.) are equatorial; alt/az slew is not
                // natively supported. Return an error rather than silently failing.
                Err(DeviceOpError::unsupported("Alt/Az slew is not supported for native serial mounts"))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.altitude = Some(altitude);
                m.status.azimuth = Some(azimuth);
                m.status.parked = false;
                Ok(())
            }
        }
    }

    pub async fn mount_find_home(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.write().await;
                        return mount.find_home().await.map_err(|e| {
                            tracing::error!("mount_find_home ASCOM error: {}", e);
                            DeviceOpError::driver(e)
                        });
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.find_home().await.map_err(|e| {
                        tracing::error!("mount_find_home Alpaca error: {}", e);
                        DeviceOpError::driver(e)
                    });
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
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
                            DeviceOpError::driver(e)
                        });
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Native => {
                // Native serial mounts don't have a standardized find-home command
                Err(DeviceOpError::unsupported("Find home is not supported for native serial mounts"))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.at_home = Some(true);
                m.status.parked = false;
                Ok(())
            }
        }
    }

    pub async fn mount_get_coordinates(&self, device_id: &str) -> Result<(f64, f64), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.get_coordinates().await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    return mount.get_coordinates().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    let ra = mount.right_ascension().await.map_err(DeviceOpError::driver)?;
                    let dec = mount.declination().await.map_err(DeviceOpError::driver)?;
                    return Ok((ra, dec));
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.get_coordinates().await.map_err(DeviceOpError::driver);
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Simulator => {
                let sim = crate::device_manager::ops::sim_gate::read_mount_status().await?;
                Ok((sim.right_ascension, sim.declination))
            }
        }
    }

    pub async fn mount_abort(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.abort_slew().await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.abort_slew().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.abort_slew().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.abort_slew().await.map_err(DeviceOpError::driver);
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.slewing = false;
                Ok(())
            }
        }
    }

    pub async fn mount_stop(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.stop().await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.abort_slew().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.abort_slew().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.abort_slew().await.map_err(DeviceOpError::driver);
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.slewing = false;
                m.status.tracking = false;
                Ok(())
            }
        }
    }

    pub async fn mount_set_tracking(&self, device_id: &str, enabled: bool) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.set_tracking(enabled).await.map_err(|e| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "Failed to set ASCOM mount {} tracking={}: {}",
                                device_id, enabled, e
                            ))
                        });
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.set_tracking(enabled).await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to set native mount {} tracking={}: {}",
                            device_id, enabled, e
                        ))
                    });
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.set_tracking(enabled).await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to set Alpaca mount {} tracking={}: {}",
                            device_id, enabled, e
                        ))
                    });
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.set_tracking(enabled).await.map_err(|e| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "Failed to set INDI mount {} tracking={}: {}",
                                device_name, enabled, e
                            ))
                        });
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                m.status.tracking = enabled;
                Ok(())
            }
        }
    }

    pub async fn mount_pulse_guide(
        &self,
        device_id: &str,
        direction: String,
        duration_ms: u32,
    ) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        let direction_lower = direction.to_lowercase();
        let dir = match direction_lower.as_str() {
            "north" | "n" => nightshade_native::traits::GuideDirection::North,
            "south" | "s" => nightshade_native::traits::GuideDirection::South,
            "east" | "e" => nightshade_native::traits::GuideDirection::East,
            "west" | "w" => nightshade_native::traits::GuideDirection::West,
            _ => return Err(DeviceOpError::invalid_parameter(format!("Invalid direction: {}", direction))),
        };

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount
                            .pulse_guide(dir, duration_ms)
                            .await
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount
                        .pulse_guide(dir, duration_ms)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
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
                        DeviceOpError::invalid_parameter(format!(
                            "Alpaca pulse_guide duration {}ms exceeds i32::MAX",
                            duration_ms
                        ))
                    })?;
                    return mount
                        .pulse_guide(alpaca_dir, duration_i32)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        let direction = match dir {
                            nightshade_native::traits::GuideDirection::North => {
                                nightshade_indi::IndiMountGuideDirection::North
                            }
                            nightshade_native::traits::GuideDirection::South => {
                                nightshade_indi::IndiMountGuideDirection::South
                            }
                            nightshade_native::traits::GuideDirection::East => {
                                nightshade_indi::IndiMountGuideDirection::East
                            }
                            nightshade_native::traits::GuideDirection::West => {
                                nightshade_indi::IndiMountGuideDirection::West
                            }
                        };
                        return mount
                            .pulse_guide(direction, duration_ms)
                            .await
                            .map_err(DeviceOpError::driver);
                    }
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Simulator => {
                // Pulse guide on the simulator is a timing-only op; the
                // singleton has no field that records the last pulse. Just
                // gate on connection and return Ok so guide-loops driving a
                // sim mount don't spuriously fail.
                crate::device_manager::ops::sim_gate::require_mount_connected()
                    .await
                    .map_err(DeviceOpError::driver)
            }
        }
    }

    pub async fn mount_can_park(&self, device_id: &str) -> Result<bool, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.can_park().await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    return match mount.is_parked().await {
                        Ok(_) => Ok(true),
                        Err(nightshade_native::traits::NativeError::NotSupported) => Ok(false),
                        Err(e) => Err(DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to determine native mount park capability for {}: {}",
                            device_id, e
                        ))),
                    };
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native mount {} not connected", device_id)))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.can_park().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
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
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Simulator => {
                let sim = crate::device_manager::ops::sim_gate::read_mount_status().await?;
                Ok(sim.can_park)
            }
        }
    }

    pub async fn mount_get_status(&self, device_id: &str) -> Result<MountStatus, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;

                        // Required fields propagate read failures — these are not optional.
                        let (ra, dec) = mount.get_coordinates().await.map_err(DeviceOpError::driver)?;
                        let tracking = mount.get_tracking().await.map_err(DeviceOpError::driver)?;
                        let slewing = mount.is_slewing().await.map_err(DeviceOpError::driver)?;
                        let parked = mount.is_parked().await.map_err(DeviceOpError::driver)?;

                        let mut availability = Self::mount_status_availability_map();

                        // Optional fields: the ASCOM wrapper currently does not surface a
                        // distinct "not supported" error so any failure is recorded as Error.
                        let (alt_opt, az_opt) = match mount.get_alt_az().await {
                            Ok((a, z)) => (Some(a), Some(z)),
                            Err(e) => {
                                let msg = e.to_string();
                                Self::set_mount_availability(
                                    &mut availability,
                                    mount_status_field::ALTITUDE,
                                    FieldAvailability::Error(msg.clone()),
                                );
                                Self::set_mount_availability(
                                    &mut availability,
                                    mount_status_field::AZIMUTH,
                                    FieldAvailability::Error(msg),
                                );
                                (None, None)
                            }
                        };
                        if alt_opt.is_some() {
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::ALTITUDE,
                                FieldAvailability::Available,
                            );
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::AZIMUTH,
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
                        Self::set_mount_availability(
                            &mut availability,
                            mount_status_field::AT_HOME,
                            FieldAvailability::Unsupported,
                        );

                        let capabilities = match mount.get_capabilities().await {
                            Ok(caps) => caps,
                            Err(err) => {
                                warn!(
                                    "Failed to query ASCOM mount capabilities for {}: {}. Marking capabilities unavailable.",
                                    device_id, err
                                );
                                crate::ascom_wrapper::mount::AscomMountCapabilities::default()
                            }
                        };

                        let (tracking_rate_opt, can_set_tracking_rate) =
                            match mount.get_tracking_rate().await {
                                Ok(rate) => {
                                    Self::set_mount_availability(
                                        &mut availability,
                                        mount_status_field::TRACKING_RATE,
                                        FieldAvailability::Available,
                                    );
                                    (Some(Self::tracking_rate_from_native(rate)), true)
                                }
                                Err(nightshade_native::traits::NativeError::NotSupported) => {
                                    Self::set_mount_availability(
                                        &mut availability,
                                        mount_status_field::TRACKING_RATE,
                                        FieldAvailability::Unsupported,
                                    );
                                    (None, false)
                                }
                                Err(err) => {
                                    Self::set_mount_availability(
                                        &mut availability,
                                        mount_status_field::TRACKING_RATE,
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
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    // Required fields propagate read failures — these are not optional.
                    let (ra, dec) = mount.get_coordinates().await.map_err(DeviceOpError::driver)?;
                    let tracking = mount.get_tracking().await.map_err(DeviceOpError::driver)?;
                    let slewing = mount.is_slewing().await.map_err(DeviceOpError::driver)?;
                    let (parked, can_park) = match mount.is_parked().await {
                        Ok(p) => (p, true),
                        Err(nightshade_native::traits::NativeError::NotSupported) => (false, false),
                        Err(e) => {
                            return Err(DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "Failed to read native mount parked state for {}: {}",
                                device_id, e
                            )));
                        }
                    };

                    let mut availability = Self::mount_status_availability_map();

                    // get_side_of_pier on `NativeMount` returns Unknown rather than Err
                    // for unsupported mounts (e.g. SkyWatcher), so distinguish here:
                    // Unknown → Unsupported availability; East/West → Available.
                    let side_of_pier_opt = match mount.get_side_of_pier().await {
                        Ok(nightshade_native::traits::PierSide::Unknown) => {
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::SIDE_OF_PIER,
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Ok(other) => {
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::SIDE_OF_PIER,
                                FieldAvailability::Available,
                            );
                            Some(Self::pier_side_from_native(other))
                        }
                        Err(nightshade_native::traits::NativeError::NotSupported) => {
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::SIDE_OF_PIER,
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Err(e) => {
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::SIDE_OF_PIER,
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
                    Self::set_mount_availability(
                        &mut availability,
                        mount_status_field::AZIMUTH,
                        alt_avail,
                    );
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
                    Self::set_mount_availability(
                        &mut availability,
                        mount_status_field::AT_HOME,
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
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    // Required fields propagate read failures.
                    let ra = mount.right_ascension().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!("Failed to read Alpaca mount RA for {}: {}", device_id, e))
                    })?;
                    let dec = mount.declination().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!("Failed to read Alpaca mount Dec for {}: {}", device_id, e))
                    })?;
                    let tracking = mount.tracking().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to read Alpaca mount tracking for {}: {}",
                            device_id, e
                        ))
                    })?;
                    let slewing = mount.slewing().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to read Alpaca mount slewing for {}: {}",
                            device_id, e
                        ))
                    })?;
                    let parked = mount.at_park().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to read Alpaca mount at_park for {}: {}",
                            device_id, e
                        ))
                    })?;

                    let mut availability = Self::mount_status_availability_map();

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
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::SIDE_OF_PIER,
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Ok(other) => {
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::SIDE_OF_PIER,
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
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::SIDE_OF_PIER,
                                FieldAvailability::Error(e),
                            );
                            None
                        }
                    };

                    let (can_park, can_slew, can_sync, can_pulse_guide) = match mount
                        .get_capabilities()
                        .await
                    {
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
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::TRACKING_RATE,
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
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::TRACKING_RATE,
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
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Alpaca mount not connected"))
            }
            DriverType::Indi => {
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                    let (ra, dec) = mount.get_coordinates().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to read INDI mount coordinates for {}: {}",
                            device_id, e
                        ))
                    })?;
                    let tracking = mount.try_is_tracking().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to read INDI mount tracking for {}: {}",
                            device_id, e
                        ))
                    })?;
                    let slewing = mount.try_is_slewing().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!("Failed to read INDI mount slewing for {}: {}", device_id, e))
                    })?;
                    let parked = mount.try_is_parked().await.map_err(|e| {
                        DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "Failed to read INDI mount parked state for {}: {}",
                            device_id, e
                        ))
                    })?;

                    let mut availability = Self::mount_status_availability_map();

                    let (alt_opt, az_opt) = match mount.get_horizontal_coordinates().await {
                        Ok((a, z)) => {
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::ALTITUDE,
                                FieldAvailability::Available,
                            );
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::AZIMUTH,
                                FieldAvailability::Available,
                            );
                            (Some(a), Some(z))
                        }
                        Err(e) => {
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::ALTITUDE,
                                FieldAvailability::Error(e.clone()),
                            );
                            Self::set_mount_availability(
                                &mut availability,
                                mount_status_field::AZIMUTH,
                                FieldAvailability::Error(e),
                            );
                            (None, None)
                        }
                    };
                    let side_of_pier_opt = mount
                        .get_pier_side()
                        .await
                        .map(|side| Self::pier_side_from_indi_element(&side));

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
                            .get_number(&device_name, "TELESCOPE_TIMED_GUIDE_NS", "TIMED_GUIDE_N")
                            .await
                            .is_some()
                            || locked
                                .get_number(
                                    &device_name,
                                    "TELESCOPE_TIMED_GUIDE_WE",
                                    "TIMED_GUIDE_E",
                                )
                                .await
                                .is_some();
                        (can_park, can_slew, can_sync, can_pulse_guide)
                    };
                    let (tracking_rate_native, can_set_tracking_rate) =
                        Self::indi_mount_tracking_rate(&locked, &device_name).await;
                    let tracking_rate_opt = if can_set_tracking_rate {
                        Self::set_mount_availability(
                            &mut availability,
                            mount_status_field::TRACKING_RATE,
                            FieldAvailability::Available,
                        );
                        Some(tracking_rate_native)
                    } else {
                        // INDI helper currently signals "no tracking-rate property" by
                        // returning false for the second tuple element; treat that as
                        // Unsupported rather than asserting Sidereal.
                        Self::set_mount_availability(
                            &mut availability,
                            mount_status_field::TRACKING_RATE,
                            FieldAvailability::Unsupported,
                        );
                        None
                    };

                    // INDI does not standardise an at-home property, and TIME_LST is
                    // optional — record both as Unsupported until per-driver support
                    // can be added.
                    Self::set_mount_availability(
                        &mut availability,
                        mount_status_field::AT_HOME,
                        FieldAvailability::Unsupported,
                    );
                    Self::set_mount_availability(
                        &mut availability,
                        mount_status_field::SIDEREAL_TIME,
                        FieldAvailability::Unsupported,
                    );
                    Self::set_mount_availability(
                        &mut availability,
                        mount_status_field::SIDE_OF_PIER,
                        if side_of_pier_opt.is_some() {
                            FieldAvailability::Available
                        } else {
                            FieldAvailability::Unsupported
                        },
                    );

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
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)))
            }
            DriverType::Simulator => {
                crate::device_manager::ops::sim_gate::read_mount_status()
                    .await
                    .map_err(DeviceOpError::driver)
            }
        }
    }

    fn mount_status_availability_map() -> HashMap<String, FieldAvailability> {
        HashMap::with_capacity(6)
    }

    fn set_mount_availability(
        availability: &mut HashMap<String, FieldAvailability>,
        field: &'static str,
        value: FieldAvailability,
    ) {
        availability.insert(field.to_owned(), value);
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
                Self::set_mount_availability(availability, field, FieldAvailability::Available);
                Some(v)
            }
            Err(nightshade_native::traits::NativeError::NotSupported) => {
                Self::set_mount_availability(availability, field, FieldAvailability::Unsupported);
                None
            }
            Err(e) => {
                Self::set_mount_availability(
                    availability,
                    field,
                    FieldAvailability::Error(e.to_string()),
                );
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
                Self::set_mount_availability(availability, field, FieldAvailability::Available);
                Some(v)
            }
            Err(e) => {
                Self::set_mount_availability(availability, field, FieldAvailability::Error(e));
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

    fn pier_side_from_indi_element(element: &str) -> crate::device::PierSide {
        let upper = element.to_ascii_uppercase();
        if upper.contains("EAST") || upper.ends_with("_E") || upper == "PIER_E" {
            crate::device::PierSide::East
        } else if upper.contains("WEST") || upper.ends_with("_W") || upper == "PIER_W" {
            crate::device::PierSide::West
        } else {
            crate::device::PierSide::Unknown
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

    pub async fn mount_set_tracking_rate(&self, device_id: &str, rate: i32) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

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
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
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
                        _ => return Err(DeviceOpError::invalid_parameter(format!("Invalid tracking rate: {}", rate))),
                    };
                    return mount
                        .set_tracking_rate(tracking_rate)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            _ => Err(DeviceOpError::unsupported("Setting tracking rate is not supported by this driver type")),
        }
    }

    pub async fn mount_get_tracking_rate(&self, device_id: &str) -> Result<i32, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

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
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    let rate = mount.get_tracking_rate().await.map_err(DeviceOpError::driver)?;
                    // Why (audit-rust §1.4): `TrackingRate` is a C-like enum
                    // (Sidereal=0, Lunar=1, Solar=2, King=3); `as i32`
                    // extracts the discriminant — SAFE narrowing.
                    return Ok(rate as i32);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "Native mount not connected"))
            }
            DriverType::Simulator => {
                let sim = crate::device_manager::ops::sim_gate::read_mount_status().await?;
                // Project the singleton's `tracking_rate` Option onto the
                // i32 wire form. None → 0 (Sidereal) is the project-wide
                // default for "rate not declared".
                Ok(match sim.tracking_rate {
                    Some(TrackingRate::Sidereal) => 0,
                    Some(TrackingRate::Lunar) => 1,
                    Some(TrackingRate::Solar) => 2,
                    Some(TrackingRate::King) => 3,
                    Some(TrackingRate::Custom) => 4,
                    None => 0,
                })
            }
            _ => Err(DeviceOpError::unsupported("Getting tracking rate is not supported by this driver type")),
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
    ) -> Result<(), DeviceOpError> {
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
                DeviceOpError::device_not_found(device_id)
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
                    tracing::debug!(
                        "mount_move_axis: ascom_mounts contains {} entries",
                        mounts.len()
                    );
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.move_axis(axis, rate).await.map_err(|e| {
                            tracing::error!("mount_move_axis ASCOM error: {}", e);
                            DeviceOpError::driver(e)
                        });
                    } else {
                        tracing::error!(
                            "mount_move_axis: Mount {} not found in ascom_mounts. Available: {:?}",
                            device_id,
                            mounts.keys().collect::<Vec<_>>()
                        );
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "ASCOM mount not connected"))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    tracing::debug!("mount_move_axis: Calling Alpaca move_axis");
                    return mount.move_axis(axis, rate).await.map_err(|e| {
                        tracing::error!("mount_move_axis Alpaca error: {}", e);
                        DeviceOpError::driver(e)
                    });
                }
                tracing::error!("mount_move_axis: Alpaca mount {} not connected", device_id);
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca mount {} not connected", device_id)))
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
                                    tracing::error!(
                                        "mount_move_axis INDI error (move east): {}",
                                        e
                                    );
                                    DeviceOpError::driver(e)
                                });
                            } else if rate < 0.0 {
                                return mount.move_west(true).await.map_err(|e| {
                                    tracing::error!(
                                        "mount_move_axis INDI error (move west): {}",
                                        e
                                    );
                                    DeviceOpError::driver(e)
                                });
                            } else {
                                // Stop both directions
                                let _ = mount.move_east(false).await;
                                return mount.move_west(false).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (stop RA): {}", e);
                                    DeviceOpError::driver(e)
                                });
                            }
                        } else {
                            // Dec/Altitude axis
                            if rate > 0.0 {
                                return mount.move_north(true).await.map_err(|e| {
                                    tracing::error!(
                                        "mount_move_axis INDI error (move north): {}",
                                        e
                                    );
                                    DeviceOpError::driver(e)
                                });
                            } else if rate < 0.0 {
                                return mount.move_south(true).await.map_err(|e| {
                                    tracing::error!(
                                        "mount_move_axis INDI error (move south): {}",
                                        e
                                    );
                                    DeviceOpError::driver(e)
                                });
                            } else {
                                // Stop both directions
                                let _ = mount.move_north(false).await;
                                return mount.move_south(false).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (stop Dec): {}", e);
                                    DeviceOpError::driver(e)
                                });
                            }
                        }
                    }
                    tracing::error!(
                        "mount_move_axis: INDI client not connected for {}",
                        server_key
                    );
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("INDI client not connected for {}", server_key)));
                }
                Err(DeviceOpError::invalid_device_id(format!("Invalid INDI device ID format: {}", device_id)))
            }
            DriverType::Native => {
                tracing::warn!("mount_move_axis: Native SDK does not support mount axis movement");
                Err(DeviceOpError::unsupported("Native SDK does not support mount axis movement"))
            }
            DriverType::Simulator => {
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                if !m.status.connected {
                    return Err(DeviceOpError::not_connected(None, crate::device_manager::ops::sim_gate::not_connected_mount()));
                }
                // The simulator has no axis-rate state model — just gate on
                // connection and record `slewing` so subsequent
                // `mount_get_status` reflects the move command. A real driver
                // wouldn't no-op silently.
                m.status.slewing = rate != 0.0;
                Ok(())
            }
        }
    }
}
