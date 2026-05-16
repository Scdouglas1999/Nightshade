//! ASCOM Switch wrapper and batch status types.

use std::ptr;
use windows::{
    core::GUID,
    Win32::System::Com::{DISPATCH_METHOD, DISPPARAMS},
    Win32::System::Variant::VARIANT,
};

use super::connection::AscomDeviceConnection;
use super::health::ConnectionHealth;
use super::variant::{
    variant_bool, variant_f64, variant_i32, variant_to_bool, variant_to_f64, variant_to_string,
};

/// ASCOM Switch
pub struct AscomSwitch {
    device: AscomDeviceConnection,
}

impl AscomSwitch {
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

    pub fn max_switch(&self) -> Result<i32, String> {
        self.device.get_int_property("MaxSwitch")
    }

    pub fn get_switch(&self, id: i32) -> Result<bool, String> {
        // SAFETY: DISPATCH_METHOD with one VT_I4 positional arg and a result VARIANT —
        // `args` is a 1-element stack array matching `cArgs = 1`, no named args.
        // `result` is a stack VARIANT out-pointer. `variant_to_bool` reads it under its
        // own `vt`-guarded match. Caller invariant: STA worker thread.
        unsafe {
            let dispid = self.device.get_dispid("GetSwitch")?;
            let mut args = [variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            let mut result = VARIANT::default();
            self.device
                .dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_METHOD,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to call GetSwitch: {}", e))?;

            variant_to_bool(&result).ok_or_else(|| "GetSwitch did not return a bool".to_string())
        }
    }

    pub fn set_switch(&mut self, id: i32, state: bool) -> Result<(), String> {
        // SAFETY: DISPATCH_METHOD with two positional args (VT_BOOL then VT_I4) —
        // `cArgs = 2` matches the 2-element stack array, no named args. All pointers
        // outlive the FFI call. Caller invariant: STA worker thread.
        unsafe {
            let dispid = self.device.get_dispid("SetSwitch")?;
            let mut args = [variant_bool(state), variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 2,
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
                .map_err(|e| format!("Failed to call SetSwitch: {}", e))?;

            Ok(())
        }
    }

    pub fn get_switch_name(&self, id: i32) -> Result<String, String> {
        // SAFETY: DISPATCH_METHOD with one VT_I4 positional arg and a result VARIANT —
        // same shape as `get_switch`. `variant_to_string` reads the result under its
        // own `vt == VT_BSTR` guard.
        unsafe {
            let dispid = self.device.get_dispid("GetSwitchName")?;
            let mut args = [variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            let mut result = VARIANT::default();
            self.device
                .dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_METHOD,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to call GetSwitchName: {}", e))?;

            variant_to_string(&result)
                .ok_or_else(|| "GetSwitchName did not return a string".to_string())
        }
    }

    pub fn get_switch_description(&self, id: i32) -> Result<String, String> {
        // SAFETY: Same single-VT_I4-arg-with-string-result shape as `get_switch_name`;
        // `cArgs = 1` matches the 1-element stack args array; result VARIANT is read
        // through `variant_to_string`'s VT_BSTR-guarded path.
        unsafe {
            let dispid = self.device.get_dispid("GetSwitchDescription")?;
            let mut args = [variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            let mut result = VARIANT::default();
            self.device
                .dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_METHOD,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to call GetSwitchDescription: {}", e))?;

            variant_to_string(&result)
                .ok_or_else(|| "GetSwitchDescription did not return a string".to_string())
        }
    }

    pub fn get_switch_value(&self, id: i32) -> Result<f64, String> {
        // SAFETY: Same single-VT_I4-arg pattern; result VARIANT is consumed by
        // `variant_to_f64` whose match handles each numeric `vt` tag. Pointers point
        // at stack locals; STA invariant enforced by worker-thread wrapper.
        unsafe {
            let dispid = self.device.get_dispid("GetSwitchValue")?;
            let mut args = [variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            let mut result = VARIANT::default();
            self.device
                .dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_METHOD,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to call GetSwitchValue: {}", e))?;

            variant_to_f64(&result)
                .ok_or_else(|| "GetSwitchValue did not return a number".to_string())
        }
    }

    pub fn set_switch_value(&mut self, id: i32, value: f64) -> Result<(), String> {
        // SAFETY: DISPATCH_METHOD with two positional args (VT_R8 then VT_I4) —
        // `cArgs = 2` matches the 2-element stack array; no named args; no result var.
        // Caller invariant: STA worker thread.
        unsafe {
            let dispid = self.device.get_dispid("SetSwitchValue")?;
            let mut args = [variant_f64(value), variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 2,
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
                .map_err(|e| format!("Failed to call SetSwitchValue: {}", e))?;

            Ok(())
        }
    }

    pub fn min_switch_value(&self, id: i32) -> Result<f64, String> {
        // SAFETY: Single-VT_I4-arg with result VARIANT — same shape as `get_switch_value`.
        unsafe {
            let dispid = self.device.get_dispid("MinSwitchValue")?;
            let mut args = [variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            let mut result = VARIANT::default();
            self.device
                .dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_METHOD,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to call MinSwitchValue: {}", e))?;

            variant_to_f64(&result)
                .ok_or_else(|| "MinSwitchValue did not return a number".to_string())
        }
    }

    pub fn max_switch_value(&self, id: i32) -> Result<f64, String> {
        // SAFETY: Single-VT_I4-arg with result VARIANT — same shape as `get_switch_value`.
        unsafe {
            let dispid = self.device.get_dispid("MaxSwitchValue")?;
            let mut args = [variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            let mut result = VARIANT::default();
            self.device
                .dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_METHOD,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to call MaxSwitchValue: {}", e))?;

            variant_to_f64(&result)
                .ok_or_else(|| "MaxSwitchValue did not return a number".to_string())
        }
    }

    pub fn can_write(&self, id: i32) -> Result<bool, String> {
        // SAFETY: Single-VT_I4-arg with result VARIANT consumed by `variant_to_bool` —
        // same shape as `get_switch`.
        unsafe {
            let dispid = self.device.get_dispid("CanWrite")?;
            let mut args = [variant_i32(id)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            let mut result = VARIANT::default();
            self.device
                .dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_METHOD,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to call CanWrite: {}", e))?;

            variant_to_bool(&result).ok_or_else(|| "CanWrite did not return a bool".to_string())
        }
    }

    // ========================================================================
    // Batch Property Queries
    // ========================================================================

    /// Get all switch states in a single batch operation
    /// Returns states for switches 0 through max_switch-1
    pub fn get_all_switch_states(&self) -> SwitchFullStatus {
        let max_switch = self.max_switch().ok();
        let mut states = Vec::new();

        if let Some(max) = max_switch {
            for i in 0..max {
                states.push(self.get_switch(i).ok());
            }
        }

        SwitchFullStatus { max_switch, states }
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

/// Full switch status
#[derive(Debug, Clone, Default)]
pub struct SwitchFullStatus {
    pub max_switch: Option<i32>,
    pub states: Vec<Option<bool>>,
}
