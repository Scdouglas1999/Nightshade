//! ZWO ASI Camera SDK Wrapper
//!
//! Provides native support for ZWO ASI cameras by wrapping the ASI SDK.
//! The SDK is typically provided as a DLL (Windows) or shared library (macOS/Linux).
//!
//! ## Thread Safety
//!
//! The ASI SDK is NOT thread-safe. All SDK operations are protected by per-SDK
//! mutexes from `crate::sync`:
//! - `zwo_camera_mutex()` - ASI Camera SDK (ASICamera2.dll)
//! - `zwo_eaf_mutex()` - EAF Focuser SDK (EAF_focuser.dll)
//! - `zwo_efw_mutex()` - EFW Filter Wheel SDK (EFW_filter.dll)
//!
//! ## Timeout Handling
//!
//! All SDK operations that can potentially hang (exposure polling, image download,
//! focuser moves, filter wheel moves) have configurable timeouts via `NativeTimeoutConfig`.
//! Use the helper methods like `wait_for_exposure_complete`, `move_focuser_with_timeout`,
//! and `move_filterwheel_with_timeout` to ensure operations don't block indefinitely.

#![allow(dead_code)] // FFI types must match SDK headers even if not all variants are used

use crate::camera::*;
use crate::sync::{zwo_camera_mutex, zwo_eaf_mutex, zwo_efw_mutex};
use crate::traits::*;
use crate::utils::{
    calculate_buffer_size_i32, safe_cstr_to_string, wait_for_exposure, wait_for_filterwheel_move,
    wait_for_focuser_move, CleanupGuard,
};
use crate::NativeVendor;
use async_trait::async_trait;
use nightshade_imaging::buffer_pool::global_u8_pool;
use std::ffi::{c_char, c_int, c_long, c_uchar, CStr};
use std::sync::Mutex;

// =============================================================================
// ASI SDK TYPE DEFINITIONS
// =============================================================================

/// ASI Camera Info structure from SDK - matches ASI_CAMERA_INFO from ASICamera2.h
#[repr(C)]
#[derive(Debug, Clone)]
struct ASICameraInfo {
    name: [c_char; 64],                 // Name[64] - camera name
    camera_id: c_int,                   // CameraID - unique camera ID
    max_height: c_long,                 // MaxHeight - max height
    max_width: c_long,                  // MaxWidth - max width
    is_color_cam: c_int,                // IsColorCam (ASI_BOOL)
    bayer_pattern: c_int,               // BayerPattern (ASI_BAYER_PATTERN)
    supported_bins: [c_int; 16],        // SupportedBins[16] - ends with 0
    supported_video_format: [c_int; 8], // SupportedVideoFormat[8] - ends with ASI_IMG_END
    pixel_size: f64,                    // PixelSize (double) - in um
    mechanical_shutter: c_int,          // MechanicalShutter (ASI_BOOL)
    st4_port: c_int,                    // ST4Port (ASI_BOOL)
    is_cooler_cam: c_int,               // IsCoolerCam (ASI_BOOL)
    is_usb3_host: c_int,                // IsUSB3Host (ASI_BOOL)
    is_usb3_camera: c_int,              // IsUSB3Camera (ASI_BOOL)
    elec_per_adu: f32,                  // ElecPerADU (float)
    bit_depth: c_int,                   // BitDepth (int)
    is_trigger_cam: c_int,              // IsTriggerCam (ASI_BOOL)
    unused: [c_char; 16],               // Unused[16] - padding
}

/// ASI Exposure Status
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
enum ASIExposureStatus {
    Idle = 0,
    Working = 1,
    Success = 2,
    Failed = 3,
}

/// ASI Bool type
type ASIBool = c_int;
const ASI_FALSE: ASIBool = 0;
const ASI_TRUE: ASIBool = 1;

/// ASI Error codes - matches ASI_ERROR_CODE from ASICamera2.h
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
#[allow(non_camel_case_types, dead_code)]
enum ASIError {
    ASI_SUCCESS = 0,
    ASI_ERROR_INVALID_INDEX = 1, // no camera connected or index value out of boundary
    ASI_ERROR_INVALID_ID = 2,    // invalid ID
    ASI_ERROR_INVALID_CONTROL_TYPE = 3, // invalid control type
    ASI_ERROR_CAMERA_CLOSED = 4, // camera didn't open
    ASI_ERROR_CAMERA_REMOVED = 5, // failed to find the camera, maybe removed
    ASI_ERROR_INVALID_PATH = 6,  // cannot find the path of the file
    ASI_ERROR_INVALID_FILEFORMAT = 7,
    ASI_ERROR_INVALID_SIZE = 8,      // wrong video format size
    ASI_ERROR_INVALID_IMGTYPE = 9,   // unsupported image format
    ASI_ERROR_OUTOF_BOUNDARY = 10,   // the startpos is out of boundary
    ASI_ERROR_TIMEOUT = 11,          // timeout
    ASI_ERROR_INVALID_SEQUENCE = 12, // stop capture first
    ASI_ERROR_BUFFER_TOO_SMALL = 13, // buffer size is not big enough
    ASI_ERROR_VIDEO_MODE_ACTIVE = 14,
    ASI_ERROR_EXPOSURE_IN_PROGRESS = 15,
    ASI_ERROR_GENERAL_ERROR = 16, // general error, eg: value is out of valid range
    ASI_ERROR_INVALID_MODE = 17,  // the current mode is wrong
    ASI_ERROR_GPS_NOT_SUPPORTED = 18, // camera does not support GPS
    ASI_ERROR_GPS_VER_ERR = 19,   // FPGA GPS ver is too low
    ASI_ERROR_GPS_FPGA_ERR = 20,  // failed to read or write data to FPGA
    ASI_ERROR_GPS_PARAM_OUT_OF_RANGE = 21, // start line or end line out of range
    ASI_ERROR_GPS_DATA_INVALID = 22, // GPS has not yet found satellite
    ASI_ERROR_END = 23,
}

/// ASI Control types - matches ASI_CONTROL_TYPE enum from ASICamera2.h
#[repr(C)]
#[derive(Debug, Clone, Copy)]
#[allow(non_camel_case_types)]
enum ASIControlType {
    ASI_GAIN = 0,
    ASI_EXPOSURE = 1,
    ASI_GAMMA = 2,
    ASI_WB_R = 3,
    ASI_WB_B = 4,
    ASI_OFFSET = 5,
    ASI_BANDWIDTHOVERLOAD = 6,
    ASI_OVERCLOCK = 7,
    ASI_TEMPERATURE = 8, // returns 10*temperature
    ASI_FLIP = 9,
    ASI_AUTO_MAX_GAIN = 10,
    ASI_AUTO_MAX_EXP = 11, // micro second
    ASI_AUTO_TARGET_BRIGHTNESS = 12,
    ASI_HARDWARE_BIN = 13,
    ASI_HIGH_SPEED_MODE = 14,
    ASI_COOLER_POWER_PERC = 15,
    ASI_TARGET_TEMP = 16, // NOT multiplied by 10 (direct degrees C)
    ASI_COOLER_ON = 17,
    ASI_MONO_BIN = 18, // reduces grid at software bin for color camera
    ASI_FAN_ON = 19,
    ASI_PATTERN_ADJUST = 20,
    ASI_ANTI_DEW_HEATER = 21,
    ASI_FAN_ADJUST = 22,
    ASI_PWRLED_BRIGNT = 23,
    ASI_USBHUB_RESET = 24,
    ASI_GPS_SUPPORT = 25,
    ASI_GPS_START_LINE = 26,
    ASI_GPS_END_LINE = 27,
    ASI_ROLLING_INTERVAL = 28, // microsecond
}

/// ASI Image type
#[repr(C)]
#[derive(Debug, Clone, Copy)]
enum ASIImgType {
    Raw8 = 0,
    Rgb24 = 1,
    Raw16 = 2,
    Y8 = 3,
    End = -1,
}

/// ASI Flip Status
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
enum ASIFlipStatus {
    None = 0,
    Horiz = 1,
    Vert = 2,
    Both = 3,
}

/// ASI Control Capabilities
#[repr(C)]
#[derive(Debug, Clone)]
struct ASIControlCaps {
    name: [c_char; 64],
    description: [c_char; 128],
    max_value: c_long,
    min_value: c_long,
    default_value: c_long,
    is_auto_supported: ASIBool,
    is_writable: ASIBool,
    control_type: ASIControlType,
    unused: [c_char; 32],
}

/// ASI Bayer pattern
#[repr(C)]
#[derive(Debug, Clone, Copy)]
enum ASIBayerPattern {
    Rg = 0,
    Bg = 1,
    Gr = 2,
    Gb = 3,
}

// =============================================================================
// SDK LIBRARY LOADING
// =============================================================================
//
// Path search + library open + per-symbol resolution + OnceLock storage is
// delegated to the shared `vendor::sdk_loader` infrastructure via the
// `load_vendor_sdk!` macro. Adding a new ZWO SDK function pointer is now a
// single-line change in the `symbols: { ... }` block below.

use crate::load_vendor_sdk;
use std::path::PathBuf;

/// Build the ordered list of candidate paths for ASICamera2 (the ZWO camera SDK).
///
/// Windows has a richer search list because the SDK ships as a loose DLL that
/// users typically drop next to the executable or leave in the SDK installer's
/// default path. macOS/Linux rely on system library paths or the binary's
/// install prefix.
fn asi_candidate_paths() -> Vec<PathBuf> {
    let mut paths: Vec<PathBuf> = Vec::new();

    if cfg!(target_os = "windows") {
        paths.push(PathBuf::from("ASICamera2.dll"));
        paths.push(PathBuf::from(
            "C:\\Program Files\\ZWO\\ASI SDK\\lib\\x64\\ASICamera2.dll",
        ));
        paths.push(PathBuf::from(
            "C:\\Program Files (x86)\\ZWO\\ASI SDK\\lib\\x64\\ASICamera2.dll",
        ));

        if let Ok(exe_path) = std::env::current_exe() {
            if let Some(exe_dir) = exe_path.parent() {
                paths.push(exe_dir.join("ASICamera2.dll"));

                if let Some(parent) = exe_dir.parent() {
                    paths.push(parent.join("ASICamera2.dll"));
                    paths.push(
                        parent
                            .join("SDKs")
                            .join("ZWO")
                            .join("ASI_Camera_SDK")
                            .join("ASI_Windows_SDK_V1.40")
                            .join("ASI SDK")
                            .join("lib")
                            .join("x64")
                            .join("ASICamera2.dll"),
                    );
                }

                if let Some(grandparent) = exe_dir.parent().and_then(|p| p.parent()) {
                    paths.push(grandparent.join("ASICamera2.dll"));
                    paths.push(
                        grandparent
                            .join("SDKs")
                            .join("ZWO")
                            .join("ASI_Camera_SDK")
                            .join("ASI_Windows_SDK_V1.40")
                            .join("ASI SDK")
                            .join("lib")
                            .join("x64")
                            .join("ASICamera2.dll"),
                    );
                }
            }
        }
    } else if cfg!(target_os = "macos") {
        paths.push(PathBuf::from("libASICamera2.dylib"));
        paths.push(PathBuf::from("/usr/local/lib/libASICamera2.dylib"));
    } else {
        paths.push(PathBuf::from("libASICamera2.so"));
        paths.push(PathBuf::from("libASICamera2.so.1"));
        paths.push(PathBuf::from("/usr/lib/libASICamera2.so"));
        paths.push(PathBuf::from("/usr/local/lib/libASICamera2.so"));
    }

    paths
}

load_vendor_sdk! {
    /// ZWO ASI Camera SDK function-pointer table (ASICamera2.dll / libASICamera2.{so,dylib}).
    vendor_name: "ZWO ASI Camera",
    sdk_struct: AsiSdk,
    sdk_static: ASI_SDK,
    candidate_paths_fn: asi_candidate_paths,
    symbols: {
        get_num_cameras: b"ASIGetNumOfConnectedCameras\0"
            => unsafe extern "C" fn() -> c_int,
        // ASIGetCameraProperty(ASI_CAMERA_INFO *pASICameraInfo, int iCameraIndex)
        get_camera_property: b"ASIGetCameraProperty\0"
            => unsafe extern "C" fn(*mut ASICameraInfo, c_int) -> c_int,
        open_camera: b"ASIOpenCamera\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        init_camera: b"ASIInitCamera\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        close_camera: b"ASICloseCamera\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        get_control_value: b"ASIGetControlValue\0"
            => unsafe extern "C" fn(c_int, c_int, *mut c_long, *mut ASIBool) -> c_int,
        set_control_value: b"ASISetControlValue\0"
            => unsafe extern "C" fn(c_int, c_int, c_long, ASIBool) -> c_int,
        set_roi_format: b"ASISetROIFormat\0"
            => unsafe extern "C" fn(c_int, c_int, c_int, c_int, c_int) -> c_int,
        set_start_pos: b"ASISetStartPos\0"
            => unsafe extern "C" fn(c_int, c_int, c_int) -> c_int,
        get_roi_format: b"ASIGetROIFormat\0"
            => unsafe extern "C" fn(c_int, *mut c_int, *mut c_int, *mut c_int, *mut c_int) -> c_int,
        start_exposure: b"ASIStartExposure\0"
            => unsafe extern "C" fn(c_int, ASIBool) -> c_int,
        stop_exposure: b"ASIStopExposure\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        get_exp_status: b"ASIGetExpStatus\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        get_data_after_exp: b"ASIGetDataAfterExp\0"
            => unsafe extern "C" fn(c_int, *mut c_uchar, c_long) -> c_int,
        get_num_controls: b"ASIGetNumOfControls\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        get_control_caps: b"ASIGetControlCaps\0"
            => unsafe extern "C" fn(c_int, c_int, *mut ASIControlCaps) -> c_int,
    }
}

/// Check ASI error and convert to NativeError with detailed messages
fn check_asi_error(code: c_int) -> Result<(), NativeError> {
    match code {
        0 => Ok(()),
        1 => Err(NativeError::InvalidDevice("ASI_ERROR_INVALID_INDEX: No camera connected or camera index out of bounds".to_string())),
        2 => Err(NativeError::InvalidDevice("ASI_ERROR_INVALID_ID: Invalid camera ID - camera may have been disconnected".to_string())),
        3 => Err(NativeError::SdkError("ASI_ERROR_INVALID_CONTROL_TYPE: Invalid control type".to_string())),
        4 => Err(NativeError::NotConnected),
        5 => Err(NativeError::Disconnected),
        6 => Err(NativeError::SdkError("ASI_ERROR_INVALID_PATH: Cannot find file path".to_string())),
        7 => Err(NativeError::SdkError("ASI_ERROR_INVALID_FILEFORMAT: Invalid file format".to_string())),
        8 => Err(NativeError::SdkError("ASI_ERROR_INVALID_SIZE: Invalid video format size".to_string())),
        9 => Err(NativeError::SdkError("ASI_ERROR_INVALID_IMGTYPE: Unsupported image format".to_string())),
        10 => Err(NativeError::SdkError("ASI_ERROR_OUTOF_BOUNDARY: Start position out of boundary".to_string())),
        11 => Err(NativeError::Timeout("ASI_ERROR_TIMEOUT: Operation timed out".to_string())),
        12 => Err(NativeError::SdkError("ASI_ERROR_INVALID_SEQUENCE: Invalid operation sequence - stop capture first".to_string())),
        13 => Err(NativeError::SdkError("ASI_ERROR_BUFFER_TOO_SMALL: Buffer size is too small".to_string())),
        14 => Err(NativeError::SdkError("ASI_ERROR_VIDEO_MODE_ACTIVE: Camera is in video mode - may be in use by another application".to_string())),
        15 => Err(NativeError::SdkError("ASI_ERROR_EXPOSURE_IN_PROGRESS: Exposure in progress".to_string())),
        16 => Err(NativeError::SdkError("ASI_ERROR_GENERAL_ERROR: General error - camera may be in use by another application (NINA, SharpCap, etc.)".to_string())),
        17 => Err(NativeError::SdkError("ASI_ERROR_INVALID_MODE: Invalid mode".to_string())),
        _ => Err(NativeError::SdkError(format!("Unknown ASI error code: {}", code))),
    }
}

// =============================================================================
// ZWO CAMERA IMPLEMENTATION
// =============================================================================

/// Locally-tracked cooler state.
///
/// The ZWO SDK does not expose a reliable boolean read of "is the cooler currently
/// commanded on?". `ASIGetControlValue(ASI_COOLER_ON)` is queried first and used
/// when it succeeds; if the SDK call fails or the camera lacks a cooler, the value
/// last written via `set_cooler` is the canonical source of truth. Without this
/// `get_status` would have to lie and report `cooler_on: false` after the user
/// commanded it on.
#[derive(Debug, Clone, Copy)]
struct CoolerState {
    enabled: bool,
    target_c: f64,
}

impl Default for CoolerState {
    fn default() -> Self {
        // -10 C is the documented power-on default the SDK picks for the target
        // register; using it here keeps `target_temp` consistent across drivers.
        Self {
            enabled: false,
            target_c: -10.0,
        }
    }
}

/// ZWO ASI Camera implementation
#[derive(Debug)]
pub struct ZwoCamera {
    camera_id: i32,
    camera_info: Option<ASICameraInfo>,
    connected: bool,
    device_id: String,
    current_bin: i32,
    current_width: i32,
    current_height: i32,
    image_type: ASIImgType,

    // Current settings tracking
    current_gain: i32,
    current_offset: i32,
    // Exposure metadata tracking
    exposure_time: f64,
    current_subframe: Option<SubFrame>,
    // Locally-tracked cooler command (last set_cooler) — see CoolerState docs.
    cooler_state: Mutex<CoolerState>,
}

impl ZwoCamera {
    /// Create a new ZWO camera instance
    pub fn new(camera_id: i32) -> Self {
        Self {
            camera_id,
            camera_info: None,
            connected: false,
            device_id: format!("native:zwo:{}", camera_id),
            current_bin: 1,
            current_width: 0,
            current_height: 0,
            image_type: ASIImgType::Raw16,
            current_gain: 0,
            current_offset: 0,
            exposure_time: 0.0,
            current_subframe: None,
            cooler_state: Mutex::new(CoolerState::default()),
        }
    }

    /// Load camera info from SDK
    fn load_camera_info(&mut self) -> Result<(), NativeError> {
        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // SAFETY: ASICameraInfo is `#[repr(C)]` POD (only c_int/c_long/f64/f32/c_char arrays); zeroed is a valid initial state per ASI SDK contract before ASIGetCameraProperty writes into it.
        let mut info: ASICameraInfo = unsafe { std::mem::zeroed() };
        // ASIGetCameraProperty(ASI_CAMERA_INFO *pASICameraInfo, int iCameraIndex)
        // SAFETY: `&mut info` points to a fully-allocated ASICameraInfo on the stack; camera_id is the index validated against the SDK's ASIGetNumOfConnectedCameras() at construction time. zwo_camera_mutex is held by caller (sync helper) ensuring the non-thread-safe SDK is single-threaded.
        let result = unsafe { (sdk.get_camera_property)(&mut info, self.camera_id) };
        check_asi_error(result)?;

        self.current_width = info.max_width;
        self.current_height = info.max_height;
        self.camera_info = Some(info);
        Ok(())
    }

    /// Get camera name using safe string conversion
    fn camera_name(&self) -> String {
        if let Some(info) = &self.camera_info {
            // Use safe string conversion with bounded length
            safe_cstr_to_string(info.name.as_ptr(), 64)
        } else {
            format!("ZWO Camera {}", self.camera_id)
        }
    }

    /// Get a control value (mutex protected)
    async fn get_control_async(&self, control: ASIControlType) -> Result<c_long, NativeError> {
        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_camera_mutex().lock().await;
        let mut value: c_long = 0;
        let mut is_auto: ASIBool = ASI_FALSE;
        // SAFETY: zwo_camera_mutex is held above guaranteeing single-threaded SDK access; `value` and `is_auto` are stack-allocated and outlive the call; camera_id was validated when the camera was opened.
        let result = unsafe {
            (sdk.get_control_value)(self.camera_id, control as c_int, &mut value, &mut is_auto)
        };
        check_asi_error(result)?;
        Ok(value)
    }

    /// Get a control value (synchronous version - caller must hold mutex)
    fn get_control(&self, control: ASIControlType) -> Result<c_long, NativeError> {
        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let mut value: c_long = 0;
        let mut is_auto: ASIBool = ASI_FALSE;
        // SAFETY: per function contract the caller already holds zwo_camera_mutex (called only from connect/get_status/download_image while lock is held). `value`/`is_auto` are valid stack pointers; camera_id was validated at open time.
        let result = unsafe {
            (sdk.get_control_value)(self.camera_id, control as c_int, &mut value, &mut is_auto)
        };
        check_asi_error(result)?;
        Ok(value)
    }

    /// Set a control value (mutex protected)
    async fn set_control_async(
        &mut self,
        control: ASIControlType,
        value: c_long,
        auto: bool,
    ) -> Result<(), NativeError> {
        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_camera_mutex().lock().await;
        // SAFETY: zwo_camera_mutex is held above; all arguments are pass-by-value primitives validated by ASI control range; camera_id is valid (camera was opened).
        let result = unsafe {
            (sdk.set_control_value)(
                self.camera_id,
                control as c_int,
                value,
                if auto { ASI_TRUE } else { ASI_FALSE },
            )
        };
        check_asi_error(result)
    }

    /// Set a control value (synchronous version - caller must hold mutex)
    fn set_control(
        &mut self,
        control: ASIControlType,
        value: c_long,
        auto: bool,
    ) -> Result<(), NativeError> {
        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        // SAFETY: caller-must-hold-mutex contract documented on the function. All args are pass-by-value primitives; camera_id is valid since this method is only called between connect()/disconnect() while the mutex is held.
        let result = unsafe {
            (sdk.set_control_value)(
                self.camera_id,
                control as c_int,
                value,
                if auto { ASI_TRUE } else { ASI_FALSE },
            )
        };
        check_asi_error(result)
    }

    /// Get the min/max range for a control (mutex protected)
    async fn get_control_range_async(
        &self,
        target_control: ASIControlType,
    ) -> Result<(i32, i32), NativeError> {
        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_camera_mutex().lock().await;

        // Get number of controls
        let mut num_controls: c_int = 0;
        // SAFETY: zwo_camera_mutex is held (acquired above); `num_controls` is a valid stack pointer; camera_id is valid (camera opened during connect).
        let result = unsafe { (sdk.get_num_controls)(self.camera_id, &mut num_controls) };
        check_asi_error(result)?;

        // Search for the specific control
        for i in 0..num_controls {
            // SAFETY: ASIControlCaps is `#[repr(C)]` POD; zeroed is a safe initial state per SDK contract.
            let mut caps: ASIControlCaps = unsafe { std::mem::zeroed() };
            // SAFETY: zwo_camera_mutex held; `caps` is a valid stack pointer; `i` is bounded by num_controls returned by the SDK above; camera_id is valid.
            let result = unsafe { (sdk.get_control_caps)(self.camera_id, i, &mut caps) };
            if result == 0 {
                // Check if this is the control we're looking for
                // The control_type field tells us which control this is
                if caps.control_type as c_int == target_control as c_int {
                    return Ok((caps.min_value, caps.max_value));
                }
            }
        }

        Err(NativeError::NotSupported)
    }

    /// Get the min/max range for a control (synchronous version - caller must hold mutex)
    fn get_control_range(&self, target_control: ASIControlType) -> Result<(i32, i32), NativeError> {
        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Get number of controls
        let mut num_controls: c_int = 0;
        // SAFETY: per function contract the caller already holds zwo_camera_mutex; `num_controls` is a valid stack pointer; camera_id is valid.
        let result = unsafe { (sdk.get_num_controls)(self.camera_id, &mut num_controls) };
        check_asi_error(result)?;

        // Search for the specific control
        for i in 0..num_controls {
            // SAFETY: ASIControlCaps is `#[repr(C)]` POD; zeroed is a safe initial state.
            let mut caps: ASIControlCaps = unsafe { std::mem::zeroed() };
            // SAFETY: caller-held mutex (function contract); `caps` is a valid stack pointer; `i` is bounded by num_controls; camera_id is valid.
            let result = unsafe { (sdk.get_control_caps)(self.camera_id, i, &mut caps) };
            if result == 0 {
                // Check if this is the control we're looking for
                // The control_type field tells us which control this is
                if caps.control_type as c_int == target_control as c_int {
                    return Ok((caps.min_value, caps.max_value));
                }
            }
        }

        Err(NativeError::NotSupported)
    }

    /// Wait for exposure to complete with timeout.
    ///
    /// Polls `is_exposure_complete()` until it returns true or the timeout is reached.
    /// Uses the timeout calculated from the exposure duration plus a margin.
    ///
    /// # Arguments
    /// * `config` - Timeout configuration
    ///
    /// # Returns
    /// * `Ok(())` - Exposure completed successfully
    /// * `Err(NativeError::ExposureTimeout)` - Exposure did not complete within timeout
    /// * `Err(NativeError::...)` - Other errors from polling
    pub async fn wait_for_exposure_complete(
        &self,
        config: &NativeTimeoutConfig,
    ) -> Result<(), NativeError> {
        wait_for_exposure(
            || async { self.is_exposure_complete().await },
            config,
            self.exposure_time,
        )
        .await
    }

    /// Download image with timeout protection.
    ///
    /// This wrapper uses `tokio::time::timeout()` to enforce a hard timeout on the
    /// image download operation. If the download takes longer than
    /// `config.image_download_timeout`, the operation is cancelled and an error is returned.
    ///
    /// # Arguments
    /// * `config` - Timeout configuration
    ///
    /// # Returns
    /// * `Ok(ImageData)` - Image downloaded successfully
    /// * `Err(NativeError::DownloadTimeout)` - Download timed out
    pub async fn download_image_with_timeout(
        &mut self,
        config: &NativeTimeoutConfig,
    ) -> Result<ImageData, NativeError> {
        let timeout_duration = config.image_download_timeout;

        match tokio::time::timeout(timeout_duration, self.download_image()).await {
            Ok(result) => result,
            Err(_elapsed) => {
                tracing::error!("ZWO image download timed out after {:?}", timeout_duration);
                Err(NativeError::download_timeout(
                    timeout_duration,
                    self.current_width as u32,
                    self.current_height as u32,
                ))
            }
        }
    }
}

#[async_trait]
impl NativeDevice for ZwoCamera {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        // We need to return a &str, but camera_name() returns String
        // Use a stable identifier until an owned display-name field is added.
        &self.device_id
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Zwo
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        tracing::info!("Connecting to ZWO camera ID {}...", self.camera_id);

        let sdk = AsiSdk::get().ok_or_else(|| {
            tracing::error!("Cannot connect to ZWO camera: ASI SDK not loaded");
            NativeError::SdkNotLoaded
        })?;

        // Acquire mutex for all SDK operations during connect
        let _lock = zwo_camera_mutex().lock().await;

        // Load camera info
        tracing::debug!("Loading camera info for ID {}", self.camera_id);
        self.load_camera_info().map_err(|e| {
            tracing::error!(
                "Failed to load camera info for ID {}: {:?}",
                self.camera_id,
                e
            );
            e
        })?;
        tracing::debug!("Camera info loaded successfully");

        // Open camera
        tracing::debug!("Opening camera ID {}", self.camera_id);
        // SAFETY: zwo_camera_mutex is held (acquired in connect() before this point); camera_id is the index from discover_devices() which was validated against ASIGetNumOfConnectedCameras.
        let result = unsafe { (sdk.open_camera)(self.camera_id) };
        if result != 0 {
            tracing::error!(
                "ASIOpenCamera failed for ID {}: ASI error code {}",
                self.camera_id,
                result
            );
            return Err(check_asi_error(result).unwrap_err());
        }
        tracing::debug!("Camera opened successfully");

        // Create cleanup guard to close the camera if subsequent operations fail
        let camera_id = self.camera_id;
        let cleanup_guard = CleanupGuard::new(|| {
            tracing::debug!("Cleaning up ZWO camera {} after failed connect", camera_id);
            if let Some(sdk) = AsiSdk::get() {
                // SAFETY: Best-effort cleanup on error path; camera_id was successfully opened above (we only reach the guard after ASIOpenCamera succeeded). Cleanup runs on drop while the connect() lock is still held since the guard is dropped before connect() returns.
                let _ = unsafe { (sdk.close_camera)(camera_id) };
            }
        });

        // Initialize camera
        tracing::debug!("Initializing camera ID {}", self.camera_id);
        // SAFETY: zwo_camera_mutex held by connect(); camera_id was successfully opened by ASIOpenCamera above.
        let result = unsafe { (sdk.init_camera)(self.camera_id) };
        if result != 0 {
            tracing::error!(
                "ASIInitCamera failed for ID {}: ASI error code {}",
                self.camera_id,
                result
            );
            // cleanup_guard will handle closing the camera
            return Err(check_asi_error(result).unwrap_err());
        }
        tracing::debug!("Camera initialized successfully");

        // Set default ROI format (full frame, bin 1, Raw16)
        if let Some(info) = &self.camera_info {
            tracing::debug!(
                "Setting ROI format: {}x{}, bin 1, Raw16",
                info.max_width,
                info.max_height
            );
            // SAFETY: zwo_camera_mutex held by connect(); camera_id is open and initialized; width/height come from the SDK-reported ASICameraInfo and bin=1 is always valid.
            let result = unsafe {
                (sdk.set_roi_format)(
                    self.camera_id,
                    info.max_width as c_int,
                    info.max_height as c_int,
                    1, // bin
                    ASIImgType::Raw16 as c_int,
                )
            };
            if result != 0 {
                tracing::error!("ASISetROIFormat failed: ASI error code {}", result);
                return Err(check_asi_error(result).unwrap_err());
            }
            tracing::debug!("ROI format set successfully");
        }

        // Get current gain and offset (use synchronous versions since we already hold the mutex)
        tracing::debug!("Reading current gain and offset");
        if let Ok(val) = self.get_control(ASIControlType::ASI_GAIN) {
            self.current_gain = val;
            tracing::debug!("Current gain: {}", self.current_gain);
        }
        if let Ok(val) = self.get_control(ASIControlType::ASI_OFFSET) {
            self.current_offset = val;
            tracing::debug!("Current offset: {}", self.current_offset);
        }

        // All operations succeeded - defuse the cleanup guard
        cleanup_guard.defuse();

        self.connected = true;
        tracing::info!(
            "Successfully connected to ZWO camera: {}",
            self.camera_name()
        );
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if self.connected {
            let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
            let _lock = zwo_camera_mutex().lock().await;
            // SAFETY: zwo_camera_mutex acquired above; camera_id is valid because self.connected is true (only set after successful connect()).
            let result = unsafe { (sdk.close_camera)(self.camera_id) };
            check_asi_error(result)?;
            self.connected = false;
            tracing::info!("Disconnected from {}", self.camera_name());
        }
        Ok(())
    }
}

#[async_trait]
impl NativeCamera for ZwoCamera {
    fn capabilities(&self) -> CameraCapabilities {
        if let Some(info) = &self.camera_info {
            CameraCapabilities {
                can_cool: info.is_cooler_cam != 0,
                can_set_gain: true,
                can_set_offset: true,
                can_set_binning: true,
                can_subframe: true,
                has_shutter: info.mechanical_shutter != 0,
                has_guider_port: info.st4_port != 0,
                max_bin_x: 4,
                max_bin_y: 4,
                supports_readout_modes: false,
            }
        } else {
            CameraCapabilities::default()
        }
    }

    async fn get_status(&self) -> Result<CameraStatus, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = zwo_camera_mutex().lock().await;

        let mut exp_status: c_int = 0;
        // SAFETY: zwo_camera_mutex held above; `exp_status` is a valid stack pointer; camera_id is valid (self.connected was checked).
        let result = unsafe { (sdk.get_exp_status)(self.camera_id, &mut exp_status) };
        check_asi_error(result)?;

        let state = match exp_status {
            0 => CameraState::Idle,
            1 => CameraState::Exposing,
            2 => CameraState::Downloading,
            _ => CameraState::Error,
        };

        // Get temperature (ASI_TEMPERATURE returns 10*temperature) - use sync version since we hold mutex
        let temp = self
            .get_control(ASIControlType::ASI_TEMPERATURE)
            .map(|v| v as f64 / 10.0)
            .ok();

        let supports_cooler = if let Some(info) = self.camera_info.as_ref() {
            info.is_cooler_cam != 0
        } else {
            tracing::warn!(
                "ZWO camera_info metadata unavailable while reading status; probing cooler capability via control API."
            );
            self.get_control(ASIControlType::ASI_COOLER_ON).is_ok()
        };

        let cooler_power = if supports_cooler {
            self.get_control(ASIControlType::ASI_COOLER_POWER_PERC)
                .ok()
                .map(|v| v as f64)
        } else {
            None
        };

        // Trust the SDK's COOLER_ON readback when it succeeds; otherwise fall back to
        // the value last written via set_cooler. Locked-state poisoning is recovered
        // (we own the data, not a foreign invariant), since refusing to report status
        // because of a poisoned lock would be a worse failure mode than reading a
        // last-known-good copy. Cameras without a cooler always report `false`.
        let (cooler_on, target_temp) = if supports_cooler {
            let local = *self.cooler_state.lock().unwrap_or_else(|e| e.into_inner());
            let sdk_enabled = self
                .get_control(ASIControlType::ASI_COOLER_ON)
                .ok()
                .map(|v| v != 0);
            (sdk_enabled.unwrap_or(local.enabled), Some(local.target_c))
        } else {
            (false, None)
        };

        Ok(CameraStatus {
            state,
            sensor_temp: temp,
            target_temp,
            cooler_on,
            cooler_power,
            gain: self.current_gain,
            offset: self.current_offset,
            bin_x: self.current_bin,
            bin_y: self.current_bin,
            exposure_remaining: None,
        })
    }

    async fn start_exposure(&mut self, params: ExposureParams) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = zwo_camera_mutex().lock().await;

        // Set exposure time (in microseconds) - use sync version since we hold mutex
        let exposure_us = (params.duration_secs * 1_000_000.0) as c_long;
        self.set_control(ASIControlType::ASI_EXPOSURE, exposure_us, false)?;

        // Set gain
        if let Some(gain) = params.gain {
            self.set_control(ASIControlType::ASI_GAIN, gain as c_long, false)?;
            self.current_gain = gain;
        }

        // Set offset if provided
        if let Some(offset) = params.offset {
            self.set_control(ASIControlType::ASI_OFFSET, offset as c_long, false)?;
            self.current_offset = offset;
        }

        // Start exposure (false = not dark frame)
        // SAFETY: zwo_camera_mutex held by caller (start_exposure() acquires it before this point); camera_id is valid (connected=true checked earlier).
        let result = unsafe { (sdk.start_exposure)(self.camera_id, ASI_FALSE) };
        check_asi_error(result)?;

        // Track exposure time for metadata
        self.exposure_time = params.duration_secs;

        tracing::info!("Started {}s exposure", params.duration_secs);
        Ok(())
    }

    async fn abort_exposure(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_camera_mutex().lock().await;
        // SAFETY: zwo_camera_mutex held above; camera_id is valid (connected=true checked earlier).
        let result = unsafe { (sdk.stop_exposure)(self.camera_id) };
        check_asi_error(result)?;

        tracing::info!("Aborted exposure");
        Ok(())
    }

    async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_camera_mutex().lock().await;

        let mut status: c_int = 0;
        // SAFETY: zwo_camera_mutex held above; `status` is a valid stack pointer; camera_id is valid (connected=true checked).
        let result = unsafe { (sdk.get_exp_status)(self.camera_id, &mut status) };
        check_asi_error(result)?;

        let is_complete = status == ASIExposureStatus::Success as c_int;
        // Log status for debugging (0=Idle, 1=Working, 2=Success, 3=Failed)
        if is_complete || status == ASIExposureStatus::Failed as c_int {
            tracing::info!(
                "ZWO exposure status: {} ({})",
                status,
                match status {
                    0 => "Idle",
                    1 => "Working",
                    2 => "Success",
                    3 => "Failed",
                    _ => "Unknown",
                }
            );
        }

        Ok(is_complete)
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = zwo_camera_mutex().lock().await;

        // Get current ROI
        let mut width: c_int = 0;
        let mut height: c_int = 0;
        let mut bin: c_int = 0;
        let mut img_type: c_int = 0;

        // SAFETY: zwo_camera_mutex held above; all four out-pointers are valid stack pointers; camera_id is valid (connected=true checked).
        let result = unsafe {
            (sdk.get_roi_format)(
                self.camera_id,
                &mut width,
                &mut height,
                &mut bin,
                &mut img_type,
            )
        };
        check_asi_error(result)?;

        // Calculate buffer size (Raw16 = 2 bytes per pixel) with overflow protection
        let bytes_per_pixel = if img_type == ASIImgType::Raw16 as c_int {
            2
        } else {
            1
        };
        let buffer_size = calculate_buffer_size_i32(width, height, bytes_per_pixel)?;

        // Use pooled buffer for efficient memory reuse during high-throughput capture
        let mut pooled_buffer = global_u8_pool().get_buffer(buffer_size);
        pooled_buffer.resize(buffer_size);

        // SAFETY: zwo_camera_mutex held above; `pooled_buffer` was resized to exactly `buffer_size` bytes (computed via calculate_buffer_size_i32 from the SDK-reported ROI), and the SDK writes at most `buffer_size` bytes into the pointer. camera_id is valid (connected=true checked).
        let result = unsafe {
            (sdk.get_data_after_exp)(
                self.camera_id,
                pooled_buffer.as_mut_ptr(),
                buffer_size as c_long,
            )
        };
        check_asi_error(result)?;

        // Convert to u16 if needed
        let data: Vec<u16> = if bytes_per_pixel == 2 {
            pooled_buffer
                .chunks_exact(2)
                .map(|chunk| u16::from_ne_bytes([chunk[0], chunk[1]]))
                .collect()
        } else {
            pooled_buffer.iter().map(|&x| (x as u16) * 256).collect()
        };

        // DIAGNOSTIC: Log data statistics to debug mid-gray image issue
        if !data.is_empty() {
            let min_val = data.iter().min().copied().expect("non-empty data");
            let max_val = data.iter().max().copied().expect("non-empty data");
            let sum: u64 = data.iter().map(|&x| x as u64).sum();
            let avg_val = sum / data.len() as u64;
            let non_zero_count = data.iter().filter(|&&x| x != 0).count();
            tracing::info!(
                "ZWO DIAGNOSTIC: Raw buffer stats - min={}, max={}, avg={}, non_zero={}/{}, img_type={}",
                min_val, max_val, avg_val, non_zero_count, data.len(), img_type
            );
            if min_val == max_val {
                tracing::warn!(
                    "ZWO WARNING: All pixels have same value {}! This indicates no actual image data was captured.",
                    min_val
                );
            }
        }

        tracing::info!(
            "Downloaded {}x{} image ({} bytes, img_type={})",
            width,
            height,
            buffer_size,
            img_type
        );

        // Get temperature and vendor features using sync methods since we already hold the lock
        // (calling async methods here would deadlock because they try to acquire the same mutex)
        let temperature = self
            .get_control(ASIControlType::ASI_TEMPERATURE)
            .map(|v| v as f64 / 10.0)
            .ok();

        let mut vendor_data = VendorFeatures::default();
        if let Ok(bw) = self.get_control(ASIControlType::ASI_BANDWIDTHOVERLOAD) {
            vendor_data.usb_bandwidth = Some(bw as f64);
        }
        if let Ok(heater) = self.get_control(ASIControlType::ASI_ANTI_DEW_HEATER) {
            vendor_data.anti_dew_heater = Some(heater != 0);
        }

        Ok(ImageData {
            width: width as u32,
            height: height as u32,
            data,
            bits_per_pixel: if bytes_per_pixel == 2 { 16 } else { 8 },
            bayer_pattern: self
                .camera_info
                .as_ref()
                .filter(|i| i.is_color_cam != 0)
                .map(|i| match i.bayer_pattern {
                    0 => BayerPattern::Rggb,
                    1 => BayerPattern::Bggr,
                    2 => BayerPattern::Grbg,
                    3 => BayerPattern::Gbrg,
                    _ => BayerPattern::Rggb,
                }),
            metadata: ImageMetadata {
                exposure_time: self.exposure_time,
                gain: self.current_gain,
                offset: self.current_offset,
                bin_x: self.current_bin,
                bin_y: self.current_bin,
                temperature,
                timestamp: chrono::Utc::now(),
                subframe: self.current_subframe.clone(),
                readout_mode: None,
                vendor_data,
            },
        })
    }

    async fn set_cooler(&mut self, enabled: bool, target_temp: f64) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let supports_cooler = self
            .camera_info
            .as_ref()
            .map(|i| i.is_cooler_cam != 0)
            .ok_or_else(|| {
                NativeError::InvalidDevice(
                    "Camera capability metadata unavailable for cooler operation".to_string(),
                )
            })?;
        if !supports_cooler {
            return Err(NativeError::NotSupported);
        }

        // Use async versions with mutex protection
        self.set_control_async(
            ASIControlType::ASI_TARGET_TEMP,
            target_temp as c_long,
            false,
        )
        .await?;
        self.set_control_async(
            ASIControlType::ASI_COOLER_ON,
            if enabled { 1 } else { 0 },
            false,
        )
        .await?;

        // Persist the commanded state only after both SDK writes succeed: a partial
        // write must not leave the local cache asserting a state the hardware never
        // reached. Lock poisoning is recovered because a previous panic in this
        // section could not have left the cooler in an unknown state.
        {
            let mut state = self.cooler_state.lock().unwrap_or_else(|e| e.into_inner());
            state.enabled = enabled;
            state.target_c = target_temp;
        }

        Ok(())
    }

    async fn get_temperature(&self) -> Result<f64, NativeError> {
        // ASI_TEMPERATURE returns 10*temperature - use async version with mutex
        let value = self
            .get_control_async(ASIControlType::ASI_TEMPERATURE)
            .await?;
        Ok(value as f64 / 10.0)
    }

    async fn get_cooler_power(&self) -> Result<f64, NativeError> {
        let supports_cooler = self
            .camera_info
            .as_ref()
            .map(|i| i.is_cooler_cam != 0)
            .ok_or_else(|| {
                NativeError::InvalidDevice(
                    "Camera capability metadata unavailable for cooler power query".to_string(),
                )
            })?;
        if !supports_cooler {
            return Err(NativeError::NotSupported);
        }
        let value = self
            .get_control_async(ASIControlType::ASI_COOLER_POWER_PERC)
            .await?;
        Ok(value as f64)
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        self.current_gain = gain;
        self.set_control_async(ASIControlType::ASI_GAIN, gain as c_long, false)
            .await
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        let val = self
            .get_control_async(ASIControlType::ASI_GAIN)
            .await
            .map(|v| v)?;
        Ok(val)
    }

    async fn set_offset(&mut self, offset: i32) -> Result<(), NativeError> {
        self.current_offset = offset;
        self.set_control_async(ASIControlType::ASI_OFFSET, offset as c_long, false)
            .await
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        let val = self
            .get_control_async(ASIControlType::ASI_OFFSET)
            .await
            .map(|v| v)?;
        Ok(val)
    }

    async fn set_binning(&mut self, bin_x: i32, bin_y: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // ZWO only supports symmetric binning
        let bin = bin_x.max(bin_y);

        // Calculate new dimensions
        let info = self.camera_info.as_ref().ok_or(NativeError::NotConnected)?;
        let new_width = info.max_width / bin;
        let new_height = info.max_height / bin;

        // Acquire mutex for SDK operation
        let _lock = zwo_camera_mutex().lock().await;

        // SAFETY: zwo_camera_mutex held above; new_width/new_height derive from SDK-reported max_width/max_height divided by `bin` (clamped 1..=4); camera_id is valid (connected=true checked).
        let result = unsafe {
            (sdk.set_roi_format)(
                self.camera_id,
                new_width as c_int,
                new_height as c_int,
                bin as c_int,
                self.image_type as c_int,
            )
        };
        check_asi_error(result)?;

        self.current_bin = bin;
        self.current_width = new_width;
        self.current_height = new_height;

        Ok(())
    }

    async fn get_binning(&self) -> Result<(i32, i32), NativeError> {
        Ok((self.current_bin, self.current_bin))
    }

    async fn set_subframe(&mut self, subframe: Option<SubFrame>) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = AsiSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let info = self.camera_info.as_ref().ok_or(NativeError::NotConnected)?;

        let (width, height, x, y) = if let Some(ref sf) = subframe {
            (
                sf.width as c_int,
                sf.height as c_int,
                sf.start_x as c_int,
                sf.start_y as c_int,
            )
        } else {
            (
                info.max_width as c_int / self.current_bin as c_int,
                info.max_height as c_int / self.current_bin as c_int,
                0,
                0,
            )
        };

        // Acquire mutex for SDK operations
        let _lock = zwo_camera_mutex().lock().await;

        // SAFETY: zwo_camera_mutex held above; width/height derive from SubFrame supplied by caller (validated by upper layer) or SDK-reported max dimensions; camera_id is valid (connected=true checked).
        let result = unsafe {
            (sdk.set_roi_format)(
                self.camera_id,
                width,
                height,
                self.current_bin as c_int,
                self.image_type as c_int,
            )
        };
        check_asi_error(result)?;

        // SAFETY: zwo_camera_mutex still held; x/y are subframe coordinates from caller validated by upper layer; camera_id is valid.
        let result = unsafe { (sdk.set_start_pos)(self.camera_id, x, y) };
        check_asi_error(result)?;

        self.current_width = width;
        self.current_height = height;
        // Track subframe for metadata
        self.current_subframe = subframe;

        Ok(())
    }

    fn get_sensor_info(&self) -> SensorInfo {
        if let Some(info) = &self.camera_info {
            SensorInfo {
                width: info.max_width as u32,
                height: info.max_height as u32,
                pixel_size_x: info.pixel_size,
                pixel_size_y: info.pixel_size,
                max_adu: (1u32 << info.bit_depth) - 1,
                bit_depth: info.bit_depth as u32,
                color: info.is_color_cam != 0,
                bayer_pattern: if info.is_color_cam != 0 {
                    Some(match info.bayer_pattern {
                        0 => BayerPattern::Rggb,
                        1 => BayerPattern::Bggr,
                        2 => BayerPattern::Grbg,
                        3 => BayerPattern::Gbrg,
                        _ => BayerPattern::Rggb,
                    })
                } else {
                    None
                },
            }
        } else {
            SensorInfo::default()
        }
    }

    async fn get_readout_modes(&self) -> Result<Vec<ReadoutMode>, NativeError> {
        // ZWO doesn't have readout modes
        Ok(Vec::new())
    }

    async fn set_readout_mode(&mut self, _mode: &ReadoutMode) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
        let mut features = VendorFeatures::default();

        // Get USB bandwidth - use async version with mutex
        if let Ok(bw) = self
            .get_control_async(ASIControlType::ASI_BANDWIDTHOVERLOAD)
            .await
        {
            features.usb_bandwidth = Some(bw as f64);
        }

        // ZWO-specific: Anti-dew heater - use async version with mutex
        if let Ok(heater) = self
            .get_control_async(ASIControlType::ASI_ANTI_DEW_HEATER)
            .await
        {
            features.anti_dew_heater = Some(heater != 0);
        }

        Ok(features)
    }

    async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        self.get_control_range_async(ASIControlType::ASI_GAIN).await
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        self.get_control_range_async(ASIControlType::ASI_OFFSET)
            .await
    }
}

// =============================================================================
// ZWO CAMERA DISCOVERY
// =============================================================================

/// ZWO camera discovery info
pub struct ZwoDiscoveryInfo {
    pub camera_id: i32,
    pub name: String,
    /// Discovery index (0-based) for disambiguation when multiple same-model cameras
    /// ZWO SDK doesn't expose serial numbers, so we use index instead
    pub discovery_index: usize,
}

/// Check if ZWO SDK is available
pub fn is_sdk_available() -> bool {
    AsiSdk::get().is_some()
}

/// Check if ZWO SDK is loaded and return status message
pub fn get_sdk_status() -> (bool, String) {
    match AsiSdk::get() {
        Some(_) => (true, "ZWO ASI SDK loaded successfully".to_string()),
        None => (false, "ZWO ASI SDK (ASICamera2.dll) not found. Install the ASI SDK or use ASCOM drivers instead.".to_string()),
    }
}

/// Discover ZWO cameras
pub async fn discover_devices() -> Result<Vec<ZwoDiscoveryInfo>, NativeError> {
    let sdk = match AsiSdk::get() {
        Some(sdk) => sdk,
        None => {
            // Log prominently so users know why discovery returned nothing
            tracing::debug!("ZWO native camera discovery skipped: ASI SDK not loaded");
            return Ok(Vec::new());
        }
    };

    // Acquire mutex for SDK discovery operations
    let _lock = zwo_camera_mutex().lock().await;

    tracing::debug!("Discovering ZWO cameras via native ASI SDK...");
    // SAFETY: zwo_camera_mutex held above; ASIGetNumOfConnectedCameras takes no arguments and only reads internal SDK state.
    let num_cameras = unsafe { (sdk.get_num_cameras)() };
    tracing::debug!("ASI SDK reports {} connected camera(s)", num_cameras);

    let mut cameras = Vec::new();
    let mut failed_count = 0;

    for i in 0..num_cameras {
        // SAFETY: ASICameraInfo is `#[repr(C)]` POD; zeroed is a valid initial state before SDK populates it.
        let mut info: ASICameraInfo = unsafe { std::mem::zeroed() };
        // ASIGetCameraProperty(ASI_CAMERA_INFO *pASICameraInfo, int iCameraIndex)
        // SAFETY: zwo_camera_mutex held above; `i` is bounded by num_cameras returned by the SDK; `info` is a valid stack pointer.
        let result = unsafe { (sdk.get_camera_property)(&mut info, i) };

        if result == 0 {
            // SAFETY: ASI SDK guarantees `info.name` is a NUL-terminated UTF-8 string within the 64-byte array; to_string_lossy handles any non-UTF8 bytes by replacing them.
            let name = unsafe {
                CStr::from_ptr(info.name.as_ptr())
                    .to_string_lossy()
                    .to_string()
            };
            tracing::info!("Found ZWO camera: {} (ID: {})", name, i);

            cameras.push(ZwoDiscoveryInfo {
                camera_id: i,
                name,
                discovery_index: i as usize,
            });
        } else {
            failed_count += 1;
            let error_desc = match result {
                1 => "INVALID_INDEX - camera may be in use by another application",
                2 => "INVALID_ID",
                3 => "INVALID_CONTROL_TYPE",
                4 => "CAMERA_CLOSED",
                5 => "CAMERA_REMOVED - camera was disconnected",
                6 => "INVALID_PATH",
                7 => "INVALID_FILEFORMAT",
                8 => "INVALID_SIZE",
                9 => "INVALID_IMGTYPE",
                10 => "OUTOF_BOUNDARY",
                11 => "TIMEOUT",
                12 => "INVALID_SEQUENCE",
                13 => "BUFFER_TOO_SMALL",
                14 => "VIDEO_MODE_ACTIVE",
                15 => "EXPOSURE_IN_PROGRESS",
                16 => "GENERAL_ERROR - camera may be in use by another application",
                17 => "INVALID_MODE",
                18 => "GPS_NOT_SUPPORTED",
                19 => "GPS_VER_ERROR",
                20 => "GPS_FPGA_ERROR",
                21 => "GPS_DATA_ERROR",
                22 => "END",
                _ => "UNKNOWN",
            };
            tracing::warn!(
                "Failed to query camera index {}: ASI error {} ({})",
                i,
                result,
                error_desc
            );
        }
    }

    if cameras.is_empty() && num_cameras > 0 {
        tracing::error!(
            "ASI SDK detected {} camera(s) but none could be queried. \
            This usually means the cameras are in use by another application \
            (NINA, SharpCap, APT, PHD2, etc.). Close other astrophotography software and try again.",
            num_cameras
        );
    } else if failed_count > 0 {
        tracing::warn!(
            "Successfully discovered {} of {} cameras. {} camera(s) may be in use by other software.",
            cameras.len(), num_cameras, failed_count
        );
    }

    Ok(cameras)
}

// =============================================================================
// ZWO EAF FOCUSER SDK
// =============================================================================

/// EAF Info structure from SDK
#[repr(C)]
#[derive(Debug, Clone)]
struct EAFInfo {
    id: c_int,
    name: [c_char; 64],
    max_step: c_int,
}

/// EAF Error codes
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
#[allow(non_camel_case_types, dead_code)]
enum EAFError {
    EAF_SUCCESS = 0,
    EAF_ERROR_INVALID_INDEX = 1,
    EAF_ERROR_INVALID_ID = 2,
    EAF_ERROR_INVALID_VALUE = 3,
    EAF_ERROR_REMOVED = 4,
    EAF_ERROR_MOVING = 5,
    EAF_ERROR_ERROR_STATE = 6,
    EAF_ERROR_GENERAL_ERROR = 7,
    EAF_ERROR_NOT_SUPPORTED = 8,
    EAF_ERROR_CLOSED = 9,
    EAF_ERROR_END = -1,
}

/// EAF ID/Serial Number structure
#[repr(C)]
#[derive(Debug, Clone)]
struct EAFSerialNumber {
    id: [c_uchar; 8],
}

/// Candidate library paths for the ZWO EAF (focuser) SDK. ZWO only ships the
/// EAF focuser SDK as a single platform-specific filename — no install-tree
/// search is needed beyond the system loader path.
fn eaf_candidate_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if cfg!(target_os = "windows") {
        paths.push(PathBuf::from("EAF_focuser.dll"));
    } else if cfg!(target_os = "macos") {
        paths.push(PathBuf::from("libEAF_focuser.dylib"));
    } else {
        paths.push(PathBuf::from("libEAF_focuser.so"));
    }
    paths
}

load_vendor_sdk! {
    /// ZWO EAF Focuser SDK function-pointer table.
    vendor_name: "ZWO EAF Focuser",
    sdk_struct: EafSdk,
    sdk_static: EAF_SDK,
    candidate_paths_fn: eaf_candidate_paths,
    symbols: {
        get_num: b"EAFGetNum\0"
            => unsafe extern "C" fn() -> c_int,
        get_id: b"EAFGetID\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        open: b"EAFOpen\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        close: b"EAFClose\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        get_property: b"EAFGetProperty\0"
            => unsafe extern "C" fn(c_int, *mut EAFInfo) -> c_int,
        move_to: b"EAFMove\0"
            => unsafe extern "C" fn(c_int, c_int) -> c_int,
        stop: b"EAFStop\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        is_moving: b"EAFIsMoving\0"
            => unsafe extern "C" fn(c_int, *mut bool, *mut bool) -> c_int,
        get_position: b"EAFGetPosition\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        get_temp: b"EAFGetTemp\0"
            => unsafe extern "C" fn(c_int, *mut f32) -> c_int,
        set_max_step: b"EAFSetMaxStep\0"
            => unsafe extern "C" fn(c_int, c_int) -> c_int,
        get_max_step: b"EAFGetMaxStep\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        set_backlash: b"EAFSetBacklash\0"
            => unsafe extern "C" fn(c_int, c_int) -> c_int,
        get_backlash: b"EAFGetBacklash\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        set_reverse: b"EAFSetReverse\0"
            => unsafe extern "C" fn(c_int, bool) -> c_int,
        get_reverse: b"EAFGetReverse\0"
            => unsafe extern "C" fn(c_int, *mut bool) -> c_int,
        set_beep: b"EAFSetBeep\0"
            => unsafe extern "C" fn(c_int, bool) -> c_int,
        get_beep: b"EAFGetBeep\0"
            => unsafe extern "C" fn(c_int, *mut bool) -> c_int,
        get_sdk_version: b"EAFGetSDKVersion\0"
            => unsafe extern "C" fn() -> *const c_char,
        get_firmware_version: b"EAFGetFirmwareVersion\0"
            => unsafe extern "C" fn(c_int, *mut c_uchar, *mut c_uchar, *mut c_uchar) -> c_int,
        get_serial_number: b"EAFGetSerialNumber\0"
            => unsafe extern "C" fn(c_int, *mut EAFSerialNumber) -> c_int,
        // SDK header ships with the typo "EAFResetPostion" (sic) — we must keep
        // it because that's the only symbol the .dll actually exports.
        reset_position: b"EAFResetPostion\0"
            => unsafe extern "C" fn(c_int, c_int) -> c_int,
    }
}

/// Check EAF error code and convert to NativeError
fn check_eaf_error(code: c_int) -> Result<(), NativeError> {
    match code {
        0 => Ok(()),
        1 => Err(NativeError::InvalidDevice(
            "EAF_ERROR_INVALID_INDEX".to_string(),
        )),
        2 => Err(NativeError::InvalidDevice(
            "EAF_ERROR_INVALID_ID".to_string(),
        )),
        3 => Err(NativeError::InvalidParameter(
            "EAF_ERROR_INVALID_VALUE".to_string(),
        )),
        4 => Err(NativeError::Disconnected),
        5 => Err(NativeError::SdkError(
            "EAF_ERROR_MOVING: Focuser is moving".to_string(),
        )),
        6 => Err(NativeError::SdkError(
            "EAF_ERROR_ERROR_STATE: Focuser in error state".to_string(),
        )),
        7 => Err(NativeError::SdkError("EAF_ERROR_GENERAL_ERROR".to_string())),
        8 => Err(NativeError::NotSupported),
        9 => Err(NativeError::NotConnected),
        _ => Err(NativeError::SdkError(format!(
            "Unknown EAF error code: {}",
            code
        ))),
    }
}

// =============================================================================
// ZWO FOCUSER IMPLEMENTATION
// =============================================================================

/// ZWO EAF Focuser implementation
#[derive(Debug)]
pub struct ZwoFocuser {
    focuser_id: i32,
    device_id: String,
    connected: bool,
    max_position: i32,
    name: String,
    /// Microns of mechanical travel per motor step, resolved at connect time from the
    /// quirks database keyed by the SDK-reported model name. The EAF SDK does not
    /// expose this value, so absent a quirks entry we cannot honestly answer
    /// `get_step_size`; tracking it here lets us fail loudly instead of guessing.
    step_size_um: Option<f64>,
}

impl ZwoFocuser {
    /// Create a new ZWO focuser instance
    pub fn new(focuser_id: i32) -> Self {
        Self {
            focuser_id,
            device_id: format!("native:zwo:eaf:{}", focuser_id),
            connected: false,
            max_position: 0,
            name: format!("ZWO EAF {}", focuser_id),
            step_size_um: None,
        }
    }
}

#[async_trait]
impl NativeDevice for ZwoFocuser {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Zwo
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        tracing::info!("Connecting to ZWO EAF focuser ID {}...", self.focuser_id);

        let sdk = EafSdk::get().ok_or_else(|| {
            tracing::error!("Cannot connect to ZWO EAF: EAF SDK not loaded");
            NativeError::SdkNotLoaded
        })?;

        // Acquire mutex for EAF SDK operations
        let _lock = zwo_eaf_mutex().lock().await;

        // Open focuser
        // SAFETY: zwo_eaf_mutex held above; focuser_id comes from discover_focusers() via EAFGetID() so it's a valid SDK-issued identifier.
        let result = unsafe { (sdk.open)(self.focuser_id) };
        check_eaf_error(result)?;

        // Create cleanup guard to close the focuser if subsequent operations fail
        let focuser_id = self.focuser_id;
        let cleanup_guard = CleanupGuard::new(|| {
            tracing::debug!(
                "Cleaning up ZWO EAF focuser {} after failed connect",
                focuser_id
            );
            if let Some(sdk) = EafSdk::get() {
                // SAFETY: best-effort cleanup; focuser_id was successfully opened above (guard only runs if we got past open). Mutex is still held from the connect() scope when this drops.
                let _ = unsafe { (sdk.close)(focuser_id) };
            }
        });

        // Get properties
        // SAFETY: EAFInfo is `#[repr(C)]` POD; zeroed is a valid initial state.
        let mut info: EAFInfo = unsafe { std::mem::zeroed() };
        // SAFETY: zwo_eaf_mutex held by connect(); `info` is a valid stack pointer; focuser_id was successfully opened above.
        let result = unsafe { (sdk.get_property)(self.focuser_id, &mut info) };
        check_eaf_error(result)?;

        self.max_position = info.max_step;
        self.name = safe_cstr_to_string(info.name.as_ptr(), 64);

        // Resolve step size via the quirks DB using the SDK-reported model as the
        // matchable token. The model lives only in `name`, never in `device_id`,
        // so a synthesized lookup id is required for ModelContains matchers
        // ("EAF-S", "EAF-2", "EAF") to differentiate the gear-ratio variants.
        let lookup_id = format!("native:zwo:{}", self.name);
        self.step_size_um = crate::quirks::get_focuser_step_size_um(&lookup_id);
        if self.step_size_um.is_none() {
            tracing::warn!(
                "ZWO EAF model '{}' has no step-size quirk entry; get_step_size will return an error",
                self.name
            );
        }

        // All operations succeeded - defuse the cleanup guard
        cleanup_guard.defuse();

        self.connected = true;
        tracing::info!(
            "Connected to ZWO EAF: {} (max step: {}, step size: {:?} um)",
            self.name,
            self.max_position,
            self.step_size_um
        );
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Ok(());
        }

        tracing::info!(
            "Disconnecting from ZWO EAF focuser ID {}...",
            self.focuser_id
        );

        let sdk = EafSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_eaf_mutex().lock().await;
        // SAFETY: zwo_eaf_mutex held above; focuser_id is valid because self.connected is true (only set after successful connect()).
        let result = unsafe { (sdk.close)(self.focuser_id) };
        check_eaf_error(result)?;

        self.connected = false;
        tracing::info!("Disconnected from ZWO EAF");
        Ok(())
    }
}

#[async_trait]
impl NativeFocuser for ZwoFocuser {
    async fn move_to(&mut self, position: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = EafSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_eaf_mutex().lock().await;

        // Clamp position to valid range
        let target = position.clamp(0, self.max_position);

        tracing::debug!("Moving ZWO EAF to position {}", target);
        // SAFETY: zwo_eaf_mutex held above; `target` is clamped to [0, max_position] by the caller; focuser_id is valid (connected=true checked).
        let result = unsafe { (sdk.move_to)(self.focuser_id, target) };
        check_eaf_error(result)
    }

    async fn move_relative(&mut self, steps: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let current = self.get_position().await?;
        let target = (current + steps).clamp(0, self.max_position);
        self.move_to(target).await
    }

    async fn get_position(&self) -> Result<i32, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = EafSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_eaf_mutex().lock().await;
        let mut position: c_int = 0;
        // SAFETY: zwo_eaf_mutex held above; `position` is a valid stack pointer; focuser_id is valid (connected=true checked).
        let result = unsafe { (sdk.get_position)(self.focuser_id, &mut position) };
        check_eaf_error(result)?;
        Ok(position)
    }

    async fn is_moving(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = EafSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_eaf_mutex().lock().await;
        let mut is_moving = false;
        let mut hand_control = false;
        // SAFETY: zwo_eaf_mutex held above; both out-bool pointers point to valid stack bools (SDK writes 0 or 1); focuser_id is valid (connected=true checked).
        let result = unsafe { (sdk.is_moving)(self.focuser_id, &mut is_moving, &mut hand_control) };
        check_eaf_error(result)?;
        Ok(is_moving)
    }

    async fn halt(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = EafSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_eaf_mutex().lock().await;
        tracing::debug!("Stopping ZWO EAF movement");
        // SAFETY: zwo_eaf_mutex held above; focuser_id is valid (connected=true checked).
        let result = unsafe { (sdk.stop)(self.focuser_id) };
        check_eaf_error(result)
    }

    async fn get_temperature(&self) -> Result<Option<f64>, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = EafSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_eaf_mutex().lock().await;
        let mut temp: f32 = 0.0;
        // SAFETY: zwo_eaf_mutex held above; `temp` is a valid stack pointer; focuser_id is valid (connected=true checked).
        let result = unsafe { (sdk.get_temp)(self.focuser_id, &mut temp) };

        // Temperature of -273 means invalid/unavailable
        if result == 0 && temp > -273.0 {
            Ok(Some(temp as f64))
        } else {
            Ok(None)
        }
    }

    fn get_max_position(&self) -> i32 {
        self.max_position
    }

    fn get_step_size(&self) -> f64 {
        // Resolved at connect time from the quirks DB; 0.0 here is the contract
        // the trait offers for "unknown" and is surfaced to callers as such. The
        // tracing::error makes the missing-entry case loud and diagnosable rather
        // than a silent guess that propagates into the focus model micron axis.
        match self.step_size_um {
            Some(um) => um,
            None => {
                tracing::error!(
                    "ZWO EAF '{}' has no step-size quirk entry; returning 0.0 to signal unknown",
                    self.name
                );
                0.0
            }
        }
    }
}

impl ZwoFocuser {
    /// Move focuser to position and wait for completion with timeout.
    ///
    /// This is a convenience method that combines `move_to` with waiting for
    /// the move to complete, with timeout protection.
    ///
    /// # Arguments
    /// * `position` - Target position to move to
    /// * `config` - Timeout configuration
    ///
    /// # Returns
    /// * `Ok(())` - Move completed successfully
    /// * `Err(NativeError::MoveTimeout)` - Move did not complete within timeout
    pub async fn move_to_with_timeout(
        &mut self,
        position: i32,
        config: &NativeTimeoutConfig,
    ) -> Result<(), NativeError> {
        // Start the move
        self.move_to(position).await?;

        // Wait for move to complete
        wait_for_focuser_move(|| async { self.is_moving().await }, config, position).await
    }

    /// Move focuser relative and wait for completion with timeout.
    ///
    /// # Arguments
    /// * `steps` - Number of steps to move (positive = outward, negative = inward)
    /// * `config` - Timeout configuration
    ///
    /// # Returns
    /// * `Ok(())` - Move completed successfully
    /// * `Err(NativeError::MoveTimeout)` - Move did not complete within timeout
    pub async fn move_relative_with_timeout(
        &mut self,
        steps: i32,
        config: &NativeTimeoutConfig,
    ) -> Result<(), NativeError> {
        // Calculate target position
        let current = self.get_position().await?;
        let target = (current + steps).clamp(0, self.max_position);

        // Use move_to_with_timeout
        self.move_to_with_timeout(target, config).await
    }
}

// =============================================================================
// ZWO FOCUSER DISCOVERY
// =============================================================================

/// ZWO focuser discovery info
pub struct ZwoFocuserDiscoveryInfo {
    pub focuser_id: i32,
    pub name: String,
    pub serial_number: Option<String>,
    pub discovery_index: usize,
}

/// Check if EAF SDK is available
pub fn is_eaf_sdk_available() -> bool {
    EafSdk::get().is_some()
}

/// Get EAF SDK status
pub fn get_eaf_sdk_status() -> (bool, String) {
    match EafSdk::get() {
        Some(_) => (true, "ZWO EAF SDK loaded successfully".to_string()),
        None => (
            false,
            "ZWO EAF SDK (EAF_focuser.dll) not found.".to_string(),
        ),
    }
}

/// Discover ZWO EAF focusers
pub async fn discover_focusers() -> Result<Vec<ZwoFocuserDiscoveryInfo>, NativeError> {
    let sdk = match EafSdk::get() {
        Some(sdk) => sdk,
        None => {
            tracing::debug!("ZWO EAF discovery skipped: EAF SDK not loaded");
            return Ok(Vec::new());
        }
    };

    // Acquire mutex for EAF SDK discovery operations
    let _lock = zwo_eaf_mutex().lock().await;

    tracing::debug!("Discovering ZWO EAF focusers via native SDK...");
    // SAFETY: zwo_eaf_mutex held above; EAFGetNum takes no arguments and only reads internal SDK state.
    let num_focusers = unsafe { (sdk.get_num)() };
    tracing::info!("EAF SDK reports {} connected focuser(s)", num_focusers);

    let mut focusers = Vec::new();

    for i in 0..num_focusers {
        let mut id: c_int = 0;
        // SAFETY: zwo_eaf_mutex held above; `i` is bounded by num_focusers; `id` is a valid stack pointer.
        let result = unsafe { (sdk.get_id)(i, &mut id) };

        if result == 0 {
            // Get focuser info
            // SAFETY: zwo_eaf_mutex held above; `id` was just populated by EAFGetID, a valid SDK identifier.
            let result = unsafe { (sdk.open)(id) };
            if result == 0 {
                // SAFETY: EAFInfo is `#[repr(C)]` POD; zeroed is a valid initial state.
                let mut info: EAFInfo = unsafe { std::mem::zeroed() };
                // SAFETY: mutex held; `info` is a valid stack pointer; `id` was just successfully opened.
                let _ = unsafe { (sdk.get_property)(id, &mut info) };
                // SAFETY: ASI SDK guarantees `info.name` is NUL-terminated within the 64-byte array.
                let name = unsafe {
                    CStr::from_ptr(info.name.as_ptr())
                        .to_string_lossy()
                        .to_string()
                };

                // Try to get serial number (must be done before close)
                // SAFETY: EAFSerialNumber is `#[repr(C)]` POD (just `id: [u8; 8]`); zeroed is valid.
                let mut sn: EAFSerialNumber = unsafe { std::mem::zeroed() };
                // SAFETY: mutex held; `sn` is a valid stack pointer; `id` is open.
                let serial_number = if unsafe { (sdk.get_serial_number)(id, &mut sn) } == 0 {
                    let sn_bytes: [u8; 8] = sn.id;
                    let sn_str = sn_bytes
                        .iter()
                        .take_while(|&&b| b != 0)
                        .map(|&b| format!("{:02X}", b))
                        .collect::<String>();
                    if sn_str.is_empty() {
                        None
                    } else {
                        Some(sn_str)
                    }
                } else {
                    None
                };

                // SAFETY: mutex held; `id` was successfully opened above. EAFClose pairs with EAFOpen.
                let _ = unsafe { (sdk.close)(id) };

                tracing::info!(
                    "Found ZWO EAF: {} (ID: {}, SN: {:?})",
                    name,
                    id,
                    serial_number
                );
                focusers.push(ZwoFocuserDiscoveryInfo {
                    focuser_id: id,
                    name,
                    serial_number,
                    discovery_index: i as usize,
                });
            }
        }
    }

    Ok(focusers)
}

// =============================================================================
// ZWO EFW FILTER WHEEL SDK
// =============================================================================

/// EFW Info structure from SDK
#[repr(C)]
#[derive(Debug, Clone)]
struct EFWInfo {
    id: c_int,
    name: [c_char; 64],
    slot_num: c_int,
}

/// EFW Error codes
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
#[allow(non_camel_case_types, dead_code)]
enum EFWError {
    EFW_SUCCESS = 0,
    EFW_ERROR_INVALID_INDEX = 1,
    EFW_ERROR_INVALID_ID = 2,
    EFW_ERROR_INVALID_VALUE = 3,
    EFW_ERROR_REMOVED = 4,
    EFW_ERROR_MOVING = 5,
    EFW_ERROR_ERROR_STATE = 6,
    EFW_ERROR_GENERAL_ERROR = 7,
    EFW_ERROR_NOT_SUPPORTED = 8,
    EFW_ERROR_CLOSED = 9,
    EFW_ERROR_END = -1,
}

/// EFW ID/Serial Number structure
#[repr(C)]
#[derive(Debug, Clone)]
struct EFWSerialNumber {
    id: [c_uchar; 8],
}

/// Candidate library paths for the ZWO EFW (electronic filter wheel) SDK.
fn efw_candidate_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if cfg!(target_os = "windows") {
        paths.push(PathBuf::from("EFW_filter.dll"));
    } else if cfg!(target_os = "macos") {
        paths.push(PathBuf::from("libEFW_filter.dylib"));
    } else {
        paths.push(PathBuf::from("libEFW_filter.so"));
    }
    paths
}

load_vendor_sdk! {
    /// ZWO EFW Filter Wheel SDK function-pointer table.
    vendor_name: "ZWO EFW Filter Wheel",
    sdk_struct: EfwSdk,
    sdk_static: EFW_SDK,
    candidate_paths_fn: efw_candidate_paths,
    symbols: {
        get_num: b"EFWGetNum\0"
            => unsafe extern "C" fn() -> c_int,
        get_id: b"EFWGetID\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        open: b"EFWOpen\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        close: b"EFWClose\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        get_property: b"EFWGetProperty\0"
            => unsafe extern "C" fn(c_int, *mut EFWInfo) -> c_int,
        get_position: b"EFWGetPosition\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        set_position: b"EFWSetPosition\0"
            => unsafe extern "C" fn(c_int, c_int) -> c_int,
        set_direction: b"EFWSetDirection\0"
            => unsafe extern "C" fn(c_int, bool) -> c_int,
        get_direction: b"EFWGetDirection\0"
            => unsafe extern "C" fn(c_int, *mut bool) -> c_int,
        calibrate: b"EFWCalibrate\0"
            => unsafe extern "C" fn(c_int) -> c_int,
        get_sdk_version: b"EFWGetSDKVersion\0"
            => unsafe extern "C" fn() -> *const c_char,
        get_hw_error_code: b"EFWGetHWErrorCode\0"
            => unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
        get_firmware_version: b"EFWGetFirmwareVersion\0"
            => unsafe extern "C" fn(c_int, *mut c_uchar, *mut c_uchar, *mut c_uchar) -> c_int,
        get_serial_number: b"EFWGetSerialNumber\0"
            => unsafe extern "C" fn(c_int, *mut EFWSerialNumber) -> c_int,
    }
}

/// Check EFW error code and convert to NativeError
fn check_efw_error(code: c_int) -> Result<(), NativeError> {
    match code {
        0 => Ok(()),
        1 => Err(NativeError::InvalidDevice(
            "EFW_ERROR_INVALID_INDEX".to_string(),
        )),
        2 => Err(NativeError::InvalidDevice(
            "EFW_ERROR_INVALID_ID".to_string(),
        )),
        3 => Err(NativeError::InvalidParameter(
            "EFW_ERROR_INVALID_VALUE".to_string(),
        )),
        4 => Err(NativeError::Disconnected),
        5 => Err(NativeError::SdkError(
            "EFW_ERROR_MOVING: Filter wheel is moving".to_string(),
        )),
        6 => Err(NativeError::SdkError(
            "EFW_ERROR_ERROR_STATE: Filter wheel in error state".to_string(),
        )),
        7 => Err(NativeError::SdkError("EFW_ERROR_GENERAL_ERROR".to_string())),
        8 => Err(NativeError::NotSupported),
        9 => Err(NativeError::NotConnected),
        _ => Err(NativeError::SdkError(format!(
            "Unknown EFW error code: {}",
            code
        ))),
    }
}

// =============================================================================
// ZWO FILTER WHEEL IMPLEMENTATION
// =============================================================================

/// ZWO EFW Filter Wheel implementation
#[derive(Debug)]
pub struct ZwoFilterWheel {
    filterwheel_id: i32,
    device_id: String,
    connected: bool,
    slot_count: i32,
    name: String,
    filter_names: Vec<String>,
}

impl ZwoFilterWheel {
    /// Create a new ZWO filter wheel instance
    pub fn new(filterwheel_id: i32) -> Self {
        Self {
            filterwheel_id,
            device_id: format!("native:zwo:efw:{}", filterwheel_id),
            connected: false,
            slot_count: 0,
            name: format!("ZWO EFW {}", filterwheel_id),
            filter_names: Vec::new(),
        }
    }
}

#[async_trait]
impl NativeDevice for ZwoFilterWheel {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Zwo
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        tracing::info!(
            "Connecting to ZWO EFW filter wheel ID {}...",
            self.filterwheel_id
        );

        let sdk = EfwSdk::get().ok_or_else(|| {
            tracing::error!("Cannot connect to ZWO EFW: EFW SDK not loaded");
            NativeError::SdkNotLoaded
        })?;

        // Acquire mutex for EFW SDK operations
        let _lock = zwo_efw_mutex().lock().await;

        // Open filter wheel
        // SAFETY: zwo_efw_mutex held above; filterwheel_id comes from discover_filter_wheels() via EFWGetID(), a valid SDK-issued identifier.
        let result = unsafe { (sdk.open)(self.filterwheel_id) };
        check_efw_error(result)?;

        // Create cleanup guard to close the filter wheel if subsequent operations fail
        let filterwheel_id = self.filterwheel_id;
        let cleanup_guard = CleanupGuard::new(|| {
            tracing::debug!(
                "Cleaning up ZWO EFW filter wheel {} after failed connect",
                filterwheel_id
            );
            if let Some(sdk) = EfwSdk::get() {
                // SAFETY: best-effort cleanup; filterwheel_id was successfully opened above (guard only runs after open succeeded). Mutex still held when this drop runs in connect() scope.
                let _ = unsafe { (sdk.close)(filterwheel_id) };
            }
        });

        // Get properties
        // SAFETY: EFWInfo is `#[repr(C)]` POD; zeroed is a valid initial state.
        let mut info: EFWInfo = unsafe { std::mem::zeroed() };
        // SAFETY: zwo_efw_mutex held by connect(); `info` is a valid stack pointer; filterwheel_id was successfully opened above.
        let result = unsafe { (sdk.get_property)(self.filterwheel_id, &mut info) };
        check_efw_error(result)?;

        self.slot_count = info.slot_num;
        self.name = safe_cstr_to_string(info.name.as_ptr(), 64);

        // Initialize default filter names
        self.filter_names = (0..self.slot_count)
            .map(|i| format!("Filter {}", i + 1))
            .collect();

        // All operations succeeded - defuse the cleanup guard
        cleanup_guard.defuse();

        self.connected = true;

        // Drop the mutex before the async sleep so other operations aren't blocked
        drop(_lock);

        // Give the firmware time to read the encoder position after EFWOpen.
        // Some ZWO EFW firmware returns position 0 or -1 immediately after open
        // because the encoder hasn't been polled yet. A short settle delay lets
        // the firmware synchronise with the physical slot position.
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        // Read initial position to pre-warm the SDK and verify it works
        {
            let _lock = zwo_efw_mutex().lock().await;
            let mut position: c_int = -999;
            // SAFETY: zwo_efw_mutex held in this inner scope; `position` is a valid stack pointer; filterwheel_id is valid (already opened in this connect() above).
            let result = unsafe { (sdk.get_position)(self.filterwheel_id, &mut position) };
            tracing::info!(
                "[ZWO EFW] Post-connect initial position read: hw_id={}, SDK result={}, position={}",
                self.filterwheel_id,
                result,
                position
            );
        }

        tracing::info!(
            "Connected to ZWO EFW: {} ({} slots)",
            self.name,
            self.slot_count
        );
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Ok(());
        }

        tracing::info!(
            "Disconnecting from ZWO EFW filter wheel ID {}...",
            self.filterwheel_id
        );

        let sdk = EfwSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_efw_mutex().lock().await;
        // SAFETY: zwo_efw_mutex held above; filterwheel_id is valid because self.connected is true (only set after successful connect()).
        let result = unsafe { (sdk.close)(self.filterwheel_id) };
        check_efw_error(result)?;

        self.connected = false;
        tracing::info!("Disconnected from ZWO EFW");
        Ok(())
    }
}

#[async_trait]
impl NativeFilterWheel for ZwoFilterWheel {
    async fn move_to_position(&mut self, position: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = EfwSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Validate position
        if position < 0 || position >= self.slot_count {
            return Err(NativeError::InvalidParameter(format!(
                "Invalid position {}. Valid range: 0-{}",
                position,
                self.slot_count - 1
            )));
        }

        let _lock = zwo_efw_mutex().lock().await;
        tracing::debug!("Moving ZWO EFW to position {}", position);
        // SAFETY: zwo_efw_mutex held above; `position` was bounds-checked against slot_count earlier in this function; filterwheel_id is valid (connected=true checked).
        let result = unsafe { (sdk.set_position)(self.filterwheel_id, position) };
        check_efw_error(result)
    }

    async fn get_position(&self) -> Result<i32, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = EfwSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_efw_mutex().lock().await;
        let mut position: c_int = -999; // sentinel to detect if SDK writes
        // SAFETY: zwo_efw_mutex held above; `position` is a valid stack pointer; filterwheel_id is valid (connected=true checked).
        let result = unsafe { (sdk.get_position)(self.filterwheel_id, &mut position) };
        tracing::info!(
            "[ZWO EFW] get_position(hw_id={}) => SDK result={}, position={}",
            self.filterwheel_id,
            result,
            position
        );
        check_efw_error(result)?;
        Ok(position)
    }

    async fn is_moving(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = EfwSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = zwo_efw_mutex().lock().await;
        let mut position: c_int = -999; // sentinel to detect if SDK writes
        // SAFETY: zwo_efw_mutex held above; `position` is a valid stack pointer; filterwheel_id is valid (connected=true checked).
        let result = unsafe { (sdk.get_position)(self.filterwheel_id, &mut position) };
        tracing::info!(
            "[ZWO EFW] is_moving(hw_id={}) => SDK result={}, position={}",
            self.filterwheel_id,
            result,
            position
        );
        check_efw_error(result)?;
        // Position is -1 when moving
        Ok(position == -1)
    }

    fn get_filter_count(&self) -> i32 {
        self.slot_count
    }

    async fn get_filter_names(&self) -> Result<Vec<String>, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        Ok(self.filter_names.clone())
    }

    async fn set_filter_name(&mut self, position: i32, name: String) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if position < 0 || position >= self.slot_count {
            return Err(NativeError::InvalidParameter(format!(
                "Invalid position {}. Valid range: 0-{}",
                position,
                self.slot_count - 1
            )));
        }

        self.filter_names[position as usize] = name;
        Ok(())
    }
}

impl ZwoFilterWheel {
    /// Move filter wheel to position and wait for completion with timeout.
    ///
    /// This is a convenience method that combines `move_to_position` with waiting for
    /// the move to complete, with timeout protection.
    ///
    /// # Arguments
    /// * `position` - Target filter slot (0-indexed)
    /// * `config` - Timeout configuration
    ///
    /// # Returns
    /// * `Ok(())` - Move completed successfully
    /// * `Err(NativeError::MoveTimeout)` - Move did not complete within timeout
    pub async fn move_to_position_with_timeout(
        &mut self,
        position: i32,
        config: &NativeTimeoutConfig,
    ) -> Result<(), NativeError> {
        // Start the move
        self.move_to_position(position).await?;

        // Wait for move to complete
        wait_for_filterwheel_move(|| async { self.is_moving().await }, config, position).await
    }
}

// =============================================================================
// ZWO FILTER WHEEL DISCOVERY
// =============================================================================

/// ZWO filter wheel discovery info
pub struct ZwoFilterWheelDiscoveryInfo {
    pub filterwheel_id: i32,
    pub name: String,
    pub slot_count: i32,
    pub serial_number: Option<String>,
    pub discovery_index: usize,
}

/// Check if EFW SDK is available
pub fn is_efw_sdk_available() -> bool {
    EfwSdk::get().is_some()
}

/// Get EFW SDK status
pub fn get_efw_sdk_status() -> (bool, String) {
    match EfwSdk::get() {
        Some(_) => (true, "ZWO EFW SDK loaded successfully".to_string()),
        None => (false, "ZWO EFW SDK (EFW_filter.dll) not found.".to_string()),
    }
}

/// Discover ZWO EFW filter wheels
pub async fn discover_filter_wheels() -> Result<Vec<ZwoFilterWheelDiscoveryInfo>, NativeError> {
    let sdk = match EfwSdk::get() {
        Some(sdk) => sdk,
        None => {
            tracing::debug!("ZWO EFW discovery skipped: EFW SDK not loaded");
            return Ok(Vec::new());
        }
    };

    // Acquire mutex for EFW SDK discovery operations
    let _lock = zwo_efw_mutex().lock().await;

    tracing::debug!("Discovering ZWO EFW filter wheels via native SDK...");
    // SAFETY: zwo_efw_mutex held above; EFWGetNum takes no arguments and only reads internal SDK state.
    let num_wheels = unsafe { (sdk.get_num)() };
    tracing::info!("EFW SDK reports {} connected filter wheel(s)", num_wheels);

    let mut wheels = Vec::new();

    for i in 0..num_wheels {
        let mut id: c_int = 0;
        // SAFETY: zwo_efw_mutex held above; `i` is bounded by num_wheels; `id` is a valid stack pointer.
        let result = unsafe { (sdk.get_id)(i, &mut id) };

        if result == 0 {
            // Get filter wheel info
            // SAFETY: mutex held; `id` was just populated by EFWGetID.
            let result = unsafe { (sdk.open)(id) };
            if result == 0 {
                // SAFETY: EFWInfo is `#[repr(C)]` POD; zeroed is a valid initial state.
                let mut info: EFWInfo = unsafe { std::mem::zeroed() };
                // SAFETY: mutex held; `info` is a valid stack pointer; `id` was just successfully opened.
                let _ = unsafe { (sdk.get_property)(id, &mut info) };
                // SAFETY: ASI SDK guarantees `info.name` is NUL-terminated within the 64-byte array.
                let name = unsafe {
                    CStr::from_ptr(info.name.as_ptr())
                        .to_string_lossy()
                        .to_string()
                };
                let slot_count = info.slot_num;

                // Try to get serial number (must be done before close)
                // SAFETY: EFWSerialNumber is `#[repr(C)]` POD (just `id: [u8; 8]`); zeroed is valid.
                let mut sn: EFWSerialNumber = unsafe { std::mem::zeroed() };
                // SAFETY: mutex held; `sn` is a valid stack pointer; `id` is open.
                let serial_number = if unsafe { (sdk.get_serial_number)(id, &mut sn) } == 0 {
                    let sn_bytes: [u8; 8] = sn.id;
                    let sn_str = sn_bytes
                        .iter()
                        .take_while(|&&b| b != 0)
                        .map(|&b| format!("{:02X}", b))
                        .collect::<String>();
                    if sn_str.is_empty() {
                        None
                    } else {
                        Some(sn_str)
                    }
                } else {
                    None
                };

                // SAFETY: mutex held; `id` was successfully opened above. EFWClose pairs with EFWOpen.
                let _ = unsafe { (sdk.close)(id) };

                tracing::info!(
                    "Found ZWO EFW: {} (ID: {}, {} slots, SN: {:?})",
                    name,
                    id,
                    slot_count,
                    serial_number
                );
                wheels.push(ZwoFilterWheelDiscoveryInfo {
                    filterwheel_id: id,
                    name,
                    slot_count,
                    serial_number,
                    discovery_index: i as usize,
                });
            }
        }
    }

    Ok(wheels)
}
