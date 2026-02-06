//! Touptek/OGMA Camera Native Driver
//!
//! Provides FFI bindings to the Touptek OGMA SDK (ogmacam.dll).
//! This SDK is used by many camera brands including:
//! - Touptek
//! - Altair Astro
//! - OGMA
//! - Mallincam
//! - And many other white-label brands

use crate::camera::{
    CameraCapabilities, CameraState, CameraStatus, ExposureParams, ImageData, ImageMetadata,
    ReadoutMode, SensorInfo, SubFrame, VendorFeatures,
};
use crate::sync::touptek_mutex;
use crate::traits::{NativeCamera, NativeDevice, NativeError};
use crate::NativeVendor;
use async_trait::async_trait;
use libloading::Library;
use std::collections::HashMap;
use std::ffi::{c_char, c_int, c_uint, c_void, CStr};
use std::sync::{Mutex, OnceLock};

// ============================================================================
// SDK Types and Constants
// ============================================================================

/// Opaque handle to a camera
type HOgmacam = *mut c_void;

/// Maximum number of cameras supported
const OGMACAM_MAX: usize = 128;

// Camera flags
const OGMACAM_FLAG_MONO: u64 = 0x00000010;
const OGMACAM_FLAG_TEC: u64 = 0x00000080;
const OGMACAM_FLAG_TEC_ONOFF: u64 = 0x00020000;
const OGMACAM_FLAG_ST4: u64 = 0x00000200;
const OGMACAM_FLAG_ROI_HARDWARE: u64 = 0x00000008;
const OGMACAM_FLAG_BINSKIP_SUPPORTED: u64 = 0x00000020;

// Options
const OGMACAM_OPTION_TEC: c_uint = 0x08;
const OGMACAM_OPTION_BITDEPTH: c_uint = 0x04;
const OGMACAM_OPTION_BINNING: c_uint = 0x01;
const OGMACAM_OPTION_RAW: c_uint = 0x04;

/// Camera model information
#[repr(C)]
#[derive(Debug, Clone)]
pub struct OgmacamModelV2 {
    pub name: *const c_char,
    pub flag: u64,
    pub maxspeed: c_uint,
    pub preview: c_uint,
    pub still: c_uint,
    pub maxfanspeed: c_uint,
    pub ioctrol: c_uint,
    pub xpixsz: f32,
    pub ypixsz: f32,
    pub res: [OgmacamResolution; 16],
}

/// Resolution info
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct OgmacamResolution {
    pub width: c_uint,
    pub height: c_uint,
}

/// Device info for enumeration (Windows version with wide strings)
#[repr(C)]
pub struct OgmacamDeviceV2 {
    pub displayname: [u16; 64],
    pub id: [u16; 64],
    pub model: *const OgmacamModelV2,
}

impl Clone for OgmacamDeviceV2 {
    fn clone(&self) -> Self {
        Self {
            displayname: self.displayname,
            id: self.id,
            model: self.model, // Copy the pointer
        }
    }
}

/// Frame info structure
#[repr(C)]
#[derive(Debug, Clone, Default)]
pub struct OgmacamFrameInfoV3 {
    pub width: c_uint,
    pub height: c_uint,
    pub flag: c_uint,
    pub seq: c_uint,
    pub timestamp: u64,
    pub shutterseq: c_uint,
    pub expotime: c_uint,
    pub expogain: u16,
    pub blacklevel: u16,
}

// ============================================================================
// SDK Function Types
// ============================================================================

type OgmacamEnumV2 = unsafe extern "system" fn(arr: *mut OgmacamDeviceV2) -> c_uint;
type OgmacamOpenByIndex = unsafe extern "system" fn(index: c_uint) -> HOgmacam;
type OgmacamClose = unsafe extern "system" fn(h: HOgmacam);
type OgmacamStop = unsafe extern "system" fn(h: HOgmacam) -> i32;

// Frame pulling
type OgmacamPullImageV3 = unsafe extern "system" fn(
    h: HOgmacam,
    p_image_data: *mut c_void,
    b_still: c_int,
    bits: c_int,
    row_pitch: c_int,
    p_info: *mut OgmacamFrameInfoV3,
) -> i32;

// Exposure
type OgmacamPutExpoTime = unsafe extern "system" fn(h: HOgmacam, time: c_uint) -> i32;

// Gain
type OgmacamPutExpoAGain = unsafe extern "system" fn(h: HOgmacam, gain: u16) -> i32;
type OgmacamGetExpoAGainRange = unsafe extern "system" fn(
    h: HOgmacam,
    n_min: *mut u16,
    n_max: *mut u16,
    n_def: *mut u16,
) -> i32;

// Temperature
type OgmacamGetTemperature = unsafe extern "system" fn(h: HOgmacam, temp: *mut i16) -> i32;
type OgmacamPutTemperature = unsafe extern "system" fn(h: HOgmacam, temp: i16) -> i32;

// Options
type OgmacamPutOption = unsafe extern "system" fn(h: HOgmacam, opt: c_uint, val: c_int) -> i32;

// Resolution/ROI
type OgmacamGetSize = unsafe extern "system" fn(h: HOgmacam, w: *mut c_int, h_: *mut c_int) -> i32;
type OgmacamPutRoi = unsafe extern "system" fn(
    h: HOgmacam,
    x_offset: c_uint,
    y_offset: c_uint,
    x_width: c_uint,
    y_height: c_uint,
) -> i32;

// Serial number and info
type OgmacamGetSerialNumber = unsafe extern "system" fn(h: HOgmacam, sn: *mut c_char) -> i32;

// Snap (still image capture)
type OgmacamSnap = unsafe extern "system" fn(h: HOgmacam, n_resolution_index: c_uint) -> i32;

// ============================================================================
// SDK Wrapper
// ============================================================================

struct TouptekSdk {
    _library: Library,
    enum_v2: OgmacamEnumV2,
    open_by_index: OgmacamOpenByIndex,
    close: OgmacamClose,
    stop: OgmacamStop,
    pull_image_v3: OgmacamPullImageV3,
    put_expo_time: OgmacamPutExpoTime,
    put_expo_again: OgmacamPutExpoAGain,
    get_expo_again_range: OgmacamGetExpoAGainRange,
    get_temperature: OgmacamGetTemperature,
    put_temperature: OgmacamPutTemperature,
    put_option: OgmacamPutOption,
    get_size: OgmacamGetSize,
    put_roi: OgmacamPutRoi,
    get_serial_number: OgmacamGetSerialNumber,
    snap: OgmacamSnap,
}

unsafe impl Send for TouptekSdk {}
unsafe impl Sync for TouptekSdk {}

/// Supported Touptek white-label brands and their SDK details.
/// Each entry: (DLL name, function prefix, brand display name)
#[cfg(windows)]
const TOUPTEK_BRANDS: &[(&str, &str, &str)] = &[
    ("ogmacam.dll", "Ogmacam", "OGMA"),
    ("toupcam.dll", "Toupcam", "Touptek"),
    ("altaircam.dll", "Altaircam", "Altair"),
    ("mallincam.dll", "Mallincam", "Mallincam"),
];

#[cfg(target_os = "linux")]
const TOUPTEK_BRANDS: &[(&str, &str, &str)] = &[
    ("libogmacam.so", "Ogmacam", "OGMA"),
    ("libtoupcam.so", "Toupcam", "Touptek"),
    ("libaltaircam.so", "Altaircam", "Altair"),
    ("libmallincam.so", "Mallincam", "Mallincam"),
];

#[cfg(target_os = "macos")]
const TOUPTEK_BRANDS: &[(&str, &str, &str)] = &[
    ("libogmacam.dylib", "Ogmacam", "OGMA"),
    ("libtoupcam.dylib", "Toupcam", "Touptek"),
    ("libaltaircam.dylib", "Altaircam", "Altair"),
    ("libmallincam.dylib", "Mallincam", "Mallincam"),
];

impl TouptekSdk {
    fn load(dll_name: &str, func_prefix: &str) -> Result<Self, NativeError> {
        let library = unsafe { Library::new(dll_name) }
            .map_err(|e| NativeError::SdkError(format!("Failed to load {}: {}", dll_name, e)))?;

        // Build symbol names dynamically from the function prefix
        let sym = |suffix: &str| -> Vec<u8> {
            let mut name = format!("{}_{}", func_prefix, suffix);
            name.push('\0');
            name.into_bytes()
        };

        unsafe {
            Ok(Self {
                enum_v2: *library.get::<OgmacamEnumV2>(&sym("EnumV2")).map_err(|e| {
                    NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                })?,
                open_by_index: *library
                    .get::<OgmacamOpenByIndex>(&sym("OpenByIndex"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                close: *library.get::<OgmacamClose>(&sym("Close")).map_err(|e| {
                    NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                })?,
                stop: *library.get::<OgmacamStop>(&sym("Stop")).map_err(|e| {
                    NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                })?,
                pull_image_v3: *library
                    .get::<OgmacamPullImageV3>(&sym("PullImageV3"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                put_expo_time: *library
                    .get::<OgmacamPutExpoTime>(&sym("put_ExpoTime"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                put_expo_again: *library
                    .get::<OgmacamPutExpoAGain>(&sym("put_ExpoAGain"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                get_expo_again_range: *library
                    .get::<OgmacamGetExpoAGainRange>(&sym("get_ExpoAGainRange"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                get_temperature: *library
                    .get::<OgmacamGetTemperature>(&sym("get_Temperature"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                put_temperature: *library
                    .get::<OgmacamPutTemperature>(&sym("put_Temperature"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                put_option: *library
                    .get::<OgmacamPutOption>(&sym("put_Option"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                get_size: *library
                    .get::<OgmacamGetSize>(&sym("get_Size"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                put_roi: *library.get::<OgmacamPutRoi>(&sym("put_Roi")).map_err(|e| {
                    NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                })?,
                get_serial_number: *library
                    .get::<OgmacamGetSerialNumber>(&sym("get_SerialNumber"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                snap: *library.get::<OgmacamSnap>(&sym("Snap")).map_err(|e| {
                    NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                })?,
                _library: library,
            })
        }
    }
}

/// Multi-brand SDK storage. Each brand's SDK is loaded lazily on first use.
static SDKS: OnceLock<Mutex<HashMap<String, Result<TouptekSdk, String>>>> = OnceLock::new();

fn get_sdks() -> &'static Mutex<HashMap<String, Result<TouptekSdk, String>>> {
    SDKS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn get_sdk_for_brand(brand: &str) -> Result<(), NativeError> {
    let sdks = get_sdks();
    let mut map = sdks.lock().unwrap();
    if map.contains_key(brand) {
        return map
            .get(brand)
            .unwrap()
            .as_ref()
            .map(|_| ())
            .map_err(|e| NativeError::SdkError(e.clone()));
    }

    // Find the brand's DLL info
    let brand_info = TOUPTEK_BRANDS
        .iter()
        .find(|(_, _, name)| name.eq_ignore_ascii_case(brand))
        .ok_or_else(|| NativeError::SdkError(format!("Unknown Touptek brand: {}", brand)))?;

    match TouptekSdk::load(brand_info.0, brand_info.1) {
        Ok(sdk) => {
            map.insert(brand.to_string(), Ok(sdk));
            Ok(())
        }
        Err(e) => {
            let msg = e.to_string();
            map.insert(brand.to_string(), Err(msg.clone()));
            Err(NativeError::SdkError(msg))
        }
    }
}

fn with_sdk<F, R>(brand: &str, f: F) -> Result<R, NativeError>
where
    F: FnOnce(&TouptekSdk) -> Result<R, NativeError>,
{
    get_sdk_for_brand(brand)?;
    let sdks = get_sdks();
    let map = sdks.lock().unwrap();
    let sdk = map
        .get(brand)
        .unwrap()
        .as_ref()
        .map_err(|e| NativeError::SdkError(e.clone()))?;
    f(sdk)
}

// ============================================================================
// Discovery
// ============================================================================

/// Information about a discovered Touptek camera
#[derive(Debug, Clone)]
pub struct TouptekDeviceInfo {
    pub camera_id: String,
    pub name: String,
    pub serial_number: Option<String>,
    pub discovery_index: usize,
    pub model_flags: u64,
    pub width: u32,
    pub height: u32,
    pub pixel_size_x: f32,
    pub pixel_size_y: f32,
    /// Which brand SDK this camera was discovered through
    pub brand: String,
}

/// Discover connected Touptek cameras across all supported brands
///
/// Iterates over all known Touptek white-label SDKs, attempts to load each,
/// and enumerates cameras from each successfully loaded SDK.
pub async fn discover_devices() -> Result<Vec<TouptekDeviceInfo>, NativeError> {
    // Acquire global SDK mutex for thread safety
    let _lock = touptek_mutex().lock().await;

    let mut devices = Vec::new();

    for &(dll_name, _func_prefix, brand_name) in TOUPTEK_BRANDS {
        // Try to load this brand's SDK -- skip silently if DLL not present
        if get_sdk_for_brand(brand_name).is_err() {
            tracing::debug!(
                "Touptek brand SDK '{}' ({}) not available, skipping",
                brand_name,
                dll_name
            );
            continue;
        }

        let brand_devices = with_sdk(brand_name, |sdk| {
            let mut brand_devs = Vec::new();

            let mut arr: Vec<OgmacamDeviceV2> = vec![unsafe { std::mem::zeroed() }; OGMACAM_MAX];
            let count = unsafe { (sdk.enum_v2)(arr.as_mut_ptr()) };

            for i in 0..count as usize {
                let dev = &arr[i];

                // Convert wide string display name to String
                let name = String::from_utf16_lossy(
                    &dev.displayname[..dev.displayname.iter().position(|&c| c == 0).unwrap_or(64)],
                );

                // Convert wide string ID to String
                let id = String::from_utf16_lossy(
                    &dev.id[..dev.id.iter().position(|&c| c == 0).unwrap_or(64)],
                );

                // Get model info
                let (flags, width, height, pixel_x, pixel_y) = if !dev.model.is_null() {
                    let model = unsafe { &*dev.model };
                    let res = model.res[0]; // Primary resolution
                    (
                        model.flag,
                        res.width,
                        res.height,
                        model.xpixsz,
                        model.ypixsz,
                    )
                } else {
                    (0, 0, 0, 0.0, 0.0)
                };

                brand_devs.push(TouptekDeviceInfo {
                    camera_id: id,
                    name,
                    serial_number: None, // Will be populated on connect
                    discovery_index: i,
                    model_flags: flags,
                    width,
                    height,
                    pixel_size_x: pixel_x,
                    pixel_size_y: pixel_y,
                    brand: brand_name.to_string(),
                });
            }

            Ok(brand_devs)
        })?;

        if !brand_devices.is_empty() {
            tracing::info!("Found {} {} cameras", brand_devices.len(), brand_name);
        }
        devices.extend(brand_devices);
    }

    Ok(devices)
}

/// Discover connected Touptek cameras for a specific brand only
pub async fn discover_devices_for_brand(
    brand: &str,
) -> Result<Vec<TouptekDeviceInfo>, NativeError> {
    let _lock = touptek_mutex().lock().await;

    get_sdk_for_brand(brand)?;

    with_sdk(brand, |sdk| {
        let mut devices = Vec::new();
        let mut arr: Vec<OgmacamDeviceV2> = vec![unsafe { std::mem::zeroed() }; OGMACAM_MAX];
        let count = unsafe { (sdk.enum_v2)(arr.as_mut_ptr()) };

        for i in 0..count as usize {
            let dev = &arr[i];
            let name = String::from_utf16_lossy(
                &dev.displayname[..dev.displayname.iter().position(|&c| c == 0).unwrap_or(64)],
            );
            let id = String::from_utf16_lossy(
                &dev.id[..dev.id.iter().position(|&c| c == 0).unwrap_or(64)],
            );
            let (flags, width, height, pixel_x, pixel_y) = if !dev.model.is_null() {
                let model = unsafe { &*dev.model };
                let res = model.res[0];
                (
                    model.flag,
                    res.width,
                    res.height,
                    model.xpixsz,
                    model.ypixsz,
                )
            } else {
                (0, 0, 0, 0.0, 0.0)
            };

            devices.push(TouptekDeviceInfo {
                camera_id: id,
                name,
                serial_number: None,
                discovery_index: i,
                model_flags: flags,
                width,
                height,
                pixel_size_x: pixel_x,
                pixel_size_y: pixel_y,
                brand: brand.to_string(),
            });
        }

        Ok(devices)
    })
}

// ============================================================================
// Handle Wrapper for Thread Safety
// ============================================================================

struct HandleWrapper(HOgmacam);
unsafe impl Send for HandleWrapper {}
unsafe impl Sync for HandleWrapper {}

// ============================================================================
// Camera Implementation
// ============================================================================

/// Touptek camera instance
pub struct TouptekCamera {
    device_index: usize,
    device_id: String,
    name: String,
    handle: Mutex<HandleWrapper>,
    connected: bool,
    capabilities: CameraCapabilities,
    sensor_info: SensorInfo,
    state: CameraState,
    current_gain: i32,
    current_offset: i32,
    current_bin_x: i32,
    current_bin_y: i32,
    subframe: Option<SubFrame>,
    cooler_on: bool,
    target_temp: f64,
    exposure_duration: f64,
    model_flags: u64,
    /// Which brand SDK this camera uses
    brand: String,
}

impl std::fmt::Debug for TouptekCamera {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TouptekCamera")
            .field("name", &self.name)
            .field("device_index", &self.device_index)
            .finish()
    }
}

impl TouptekCamera {
    /// Create a new Touptek camera instance for a specific brand
    pub fn new(device_index: usize, brand: &str) -> Self {
        Self {
            device_index,
            device_id: format!("touptek_{}", device_index),
            name: format!("{} Camera {}", brand, device_index),
            handle: Mutex::new(HandleWrapper(std::ptr::null_mut())),
            connected: false,
            capabilities: CameraCapabilities::default(),
            sensor_info: SensorInfo::default(),
            state: CameraState::Idle,
            current_gain: 100,
            current_offset: 0,
            current_bin_x: 1,
            current_bin_y: 1,
            subframe: None,
            cooler_on: false,
            target_temp: -10.0,
            exposure_duration: 0.0,
            model_flags: 0,
            brand: brand.to_string(),
        }
    }

    /// Create a new Touptek camera instance with the default OGMA brand
    /// (backward-compatible constructor)
    pub fn new_default(device_index: usize) -> Self {
        Self::new(device_index, "OGMA")
    }
}

#[async_trait]
impl NativeDevice for TouptekCamera {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Other("Touptek".to_string())
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        if self.connected {
            return Ok(());
        }

        // Ensure the brand's SDK is loaded
        get_sdk_for_brand(&self.brand)?;

        let brand = self.brand.clone();

        // First phase: Open camera and get basic info (needs mutex)
        {
            // Acquire global SDK mutex for thread safety
            let _lock = touptek_mutex().lock().await;

            let device_index = self.device_index;
            let handle = with_sdk(&brand, |sdk| {
                let h = unsafe { (sdk.open_by_index)(device_index as c_uint) };
                if h.is_null() {
                    tracing::error!(
                        "Touptek ({}) OpenByIndex() returned NULL for index {}. Check USB connection and driver installation.",
                        brand, device_index
                    );
                    return Err(NativeError::SdkError(format!(
                        "Failed to open {} camera at index {} - SDK returned NULL. Ensure camera is connected and {} driver is installed.",
                        brand, device_index, brand
                    )));
                }
                Ok(h)
            })?;

            // Store handle
            {
                let mut h = self.handle.lock().unwrap();
                *h = HandleWrapper(handle);
            }

            // Get serial number, resolution, and gain range (all synchronous)
            {
                let handle_val = self.handle.lock().unwrap().0;

                with_sdk(&brand, |sdk| {
                    let mut sn_buf = [0i8; 64];
                    if unsafe { (sdk.get_serial_number)(handle_val, sn_buf.as_mut_ptr()) } >= 0 {
                        let sn = unsafe { CStr::from_ptr(sn_buf.as_ptr()) }
                            .to_string_lossy()
                            .to_string();
                        if !sn.is_empty() {
                            self.name = format!("{} ({})", self.name, sn);
                        }
                    }

                    let mut width: c_int = 0;
                    let mut height: c_int = 0;
                    let _ = unsafe { (sdk.get_size)(handle_val, &mut width, &mut height) };

                    let mut gain_min: u16 = 100;
                    let mut gain_max: u16 = 10000;
                    let mut gain_def: u16 = 100;
                    let _ = unsafe {
                        (sdk.get_expo_again_range)(
                            handle_val,
                            &mut gain_min,
                            &mut gain_max,
                            &mut gain_def,
                        )
                    };
                    self.current_gain = gain_def as i32;
                    Ok(())
                })?;
            }
        } // Release mutex before discover_devices

        // Discover camera from info to get model flags (has its own mutex lock)
        if let Ok(devices) = discover_devices().await {
            if let Some(dev) = devices.get(self.device_index) {
                self.model_flags = dev.model_flags;
                self.sensor_info = SensorInfo {
                    width: dev.width,
                    height: dev.height,
                    pixel_size_x: dev.pixel_size_x as f64,
                    pixel_size_y: dev.pixel_size_y as f64,
                    max_adu: 65535,
                    bit_depth: 16,
                    color: (dev.model_flags & OGMACAM_FLAG_MONO) == 0,
                    bayer_pattern: if (dev.model_flags & OGMACAM_FLAG_MONO) == 0 {
                        Some(crate::camera::BayerPattern::Rggb)
                    } else {
                        None
                    },
                };
                self.name = dev.name.clone();
            }
        }

        // Set capabilities based on flags
        let can_cool = (self.model_flags & OGMACAM_FLAG_TEC) != 0;
        let can_set_temp = (self.model_flags & OGMACAM_FLAG_TEC_ONOFF) != 0;
        let has_st4 = (self.model_flags & OGMACAM_FLAG_ST4) != 0;
        let can_bin = (self.model_flags & OGMACAM_FLAG_BINSKIP_SUPPORTED) != 0;
        let can_subframe = (self.model_flags & OGMACAM_FLAG_ROI_HARDWARE) != 0;

        self.capabilities = CameraCapabilities {
            can_cool: can_cool && can_set_temp,
            can_set_gain: true,
            can_set_offset: false, // Touptek doesn't have separate offset
            can_set_binning: can_bin,
            can_subframe,
            has_shutter: false,
            has_guider_port: has_st4,
            max_bin_x: if can_bin { 4 } else { 1 },
            max_bin_y: if can_bin { 4 } else { 1 },
            supports_readout_modes: false,
        };

        // Set 16-bit raw mode (get fresh handle after await, needs mutex)
        {
            let _lock = touptek_mutex().lock().await;
            let handle_val = self.handle.lock().unwrap().0;
            with_sdk(&brand, |sdk| {
                let _ = unsafe { (sdk.put_option)(handle_val, OGMACAM_OPTION_RAW, 1) };
                let _ = unsafe { (sdk.put_option)(handle_val, OGMACAM_OPTION_BITDEPTH, 1) }; // 1 = 16-bit
                Ok(())
            })?;
        }

        self.connected = true;
        self.state = CameraState::Idle;

        tracing::info!(
            "Connected to Touptek camera: {} ({}x{})",
            self.name,
            self.sensor_info.width,
            self.sensor_info.height
        );

        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Ok(());
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        // Stop any capture and close camera
        with_sdk(&brand, |sdk| {
            let _ = unsafe { (sdk.stop)(handle) };
            unsafe { (sdk.close)(handle) };
            Ok(())
        })?;

        {
            let mut h = self.handle.lock().unwrap();
            *h = HandleWrapper(std::ptr::null_mut());
        }
        self.connected = false;
        self.state = CameraState::Idle;

        tracing::info!("Disconnected from Touptek camera: {}", self.name);

        Ok(())
    }
}

#[async_trait]
impl NativeCamera for TouptekCamera {
    fn capabilities(&self) -> CameraCapabilities {
        self.capabilities.clone()
    }

    fn get_sensor_info(&self) -> SensorInfo {
        self.sensor_info.clone()
    }

    async fn get_status(&self) -> Result<CameraStatus, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        // Get current temperature
        let current_temp = with_sdk(&brand, |sdk| {
            let mut temp: i16 = 0;
            if unsafe { (sdk.get_temperature)(handle, &mut temp) } >= 0 {
                Ok(temp as f64 / 10.0)
            } else {
                Ok(0.0)
            }
        })?;

        // Get TEC power (not directly available, estimate from temp difference)
        let cooler_power = if self.cooler_on {
            let diff = (self.target_temp - current_temp).abs();
            Some(((diff / 20.0) * 100.0).min(100.0))
        } else {
            Some(0.0)
        };

        // Calculate exposure remaining
        let exposure_remaining = if self.state == CameraState::Exposing {
            Some(self.exposure_duration) // Simplified - would need actual tracking
        } else {
            None
        };

        Ok(CameraStatus {
            state: self.state.clone(),
            sensor_temp: Some(current_temp),
            cooler_power,
            target_temp: Some(self.target_temp),
            cooler_on: self.cooler_on,
            gain: self.current_gain,
            offset: self.current_offset,
            bin_x: self.current_bin_x,
            bin_y: self.current_bin_y,
            exposure_remaining,
        })
    }

    async fn start_exposure(&mut self, params: ExposureParams) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Set gain if provided
        if let Some(gain) = params.gain {
            self.set_gain(gain).await?;
        }

        // Set binning
        self.set_binning(params.bin_x, params.bin_y).await?;

        // Set subframe
        self.set_subframe(params.subframe.clone()).await?;

        // Now get SDK and handle after all awaits
        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        // Set exposure time and start snap, all within SDK lock
        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            let exposure_us = (params.duration_secs * 1_000_000.0) as c_uint;
            let result = unsafe { (sdk.put_expo_time)(handle, exposure_us) };
            if result < 0 {
                tracing::error!(
                    "Touptek put_ExpoTime() failed for camera '{}'. Requested: {}µs ({:.3}s), error code: {}",
                    name, exposure_us, params.duration_secs, result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to set exposure time {:.3}s on Touptek camera '{}'. SDK error: {}",
                    params.duration_secs, name, result
                )));
            }

            let result = unsafe { (sdk.snap)(handle, 0) };
            if result < 0 {
                tracing::error!(
                    "Touptek Snap() failed for camera '{}'. Duration: {:.3}s, error code: {}",
                    name,
                    params.duration_secs,
                    result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to start exposure on Touptek camera '{}'. SDK error: {}",
                    name, result
                )));
            }
            Ok(())
        })?;

        self.exposure_duration = params.duration_secs;
        self.state = CameraState::Exposing;

        Ok(())
    }

    async fn abort_exposure(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            let result = unsafe { (sdk.stop)(handle) };
            if result < 0 {
                tracing::error!(
                    "Touptek Stop() failed for camera '{}'. Error code: {}",
                    name,
                    result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to abort exposure on Touptek camera '{}'. SDK error: {}",
                    name, result
                )));
            }
            Ok(())
        })?;

        self.state = CameraState::Idle;
        tracing::info!("Aborted exposure on Touptek camera '{}'", self.name);
        Ok(())
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        // Calculate buffer size
        let width = self.sensor_info.width as usize;
        let height = self.sensor_info.height as usize;
        let bytes_per_pixel = 2; // 16-bit
        let buffer_size = width * height * bytes_per_pixel;

        let mut buffer = vec![0u8; buffer_size];
        let mut info: OgmacamFrameInfoV3 = unsafe { std::mem::zeroed() };

        // Pull the image
        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            let result = unsafe {
                (sdk.pull_image_v3)(
                    handle,
                    buffer.as_mut_ptr() as *mut c_void,
                    1,  // bStill = true
                    16, // 16 bits
                    0,  // auto row pitch
                    &mut info,
                )
            };

            if result < 0 {
                tracing::error!(
                    "Touptek PullImageV3() failed for camera '{}'. Buffer: {}x{} pixels, error code: {}",
                    name, width, height, result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to download image from Touptek camera '{}'. SDK error: {}",
                    name, result
                )));
            }
            Ok(())
        })?;

        // Convert to u16 array
        let data: Vec<u16> = buffer
            .chunks_exact(2)
            .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
            .collect();

        self.state = CameraState::Idle;

        let metadata = ImageMetadata {
            exposure_time: self.exposure_duration,
            gain: self.current_gain,
            offset: self.current_offset,
            bin_x: self.current_bin_x,
            bin_y: self.current_bin_y,
            temperature: None,
            timestamp: chrono::Utc::now(),
            subframe: self.subframe.clone(),
            readout_mode: None,
            vendor_data: VendorFeatures::default(),
        };

        Ok(ImageData {
            width: info.width as u32,
            height: info.height as u32,
            data,
            bits_per_pixel: 16,
            bayer_pattern: self.sensor_info.bayer_pattern,
            metadata,
        })
    }

    async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        // For Touptek, we check if state is no longer Exposing
        // In a real implementation, we'd check the SDK status
        Ok(self.state != CameraState::Exposing)
    }

    async fn set_cooler(&mut self, enabled: bool, target_temp: f64) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.capabilities.can_cool {
            return Err(NativeError::NotSupported);
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        // Enable/disable TEC
        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            let result = unsafe {
                (sdk.put_option)(handle, OGMACAM_OPTION_TEC, if enabled { 1 } else { 0 })
            };
            if result < 0 {
                tracing::error!(
                    "Touptek put_Option(TEC) failed for camera '{}'. Enabled: {}, error code: {}",
                    name,
                    enabled,
                    result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to {} cooler on Touptek camera '{}'. SDK error: {}",
                    if enabled { "enable" } else { "disable" },
                    name,
                    result
                )));
            }

            // Set target temperature (in 0.1 degrees Celsius)
            if enabled {
                let temp = (target_temp * 10.0) as i16;
                let result = unsafe { (sdk.put_temperature)(handle, temp) };
                if result < 0 {
                    tracing::error!(
                        "Touptek put_Temperature() failed for camera '{}'. Target: {:.1}°C, error code: {}",
                        name, target_temp, result
                    );
                    return Err(NativeError::SdkError(format!(
                        "Failed to set cooler temperature to {:.1}°C on Touptek camera '{}'. SDK error: {}",
                        target_temp, name, result
                    )));
                }
            }
            Ok(())
        })?;

        self.cooler_on = enabled;
        self.target_temp = target_temp;
        Ok(())
    }

    async fn get_temperature(&self) -> Result<f64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            let mut temp: i16 = 0;
            let result = unsafe { (sdk.get_temperature)(handle, &mut temp) };
            if result < 0 {
                tracing::error!(
                    "Touptek get_Temperature() failed for camera '{}'. Error code: {}",
                    name,
                    result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to read temperature from Touptek camera '{}'. SDK error: {}. Camera may not have a temperature sensor.",
                    name, result
                )));
            }
            Ok(temp as f64 / 10.0)
        })
    }

    async fn get_cooler_power(&self) -> Result<f64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Touptek SDK doesn't expose cooler power directly
        // Estimate from temperature difference
        if self.cooler_on {
            let current_temp = self.get_temperature().await?;
            let diff = (self.target_temp - current_temp).abs();
            Ok(((diff / 20.0) * 100.0).min(100.0))
        } else {
            Ok(0.0)
        }
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            let result = unsafe { (sdk.put_expo_again)(handle, gain as u16) };
            if result < 0 {
                tracing::error!(
                    "Touptek put_ExpoAGain() failed for camera '{}'. Requested gain: {}, error code: {}",
                    name, gain, result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to set gain to {} on Touptek camera '{}'. SDK error: {}. Value may be out of range.",
                    gain, name, result
                )));
            }
            Ok(())
        })?;

        self.current_gain = gain;
        Ok(())
    }

    async fn set_offset(&mut self, offset: i32) -> Result<(), NativeError> {
        // Touptek doesn't have a separate offset control
        self.current_offset = offset;
        Ok(())
    }

    async fn set_binning(&mut self, bin_x: i32, bin_y: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.capabilities.can_set_binning && (bin_x > 1 || bin_y > 1) {
            return Err(NativeError::NotSupported);
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        // Touptek uses combined binning value
        let bin_mode = bin_x.max(bin_y);
        let name = self.name.clone();
        let max_bx = self.capabilities.max_bin_x;
        let max_by = self.capabilities.max_bin_y;
        with_sdk(&brand, |sdk| {
            let result = unsafe { (sdk.put_option)(handle, OGMACAM_OPTION_BINNING, bin_mode) };
            if result < 0 {
                tracing::error!(
                    "Touptek put_Option(BINNING) failed for camera '{}'. Requested: {}x{}, error code: {}",
                    name, bin_x, bin_y, result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to set binning to {}x{} on Touptek camera '{}'. SDK error: {}. Max: {}x{}",
                    bin_x, bin_y, name, result, max_bx, max_by
                )));
            }
            Ok(())
        })?;

        self.current_bin_x = bin_x;
        self.current_bin_y = bin_y;
        Ok(())
    }

    async fn set_subframe(&mut self, subframe: Option<SubFrame>) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap().0;

        let name = self.name.clone();
        let sensor_w = self.sensor_info.width;
        let sensor_h = self.sensor_info.height;

        if let Some(sf) = &subframe {
            if !self.capabilities.can_subframe {
                return Err(NativeError::NotSupported);
            }

            let sx = sf.start_x;
            let sy = sf.start_y;
            let sw = sf.width;
            let sh = sf.height;
            with_sdk(&brand, |sdk| {
                let result = unsafe { (sdk.put_roi)(handle, sx, sy, sw, sh) };
                if result < 0 {
                    tracing::error!(
                        "Touptek put_Roi() failed for camera '{}'. Requested: ({}, {}) {}x{}, sensor: {}x{}, error code: {}",
                        name, sx, sy, sw, sh, sensor_w, sensor_h, result
                    );
                    return Err(NativeError::SdkError(format!(
                        "Failed to set ROI ({}, {}) {}x{} on Touptek camera '{}'. SDK error: {}",
                        sx, sy, sw, sh, name, result
                    )));
                }
                Ok(())
            })?;
        } else {
            // Reset to full frame
            with_sdk(&brand, |sdk| {
                let result = unsafe { (sdk.put_roi)(handle, 0, 0, sensor_w, sensor_h) };
                if result < 0 {
                    tracing::error!(
                        "Touptek put_Roi() failed to reset to full frame for camera '{}'. Error code: {}",
                        name, result
                    );
                    return Err(NativeError::SdkError(format!(
                        "Failed to reset ROI to full frame on Touptek camera '{}'. SDK error: {}",
                        name, result
                    )));
                }
                Ok(())
            })?;
        }

        self.subframe = subframe;
        Ok(())
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        Ok(self.current_gain)
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        Ok(self.current_offset)
    }

    async fn get_binning(&self) -> Result<(i32, i32), NativeError> {
        Ok((self.current_bin_x, self.current_bin_y))
    }

    async fn get_readout_modes(&self) -> Result<Vec<ReadoutMode>, NativeError> {
        // Touptek cameras don't have distinct readout modes
        Ok(vec![ReadoutMode {
            name: "Normal".to_string(),
            description: "Standard readout mode".to_string(),
            index: 0,
            gain_min: None,
            gain_max: None,
            offset_min: None,
            offset_max: None,
        }])
    }

    async fn set_readout_mode(&mut self, _mode: &ReadoutMode) -> Result<(), NativeError> {
        // No-op for Touptek cameras
        Ok(())
    }

    async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
        Ok(VendorFeatures::default())
    }

    async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Touptek cameras typically support gain ranges similar to ZWO cameras.
        // Most CMOS sensors support 0-500 or similar range.
        // The actual range is camera-dependent; SDK should ideally provide this.
        Ok((0, 500))
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Touptek cameras typically support offset in a similar range to ZWO.
        Ok((0, 256))
    }
}
