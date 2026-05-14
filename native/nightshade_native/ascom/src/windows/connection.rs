//! COM initialization, ASCOM device discovery, and the
//! `AscomDeviceConnection` core wrapper plus RAII cleanup guards.

use crate::AscomDevice;
use std::ptr;
use windows::{
    core::{GUID, PCWSTR, PWSTR},
    Win32::System::{
        Com::{
            CLSIDFromProgID, CoCreateInstance, CoInitializeEx, CoUninitialize, IDispatch,
            CLSCTX_ALL, COINIT_APARTMENTTHREADED, DISPATCH_METHOD, DISPATCH_PROPERTYGET,
            DISPATCH_PROPERTYPUT, DISPPARAMS, EXCEPINFO,
        },
        Registry::{
            RegCloseKey, RegEnumKeyExW, RegOpenKeyExW, RegQueryValueExW, HKEY, HKEY_LOCAL_MACHINE,
            KEY_READ, REG_SZ, REG_VALUE_TYPE,
        },
        Variant::VARIANT,
    },
};

use super::health::{ConnectionHealth, HealthMonitor};
use super::variant::{
    excepinfo_to_string, extract_safearray_string, variant_bool, variant_f64, variant_i32,
    variant_to_bool, variant_to_f64, variant_to_i32, variant_to_string, DISPID_PROPERTYPUT,
};

/// Initialize COM for the current thread
pub fn init_com() -> Result<(), String> {
    unsafe {
        CoInitializeEx(None, COINIT_APARTMENTTHREADED)
            .map_err(|e| format!("Failed to initialize COM: {}", e))
    }
}

/// Uninitialize COM for the current thread
pub fn uninit_com() {
    unsafe {
        CoUninitialize();
    }
}

/// Discover ASCOM devices by reading the Windows Registry
pub fn discover_devices(device_type: &str) -> Vec<AscomDevice> {
    let mut devices = Vec::new();

    let reg_path = format!("SOFTWARE\\ASCOM\\{} Drivers", device_type);
    tracing::debug!("Scanning ASCOM registry: {}", reg_path);

    if let Some(found) = scan_registry_path(&reg_path) {
        devices.extend(found);
    }

    // Also try WOW6432Node for 32-bit drivers on 64-bit Windows
    let reg_path_wow = format!("SOFTWARE\\WOW6432Node\\ASCOM\\{} Drivers", device_type);
    if let Some(found) = scan_registry_path(&reg_path_wow) {
        for dev in found {
            if !devices.iter().any(|d| d.prog_id == dev.prog_id) {
                devices.push(dev);
            }
        }
    }

    tracing::info!("Found {} ASCOM {} drivers", devices.len(), device_type);
    devices
}

fn scan_registry_path(reg_path: &str) -> Option<Vec<AscomDevice>> {
    let mut devices = Vec::new();

    unsafe {
        let mut key: HKEY = HKEY::default();
        let reg_path_wide: Vec<u16> = reg_path.encode_utf16().chain(std::iter::once(0)).collect();

        let result = RegOpenKeyExW(
            HKEY_LOCAL_MACHINE,
            PCWSTR::from_raw(reg_path_wide.as_ptr()),
            0,
            KEY_READ,
            &mut key,
        );

        if result.is_err() {
            return None;
        }

        let mut index: u32 = 0;
        let mut name_buffer: [u16; 256] = [0; 256];

        loop {
            let mut name_len = name_buffer.len() as u32;

            let result = RegEnumKeyExW(
                key,
                index,
                PWSTR(name_buffer.as_mut_ptr()),
                &mut name_len,
                None,
                PWSTR::null(),
                None,
                None,
            );

            if result.is_err() {
                break;
            }

            let prog_id = String::from_utf16_lossy(&name_buffer[..name_len as usize]);
            let registry_description = get_driver_description(&key, &prog_id).unwrap_or_default();

            if !prog_id.is_empty() {
                // NOTE: We intentionally do NOT probe the device here because:
                // 1. Some ASCOM drivers show setup dialogs when COM object is created
                // 2. Probing is slow (creates/destroys COM objects)
                // 3. We can probe later when user actually selects the device
                //
                // The probe_device_name() function is available for on-demand use
                // after user selects a device, if we need the real name.

                let name = if registry_description.is_empty() {
                    prog_id.clone()
                } else {
                    registry_description.clone()
                };

                tracing::debug!("Found ASCOM driver: {} - {}", prog_id, registry_description);

                devices.push(AscomDevice {
                    prog_id: prog_id.clone(),
                    name,
                    description: registry_description,
                });
            }

            index += 1;
        }

        let _ = RegCloseKey(key);
    }

    Some(devices)
}

unsafe fn get_driver_description(parent_key: &HKEY, prog_id: &str) -> Option<String> {
    let mut subkey: HKEY = HKEY::default();
    let prog_id_wide: Vec<u16> = prog_id.encode_utf16().chain(std::iter::once(0)).collect();

    let result = RegOpenKeyExW(
        *parent_key,
        PCWSTR::from_raw(prog_id_wide.as_ptr()),
        0,
        KEY_READ,
        &mut subkey,
    );

    if result.is_err() {
        return None;
    }

    let mut data_type: REG_VALUE_TYPE = REG_VALUE_TYPE(0);
    let mut data_buffer: [u8; 512] = [0; 512];
    let mut data_len = data_buffer.len() as u32;

    let result = RegQueryValueExW(
        subkey,
        PCWSTR::null(),
        None,
        Some(&mut data_type),
        Some(data_buffer.as_mut_ptr()),
        Some(&mut data_len),
    );

    let _ = RegCloseKey(subkey);

    if result.is_ok() && data_type == REG_SZ {
        let wide_slice: &[u16] = std::slice::from_raw_parts(
            data_buffer.as_ptr() as *const u16,
            (data_len as usize / 2).saturating_sub(1),
        );
        return Some(String::from_utf16_lossy(wide_slice));
    }

    None
}

/// Probe an ASCOM device to get its actual name without connecting
///
/// This instantiates the COM object and reads the Name property, which
/// according to ASCOM standards should be available without setting Connected=true.
/// This allows us to get the real device name (e.g., "ASI1600MM-Cool") instead of
/// the generic registry description (e.g., "ASI Camera (1)").
pub fn probe_device_name(prog_id: &str) -> Option<String> {
    tracing::debug!("Probing ASCOM device name for: {}", prog_id);

    // Try to create the COM object and read Name property
    match AscomDeviceConnection::new(prog_id) {
        Ok(device) => {
            // Read Name property - should work without connecting
            match device.get_string_property("Name") {
                Ok(name) if !name.is_empty() => {
                    tracing::debug!("Probed device name: {} -> {}", prog_id, name);
                    Some(name)
                }
                Ok(_) => {
                    // Empty name, try Description
                    match device.get_string_property("Description") {
                        Ok(desc) if !desc.is_empty() => {
                            tracing::debug!("Probed device description: {} -> {}", prog_id, desc);
                            Some(desc)
                        }
                        _ => None,
                    }
                }
                Err(e) => {
                    tracing::debug!("Failed to read Name property for {}: {}", prog_id, e);
                    // Try Description as fallback
                    device.get_string_property("Description").ok()
                }
            }
            // device is dropped here, releasing COM object
        }
        Err(e) => {
            tracing::debug!("Failed to create COM object for {}: {}", prog_id, e);
            None
        }
    }
}

/// ASCOM Device wrapper for COM interaction
///
/// This struct provides a safe wrapper around COM IDispatch for ASCOM devices.
/// It includes:
/// - Connection state tracking
/// - Health monitoring for detecting disconnected devices
/// - RAII cleanup via Drop trait
pub struct AscomDeviceConnection {
    // Why: device-specific wrappers (camera, switch, cover_calibrator) in
    // sibling modules need direct IDispatch access to invoke methods with
    // multi-argument SAFEARRAY-bearing signatures that the typed helpers
    // below do not cover. Visibility is scoped to `super` to keep the field
    // private to the `windows` module tree.
    pub(super) dispatch: IDispatch,
    connected: bool,
    /// Health monitor for tracking device responsiveness
    health: HealthMonitor,
    /// ProgID for logging/diagnostics
    prog_id: String,
}

impl AscomDeviceConnection {
    /// Create a new ASCOM device connection
    pub fn new(prog_id: &str) -> Result<Self, String> {
        unsafe {
            let prog_id_wide: Vec<u16> = prog_id.encode_utf16().chain(std::iter::once(0)).collect();

            let clsid = CLSIDFromProgID(PCWSTR::from_raw(prog_id_wide.as_ptr()))
                .map_err(|e| format!("Failed to get CLSID for {}: {}", prog_id, e))?;

            let dispatch: IDispatch = CoCreateInstance(&clsid, None, CLSCTX_ALL)
                .map_err(|e| format!("Failed to create COM object {}: {}", prog_id, e))?;

            tracing::info!("Created ASCOM COM object for: {}", prog_id);

            Ok(Self {
                dispatch,
                connected: false,
                health: HealthMonitor::default(),
                prog_id: prog_id.to_string(),
            })
        }
    }

    /// Get the connection health status
    pub fn get_health(&self) -> ConnectionHealth {
        self.health.get_health()
    }

    /// Check if the device is healthy (responding to commands)
    pub fn is_healthy(&self) -> bool {
        matches!(
            self.health.get_health(),
            ConnectionHealth::Healthy | ConnectionHealth::Unknown
        )
    }

    /// Perform a heartbeat check by reading the Connected property
    /// This should be called periodically to verify device is still responding
    pub fn heartbeat(&self) -> Result<(), String> {
        match self.get_bool_property("Connected") {
            Ok(_) => {
                self.health.record_success();
                Ok(())
            }
            Err(e) => {
                self.health.record_failure();
                Err(e)
            }
        }
    }

    pub fn connect(&mut self) -> Result<(), String> {
        self.health.reset(); // Reset health state on new connection
        self.set_bool_property("Connected", true)?;
        self.connected = true;
        self.health.record_success();
        tracing::info!("ASCOM device {} connected", self.prog_id);
        Ok(())
    }

    pub fn disconnect(&mut self) -> Result<(), String> {
        self.set_bool_property("Connected", false)?;
        self.connected = false;
        tracing::info!("ASCOM device {} disconnected", self.prog_id);
        Ok(())
    }

    pub fn is_connected(&self) -> Result<bool, String> {
        self.get_bool_property("Connected")
    }

    pub(super) fn get_dispid(&self, name: &str) -> Result<i32, String> {
        unsafe {
            let name_wide: Vec<u16> = name.encode_utf16().chain(std::iter::once(0)).collect();
            let names = [PCWSTR::from_raw(name_wide.as_ptr())];
            let mut dispid: i32 = 0;

            self.dispatch
                .GetIDsOfNames(&GUID::zeroed(), names.as_ptr(), 1, 0, &mut dispid)
                .map_err(|e| format!("Failed to get DISPID for {}: {}", name, e))?;

            Ok(dispid)
        }
    }

    pub fn get_string_property(&self, name: &str) -> Result<String, String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut result = VARIANT::default();
            let params = DISPPARAMS::default();

            self.dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_PROPERTYGET,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to get property {}: {}", name, e))?;

            variant_to_string(&result).ok_or_else(|| format!("Property {} is not a string", name))
        }
    }

    /// Get a string array property (for SupportedActions, etc.)
    pub fn get_string_array_property(&self, name: &str) -> Result<Vec<String>, String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut result = VARIANT::default();
            let params = DISPPARAMS::default();

            self.dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_PROPERTYGET,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to get property {}: {}", name, e))?;

            extract_safearray_string(&result)
                .map_err(|e| format!("Property {} is not a string array: {}", name, e))
        }
    }

    pub fn get_bool_property(&self, name: &str) -> Result<bool, String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut result = VARIANT::default();
            let params = DISPPARAMS::default();

            self.dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_PROPERTYGET,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to get property {}: {}", name, e))?;

            variant_to_bool(&result).ok_or_else(|| format!("Property {} is not a bool", name))
        }
    }

    pub fn set_bool_property(&self, name: &str, value: bool) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut arg = variant_bool(value);
            let mut dispid_named = DISPID_PROPERTYPUT;

            let params = DISPPARAMS {
                rgvarg: &mut arg,
                rgdispidNamedArgs: &mut dispid_named,
                cArgs: 1,
                cNamedArgs: 1,
            };

            self.dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_PROPERTYPUT,
                    &params,
                    None,
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to set property {}: {}", name, e))?;

            Ok(())
        }
    }

    pub fn get_double_property(&self, name: &str) -> Result<f64, String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut result = VARIANT::default();
            let params = DISPPARAMS::default();

            self.dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_PROPERTYGET,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to get property {}: {}", name, e))?;

            variant_to_f64(&result).ok_or_else(|| format!("Property {} is not a double", name))
        }
    }

    pub fn set_double_property(&self, name: &str, value: f64) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut arg = variant_f64(value);
            let mut dispid_named = DISPID_PROPERTYPUT;

            let params = DISPPARAMS {
                rgvarg: &mut arg,
                rgdispidNamedArgs: &mut dispid_named,
                cArgs: 1,
                cNamedArgs: 1,
            };

            self.dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_PROPERTYPUT,
                    &params,
                    None,
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to set property {}: {}", name, e))?;

            Ok(())
        }
    }

    pub fn get_int_property(&self, name: &str) -> Result<i32, String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut result = VARIANT::default();
            let params = DISPPARAMS::default();

            self.dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_PROPERTYGET,
                    &params,
                    Some(&mut result),
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to get property {}: {}", name, e))?;

            let vt = (*result.Anonymous.Anonymous).vt;
            tracing::debug!(
                "ASCOM get_int_property('{}') VARIANT type: {} (VT_I2=2, VT_I4=3, VT_R8=5)",
                name,
                vt.0
            );
            variant_to_i32(&result)
                .ok_or_else(|| format!("Property {} is not an int (VARIANT type={})", name, vt.0))
        }
    }

    pub fn set_int_property(&self, name: &str, value: i32) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut arg = variant_i32(value);
            let mut dispid_named = DISPID_PROPERTYPUT;

            let params = DISPPARAMS {
                rgvarg: &mut arg,
                rgdispidNamedArgs: &mut dispid_named,
                cArgs: 1,
                cNamedArgs: 1,
            };

            self.dispatch
                .Invoke(
                    dispid,
                    &GUID::zeroed(),
                    0,
                    DISPATCH_PROPERTYPUT,
                    &params,
                    None,
                    None,
                    None,
                )
                .map_err(|e| format!("Failed to set property {}: {}", name, e))?;

            Ok(())
        }
    }

    pub fn call_method(&self, name: &str) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let params = DISPPARAMS::default();

            // Capture exception info for better error messages
            let mut excep_info = EXCEPINFO::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                None,
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                // Check if we have exception info with a better message
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            Ok(())
        }
    }

    pub fn call_method_2_double(&self, name: &str, arg1: f64, arg2: f64) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;

            // Arguments are passed in reverse order
            let mut args = [variant_f64(arg2), variant_f64(arg1)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 2,
                cNamedArgs: 0,
            };

            // Capture exception info for better error messages
            let mut excep_info = EXCEPINFO::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                None,
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                // Check if we have exception info with a better message
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            Ok(())
        }
    }

    pub fn call_method_1_double(&self, name: &str, arg: f64) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut args = [variant_f64(arg)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            // Capture exception info for better error messages
            let mut excep_info = EXCEPINFO::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                None,
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            Ok(())
        }
    }

    pub fn call_method_1_int(&self, name: &str, arg: i32) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut args = [variant_i32(arg)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            // Capture exception info for better error messages
            let mut excep_info = EXCEPINFO::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                None,
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            Ok(())
        }
    }

    /// Call a method with one integer argument that returns a boolean
    /// Used for ASCOM methods like CanMoveAxis(TelescopeAxes) -> Boolean
    pub fn call_method_1_int_return_bool(&self, name: &str, arg: i32) -> Result<bool, String> {
        unsafe {
            let dispid = self.get_dispid(name)?;
            let mut args = [variant_i32(arg)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 1,
                cNamedArgs: 0,
            };

            // Capture exception info and result
            let mut excep_info = EXCEPINFO::default();
            let mut result_var = VARIANT::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                Some(&mut result_var),
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            // Extract boolean result
            variant_to_bool(&result_var)
                .ok_or_else(|| format!("Method {} did not return a boolean", name))
        }
    }

    pub fn call_method_2_int(&self, name: &str, arg1: i32, arg2: i32) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;

            // Arguments are passed in reverse order
            let mut args = [variant_i32(arg2), variant_i32(arg1)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 2,
                cNamedArgs: 0,
            };

            // Capture exception info for better error messages
            let mut excep_info = EXCEPINFO::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                None,
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            Ok(())
        }
    }

    pub fn call_method_2_double_bool(
        &self,
        name: &str,
        arg1: f64,
        arg2: bool,
    ) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;

            // Arguments are passed in reverse order
            let mut args = [variant_bool(arg2), variant_f64(arg1)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 2,
                cNamedArgs: 0,
            };

            // Capture exception info for better error messages
            let mut excep_info = EXCEPINFO::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                None,
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            Ok(())
        }
    }

    /// Call a method with an int and a double argument (e.g., MoveAxis)
    pub fn call_method_int_double(&self, name: &str, arg1: i32, arg2: f64) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;

            // Arguments are passed in reverse order
            let mut args = [variant_f64(arg2), variant_i32(arg1)];

            let params = DISPPARAMS {
                rgvarg: args.as_mut_ptr(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 2,
                cNamedArgs: 0,
            };

            // Capture exception info for better error messages
            let mut excep_info = EXCEPINFO::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                None,
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            Ok(())
        }
    }

    /// Call a parameterless method (e.g., SetupDialog) on the COM object
    pub fn call_method_0(&self, name: &str) -> Result<(), String> {
        unsafe {
            let dispid = self.get_dispid(name)?;

            let params = DISPPARAMS {
                rgvarg: ptr::null_mut(),
                rgdispidNamedArgs: ptr::null_mut(),
                cArgs: 0,
                cNamedArgs: 0,
            };

            // Capture exception info for better error messages
            let mut excep_info = EXCEPINFO::default();

            let result = self.dispatch.Invoke(
                dispid,
                &GUID::zeroed(),
                0,
                DISPATCH_METHOD,
                &params,
                None,
                Some(&mut excep_info),
                None,
            );

            if let Err(e) = result {
                let excep_msg = excepinfo_to_string(&excep_info);
                if excep_msg != "Unknown ASCOM error" {
                    return Err(format!("Failed to call method {}: {}", name, excep_msg));
                }
                return Err(format!("Failed to call method {}: {}", name, e));
            }

            Ok(())
        }
    }
}

impl Drop for AscomDeviceConnection {
    fn drop(&mut self) {
        // Why: COM apartment threading requires that property writes (including
        // `Connected = false`) execute on the same STA thread that called
        // `CoInitialize`. Drop runs on whichever thread happens to release the
        // last reference; that is not guaranteed to be the originating STA
        // thread, so issuing a `disconnect()` here can:
        //   - call into a stale apartment proxy (RPC_E_WRONG_THREAD), or
        //   - run after `uninit_com()` has torn down the apartment, or
        //   - race the wrapper-managed disconnect already in flight.
        //
        // Invariant: explicit `disconnect()` MUST be issued on the STA worker
        // thread (see `ascom_wrapper*.rs` worker loops). Drop simply marks the
        // connection as no-longer-tracked and lets COM reference counting
        // release the IDispatch (the IDispatch::Release call IS allowed from
        // any thread per COM rules — only typed method/property calls require
        // the STA).
        if self.connected {
            tracing::warn!(
                "AscomDeviceConnection::drop on {} while still flagged connected — \
                 explicit disconnect was skipped. Wrapper STA worker thread is \
                 expected to issue disconnect before drop.",
                self.prog_id
            );
            self.connected = false;
        }
        tracing::debug!("AscomDeviceConnection::drop - released {}", self.prog_id);
    }
}

// SAFETY: COM objects are apartment-threaded and we manage thread affinity
// ourselves. All COM property/method calls MUST happen from the thread that
// called `CoInitialize` (the STA worker thread). The wrapper-thread pattern
// used in `ascom_wrapper*.rs` enforces this — `Send`/`Sync` here only allows
// the typed wrapper struct (e.g. `AscomCamera`) to be moved into the worker
// thread once at construction; from then on every COM call is dispatched onto
// that worker via mpsc, and `Drop` is a no-op so it is safe to be released on
// any thread.
unsafe impl Send for AscomDeviceConnection {}
unsafe impl Sync for AscomDeviceConnection {}

// ============================================================================
// ASCOM Operation Guard
// ============================================================================

/// RAII guard that ensures ASCOM device cleanup when operations fail.
///
/// This guard calls disconnect on the device if dropped without being defused.
/// Use this for multi-step operations where you need to ensure cleanup even
/// if an intermediate step fails.
///
/// # Example
/// ```ignore
/// let mut mount = AscomMount::new(&prog_id)?;
/// mount.connect()?;
///
/// // Create guard - will disconnect on drop if not defused
/// let guard = AscomOperationGuard::new(&mut mount as &mut dyn AscomDisconnectable, "slew");
///
/// // Perform operations
/// mount.slew_to_coordinates(ra, dec)?;
///
/// // Operation succeeded - defuse the guard
/// guard.defuse();
/// mount.disconnect()?;
/// ```
pub struct AscomOperationGuard<'a> {
    device: Option<&'a mut dyn AscomDisconnectable>,
    operation: String,
}

/// Trait for ASCOM devices that can be disconnected
pub trait AscomDisconnectable {
    /// Disconnect from the device (best-effort cleanup)
    fn try_disconnect(&mut self) -> Result<(), String>;
}

impl AscomDisconnectable for AscomDeviceConnection {
    fn try_disconnect(&mut self) -> Result<(), String> {
        self.disconnect()
    }
}

impl<'a> AscomOperationGuard<'a> {
    /// Create a new operation guard for the given device.
    pub fn new(device: &'a mut dyn AscomDisconnectable, operation: impl Into<String>) -> Self {
        Self {
            device: Some(device),
            operation: operation.into(),
        }
    }

    /// Defuse the guard, preventing automatic cleanup on drop.
    /// Call this when the operation succeeds.
    pub fn defuse(mut self) {
        self.device = None;
    }
}

impl<'a> Drop for AscomOperationGuard<'a> {
    fn drop(&mut self) {
        if let Some(device) = self.device.take() {
            tracing::warn!(
                "AscomOperationGuard: operation '{}' did not complete - disconnecting",
                self.operation
            );
            if let Err(e) = device.try_disconnect() {
                tracing::error!(
                    "AscomOperationGuard: failed to disconnect after failed '{}': {}",
                    self.operation,
                    e
                );
            }
        }
    }
}

/// Synchronous cleanup guard for use in ASCOM connect sequences.
///
/// This guard runs a cleanup closure if dropped without being defused.
/// Useful for cleaning up partially-initialized state when connect fails.
///
/// # Example
/// ```ignore
/// // Open device
/// let device = AscomDeviceConnection::new(&prog_id)?;
///
/// // Create guard that will disconnect if subsequent operations fail
/// let guard = AscomCleanupGuard::new(|| {
///     let _ = device.disconnect();
/// });
///
/// // Do more initialization
/// device.connect()?;
/// device.setup_something()?;
///
/// // Success - defuse the guard
/// guard.defuse();
/// ```
pub struct AscomCleanupGuard<F: FnOnce()> {
    cleanup: Option<F>,
}

impl<F: FnOnce()> AscomCleanupGuard<F> {
    /// Create a new cleanup guard with the given cleanup function.
    pub fn new(cleanup: F) -> Self {
        Self {
            cleanup: Some(cleanup),
        }
    }

    /// Defuse the guard, preventing the cleanup function from running.
    pub fn defuse(mut self) {
        self.cleanup = None;
    }
}

impl<F: FnOnce()> Drop for AscomCleanupGuard<F> {
    fn drop(&mut self) {
        if let Some(cleanup) = self.cleanup.take() {
            cleanup();
        }
    }
}
