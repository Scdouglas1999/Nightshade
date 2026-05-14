//! Filter wheel operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::DeviceManager;
use nightshade_native::traits::NativeFilterWheel;

impl DeviceManager {
    // =========================================================================
    // Filter Wheel Control
    // =========================================================================

    pub async fn filter_wheel_set_position(
        &self,
        device_id: &str,
        position: i32,
    ) -> Result<(), String> {
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
                    let wheels = self.ascom_filter_wheels.read().await;
                    if let Some(wheel) = wheels.get(device_id) {
                        let mut wheel = wheel.write().await;
                        return wheel.move_to_position(position).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM filter wheel not connected".to_string())
            }
            DriverType::Native => {
                let mut native_filter_wheels = self.native_filter_wheels.write().await;
                if let Some(wheel) = native_filter_wheels.get_mut(device_id) {
                    return wheel.move_to_position(position).await.map_err(|e| e.to_string());
                }
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Alpaca => {
                let wheels = self.alpaca_filter_wheels.read().await;
                if let Some(wheel) = wheels.get(device_id) {
                    return wheel.set_position(position).await;
                }
                Err(format!("Alpaca filter wheel {} not found", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    // INDI filter slots are 1-based
                    return locked.set_number(&device_name, "FILTER_SLOT", "FILTER_SLOT_VALUE", position as f64).await.map_err(|e| e.to_string());
                }
                Err("INDI filter wheel not connected".to_string())
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

    pub async fn filter_wheel_get_position(&self, device_id: &str) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            let info = devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?;
            info.driver_type
        }; // devices lock dropped here before acquiring other locks

        match driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let wheels = self.ascom_filter_wheels.read().await;
                    if let Some(wheel) = wheels.get(device_id) {
                        let wheel = wheel.read().await;
                        return wheel.get_position().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM filter wheel not connected".to_string())
            }
            DriverType::Native => {
                let native_filter_wheels = self.native_filter_wheels.read().await;
                if let Some(wheel) = native_filter_wheels.get(device_id) {
                    return wheel.get_position().await.map_err(|e| e.to_string());
                }
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Alpaca => {
                let wheels = self.alpaca_filter_wheels.read().await;
                if let Some(wheel) = wheels.get(device_id) {
                    return wheel.position().await;
                }
                Err(format!("Alpaca filter wheel {} not found", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    // INDI filter slots are 1-based, convert to 0-based for consistency
                    if let Some(pos) = locked.get_number(&device_name, "FILTER_SLOT", "FILTER_SLOT_VALUE").await {
                        return Ok((pos as i32) - 1);
                    }
                    return Err("Could not read filter position from INDI device".to_string());
                }
                Err("INDI filter wheel not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn filter_wheel_is_moving(&self, device_id: &str) -> Result<bool, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            let info = devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?;
            info.driver_type
        }; // devices lock dropped here

        match driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let wheels = self.ascom_filter_wheels.read().await;
                    if let Some(wheel) = wheels.get(device_id) {
                        let wheel = wheel.read().await;
                        return wheel.is_moving().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM filter wheel not connected".to_string())
            }
            DriverType::Native => {
                let native_filter_wheels = self.native_filter_wheels.read().await;
                if let Some(wheel) = native_filter_wheels.get(device_id) {
                    return wheel.is_moving().await.map_err(|e| e.to_string());
                }
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Alpaca => {
                let wheels = self.alpaca_filter_wheels.read().await;
                if let Some(wheel) = wheels.get(device_id) {
                    // Alpaca filter wheels return -1 for position when moving
                    let pos = wheel.position().await?;
                    return Ok(pos == -1);
                }
                Err(format!("Alpaca filter wheel {} not found", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    // INDI uses property busy state to indicate movement
                    return Ok(locked.is_property_busy(&device_name, "FILTER_SLOT").await);
                }
                Err("INDI filter wheel not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn filter_wheel_get_config(
        &self,
        device_id: &str,
    ) -> Result<(i32, Vec<String>), String> {
        tracing::debug!(
            "filter_wheel_get_config: Looking up device_id='{}'",
            device_id
        );

        let devices = self.devices.read().await;
        let device_keys: Vec<_> = devices.keys().collect();
        tracing::debug!(
            "filter_wheel_get_config: Available devices in registry: {:?}",
            device_keys
        );

        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        tracing::debug!(
            "filter_wheel_get_config: Found device with driver_type={:?}",
            info.driver_type
        );
        drop(devices); // Release the lock before async operations

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let wheels = self.ascom_filter_wheels.read().await;
                    let ascom_keys: Vec<_> = wheels.keys().collect();
                    tracing::debug!("filter_wheel_get_config: Looking for '{}' in ascom_filter_wheels: {:?}", device_id, ascom_keys);

                    if let Some(wheel) = wheels.get(device_id) {
                        let wheel = wheel.read().await;
                        let names = wheel.get_filter_names().await.map_err(|e| e.to_string())?;
                        let count = names.len() as i32;
                        return Ok((count, names));
                    }
                    tracing::error!("filter_wheel_get_config: ASCOM filter wheel '{}' not found in ascom_filter_wheels map!", device_id);
                }
                Err("ASCOM filter wheel not connected".to_string())
            }
            DriverType::Alpaca => {
                let wheels = self.alpaca_filter_wheels.read().await;
                if let Some(wheel) = wheels.get(device_id) {
                    let names = wheel.names().await?;
                    let count = names.len() as i32;
                    return Ok((count, names));
                }
                Err(format!("Alpaca filter wheel {} not found", device_id))
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
                        let locked_client = client.read().await;
                        let names = locked_client.get_filter_names(&device_name).await
                            .unwrap_or_else(|_| vec![]);
                        let count = names.len() as i32;
                        return Ok((count, names));
                    }
                }
                Err("INDI filter wheel not connected".to_string())
            }
            DriverType::Native => {
                let native_filter_wheels = self.native_filter_wheels.read().await;
                let native_keys: Vec<_> = native_filter_wheels.keys().collect();
                tracing::debug!("filter_wheel_get_config: Looking for '{}' in native_filter_wheels: {:?}", device_id, native_keys);

                if let Some(wheel) = native_filter_wheels.get(device_id) {
                    let count = wheel.get_filter_count();
                    let names = wheel.get_filter_names().await.map_err(|e| e.to_string())?;
                    tracing::info!("filter_wheel_get_config: Returning {} filter names: {:?}", count, names);
                    return Ok((count, names));
                }
                tracing::error!("filter_wheel_get_config: Native filter wheel '{}' not found in native_filter_wheels map!", device_id);
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    /// Set filter names on a filter wheel.
    /// This pushes user-defined filter names from the equipment profile to the hardware driver.
    pub async fn filter_wheel_set_filter_names(
        &self,
        device_id: &str,
        names: Vec<String>,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        tracing::info!(
            "filter_wheel_set_filter_names: Setting filter names for '{}': {:?}",
            device_id,
            names
        );

        match info.driver_type {
            DriverType::Native => {
                let mut native_filter_wheels = self.native_filter_wheels.write().await;
                if let Some(wheel) = native_filter_wheels.get_mut(device_id) {
                    for (i, name) in names.iter().enumerate() {
                        wheel.set_filter_name(i as i32, name.clone()).await.map_err(|e| e.to_string())?;
                    }
                    tracing::info!("filter_wheel_set_filter_names: Successfully set {} filter names", names.len());
                    return Ok(());
                }
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Ascom => {
                // ASCOM filter names are typically stored in the driver's configuration
                // Many ASCOM drivers don't support programmatic name setting
                let msg = "ASCOM filter names are managed by the driver and cannot be set programmatically";
                tracing::warn!("filter_wheel_set_filter_names: {}", msg);
                Err(msg.to_string())
            }
            DriverType::Alpaca => {
                // Alpaca filter names are typically read-only from the driver
                let msg = "Alpaca filter names are read-only and cannot be set programmatically";
                tracing::warn!("filter_wheel_set_filter_names: {}", msg);
                Err(msg.to_string())
            }
            DriverType::Indi => {
                // INDI filter names can be set via FILTER_NAME property
                let msg = "INDI filter name setting is unavailable in this manager path";
                tracing::warn!("filter_wheel_set_filter_names: {}", msg);
                Err(msg.to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }
}
