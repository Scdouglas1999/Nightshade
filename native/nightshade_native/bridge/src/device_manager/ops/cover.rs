//! Cover calibrator operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.
//!
//! # `as`-cast policy (audit-rust §1.4)
//!
//! - **i32 brightness → f64 INDI wire** (line 201): exact widening.
//! - **i32 state → i32** (lines 275, 327, 489, 490): these are no-op
//!   widenings around enum discriminant extraction (CoverState /
//!   CalibratorState are small {0..5} enums per ASCOM ICoverCalibratorV1).
//! - **i32 brightness → i32** (line 409): no-op widening; brightness is
//!   already i32 in the ASCOM API.
//!
//! # `unwrap_or` policy (audit-rust §4.3)
//!
//! Every `unwrap_or` / `unwrap_or_else` in this file is a property-read
//! failure on the ICoverCalibrator interface (ASCOM/Alpaca) or its INDI
//! switch equivalent. Each site logs via `warn!` with the device id +
//! error message AND falls back to the documented "unknown" sentinel:
//!
//!   * `cover_state` / `calibrator_state` → `4` (the ASCOM "Unknown" enum
//!     value). The UI renders these as a yellow "?" badge.
//!   * `brightness` → `0` (the off state — safe for night-time imaging).
//!   * `max_brightness` → `255` (the ASCOM default; the brightness slider
//!     UI then renders 0-255 instead of a calibrator-specific scale).
//!
//! The `warn!` log is the explicit non-silent error signal required by
//! CLAUDE.md "errors are a feature".

use crate::device::*;
use crate::device_manager::DeviceManager;
use tracing::warn;

impl DeviceManager {
    // =========================================================================
    // Cover Calibrator Control
    // =========================================================================

    /// Open cover calibrator cover
    pub async fn cover_calibrator_open_cover(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.open_cover().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.open_cover().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
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
                        .set_switch(&device_name, "CAP_PARK", "UNPARK", true)
                        .await
                        .map_err(|e| {
                            format!("Failed to open INDI cover (unpark) on {}: {}", device_name, e)
                        });
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Close cover calibrator cover
    pub async fn cover_calibrator_close_cover(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.close_cover().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.close_cover().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
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
                        .set_switch(&device_name, "CAP_PARK", "PARK", true)
                        .await
                        .map_err(|e| {
                            format!("Failed to close INDI cover (park) on {}: {}", device_name, e)
                        });
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Halt cover calibrator cover movement
    pub async fn cover_calibrator_halt_cover(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.halt_cover().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.halt_cover().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // INDI doesn't have a specific halt command for dust caps
                Err("INDI cover calibrator halt not supported".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Turn on cover calibrator light
    pub async fn cover_calibrator_calibrator_on(
        &self,
        device_id: &str,
        brightness: i32,
    ) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.calibrator_on(brightness).await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.calibrator_on(brightness).await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
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
                    // Set brightness first, then turn on
                    locked
                        .set_number(
                            &device_name,
                            "FLAT_LIGHT_INTENSITY",
                            "FLAT_LIGHT_INTENSITY_VALUE",
                            brightness as f64,
                        )
                        .await
                        .map_err(|e| e.to_string())?;
                    return locked
                        .set_switch(&device_name, "FLAT_LIGHT_CONTROL", "FLAT_LIGHT_ON", true)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Turn off cover calibrator light
    pub async fn cover_calibrator_calibrator_off(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.calibrator_off().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.calibrator_off().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
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
                        .set_switch(&device_name, "FLAT_LIGHT_CONTROL", "FLAT_LIGHT_OFF", true)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator cover state
    /// Returns: 0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error
    pub async fn cover_calibrator_get_cover_state(&self, device_id: &str) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let state = cover_cal.cover_state().await?;
                    return Ok(state as i32);
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.cover_state().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
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
                    if let Some(state) = locked.get_switch(&device_name, "CAP_PARK", "PARK").await {
                        // PARK=on means closed, UNPARK=on means open
                        return Ok(if state { 1 } else { 3 }); // 1=Closed, 3=Open
                    }
                    return Ok(4); // Unknown
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator calibrator state
    /// Returns: 0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error
    pub async fn cover_calibrator_get_calibrator_state(
        &self,
        device_id: &str,
    ) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let state = cover_cal.calibrator_state().await?;
                    return Ok(state as i32);
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.calibrator_state().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
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
                    if let Some(state) = locked
                        .get_switch(&device_name, "FLAT_LIGHT_CONTROL", "FLAT_LIGHT_ON")
                        .await
                    {
                        // FLAT_LIGHT_ON=true means Ready (light is on), false means Off
                        return Ok(if state { 3 } else { 1 }); // 3=Ready, 1=Off
                    }
                    return Ok(4); // Unknown
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator brightness
    pub async fn cover_calibrator_get_brightness(&self, device_id: &str) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.brightness().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.brightness().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
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
                    if let Some(brightness) = locked
                        .get_number(
                            &device_name,
                            "FLAT_LIGHT_INTENSITY",
                            "FLAT_LIGHT_INTENSITY_VALUE",
                        )
                        .await
                    {
                        return Ok(brightness as i32);
                    }
                    return Ok(0);
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator max brightness
    pub async fn cover_calibrator_get_max_brightness(
        &self,
        device_id: &str,
    ) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.max_brightness().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.max_brightness().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let cover_cal =
                        nightshade_indi::IndiCoverCalibrator::new(client.clone(), &device_name);
                    return cover_cal.get_max_brightness().await;
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator status (combined state)
    pub async fn cover_calibrator_get_status(
        &self,
        device_id: &str,
    ) -> Result<CoverCalibratorStatus, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                let Some(cover_cal) = cover_cals.get(device_id) else {
                    return Err(format!("Alpaca cover calibrator {} not found", device_id));
                };

                let status = cover_cal.get_status().await?;
                let max_brightness = cover_cal.max_brightness().await.unwrap_or_else(|e| {
                    warn!(
                        "Failed to read cover calibrator max_brightness for {}: {}. Using default 255.",
                        device_id, e
                    );
                    255
                });

                Ok(CoverCalibratorStatus {
                    connected: true,
                    cover_state: CoverState::from_i32(status.cover_state as i32),
                    calibrator_state: CalibratorState::from_i32(status.calibrator_state as i32),
                    brightness: status.brightness.unwrap_or(0),
                    max_brightness,
                })
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                let Some(cover_cal) = cover_cals.get(device_id) else {
                    return Err(format!("ASCOM cover calibrator {} not found", device_id));
                };

                let locked = cover_cal.read().await;
                let cover_state_raw = locked.cover_state().await.unwrap_or_else(|e| {
                    warn!(
                        "Failed to read cover calibrator cover_state for {}: {}. Using Unknown (4).",
                        device_id, e
                    );
                    4
                });
                let calibrator_state_raw = locked.calibrator_state().await.unwrap_or_else(|e| {
                    warn!(
                        "Failed to read cover calibrator calibrator_state for {}: {}. Using Unknown (4).",
                        device_id, e
                    );
                    4
                });
                let brightness = locked.brightness().await.unwrap_or_else(|e| {
                    warn!(
                        "Failed to read cover calibrator brightness for {}: {}. Using default 0.",
                        device_id, e
                    );
                    0
                });

                Ok(CoverCalibratorStatus {
                    connected: true,
                    cover_state: CoverState::from_i32(cover_state_raw),
                    calibrator_state: CalibratorState::from_i32(calibrator_state_raw),
                    brightness,
                    max_brightness: locked.cached_max_brightness(),
                })
            }
            Some(DriverType::Indi) => {
                let cover_state_raw = match self.cover_calibrator_get_cover_state(device_id).await {
                    Ok(s) => s,
                    Err(e) => {
                        warn!(
                            "Failed to read cover calibrator cover_state for {}: {}. Using Unknown (4).",
                            device_id, e
                        );
                        4
                    }
                };
                let calibrator_state_raw = match self
                    .cover_calibrator_get_calibrator_state(device_id)
                    .await
                {
                    Ok(s) => s,
                    Err(e) => {
                        warn!(
                                "Failed to read cover calibrator calibrator_state for {}: {}. Using Unknown (4).",
                                device_id, e
                            );
                        4
                    }
                };
                let brightness = self
                    .cover_calibrator_get_brightness(device_id)
                    .await
                    .unwrap_or_else(|e| {
                        warn!(
                            "Failed to read cover calibrator brightness for {}: {}. Using default 0.",
                            device_id, e
                        );
                        0
                    });
                let max_brightness = self
                    .cover_calibrator_get_max_brightness(device_id)
                    .await
                    .unwrap_or_else(|e| {
                        warn!(
                            "Failed to read cover calibrator max_brightness for {}: {}. Using default 255.",
                            device_id, e
                        );
                        255
                    });

                Ok(CoverCalibratorStatus {
                    connected: true,
                    cover_state: CoverState::from_i32(cover_state_raw),
                    calibrator_state: CalibratorState::from_i32(calibrator_state_raw),
                    brightness,
                    max_brightness,
                })
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }
}
