//! Focuser operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::DeviceManager;
use nightshade_native::traits::NativeFocuser;
use tracing::warn;

impl DeviceManager {
    // =========================================================================
    // Focuser Control
    // =========================================================================

    pub async fn focuser_move_abs(&self, device_id: &str, position: i32) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let mut focuser = focuser.write().await;
                        return focuser.move_to(position).await.map_err(|e| {
                            format!("Failed to move ASCOM focuser {} to position {}: {}", device_id, position, e)
                        });
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let mut native_focusers = self.native_focusers.write().await;
                if let Some(focuser) = native_focusers.get_mut(device_id) {
                    return focuser.move_to(position).await.map_err(|e| {
                        format!("Failed to move native focuser {} to position {}: {}", device_id, position, e)
                    });
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser
                        .move_to_typed(position)
                        .await
                        .map_err(|e| {
                            format!("Failed to move Alpaca focuser {} to position {}: {}", device_id, position, e)
                        });
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return focuser.move_to(position).await.map_err(|e| {
                            format!("Failed to move INDI focuser {} to position {}: {}", device_name, position, e)
                        });
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn focuser_move_rel(&self, device_id: &str, steps: i32) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let mut focuser = focuser.write().await;
                        return focuser.move_relative(steps).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let mut native_focusers = self.native_focusers.write().await;
                if let Some(focuser) = native_focusers.get_mut(device_id) {
                    return focuser.move_relative(steps).await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                // Alpaca focusers only support absolute positioning, so we compute target position
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    let current_position = focuser.position().await?;
                    let target_position = current_position + steps;
                    return focuser
                        .move_to_typed(target_position)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return focuser.move_relative(steps).await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn focuser_halt(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let mut focuser = focuser.write().await;
                        return focuser.halt().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let mut native_focusers = self.native_focusers.write().await;
                if let Some(focuser) = native_focusers.get_mut(device_id) {
                    return focuser.halt().await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser.halt().await;
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return focuser.abort_motion().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
// Fallback logic for devices not matching specific driver types
            // This is primarily for the catch-all pattern required by match
            // but in practice DriverType is exhaustive for supported devices.
            // Keeping this arm for safety but returning an error is correct.
        }
    }

    pub async fn focuser_get_position(&self, device_id: &str) -> Result<i32, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return focuser.get_position().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let native_focusers = self.native_focusers.read().await;
                if let Some(focuser) = native_focusers.get(device_id) {
                    return focuser.get_position().await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser.position().await;
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return focuser.get_position().await;
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
// Fallback logic for devices not matching specific driver types
        }
    }

    pub async fn focuser_is_moving(&self, device_id: &str) -> Result<bool, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return focuser.is_moving().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let native_focusers = self.native_focusers.read().await;
                if let Some(focuser) = native_focusers.get(device_id) {
                    return focuser.is_moving().await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser.is_moving().await;
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return Ok(focuser.is_moving().await);
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
// Fallback logic for devices not matching specific driver types
        }
    }

    pub async fn focuser_is_absolute(&self, device_id: &str) -> Result<bool, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return focuser.is_absolute().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => Ok(true),
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser.absolute().await;
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let client = client.read().await;
                        return Ok(client
                            .get_property_state(&device_name, "ABS_FOCUS_POSITION")
                            .await
                            .is_some());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn focuser_get_temp(&self, device_id: &str) -> Result<Option<f64>, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return focuser.get_temperature().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let native_focusers = self.native_focusers.read().await;
                if let Some(focuser) = native_focusers.get(device_id) {
                    return focuser.get_temperature().await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    // Alpaca temperature() returns f64, wrap in Some for consistency
                    return focuser.temperature().await.map(Some);
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        // Temperature might not be available on all focusers
                        match focuser.get_temperature().await {
                            Ok(temp) => return Ok(Some(temp)),
                            Err(_) => return Ok(None), // Temperature not available
                        }
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn focuser_get_details(&self, device_id: &str) -> Result<(i32, f64), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return Ok((focuser.get_max_position(), focuser.get_step_size()));
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let native_focusers = self.native_focusers.read().await;
                if let Some(focuser) = native_focusers.get(device_id) {
                    return Ok((focuser.get_max_position(), focuser.get_step_size()));
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    let max_step = focuser.max_step().await?;
                    let step_size = match focuser.step_size().await {
                        Ok(s) => s,
                        Err(e) => {
                            warn!("Failed to read Alpaca focuser step_size for {}: {}. Using default 1.0.", device_id, e);
                            1.0
                        }
                    };
                    return Ok((max_step, step_size));
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let client = client.read().await;

                        // Try to get max position from FOCUS_MAX property (common INDI standard)
                        // If unavailable, report unknown (0) instead of inventing a fake limit.
                        let max_position = match client.get_number(&device_name, "FOCUS_MAX", "FOCUS_MAX_VALUE").await {
                            // Why (audit-rust §1.4): INDI wire is f64 but
                            // FOCUS_MAX is a step count physically ≤ ~200k
                            // for any real focuser. Rust 1.45+ saturating
                            // f64 → i32 catches an out-of-range driver bug
                            // by reporting i32::MAX (which the UI displays
                            // as "max step out of range" anyway).
                            Some(v) => v as i32,
                            None => {
                                warn!(
                                    "Failed to read INDI focuser max position for {}: property not available. Reporting unknown max position.",
                                    device_id
                                );
                                0
                            }
                        };

                        // Step size is not universally standardized in INDI
                        // Report unknown (0.0) when unavailable rather than assuming 1.0.
                        let step_size = match client.get_number(&device_name, "FOCUS_STEP", "FOCUS_STEP_VALUE").await {
                            Some(s) => s,
                            None => {
                                warn!(
                                    "Failed to read INDI focuser step size for {}: property not available. Reporting unknown step size.",
                                    device_id
                                );
                                0.0
                            }
                        };

                        return Ok((max_position, step_size));
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }
}
