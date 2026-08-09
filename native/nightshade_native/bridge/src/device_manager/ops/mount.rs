//! Mount operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.
//!
//! # `unwrap_or` policy
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
#[cfg(windows)]
use nightshade_native::traits::NativeMount;
use std::collections::HashMap;
use tracing::warn;

impl DeviceManager {
    // =========================================================================
    // Mount Control
    // =========================================================================

    pub async fn mount_slew(
        &self,
        device_id: &str,
        ra: f64,
        dec: f64,
    ) -> Result<(), DeviceOpError> {
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

        // Catalog/solver coordinates are J2000; real mounts (ASCOM default
        // equTopocentric, INDI EQUATORIAL_EOD_COORD, native LX200-protocol)
        // expect of-date coordinates — ~22′ apart in 2026. Convert at this
        // single choke point so every caller (sequencer, planetarium GOTO,
        // centering) lands on target. The Simulator stores whatever it is
        // sent and is read back by epoch-agnostic tests, so it stays raw.
        // See `device_manager::epoch` for the direction policy.
        let (ra, dec) = match info.driver_type {
            DriverType::Simulator => (ra, dec),
            _ => {
                let (ra_now, dec_now) = crate::device_manager::epoch::j2000_to_jnow(ra, dec);
                tracing::debug!(
                    "mount_slew: J2000 ({:.5}h, {:.4}°) -> JNOW ({:.5}h, {:.4}°)",
                    ra,
                    dec,
                    ra_now,
                    dec_now
                );
                (ra_now, dec_now)
            }
        };

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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Simulator => {
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                crate::device_manager::ops::sim_gate::refuse_while_mount_slewing("slew").await?;
                // Travels to the target over time rather than teleporting, and
                // records the pier side the mount lands on. See
                // `simulation::begin_sim_slew`.
                crate::api::devices::simulation::begin_sim_slew(ra, dec, chrono::Utc::now()).await;
                // Repointing starts a new target: the previous one's accumulated
                // drift does not carry over, and this is what stops a long
                // session leaving the field pinned at its offset clamp.
                crate::api::devices::simulation::reset_sim_guide_offset().await;
                Ok(())
            }
        }
    }

    pub async fn mount_sync(
        &self,
        device_id: &str,
        ra: f64,
        dec: f64,
    ) -> Result<(), DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        // Same J2000 -> of-date conversion as mount_slew, and it MUST match:
        // sync and slew feeding the mount from different frames would skew
        // the pointing model by the precession offset on every centering
        // iteration. See `device_manager::epoch`.
        let (ra, dec) = match info.driver_type {
            DriverType::Simulator => (ra, dec),
            _ => crate::device_manager::epoch::j2000_to_jnow(ra, dec),
        };

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.sync_to_coordinates(ra, dec).await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to sync ASCOM mount {} to RA={:.4} Dec={:.4}: {}",
                                    device_id, ra, dec, e
                                ),
                            )
                        });
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount
                        .sync_to_coordinates(ra, dec)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to sync INDI mount {} to RA={:.4} Dec={:.4}: {}",
                                    device_name, ra, dec, e
                                ),
                            )
                        });
                    }
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.sync_to_coordinates(ra, dec).await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to sync native mount {} to RA={:.4} Dec={:.4}: {}",
                                device_id, ra, dec, e
                            ),
                        )
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Simulator => {
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                crate::device_manager::ops::sim_gate::refuse_while_mount_slewing("sync").await?;
                // A sync redefines where the mount believes it is pointing
                // without moving it, so any in-flight slew has to be dropped
                // first — otherwise the interpolation would overwrite the
                // synced coordinates on the next status read.
                crate::api::devices::simulation::cancel_sim_slew().await;
                let m = crate::api::devices::simulation::get_sim_mount();
                let mut m = m.write().await;
                m.status.right_ascension = ra;
                m.status.declination = dec;
                m.status.slewing = false;
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
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!("Failed to park ASCOM mount {}: {}", device_id, e),
                            )
                        });
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.park().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!("Failed to park INDI mount {}: {}", device_name, e),
                            )
                        });
                    }
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.park().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!("Failed to park native mount {}: {}", device_id, e),
                        )
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Simulator => {
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                crate::device_manager::ops::sim_gate::refuse_while_mount_slewing("park").await?;
                // Drop the in-flight slew BEFORE writing the park position: a
                // status read landing in between would otherwise advance the
                // abandoned slew straight back over it.
                crate::api::devices::simulation::cancel_sim_slew().await;
                let (ra, dec) = crate::api::devices::simulation::sim_park_position();
                let mut m = crate::api::devices::simulation::get_sim_mount()
                    .write()
                    .await;
                m.status.right_ascension = ra;
                m.status.declination = dec;
                m.status.parked = true;
                m.status.tracking = false;
                m.status.slewing = false;
                drop(m);
                crate::api::devices::simulation::reset_sim_guide_offset().await;
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
                        mount.unpark().await.map_err(DeviceOpError::driver)?;
                        let deadline =
                            tokio::time::Instant::now() + std::time::Duration::from_secs(15);
                        loop {
                            match mount.is_parked().await {
                                Ok(false) => return Ok(()),
                                Ok(true) => {}
                                Err(error) => {
                                    return Err(DeviceOpError::hardware(
                                        Some(device_id.to_string()),
                                        format!(
                                            "ASCOM mount {} accepted Unpark but its parked-state readback failed: {}",
                                            device_id, error
                                        ),
                                    ));
                                }
                            }
                            if tokio::time::Instant::now() >= deadline {
                                return Err(DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    format!(
                                        "ASCOM mount {} did not report unparked within 15s",
                                        device_id
                                    ),
                                ));
                            }
                            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                        }
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.unpark().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.unpark().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Simulator => {
                // Goes through the shared gate rather than an inline
                // `connected` read: the gate is also what runs the fault
                // injector and advances the in-flight slew, so unpark now sees
                // — and can be made to fail on — the same mount state every
                // other mutating op does.
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                let m = crate::api::devices::simulation::get_sim_mount();
                m.write().await.status.parked = false;
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Native => {
                // Native mounts (SkyWatcher, iOptron, etc.) are equatorial; alt/az slew is not
                // natively supported. Return an error rather than silently failing.
                Err(DeviceOpError::unsupported(
                    "Alt/Az slew is not supported for native serial mounts",
                ))
            }
            DriverType::Simulator => {
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                crate::device_manager::ops::sim_gate::refuse_while_mount_slewing("alt/az slew")
                    .await?;
                // Store the equatorial pointing the alt/az slew produced, not the
                // alt/az pair itself: RA/Dec is the simulator's single source of
                // truth and the horizon-frame fields are derived from it on every
                // read (see `sim_gate::read_mount_status`). Writing alt/az here
                // instead left them frozen at the commanded value while the sky
                // moved on underneath.
                let site = crate::api::get_state()
                    .get_observer_location()
                    .ok()
                    .flatten();
                let Some(site) = site else {
                    return Err(DeviceOpError::unsupported(
                        "Alt/Az slew needs an observer location; set the site first",
                    ));
                };
                let now = chrono::Utc::now();
                let (ra, dec) = nightshade_sequencer::meridian::alt_az_to_ra_dec(
                    altitude,
                    azimuth,
                    site.latitude,
                    site.longitude,
                    now,
                );
                crate::api::devices::simulation::begin_sim_slew(ra, dec, now).await;
                crate::api::devices::simulation::reset_sim_guide_offset().await;
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.find_home().await.map_err(|e| {
                        tracing::error!("mount_find_home Alpaca error: {}", e);
                        DeviceOpError::driver(e)
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Native => {
                // Native serial mounts don't have a standardized find-home command
                Err(DeviceOpError::unsupported(
                    "Find home is not supported for native serial mounts",
                ))
            }
            DriverType::Simulator => {
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                crate::api::devices::simulation::cancel_sim_slew().await;
                // Home is the same mechanical rest position park uses; the
                // difference is that a homed mount is not parked. Leaving the
                // pointing at the previous target would report the altitude of
                // whatever it had been imaging.
                let (ra, dec) = crate::api::devices::simulation::sim_park_position();
                let mut m = crate::api::devices::simulation::get_sim_mount()
                    .write()
                    .await;
                m.status.right_ascension = ra;
                m.status.declination = dec;
                m.status.at_home = Some(true);
                m.status.parked = false;
                m.status.slewing = false;
                drop(m);
                crate::api::devices::simulation::reset_sim_guide_offset().await;
                Ok(())
            }
        }
    }

    pub async fn mount_get_coordinates(
        &self,
        device_id: &str,
    ) -> Result<(f64, f64), DeviceOpError> {
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    return mount.get_coordinates().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    let ra = mount
                        .right_ascension()
                        .await
                        .map_err(DeviceOpError::driver)?;
                    let dec = mount.declination().await.map_err(DeviceOpError::driver)?;
                    return Ok((ra, dec));
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.abort_slew().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.abort_slew().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Simulator => {
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                // Drop the in-flight slew first, or the interpolation would
                // carry the mount on to the target it was just told to stop
                // travelling to.
                crate::api::devices::simulation::cancel_sim_slew().await;
                crate::api::devices::simulation::get_sim_mount()
                    .write()
                    .await
                    .status
                    .slewing = false;
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.abort_slew().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.abort_slew().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Simulator => {
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                crate::api::devices::simulation::cancel_sim_slew().await;
                let mut m = crate::api::devices::simulation::get_sim_mount()
                    .write()
                    .await;
                m.status.slewing = false;
                m.status.tracking = false;
                Ok(())
            }
        }
    }

    pub async fn mount_set_tracking(
        &self,
        device_id: &str,
        enabled: bool,
    ) -> Result<(), DeviceOpError> {
        let result = self.mount_set_tracking_dispatch(device_id, enabled).await;

        // Record the commanded tracking state so an unplanned reconnect (USB /
        // serial yank mid-run) can re-apply it. A mount that comes back from a
        // reconnect is parked / not tracking; without this the sequence would
        // "resume" while the mount sits still. Only record on success so a
        // failed command does not clobber the last known good desired state.
        if result.is_ok() {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                dev.desired_tracking = Some(enabled);
            }
        }

        result
    }

    /// Driver dispatch for `mount_set_tracking`. Split out so the public method
    /// can record the desired tracking state (for reconnect re-application)
    /// without holding the `devices` read lock across the per-driver calls.
    async fn mount_set_tracking_dispatch(
        &self,
        device_id: &str,
        enabled: bool,
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
                        let mut mount = mount.write().await;
                        return mount.set_tracking(enabled).await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to set ASCOM mount {} tracking={}: {}",
                                    device_id, enabled, e
                                ),
                            )
                        });
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.set_tracking(enabled).await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to set native mount {} tracking={}: {}",
                                device_id, enabled, e
                            ),
                        )
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.set_tracking(enabled).await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to set Alpaca mount {} tracking={}: {}",
                                device_id, enabled, e
                            ),
                        )
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to set INDI mount {} tracking={}: {}",
                                    device_name, enabled, e
                                ),
                            )
                        });
                    }
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Simulator => {
                // See `mount_unpark`: the shared gate, not an inline
                // `connected` read, is what advances the motion and runs the
                // fault injector.
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                let m = crate::api::devices::simulation::get_sim_mount();
                m.write().await.status.tracking = enabled;
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
            _ => {
                return Err(DeviceOpError::invalid_parameter(format!(
                    "Invalid direction: {}",
                    direction
                )))
            }
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount
                        .pulse_guide(dir, duration_ms)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
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
                    // Why: Alpaca PulseGuide takes i32 ms;
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Simulator => {
                // Move the simulated star field. This used to gate on connection
                // and return Ok without recording anything, which meant the
                // built-in guider's own pulses never shifted the field it was
                // measuring: calibration always aborted with "Calibration
                // response on east axis was too small (0.000px)", so guiding,
                // dithering and the correction loop could not be exercised
                // without a mount.
                crate::device_manager::ops::sim_gate::require_mount_connected()
                    .await
                    .map_err(DeviceOpError::driver)?;
                crate::api::devices::simulation::advance_sim_guide_pulse(
                    &direction_lower,
                    duration_ms,
                )
                .await;
                Ok(())
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    return match mount.is_parked().await {
                        Ok(_) => Ok(true),
                        Err(nightshade_native::traits::NativeError::NotSupported) => Ok(false),
                        Err(e) => Err(DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to determine native mount park capability for {}: {}",
                                device_id, e
                            ),
                        )),
                    };
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native mount {} not connected", device_id),
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.can_park().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
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
                        let (ra, dec) = mount
                            .get_coordinates()
                            .await
                            .map_err(DeviceOpError::driver)?;
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    // Required fields propagate read failures — these are not optional.
                    let (ra, dec) = mount
                        .get_coordinates()
                        .await
                        .map_err(DeviceOpError::driver)?;
                    let tracking = mount.get_tracking().await.map_err(DeviceOpError::driver)?;
                    let slewing = mount.is_slewing().await.map_err(DeviceOpError::driver)?;
                    let (parked, can_park) = match mount.is_parked().await {
                        Ok(p) => (p, true),
                        Err(nightshade_native::traits::NativeError::NotSupported) => (false, false),
                        Err(e) => {
                            return Err(DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to read native mount parked state for {}: {}",
                                    device_id, e
                                ),
                            ));
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    // Required fields propagate read failures.
                    let ra = mount.right_ascension().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!("Failed to read Alpaca mount RA for {}: {}", device_id, e),
                        )
                    })?;
                    let dec = mount.declination().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!("Failed to read Alpaca mount Dec for {}: {}", device_id, e),
                        )
                    })?;
                    let tracking = mount.tracking().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read Alpaca mount tracking for {}: {}",
                                device_id, e
                            ),
                        )
                    })?;
                    let slewing = mount.slewing().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read Alpaca mount slewing for {}: {}",
                                device_id, e
                            ),
                        )
                    })?;
                    let parked = mount.at_park().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read Alpaca mount at_park for {}: {}",
                                device_id, e
                            ),
                        )
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
                    // CanSetTracking governs the boolean Tracking property.
                    // Rate mutability is advertised by TelescopeRates.
                    let can_set_tracking_rate = mount
                        .tracking_rates()
                        .await
                        .map(|rates| !rates.is_empty())
                        .unwrap_or(false);

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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Alpaca mount not connected",
                ))
            }
            DriverType::Indi => {
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                    let (ra, dec) = mount.get_coordinates().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read INDI mount coordinates for {}: {}",
                                device_id, e
                            ),
                        )
                    })?;
                    let tracking = mount.try_is_tracking().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read INDI mount tracking for {}: {}",
                                device_id, e
                            ),
                        )
                    })?;
                    let slewing = mount.try_is_slewing().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!("Failed to read INDI mount slewing for {}: {}", device_id, e),
                        )
                    })?;
                    let parked = mount.try_is_parked().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read INDI mount parked state for {}: {}",
                                device_id, e
                            ),
                        )
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI client not connected for {}", server_key),
                ))
            }
            DriverType::Simulator => crate::device_manager::ops::sim_gate::read_mount_status()
                .await
                .map_err(DeviceOpError::driver),
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

    pub async fn mount_set_tracking_rate(
        &self,
        device_id: &str,
        rate: i32,
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
                        let mut mount = mount.write().await;
                        return mount
                            .set_tracking_rate_raw(rate)
                            .await
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
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
                        _ => {
                            return Err(DeviceOpError::invalid_parameter(format!(
                                "Invalid tracking rate: {}",
                                rate
                            )))
                        }
                    };
                    return mount
                        .set_tracking_rate(tracking_rate)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
            }
            DriverType::Simulator => {
                // See `mount_unpark`: the shared gate, not an inline
                // `connected` read, is what advances the motion and runs the
                // fault injector. It runs before the rate is parsed so a
                // disconnected mount reports being disconnected rather than
                // grading the caller's argument.
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                // The simulated mount advertises `can_set_tracking_rate: true`
                // and reports a rate, so it has to accept one — falling through
                // to the unsupported arm made its own capability report a lie.
                let rate = match rate {
                    0 => TrackingRate::Sidereal,
                    1 => TrackingRate::Lunar,
                    2 => TrackingRate::Solar,
                    3 => TrackingRate::King,
                    4 => TrackingRate::Custom,
                    _ => {
                        return Err(DeviceOpError::invalid_parameter(format!(
                            "Invalid tracking rate: {}",
                            rate
                        )))
                    }
                };
                let m = crate::api::devices::simulation::get_sim_mount();
                m.write().await.status.tracking_rate = Some(rate);
                Ok(())
            }
            _ => Err(DeviceOpError::unsupported(
                "Setting tracking rate is not supported by this driver type",
            )),
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    let rate = mount
                        .get_tracking_rate()
                        .await
                        .map_err(DeviceOpError::driver)?;
                    // Why: `TrackingRate` is a C-like enum
                    // (Sidereal=0, Lunar=1, Solar=2, King=3); `as i32`
                    // extracts the discriminant — SAFE narrowing.
                    return Ok(rate as i32);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "Native mount not connected",
                ))
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
            _ => Err(DeviceOpError::unsupported(
                "Getting tracking rate is not supported by this driver type",
            )),
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM mount not connected",
                ))
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca mount {} not connected", device_id),
                ))
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
                    return Err(DeviceOpError::not_connected(
                        Some(device_id.to_string()),
                        format!("INDI client not connected for {}", server_key),
                    ));
                }
                Err(DeviceOpError::invalid_device_id(format!(
                    "Invalid INDI device ID format: {}",
                    device_id
                )))
            }
            DriverType::Native => {
                tracing::warn!("mount_move_axis: Native SDK does not support mount axis movement");
                Err(DeviceOpError::unsupported(
                    "Native SDK does not support mount axis movement",
                ))
            }
            DriverType::Simulator => {
                // See `mount_unpark`: the shared gate, not an inline
                // `connected` read, is what advances the motion and runs the
                // fault injector.
                crate::device_manager::ops::sim_gate::require_mount_connected().await?;
                // NOT refused mid-slew: `rate == 0.0` is how the hand-controller
                // buttons STOP an axis, and a stop must never be rejected.
                // The simulator has no axis-rate state model — just record
                // `slewing` so subsequent `mount_get_status` reflects the move
                // command. A real driver wouldn't no-op silently.
                let m = crate::api::devices::simulation::get_sim_mount();
                m.write().await.status.slewing = rate != 0.0;
                Ok(())
            }
        }
    }
}

#[cfg(test)]
mod sim_mount_tests {
    use crate::api::devices::simulation::{get_sim_mount, sim_singleton_test_lock, SimulatedMount};
    use crate::api::{get_device_manager, get_state};
    use crate::device::{DeviceInfo, DeviceType, DriverType, PierSide};
    use crate::storage::ObserverLocation;

    const TEST_LATITUDE: f64 = 40.0;

    async fn attach_sim_mount(device_id: &str) {
        let info = DeviceInfo {
            id: device_id.to_string(),
            name: "Simulated Mount".to_string(),
            device_type: DeviceType::Mount,
            driver_type: DriverType::Simulator,
            description: "Simulated mount".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Simulated Mount".to_string(),
        };
        get_device_manager().register_device(info, false).await;
        // The interpolation cell lives outside `SimulatedMount`, so resetting
        // the struct alone would leave the previous test's slew in flight and
        // this one's first command would be refused as "still moving".
        crate::api::devices::simulation::cancel_sim_slew().await;
        let mut mount = get_sim_mount().write().await;
        *mount = SimulatedMount::default();
        mount.status.connected = true;
    }

    fn set_site(longitude: f64) {
        get_state()
            .set_observer_location(Some(ObserverLocation {
                latitude: TEST_LATITUDE,
                longitude,
                elevation: 100.0,
            }))
            .expect("test site should be settable");
    }

    /// Longitude that puts `ra_hours` at the requested hour angle right now, so
    /// a test can place a target either side of the meridian without waiting for
    /// the sky to turn.
    fn longitude_for_hour_angle(ra_hours: f64, hour_angle_hours: f64) -> f64 {
        let now = chrono::Utc::now();
        let jd = nightshade_sequencer::meridian::julian_day(&now);
        let lst_at_greenwich = nightshade_sequencer::meridian::local_sidereal_time(jd, 0.0);
        let wanted_lst = ra_hours + hour_angle_hours;
        (((wanted_lst - lst_at_greenwich) * 15.0 + 180.0).rem_euclid(360.0)) - 180.0
    }

    async fn wait_for_slew_to_finish(device_id: &str) {
        let mgr = get_device_manager();
        for _ in 0..200 {
            if !mgr.mount_get_status(device_id).await.unwrap().slewing {
                return;
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }
        panic!("simulated slew never finished");
    }

    /// The simulator set RA/Dec instantly and never raised `slewing`, so every
    /// wait-for-motion path in the app completed before the mount had
    /// "moved" — none of them could be exercised without hardware.
    #[tokio::test]
    async fn a_slew_reports_motion_and_converges_over_time() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_mount_slewing";
        attach_sim_mount(device_id).await;
        set_site(-75.0);
        let mgr = get_device_manager();

        mgr.mount_slew(device_id, 6.0, 45.0).await.unwrap();
        let moving = mgr.mount_get_status(device_id).await.unwrap();
        assert!(
            moving.slewing,
            "the mount reported it was not slewing the instant a 45-degree slew was commanded"
        );
        assert!(
            (moving.declination - 45.0).abs() > 1e-6,
            "the mount teleported to the target declination instead of travelling to it"
        );

        wait_for_slew_to_finish(device_id).await;
        let arrived = mgr.mount_get_status(device_id).await.unwrap();
        assert!((arrived.right_ascension - 6.0).abs() < 1e-6);
        assert!((arrived.declination - 45.0).abs() < 1e-6);
        assert!(!arrived.slewing);
    }

    /// Aborting has to stop the motion where it is, not let the interpolation
    /// carry on to the commanded target.
    #[tokio::test]
    async fn aborting_a_slew_stops_the_mount_short() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_mount_abort_slew";
        attach_sim_mount(device_id).await;
        set_site(-75.0);
        let mgr = get_device_manager();

        mgr.mount_slew(device_id, 12.0, 80.0).await.unwrap();
        mgr.mount_abort(device_id).await.unwrap();
        let stopped = mgr.mount_get_status(device_id).await.unwrap();
        assert!(!stopped.slewing);

        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        let later = mgr.mount_get_status(device_id).await.unwrap();
        assert!(!later.slewing, "an aborted slew resumed on its own");
        assert!(
            (later.declination - 80.0).abs() > 1e-6,
            "an aborted slew still arrived at its target"
        );
    }

    /// Pier side is mechanical state. Tracking across the meridian does NOT
    /// flip a German equatorial, so the reported side must not change just
    /// because the sky moved — it was derived from RA and the clock, which made
    /// it change without the mount moving and made a real flip undetectable.
    #[tokio::test]
    async fn pier_side_is_mechanical_state_not_a_function_of_pointing() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_mount_pier_side";
        attach_sim_mount(device_id).await;
        let mgr = get_device_manager();

        let target_ra = 5.5;
        set_site(longitude_for_hour_angle(target_ra, -1.0));
        mgr.mount_slew(device_id, target_ra, 30.0).await.unwrap();
        wait_for_slew_to_finish(device_id).await;
        let before = mgr
            .mount_get_status(device_id)
            .await
            .unwrap()
            .side_of_pier
            .unwrap();
        assert_ne!(before, PierSide::Unknown, "a slewed mount knows its side");

        // Two hours of sky rotation, expressed as longitude so the test does not
        // have to wait for it. The mount has not been commanded to move.
        set_site(longitude_for_hour_angle(target_ra, 1.0));
        let after_tracking = mgr
            .mount_get_status(device_id)
            .await
            .unwrap()
            .side_of_pier
            .unwrap();
        assert_eq!(
            after_tracking, before,
            "the mount changed pier side without being commanded to move"
        );

        // The flip: re-slew to the SAME coordinates, now past the meridian.
        mgr.mount_slew(device_id, target_ra, 30.0).await.unwrap();
        wait_for_slew_to_finish(device_id).await;
        let after_flip = mgr
            .mount_get_status(device_id)
            .await
            .unwrap()
            .side_of_pier
            .unwrap();
        assert_ne!(
            after_flip, before,
            "re-slewing past the meridian did not change the pier side, so \
             every simulated meridian flip fails its own verification"
        );
    }

    /// Park left RA/Dec at the previous target, so a parked mount reported the
    /// altitude of whatever it had been imaging — and that altitude kept moving
    /// with the sky.
    #[tokio::test]
    async fn parking_moves_the_mount_to_a_park_position() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_mount_park";
        attach_sim_mount(device_id).await;
        set_site(-75.0);
        let mgr = get_device_manager();

        mgr.mount_slew(device_id, 5.5, 30.0).await.unwrap();
        wait_for_slew_to_finish(device_id).await;
        mgr.mount_park(device_id).await.unwrap();

        let parked = mgr.mount_get_status(device_id).await.unwrap();
        assert!(parked.parked && !parked.tracking && !parked.slewing);
        assert!(
            (parked.right_ascension - 5.5).abs() > 1e-6 || (parked.declination - 30.0).abs() > 1e-6,
            "park left the mount pointing at the target it had been imaging \
             (RA {:.4}h Dec {:.4})",
            parked.right_ascension,
            parked.declination
        );
        let altitude = parked.altitude.expect("a parked mount reports an altitude");
        assert!(
            (altitude - TEST_LATITUDE).abs() < 1e-6,
            "a parked German equatorial points at the pole, so its altitude is \
             the site latitude; got {altitude}"
        );

        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        let later = mgr
            .mount_get_status(device_id)
            .await
            .unwrap()
            .altitude
            .unwrap();
        assert!(
            (later - altitude).abs() < 1e-9,
            "a parked mount's altitude drifted with the sky ({altitude} -> {later})"
        );
    }

    /// The simulator advertised `can_set_tracking_rate: true` and reported a
    /// rate, then rejected every attempt to set one.
    #[tokio::test]
    async fn an_advertised_tracking_rate_can_actually_be_set() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_mount_tracking_rate";
        attach_sim_mount(device_id).await;
        let mgr = get_device_manager();

        assert!(
            mgr.mount_get_status(device_id)
                .await
                .unwrap()
                .can_set_tracking_rate,
            "the simulator advertises the capability"
        );

        mgr.mount_set_tracking_rate(device_id, 1)
            .await
            .expect("a mount that advertises can_set_tracking_rate must accept one");
        assert_eq!(mgr.mount_get_tracking_rate(device_id).await.unwrap(), 1);
        assert_eq!(
            mgr.mount_get_status(device_id).await.unwrap().tracking_rate,
            Some(crate::device::TrackingRate::Lunar)
        );

        let err = mgr
            .mount_set_tracking_rate(device_id, 99)
            .await
            .expect_err("an out-of-range rate is a caller error");
        assert!(err.to_string().contains("Invalid tracking rate"));
    }
}
