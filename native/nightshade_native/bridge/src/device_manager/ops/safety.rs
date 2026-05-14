//! Safety monitor operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::DeviceManager;

impl DeviceManager {
    // =========================================================================
    // Safety Monitor
    // =========================================================================

    /// Check if conditions are safe
    pub async fn safety_is_safe(&self, device_id: &str) -> Result<bool, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let safety_devs = self.alpaca_safety_monitors.read().await;
                if let Some(safety) = safety_devs.get(device_id) {
                    return safety.is_safe().await;
                }
                Err(format!("Alpaca safety monitor {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    use nightshade_indi::IndiSafetyMonitor;
                    let safety = IndiSafetyMonitor::new(client.clone(), &device_name);
                    return safety.is_safe().await;
                }
                Err(format!("INDI client not connected for server {}", server_key))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let safety_monitors = self.ascom_safety_monitors.read().await;
                    if let Some(safety) = safety_monitors.get(device_id) {
                        let safety_guard = safety.read().await;
                        return safety_guard.is_safe().await;
                    }
                    Err(format!("ASCOM safety monitor {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
            }
            Some(DriverType::Native) => {
                let native_safety = self.native_safety_monitors.read().await;
                if let Some(safety) = native_safety.get(device_id) {
                    return safety.is_safe().await.map_err(|e| e.to_string());
                }
                Err("Native safety monitor not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }
}
