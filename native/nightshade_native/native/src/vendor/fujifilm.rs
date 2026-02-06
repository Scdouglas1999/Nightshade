//! Fujifilm X Acquire SDK Wrapper
//!
//! Provides native support for Fujifilm cameras (GFX and X-series) via the X Acquire SDK.
//! The SDK is Windows-only and provided as XAPI.dll plus model-specific DLLs.
//!
//! ## Thread Safety
//!
//! The Fujifilm SDK is NOT thread-safe. All SDK operations are protected by
//! `fujifilm_mutex()` from `crate::sync`.
//!
//! ## Important SDK Behaviors
//!
//! 1. **Dynamic Range First**: Must set DR to 100 before querying ISO values
//! 2. **100ms Delays**: Required between operations for hardware settling
//! 3. **Retry Detection**: Camera detection may need 3 attempts with exponential backoff
//! 4. **Bulb Sequence**: Must follow exact S1ON → BULBS2_ON → wait → N_BULBS1OFF sequence
//!
//! ## SDK Requirements
//!
//! - XAPI.dll (main SDK)
//! - FF0000API.dll through FF0020API.dll (model-specific modules)
//!
//! Based on the Nina Fujifilm plugin: https://github.com/Scoduglas1999/NINA-Fujifilm-Native-Plugin

#![cfg(target_os = "windows")]
#![allow(dead_code)] // FFI types must match SDK headers even if not all variants are used

use crate::camera::*;
use crate::sync::fujifilm_mutex;
use crate::traits::*;
use crate::NativeVendor;
use async_trait::async_trait;
use std::ffi::{c_char, c_long, c_ulong, c_void, CString};
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

// =============================================================================
// FUJIFILM SDK TYPE DEFINITIONS (from XAPI.h)
// =============================================================================

/// Camera handle type
type XsdkHandle = *mut c_void;

/// Camera list for device detection (XAPI.h lines 52-60)
#[repr(C, packed)]
#[derive(Clone)]
struct XsdkCameraList {
    str_product: [c_char; 256],    // Model name (e.g., "X-T5")
    str_serial_no: [c_char; 256],  // Serial number (USB only)
    str_ip_address: [c_char; 256], // IPv4 address (network only)
    str_framework: [c_char; 256],  // "USB" / "ETHER" / "IP"
    b_valid: bool,                 // true if entry is valid
}

impl Default for XsdkCameraList {
    fn default() -> Self {
        Self {
            str_product: [0; 256],
            str_serial_no: [0; 256],
            str_ip_address: [0; 256],
            str_framework: [0; 256],
            b_valid: false,
        }
    }
}

/// Device information (XAPI.h lines 63-76)
#[repr(C, packed)]
#[derive(Clone)]
struct XsdkDeviceInformation {
    str_vendor: [c_char; 256],
    str_manufacturer: [c_char; 256],
    str_product: [c_char; 256],
    str_firmware: [c_char; 256],
    str_device_type: [c_char; 256],
    str_serial_no: [c_char; 256],
    str_framework: [c_char; 256],
    b_device_id: u8,
    str_device_name: [c_char; 32],
    str_y_no: [c_char; 32],
}

impl Default for XsdkDeviceInformation {
    fn default() -> Self {
        Self {
            str_vendor: [0; 256],
            str_manufacturer: [0; 256],
            str_product: [0; 256],
            str_firmware: [0; 256],
            str_device_type: [0; 256],
            str_serial_no: [0; 256],
            str_framework: [0; 256],
            b_device_id: 0,
            str_device_name: [0; 32],
            str_y_no: [0; 32],
        }
    }
}

/// Image information from camera buffer (XAPI.h lines 115-127)
#[repr(C, packed)]
#[derive(Clone)]
struct XsdkImageInformation {
    str_internal_name: [c_char; 32],
    l_format: c_long,    // XSDK_IMAGEFORMAT_RAW = 1, XSDK_IMAGEFORMAT_JPEG = 7
    l_data_size: c_long, // Size of image data in bytes
    l_image_pix_height: c_long,
    l_image_pix_width: c_long,
    l_image_bit_depth: c_long,
    l_preview_size: c_long,
    h_image: *mut c_void, // XSDK_HANDLE
}

impl Default for XsdkImageInformation {
    fn default() -> Self {
        Self {
            str_internal_name: [0; 32],
            l_format: 0,
            l_data_size: 0,
            l_image_pix_height: 0,
            l_image_pix_width: 0,
            l_image_bit_depth: 0,
            l_preview_size: 0,
            h_image: std::ptr::null_mut(),
        }
    }
}

// =============================================================================
// SDK CONSTANTS (from XAPI.h)
// =============================================================================

// Return values (XAPI.h lines 2264-2267)
const XSDK_COMPLETE: c_long = 0;
#[allow(dead_code)]
const XSDK_ERROR: c_long = -1;

// Connection interface (XAPI.h lines 259-261)
const XSDK_DSC_IF_USB: c_long = 0x00000001;
#[allow(dead_code)]
const XSDK_DSC_IF_WIFI_LOCAL: c_long = 0x00000010;
#[allow(dead_code)]
const XSDK_DSC_IF_WIFI_IP: c_long = 0x00000020;

// Priority mode (XAPI.h lines 270-271)
#[allow(dead_code)]
const XSDK_PRIORITY_CAMERA: c_long = 0x0001;
const XSDK_PRIORITY_PC: c_long = 0x0002;

// Release mode - ON modes (XAPI.h lines 276-290)
#[allow(dead_code)]
const XSDK_RELEASE_SHOOT: c_long = 0x0100;
const XSDK_RELEASE_S1ON: c_long = 0x0200;
#[allow(dead_code)]
const XSDK_RELEASE_S2: c_long = 0x0300;
#[allow(dead_code)]
const XSDK_RELEASE_BULB_ON: c_long = 0x0400;
const XSDK_RELEASE_BULBS2_ON: c_long = 0x0500;

// Release mode - OFF modes (XAPI.h lines 292-310)
#[allow(dead_code)]
const XSDK_RELEASE_N_S1OFF: c_long = 0x0004;
#[allow(dead_code)]
const XSDK_RELEASE_N_BULBOFF: c_long = 0x0008;
const XSDK_RELEASE_N_BULBS1OFF: c_long = 0x000C; // BULBS2OFF | S1OFF
#[allow(dead_code)]
const XSDK_RELEASE_CANCEL: c_long = 0x000F;

// Combined release modes (XAPI.h lines 313-324)
const XSDK_RELEASE_SHOOT_S1OFF: c_long = 0x0104; // Normal single shot

// Image format (XAPI.h lines 376-393)
const XSDK_IMAGEFORMAT_RAW: c_long = 1;
const XSDK_IMAGEFORMAT_LIVE: c_long = 4;
#[allow(dead_code)]
const XSDK_IMAGEFORMAT_NONE: c_long = 5;
#[allow(dead_code)]
const XSDK_IMAGEFORMAT_JPEG: c_long = 7;

// Live View control (XAPIOpt.h lines 366-384)
const API_CODE_START_LIVE_VIEW: c_long = 0x3301;
const API_CODE_STOP_LIVE_VIEW: c_long = 0x3302;
const API_CODE_SET_LIVE_VIEW_IMAGE_QUALITY: c_long = 0x3323;
const API_CODE_SET_LIVE_VIEW_IMAGE_SIZE: c_long = 0x3325;
#[allow(dead_code)]
const API_CODE_GET_LIVE_VIEW_STATUS: c_long = 0x332D;

// Live view quality (XAPIOpt.h lines 574-579)
const SDK_LIVEVIEW_QUALITY_FINE: c_long = 0x0001;
const SDK_LIVEVIEW_QUALITY_NORMAL: c_long = 0x0002;
const SDK_LIVEVIEW_QUALITY_BASIC: c_long = 0x0003;

// Live view size (XAPIOpt.h lines 582-590)
const SDK_LIVEVIEW_SIZE_L: c_long = 0x0001; // 1280px
#[allow(dead_code)]
const SDK_LIVEVIEW_SIZE_M: c_long = 0x0002; // 800px
#[allow(dead_code)]
const SDK_LIVEVIEW_SIZE_S: c_long = 0x0003; // 640px

// Focus control API codes (XAPIOpt.h lines 265-275, 316)
const API_CODE_SET_FOCUS_POS: c_long = 0x2207;
const API_CODE_GET_FOCUS_POS: c_long = 0x2208;
const API_CODE_CAP_FOCUS_POS: c_long = 0x2259;
#[allow(dead_code)]
const API_CODE_SET_FOCUS_MODE: c_long = 0x2201;
#[allow(dead_code)]
const API_CODE_GET_FOCUS_MODE: c_long = 0x2202;

// Focus mode constants
#[allow(dead_code)]
const SDK_FOCUS_MODE_MF: c_long = 0x0001;
#[allow(dead_code)]
const SDK_FOCUS_MODE_AFS: c_long = 0x0002;
#[allow(dead_code)]
const SDK_FOCUS_MODE_AFC: c_long = 0x0003;

// Dynamic range (XAPI.h lines 2087-2090)
const XSDK_DR_100: c_long = 100;
#[allow(dead_code)]
const XSDK_DR_200: c_long = 200;
#[allow(dead_code)]
const XSDK_DR_400: c_long = 400;

// Shutter speed codes (XAPI.h lines 405-533)
const XSDK_SHUTTER_BULB: c_long = -1;

// Error codes (XAPI.h lines 2233-2261)
const XSDK_ERRCODE_NOERR: c_long = 0x00000000;
const XSDK_ERRCODE_SEQUENCE: c_long = 0x00001001;
const XSDK_ERRCODE_PARAM: c_long = 0x00001002;
const XSDK_ERRCODE_INVALID_CAMERA: c_long = 0x00001003;
const XSDK_ERRCODE_LOADLIB: c_long = 0x00001004;
const XSDK_ERRCODE_UNSUPPORTED: c_long = 0x00001005;
const XSDK_ERRCODE_BUSY: c_long = 0x00001006;
const XSDK_ERRCODE_AF_TIMEOUT: c_long = 0x00001007;
const XSDK_ERRCODE_SHOOT_ERROR: c_long = 0x00001008;
const XSDK_ERRCODE_FRAME_FULL: c_long = 0x00001009;
const XSDK_ERRCODE_STANDBY: c_long = 0x00001010;
const XSDK_ERRCODE_NODRIVER: c_long = 0x00001011;
const XSDK_ERRCODE_NO_MODEL_MODULE: c_long = 0x00001012;
const XSDK_ERRCODE_API_NOTFOUND: c_long = 0x00001013;
const XSDK_ERRCODE_API_MISMATCH: c_long = 0x00001014;
const XSDK_ERRCODE_INVALID_USBMODE: c_long = 0x00001015;
const XSDK_ERRCODE_FORCEMODE_BUSY: c_long = 0x00001016;
const XSDK_ERRCODE_RUNNING_OTHER_FUNCTION: c_long = 0x00001017;
const XSDK_ERRCODE_COMMUNICATION: c_long = 0x00002001;
const XSDK_ERRCODE_TIMEOUT: c_long = 0x00002002;
const XSDK_ERRCODE_COMBINATION: c_long = 0x00002003;
const XSDK_ERRCODE_WRITEERROR: c_long = 0x00002004;
const XSDK_ERRCODE_CARDFULL: c_long = 0x00002005;
const XSDK_ERRCODE_HARDWARE: c_long = 0x00003001;
const XSDK_ERRCODE_INTERNAL: c_long = 0x00009001;
const XSDK_ERRCODE_MEMFULL: c_long = 0x00009002;
const XSDK_ERRCODE_UNKNOWN: c_long = 0x00009100;

// =============================================================================
// SHUTTER SPEED MAPPING
// =============================================================================

/// Shutter speed code to seconds mapping
struct ShutterSpeedEntry {
    code: c_long,
    seconds: f64,
}

/// Common shutter speeds from XAPI.h
/// The SDK uses integer codes proportional to time
static SHUTTER_SPEEDS: &[ShutterSpeedEntry] = &[
    ShutterSpeedEntry {
        code: 122,
        seconds: 1.0 / 8000.0,
    },
    ShutterSpeedEntry {
        code: 244,
        seconds: 1.0 / 4000.0,
    },
    ShutterSpeedEntry {
        code: 488,
        seconds: 1.0 / 2000.0,
    },
    ShutterSpeedEntry {
        code: 976,
        seconds: 1.0 / 1000.0,
    },
    ShutterSpeedEntry {
        code: 1953,
        seconds: 1.0 / 500.0,
    },
    ShutterSpeedEntry {
        code: 3906,
        seconds: 1.0 / 250.0,
    },
    ShutterSpeedEntry {
        code: 7812,
        seconds: 1.0 / 125.0,
    },
    ShutterSpeedEntry {
        code: 15625,
        seconds: 1.0 / 60.0,
    },
    ShutterSpeedEntry {
        code: 31250,
        seconds: 1.0 / 30.0,
    },
    ShutterSpeedEntry {
        code: 62500,
        seconds: 1.0 / 15.0,
    },
    ShutterSpeedEntry {
        code: 125000,
        seconds: 1.0 / 8.0,
    },
    ShutterSpeedEntry {
        code: 250000,
        seconds: 1.0 / 4.0,
    },
    ShutterSpeedEntry {
        code: 500000,
        seconds: 1.0 / 2.0,
    },
    ShutterSpeedEntry {
        code: 1000000,
        seconds: 1.0,
    },
    ShutterSpeedEntry {
        code: 2000000,
        seconds: 2.0,
    },
    ShutterSpeedEntry {
        code: 4000000,
        seconds: 4.0,
    },
    ShutterSpeedEntry {
        code: 8000000,
        seconds: 8.0,
    },
    ShutterSpeedEntry {
        code: 16000000,
        seconds: 15.0,
    },
    ShutterSpeedEntry {
        code: 32000000,
        seconds: 30.0,
    },
    ShutterSpeedEntry {
        code: 64000000,
        seconds: 60.0,
    },
];

/// Find the closest shutter speed code for a given duration
fn find_shutter_code(seconds: f64) -> c_long {
    if seconds > 60.0 {
        return XSDK_SHUTTER_BULB;
    }

    // Find the closest matching shutter speed
    let mut best_code = XSDK_SHUTTER_BULB;
    let mut best_diff = f64::MAX;

    for entry in SHUTTER_SPEEDS {
        let diff = (entry.seconds - seconds).abs();
        if diff < best_diff {
            best_diff = diff;
            best_code = entry.code;
        }
    }

    best_code
}

// =============================================================================
// LIVE VIEW QUALITY
// =============================================================================

/// Live view quality setting
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum LiveViewQuality {
    /// Fine quality (highest, more bandwidth)
    Fine,
    /// Normal quality (balanced)
    #[default]
    Normal,
    /// Basic quality (lowest, less bandwidth)
    Basic,
}

impl LiveViewQuality {
    /// Convert to SDK constant
    fn to_sdk_code(self) -> c_long {
        match self {
            LiveViewQuality::Fine => SDK_LIVEVIEW_QUALITY_FINE,
            LiveViewQuality::Normal => SDK_LIVEVIEW_QUALITY_NORMAL,
            LiveViewQuality::Basic => SDK_LIVEVIEW_QUALITY_BASIC,
        }
    }
}

// =============================================================================
// CAMERA MODEL DATABASE
// =============================================================================

/// Fujifilm camera model information
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FujifilmModel {
    // GFX Medium Format (Bayer sensors)
    Gfx100,
    Gfx100II,
    Gfx100SII,
    Gfx50R,
    Gfx50S,
    Gfx50SII,

    // X-H Series (X-Trans V sensors, high-res)
    XH2,
    XH2S,

    // X-T Series (X-Trans)
    XT3,
    XT4,
    XT5,

    // Other X-series
    XM5,
    XS10,
    XS20,
    XPro3,
    XE4,
    X100V,
    X100VI,

    Unknown,
}

impl FujifilmModel {
    /// Parse model from product name string
    fn from_product_name(name: &str) -> Self {
        let name_upper = name.to_uppercase();

        if name_upper.contains("GFX 100S II") || name_upper.contains("GFX100S II") {
            Self::Gfx100SII
        } else if name_upper.contains("GFX 100 II") || name_upper.contains("GFX100 II") {
            Self::Gfx100II
        } else if name_upper.contains("GFX 100") || name_upper.contains("GFX100") {
            Self::Gfx100
        } else if name_upper.contains("GFX 50S II") || name_upper.contains("GFX50S II") {
            Self::Gfx50SII
        } else if name_upper.contains("GFX 50R") || name_upper.contains("GFX50R") {
            Self::Gfx50R
        } else if name_upper.contains("GFX 50S") || name_upper.contains("GFX50S") {
            Self::Gfx50S
        } else if name_upper.contains("X-H2S") || name_upper.contains("XH2S") {
            Self::XH2S
        } else if name_upper.contains("X-H2") || name_upper.contains("XH2") {
            Self::XH2
        } else if name_upper.contains("X-T5") || name_upper.contains("XT5") {
            Self::XT5
        } else if name_upper.contains("X-T4") || name_upper.contains("XT4") {
            Self::XT4
        } else if name_upper.contains("X-T3") || name_upper.contains("XT3") {
            Self::XT3
        } else if name_upper.contains("X-M5") || name_upper.contains("XM5") {
            Self::XM5
        } else if name_upper.contains("X-S20") || name_upper.contains("XS20") {
            Self::XS20
        } else if name_upper.contains("X-S10") || name_upper.contains("XS10") {
            Self::XS10
        } else if name_upper.contains("X-PRO3") || name_upper.contains("XPRO3") {
            Self::XPro3
        } else if name_upper.contains("X-E4") || name_upper.contains("XE4") {
            Self::XE4
        } else if name_upper.contains("X100VI") {
            Self::X100VI
        } else if name_upper.contains("X100V") {
            Self::X100V
        } else {
            Self::Unknown
        }
    }

    /// Check if this is an X-Trans sensor (non-Bayer)
    fn is_xtrans(&self) -> bool {
        !matches!(
            self,
            Self::Gfx100
                | Self::Gfx100II
                | Self::Gfx100SII
                | Self::Gfx50R
                | Self::Gfx50S
                | Self::Gfx50SII
        )
    }

    /// Get sensor specifications (width, height, pixel_size_um, bit_depth)
    fn sensor_specs(&self) -> (u32, u32, f64, u32) {
        match self {
            Self::Gfx100 | Self::Gfx100II | Self::Gfx100SII => (11648, 8736, 3.76, 14),
            Self::Gfx50R | Self::Gfx50S | Self::Gfx50SII => (8256, 6192, 5.3, 14),
            Self::XH2 | Self::XT5 => (9728, 7296, 3.0, 14), // 40MP X-Trans
            Self::XH2S => (6240, 4160, 3.76, 14),           // 26MP X-Trans stacked
            _ => (6240, 4160, 3.76, 14),                    // 26MP X-Trans default
        }
    }
}

// =============================================================================
// SDK LIBRARY LOADING
// =============================================================================

/// Fujifilm SDK library wrapper
struct FujifilmSdk {
    #[allow(dead_code)]
    lib: libloading::Library,

    // Initialize/Finalize
    init: unsafe extern "C" fn(h_lib: *mut c_void) -> c_long,
    exit: unsafe extern "C" fn() -> c_long,

    // Enumeration
    detect: unsafe extern "C" fn(
        l_interface: c_long,
        p_interface: *mut c_char,
        p_device_name: *mut c_char,
        pl_count: *mut c_long,
    ) -> c_long,
    append: unsafe extern "C" fn(
        l_interface: c_long,
        p_interface: *mut c_char,
        p_device_name: *mut c_char,
        pl_count: *mut c_long,
        p_camera_list: *mut XsdkCameraList,
    ) -> c_long,

    // Session management
    open_ex: unsafe extern "C" fn(
        p_device: *const c_char,
        ph_camera: *mut XsdkHandle,
        pl_camera_mode: *mut c_long,
        p_option: *mut c_void,
    ) -> c_long,
    close: unsafe extern "C" fn(h_camera: XsdkHandle) -> c_long,

    // Basic functions
    get_error_number: unsafe extern "C" fn(
        h_camera: XsdkHandle,
        pl_api_code: *mut c_long,
        pl_err_code: *mut c_long,
    ) -> c_long,

    // Device Information
    get_device_info: unsafe extern "C" fn(
        h_camera: XsdkHandle,
        p_dev_info: *mut XsdkDeviceInformation,
    ) -> c_long,

    // Priority Mode
    set_priority_mode:
        unsafe extern "C" fn(h_camera: XsdkHandle, l_priority_mode: c_long) -> c_long,

    // Release Control
    release: unsafe extern "C" fn(
        h_camera: XsdkHandle,
        l_release_mode: c_long,
        pl_shot_opt: *mut c_long,
        pl_af_status: *mut c_long,
    ) -> c_long,

    // Image acquisition
    read_image_info:
        unsafe extern "C" fn(h_camera: XsdkHandle, p_img_info: *mut XsdkImageInformation) -> c_long,
    read_image:
        unsafe extern "C" fn(h_camera: XsdkHandle, p_data: *mut u8, l_data_size: c_ulong) -> c_long,
    delete_image: unsafe extern "C" fn(h_camera: XsdkHandle) -> c_long,

    // Exposure control
    cap_shutter_speed: unsafe extern "C" fn(
        h_camera: XsdkHandle,
        pl_num: *mut c_long,
        pl_shutter_speed: *mut c_long,
        pl_bulb_capable: *mut c_long,
    ) -> c_long,
    set_shutter_speed: unsafe extern "C" fn(
        h_camera: XsdkHandle,
        l_shutter_speed: c_long,
        l_bulb: c_long,
    ) -> c_long,
    cap_sensitivity: unsafe extern "C" fn(
        h_camera: XsdkHandle,
        pl_num: *mut c_long,
        pl_sensitivity: *mut c_long,
    ) -> c_long,
    set_sensitivity: unsafe extern "C" fn(h_camera: XsdkHandle, l_sensitivity: c_long) -> c_long,
    get_sensitivity:
        unsafe extern "C" fn(h_camera: XsdkHandle, pl_sensitivity: *mut c_long) -> c_long,
    set_dynamic_range:
        unsafe extern "C" fn(h_camera: XsdkHandle, l_dynamic_range: c_long) -> c_long,

    // Optional functions via XSDK_SetProp/XSDK_GetProp (lines 2390-2392)
    // These are varargs functions for live view, focus control, and other optional features
    set_prop: unsafe extern "C" fn(
        h_camera: XsdkHandle,
        l_api_code: c_long,
        l_api_param: c_long,
        ...
    ) -> c_long,
    get_prop: unsafe extern "C" fn(
        h_camera: XsdkHandle,
        l_api_code: c_long,
        l_api_param: c_long,
        ...
    ) -> c_long,
}

static FUJIFILM_SDK: OnceLock<Option<FujifilmSdk>> = OnceLock::new();

impl FujifilmSdk {
    /// Find the SDK DLL path
    fn find_sdk_path() -> Option<PathBuf> {
        // Try executable directory first
        if let Ok(exe_path) = std::env::current_exe() {
            if let Some(exe_dir) = exe_path.parent() {
                let xapi_path = exe_dir.join("XAPI.dll");
                if xapi_path.exists() {
                    return Some(xapi_path);
                }
            }
        }

        // Try X Acquire installation
        let x_acquire_paths = [
            PathBuf::from(r"C:\Program Files\Fujifilm\X Acquire\XAPI.dll"),
            PathBuf::from(r"C:\Program Files (x86)\Fujifilm\X Acquire\XAPI.dll"),
        ];
        for path in &x_acquire_paths {
            if path.exists() {
                return Some(path.clone());
            }
        }

        // Try current directory
        let current_dir = PathBuf::from("XAPI.dll");
        if current_dir.exists() {
            return Some(current_dir);
        }

        None
    }

    /// Load the Fujifilm SDK library
    fn load() -> Option<Self> {
        let lib_path = Self::find_sdk_path().or_else(|| {
            // Last resort: try loading from system PATH
            Some(PathBuf::from("XAPI.dll"))
        })?;

        tracing::debug!("Trying to load Fujifilm SDK from: {:?}", lib_path);

        unsafe {
            match libloading::Library::new(&lib_path) {
                Ok(lib) => {
                    tracing::info!("Found Fujifilm SDK at: {:?}", lib_path);

                    // Helper to load and log function pointer failures
                    fn load_symbol<T: Copy>(
                        lib: &libloading::Library,
                        name: &[u8],
                        name_str: &str,
                    ) -> Option<T> {
                        match unsafe { lib.get::<T>(name) } {
                            Ok(sym) => Some(*sym),
                            Err(e) => {
                                tracing::error!(
                                    "Failed to load Fujifilm function '{}': {}",
                                    name_str,
                                    e
                                );
                                None
                            }
                        }
                    }

                    let init = load_symbol(&lib, b"XSDK_Init\0", "XSDK_Init")?;
                    let exit = load_symbol(&lib, b"XSDK_Exit\0", "XSDK_Exit")?;
                    let detect = load_symbol(&lib, b"XSDK_Detect\0", "XSDK_Detect")?;
                    let append = load_symbol(&lib, b"XSDK_Append\0", "XSDK_Append")?;
                    let open_ex = load_symbol(&lib, b"XSDK_OpenEx\0", "XSDK_OpenEx")?;
                    let close = load_symbol(&lib, b"XSDK_Close\0", "XSDK_Close")?;
                    let get_error_number =
                        load_symbol(&lib, b"XSDK_GetErrorNumber\0", "XSDK_GetErrorNumber")?;
                    let get_device_info =
                        load_symbol(&lib, b"XSDK_GetDeviceInfo\0", "XSDK_GetDeviceInfo")?;
                    let set_priority_mode =
                        load_symbol(&lib, b"XSDK_SetPriorityMode\0", "XSDK_SetPriorityMode")?;
                    let release = load_symbol(&lib, b"XSDK_Release\0", "XSDK_Release")?;
                    let read_image_info =
                        load_symbol(&lib, b"XSDK_ReadImageInfo\0", "XSDK_ReadImageInfo")?;
                    let read_image = load_symbol(&lib, b"XSDK_ReadImage\0", "XSDK_ReadImage")?;
                    let delete_image =
                        load_symbol(&lib, b"XSDK_DeleteImage\0", "XSDK_DeleteImage")?;
                    let cap_shutter_speed =
                        load_symbol(&lib, b"XSDK_CapShutterSpeed\0", "XSDK_CapShutterSpeed")?;
                    let set_shutter_speed =
                        load_symbol(&lib, b"XSDK_SetShutterSpeed\0", "XSDK_SetShutterSpeed")?;
                    let cap_sensitivity =
                        load_symbol(&lib, b"XSDK_CapSensitivity\0", "XSDK_CapSensitivity")?;
                    let set_sensitivity =
                        load_symbol(&lib, b"XSDK_SetSensitivity\0", "XSDK_SetSensitivity")?;
                    let get_sensitivity =
                        load_symbol(&lib, b"XSDK_GetSensitivity\0", "XSDK_GetSensitivity")?;
                    let set_dynamic_range =
                        load_symbol(&lib, b"XSDK_SetDynamicRange\0", "XSDK_SetDynamicRange")?;
                    let set_prop = load_symbol(&lib, b"XSDK_SetProp\0", "XSDK_SetProp")?;
                    let get_prop = load_symbol(&lib, b"XSDK_GetProp\0", "XSDK_GetProp")?;

                    let sdk = Self {
                        lib,
                        init,
                        exit,
                        detect,
                        append,
                        open_ex,
                        close,
                        get_error_number,
                        get_device_info,
                        set_priority_mode,
                        release,
                        read_image_info,
                        read_image,
                        delete_image,
                        cap_shutter_speed,
                        set_shutter_speed,
                        cap_sensitivity,
                        set_sensitivity,
                        get_sensitivity,
                        set_dynamic_range,
                        set_prop,
                        get_prop,
                    };

                    tracing::info!("Successfully loaded all Fujifilm SDK functions");
                    return Some(sdk);
                }
                Err(e) => {
                    tracing::debug!("Fujifilm SDK not found at {:?}: {}", lib_path, e);
                }
            }
        }

        tracing::info!("Fujifilm X Acquire SDK (XAPI.dll) not found. Native Fujifilm camera support unavailable.");
        tracing::info!("To use native Fujifilm drivers, install the Fujifilm X Acquire SDK or place XAPI.dll in the application directory.");
        None
    }

    /// Get the global SDK instance
    fn get() -> Option<&'static FujifilmSdk> {
        FUJIFILM_SDK.get_or_init(|| Self::load()).as_ref()
    }
}

// =============================================================================
// ERROR HANDLING
// =============================================================================

/// Map XSDK error codes to NativeError
fn check_xapi_error(h_camera: XsdkHandle, sdk: &FujifilmSdk) -> Result<(), NativeError> {
    let mut api_code: c_long = 0;
    let mut err_code: c_long = 0;
    unsafe { (sdk.get_error_number)(h_camera, &mut api_code, &mut err_code) };

    match err_code {
        XSDK_ERRCODE_NOERR => Ok(()),

        // Sequence/parameter errors
        XSDK_ERRCODE_SEQUENCE => Err(NativeError::SdkError("API call sequence error".into())),
        XSDK_ERRCODE_PARAM => Err(NativeError::InvalidParameter("Invalid parameter".into())),
        XSDK_ERRCODE_INVALID_CAMERA => Err(NativeError::NotConnected),

        // SDK/hardware errors
        XSDK_ERRCODE_LOADLIB => Ok(()), // Already initialized, recoverable
        XSDK_ERRCODE_UNSUPPORTED => Err(NativeError::NotSupported),
        XSDK_ERRCODE_BUSY => Err(NativeError::SdkError("Camera is busy".into())),
        XSDK_ERRCODE_AF_TIMEOUT => Err(NativeError::Timeout("Autofocus timeout".into())),
        XSDK_ERRCODE_SHOOT_ERROR => Err(NativeError::SdkError("Shooting error".into())),
        XSDK_ERRCODE_FRAME_FULL => Err(NativeError::SdkError("Camera buffer full".into())),
        XSDK_ERRCODE_STANDBY => Err(NativeError::SdkError("Camera in standby".into())),

        // Driver/model errors
        XSDK_ERRCODE_NODRIVER => Err(NativeError::SdkNotLoaded),
        XSDK_ERRCODE_NO_MODEL_MODULE => {
            Err(NativeError::SdkError("Model-specific DLL not found".into()))
        }
        XSDK_ERRCODE_API_NOTFOUND => Err(NativeError::NotSupported),
        XSDK_ERRCODE_API_MISMATCH => Err(NativeError::SdkError("API version mismatch".into())),
        XSDK_ERRCODE_INVALID_USBMODE => Err(NativeError::SdkError(
            "Camera not in correct USB mode".into(),
        )),
        XSDK_ERRCODE_FORCEMODE_BUSY => Err(NativeError::SdkError(
            "Force mode operation in progress".into(),
        )),
        XSDK_ERRCODE_RUNNING_OTHER_FUNCTION => {
            Err(NativeError::SdkError("Another operation running".into()))
        }

        // Communication errors
        XSDK_ERRCODE_COMMUNICATION => {
            Err(NativeError::SdkError("USB/WiFi communication error".into()))
        }
        XSDK_ERRCODE_TIMEOUT => Err(NativeError::Timeout("Operation timeout".into())),
        XSDK_ERRCODE_COMBINATION => Err(NativeError::InvalidParameter(
            "Invalid parameter combination".into(),
        )),
        XSDK_ERRCODE_WRITEERROR => Err(NativeError::SdkError("Write error".into())),
        XSDK_ERRCODE_CARDFULL => Err(NativeError::SdkError("Memory card full".into())),

        // Hardware/internal errors
        XSDK_ERRCODE_HARDWARE => Err(NativeError::SdkError("Camera hardware error".into())),
        XSDK_ERRCODE_INTERNAL => Err(NativeError::SdkError("Internal SDK error".into())),
        XSDK_ERRCODE_MEMFULL => Err(NativeError::SdkError("SDK memory allocation failed".into())),
        XSDK_ERRCODE_UNKNOWN => Err(NativeError::SdkError("Unknown error".into())),

        _ => Err(NativeError::SdkError(format!(
            "XAPI error: API=0x{:04X}, ERR=0x{:08X}",
            api_code, err_code
        ))),
    }
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/// Safely convert C string array to Rust String
fn cstr_to_string(arr: &[c_char; 256]) -> String {
    let bytes: Vec<u8> = arr
        .iter()
        .take_while(|&&c| c != 0)
        .map(|&c| c as u8)
        .collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

fn cstr_to_string_32(arr: &[c_char; 32]) -> String {
    let bytes: Vec<u8> = arr
        .iter()
        .take_while(|&&c| c != 0)
        .map(|&c| c as u8)
        .collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

// =============================================================================
// DEVICE DISCOVERY
// =============================================================================

/// Information about a discovered Fujifilm device
pub struct FujifilmDeviceInfo {
    pub name: String,
    pub serial_number: Option<String>,
    pub firmware_version: Option<String>,
    pub model: FujifilmModel,
    pub connection_type: String,
}

/// Discover all connected Fujifilm cameras
pub async fn discover_devices() -> Result<Vec<FujifilmDeviceInfo>, NativeError> {
    let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
    let _lock = fujifilm_mutex().lock().await;

    // Initialize SDK (ignore "already initialized" error)
    let _ = unsafe { (sdk.init)(std::ptr::null_mut()) };

    let mut devices = Vec::new();

    // Step 1: Detect USB devices with retry logic
    let mut count: c_long = 0;
    for attempt in 1..=3 {
        let result = unsafe {
            (sdk.detect)(
                XSDK_DSC_IF_USB,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                &mut count,
            )
        };
        if result == XSDK_COMPLETE && count > 0 {
            break;
        }
        if attempt < 3 {
            tokio::time::sleep(Duration::from_millis(100 * (1 << attempt))).await;
        }
    }

    if count == 0 {
        return Ok(devices);
    }

    // Step 2: Get camera list
    let mut camera_list = vec![XsdkCameraList::default(); count as usize];
    let mut actual_count: c_long = 0;
    let result = unsafe {
        (sdk.append)(
            XSDK_DSC_IF_USB,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &mut actual_count,
            camera_list.as_mut_ptr(),
        )
    };

    if result != XSDK_COMPLETE {
        return Err(NativeError::SdkError("XSDK_Append failed".into()));
    }

    // Step 3: Convert to FujifilmDeviceInfo
    for i in 0..actual_count as usize {
        let cam = &camera_list[i];
        if !cam.b_valid {
            continue;
        }

        let name = cstr_to_string(&cam.str_product);
        let serial = cstr_to_string(&cam.str_serial_no);
        let framework = cstr_to_string(&cam.str_framework);

        devices.push(FujifilmDeviceInfo {
            name: name.clone(),
            serial_number: if serial.is_empty() {
                None
            } else {
                Some(serial)
            },
            firmware_version: None,
            model: FujifilmModel::from_product_name(&name),
            connection_type: framework,
        });
    }

    Ok(devices)
}

// =============================================================================
// FUJIFILM CAMERA IMPLEMENTATION
// =============================================================================

/// Wrapper for camera handle to implement Send/Sync
/// SAFETY: The SDK mutex ensures exclusive access, making it safe to send between threads
struct HandleWrapper(XsdkHandle);
unsafe impl Send for HandleWrapper {}
unsafe impl Sync for HandleWrapper {}

impl std::fmt::Debug for HandleWrapper {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "HandleWrapper({:p})", self.0)
    }
}

/// Fujifilm camera driver
#[derive(Debug)]
pub struct FujifilmCamera {
    // Device identification
    id: String,
    name: String,
    serial_number: String,
    model: FujifilmModel,

    // Connection state
    connected: bool,
    camera_handle: HandleWrapper,

    // Camera properties
    firmware_version: String,
    sensor_info: SensorInfo,

    // Exposure state
    is_exposing: bool,
    is_bulb_mode: bool,
    exposure_start: Option<Instant>,
    exposure_duration: Duration,

    // Live view state
    live_view_active: bool,

    // Focus control state
    has_focus_control: bool,
    focus_min: i32,
    focus_max: i32,

    // Current settings
    current_iso: i32,
    current_offset: i32,
    supported_isos: Vec<c_long>,
    supports_bulb: bool,
}

impl FujifilmCamera {
    /// Create a new Fujifilm camera instance
    pub fn new(device_info: &FujifilmDeviceInfo) -> Self {
        let serial = device_info
            .serial_number
            .clone()
            .unwrap_or_else(|| device_info.name.clone());
        let (width, height, pixel_size, bit_depth) = device_info.model.sensor_specs();

        Self {
            id: format!("native:fujifilm:{}", serial),
            name: device_info.name.clone(),
            serial_number: serial,
            model: device_info.model,
            connected: false,
            camera_handle: HandleWrapper(std::ptr::null_mut()),
            firmware_version: String::new(),
            sensor_info: SensorInfo {
                width,
                height,
                pixel_size_x: pixel_size,
                pixel_size_y: pixel_size,
                max_adu: (1 << bit_depth) - 1,
                bit_depth,
                color: true,
                bayer_pattern: if device_info.model.is_xtrans() {
                    None // X-Trans is not Bayer
                } else {
                    Some(BayerPattern::Rggb) // GFX uses standard Bayer
                },
            },
            is_exposing: false,
            is_bulb_mode: false,
            exposure_start: None,
            exposure_duration: Duration::ZERO,
            live_view_active: false,
            has_focus_control: false,
            focus_min: 0,
            focus_max: 0,
            current_iso: 800,
            current_offset: 0,
            supported_isos: Vec::new(),
            supports_bulb: true,
        }
    }

    /// Start a bulb exposure
    async fn start_bulb_exposure(&mut self, duration_secs: f64) -> Result<(), NativeError> {
        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let mut shot_opt: c_long = 0;
        let mut af_status: c_long = 0;

        // Set shutter to BULB mode
        unsafe { (sdk.set_shutter_speed)(self.camera_handle.0, XSDK_SHUTTER_BULB, 0) };
        tokio::time::sleep(Duration::from_millis(100)).await;

        // Start bulb: Half-press (S1ON)
        let result = unsafe {
            (sdk.release)(
                self.camera_handle.0,
                XSDK_RELEASE_S1ON,
                &mut shot_opt,
                &mut af_status,
            )
        };
        if result != XSDK_COMPLETE {
            return check_xapi_error(self.camera_handle.0, sdk);
        }
        tokio::time::sleep(Duration::from_millis(50)).await;

        // Full press to open shutter (BULBS2_ON)
        let result = unsafe {
            (sdk.release)(
                self.camera_handle.0,
                XSDK_RELEASE_BULBS2_ON,
                &mut shot_opt,
                &mut af_status,
            )
        };
        if result != XSDK_COMPLETE {
            return check_xapi_error(self.camera_handle.0, sdk);
        }

        self.is_bulb_mode = true;
        self.exposure_start = Some(Instant::now());
        self.exposure_duration = Duration::from_secs_f64(duration_secs);
        self.is_exposing = true;

        Ok(())
    }

    /// Stop a bulb exposure
    async fn stop_bulb_exposure(&mut self) -> Result<(), NativeError> {
        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let mut shot_opt: c_long = 0;
        let mut af_status: c_long = 0;

        // End bulb: Release S2 and S1
        let result = unsafe {
            (sdk.release)(
                self.camera_handle.0,
                XSDK_RELEASE_N_BULBS1OFF,
                &mut shot_opt,
                &mut af_status,
            )
        };
        if result != XSDK_COMPLETE {
            return check_xapi_error(self.camera_handle.0, sdk);
        }

        self.is_bulb_mode = false;
        tokio::time::sleep(Duration::from_millis(100)).await;

        Ok(())
    }

    // =========================================================================
    // FOCUS CONTROL
    // =========================================================================

    /// Query focus capabilities from the lens
    ///
    /// Focus control requires:
    /// 1. Lens attached with electronic focus motor
    /// 2. Camera/lens in MF mode (focus mode switch)
    ///
    /// This method queries the SDK for focus position range. If the lens supports
    /// electronic focus control, `has_focus_control` will be set to true and
    /// `focus_min`/`focus_max` will contain the valid range.
    pub async fn query_focus_capabilities(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        // Query focus position capabilities via get_prop
        // The SDK returns min position (near/MOD) and max position (infinity)
        let mut focus_min: c_long = 0;
        let mut focus_max: c_long = 0;
        let mut focus_cap: c_long = 0;

        // Use blocking operations to avoid raw pointer issues across await points
        let result = unsafe {
            (sdk.get_prop)(
                self.camera_handle.0,
                API_CODE_CAP_FOCUS_POS,
                0, // lApiParam
                &mut focus_min,
                &mut focus_max,
                &mut focus_cap,
            )
        };

        if result == XSDK_COMPLETE && focus_cap != 0 {
            self.has_focus_control = true;
            self.focus_min = focus_min as i32;
            self.focus_max = focus_max as i32;
            tracing::info!(
                "Focus control available: range [{}, {}]",
                self.focus_min,
                self.focus_max
            );
        } else {
            self.has_focus_control = false;
            self.focus_min = 0;
            self.focus_max = 0;
            tracing::debug!("Focus control not available (no electronic lens or not in MF mode)");
        }

        Ok(())
    }

    /// Get the current focus position
    ///
    /// Returns the current focus motor position within the range [focus_min, focus_max].
    /// Returns an error if focus control is not available.
    pub async fn get_focus_position(&self) -> Result<i32, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.has_focus_control {
            return Err(NativeError::NotSupported);
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        let mut pos: c_long = 0;
        let result = unsafe {
            (sdk.get_prop)(
                self.camera_handle.0,
                API_CODE_GET_FOCUS_POS,
                0, // lApiParam
                &mut pos,
            )
        };

        if result != XSDK_COMPLETE {
            check_xapi_error(self.camera_handle.0, sdk)?;
            // If check_xapi_error didn't return an error, return a generic one
            return Err(NativeError::SdkError("Failed to get focus position".into()));
        }

        Ok(pos as i32)
    }

    /// Set the focus position
    ///
    /// Moves the focus motor to the specified position. The position must be within
    /// the range [focus_min, focus_max] as reported by `query_focus_capabilities`.
    ///
    /// Note: This method uses blocking sleep (std::thread::sleep) for the motor
    /// settling delay to avoid raw pointer issues across await points.
    ///
    /// # Arguments
    /// * `position` - Target focus position (must be in range [focus_min, focus_max])
    pub async fn set_focus_position(&mut self, position: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.has_focus_control {
            return Err(NativeError::NotSupported);
        }

        // Validate position is within range
        if position < self.focus_min || position > self.focus_max {
            return Err(NativeError::InvalidParameter(format!(
                "Focus position {} out of range [{}, {}]",
                position, self.focus_min, self.focus_max
            )));
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        let result = unsafe {
            (sdk.set_prop)(
                self.camera_handle.0,
                API_CODE_SET_FOCUS_POS,
                0, // lApiParam
                position as c_long,
            )
        };

        if result != XSDK_COMPLETE {
            return check_xapi_error(self.camera_handle.0, sdk);
        }

        // Use blocking sleep to allow focus motor to settle
        // (avoid raw pointer across await point)
        std::thread::sleep(Duration::from_millis(200));

        tracing::debug!("Focus position set to {}", position);
        Ok(())
    }

    /// Check if focus control is available
    ///
    /// Returns true if the attached lens supports electronic focus control
    /// and the camera is in MF mode. Call `query_focus_capabilities` first
    /// to populate this value.
    pub fn has_focus_control(&self) -> bool {
        self.has_focus_control
    }

    /// Get the focus position range
    ///
    /// Returns (min, max) focus positions, or (0, 0) if focus control is not available.
    pub fn get_focus_range(&self) -> (i32, i32) {
        (self.focus_min, self.focus_max)
    }

    // =========================================================================
    // LIVE VIEW METHODS
    // =========================================================================

    /// Start live view streaming
    ///
    /// Live view frames can be retrieved via `read_live_view_frame()`.
    /// The frames are JPEG data at the configured quality/size.
    ///
    /// Note: This method uses blocking sleep (std::thread::sleep) between SDK calls
    /// to avoid raw pointer issues across await points.
    ///
    /// # Arguments
    ///
    /// * `quality` - The live view quality setting (Fine, Normal, or Basic)
    ///
    /// # Returns
    ///
    /// `Ok(())` if live view started successfully, or an error if it failed.
    pub async fn start_live_view(&mut self, quality: LiveViewQuality) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if self.live_view_active {
            // Already active, just return success
            return Ok(());
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        // Copy handle to local variable to avoid packed struct issues across FFI calls
        let handle = self.camera_handle.0;

        // Set quality via XSDK_SetProp(hCamera, API_CODE, 0, value)
        let quality_code = quality.to_sdk_code();
        let result = unsafe {
            (sdk.set_prop)(
                handle,
                API_CODE_SET_LIVE_VIEW_IMAGE_QUALITY,
                0,
                quality_code,
            )
        };
        if result != XSDK_COMPLETE {
            tracing::warn!("Failed to set live view quality: {}", result);
            // Continue anyway, some cameras may not support quality setting
        }

        // Use blocking sleep to avoid raw pointer across await issues
        std::thread::sleep(Duration::from_millis(50));

        // Set size (use Large for best framing assistance in astrophotography)
        let result = unsafe {
            (sdk.set_prop)(
                handle,
                API_CODE_SET_LIVE_VIEW_IMAGE_SIZE,
                0,
                SDK_LIVEVIEW_SIZE_L,
            )
        };
        if result != XSDK_COMPLETE {
            tracing::warn!("Failed to set live view size: {}", result);
            // Continue anyway, some cameras may not support size setting
        }

        std::thread::sleep(Duration::from_millis(50));

        // Start live view
        let result = unsafe { (sdk.set_prop)(handle, API_CODE_START_LIVE_VIEW, 0) };
        if result != XSDK_COMPLETE {
            return Err(NativeError::SdkError(format!(
                "Failed to start live view: SDK returned {}",
                result
            )));
        }

        self.live_view_active = true;
        tracing::info!("Fujifilm live view started with quality {:?}", quality);

        Ok(())
    }

    /// Read a live view frame from the camera
    ///
    /// Returns the raw JPEG data of the current live view frame.
    /// This should be called repeatedly to get streaming frames.
    ///
    /// Note: This method copies packed struct fields to local variables before
    /// using them to avoid undefined behavior with misaligned reads.
    ///
    /// # Returns
    ///
    /// `Ok(Vec<u8>)` containing JPEG data, or an error if no frame is available.
    pub async fn read_live_view_frame(&self) -> Result<Vec<u8>, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.live_view_active {
            return Err(NativeError::SdkError("Live view is not active".into()));
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        // Copy handle to local variable for safety
        let handle = self.camera_handle.0;

        // Live view frames come through ReadImageInfo with XSDK_IMAGEFORMAT_LIVE
        let mut img_info = XsdkImageInformation::default();
        let result = unsafe { (sdk.read_image_info)(handle, &mut img_info) };

        // Copy packed struct fields to local variables before using them
        let img_format = img_info.l_format;
        let data_size = img_info.l_data_size;

        if result != XSDK_COMPLETE {
            return Err(NativeError::SdkError(
                "Failed to read live view frame info".into(),
            ));
        }

        if img_format != XSDK_IMAGEFORMAT_LIVE {
            return Err(NativeError::SdkError(format!(
                "Expected live view format ({}), got format {}",
                XSDK_IMAGEFORMAT_LIVE, img_format
            )));
        }

        if data_size <= 0 {
            return Err(NativeError::SdkError("No live view frame available".into()));
        }

        let buffer_size = data_size as usize;
        let mut buffer = vec![0u8; buffer_size];
        let result =
            unsafe { (sdk.read_image)(handle, buffer.as_mut_ptr(), buffer_size as c_ulong) };

        if result != XSDK_COMPLETE {
            return Err(NativeError::SdkError(
                "Failed to read live view frame data".into(),
            ));
        }

        // Delete the image from the buffer to make room for the next frame
        unsafe { (sdk.delete_image)(handle) };

        Ok(buffer) // Returns JPEG data
    }

    /// Stop live view streaming
    ///
    /// # Returns
    ///
    /// `Ok(())` if live view stopped successfully, or an error if it failed.
    pub async fn stop_live_view(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.live_view_active {
            // Not active, just return success
            return Ok(());
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        // Copy handle to local variable for safety
        let handle = self.camera_handle.0;

        let result = unsafe { (sdk.set_prop)(handle, API_CODE_STOP_LIVE_VIEW, 0) };

        if result != XSDK_COMPLETE {
            tracing::warn!("Failed to stop live view cleanly: SDK returned {}", result);
            // Still mark as inactive even if the SDK call failed
        }

        self.live_view_active = false;
        tracing::info!("Fujifilm live view stopped");

        Ok(())
    }

    /// Check if live view is currently active
    pub fn is_live_view_active(&self) -> bool {
        self.live_view_active
    }
}

// =============================================================================
// TRAIT IMPLEMENTATIONS
// =============================================================================

#[async_trait]
impl NativeDevice for FujifilmCamera {
    fn id(&self) -> &str {
        &self.id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Fujifilm
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        // 1. Initialize SDK
        let result = unsafe { (sdk.init)(std::ptr::null_mut()) };
        if result != XSDK_COMPLETE {
            let mut api_code: c_long = 0;
            let mut err_code: c_long = 0;
            unsafe { (sdk.get_error_number)(std::ptr::null_mut(), &mut api_code, &mut err_code) };
            if err_code != XSDK_ERRCODE_LOADLIB {
                return Err(NativeError::SdkError(format!(
                    "XSDK_Init failed: 0x{:08X}",
                    err_code
                )));
            }
        }

        // 2. Open connection (using blocking sleep to avoid raw pointer across await)
        let serial_cstr = CString::new(self.serial_number.clone())
            .map_err(|_| NativeError::InvalidParameter("Invalid serial number".into()))?;

        let camera_handle = {
            let mut handle: XsdkHandle = std::ptr::null_mut();
            let mut camera_mode: c_long = 0;

            for attempt in 1..=3 {
                let result = unsafe {
                    (sdk.open_ex)(
                        serial_cstr.as_ptr(),
                        &mut handle,
                        &mut camera_mode,
                        std::ptr::null_mut(),
                    )
                };
                if result == XSDK_COMPLETE {
                    break;
                }
                if attempt == 3 {
                    return Err(NativeError::SdkError(
                        "XSDK_OpenEx failed after 3 attempts".into(),
                    ));
                }
                // Use blocking sleep here to avoid raw pointer across await
                std::thread::sleep(Duration::from_millis(100 * (1 << attempt)));
            }
            handle
        };
        self.camera_handle = HandleWrapper(camera_handle);

        // 3. Set PC priority mode
        unsafe { (sdk.set_priority_mode)(camera_handle, XSDK_PRIORITY_PC) };
        std::thread::sleep(Duration::from_millis(100));

        // 4. CRITICAL: Set dynamic range to 100 BEFORE ISO operations
        unsafe { (sdk.set_dynamic_range)(camera_handle, XSDK_DR_100) };
        std::thread::sleep(Duration::from_millis(100));

        // 5. Query device information
        let mut dev_info = XsdkDeviceInformation::default();
        unsafe { (sdk.get_device_info)(camera_handle, &mut dev_info) };
        self.firmware_version = cstr_to_string(&dev_info.str_firmware);

        // Update model from actual device info
        let actual_name = cstr_to_string(&dev_info.str_product);
        if !actual_name.is_empty() {
            self.model = FujifilmModel::from_product_name(&actual_name);
            let (width, height, pixel_size, bit_depth) = self.model.sensor_specs();
            self.sensor_info.width = width;
            self.sensor_info.height = height;
            self.sensor_info.pixel_size_x = pixel_size;
            self.sensor_info.pixel_size_y = pixel_size;
            self.sensor_info.bit_depth = bit_depth;
            self.sensor_info.max_adu = (1 << bit_depth) - 1;
        }

        // 6. Query ISO capabilities
        let mut iso_count: c_long = 0;
        let mut iso_values: [c_long; 64] = [0; 64];
        unsafe { (sdk.cap_sensitivity)(camera_handle, &mut iso_count, iso_values.as_mut_ptr()) };
        self.supported_isos = iso_values[..iso_count as usize].to_vec();

        // 7. Query shutter speed capabilities
        let mut ss_count: c_long = 0;
        let mut ss_values: [c_long; 128] = [0; 128];
        let mut bulb_capable: c_long = 0;
        unsafe {
            (sdk.cap_shutter_speed)(
                camera_handle,
                &mut ss_count,
                ss_values.as_mut_ptr(),
                &mut bulb_capable,
            )
        };
        self.supports_bulb = bulb_capable != 0;

        // 8. Get current ISO
        let mut current_iso: c_long = 0;
        unsafe { (sdk.get_sensitivity)(camera_handle, &mut current_iso) };
        self.current_iso = current_iso as i32;

        self.connected = true;
        tracing::info!(
            "Connected to Fujifilm {} ({})",
            self.name,
            self.firmware_version
        );

        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Ok(());
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        // Stop any ongoing exposure
        if self.is_bulb_mode {
            let _ = self.stop_bulb_exposure().await;
        }

        // Close camera connection
        unsafe { (sdk.close)(self.camera_handle.0) };

        self.camera_handle = HandleWrapper(std::ptr::null_mut());
        self.connected = false;
        self.is_exposing = false;
        self.is_bulb_mode = false;

        tracing::info!("Disconnected from Fujifilm {}", self.name);

        Ok(())
    }
}

#[async_trait]
impl NativeCamera for FujifilmCamera {
    fn capabilities(&self) -> CameraCapabilities {
        CameraCapabilities {
            can_cool: false,        // No cooling in mirrorless
            can_set_gain: true,     // ISO control
            can_set_offset: false,  // No offset control
            can_set_binning: false, // No binning in DSLR/mirrorless
            can_subframe: false,    // Full sensor only
            has_shutter: true,      // Mechanical shutter
            has_guider_port: false, // No ST-4
            max_bin_x: 1,
            max_bin_y: 1,
            supports_readout_modes: false,
        }
    }

    async fn get_status(&self) -> Result<CameraStatus, NativeError> {
        let state = if self.is_exposing {
            CameraState::Exposing
        } else {
            CameraState::Idle
        };

        let exposure_remaining = if self.is_exposing {
            self.exposure_start.map(|start| {
                let elapsed = start.elapsed();
                (self.exposure_duration.as_secs_f64() - elapsed.as_secs_f64()).max(0.0)
            })
        } else {
            None
        };

        Ok(CameraStatus {
            state,
            sensor_temp: None,
            cooler_power: None,
            target_temp: None,
            cooler_on: false,
            gain: self.current_iso,
            offset: self.current_offset,
            bin_x: 1,
            bin_y: 1,
            exposure_remaining,
        })
    }

    async fn start_exposure(&mut self, params: ExposureParams) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        // 1. Set ISO if specified
        if let Some(gain) = params.gain {
            unsafe { (sdk.set_sensitivity)(self.camera_handle.0, gain as c_long) };
            self.current_iso = gain;
            tokio::time::sleep(Duration::from_millis(100)).await;
        }

        // 2. Determine if bulb mode needed (> 60s)
        if params.duration_secs > 60.0 {
            // Need to drop the lock before calling start_bulb_exposure
            drop(_lock);
            return self.start_bulb_exposure(params.duration_secs).await;
        }

        // 3. Set shutter speed code
        let shutter_code = find_shutter_code(params.duration_secs);
        unsafe { (sdk.set_shutter_speed)(self.camera_handle.0, shutter_code, 0) };
        tokio::time::sleep(Duration::from_millis(100)).await;

        // 4. Trigger capture
        let mut shot_opt: c_long = 0;
        let mut af_status: c_long = 0;
        let result = unsafe {
            (sdk.release)(
                self.camera_handle.0,
                XSDK_RELEASE_SHOOT_S1OFF,
                &mut shot_opt,
                &mut af_status,
            )
        };

        if result != XSDK_COMPLETE {
            return check_xapi_error(self.camera_handle.0, sdk);
        }

        self.exposure_start = Some(Instant::now());
        self.exposure_duration = Duration::from_secs_f64(params.duration_secs);
        self.is_exposing = true;

        Ok(())
    }

    async fn abort_exposure(&mut self) -> Result<(), NativeError> {
        if self.is_bulb_mode {
            self.stop_bulb_exposure().await?;
        }

        self.is_exposing = false;
        self.exposure_start = None;

        Ok(())
    }

    async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
        if !self.is_exposing {
            return Ok(true);
        }

        if let Some(start) = self.exposure_start {
            Ok(start.elapsed() >= self.exposure_duration)
        } else {
            Ok(true)
        }
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        // End bulb if active
        if self.is_bulb_mode {
            // Need to drop the lock temporarily
            drop(_lock);
            self.stop_bulb_exposure().await?;
            let _lock = fujifilm_mutex().lock().await;
        }

        // Poll for image ready (using blocking sleep to avoid packed struct across await)
        let mut img_info = XsdkImageInformation::default();
        for attempt in 1..=30 {
            let result = unsafe { (sdk.read_image_info)(self.camera_handle.0, &mut img_info) };
            // Copy fields from packed struct before checking
            let data_size = img_info.l_data_size;
            if result == XSDK_COMPLETE && data_size > 0 {
                break;
            }
            if attempt == 30 {
                return Err(NativeError::Timeout(
                    "Image not ready after 15 seconds".into(),
                ));
            }
            std::thread::sleep(Duration::from_millis(500));
        }

        // Copy packed fields to local variables for safe access
        let img_format = img_info.l_format;
        let data_size = img_info.l_data_size as usize;

        // Verify we got RAW format
        if img_format != XSDK_IMAGEFORMAT_RAW {
            tracing::warn!("Expected RAW format (1), got format {}", img_format);
        }

        // Download image data (RAF format)
        let mut buffer = vec![0u8; data_size];
        let result = unsafe {
            (sdk.read_image)(
                self.camera_handle.0,
                buffer.as_mut_ptr(),
                data_size as c_ulong,
            )
        };

        if result != XSDK_COMPLETE {
            check_xapi_error(self.camera_handle.0, sdk)?;
            return Err(NativeError::SdkError("Image download failed".into()));
        }

        // Clear camera buffer
        unsafe { (sdk.delete_image)(self.camera_handle.0) };

        self.is_exposing = false;

        // Process RAF file with LibRaw
        let (width, height, data) = process_raf_buffer(&buffer, self.model.is_xtrans())?;

        let metadata = ImageMetadata {
            exposure_time: self.exposure_duration.as_secs_f64(),
            gain: self.current_iso,
            offset: self.current_offset,
            bin_x: 1,
            bin_y: 1,
            temperature: None,
            timestamp: chrono::Utc::now(),
            subframe: None,
            readout_mode: None,
            vendor_data: VendorFeatures::default(),
        };

        Ok(ImageData {
            width,
            height,
            data,
            bits_per_pixel: self.sensor_info.bit_depth,
            bayer_pattern: self.sensor_info.bayer_pattern,
            metadata,
        })
    }

    async fn set_cooler(&mut self, _enabled: bool, _target_temp: f64) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_temperature(&self) -> Result<f64, NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_cooler_power(&self) -> Result<f64, NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = FujifilmSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = fujifilm_mutex().lock().await;

        unsafe { (sdk.set_sensitivity)(self.camera_handle.0, gain as c_long) };
        self.current_iso = gain;
        tokio::time::sleep(Duration::from_millis(100)).await;

        Ok(())
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        Ok(self.current_iso)
    }

    async fn set_offset(&mut self, _offset: i32) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        Ok(0)
    }

    async fn set_binning(&mut self, _bin_x: i32, _bin_y: i32) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    fn get_sensor_info(&self) -> SensorInfo {
        self.sensor_info.clone()
    }

    async fn get_binning(&self) -> Result<(i32, i32), NativeError> {
        Ok((1, 1)) // Fujifilm cameras don't support binning
    }

    async fn set_subframe(&mut self, _subframe: Option<SubFrame>) -> Result<(), NativeError> {
        Err(NativeError::NotSupported) // Full frame only
    }

    async fn get_readout_modes(&self) -> Result<Vec<ReadoutMode>, NativeError> {
        Ok(vec![])
    }

    async fn set_readout_mode(&mut self, _mode: &ReadoutMode) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
        Ok(VendorFeatures::default())
    }

    async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
        // Return ISO range based on supported ISOs
        if self.supported_isos.is_empty() {
            // Default Fujifilm ISO range if not queried
            Ok((100, 12800))
        } else {
            let min = self.supported_isos.iter().min().copied().unwrap_or(100) as i32;
            let max = self.supported_isos.iter().max().copied().unwrap_or(12800) as i32;
            Ok((min, max))
        }
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        Err(NativeError::NotSupported) // Fujifilm cameras don't support offset
    }
}

// =============================================================================
// RAF PROCESSING
// =============================================================================

/// Process RAF buffer and convert to 16-bit image data
fn process_raf_buffer(
    buffer: &[u8],
    _is_xtrans: bool,
) -> Result<(u32, u32, Vec<u16>), NativeError> {
    // Write to temp file for LibRaw processing
    let temp_path = std::env::temp_dir().join(format!("fuji_raw_{}.raf", std::process::id()));
    std::fs::write(&temp_path, buffer)
        .map_err(|e| NativeError::SdkError(format!("Failed to write temp RAF file: {}", e)))?;

    // Use LibRaw to process
    // For now, use nightshade_imaging if available, otherwise return error
    let result = process_raf_with_libraw(&temp_path);

    // Cleanup temp file
    let _ = std::fs::remove_file(&temp_path);

    result
}

/// Process RAF file with LibRaw
fn process_raf_with_libraw(path: &std::path::Path) -> Result<(u32, u32, Vec<u16>), NativeError> {
    // Try to use nightshade_imaging's LibRaw integration
    // Use DHT demosaic for best X-Trans quality
    let params = nightshade_imaging::RawProcessingParams {
        output_bps: 16, // 16-bit output
        ..Default::default()
    };

    match nightshade_imaging::read_raw(path, Some(&params)) {
        Ok((image_data, _metadata)) => {
            // Convert ImageData to Vec<u16>
            // ImageData stores bytes, need to convert to u16
            let u16_data = if let Some(data) = image_data.as_u16() {
                data
            } else {
                // Fallback: convert raw bytes to u16
                image_data
                    .data
                    .chunks_exact(2)
                    .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                    .collect()
            };

            Ok((image_data.width, image_data.height, u16_data))
        }
        Err(e) => Err(NativeError::SdkError(format!(
            "LibRaw processing failed: {}",
            e
        ))),
    }
}

// =============================================================================
// UNIT TESTS
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // =========================================================================
    // MODEL DETECTION TESTS
    // =========================================================================

    #[test]
    fn test_model_from_product_name_x_series() {
        // X-T series
        assert_eq!(FujifilmModel::from_product_name("X-T5"), FujifilmModel::XT5);
        assert_eq!(FujifilmModel::from_product_name("XT5"), FujifilmModel::XT5);
        assert_eq!(
            FujifilmModel::from_product_name("FUJIFILM X-T5"),
            FujifilmModel::XT5
        );
        assert_eq!(FujifilmModel::from_product_name("X-T4"), FujifilmModel::XT4);
        assert_eq!(FujifilmModel::from_product_name("X-T3"), FujifilmModel::XT3);

        // X-H series
        assert_eq!(
            FujifilmModel::from_product_name("X-H2S"),
            FujifilmModel::XH2S
        );
        assert_eq!(
            FujifilmModel::from_product_name("XH2S"),
            FujifilmModel::XH2S
        );
        assert_eq!(FujifilmModel::from_product_name("X-H2"), FujifilmModel::XH2);
        assert_eq!(FujifilmModel::from_product_name("XH2"), FujifilmModel::XH2);

        // Other X-series
        assert_eq!(
            FujifilmModel::from_product_name("X-S20"),
            FujifilmModel::XS20
        );
        assert_eq!(
            FujifilmModel::from_product_name("X-S10"),
            FujifilmModel::XS10
        );
        assert_eq!(
            FujifilmModel::from_product_name("X-Pro3"),
            FujifilmModel::XPro3
        );
        assert_eq!(FujifilmModel::from_product_name("X-E4"), FujifilmModel::XE4);
        assert_eq!(FujifilmModel::from_product_name("X-M5"), FujifilmModel::XM5);

        // X100 series
        assert_eq!(
            FujifilmModel::from_product_name("X100V"),
            FujifilmModel::X100V
        );
        assert_eq!(
            FujifilmModel::from_product_name("X100VI"),
            FujifilmModel::X100VI
        );
    }

    #[test]
    fn test_model_from_product_name_gfx_series() {
        // GFX 100 series (102MP)
        assert_eq!(
            FujifilmModel::from_product_name("GFX100 II"),
            FujifilmModel::Gfx100II
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX 100 II"),
            FujifilmModel::Gfx100II
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX100S II"),
            FujifilmModel::Gfx100SII
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX 100S II"),
            FujifilmModel::Gfx100SII
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX100"),
            FujifilmModel::Gfx100
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX 100"),
            FujifilmModel::Gfx100
        );

        // GFX 50 series (51MP)
        assert_eq!(
            FujifilmModel::from_product_name("GFX 50S II"),
            FujifilmModel::Gfx50SII
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX50S II"),
            FujifilmModel::Gfx50SII
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX 50S"),
            FujifilmModel::Gfx50S
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX50S"),
            FujifilmModel::Gfx50S
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX 50R"),
            FujifilmModel::Gfx50R
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX50R"),
            FujifilmModel::Gfx50R
        );
    }

    #[test]
    fn test_model_from_product_name_unknown() {
        assert_eq!(
            FujifilmModel::from_product_name("Unknown Camera"),
            FujifilmModel::Unknown
        );
        assert_eq!(
            FujifilmModel::from_product_name("Sony A7IV"),
            FujifilmModel::Unknown
        );
        assert_eq!(FujifilmModel::from_product_name(""), FujifilmModel::Unknown);
        assert_eq!(
            FujifilmModel::from_product_name("Random String"),
            FujifilmModel::Unknown
        );
    }

    #[test]
    fn test_model_from_product_name_case_insensitive() {
        // Should work with any case
        assert_eq!(FujifilmModel::from_product_name("x-t5"), FujifilmModel::XT5);
        assert_eq!(FujifilmModel::from_product_name("X-T5"), FujifilmModel::XT5);
        assert_eq!(
            FujifilmModel::from_product_name("x-h2s"),
            FujifilmModel::XH2S
        );
        assert_eq!(
            FujifilmModel::from_product_name("gfx100 ii"),
            FujifilmModel::Gfx100II
        );
        assert_eq!(
            FujifilmModel::from_product_name("GFX100 II"),
            FujifilmModel::Gfx100II
        );
    }

    // =========================================================================
    // SENSOR SPECS TESTS
    // =========================================================================

    #[test]
    fn test_sensor_specs_40mp_xtrans() {
        // X-H2 and X-T5 share the same 40MP X-Trans sensor
        let (w, h, pixel_size, bit_depth) = FujifilmModel::XH2.sensor_specs();
        assert_eq!(w, 9728, "X-H2 width should be 9728");
        assert_eq!(h, 7296, "X-H2 height should be 7296");
        assert_eq!(pixel_size, 3.0, "X-H2 pixel size should be 3.0um");
        assert_eq!(bit_depth, 14, "X-H2 bit depth should be 14");

        let (w, h, pixel_size, bit_depth) = FujifilmModel::XT5.sensor_specs();
        assert_eq!(w, 9728, "X-T5 width should be 9728");
        assert_eq!(h, 7296, "X-T5 height should be 7296");
        assert_eq!(pixel_size, 3.0, "X-T5 pixel size should be 3.0um");
        assert_eq!(bit_depth, 14, "X-T5 bit depth should be 14");

        // Verify total resolution is approximately 40MP (71 million pixels)
        let megapixels = (w as u64 * h as u64) as f64 / 1_000_000.0;
        assert!(
            (megapixels - 71.0).abs() < 1.0,
            "40MP sensor should have ~71 million pixels"
        );
    }

    #[test]
    fn test_sensor_specs_gfx100ii() {
        // GFX100 II has 102MP sensor
        let (w, h, pixel_size, bit_depth) = FujifilmModel::Gfx100II.sensor_specs();
        assert_eq!(w, 11648, "GFX100 II width should be 11648");
        assert_eq!(h, 8736, "GFX100 II height should be 8736");
        assert_eq!(pixel_size, 3.76, "GFX100 II pixel size should be 3.76um");
        assert_eq!(bit_depth, 14, "GFX100 II bit depth should be 14");

        // Verify total resolution is approximately 102MP
        let megapixels = (w as u64 * h as u64) as f64 / 1_000_000.0;
        assert!(
            (megapixels - 102.0).abs() < 2.0,
            "GFX100 II should have ~102 million pixels"
        );
    }

    #[test]
    fn test_sensor_specs_gfx50sii() {
        // GFX 50S II has 51MP sensor
        let (w, h, pixel_size, bit_depth) = FujifilmModel::Gfx50SII.sensor_specs();
        assert_eq!(w, 8256, "GFX 50S II width should be 8256");
        assert_eq!(h, 6192, "GFX 50S II height should be 6192");
        assert_eq!(pixel_size, 5.3, "GFX 50S II pixel size should be 5.3um");
        assert_eq!(bit_depth, 14, "GFX 50S II bit depth should be 14");

        // Verify total resolution is approximately 51MP
        let megapixels = (w as u64 * h as u64) as f64 / 1_000_000.0;
        assert!(
            (megapixels - 51.0).abs() < 2.0,
            "GFX 50S II should have ~51 million pixels"
        );
    }

    #[test]
    fn test_sensor_specs_26mp_xtrans() {
        // X-H2S has 26MP stacked X-Trans sensor
        let (w, h, pixel_size, bit_depth) = FujifilmModel::XH2S.sensor_specs();
        assert_eq!(w, 6240, "X-H2S width should be 6240");
        assert_eq!(h, 4160, "X-H2S height should be 4160");
        assert_eq!(pixel_size, 3.76, "X-H2S pixel size should be 3.76um");
        assert_eq!(bit_depth, 14, "X-H2S bit depth should be 14");

        // Verify total resolution is approximately 26MP
        let megapixels = (w as u64 * h as u64) as f64 / 1_000_000.0;
        assert!(
            (megapixels - 26.0).abs() < 1.0,
            "X-H2S should have ~26 million pixels"
        );
    }

    #[test]
    fn test_sensor_specs_default_26mp() {
        // Unknown and other X-series default to 26MP X-Trans
        let (w, h, _, _) = FujifilmModel::Unknown.sensor_specs();
        assert_eq!(w, 6240);
        assert_eq!(h, 4160);

        let (w, h, _, _) = FujifilmModel::XT4.sensor_specs();
        assert_eq!(w, 6240);
        assert_eq!(h, 4160);

        let (w, h, _, _) = FujifilmModel::XS20.sensor_specs();
        assert_eq!(w, 6240);
        assert_eq!(h, 4160);
    }

    // =========================================================================
    // X-TRANS DETECTION TESTS
    // =========================================================================

    #[test]
    fn test_is_xtrans_x_series() {
        // All X-series cameras use X-Trans sensors
        assert!(FujifilmModel::XT5.is_xtrans(), "X-T5 should be X-Trans");
        assert!(FujifilmModel::XT4.is_xtrans(), "X-T4 should be X-Trans");
        assert!(FujifilmModel::XT3.is_xtrans(), "X-T3 should be X-Trans");
        assert!(FujifilmModel::XH2.is_xtrans(), "X-H2 should be X-Trans");
        assert!(FujifilmModel::XH2S.is_xtrans(), "X-H2S should be X-Trans");
        assert!(FujifilmModel::XS10.is_xtrans(), "X-S10 should be X-Trans");
        assert!(FujifilmModel::XS20.is_xtrans(), "X-S20 should be X-Trans");
        assert!(FujifilmModel::XPro3.is_xtrans(), "X-Pro3 should be X-Trans");
        assert!(FujifilmModel::XE4.is_xtrans(), "X-E4 should be X-Trans");
        assert!(FujifilmModel::XM5.is_xtrans(), "X-M5 should be X-Trans");
        assert!(FujifilmModel::X100V.is_xtrans(), "X100V should be X-Trans");
        assert!(
            FujifilmModel::X100VI.is_xtrans(),
            "X100VI should be X-Trans"
        );
    }

    #[test]
    fn test_is_xtrans_gfx_series_bayer() {
        // All GFX cameras use standard Bayer sensors (NOT X-Trans)
        assert!(
            !FujifilmModel::Gfx100.is_xtrans(),
            "GFX100 should NOT be X-Trans"
        );
        assert!(
            !FujifilmModel::Gfx100II.is_xtrans(),
            "GFX100 II should NOT be X-Trans"
        );
        assert!(
            !FujifilmModel::Gfx100SII.is_xtrans(),
            "GFX100S II should NOT be X-Trans"
        );
        assert!(
            !FujifilmModel::Gfx50R.is_xtrans(),
            "GFX 50R should NOT be X-Trans"
        );
        assert!(
            !FujifilmModel::Gfx50S.is_xtrans(),
            "GFX 50S should NOT be X-Trans"
        );
        assert!(
            !FujifilmModel::Gfx50SII.is_xtrans(),
            "GFX 50S II should NOT be X-Trans"
        );
    }

    #[test]
    fn test_is_xtrans_unknown() {
        // Unknown defaults to X-Trans (assumes X-series)
        assert!(
            FujifilmModel::Unknown.is_xtrans(),
            "Unknown should default to X-Trans"
        );
    }

    // =========================================================================
    // SHUTTER SPEED CODE MAPPING TESTS
    // =========================================================================

    #[test]
    fn test_find_shutter_code_exact_matches() {
        // Test exact shutter speed matches
        assert_eq!(
            find_shutter_code(1.0),
            1000000,
            "1 second should return 1000000"
        );
        assert_eq!(
            find_shutter_code(0.5),
            500000,
            "1/2 second should return 500000"
        );
        assert_eq!(
            find_shutter_code(30.0),
            32000000,
            "30 seconds should return 32000000"
        );
        assert_eq!(
            find_shutter_code(60.0),
            64000000,
            "60 seconds should return 64000000"
        );
        assert_eq!(
            find_shutter_code(2.0),
            2000000,
            "2 seconds should return 2000000"
        );
        assert_eq!(
            find_shutter_code(4.0),
            4000000,
            "4 seconds should return 4000000"
        );
        assert_eq!(
            find_shutter_code(8.0),
            8000000,
            "8 seconds should return 8000000"
        );
        assert_eq!(
            find_shutter_code(15.0),
            16000000,
            "15 seconds should return 16000000"
        );
    }

    #[test]
    fn test_find_shutter_code_bulb_mode() {
        // Exposures > 60 seconds should return BULB mode
        assert_eq!(
            find_shutter_code(61.0),
            XSDK_SHUTTER_BULB,
            "61s should trigger BULB mode"
        );
        assert_eq!(
            find_shutter_code(120.0),
            XSDK_SHUTTER_BULB,
            "120s should trigger BULB mode"
        );
        assert_eq!(
            find_shutter_code(300.0),
            XSDK_SHUTTER_BULB,
            "300s (5min) should trigger BULB mode"
        );
        assert_eq!(
            find_shutter_code(3600.0),
            XSDK_SHUTTER_BULB,
            "3600s (1hr) should trigger BULB mode"
        );
    }

    #[test]
    fn test_find_shutter_code_fast_speeds() {
        // Test fast shutter speeds (fractions of a second)
        assert_eq!(
            find_shutter_code(1.0 / 8000.0),
            122,
            "1/8000s should return 122"
        );
        assert_eq!(
            find_shutter_code(1.0 / 4000.0),
            244,
            "1/4000s should return 244"
        );
        assert_eq!(
            find_shutter_code(1.0 / 2000.0),
            488,
            "1/2000s should return 488"
        );
        assert_eq!(
            find_shutter_code(1.0 / 1000.0),
            976,
            "1/1000s should return 976"
        );
        assert_eq!(
            find_shutter_code(1.0 / 500.0),
            1953,
            "1/500s should return 1953"
        );
        assert_eq!(
            find_shutter_code(1.0 / 250.0),
            3906,
            "1/250s should return 3906"
        );
        assert_eq!(
            find_shutter_code(1.0 / 125.0),
            7812,
            "1/125s should return 7812"
        );
        assert_eq!(
            find_shutter_code(1.0 / 60.0),
            15625,
            "1/60s should return 15625"
        );
        assert_eq!(
            find_shutter_code(1.0 / 30.0),
            31250,
            "1/30s should return 31250"
        );
    }

    #[test]
    fn test_find_shutter_code_nearest_match() {
        // Test that we find the closest shutter speed for in-between values
        // 0.75s is between 0.5s (500000) and 1.0s (1000000), closer to 1.0s
        let code = find_shutter_code(0.75);
        assert!(
            code == 500000 || code == 1000000,
            "0.75s should match either 0.5s or 1.0s code"
        );

        // Very small values should match the fastest available speed
        let code = find_shutter_code(0.0001);
        assert_eq!(
            code, 122,
            "Very small values should match fastest speed (1/8000s)"
        );
    }

    #[test]
    fn test_shutter_bulb_constant() {
        // Verify BULB constant is -1 as per SDK spec
        assert_eq!(XSDK_SHUTTER_BULB, -1, "XSDK_SHUTTER_BULB should be -1");
    }

    // =========================================================================
    // ERROR CODE CONSTANT TESTS
    // =========================================================================

    #[test]
    fn test_error_codes_defined() {
        // Verify key error codes are defined correctly per XAPI.h
        assert_eq!(XSDK_ERRCODE_NOERR, 0x00000000, "No error code should be 0");
        assert_eq!(
            XSDK_ERRCODE_SEQUENCE, 0x00001001,
            "Sequence error code mismatch"
        );
        assert_eq!(
            XSDK_ERRCODE_PARAM, 0x00001002,
            "Parameter error code mismatch"
        );
        assert_eq!(
            XSDK_ERRCODE_INVALID_CAMERA, 0x00001003,
            "Invalid camera error code mismatch"
        );
        assert_eq!(
            XSDK_ERRCODE_LOADLIB, 0x00001004,
            "Load library error code mismatch"
        );
        assert_eq!(
            XSDK_ERRCODE_UNSUPPORTED, 0x00001005,
            "Unsupported error code mismatch"
        );
        assert_eq!(XSDK_ERRCODE_BUSY, 0x00001006, "Busy error code mismatch");
        assert_eq!(
            XSDK_ERRCODE_TIMEOUT, 0x00002002,
            "Timeout error code mismatch"
        );
        assert_eq!(
            XSDK_ERRCODE_COMMUNICATION, 0x00002001,
            "Communication error code mismatch"
        );
        assert_eq!(
            XSDK_ERRCODE_HARDWARE, 0x00003001,
            "Hardware error code mismatch"
        );
        assert_eq!(
            XSDK_ERRCODE_INTERNAL, 0x00009001,
            "Internal error code mismatch"
        );
        assert_eq!(
            XSDK_ERRCODE_UNKNOWN, 0x00009100,
            "Unknown error code mismatch"
        );
    }

    #[test]
    fn test_sdk_return_values() {
        // Verify SDK return value constants
        assert_eq!(XSDK_COMPLETE, 0, "XSDK_COMPLETE should be 0");
        assert_eq!(XSDK_ERROR, -1, "XSDK_ERROR should be -1");
    }

    // =========================================================================
    // SDK CONSTANT TESTS
    // =========================================================================

    #[test]
    fn test_connection_interface_constants() {
        assert_eq!(
            XSDK_DSC_IF_USB, 0x00000001,
            "USB interface constant mismatch"
        );
        assert_eq!(
            XSDK_DSC_IF_WIFI_LOCAL, 0x00000010,
            "WiFi local constant mismatch"
        );
        assert_eq!(XSDK_DSC_IF_WIFI_IP, 0x00000020, "WiFi IP constant mismatch");
    }

    #[test]
    fn test_priority_mode_constants() {
        assert_eq!(
            XSDK_PRIORITY_CAMERA, 0x0001,
            "Camera priority constant mismatch"
        );
        assert_eq!(XSDK_PRIORITY_PC, 0x0002, "PC priority constant mismatch");
    }

    #[test]
    fn test_release_mode_constants() {
        assert_eq!(
            XSDK_RELEASE_SHOOT, 0x0100,
            "Shoot release constant mismatch"
        );
        assert_eq!(XSDK_RELEASE_S1ON, 0x0200, "S1 ON release constant mismatch");
        assert_eq!(
            XSDK_RELEASE_BULBS2_ON, 0x0500,
            "Bulb S2 ON release constant mismatch"
        );
        assert_eq!(
            XSDK_RELEASE_N_BULBS1OFF, 0x000C,
            "Bulb S1 OFF release constant mismatch"
        );
        assert_eq!(
            XSDK_RELEASE_SHOOT_S1OFF, 0x0104,
            "Shoot S1 OFF release constant mismatch"
        );
    }

    #[test]
    fn test_image_format_constants() {
        assert_eq!(XSDK_IMAGEFORMAT_RAW, 1, "RAW format constant mismatch");
        assert_eq!(XSDK_IMAGEFORMAT_LIVE, 4, "Live format constant mismatch");
        assert_eq!(XSDK_IMAGEFORMAT_NONE, 5, "None format constant mismatch");
        assert_eq!(XSDK_IMAGEFORMAT_JPEG, 7, "JPEG format constant mismatch");
    }

    #[test]
    fn test_dynamic_range_constants() {
        assert_eq!(XSDK_DR_100, 100, "DR 100 constant mismatch");
        assert_eq!(XSDK_DR_200, 200, "DR 200 constant mismatch");
        assert_eq!(XSDK_DR_400, 400, "DR 400 constant mismatch");
    }
}
