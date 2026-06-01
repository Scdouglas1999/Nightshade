//! Switch device operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::dispatch::DeviceOpError;

impl DeviceManager {
    // =========================================================================
    // INDI Switch Helpers
    // =========================================================================

    // indi_get_all_switches / indi_get_switch_at moved to
    // `crate::dispatch::indi`; call sites use `self.indi_*` unchanged.

    // =========================================================================
    // Switch Control
    // =========================================================================

    /// Get the number of switches exposed by a switch device
    pub async fn switch_get_max(&self, device_id: &str) -> Result<i32, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_max_switch().await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.max_switch().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                // INDI switches use named properties -- enumerate and count them
                let switches = self.indi_get_all_switches(device_id).await?;
                // Why (audit-rust §1.4): INDI switch counts are tiny (a
                // power-box has ≤ a dozen outputs); usize → i32 SAFE for
                // any realistic device.
                Ok(i32::try_from(switches.len()).unwrap_or(i32::MAX))
            }
            DriverType::Native => {
                let switches = self.native_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch_count().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Get the boolean state of a switch
    pub async fn switch_get_state(&self, device_id: &str, switch_id: i32) -> Result<bool, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_switch(switch_id).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch(switch_id).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                Ok(sw.state)
            }
            DriverType::Native => {
                let switches = self.native_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw
                        .get_switch_state(switch_id)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Set the boolean state of a switch
    pub async fn switch_set_state(
        &self,
        device_id: &str,
        switch_id: i32,
        state: bool,
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
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let mut sw = sw.write().await;
                        return sw.set_switch(switch_id, state).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.set_switch(switch_id, state).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                if !sw.writable {
                    return Err(DeviceOpError::unsupported(format!(
                        "INDI switch '{}' / '{}' is read-only",
                        sw.property_name, sw.element_name
                    )));
                }
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let switch_dev =
                        nightshade_indi::IndiSwitchDevice::new(client.clone(), &device_name);
                    return switch_dev
                        .set_switch_state(&sw.property_name, &sw.element_name, state)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "INDI switch device not connected"))
            }
            DriverType::Native => {
                let mut switches = self.native_switches.write().await;
                if let Some(sw) = switches.get_mut(device_id) {
                    return sw
                        .set_switch_state(switch_id, state)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Get the name of a switch
    pub async fn switch_get_name(&self, device_id: &str, switch_id: i32) -> Result<String, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_switch_name(switch_id).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch_name(switch_id).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                Ok(sw.element_name.clone())
            }
            DriverType::Native => {
                let switches = self.native_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw
                        .get_switch_name(switch_id)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Get the description of a switch
    pub async fn switch_get_description(
        &self,
        device_id: &str,
        switch_id: i32,
    ) -> Result<String, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_switch_description(switch_id).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch_description(switch_id).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                // For INDI, description is "property_name / label"
                Ok(format!("{} / {}", sw.property_name, sw.label))
            }
            DriverType::Native => {
                let switches = self.native_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw
                        .get_switch_description(switch_id)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Get the numeric value of a switch
    pub async fn switch_get_value(&self, device_id: &str, switch_id: i32) -> Result<f64, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_switch_value(switch_id).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch_value(switch_id).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                // INDI switches can have associated number values (e.g., PWM duty cycle)
                let parts: Vec<&str> = device_id.split(':').collect();
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let switch_dev =
                        nightshade_indi::IndiSwitchDevice::new(client.clone(), &device_name);
                    if let Some(val) = switch_dev
                        .get_switch_value(&sw.property_name, &sw.element_name)
                        .await
                    {
                        return Ok(val);
                    }
                    // If no numeric value, return 1.0 for on, 0.0 for off
                    return Ok(if sw.state { 1.0 } else { 0.0 });
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "INDI switch device not connected"))
            }
            DriverType::Native => {
                let switches = self.native_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw
                        .get_switch_value(switch_id)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Set the numeric value of a switch
    pub async fn switch_set_value(
        &self,
        device_id: &str,
        switch_id: i32,
        value: f64,
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
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let mut sw = sw.write().await;
                        return sw.set_switch_value(switch_id, value).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.set_switch_value(switch_id, value).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                if !sw.writable {
                    return Err(DeviceOpError::unsupported(format!(
                        "INDI switch '{}' / '{}' is read-only",
                        sw.property_name, sw.element_name
                    )));
                }
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let switch_dev =
                        nightshade_indi::IndiSwitchDevice::new(client.clone(), &device_name);
                    return switch_dev
                        .set_switch_value(&sw.property_name, &sw.element_name, value)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), "INDI switch device not connected"))
            }
            DriverType::Native => {
                let mut switches = self.native_switches.write().await;
                if let Some(sw) = switches.get_mut(device_id) {
                    return sw
                        .set_switch_value(switch_id, value)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Get the minimum value for a switch
    pub async fn switch_get_min_value(
        &self,
        device_id: &str,
        switch_id: i32,
    ) -> Result<f64, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_min_switch_value(switch_id).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.min_switch_value(switch_id).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                // INDI boolean switches have min 0.0
                Ok(0.0)
            }
            DriverType::Native => {
                let switches = self.native_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw
                        .get_switch_min_value(switch_id)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Get the maximum value for a switch
    pub async fn switch_get_max_value(
        &self,
        device_id: &str,
        switch_id: i32,
    ) -> Result<f64, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_max_switch_value(switch_id).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.max_switch_value(switch_id).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                // INDI boolean switches have max 1.0
                Ok(1.0)
            }
            DriverType::Native => {
                let switches = self.native_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw
                        .get_switch_max_value(switch_id)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }

    /// Check if a switch can be written to
    pub async fn switch_can_write(&self, device_id: &str, switch_id: i32) -> Result<bool, DeviceOpError> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| DeviceOpError::device_not_found(device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.can_write(switch_id).await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("ASCOM switch {} not found", device_id)))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.can_write(switch_id).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Alpaca switch {} not found", device_id)))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                Ok(sw.writable)
            }
            DriverType::Native => {
                let switches = self.native_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.can_write(switch_id).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(Some(device_id.to_string()), format!("Native switch {} not found", device_id)))
            }
            DriverType::Simulator => {
                Err(DeviceOpError::unsupported(crate::device_manager::ops::sim_gate::unsupported_simulator_device("switch")))
            }
        }
    }
}
