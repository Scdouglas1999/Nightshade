//! ASCOM Safety Monitor wrapper and batch status types.

use super::connection::AscomDeviceConnection;
use super::health::ConnectionHealth;

/// ASCOM Safety Monitor
pub struct AscomSafetyMonitor {
    device: AscomDeviceConnection,
}

impl AscomSafetyMonitor {
    pub fn new(prog_id: &str) -> Result<Self, String> {
        Ok(Self {
            device: AscomDeviceConnection::new(prog_id)?,
        })
    }

    pub fn connect(&mut self) -> Result<(), String> {
        self.device.connect()
    }

    pub fn disconnect(&mut self) -> Result<(), String> {
        self.device.disconnect()
    }

    pub fn name(&self) -> Result<String, String> {
        self.device.get_string_property("Name")
    }

    /// Get the interface version number
    pub fn interface_version(&self) -> Result<i32, String> {
        self.device.get_int_property("InterfaceVersion")
    }

    /// Get the driver version string
    pub fn driver_version(&self) -> Result<String, String> {
        self.device.get_string_property("DriverVersion")
    }

    /// Get the driver info/description
    pub fn driver_info(&self) -> Result<String, String> {
        self.device.get_string_property("DriverInfo")
    }

    /// Get the list of supported custom actions
    pub fn supported_actions(&self) -> Result<Vec<String>, String> {
        self.device.get_string_array_property("SupportedActions")
    }

    pub fn is_safe(&self) -> Result<bool, String> {
        self.device.get_bool_property("IsSafe")
    }

    // ========================================================================
    // Batch Property Queries
    // ========================================================================

    /// Get complete safety monitor status in a single batch operation
    pub fn get_full_status(&self) -> SafetyMonitorFullStatus {
        SafetyMonitorFullStatus {
            is_safe: self.is_safe().ok(),
        }
    }

    /// Perform a heartbeat check to verify device is still responding
    pub fn heartbeat(&self) -> Result<(), String> {
        self.device.heartbeat()
    }

    /// Get connection health status
    pub fn get_health(&self) -> ConnectionHealth {
        self.device.get_health()
    }
}

/// Full safety monitor status
#[derive(Debug, Clone, Default)]
pub struct SafetyMonitorFullStatus {
    pub is_safe: Option<bool>,
}
