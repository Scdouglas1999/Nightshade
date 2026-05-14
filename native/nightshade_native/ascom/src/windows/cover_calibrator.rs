//! ASCOM Cover Calibrator wrapper and batch status types.

use std::ptr;
use windows::{
    core::GUID,
    Win32::System::Com::{DISPATCH_METHOD, DISPPARAMS},
};

use super::connection::AscomDeviceConnection;
use super::health::ConnectionHealth;
use super::variant::variant_i32;

/// ASCOM Cover Calibrator
pub struct AscomCoverCalibrator {
    device: AscomDeviceConnection,
}

impl AscomCoverCalibrator {
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

    pub fn cover_state(&self) -> Result<i32, String> {
        self.device.get_int_property("CoverState")
    }

    pub fn calibrator_state(&self) -> Result<i32, String> {
        self.device.get_int_property("CalibratorState")
    }

    pub fn brightness(&self) -> Result<i32, String> {
        self.device.get_int_property("Brightness")
    }

    pub fn set_brightness(&mut self, brightness: i32) -> Result<(), String> {
        self.device.set_int_property("Brightness", brightness)
    }

    pub fn max_brightness(&self) -> Result<i32, String> {
        self.device.get_int_property("MaxBrightness")
    }

    pub fn open_cover(&mut self) -> Result<(), String> {
        self.device.call_method("OpenCover")
    }

    pub fn close_cover(&mut self) -> Result<(), String> {
        self.device.call_method("CloseCover")
    }

    pub fn halt_cover(&mut self) -> Result<(), String> {
        self.device.call_method("HaltCover")
    }

    pub fn calibrator_on(&mut self, brightness: i32) -> Result<(), String> {
        unsafe {
            let dispid = self.device.get_dispid("CalibratorOn")?;
            let mut args = [variant_i32(brightness)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            self.device
                .dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_METHOD,
                    &params,
                    None,
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to call CalibratorOn: {}", e))?;

            Ok(())
        }
    }

    pub fn calibrator_off(&mut self) -> Result<(), String> {
        self.device.call_method("CalibratorOff")
    }

    // ========================================================================
    // Batch Property Queries
    // ========================================================================

    /// Get complete cover calibrator status in a single batch operation
    pub fn get_full_status(&self) -> CoverCalibratorFullStatus {
        CoverCalibratorFullStatus {
            cover_state: self.cover_state().ok(),
            calibrator_state: self.calibrator_state().ok(),
            brightness: self.brightness().ok(),
            max_brightness: self.max_brightness().ok(),
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

/// Full cover calibrator status
#[derive(Debug, Clone, Default)]
pub struct CoverCalibratorFullStatus {
    /// Cover state (0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error)
    pub cover_state: Option<i32>,
    /// Calibrator state (0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error)
    pub calibrator_state: Option<i32>,
    pub brightness: Option<i32>,
    pub max_brightness: Option<i32>,
}
