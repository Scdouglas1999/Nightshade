//! ASCOM Filter Wheel wrapper and batch status types.

use super::connection::AscomDeviceConnection;
use super::health::ConnectionHealth;

/// ASCOM Filter Wheel
pub struct AscomFilterWheel {
    device: AscomDeviceConnection,
}

impl AscomFilterWheel {
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

    pub fn position(&self) -> Result<i32, String> {
        let pos = self.device.get_int_property("Position");
        tracing::info!("ASCOM FilterWheel.Position returned: {:?}", pos);
        pos
    }

    pub fn set_position(&mut self, position: i32) -> Result<(), String> {
        tracing::info!("ASCOM FilterWheel.SetPosition({})", position);
        self.device.set_int_property("Position", position)
    }

    pub fn names(&self) -> Result<Vec<String>, String> {
        self.device.get_string_array_property("Names")
    }

    // ========================================================================
    // Batch Property Queries
    // ========================================================================

    /// Get complete filter wheel status in a single batch operation
    pub fn get_full_status(&self) -> FilterWheelFullStatus {
        FilterWheelFullStatus {
            position: self.position().ok(),
            names: self.names().ok(),
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

/// Full filter wheel status
#[derive(Debug, Clone, Default)]
pub struct FilterWheelFullStatus {
    pub position: Option<i32>,
    pub names: Option<Vec<String>>,
}
