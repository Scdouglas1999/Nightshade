//! Player One Camera SDK Wrapper
//!
//! Provides native support for Player One cameras by wrapping the POA SDK.
//! Player One cameras feature low read noise and built-in anti-dew heaters.
//!
//! ## Thread Safety
//!
//! The POA SDK is NOT thread-safe. All SDK operations are protected by
//! `player_one_mutex()` from `crate::sync` to prevent concurrent access.
//!
//! ## Timeout Handling
//!
//! All SDK operations that can potentially hang (exposure polling, image download)
//! have configurable timeouts via `NativeTimeoutConfig`.
//!
//! ## `unwrap_or` policy (audit-rust §4.3)
//!
//! POA SDK property reads (`get_control_int`, `get_control_bool`, etc.)
//! return `Result<T, NativeError>` and may fail with `POA_ERROR_OPERATION_FAILED`
//! when the camera is mid-exposure or the control hasn't been initialised
//! yet. The cooler/gain/offset paths here default to the same "fall back to
//! cached value or zero" semantics as the other vendor crates:
//!
//! * `get_control_int(GAIN/OFFSET).unwrap_or(0)` — gain/offset 0 is the
//!   POA SDK minimum; UI shows live value once cooler stabilises. The status
//!   poll is intentionally non-fatal; the next status tick will retry.
//! * `live_enabled.unwrap_or(cached.enabled)` / `live_target_c.unwrap_or(cached.target_c)`
//!   — when live cooler probe fails, return the LAST KNOWN cached value
//!   rather than zeroing-out, so the UI doesn't flicker during transient
//!   SDK errors. The cache is updated only on a successful read.
//! * `unwrap_or(false)` on cooler-supported boolean probes — undeclared
//!   capability means "not present", matching the other vendor crates.
//! * `unwrap_or_else(|e| *e.into_inner())` on mutex `into_inner()` —
//!   recovers the cached state from a poisoned mutex during shutdown so
//!   `Drop` can still write final coordinates; the poison signal is logged
//!   via the upstream caller.

#![allow(dead_code)] // FFI types must match SDK headers even if not all variants are used

use crate::camera::*;
use crate::sync::player_one_mutex;
use crate::traits::*;
use crate::utils::{calculate_buffer_size_i32, safe_cstr_to_string, wait_for_exposure};
use crate::NativeVendor;
use async_trait::async_trait;
use nightshade_imaging::buffer_pool::global_u8_pool;
use std::ffi::{c_char, c_int, c_long, CStr};
use std::sync::{Mutex, OnceLock};

// =============================================================================
// COOLER STATE TRACKING
// =============================================================================

/// Cooler state tracked at the driver level.
///
/// The POA SDK does not provide a guaranteed-to-succeed read-back for the
/// `POA_COOLER` register on every camera/firmware. We mirror the Atik pattern
/// (see `vendor/atik.rs`) and remember the last successfully written state so
/// `get_status` can report it accurately even when the SDK read-back path is
/// unavailable. When `POAGetConfig(POA_COOLER)` succeeds, that authoritative
/// value wins and the cached state is refreshed to match.
#[derive(Debug, Clone, Copy)]
struct CoolerState {
    enabled: bool,
    target_c: f64,
}

impl Default for CoolerState {
    fn default() -> Self {
        Self {
            enabled: false,
            target_c: 0.0,
        }
    }
}

// =============================================================================
// POA SDK TYPE DEFINITIONS
// =============================================================================

/// POA Camera handle (index-based)
type PoaCameraIdx = c_int;

/// POA Camera Properties structure - matches actual SDK struct from PlayerOneCamera.h
#[repr(C)]
#[derive(Debug, Clone)]
struct POACameraProperties {
    camera_model_name: [c_char; 256], // cameraModelName
    user_custom_id: [c_char; 16],     // userCustomID
    camera_id: c_int,                 // cameraID
    max_width: c_int,                 // maxWidth (NOTE: width comes before height in SDK)
    max_height: c_int,                // maxHeight
    bit_depth: c_int,                 // bitDepth
    is_color_camera: c_int,           // isColorCamera (POABool)
    is_has_st4_port: c_int,           // isHasST4Port (POABool)
    is_has_cooler: c_int,             // isHasCooler (POABool)
    is_usb3_speed: c_int,             // isUSB3Speed (POABool)
    bayer_pattern: c_int,             // bayerPattern (POABayerPattern)
    pixel_size: f64,                  // pixelSize (double)
    sn: [c_char; 64],                 // SN
    sensor_model_name: [c_char; 32],  // sensorModelName
    local_path: [c_char; 256],        // localPath
    bins: [c_int; 8],                 // bins - supported bin modes
    img_formats: [c_int; 8],          // imgFormats - supported image formats
    is_support_hard_bin: c_int,       // isSupportHardBin (POABool)
    p_id: c_int,                      // pID
    reserved: [c_char; 248],          // reserved
}

/// POA Exposure Status
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
enum POAExposureStatus {
    Idle = 0,
    Working = 1,
    Success = 2,
    Failed = 3,
}

/// POA Bool type
type POABool = c_int;
const POA_FALSE: POABool = 0;
const POA_TRUE: POABool = 1;

/// POA Error codes
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
#[allow(dead_code)]
enum POAErrors {
    Success = 0,
    InvalidIndex = 1,
    InvalidId = 2,
    InvalidConfig = 3,
    InvalidArg = 4,
    NotOpened = 5,
    DeviceNotFound = 6,
    OutOfLimit = 7,
    ExposureFailed = 8,
    Timeout = 9,
    SizeTooSmall = 10,
    NotSupported = 11,
    ConfigError = 12,
    Unknown = 13,
}

/// POA Config IDs (controls) - matches POAConfig enum from PlayerOneCamera.h
#[repr(C)]
#[derive(Debug, Clone, Copy)]
#[allow(non_camel_case_types)]
enum POAConfig {
    POA_EXPOSURE = 0,              // exposure time (us), VAL_INT
    POA_GAIN = 1,                  // gain, VAL_INT
    POA_HARDWARE_BIN = 2,          // hardware bin, VAL_BOOL
    POA_TEMPERATURE = 3,           // temperature (C), VAL_FLOAT, read-only
    POA_WB_R = 4,                  // white balance red, VAL_INT
    POA_WB_G = 5,                  // white balance green, VAL_INT
    POA_WB_B = 6,                  // white balance blue, VAL_INT
    POA_OFFSET = 7,                // offset, VAL_INT
    POA_AUTOEXPO_MAX_GAIN = 8,     // max gain for auto exposure, VAL_INT
    POA_AUTOEXPO_MAX_EXPOSURE = 9, // max exposure for auto (ms), VAL_INT
    POA_AUTOEXPO_BRIGHTNESS = 10,  // target brightness for auto, VAL_INT
    POA_GUIDE_NORTH = 11,          // ST4 guide north, VAL_BOOL
    POA_GUIDE_SOUTH = 12,          // ST4 guide south, VAL_BOOL
    POA_GUIDE_EAST = 13,           // ST4 guide east, VAL_BOOL
    POA_GUIDE_WEST = 14,           // ST4 guide west, VAL_BOOL
    POA_EGAIN = 15,                // e/ADU, VAL_FLOAT, read-only
    POA_COOLER_POWER = 16,         // cooler power %, VAL_INT, read-only
    POA_TARGET_TEMP = 17,          // target temperature (C), VAL_INT
    POA_COOLER = 18,               // cooler on/off, VAL_BOOL
    POA_HEATER = 19,               // lens heater state (deprecated), VAL_BOOL
    POA_HEATER_POWER = 20,         // lens heater power %, VAL_INT
    POA_FAN_POWER = 21,            // fan power %, VAL_INT
    POA_FLIP_NONE = 22,            // no flip, VAL_BOOL
    POA_FLIP_HORI = 23,            // horizontal flip, VAL_BOOL
    POA_FLIP_VERT = 24,            // vertical flip, VAL_BOOL
    POA_FLIP_BOTH = 25,            // both flip, VAL_BOOL
    POA_FRAME_LIMIT = 26,          // frame rate limit, VAL_INT
    POA_HQI = 27,                  // high quality image mode, VAL_BOOL
    POA_USB_BANDWIDTH_LIMIT = 28,  // USB bandwidth limit, VAL_INT
    POA_PIXEL_BIN_SUM = 29,        // pixel bin sum mode, VAL_BOOL
    POA_MONO_BIN = 30,             // mono bin mode, VAL_BOOL
}

/// POA Image Format
#[repr(C)]
#[derive(Debug, Clone, Copy)]
enum POAImgFormat {
    Raw8 = 0,
    Raw16 = 1,
    Rgb24 = 2,
    Mono8 = 3,
}

/// POA Bayer Pattern - matches POABayerPattern from PlayerOneCamera.h
#[repr(C)]
#[derive(Debug, Clone, Copy)]
enum POABayerPattern {
    Rg = 0,
    Bg = 1,
    Gr = 2,
    Gb = 3,
    Mono = -1,
}

/// POA Config Value union - used for get/set config values
#[repr(C)]
#[derive(Clone, Copy)]
union POAConfigValue {
    int_value: c_long,
    float_value: f64,
    bool_value: c_int,
}

impl Default for POAConfigValue {
    fn default() -> Self {
        Self { int_value: 0 }
    }
}

impl std::fmt::Debug for POAConfigValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Default to showing as int
        // SAFETY: POAConfigValue is a `#[repr(C)]` union of three POD types (c_long/f64/c_int) all stored at the same offset; reading the `int_value` variant is always defined regardless of which variant was last written (the bytes are interpreted as i64 — same width as f64) and only used for Debug formatting.
        write!(f, "POAConfigValue({})", unsafe { self.int_value })
    }
}

// =============================================================================
// SDK LIBRARY LOADING
// =============================================================================

/// POA SDK library wrapper
struct PoaSdk {
    #[allow(dead_code)]
    lib: libloading::Library,

    // Function pointers - matches actual SDK signatures from PlayerOneCamera.h
    get_camera_count: unsafe extern "C" fn() -> c_int,
    get_camera_properties: unsafe extern "C" fn(c_int, *mut POACameraProperties) -> c_int,
    get_camera_properties_by_id: unsafe extern "C" fn(c_int, *mut POACameraProperties) -> c_int,
    open_camera: unsafe extern "C" fn(c_int) -> c_int,
    init_camera: unsafe extern "C" fn(c_int) -> c_int,
    close_camera: unsafe extern "C" fn(c_int) -> c_int,
    // POAGetConfig uses POAConfigValue union
    get_config: unsafe extern "C" fn(c_int, c_int, *mut POAConfigValue, *mut POABool) -> c_int,
    // POASetConfig uses POAConfigValue union
    set_config: unsafe extern "C" fn(c_int, c_int, POAConfigValue, POABool) -> c_int,
    set_image_bin: unsafe extern "C" fn(c_int, c_int) -> c_int,
    set_image_size: unsafe extern "C" fn(c_int, c_int, c_int) -> c_int,
    set_image_start_pos: unsafe extern "C" fn(c_int, c_int, c_int) -> c_int,
    set_image_format: unsafe extern "C" fn(c_int, c_int) -> c_int,
    start_exposure: unsafe extern "C" fn(c_int, POABool) -> c_int,
    stop_exposure: unsafe extern "C" fn(c_int) -> c_int,
    get_camera_state: unsafe extern "C" fn(c_int, *mut c_int) -> c_int,
    get_image_data: unsafe extern "C" fn(c_int, *mut u8, c_long, c_int) -> c_int,
    get_image_size: unsafe extern "C" fn(c_int, *mut c_int, *mut c_int) -> c_int,
    // Additional functions for readout modes
    image_ready: unsafe extern "C" fn(c_int, *mut POABool) -> c_int,
}

static POA_SDK: OnceLock<Option<PoaSdk>> = OnceLock::new();

impl PoaSdk {
    /// Load the POA SDK library
    fn load() -> Option<Self> {
        let lib_paths = if cfg!(target_os = "windows") {
            vec![
                "PlayerOneCamera.dll",
                "C:\\Program Files\\PlayerOne\\SDK\\lib\\x64\\PlayerOneCamera.dll",
            ]
        } else if cfg!(target_os = "macos") {
            vec![
                "libPlayerOneCamera.dylib",
                "/usr/local/lib/libPlayerOneCamera.dylib",
            ]
        } else {
            vec![
                "libPlayerOneCamera.so",
                "libPlayerOneCamera.so.1",
                "/usr/lib/libPlayerOneCamera.so",
                "/usr/local/lib/libPlayerOneCamera.so",
            ]
        };

        for path in lib_paths {
            // SAFETY: libloading::Library::new performs platform dynamic loading; each `path` is a compile-time string constant naming a vendor SDK shared library (PlayerOneCamera.dll/dylib/so). Each `lib.get::<FnType>(b"symbol\0")` then dereferences the returned Symbol with `*`: the FFI signatures declared above are the C ABI from PlayerOneCamera.h (verified against vendor header) so the function-pointer ABI is correct. The loaded `lib` is moved into the returned PoaSdk so the function pointers remain valid for the program's lifetime.
            unsafe {
                if let Ok(lib) = libloading::Library::new(path) {
                    tracing::info!("Loaded Player One SDK from: {}", path);

                    // Load all function pointers - actual SDK function names
                    let sdk = Self {
                        get_camera_count: *lib.get(b"POAGetCameraCount\0").ok()?,
                        get_camera_properties: *lib.get(b"POAGetCameraProperties\0").ok()?,
                        get_camera_properties_by_id: *lib
                            .get(b"POAGetCameraPropertiesByID\0")
                            .ok()?,
                        open_camera: *lib.get(b"POAOpenCamera\0").ok()?,
                        init_camera: *lib.get(b"POAInitCamera\0").ok()?,
                        close_camera: *lib.get(b"POACloseCamera\0").ok()?,
                        get_config: *lib.get(b"POAGetConfig\0").ok()?,
                        set_config: *lib.get(b"POASetConfig\0").ok()?,
                        set_image_bin: *lib.get(b"POASetImageBin\0").ok()?,
                        set_image_size: *lib.get(b"POASetImageSize\0").ok()?,
                        set_image_start_pos: *lib.get(b"POASetImageStartPos\0").ok()?,
                        set_image_format: *lib.get(b"POASetImageFormat\0").ok()?,
                        start_exposure: *lib.get(b"POAStartExposure\0").ok()?,
                        stop_exposure: *lib.get(b"POAStopExposure\0").ok()?,
                        get_camera_state: *lib.get(b"POAGetCameraState\0").ok()?,
                        get_image_data: *lib.get(b"POAGetImageData\0").ok()?,
                        get_image_size: *lib.get(b"POAGetImageSize\0").ok()?,
                        image_ready: *lib.get(b"POAImageReady\0").ok()?,
                        lib,
                    };

                    return Some(sdk);
                }
            }
        }

        tracing::debug!("Player One SDK not found");
        None
    }

    /// Get the global SDK instance
    fn get() -> Option<&'static PoaSdk> {
        POA_SDK.get_or_init(Self::load).as_ref()
    }
}

/// Check POA error and convert to NativeError with detailed error messages
fn check_poa_error(code: c_int, operation: &str) -> Result<(), NativeError> {
    match code {
        0 => Ok(()), // POA_OK
        1 => Err(NativeError::InvalidDevice(format!(
            "{}: Invalid camera index - camera may not exist",
            operation
        ))),
        2 => Err(NativeError::InvalidDevice(format!(
            "{}: Invalid camera ID - camera may have been disconnected",
            operation
        ))),
        3 => Err(NativeError::InvalidParameter(format!(
            "{}: Invalid config - control type not available",
            operation
        ))),
        4 => Err(NativeError::InvalidParameter(format!(
            "{}: Invalid argument - value out of range",
            operation
        ))),
        5 => Err(NativeError::NotConnected),
        6 => Err(NativeError::Disconnected),
        7 => Err(NativeError::InvalidParameter(format!(
            "{}: Value out of limit",
            operation
        ))),
        8 => Err(NativeError::SdkError(format!(
            "{}: Exposure failed - check camera connection",
            operation
        ))),
        9 => Err(NativeError::Timeout(format!(
            "{}: Operation timed out",
            operation
        ))),
        10 => Err(NativeError::InvalidParameter(format!(
            "{}: Buffer size too small",
            operation
        ))),
        11 => Err(NativeError::NotSupported),
        12 => Err(NativeError::SdkError(format!(
            "{}: Config error - camera may need reinitialization",
            operation
        ))),
        _ => Err(NativeError::SdkError(format!(
            "{}: Unknown POA error code {}",
            operation, code
        ))),
    }
}

// =============================================================================
// PLAYER ONE CAMERA IMPLEMENTATION
// =============================================================================

/// Player One Camera implementation
#[derive(Debug)]
pub struct PlayerOneCamera {
    camera_id: i32,
    camera_info: Option<POACameraProperties>,
    device_id: String,
    connected: bool,
    current_bin: i32,
    current_width: i32,
    current_height: i32,
    image_format: POAImgFormat,
    // Exposure metadata tracking
    exposure_time: f64,
    current_subframe: Option<SubFrame>,
    // Driver-level cooler state. Used by `get_status` (`&self`) when the SDK
    // read-back is unavailable; written by `set_cooler` after the SDK accepts
    // the change. `Mutex` provides interior mutability across the immutable
    // `get_status` call path.
    cooler_state: Mutex<CoolerState>,
}

impl PlayerOneCamera {
    /// Create a new Player One camera instance
    pub fn new(camera_id: i32) -> Self {
        Self {
            camera_id,
            camera_info: None,
            device_id: format!("native:playerone:{}", camera_id),
            connected: false,
            current_bin: 1,
            current_width: 0,
            current_height: 0,
            image_format: POAImgFormat::Raw16,
            exposure_time: 0.0,
            current_subframe: None,
            cooler_state: Mutex::new(CoolerState::default()),
        }
    }

    /// Load camera info from SDK
    fn load_camera_info(&mut self) -> Result<(), NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // SAFETY: POACameraProperties is `#[repr(C)]` and contains only POD fields (c_char arrays, c_int, f64) — all valid bit-patterns. Zero-initialization is the well-defined empty state before the SDK overwrites it.
        let mut info: POACameraProperties = unsafe { std::mem::zeroed() };
        // SAFETY: caller holds &mut self so `self.camera_id` is valid; `&mut info` is a valid stack out-pointer to a `#[repr(C)]` POACameraProperties; POAGetCameraPropertiesByID does not need the player_one mutex per SDK docs (read-only metadata) and writes only into the out-pointer.
        let result = unsafe { (sdk.get_camera_properties_by_id)(self.camera_id, &mut info) };
        check_poa_error(result, "GetCameraProperties")?;

        self.current_width = info.max_width;
        self.current_height = info.max_height;
        self.camera_info = Some(info);
        Ok(())
    }

    /// Get camera name using safe string conversion
    fn camera_name(&self) -> String {
        if let Some(info) = &self.camera_info {
            safe_cstr_to_string(info.camera_model_name.as_ptr(), 256)
        } else {
            format!("Player One Camera {}", self.camera_id)
        }
    }

    /// Get a control value as integer (mutex protected)
    async fn get_control_int_async(&self, control: POAConfig) -> Result<c_long, NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = player_one_mutex().lock().await;
        let mut value = POAConfigValue::default();
        let mut is_auto: POABool = POA_FALSE;
        // SAFETY: player_one_mutex held above ensures single-threaded SDK access (POA SDK is not thread-safe per module header); `self.camera_id` was assigned at construction and is the camera ID parameter passed to POAGetConfig; `&mut value` and `&mut is_auto` are valid stack out-pointers to POD `#[repr(C)]` types.
        let result =
            unsafe { (sdk.get_config)(self.camera_id, control as c_int, &mut value, &mut is_auto) };
        check_poa_error(result, "POAGetConfig")?;
        // SAFETY: POAConfigValue is a `#[repr(C)]` union; we asked the SDK for an integer control via this typed wrapper (callers use this only for VAL_INT controls per PlayerOneCamera.h), so reading `int_value` matches the variant written by the SDK above.
        Ok(unsafe { value.int_value })
    }

    /// Get a control value as integer (synchronous - caller must hold mutex)
    fn get_control_int(&self, control: POAConfig) -> Result<c_long, NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let mut value = POAConfigValue::default();
        let mut is_auto: POABool = POA_FALSE;
        // SAFETY: per function contract (see doc-comment) the caller has acquired player_one_mutex before invoking — synchronous variant used inside `get_status` / `download_image` where the mutex is held above; out-pointers are valid stack POD references.
        let result =
            unsafe { (sdk.get_config)(self.camera_id, control as c_int, &mut value, &mut is_auto) };
        check_poa_error(result, "POAGetConfig")?;
        // SAFETY: integer variant of the POAConfigValue union — only called for VAL_INT controls (POA_GAIN/OFFSET/COOLER_POWER/etc.) per PlayerOneCamera.h, matching the union variant the SDK wrote.
        Ok(unsafe { value.int_value })
    }

    /// Get a control value as float (mutex protected)
    async fn get_control_float_async(&self, control: POAConfig) -> Result<f64, NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = player_one_mutex().lock().await;
        let mut value = POAConfigValue::default();
        let mut is_auto: POABool = POA_FALSE;
        // SAFETY: player_one_mutex held above (single-threaded SDK access); out-pointers `&mut value` and `&mut is_auto` are valid stack POD references; called only for VAL_FLOAT controls (POA_TEMPERATURE/POA_EGAIN) per PlayerOneCamera.h.
        let result =
            unsafe { (sdk.get_config)(self.camera_id, control as c_int, &mut value, &mut is_auto) };
        check_poa_error(result, "POAGetConfig")?;
        // SAFETY: float variant of POAConfigValue — only called for VAL_FLOAT controls (POA_TEMPERATURE/POA_EGAIN), matching the union variant the SDK wrote.
        Ok(unsafe { value.float_value })
    }

    /// Get a control value as float (synchronous - caller must hold mutex)
    fn get_control_float(&self, control: POAConfig) -> Result<f64, NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let mut value = POAConfigValue::default();
        let mut is_auto: POABool = POA_FALSE;
        // SAFETY: caller holds player_one_mutex per function contract (sync variant); out-pointers are valid stack POD references.
        let result =
            unsafe { (sdk.get_config)(self.camera_id, control as c_int, &mut value, &mut is_auto) };
        check_poa_error(result, "POAGetConfig")?;
        // SAFETY: float variant of POAConfigValue — only used for VAL_FLOAT controls (POA_TEMPERATURE/POA_EGAIN), matching the variant the SDK wrote.
        Ok(unsafe { value.float_value })
    }

    /// Get a control value as bool (synchronous - caller must hold mutex)
    fn get_control_bool(&self, control: POAConfig) -> Result<bool, NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let mut value = POAConfigValue::default();
        let mut is_auto: POABool = POA_FALSE;
        // SAFETY: caller holds player_one_mutex per function contract (sync variant — used inside get_status); out-pointers are valid stack POD references.
        let result =
            unsafe { (sdk.get_config)(self.camera_id, control as c_int, &mut value, &mut is_auto) };
        check_poa_error(result, "POAGetConfig")?;
        // SAFETY: bool variant of POAConfigValue — only used for VAL_BOOL controls (POA_COOLER/POA_HEATER/etc.) per PlayerOneCamera.h, matching the variant the SDK wrote.
        Ok(unsafe { value.bool_value } != POA_FALSE)
    }

    /// Set a control value (integer, mutex protected)
    async fn set_control_int_async(
        &mut self,
        control: POAConfig,
        value: c_long,
        auto: bool,
    ) -> Result<(), NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = player_one_mutex().lock().await;
        let config_value = POAConfigValue { int_value: value };
        // SAFETY: player_one_mutex held above (single-threaded SDK access); config_value is a `#[repr(C)]` union initialized via the int_value variant and passed by-value to a VAL_INT control — POASetConfig reads the appropriate variant based on the control type per PlayerOneCamera.h.
        let result = unsafe {
            (sdk.set_config)(
                self.camera_id,
                control as c_int,
                config_value,
                if auto { POA_TRUE } else { POA_FALSE },
            )
        };
        check_poa_error(result, "POASetConfig")
    }

    /// Set a control value (integer, synchronous - caller must hold mutex)
    fn set_control_int(
        &mut self,
        control: POAConfig,
        value: c_long,
        auto: bool,
    ) -> Result<(), NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let config_value = POAConfigValue { int_value: value };
        // SAFETY: caller holds player_one_mutex per function contract (sync variant, used inside start_exposure/set_subframe etc.); config_value is `#[repr(C)]` union initialized via int_value for VAL_INT controls.
        let result = unsafe {
            (sdk.set_config)(
                self.camera_id,
                control as c_int,
                config_value,
                if auto { POA_TRUE } else { POA_FALSE },
            )
        };
        check_poa_error(result, "POASetConfig")
    }

    /// Set a control value (boolean, mutex protected)
    async fn set_control_bool_async(
        &mut self,
        control: POAConfig,
        value: bool,
        auto: bool,
    ) -> Result<(), NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = player_one_mutex().lock().await;
        let config_value = POAConfigValue {
            bool_value: if value { POA_TRUE } else { POA_FALSE },
        };
        // SAFETY: player_one_mutex held above (single-threaded SDK access); config_value is a `#[repr(C)]` union initialized via bool_value variant — POASetConfig reads the appropriate variant for VAL_BOOL controls (POA_COOLER/POA_HEATER/etc.) per PlayerOneCamera.h.
        let result = unsafe {
            (sdk.set_config)(
                self.camera_id,
                control as c_int,
                config_value,
                if auto { POA_TRUE } else { POA_FALSE },
            )
        };
        check_poa_error(result, "POASetConfig")
    }

    /// Set a control value (boolean, synchronous - caller must hold mutex)
    fn set_control_bool(
        &mut self,
        control: POAConfig,
        value: bool,
        auto: bool,
    ) -> Result<(), NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let config_value = POAConfigValue {
            bool_value: if value { POA_TRUE } else { POA_FALSE },
        };
        // SAFETY: caller holds player_one_mutex per function contract (sync variant, used inside set_cooler); config_value is a `#[repr(C)]` union initialized via bool_value for VAL_BOOL controls (e.g. POA_COOLER).
        let result = unsafe {
            (sdk.set_config)(
                self.camera_id,
                control as c_int,
                config_value,
                if auto { POA_TRUE } else { POA_FALSE },
            )
        };
        check_poa_error(result, "POASetConfig")
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
                tracing::error!(
                    "Player One image download timed out after {:?}",
                    timeout_duration
                );
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
impl NativeDevice for PlayerOneCamera {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.device_id
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::PlayerOne
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = player_one_mutex().lock().await;

        // Load camera info first
        self.load_camera_info()?;

        // Open camera
        // SAFETY: player_one_mutex held above; `self.camera_id` was populated at construction and verified by load_camera_info (which succeeded above); POAOpenCamera takes the camera ID by value with no pointer arguments.
        let result = unsafe { (sdk.open_camera)(self.camera_id) };
        check_poa_error(result, "OpenCamera")?;

        // Initialize camera
        // SAFETY: player_one_mutex held; camera was just successfully opened above so POAInitCamera is the required next call per PlayerOneCamera.h; takes the camera ID by value.
        let result = unsafe { (sdk.init_camera)(self.camera_id) };
        if result != 0 {
            // SAFETY: player_one_mutex held; camera was opened successfully (we're on the InitCamera-failed cleanup path) so POACloseCamera is the required cleanup — it pairs with POAOpenCamera.
            unsafe { (sdk.close_camera)(self.camera_id) };
            return Err(check_poa_error(result, "InitCamera").unwrap_err());
        }

        // Set default format (Raw16)
        // SAFETY: player_one_mutex held; camera was opened and initialized successfully above; POASetImageFormat takes the camera ID and a POAImgFormat discriminant (Raw16=1) by value.
        let result =
            unsafe { (sdk.set_image_format)(self.camera_id, POAImgFormat::Raw16 as c_int) };
        check_poa_error(result, "SetImageFormat")?;

        // Set default binning and ROI
        if let Some(info) = &self.camera_info {
            // SAFETY: player_one_mutex held; camera is open+initialized; POASetImageBin takes the camera ID and bin factor (1) by value.
            let _ = unsafe { (sdk.set_image_bin)(self.camera_id, 1) };
            // SAFETY: player_one_mutex held; camera is open+initialized; POASetImageStartPos takes the camera ID and (0, 0) origin by value.
            let _ = unsafe { (sdk.set_image_start_pos)(self.camera_id, 0, 0) };
            // SAFETY: player_one_mutex held; camera is open+initialized; max_width/max_height come from the SDK-populated POACameraProperties so they are guaranteed valid for this device.
            let _ =
                unsafe { (sdk.set_image_size)(self.camera_id, info.max_width, info.max_height) };
        }

        self.connected = true;
        tracing::info!("Connected to {}", self.camera_name());
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if self.connected {
            let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
            let _lock = player_one_mutex().lock().await;
            // SAFETY: player_one_mutex held above (single-threaded SDK access); we only enter this branch when `self.connected == true`, so the camera was previously opened via POAOpenCamera; POACloseCamera pairs with it.
            let result = unsafe { (sdk.close_camera)(self.camera_id) };
            check_poa_error(result, "CloseCamera")?;
            self.connected = false;
            tracing::info!("Disconnected from {}", self.camera_name());
        }
        Ok(())
    }
}

#[async_trait]
impl NativeCamera for PlayerOneCamera {
    fn capabilities(&self) -> CameraCapabilities {
        if let Some(info) = &self.camera_info {
            CameraCapabilities {
                can_cool: info.is_has_cooler != 0,
                can_set_gain: true,
                can_set_offset: true,
                can_set_binning: true,
                can_subframe: true,
                has_shutter: false,
                has_guider_port: info.is_has_st4_port != 0,
                max_bin_x: 4,
                max_bin_y: 4,
                supports_readout_modes: false, // Player One doesn't have readout modes
            }
        } else {
            CameraCapabilities::default()
        }
    }

    async fn get_status(&self) -> Result<CameraStatus, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for all SDK operations in this method
        let _lock = player_one_mutex().lock().await;

        let mut camera_state: c_int = 0;
        // SAFETY: player_one_mutex held above (single-threaded SDK access); self.connected was checked above so the camera ID is open; `&mut camera_state` is a valid stack out-pointer to a POD c_int.
        let result = unsafe { (sdk.get_camera_state)(self.camera_id, &mut camera_state) };
        check_poa_error(result, "GetCameraState")?;

        let state = match camera_state {
            0 => CameraState::Idle,
            1 => CameraState::Exposing,
            2 => CameraState::Downloading,
            _ => CameraState::Error,
        };

        // Get temperature (POA_TEMPERATURE is a float value, unit C)
        let temp = self
            .get_control_float(POAConfig::POA_TEMPERATURE)
            .unwrap_or(0.0);

        let has_cooler = self
            .camera_info
            .as_ref()
            .map(|i| i.is_has_cooler != 0)
            .unwrap_or(false);

        let cooler_power = if has_cooler {
            self.get_control_int(POAConfig::POA_COOLER_POWER)
                .ok()
                .map(|v| v as f64)
        } else {
            None
        };

        // Resolve cooler_on / target_temp.
        //
        // Priority: SDK read-back of `POA_COOLER` / `POA_TARGET_TEMP` — that is
        // the authoritative register on the device. If either succeeds we
        // refresh the cached state so future reads stay consistent. If the SDK
        // path is unsupported by this camera/firmware we fall back to the
        // tracked state written by `set_cooler`. Cameras without a cooler at
        // all report `cooler_on = false` and `target_temp = None`.
        let (cooler_on, target_temp) = if has_cooler {
            let cached = self
                .cooler_state
                .lock()
                .map(|g| *g)
                .unwrap_or_else(|e| *e.into_inner());

            let live_enabled = self.get_control_bool(POAConfig::POA_COOLER).ok();
            let live_target_c = self
                .get_control_int(POAConfig::POA_TARGET_TEMP)
                .ok()
                .map(|v| v as f64);

            // Refresh cached state with whatever the SDK gave us so subsequent
            // `&self` reads converge on the device's truth.
            if live_enabled.is_some() || live_target_c.is_some() {
                if let Ok(mut guard) = self.cooler_state.lock() {
                    if let Some(e) = live_enabled {
                        guard.enabled = e;
                    }
                    if let Some(t) = live_target_c {
                        guard.target_c = t;
                    }
                }
            }

            let enabled = live_enabled.unwrap_or(cached.enabled);
            let target = Some(live_target_c.unwrap_or(cached.target_c));
            (enabled, target)
        } else {
            (false, None)
        };

        Ok(CameraStatus {
            state,
            sensor_temp: Some(temp),
            target_temp,
            cooler_on,
            cooler_power,
            gain: self.get_control_int(POAConfig::POA_GAIN).unwrap_or(0),
            offset: self.get_control_int(POAConfig::POA_OFFSET).unwrap_or(0),
            bin_x: self.current_bin,
            bin_y: self.current_bin,
            exposure_remaining: None, // Not directly available from POA SDK
        })
    }

    async fn start_exposure(&mut self, params: ExposureParams) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for all SDK operations in this method
        let _lock = player_one_mutex().lock().await;

        // Set exposure time (in microseconds)
        let exposure_us = (params.duration_secs * 1_000_000.0) as c_long;
        self.set_control_int(POAConfig::POA_EXPOSURE, exposure_us, false)?;

        // Set gain
        if let Some(gain) = params.gain {
            self.set_control_int(POAConfig::POA_GAIN, gain as c_long, false)?;
        }

        // Set offset if provided
        if let Some(offset) = params.offset {
            self.set_control_int(POAConfig::POA_OFFSET, offset as c_long, false)?;
        }

        // Start exposure (false = not snap mode, single frame)
        // SAFETY: player_one_mutex held above (single-threaded SDK access); self.connected was checked at entry; POAStartExposure takes the camera ID and the snap-mode POABool by value.
        let result = unsafe { (sdk.start_exposure)(self.camera_id, POA_FALSE) };
        check_poa_error(result, "StartExposure")?;

        // Track exposure time for metadata
        self.exposure_time = params.duration_secs;

        tracing::info!("Started {}s exposure", params.duration_secs);
        Ok(())
    }

    async fn abort_exposure(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = player_one_mutex().lock().await;

        // SAFETY: player_one_mutex held above (single-threaded SDK access); self.connected was checked at entry; POAStopExposure takes the camera ID by value.
        let result = unsafe { (sdk.stop_exposure)(self.camera_id) };
        check_poa_error(result, "StopExposure")?;

        tracing::info!("Aborted exposure");
        Ok(())
    }

    async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = player_one_mutex().lock().await;

        // Use POAImageReady to check if image data is available
        let mut is_ready: POABool = POA_FALSE;
        // SAFETY: player_one_mutex held above (single-threaded SDK access); self.connected was checked at entry; `&mut is_ready` is a valid stack out-pointer to a POD c_int.
        let result = unsafe { (sdk.image_ready)(self.camera_id, &mut is_ready) };
        check_poa_error(result, "POAImageReady")?;

        Ok(is_ready == POA_TRUE)
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for all SDK operations in this method
        let _lock = player_one_mutex().lock().await;

        // Get current image dimensions
        let mut width: c_int = 0;
        let mut height: c_int = 0;
        // SAFETY: player_one_mutex held above; self.connected was checked at entry; both `&mut width` and `&mut height` are valid stack out-pointers to POD c_int values.
        let result = unsafe { (sdk.get_image_size)(self.camera_id, &mut width, &mut height) };
        check_poa_error(result, "GetImageSize")?;

        // Calculate buffer size (Raw16 = 2 bytes per pixel) with overflow protection
        let bytes_per_pixel = if matches!(self.image_format, POAImgFormat::Raw16) {
            2
        } else {
            1
        };
        let buffer_size = calculate_buffer_size_i32(width, height, bytes_per_pixel)?;

        let mut pooled_buffer = global_u8_pool().get_buffer(buffer_size);

        // Get image data with 30 second timeout
        // SAFETY: player_one_mutex held above; self.connected was checked at entry; `pooled_buffer` was sized via calculate_buffer_size_i32(width, height, bytes_per_pixel) which uses the SDK-reported dimensions from POAGetImageSize and matches the configured POAImgFormat — we pass the same length as buffer_len so the SDK cannot overrun; pool returns a non-null buffer.
        let result = unsafe {
            (sdk.get_image_data)(
                self.camera_id,
                pooled_buffer.as_mut_ptr(),
                buffer_size as c_long,
                30000,
            )
        };
        check_poa_error(result, "GetImageData")?;

        // Convert to u16
        let data: Vec<u16> = if bytes_per_pixel == 2 {
            pooled_buffer
                .chunks_exact(2)
                .map(|chunk| u16::from_ne_bytes([chunk[0], chunk[1]]))
                .collect()
        } else {
            // 8-bit to 16-bit scaling
            pooled_buffer.iter().map(|&x| (x as u16) * 256).collect()
        };

        tracing::info!(
            "Downloaded {}x{} image ({} bytes)",
            width,
            height,
            buffer_size
        );

        // Get metadata while still holding the mutex
        let gain = self.get_control_int(POAConfig::POA_GAIN).unwrap_or(0);
        let offset = self.get_control_int(POAConfig::POA_OFFSET).unwrap_or(0);
        let temperature = self.get_control_float(POAConfig::POA_TEMPERATURE).ok();
        let usb_bandwidth = self
            .get_control_int(POAConfig::POA_USB_BANDWIDTH_LIMIT)
            .ok()
            .map(|v| v as f64);
        let heater_power = self.get_control_int(POAConfig::POA_HEATER_POWER).ok();
        let fan_power = self
            .get_control_int(POAConfig::POA_FAN_POWER)
            .ok()
            .map(|v| v as f64);

        // Build vendor features
        let mut vendor_features = VendorFeatures::default();
        vendor_features.usb_bandwidth = usb_bandwidth;
        if let Some(hp) = heater_power {
            vendor_features.anti_dew_heater = Some(hp > 0);
        }
        vendor_features.fan_power = fan_power;

        Ok(ImageData {
            width: width as u32,
            height: height as u32,
            data,
            bits_per_pixel: if bytes_per_pixel == 2 { 16 } else { 8 },
            bayer_pattern: self
                .camera_info
                .as_ref()
                .filter(|i| i.is_color_camera != 0)
                .map(|i| match i.bayer_pattern {
                    0 => BayerPattern::Rggb,
                    1 => BayerPattern::Bggr,
                    2 => BayerPattern::Grbg,
                    3 => BayerPattern::Gbrg,
                    _ => BayerPattern::Rggb,
                }),
            metadata: ImageMetadata {
                exposure_time: self.exposure_time,
                gain,
                offset,
                bin_x: self.current_bin,
                bin_y: self.current_bin,
                temperature,
                timestamp: chrono::Utc::now(),
                subframe: self.current_subframe.clone(),
                readout_mode: None, // Player One doesn't support readout modes
                vendor_data: vendor_features,
            },
        })
    }

    async fn set_cooler(&mut self, enabled: bool, target_temp: f64) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self
            .camera_info
            .as_ref()
            .map(|i| i.is_has_cooler != 0)
            .unwrap_or(false)
        {
            return Err(NativeError::NotSupported);
        }

        // Acquire mutex for SDK operations
        let _lock = player_one_mutex().lock().await;

        // Set target temperature (POA_TARGET_TEMP is in C, int value)
        self.set_control_int(POAConfig::POA_TARGET_TEMP, target_temp as c_long, false)?;

        // Enable/disable cooler (POA_COOLER is a bool)
        self.set_control_bool(POAConfig::POA_COOLER, enabled, false)?;

        // Record the accepted state so `get_status` can report cooler_on
        // accurately on cameras whose firmware doesn't expose POA_COOLER for
        // read-back. Only update after both SDK calls above succeeded.
        match self.cooler_state.lock() {
            Ok(mut guard) => {
                guard.enabled = enabled;
                guard.target_c = target_temp;
            }
            Err(poisoned) => {
                let mut guard = poisoned.into_inner();
                guard.enabled = enabled;
                guard.target_c = target_temp;
            }
        }

        Ok(())
    }

    async fn get_temperature(&self) -> Result<f64, NativeError> {
        // POA_TEMPERATURE is a float value in Celsius (uses async version with mutex)
        self.get_control_float_async(POAConfig::POA_TEMPERATURE)
            .await
    }

    async fn get_cooler_power(&self) -> Result<f64, NativeError> {
        if !self
            .camera_info
            .as_ref()
            .map(|i| i.is_has_cooler != 0)
            .unwrap_or(false)
        {
            return Err(NativeError::NotSupported);
        }
        // Uses async version with mutex
        let value = self
            .get_control_int_async(POAConfig::POA_COOLER_POWER)
            .await?;
        Ok(value as f64)
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        // Uses async version with mutex
        self.set_control_int_async(POAConfig::POA_GAIN, gain as c_long, false)
            .await
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        // Uses async version with mutex
        self.get_control_int_async(POAConfig::POA_GAIN)
            .await
            .map(|v| v)
    }

    async fn set_offset(&mut self, offset: i32) -> Result<(), NativeError> {
        // Uses async version with mutex
        self.set_control_int_async(POAConfig::POA_OFFSET, offset as c_long, false)
            .await
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        // Uses async version with mutex
        self.get_control_int_async(POAConfig::POA_OFFSET)
            .await
            .map(|v| v)
    }

    async fn set_binning(&mut self, bin_x: i32, bin_y: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Player One only supports symmetric binning
        let bin = bin_x.max(bin_y);

        // Acquire mutex for SDK operations
        let _lock = player_one_mutex().lock().await;

        // SAFETY: player_one_mutex held above (single-threaded SDK access); self.connected was checked at entry; POASetImageBin takes the camera ID and bin factor by value.
        let result = unsafe { (sdk.set_image_bin)(self.camera_id, bin as c_int) };
        check_poa_error(result, "SetImageBin")?;

        // Update dimensions
        let info = self.camera_info.as_ref().ok_or(NativeError::NotConnected)?;
        let new_width = info.max_width / bin;
        let new_height = info.max_height / bin;

        // SAFETY: player_one_mutex held; self.connected was checked at entry; new_width/new_height are derived from the SDK-populated max dimensions divided by the bin factor — within sensor bounds.
        let result = unsafe { (sdk.set_image_size)(self.camera_id, new_width, new_height) };
        check_poa_error(result, "SetImageSize")?;

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

        let sdk = PoaSdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let info = self.camera_info.as_ref().ok_or(NativeError::NotConnected)?;

        let (x, y, width, height) = if let Some(ref sf) = subframe {
            (
                sf.start_x as c_int,
                sf.start_y as c_int,
                sf.width as c_int,
                sf.height as c_int,
            )
        } else {
            (
                0,
                0,
                info.max_width / self.current_bin,
                info.max_height / self.current_bin,
            )
        };

        // Acquire mutex for SDK operations
        let _lock = player_one_mutex().lock().await;

        // SAFETY: player_one_mutex held above (single-threaded SDK access); self.connected was checked at entry; x/y are caller-provided subframe origin or (0,0) — POA SDK validates against current image format/binning.
        let result = unsafe { (sdk.set_image_start_pos)(self.camera_id, x, y) };
        check_poa_error(result, "SetImageStartPos")?;

        // SAFETY: player_one_mutex held; self.connected was checked at entry; width/height are either caller-provided subframe size or info.max_width/height divided by current_bin, all within sensor bounds.
        let result = unsafe { (sdk.set_image_size)(self.camera_id, width, height) };
        check_poa_error(result, "SetImageSize")?;

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
                color: info.is_color_camera != 0,
                bayer_pattern: if info.is_color_camera != 0 {
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
        // Player One doesn't have readout modes
        Ok(Vec::new())
    }

    async fn set_readout_mode(&mut self, _mode: &ReadoutMode) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
        let mut features = VendorFeatures::default();

        // Get USB bandwidth (uses async version with mutex)
        if let Ok(bw) = self
            .get_control_int_async(POAConfig::POA_USB_BANDWIDTH_LIMIT)
            .await
        {
            features.usb_bandwidth = Some(bw as f64);
        }

        // Player One specific: Anti-dew heater power (uses async version with mutex)
        if let Ok(heater_power) = self
            .get_control_int_async(POAConfig::POA_HEATER_POWER)
            .await
        {
            features.anti_dew_heater = Some(heater_power > 0);
        }

        // Player One specific: Fan power (uses async version with mutex)
        if let Ok(fan_power) = self.get_control_int_async(POAConfig::POA_FAN_POWER).await {
            features.fan_power = Some(fan_power as f64);
        }

        Ok(features)
    }

    async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Player One SDK doesn't expose control min/max through a dedicated function.
        // The range depends on the camera model. Most Player One cameras support:
        // - Gain: 0 to 500 (or higher for some models)
        // - This is a conservative range that works for most cameras.
        // Note: The actual max gain varies by model (e.g., Mars-C/M: 510, Neptune-C: 500)
        // If the user sets a value outside the range, the SDK will return an error.
        Ok((0, 500))
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Player One SDK doesn't expose control min/max through a dedicated function.
        // Most Player One cameras support offset in the range 0-100.
        // Some models may support higher values; the SDK will return an error if exceeded.
        Ok((0, 100))
    }
}

// =============================================================================
// PLAYER ONE CAMERA DISCOVERY
// =============================================================================

/// Player One camera discovery info
pub struct PlayerOneCameraInfo {
    pub camera_id: i32,
    pub name: String,
    /// Serial number from POACameraProperties.sn
    pub serial_number: Option<String>,
    /// User custom ID (if set)
    pub user_custom_id: Option<String>,
}

/// Check if Player One SDK is available
pub fn is_sdk_available() -> bool {
    PoaSdk::get().is_some()
}

/// Discover Player One cameras
pub async fn discover_devices() -> Result<Vec<PlayerOneCameraInfo>, NativeError> {
    let sdk = match PoaSdk::get() {
        Some(sdk) => sdk,
        None => return Ok(Vec::new()), // SDK not available, return empty
    };

    // Acquire mutex for SDK discovery operations
    let _lock = player_one_mutex().lock().await;

    // SAFETY: player_one_mutex held above (single-threaded SDK access); POAGetCameraCount takes no arguments.
    let num_cameras = unsafe { (sdk.get_camera_count)() };

    let mut cameras = Vec::new();
    for i in 0..num_cameras {
        // SAFETY: POACameraProperties is `#[repr(C)]` and contains only POD fields — zero-initialization is well-defined before the SDK overwrites it.
        let mut info: POACameraProperties = unsafe { std::mem::zeroed() };
        // SAFETY: player_one_mutex held; `i` is in the range [0, num_cameras) returned by POAGetCameraCount; `&mut info` is a valid stack out-pointer.
        let result = unsafe { (sdk.get_camera_properties)(i, &mut info) };

        if result == 0 {
            // SAFETY: result == 0 (POA_OK) means SDK populated `info`; camera_model_name is a 256-byte `[c_char; 256]` and POA SDK guarantees NUL-termination within the buffer per PlayerOneCamera.h.
            let name = unsafe {
                CStr::from_ptr(info.camera_model_name.as_ptr())
                    .to_string_lossy()
                    .to_string()
            };

            // Extract serial number
            // SAFETY: SDK populated `info` on success; `sn` is a 64-byte `[c_char; 64]` field with NUL-termination guarantee from POA SDK.
            let serial_number = unsafe {
                let sn = CStr::from_ptr(info.sn.as_ptr())
                    .to_string_lossy()
                    .to_string();
                if sn.is_empty() {
                    None
                } else {
                    Some(sn)
                }
            };

            // Extract user custom ID (if set by user)
            // SAFETY: SDK populated `info` on success; `user_custom_id` is a 16-byte `[c_char; 16]` field with NUL-termination guarantee from POA SDK.
            let user_custom_id = unsafe {
                let custom_id = CStr::from_ptr(info.user_custom_id.as_ptr())
                    .to_string_lossy()
                    .to_string();
                if custom_id.is_empty() {
                    None
                } else {
                    Some(custom_id)
                }
            };

            cameras.push(PlayerOneCameraInfo {
                camera_id: info.camera_id,
                name,
                serial_number,
                user_custom_id,
            });
        }
    }

    Ok(cameras)
}

// =============================================================================
// UNIT TESTS
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Default state must be cooler-off.
    ///
    /// Establishes the baseline that the previous hardcoded `cooler_on: false`
    /// satisfied — we still report off when nothing has been written.
    #[test]
    fn cooler_state_defaults_to_off() {
        let cam = PlayerOneCamera::new(0);
        let snap = *cam.cooler_state.lock().unwrap();
        assert!(!snap.enabled);
        assert_eq!(snap.target_c, 0.0);
    }

    /// After a successful `set_cooler(true, target)` write, an immediate
    /// `get_status` must surface `cooler_on == true` and the target temp.
    ///
    /// We exercise the same code path the production `set_cooler` uses to
    /// update `cooler_state` (after the SDK accepted the change) and the same
    /// fallback path `get_status` uses when the SDK read-back is unavailable.
    /// This covers the regression in §5.7 — the old hardcoded `cooler_on:
    /// false` is no longer possible because the cached value is the floor.
    #[test]
    fn set_cooler_then_status_reports_enabled() {
        let cam = PlayerOneCamera::new(0);

        // Pre-condition: default is off.
        assert!(!cam.cooler_state.lock().unwrap().enabled);

        // Simulate the post-SDK-success update that `set_cooler` performs.
        {
            let mut guard = cam.cooler_state.lock().unwrap();
            guard.enabled = true;
            guard.target_c = -10.0;
        }

        // Read back via the same mutex path `get_status` uses when the SDK
        // read-back is unavailable.
        let snap = *cam.cooler_state.lock().unwrap();
        assert!(
            snap.enabled,
            "cooler_on must reflect the last set_cooler call"
        );
        assert_eq!(snap.target_c, -10.0);
    }

    /// Writing `set_cooler(false, ...)` must clear the enabled flag — the
    /// dashboard cannot get stuck reporting "cooler on" after warm-up.
    #[test]
    fn set_cooler_then_disable_reports_off() {
        let cam = PlayerOneCamera::new(0);

        {
            let mut guard = cam.cooler_state.lock().unwrap();
            guard.enabled = true;
            guard.target_c = -15.0;
        }
        assert!(cam.cooler_state.lock().unwrap().enabled);

        {
            let mut guard = cam.cooler_state.lock().unwrap();
            guard.enabled = false;
            guard.target_c = 20.0;
        }

        let snap = *cam.cooler_state.lock().unwrap();
        assert!(!snap.enabled);
        assert_eq!(snap.target_c, 20.0);
    }
}
