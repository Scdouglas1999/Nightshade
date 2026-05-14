//! ASCOM Rotator wrapper and batch status types.

use super::connection::AscomDeviceConnection;
use super::health::ConnectionHealth;

/// ASCOM Rotator
pub struct AscomRotator {
    device: AscomDeviceConnection,
}

impl AscomRotator {
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

    pub fn position(&self) -> Result<f64, String> {
        self.device.get_double_property("Position")
    }

    pub fn mechanical_position(&self) -> Result<f64, String> {
        self.device.get_double_property("MechanicalPosition")
    }

    pub fn is_moving(&self) -> Result<bool, String> {
        self.device.get_bool_property("IsMoving")
    }

    pub fn move_to(&mut self, position: f64) -> Result<(), String> {
        self.device.call_method_1_double("Move", position)
    }

    pub fn move_absolute(&mut self, position: f64) -> Result<(), String> {
        self.device.call_method_1_double("MoveAbsolute", position)
    }

    pub fn halt(&mut self) -> Result<(), String> {
        self.device.call_method("Halt")
    }

    /// Sync the reported position to the supplied angle without rotating the
    /// hardware. Why a thin wrapper: ASCOM IRotatorV3 exposes `Sync(Position)`
    /// which adjusts the offset between the mechanical encoder and the
    /// reported sky angle — the same primitive plate-solve "sync to image PA"
    /// needs.
    pub fn sync(&mut self, position: f64) -> Result<(), String> {
        self.device.call_method_1_double("Sync", position)
    }

    // ========================================================================
    // Batch Property Queries
    // ========================================================================

    /// Get complete rotator status in a single batch operation
    pub fn get_full_status(&self) -> RotatorFullStatus {
        RotatorFullStatus {
            position: self.position().ok(),
            mechanical_position: self.mechanical_position().ok(),
            is_moving: self.is_moving().ok(),
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

/// Full rotator status
#[derive(Debug, Clone, Default)]
pub struct RotatorFullStatus {
    pub position: Option<f64>,
    pub mechanical_position: Option<f64>,
    pub is_moving: Option<bool>,
}
