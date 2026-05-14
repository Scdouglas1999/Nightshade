//! Rotator operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::DeviceManager;

impl DeviceManager {
    // =========================================================================
    // Rotator Control
    // =========================================================================

    /// Get rotator position (sky angle in degrees)
    pub async fn rotator_get_position(&self, device_id: &str) -> Result<f64, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.position().await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.position().await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
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
                    if let Some(pos) = locked.get_number(&device_name, "ABS_ROTATOR_ANGLE", "ANGLE").await {
                        return Ok(pos);
                    }
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let native_rotators = self.native_rotators.read().await;
                if let Some(rotator) = native_rotators.get(device_id) {
                    return rotator.get_position().await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Move rotator to absolute sky position (degrees)
    pub async fn rotator_move_absolute(
        &self,
        device_id: &str,
        position: f64,
    ) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.move_absolute(position).await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.move_absolute(position).await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
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
                    return locked.set_number(&device_name, "ABS_ROTATOR_ANGLE", "ANGLE", position).await.map_err(|e| e.to_string());
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_rotators = self.native_rotators.write().await;
                if let Some(rotator) = native_rotators.get_mut(device_id) {
                    return rotator.move_to(position).await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Halt rotator motion
    pub async fn rotator_halt(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.halt().await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.halt().await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
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
                    return locked.set_switch(&device_name, "ROTATOR_ABORT_MOTION", "ABORT", true).await.map_err(|e| e.to_string());
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_rotators = self.native_rotators.write().await;
                if let Some(rotator) = native_rotators.get_mut(device_id) {
                    return rotator.halt().await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Sync the reported rotator sky angle to `position` without moving the
    /// hardware. Used after a plate solve to align the driver's reported PA
    /// with the astrometric PA of the last frame. Why dispatch matches
    /// `rotator_move_absolute`: identical driver layout (Alpaca/ASCOM/INDI/
    /// Native) and lock acquisition rules.
    pub async fn rotator_sync(&self, device_id: &str, position: f64) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.sync(position).await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.sync(position).await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
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
                    // INDI standard property for syncing the reported angle
                    // without rotating: SYNC_ROTATOR_ANGLE/ANGLE.
                    return locked
                        .set_number(&device_name, "SYNC_ROTATOR_ANGLE", "ANGLE", position)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_rotators = self.native_rotators.write().await;
                if let Some(rotator) = native_rotators.get_mut(device_id) {
                    return rotator.sync(position).await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Check if rotator is moving
    pub async fn rotator_is_moving(&self, device_id: &str) -> Result<bool, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.is_moving().await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.is_moving().await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
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
                    return Ok(locked.is_property_busy(&device_name, "ABS_ROTATOR_ANGLE").await);
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let native_rotators = self.native_rotators.read().await;
                if let Some(rotator) = native_rotators.get(device_id) {
                    return rotator.is_moving().await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }
}
