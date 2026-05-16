//! SVBony Camera SDK Bindings
//!
//! Native driver for SVBony cameras using their official SDK.
//!
//! ## Thread Safety
//!
//! The SVBony SDK is NOT thread-safe. All SDK operations are protected
//! by `svbony_mutex()` from `crate::sync` to prevent concurrent access.

use crate::camera::{
    BayerPattern, CameraCapabilities, CameraState, CameraStatus, ExposureParams, ImageData,
    ImageMetadata, ReadoutMode, SensorInfo, SubFrame, VendorFeatures,
};
use crate::sync::svbony_mutex;
use crate::traits::{NativeCamera, NativeDevice, NativeError};
use crate::utils::calculate_buffer_size_i32;
use crate::NativeVendor;
use async_trait::async_trait;
use std::ffi::{c_char, c_int, c_long, CStr};
use std::sync::OnceLock;

// =============================================================================
// SVBony SDK Types (from SVBCameraSDK.h)
// =============================================================================

/// SVBony error codes
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SvbError {
    Success = 0,
    InvalidIndex = 1,
    InvalidId = 2,
    InvalidControlType = 3,
    CameraClosed = 4,
    CameraRemoved = 5,
    InvalidPath = 6,
    InvalidFileFormat = 7,
    InvalidSize = 8,
    InvalidImgType = 9,
    OutOfBoundary = 10,
    Timeout = 11,
    InvalidSequence = 12,
    BufferTooSmall = 13,
    VideoModeActive = 14,
    ExposureInProgress = 15,
    GeneralError = 16,
    InvalidMode = 17,
    InvalidDirection = 18,
    UnknownSensorType = 19,
    End = 20,
}

impl SvbError {
    fn from_i32(code: i32) -> Self {
        match code {
            0 => SvbError::Success,
            1 => SvbError::InvalidIndex,
            2 => SvbError::InvalidId,
            3 => SvbError::InvalidControlType,
            4 => SvbError::CameraClosed,
            5 => SvbError::CameraRemoved,
            6 => SvbError::InvalidPath,
            7 => SvbError::InvalidFileFormat,
            8 => SvbError::InvalidSize,
            9 => SvbError::InvalidImgType,
            10 => SvbError::OutOfBoundary,
            11 => SvbError::Timeout,
            12 => SvbError::InvalidSequence,
            13 => SvbError::BufferTooSmall,
            14 => SvbError::VideoModeActive,
            15 => SvbError::ExposureInProgress,
            16 => SvbError::GeneralError,
            17 => SvbError::InvalidMode,
            18 => SvbError::InvalidDirection,
            19 => SvbError::UnknownSensorType,
            _ => SvbError::End,
        }
    }

    fn to_native_error(self, msg: &str) -> NativeError {
        match self {
            SvbError::Success => {
                NativeError::SdkError(format!("SVBony {} called to_native_error on Success", msg))
            }
            SvbError::InvalidIndex | SvbError::InvalidId => {
                NativeError::InvalidDevice(format!("SVBony {}: {:?}", msg, self))
            }
            SvbError::CameraClosed => NativeError::NotConnected,
            SvbError::CameraRemoved => NativeError::Disconnected,
            SvbError::Timeout => {
                NativeError::Timeout(format!("SVBony {}: operation timed out", msg))
            }
            SvbError::InvalidControlType
            | SvbError::InvalidSize
            | SvbError::InvalidImgType
            | SvbError::OutOfBoundary
            | SvbError::InvalidSequence
            | SvbError::InvalidMode
            | SvbError::InvalidDirection
            | SvbError::InvalidPath
            | SvbError::InvalidFileFormat => {
                NativeError::InvalidParameter(format!("SVBony {}: {:?}", msg, self))
            }
            SvbError::BufferTooSmall => {
                NativeError::InvalidParameter(format!("SVBony {}: buffer too small", msg))
            }
            SvbError::VideoModeActive | SvbError::ExposureInProgress => {
                NativeError::SdkError(format!("SVBony {}: camera busy ({:?})", msg, self))
            }
            SvbError::GeneralError => NativeError::SdkError(format!(
                "SVBony {}: general error - camera may be in use by another application",
                msg
            )),
            SvbError::UnknownSensorType | SvbError::End => {
                NativeError::SdkError(format!("SVBony {}: {:?}", msg, self))
            }
        }
    }
}

/// SVBony image types
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SvbImgType {
    Raw8 = 0,
    Raw16 = 4,
}

/// SVBony control types for camera settings
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SvbControlType {
    Gain = 0,
    Exposure = 1,
    BlackLevel = 13,
    CoolerEnable = 14,
    TargetTemperature = 15,
    CurrentTemperature = 16,
    CoolerPower = 17,
}

/// Camera info structure (SVB_CAMERA_INFO)
#[repr(C)]
#[derive(Debug)]
struct SvbCameraInfo {
    friendly_name: [c_char; 32],
    camera_sn: [c_char; 32],
    port_type: [c_char; 32],
    device_id: c_int,
    camera_id: c_int,
}

/// Camera property structure (SVB_CAMERA_PROPERTY)
#[repr(C)]
#[derive(Debug)]
struct SvbCameraProperty {
    max_height: c_long,
    max_width: c_long,
    is_color_cam: c_int,
    bayer_pattern: c_int,
    supported_bins: [c_int; 16],
    supported_video_format: [c_int; 8],
    pixel_size: f64,
    mechanical_shutter: c_int,
    st4_port: c_int,
    is_cooler_cam: c_int,
    is_usb3_host: c_int,
    is_usb3_camera: c_int,
    elec_per_adu: f32,
    bit_depth: c_int,
    is_trigger_cam: c_int,
}

/// Camera property extended structure (SVB_CAMERA_PROPERTY_EX)
#[repr(C)]
#[derive(Debug)]
struct SvbCameraPropertyEx {
    b_support_pulse_guide: c_int,
    b_support_control_temp: c_int,
    output_mode_support: [c_int; 8],
}

/// Control caps structure
#[repr(C)]
#[derive(Debug)]
struct SvbControlCaps {
    name: [c_char; 64],
    description: [c_char; 128],
    max_value: c_long,
    min_value: c_long,
    default_value: c_long,
    is_auto_supported: c_int,
    is_writable: c_int,
    control_type: c_int,
}

// =============================================================================
// SDK Function Pointers
// =============================================================================

type SvbGetNumOfConnectedCameras = unsafe extern "C" fn() -> c_int;
type SvbGetCameraInfo = unsafe extern "C" fn(info: *mut SvbCameraInfo, index: c_int) -> c_int;
type SvbGetCameraProperty =
    unsafe extern "C" fn(camera_id: c_int, prop: *mut SvbCameraProperty) -> c_int;
type SvbGetCameraPropertyEx =
    unsafe extern "C" fn(camera_id: c_int, prop: *mut SvbCameraPropertyEx) -> c_int;
type SvbOpenCamera = unsafe extern "C" fn(camera_id: c_int) -> c_int;
type SvbCloseCamera = unsafe extern "C" fn(camera_id: c_int) -> c_int;
type SvbGetNumOfControls = unsafe extern "C" fn(camera_id: c_int, num: *mut c_int) -> c_int;
type SvbGetControlCaps =
    unsafe extern "C" fn(camera_id: c_int, index: c_int, caps: *mut SvbControlCaps) -> c_int;
type SvbGetControlValue = unsafe extern "C" fn(
    camera_id: c_int,
    ctrl_type: c_int,
    value: *mut c_long,
    is_auto: *mut c_int,
) -> c_int;
type SvbSetControlValue = unsafe extern "C" fn(
    camera_id: c_int,
    ctrl_type: c_int,
    value: c_long,
    is_auto: c_int,
) -> c_int;
type SvbSetROIFormat = unsafe extern "C" fn(
    camera_id: c_int,
    start_x: c_int,
    start_y: c_int,
    width: c_int,
    height: c_int,
    bin: c_int,
) -> c_int;
type SvbGetROIFormat = unsafe extern "C" fn(
    camera_id: c_int,
    start_x: *mut c_int,
    start_y: *mut c_int,
    width: *mut c_int,
    height: *mut c_int,
    bin: *mut c_int,
) -> c_int;
type SvbSetOutputImageType = unsafe extern "C" fn(camera_id: c_int, img_type: c_int) -> c_int;
type SvbGetOutputImageType = unsafe extern "C" fn(camera_id: c_int, img_type: *mut c_int) -> c_int;
type SvbStartVideoCapture = unsafe extern "C" fn(camera_id: c_int) -> c_int;
type SvbStopVideoCapture = unsafe extern "C" fn(camera_id: c_int) -> c_int;
type SvbGetVideoData =
    unsafe extern "C" fn(camera_id: c_int, buf: *mut u8, buf_size: c_long, wait_ms: c_int) -> c_int;
type SvbGetSdkVersion = unsafe extern "C" fn() -> *const c_char;

/// SVBony SDK wrapper with dynamically loaded functions
struct SvbonySdk {
    _library: libloading::Library,
    get_num_of_connected_cameras: SvbGetNumOfConnectedCameras,
    get_camera_info: SvbGetCameraInfo,
    get_camera_property: SvbGetCameraProperty,
    get_camera_property_ex: SvbGetCameraPropertyEx,
    open_camera: SvbOpenCamera,
    close_camera: SvbCloseCamera,
    get_num_of_controls: SvbGetNumOfControls,
    get_control_caps: SvbGetControlCaps,
    get_control_value: SvbGetControlValue,
    set_control_value: SvbSetControlValue,
    set_roi_format: SvbSetROIFormat,
    get_roi_format: SvbGetROIFormat,
    set_output_image_type: SvbSetOutputImageType,
    get_output_image_type: SvbGetOutputImageType,
    start_video_capture: SvbStartVideoCapture,
    stop_video_capture: SvbStopVideoCapture,
    get_video_data: SvbGetVideoData,
    get_sdk_version: SvbGetSdkVersion,
}

impl SvbonySdk {
    /// Load the SDK from the default paths
    fn load() -> Result<Self, NativeError> {
        let lib_name = if cfg!(target_os = "windows") {
            "SVBCameraSDK.dll"
        } else if cfg!(target_os = "macos") {
            "libSVBCameraSDK.dylib"
        } else {
            "libSVBCameraSDK.so"
        };

        // SAFETY: libloading::Library::new performs platform dynamic loading; `lib_name` is a compile-time string constant naming the vendor SDK shared library (SVBCameraSDK.dll/dylib/so). Errors (missing file, invalid format) are propagated via the map_err arm rather than UB.
        let library = unsafe { libloading::Library::new(lib_name) }
            .map_err(|e| NativeError::SdkError(format!("Failed to load SVBony SDK: {}", e)))?;

        // SAFETY: each `library.get::<FnType>(b"symbol\0")` returns a `Symbol` that we immediately deref with `*` to copy out a function pointer; the C ABI signatures declared above (SvbGetNumOfConnectedCameras, SvbGetCameraInfo, ...) are from the vendor's SVBCameraSDK.h header so the function-pointer ABI matches. The loaded `library` is moved into the returned SvbonySdk so the function pointers remain valid for the program's lifetime (SDK is stored in a `static OnceLock`).
        unsafe {
            Ok(Self {
                get_num_of_connected_cameras: *library
                    .get::<SvbGetNumOfConnectedCameras>(b"SVBGetNumOfConnectedCameras\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!(
                            "Failed to load SVBGetNumOfConnectedCameras: {}",
                            e
                        ))
                    })?,
                get_camera_info: *library
                    .get::<SvbGetCameraInfo>(b"SVBGetCameraInfo\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBGetCameraInfo: {}", e))
                    })?,
                get_camera_property: *library
                    .get::<SvbGetCameraProperty>(b"SVBGetCameraProperty\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBGetCameraProperty: {}", e))
                    })?,
                get_camera_property_ex: *library
                    .get::<SvbGetCameraPropertyEx>(b"SVBGetCameraPropertyEx\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!(
                            "Failed to load SVBGetCameraPropertyEx: {}",
                            e
                        ))
                    })?,
                open_camera: *library
                    .get::<SvbOpenCamera>(b"SVBOpenCamera\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBOpenCamera: {}", e))
                    })?,
                close_camera: *library
                    .get::<SvbCloseCamera>(b"SVBCloseCamera\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBCloseCamera: {}", e))
                    })?,
                get_num_of_controls: *library
                    .get::<SvbGetNumOfControls>(b"SVBGetNumOfControls\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBGetNumOfControls: {}", e))
                    })?,
                get_control_caps: *library
                    .get::<SvbGetControlCaps>(b"SVBGetControlCaps\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBGetControlCaps: {}", e))
                    })?,
                get_control_value: *library
                    .get::<SvbGetControlValue>(b"SVBGetControlValue\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBGetControlValue: {}", e))
                    })?,
                set_control_value: *library
                    .get::<SvbSetControlValue>(b"SVBSetControlValue\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBSetControlValue: {}", e))
                    })?,
                set_roi_format: *library
                    .get::<SvbSetROIFormat>(b"SVBSetROIFormat\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBSetROIFormat: {}", e))
                    })?,
                get_roi_format: *library
                    .get::<SvbGetROIFormat>(b"SVBGetROIFormat\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBGetROIFormat: {}", e))
                    })?,
                set_output_image_type: *library
                    .get::<SvbSetOutputImageType>(b"SVBSetOutputImageType\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!(
                            "Failed to load SVBSetOutputImageType: {}",
                            e
                        ))
                    })?,
                get_output_image_type: *library
                    .get::<SvbGetOutputImageType>(b"SVBGetOutputImageType\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!(
                            "Failed to load SVBGetOutputImageType: {}",
                            e
                        ))
                    })?,
                start_video_capture: *library
                    .get::<SvbStartVideoCapture>(b"SVBStartVideoCapture\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBStartVideoCapture: {}", e))
                    })?,
                stop_video_capture: *library
                    .get::<SvbStopVideoCapture>(b"SVBStopVideoCapture\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBStopVideoCapture: {}", e))
                    })?,
                get_video_data: *library
                    .get::<SvbGetVideoData>(b"SVBGetVideoData\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBGetVideoData: {}", e))
                    })?,
                get_sdk_version: *library
                    .get::<SvbGetSdkVersion>(b"SVBGetSDKVersion\0")
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to load SVBGetSDKVersion: {}", e))
                    })?,
                _library: library,
            })
        }
    }
}

/// Global SDK instance
static SDK: OnceLock<Result<SvbonySdk, String>> = OnceLock::new();

fn get_sdk() -> Result<&'static SvbonySdk, NativeError> {
    SDK.get_or_init(|| SvbonySdk::load().map_err(|e| e.to_string()))
        .as_ref()
        .map_err(|e| NativeError::SdkError(e.clone()))
}

// =============================================================================
// Discovery
// =============================================================================

/// Discovered SVBony camera info
#[derive(Debug, Clone)]
pub struct SvbonyDiscoveryInfo {
    pub camera_id: i32,
    pub name: String,
    pub serial_number: Option<String>,
    pub discovery_index: usize,
}

/// Discover connected SVBony cameras
pub async fn discover_devices() -> Result<Vec<SvbonyDiscoveryInfo>, NativeError> {
    // If SDK is not available, return empty list (not error)
    let sdk = match get_sdk() {
        Ok(sdk) => sdk,
        Err(_) => return Ok(Vec::new()),
    };

    // Acquire mutex for SDK discovery operations
    let _lock = svbony_mutex().lock().await;

    // SAFETY: svbony_mutex held above (SVBony SDK is not thread-safe per module header); SVBGetNumOfConnectedCameras takes no arguments and returns a plain c_int count.
    let count = unsafe { (sdk.get_num_of_connected_cameras)() };

    let mut devices = Vec::new();
    for i in 0..count {
        // SAFETY: SvbCameraInfo is `#[repr(C)]` and contains only POD fields (c_char arrays, c_int) — all valid bit-patterns. Zero-initialization is the well-defined empty state before the SDK overwrites it.
        let mut info: SvbCameraInfo = unsafe { std::mem::zeroed() };
        // SAFETY: svbony_mutex held; `&mut info` is a valid stack out-pointer to a `#[repr(C)]` SvbCameraInfo; `i` is in [0, count) per the loop bound, which is the contract for SVBGetCameraInfo's index parameter.
        let result = unsafe { (sdk.get_camera_info)(&mut info, i) };
        if SvbError::from_i32(result) == SvbError::Success {
            // SAFETY: SVBGetCameraInfo populated `info.friendly_name` as a NUL-terminated C string inside a [c_char; 32] buffer per SVBCameraSDK.h; the pointer is valid for the duration of this `info` stack value and CStr::from_ptr reads up to the NUL.
            let name = unsafe { CStr::from_ptr(info.friendly_name.as_ptr()) }
                .to_string_lossy()
                .to_string();
            // SAFETY: SVBGetCameraInfo populated `info.camera_sn` as a NUL-terminated C string inside a [c_char; 32] buffer per SVBCameraSDK.h; the pointer is valid for the duration of this `info` stack value and CStr::from_ptr reads up to the NUL.
            let serial = unsafe { CStr::from_ptr(info.camera_sn.as_ptr()) }
                .to_string_lossy()
                .to_string();

            devices.push(SvbonyDiscoveryInfo {
                camera_id: info.camera_id,
                name,
                serial_number: if serial.is_empty() {
                    None
                } else {
                    Some(serial)
                },
                discovery_index: i as usize,
            });
        }
    }
    Ok(devices)
}

/// Check if SDK is available
pub fn is_sdk_available() -> bool {
    get_sdk().is_ok()
}

/// Get SDK status for diagnostics
pub fn get_sdk_status() -> (bool, String) {
    match get_sdk() {
        Ok(sdk) => {
            // SAFETY: SVBGetSDKVersion returns a pointer to a static, NUL-terminated C string baked into the SDK shared library (per SVBCameraSDK.h); the SDK library is owned by SDK::OnceLock so the pointer is valid for the program's lifetime. We explicitly null-check before reading.
            let version = unsafe {
                let ptr = (sdk.get_sdk_version)();
                if ptr.is_null() {
                    "unknown".to_string()
                } else {
                    CStr::from_ptr(ptr).to_string_lossy().to_string()
                }
            };
            (true, format!("SVBony SDK v{}", version))
        }
        Err(e) => (false, format!("SDK not available: {}", e)),
    }
}

// =============================================================================
// SVBony Camera Implementation
// =============================================================================

/// SVBony camera native driver
#[derive(Debug)]
pub struct SvbonyCamera {
    camera_id: i32,
    device_id: String,
    name: String,
    connected: bool,
    capabilities: CameraCapabilities,
    sensor_info: SensorInfo,
    state: CameraState,
    // Current settings
    current_gain: i32,
    current_offset: i32,
    current_bin_x: i32,
    current_bin_y: i32,
    subframe: Option<SubFrame>,
    cooler_on: bool,
    target_temp: f64,
    // Exposure tracking
    exposure_start: Option<std::time::Instant>,
    exposure_duration: f64,
    image_buffer: Vec<u8>,
}

impl SvbonyCamera {
    /// Create a new SVBony camera instance
    pub fn new(camera_id: i32) -> Self {
        Self {
            camera_id,
            device_id: format!("svbony_{}", camera_id),
            name: format!("SVBony Camera {}", camera_id),
            connected: false,
            capabilities: CameraCapabilities::default(),
            sensor_info: SensorInfo::default(),
            state: CameraState::Idle,
            current_gain: 0,
            current_offset: 0,
            current_bin_x: 1,
            current_bin_y: 1,
            subframe: None,
            cooler_on: false,
            target_temp: -10.0,
            exposure_start: None,
            exposure_duration: 0.0,
            image_buffer: Vec::new(),
        }
    }

    /// Get control value (synchronous - caller must hold mutex)
    fn get_control_value(&self, control_type: SvbControlType) -> Result<i64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        let sdk = get_sdk()?;
        let mut value: c_long = 0;
        let mut is_auto: c_int = 0;
        // SAFETY: per function contract (sync variant) the caller holds svbony_mutex; `self.camera_id` was validated by SVBOpenCamera in `connect`; `&mut value` and `&mut is_auto` are valid stack out-pointers to POD types; `control_type as c_int` enumerates a SvbControlType discriminant per SVBCameraSDK.h.
        let result = unsafe {
            (sdk.get_control_value)(
                self.camera_id,
                control_type as c_int,
                &mut value,
                &mut is_auto,
            )
        };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("get control value"));
        }
        Ok(value as i64)
    }

    /// Get control value (async - acquires mutex)
    async fn get_control_value_async(
        &self,
        control_type: SvbControlType,
    ) -> Result<i64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        let sdk = get_sdk()?;
        let _lock = svbony_mutex().lock().await;
        let mut value: c_long = 0;
        let mut is_auto: c_int = 0;
        // SAFETY: svbony_mutex held above (single-threaded SDK access); `self.camera_id` was validated by SVBOpenCamera in `connect`; `&mut value` and `&mut is_auto` are valid stack out-pointers to POD types; `control_type as c_int` enumerates a SvbControlType discriminant per SVBCameraSDK.h.
        let result = unsafe {
            (sdk.get_control_value)(
                self.camera_id,
                control_type as c_int,
                &mut value,
                &mut is_auto,
            )
        };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("get control value"));
        }
        Ok(value as i64)
    }

    /// Set control value (synchronous - caller must hold mutex)
    fn set_control_value(
        &self,
        control_type: SvbControlType,
        value: i64,
    ) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        let sdk = get_sdk()?;
        // SAFETY: per function contract (sync variant) the caller holds svbony_mutex; `self.camera_id` is the camera ID validated by SVBOpenCamera in `connect`; SVBSetControlValue takes all-POD arguments (c_int/c_long/c_int) with no out-pointers.
        let result = unsafe {
            (sdk.set_control_value)(self.camera_id, control_type as c_int, value as c_long, 0)
        };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("set control value"));
        }
        Ok(())
    }

    /// Set control value (async - acquires mutex)
    async fn set_control_value_async(
        &self,
        control_type: SvbControlType,
        value: i64,
    ) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        let sdk = get_sdk()?;
        let _lock = svbony_mutex().lock().await;
        // SAFETY: svbony_mutex held above (single-threaded SDK access); `self.camera_id` is the camera ID validated by SVBOpenCamera in `connect`; SVBSetControlValue takes all-POD arguments (c_int/c_long/c_int) with no out-pointers.
        let result = unsafe {
            (sdk.set_control_value)(self.camera_id, control_type as c_int, value as c_long, 0)
        };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("set control value"));
        }
        Ok(())
    }

    /// Get the min/max range for a control type (async - acquires mutex)
    async fn get_control_range_async(
        &self,
        target_type: SvbControlType,
    ) -> Result<(i64, i64), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        let sdk = get_sdk()?;
        let _lock = svbony_mutex().lock().await;

        // Get number of controls
        let mut num_controls: c_int = 0;
        // SAFETY: svbony_mutex held above; `self.camera_id` validated by SVBOpenCamera; `&mut num_controls` is a valid stack out-pointer to a c_int.
        let result = unsafe { (sdk.get_num_of_controls)(self.camera_id, &mut num_controls) };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("get num of controls"));
        }

        // Search for the specific control
        for i in 0..num_controls {
            // SAFETY: SvbControlCaps is `#[repr(C)]` POD (c_char arrays, c_int, c_long) — all valid bit-patterns. Zero-init is the well-defined empty state before SVBGetControlCaps overwrites it.
            let mut caps: SvbControlCaps = unsafe { std::mem::zeroed() };
            // SAFETY: svbony_mutex held above; `self.camera_id` validated; `i` is in [0, num_controls) per the loop bound (which is the contract for SVBGetControlCaps's index parameter); `&mut caps` is a valid stack out-pointer to a `#[repr(C)]` SvbControlCaps.
            let result = unsafe { (sdk.get_control_caps)(self.camera_id, i, &mut caps) };
            if SvbError::from_i32(result) == SvbError::Success
                && caps.control_type == target_type as c_int
            {
                return Ok((caps.min_value as i64, caps.max_value as i64));
            }
        }

        Err(NativeError::NotSupported)
    }
}

#[async_trait]
impl NativeDevice for SvbonyCamera {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Svbony
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        if self.connected {
            return Ok(());
        }

        let sdk = get_sdk()?;

        // Acquire mutex for all SDK operations in connect
        let _lock = svbony_mutex().lock().await;

        // Open camera
        // SAFETY: svbony_mutex held above; `self.camera_id` was supplied by SvbonyCamera::new (originating from SvbCameraInfo populated by SVBGetCameraInfo during discover_devices); SVBOpenCamera is the contractual handle-acquisition entry point.
        let result = unsafe { (sdk.open_camera)(self.camera_id) };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("open camera"));
        }

        // Get camera properties
        // SAFETY: SvbCameraProperty is `#[repr(C)]` POD (c_long/c_int arrays, f64, f32) — all valid bit-patterns. Zero-init is the well-defined empty state before the SDK overwrites it.
        let mut prop: SvbCameraProperty = unsafe { std::mem::zeroed() };
        // SAFETY: svbony_mutex held; `self.camera_id` valid (just opened above); `&mut prop` is a valid stack out-pointer to a `#[repr(C)]` SvbCameraProperty.
        let result = unsafe { (sdk.get_camera_property)(self.camera_id, &mut prop) };
        if SvbError::from_i32(result) != SvbError::Success {
            // SAFETY: svbony_mutex held; `self.camera_id` is the just-opened camera being torn down on error path. SVBCloseCamera is the contractual release entry point.
            unsafe { (sdk.close_camera)(self.camera_id) };
            return Err(SvbError::from_i32(result).to_native_error("get camera property"));
        }

        // Get extended properties
        // SAFETY: SvbCameraPropertyEx is `#[repr(C)]` POD (c_int and c_int arrays) — all valid bit-patterns. Zero-init is the well-defined empty state.
        let mut prop_ex: SvbCameraPropertyEx = unsafe { std::mem::zeroed() };
        // SAFETY: svbony_mutex held; `self.camera_id` valid; `&mut prop_ex` is a valid stack out-pointer to a `#[repr(C)]` SvbCameraPropertyEx. Failure is tolerated (older firmware may not support EX) — caller logs nothing and falls through with zeroed defaults.
        let _ = unsafe { (sdk.get_camera_property_ex)(self.camera_id, &mut prop_ex) };

        // Determine max binning
        let mut max_bin = 1;
        for bin in prop.supported_bins.iter() {
            if *bin > 0 {
                max_bin = (*bin).max(max_bin);
            }
        }

        // Set capabilities
        self.capabilities = CameraCapabilities {
            can_cool: prop.is_cooler_cam != 0,
            can_set_gain: true,
            can_set_offset: true,
            can_set_binning: max_bin > 1,
            can_subframe: true,
            has_shutter: prop.mechanical_shutter != 0,
            has_guider_port: prop.st4_port != 0 || prop_ex.b_support_pulse_guide != 0,
            max_bin_x: max_bin,
            max_bin_y: max_bin,
            supports_readout_modes: false,
        };

        // Determine bayer pattern
        let is_color = prop.is_color_cam != 0;
        let bayer_pattern = if is_color {
            Some(match prop.bayer_pattern {
                0 => BayerPattern::Rggb,
                1 => BayerPattern::Bggr,
                2 => BayerPattern::Grbg,
                3 => BayerPattern::Gbrg,
                _ => BayerPattern::Rggb,
            })
        } else {
            None
        };

        // Set sensor info
        self.sensor_info = SensorInfo {
            width: prop.max_width as u32,
            height: prop.max_height as u32,
            pixel_size_x: prop.pixel_size,
            pixel_size_y: prop.pixel_size,
            max_adu: (1 << prop.bit_depth) - 1,
            bit_depth: prop.bit_depth as u32,
            color: is_color,
            bayer_pattern,
        };

        // Get camera name from info
        // SAFETY: SvbCameraInfo is `#[repr(C)]` POD; zero-init is the well-defined empty state.
        let mut info: SvbCameraInfo = unsafe { std::mem::zeroed() };
        // SAFETY: svbony_mutex held; `&mut info` is a valid stack out-pointer; index 0 is a probe to verify the SDK is responsive before iterating.
        if unsafe { (sdk.get_camera_info)(&mut info, 0) } == 0 {
            // Find our camera by ID
            // SAFETY: svbony_mutex held; SVBGetNumOfConnectedCameras takes no arguments and returns a plain c_int count.
            let count = unsafe { (sdk.get_num_of_connected_cameras)() };
            for i in 0..count {
                // SAFETY: SvbCameraInfo is `#[repr(C)]` POD; zero-init is the well-defined empty state.
                let mut check_info: SvbCameraInfo = unsafe { std::mem::zeroed() };
                // SAFETY: svbony_mutex held; `i` is in [0, count) per the loop bound (which is the contract for SVBGetCameraInfo's index parameter); `&mut check_info` is a valid stack out-pointer to a `#[repr(C)]` SvbCameraInfo.
                if unsafe { (sdk.get_camera_info)(&mut check_info, i) } == 0
                    && check_info.camera_id == self.camera_id
                {
                    // SAFETY: SVBGetCameraInfo populated `check_info.friendly_name` as a NUL-terminated C string inside a [c_char; 32] buffer per SVBCameraSDK.h; the pointer is valid for the duration of this stack `check_info` value.
                    self.name = unsafe { CStr::from_ptr(check_info.friendly_name.as_ptr()) }
                        .to_string_lossy()
                        .to_string();
                    break;
                }
            }
        }

        // Set default image type (16-bit RAW)
        // SAFETY: svbony_mutex held; `self.camera_id` valid (just opened above); `SvbImgType::Raw16 as c_int` is a stable discriminant from SVBCameraSDK.h enum SVB_IMG_TYPE.
        let result =
            unsafe { (sdk.set_output_image_type)(self.camera_id, SvbImgType::Raw16 as c_int) };
        if SvbError::from_i32(result) != SvbError::Success {
            tracing::warn!("Could not set 16-bit output, trying 8-bit");
            // SAFETY: svbony_mutex held; `self.camera_id` valid; `SvbImgType::Raw8 as c_int` is a stable discriminant from SVBCameraSDK.h. Fallback path when Raw16 is unsupported by this model.
            let _ =
                unsafe { (sdk.set_output_image_type)(self.camera_id, SvbImgType::Raw8 as c_int) };
        }

        // Read initial gain/offset (while we hold the mutex)
        if let Ok(gain) = self.get_control_value(SvbControlType::Gain) {
            self.current_gain = gain as i32;
        }
        if let Ok(offset) = self.get_control_value(SvbControlType::BlackLevel) {
            self.current_offset = offset as i32;
        }

        self.connected = true;
        self.state = CameraState::Idle;

        tracing::info!(
            "Connected to SVBony camera: {} ({}x{})",
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

        let sdk = get_sdk()?;

        // Acquire mutex for SDK operations
        let _lock = svbony_mutex().lock().await;

        // Stop any ongoing capture
        // SAFETY: svbony_mutex held above (in disconnect()); `self.camera_id` valid until we close below; SVBStopVideoCapture takes a single c_int and is idempotent per SDK docs.
        let _ = unsafe { (sdk.stop_video_capture)(self.camera_id) };

        // Close camera
        // SAFETY: svbony_mutex held above; `self.camera_id` valid (handle was opened in connect()). SVBCloseCamera is the contractual release for SVBOpenCamera.
        let result = unsafe { (sdk.close_camera)(self.camera_id) };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("close camera"));
        }

        self.connected = false;
        self.state = CameraState::Idle;
        tracing::info!("Disconnected from SVBony camera: {}", self.name);
        Ok(())
    }
}

#[async_trait]
impl NativeCamera for SvbonyCamera {
    fn capabilities(&self) -> CameraCapabilities {
        self.capabilities.clone()
    }

    async fn get_status(&self) -> Result<CameraStatus, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Get sensor temperature and cooler power using async mutex-protected methods
        let sensor_temp = if self.capabilities.can_cool {
            self.get_control_value_async(SvbControlType::CurrentTemperature)
                .await
                .map(|v| v as f64 / 10.0)
                .ok()
        } else {
            None
        };

        let cooler_power = if self.capabilities.can_cool && self.cooler_on {
            self.get_control_value_async(SvbControlType::CoolerPower)
                .await
                .map(|v| v as f64)
                .ok()
        } else {
            None
        };

        let exposure_remaining = if self.state == CameraState::Exposing {
            self.exposure_start.map(|start| {
                let elapsed = start.elapsed().as_secs_f64();
                (self.exposure_duration - elapsed).max(0.0)
            })
        } else {
            None
        };

        Ok(CameraStatus {
            state: self.state,
            sensor_temp,
            cooler_power,
            target_temp: if self.capabilities.can_cool {
                Some(self.target_temp)
            } else {
                None
            },
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

        let sdk = get_sdk()?;

        // Set gain if provided (these methods acquire mutex internally)
        if let Some(gain) = params.gain {
            self.set_gain(gain).await?;
        }

        // Set offset if provided
        if let Some(offset) = params.offset {
            self.set_offset(offset).await?;
        }

        // Set binning
        self.set_binning(params.bin_x, params.bin_y).await?;

        // Set subframe/ROI
        self.set_subframe(params.subframe.clone()).await?;

        // Acquire mutex for exposure start operations
        let _lock = svbony_mutex().lock().await;

        // Set exposure time (in microseconds)
        let exposure_us = (params.duration_secs * 1_000_000.0) as i64;
        self.set_control_value(SvbControlType::Exposure, exposure_us)?;

        // Start video capture mode (SVBony uses video mode for exposures)
        // SAFETY: svbony_mutex held above (in start_exposure()); `self.camera_id` validated by SVBOpenCamera in connect(); SVBStartVideoCapture takes a single c_int and is the contractual entry point to begin capture per SVBCameraSDK.h.
        let result = unsafe { (sdk.start_video_capture)(self.camera_id) };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("start exposure"));
        }

        self.exposure_start = Some(std::time::Instant::now());
        self.exposure_duration = params.duration_secs;
        self.state = CameraState::Exposing;

        Ok(())
    }

    async fn abort_exposure(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Acquire mutex for SDK operations
        let _lock = svbony_mutex().lock().await;

        // SAFETY: svbony_mutex held above (in abort_exposure()); `self.camera_id` validated by SVBOpenCamera in connect(); SVBStopVideoCapture takes a single c_int and is idempotent.
        let result = unsafe { (sdk.stop_video_capture)(self.camera_id) };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("abort exposure"));
        }

        self.state = CameraState::Idle;
        self.exposure_start = None;
        Ok(())
    }

    async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        match self.state {
            CameraState::Idle => Ok(true),
            CameraState::Exposing => {
                if let Some(start) = self.exposure_start {
                    let elapsed = start.elapsed().as_secs_f64();
                    Ok(elapsed >= self.exposure_duration)
                } else {
                    Ok(false)
                }
            }
            _ => Ok(false),
        }
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Acquire mutex for all SDK operations in this method
        let _lock = svbony_mutex().lock().await;

        // Get current ROI
        let mut start_x: c_int = 0;
        let mut start_y: c_int = 0;
        let mut width: c_int = 0;
        let mut height: c_int = 0;
        let mut bin: c_int = 0;
        // SAFETY: svbony_mutex held above (in download_image()); `self.camera_id` validated; all five `&mut` out-pointers reference distinct c_int stack locals, matching SVBGetROIFormat's signature.
        let result = unsafe {
            (sdk.get_roi_format)(
                self.camera_id,
                &mut start_x,
                &mut start_y,
                &mut width,
                &mut height,
                &mut bin,
            )
        };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("get ROI format"));
        }

        // Get current image type
        let mut img_type: c_int = 0;
        // SAFETY: svbony_mutex held; `self.camera_id` validated; `&mut img_type` is a valid stack out-pointer to a c_int.
        let _ = unsafe { (sdk.get_output_image_type)(self.camera_id, &mut img_type) };

        // Calculate buffer size (assume 16-bit for safety) with overflow protection
        let bytes_per_pixel = 2;
        let buffer_size = calculate_buffer_size_i32(width, height, bytes_per_pixel)?;

        // Resize buffer if needed
        if self.image_buffer.len() < buffer_size {
            self.image_buffer.resize(buffer_size, 0);
        }

        // Get image data with timeout
        self.state = CameraState::Downloading;
        // SAFETY: svbony_mutex held above; `self.camera_id` validated; `self.image_buffer.as_mut_ptr()` points to at least `buffer_size` bytes (resized above via `image_buffer.resize(buffer_size, 0)`), which is what we pass as the third argument so SVBGetVideoData will not write past the allocation. The 5000 ms timeout is documented as block-with-deadline behavior in SVBCameraSDK.h.
        let result = unsafe {
            (sdk.get_video_data)(
                self.camera_id,
                self.image_buffer.as_mut_ptr(),
                buffer_size as c_long,
                5000, // 5 second timeout
            )
        };

        if SvbError::from_i32(result) != SvbError::Success {
            self.state = CameraState::Error;
            return Err(SvbError::from_i32(result).to_native_error("download image"));
        }

        // Stop video capture
        // SAFETY: svbony_mutex held; `self.camera_id` valid; SVBStopVideoCapture is idempotent and takes a single c_int.
        let _ = unsafe { (sdk.stop_video_capture)(self.camera_id) };

        // Convert to u16 data
        let data: Vec<u16> = self.image_buffer[..buffer_size]
            .chunks(2)
            .map(|chunk| u16::from_le_bytes([chunk[0], chunk.get(1).copied().unwrap_or(0)]))
            .collect();

        // Get temperature for metadata (while we hold the mutex)
        let temperature = if self.capabilities.can_cool {
            self.get_control_value(SvbControlType::CurrentTemperature)
                .map(|v| v as f64 / 10.0)
                .ok()
        } else {
            None
        };

        let metadata = ImageMetadata {
            exposure_time: self.exposure_duration,
            gain: self.current_gain,
            offset: self.current_offset,
            bin_x: self.current_bin_x,
            bin_y: self.current_bin_y,
            temperature,
            timestamp: chrono::Utc::now(),
            subframe: self.subframe.clone(),
            readout_mode: None,
            vendor_data: VendorFeatures::default(),
        };

        self.state = CameraState::Idle;
        self.exposure_start = None;

        Ok(ImageData {
            width: width as u32,
            height: height as u32,
            data,
            bits_per_pixel: self.sensor_info.bit_depth,
            bayer_pattern: self.sensor_info.bayer_pattern,
            metadata,
        })
    }

    async fn set_cooler(&mut self, enabled: bool, target_temp: f64) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        if !self.capabilities.can_cool {
            return Err(NativeError::NotSupported);
        }

        // Use async mutex-protected methods
        self.set_control_value_async(SvbControlType::CoolerEnable, if enabled { 1 } else { 0 })
            .await?;
        if enabled {
            // SVBony uses temperature * 10
            self.set_control_value_async(
                SvbControlType::TargetTemperature,
                (target_temp * 10.0) as i64,
            )
            .await?;
        }

        self.cooler_on = enabled;
        self.target_temp = target_temp;
        Ok(())
    }

    async fn get_temperature(&self) -> Result<f64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        if !self.capabilities.can_cool {
            return Err(NativeError::NotSupported);
        }

        // Use async mutex-protected method
        let value = self
            .get_control_value_async(SvbControlType::CurrentTemperature)
            .await?;
        Ok(value as f64 / 10.0)
    }

    async fn get_cooler_power(&self) -> Result<f64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        if !self.capabilities.can_cool {
            return Err(NativeError::NotSupported);
        }

        // Use async mutex-protected method
        let value = self
            .get_control_value_async(SvbControlType::CoolerPower)
            .await?;
        Ok(value as f64)
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        // Use async mutex-protected method
        self.set_control_value_async(SvbControlType::Gain, gain as i64)
            .await?;
        self.current_gain = gain;
        Ok(())
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        Ok(self.current_gain)
    }

    async fn set_offset(&mut self, offset: i32) -> Result<(), NativeError> {
        // Use async mutex-protected method
        self.set_control_value_async(SvbControlType::BlackLevel, offset as i64)
            .await?;
        self.current_offset = offset;
        Ok(())
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        Ok(self.current_offset)
    }

    async fn set_binning(&mut self, bin_x: i32, bin_y: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // SVBony only supports symmetric binning
        let bin = bin_x.min(bin_y);
        if bin > self.capabilities.max_bin_x {
            return Err(NativeError::InvalidParameter(format!(
                "Binning {} exceeds max {}",
                bin, self.capabilities.max_bin_x
            )));
        }

        let sdk = get_sdk()?;

        let width = (self.sensor_info.width as i32) / bin;
        let height = (self.sensor_info.height as i32) / bin;

        // Acquire mutex for SDK operations
        let _lock = svbony_mutex().lock().await;

        // SAFETY: svbony_mutex held above (in set_binning()); `self.camera_id` validated; all six arguments are POD c_int (no out-pointers). `width`/`height` were computed from sensor_info divided by `bin` which is ≥ 1 (bin_x.min(bin_y)) and clamped by capabilities.max_bin_x, so dimensions stay within the sensor.
        let result = unsafe {
            (sdk.set_roi_format)(
                self.camera_id,
                0,
                0,
                width as c_int,
                height as c_int,
                bin as c_int,
            )
        };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("set binning"));
        }

        self.current_bin_x = bin;
        self.current_bin_y = bin;
        Ok(())
    }

    async fn get_binning(&self) -> Result<(i32, i32), NativeError> {
        Ok((self.current_bin_x, self.current_bin_y))
    }

    async fn set_subframe(&mut self, subframe: Option<SubFrame>) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        let (start_x, start_y, width, height) = match &subframe {
            Some(sf) => (
                sf.start_x as c_int,
                sf.start_y as c_int,
                sf.width as c_int,
                sf.height as c_int,
            ),
            None => (
                0,
                0,
                (self.sensor_info.width / self.current_bin_x as u32) as c_int,
                (self.sensor_info.height / self.current_bin_y as u32) as c_int,
            ),
        };

        // Acquire mutex for SDK operations
        let _lock = svbony_mutex().lock().await;

        // SAFETY: svbony_mutex held above (in set_subframe()); `self.camera_id` validated; all six arguments are POD c_int (no out-pointers). `start_x/start_y/width/height` come from either the caller-supplied SubFrame (validated by upstream subframe logic) or default to full-sensor dimensions scaled by current binning, so the SDK clamps to sensor bounds.
        let result = unsafe {
            (sdk.set_roi_format)(
                self.camera_id,
                start_x,
                start_y,
                width,
                height,
                self.current_bin_x as c_int,
            )
        };
        if SvbError::from_i32(result) != SvbError::Success {
            return Err(SvbError::from_i32(result).to_native_error("set subframe"));
        }

        self.subframe = subframe;
        Ok(())
    }

    fn get_sensor_info(&self) -> SensorInfo {
        self.sensor_info.clone()
    }

    async fn get_readout_modes(&self) -> Result<Vec<ReadoutMode>, NativeError> {
        // SVBony cameras don't have distinct readout modes
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

    async fn set_readout_mode(&mut self, mode: &ReadoutMode) -> Result<(), NativeError> {
        // SVBony cameras expose a single fixed readout mode.
        if mode.index == 0 || mode.name.eq_ignore_ascii_case("normal") {
            return Ok(());
        }
        Err(NativeError::NotSupported)
    }

    async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
        Ok(VendorFeatures::default())
    }

    async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Use async mutex-protected method
        let (min, max) = self.get_control_range_async(SvbControlType::Gain).await?;
        Ok((min as i32, max as i32))
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // SVBony uses BlackLevel as the offset control (use async mutex-protected method)
        let (min, max) = self
            .get_control_range_async(SvbControlType::BlackLevel)
            .await?;
        Ok((min as i32, max as i32))
    }
}
