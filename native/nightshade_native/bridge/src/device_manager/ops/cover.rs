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
use crate::dispatch::DeviceOpError;
use tracing::warn;

fn native_cover_state_to_bridge(state: nightshade_native::traits::NativeCoverState) -> CoverState {
    match state {
        nightshade_native::traits::NativeCoverState::NotPresent => CoverState::NotPresent,
        nightshade_native::traits::NativeCoverState::Closed => CoverState::Closed,
        nightshade_native::traits::NativeCoverState::Moving => CoverState::Moving,
        nightshade_native::traits::NativeCoverState::Open => CoverState::Open,
        nightshade_native::traits::NativeCoverState::Unknown => CoverState::Unknown,
        nightshade_native::traits::NativeCoverState::Error => CoverState::Error,
    }
}

fn native_calibrator_state_to_bridge(
    state: nightshade_native::traits::NativeCalibratorState,
) -> CalibratorState {
    match state {
        nightshade_native::traits::NativeCalibratorState::NotPresent => CalibratorState::NotPresent,
        nightshade_native::traits::NativeCalibratorState::Off => CalibratorState::Off,
        nightshade_native::traits::NativeCalibratorState::NotReady => CalibratorState::NotReady,
        nightshade_native::traits::NativeCalibratorState::Ready => CalibratorState::Ready,
        nightshade_native::traits::NativeCalibratorState::Unknown => CalibratorState::Unknown,
        nightshade_native::traits::NativeCalibratorState::Error => CalibratorState::Error,
    }
}

impl DeviceManager {
    async fn indi_cover_calibrator(
        &self,
        device_id: &str,
    ) -> Result<nightshade_indi::IndiCoverCalibrator, DeviceOpError> {
        let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
        let server_key = format!("{}:{}", host, port);
        let clients = self.indi_clients.read().await;
        let client = clients.get(&server_key).cloned();
        drop(clients);

        client
            .map(|client| nightshade_indi::IndiCoverCalibrator::new(client, &device_name))
            .ok_or_else(|| DeviceOpError::not_connected(Some(device_id.to_string()), "INDI cover calibrator not connected"))
    }

    // =========================================================================
    // Cover Calibrator Control
    // =========================================================================

    /// Open cover calibrator cover
    pub async fn cover_calibrator_open_cover(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.open_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.open_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                cover_cal.open_cover().await.map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let mut covers = self.native_cover_calibrators.write().await;
                if let Some(cover_cal) = covers.get_mut(device_id) {
                    return cover_cal.open_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Close cover calibrator cover
    pub async fn cover_calibrator_close_cover(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.close_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.close_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                cover_cal.close_cover().await.map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let mut covers = self.native_cover_calibrators.write().await;
                if let Some(cover_cal) = covers.get_mut(device_id) {
                    return cover_cal.close_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Halt cover calibrator cover movement
    pub async fn cover_calibrator_halt_cover(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.halt_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.halt_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                cover_cal.halt_cover().await.map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let mut covers = self.native_cover_calibrators.write().await;
                if let Some(cover_cal) = covers.get_mut(device_id) {
                    return cover_cal.halt_cover().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Turn on cover calibrator light
    pub async fn cover_calibrator_calibrator_on(
        &self,
        device_id: &str,
        brightness: i32,
    ) -> Result<(), DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.calibrator_on(brightness).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.calibrator_on(brightness).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                cover_cal.calibrator_on(brightness).await.map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let mut covers = self.native_cover_calibrators.write().await;
                if let Some(cover_cal) = covers.get_mut(device_id) {
                    return cover_cal
                        .calibrator_on(brightness)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Turn off cover calibrator light
    pub async fn cover_calibrator_calibrator_off(&self, device_id: &str) -> Result<(), DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.calibrator_off().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.calibrator_off().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                cover_cal.calibrator_off().await.map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let mut covers = self.native_cover_calibrators.write().await;
                if let Some(cover_cal) = covers.get_mut(device_id) {
                    return cover_cal.calibrator_off().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Get cover calibrator cover state
    /// Returns: 0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error
    pub async fn cover_calibrator_get_cover_state(&self, device_id: &str) -> Result<i32, DeviceOpError> {
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
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.cover_state().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                Ok(cover_cal.get_cover_state().await.to_i32())
            }
            Some(DriverType::Native) => {
                let covers = self.native_cover_calibrators.read().await;
                if let Some(cover_cal) = covers.get(device_id) {
                    return cover_cal
                        .get_cover_state()
                        .await
                        .map(native_cover_state_to_bridge)
                        .map(|state| state.to_i32())
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Get cover calibrator calibrator state
    /// Returns: 0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error
    pub async fn cover_calibrator_get_calibrator_state(
        &self,
        device_id: &str,
    ) -> Result<i32, DeviceOpError> {
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
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.calibrator_state().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                Ok(cover_cal.get_calibrator_state().await.to_i32())
            }
            Some(DriverType::Native) => {
                let covers = self.native_cover_calibrators.read().await;
                if let Some(cover_cal) = covers.get(device_id) {
                    return cover_cal
                        .get_calibrator_state()
                        .await
                        .map(native_calibrator_state_to_bridge)
                        .map(|state| state.to_i32())
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Get cover calibrator brightness
    pub async fn cover_calibrator_get_brightness(&self, device_id: &str) -> Result<i32, DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.brightness().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.brightness().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                cover_cal.get_brightness().await.map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let covers = self.native_cover_calibrators.read().await;
                if let Some(cover_cal) = covers.get(device_id) {
                    return cover_cal.get_brightness().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Get cover calibrator max brightness
    pub async fn cover_calibrator_get_max_brightness(
        &self,
        device_id: &str,
    ) -> Result<i32, DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.max_brightness().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.max_brightness().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Indi) => {
                let cover_cal = self.indi_cover_calibrator(device_id).await?;
                cover_cal.get_max_brightness().await.map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let covers = self.native_cover_calibrators.read().await;
                if let Some(cover_cal) = covers.get(device_id) {
                    return cover_cal
                        .get_max_brightness()
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native cover calibrator {} not found", device_id)))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }

    /// Get cover calibrator status (combined state)
    pub async fn cover_calibrator_get_status(
        &self,
        device_id: &str,
    ) -> Result<CoverCalibratorStatus, DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                let Some(cover_cal) = cover_cals.get(device_id) else {
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca cover calibrator {} not found", device_id)));
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
                    return Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM cover calibrator {} not found", device_id)));
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
            Some(DriverType::Native) => {
                let cover_state_raw = match self.cover_calibrator_get_cover_state(device_id).await {
                    Ok(s) => s,
                    Err(e) => {
                        warn!(
                            "Failed to read native cover calibrator cover_state for {}: {}. Using Unknown (4).",
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
                            "Failed to read native cover calibrator calibrator_state for {}: {}. Using Unknown (4).",
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
                            "Failed to read native cover calibrator brightness for {}: {}. Using default 0.",
                            device_id, e
                        );
                        0
                    });
                let max_brightness = self
                    .cover_calibrator_get_max_brightness(device_id)
                    .await
                    .unwrap_or_else(|e| {
                        warn!(
                            "Failed to read native cover calibrator max_brightness for {}: {}. Using default 255.",
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
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "cover calibrator",
                ),
            )),
            _ => Err(DeviceOpError::unsupported("Cover calibrator not supported for this driver type")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::device_manager::ManagedDevice;
    use crate::state::AppState;
    use std::time::Duration;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    fn build_cover_info(id: &str) -> DeviceInfo {
        DeviceInfo {
            id: id.to_string(),
            name: "FlatMaster".to_string(),
            device_type: DeviceType::CoverCalibrator,
            driver_type: DriverType::Indi,
            description: "Test INDI cover calibrator".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "FlatMaster".to_string(),
        }
    }

    async fn connect_fake_cover(
        xml: &'static str,
    ) -> (
        std::sync::Arc<DeviceManager>,
        String,
        tokio::sync::oneshot::Receiver<String>,
        tokio::task::JoinHandle<()>,
    ) {
        let manager = DeviceManager::new(AppState::new());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind fake INDI cover server");
        let port = listener.local_addr().expect("read listener address").port();
        let device_id = format!("indi:127.0.0.1:{}:FlatMaster", port);

        manager.devices.write().await.insert(
            device_id.clone(),
            ManagedDevice {
                info: build_cover_info(&device_id),
                connection_state: ConnectionState::Connected,
                last_error: None,
                reconnect_attempts: 0,
                auto_reconnect: false,
                last_successful_comm: None,
                heartbeat_active: false,
                api_version: None,
            },
        );

        let (command_tx, command_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.expect("accept INDI client");
            let mut buf = vec![0_u8; 4096];
            let _ = socket
                .read(&mut buf)
                .await
                .expect("read initial getProperties");
            socket.write_all(xml.as_bytes()).await.expect("write XML");

            loop {
                buf.fill(0);
                let n = socket.read(&mut buf).await.expect("read cover command");
                if n == 0 {
                    break;
                }
                let command = String::from_utf8_lossy(&buf[..n]).to_string();
                if command.contains("<newSwitchVector")
                    && command.contains("name=\"LIGHTBOX_CONTROL\"")
                {
                    let _ = command_tx.send(command);
                    break;
                }
            }
        });

        let mut timeout_config = nightshade_indi::IndiTimeoutConfig::default();
        timeout_config.connection_timeout_secs = 1;
        let mut client = nightshade_indi::IndiClient::with_timeout_config(
            "127.0.0.1",
            Some(port),
            timeout_config,
        );
        client.connect().await.expect("connect fake INDI client");

        manager.indi_clients.write().await.insert(
            format!("127.0.0.1:{}", port),
            std::sync::Arc::new(tokio::sync::RwLock::new(client)),
        );

        wait_for_lightbox_property(&manager, &device_id).await;
        (manager, device_id, command_rx, server)
    }

    async fn wait_for_lightbox_property(manager: &DeviceManager, device_id: &str) {
        let parts: Vec<&str> = device_id.split(':').collect();
        let server_key = format!("{}:{}", parts[1], parts[2]);
        let deadline = tokio::time::Instant::now() + Duration::from_secs(2);

        loop {
            let client = {
                let clients = manager.indi_clients.read().await;
                clients.get(&server_key).cloned()
            }
            .expect("fake INDI client should be registered");

            if client
                .read()
                .await
                .has_property("FlatMaster", "LIGHTBOX_CONTROL")
                .await
            {
                break;
            }

            assert!(
                tokio::time::Instant::now() < deadline,
                "fake INDI LIGHTBOX_CONTROL property was not parsed in time"
            );
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }

    #[tokio::test]
    async fn indi_cover_open_uses_lightbox_control_fallback() {
        let xml = r#"
<defSwitchVector device="FlatMaster" name="LIGHTBOX_CONTROL" state="Ok" perm="rw" rule="OneOfMany">
  <defSwitch name="OPEN">Off</defSwitch>
  <defSwitch name="CLOSE">On</defSwitch>
</defSwitchVector>
"#;
        let (manager, device_id, command_rx, server) = connect_fake_cover(xml).await;

        manager
            .cover_calibrator_open_cover(&device_id)
            .await
            .expect("LIGHTBOX_CONTROL OPEN should be accepted");

        let command = tokio::time::timeout(Duration::from_secs(2), command_rx)
            .await
            .expect("fake INDI server should receive LIGHTBOX_CONTROL command")
            .expect("fake INDI server should send observed command");
        assert!(
            command.contains("<oneSwitch name=\"OPEN\">On</oneSwitch>"),
            "open command should turn LIGHTBOX OPEN on: {}",
            command
        );
        assert!(
            command.contains("<oneSwitch name=\"CLOSE\">Off</oneSwitch>"),
            "open command should turn LIGHTBOX CLOSE off: {}",
            command
        );
        server.await.expect("fake INDI server should finish");
    }

    #[tokio::test]
    async fn indi_cover_state_reads_lightbox_control() {
        let xml = r#"
<defSwitchVector device="FlatMaster" name="LIGHTBOX_CONTROL" state="Ok" perm="rw" rule="OneOfMany">
  <defSwitch name="OPEN">On</defSwitch>
  <defSwitch name="CLOSE">Off</defSwitch>
</defSwitchVector>
"#;
        let (manager, device_id, _command_rx, server) = connect_fake_cover(xml).await;

        let state = manager
            .cover_calibrator_get_cover_state(&device_id)
            .await
            .expect("LIGHTBOX_CONTROL state should be readable");

        assert_eq!(state, 3);
        drop(manager);
        server.abort();
    }
}
