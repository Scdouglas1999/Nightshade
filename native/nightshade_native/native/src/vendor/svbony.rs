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

/// Full-scale ADU of the delivered pixel container for an SVBony camera whose
/// sensor is `bit_depth` bits, given the output image type actually negotiated
/// with the SDK.
///
/// `SVB_CAMERA_PROPERTY.MaxBitDepth` is the **sensor's** bit width, not the
/// container's — SVBony say so in their own changelog for SDK v1.12.7
/// (2024-05-06): "MaxBitDepth in SVB_CAMERA_PROPERTY returns the actual bit
/// width of the sensor" (`SDKs/SVBony/SVBONY/ReadMe.txt:424,430`).
///
/// With `SVB_IMG_RAW16` selected the SDK left-justifies those sensor bits into
/// the 16-bit buffer, exactly like ZWO. Measured on real hardware, an SV305
/// (12-bit sensor): after SVBony changed the SDK to expose RAW16 in place of
/// RAW12, SharpCap's sensor analysis reported e-/ADU 16x smaller across all 11
/// gain rows, moving the implied saturation level from exactly 4096 ADU to
/// exactly 65536 ADU. SharpCap's author states the mechanism directly:
///
/// > Previously the data came from the SDK at 12 bits (0..4095), which SharpCap
/// > would multiply by 16, leading to values from 0..65520 (all the values being
/// > multiples of 16). ... Now the data comes from the SDK at 16 bits. If all the
/// > white balance/contrast/sharpness etc are default then all the pixel values
/// > will be multiples of 16 and the 12 bit depth of the sensor will be detected
/// > correctly.
///
/// — <https://forums.sharpcap.co.uk/viewtopic.php?t=4837> (posts #3 and #6).
/// "All the pixel values will be multiples of 16" over a 12-bit sensor is the
/// left-justification signature: the reachable ceiling is `4095 << 4 = 65520`,
/// not 4095. Reporting `(1 << MaxBitDepth) - 1` understated it 16x and made every
/// percent-of-full-scale consumer — flat-frame targets above all — unreachable.
///
/// `SVB_IMG_RAW8` is a genuine 8-bit container (the SDK takes the high bits), so
/// its ceiling is 255 regardless of sensor bit depth. This matters because
/// `connect()` falls back to RAW8 when a model does not offer RAW16; before this
/// function the driver kept publishing the sensor-derived ceiling in that case,
/// which overstated an 8-bit frame by up to 16x in the other direction.
///
/// `bit_depth == 0` or `>= 16` means either an unpopulated property or a
/// genuinely 16-bit ADC; both take the container's own ceiling rather than
/// underflowing to 0, which would report "this camera cannot produce any signal".
fn container_max_adu(image_type: SvbImgType, bit_depth: u32) -> u32 {
    const CONTAINER_BITS: u32 = 16;
    const CONTAINER_MAX: u32 = u16::MAX as u32;
    match image_type {
        SvbImgType::Raw8 => u32::from(u8::MAX),
        SvbImgType::Raw16 => {
            if bit_depth == 0 || bit_depth >= CONTAINER_BITS {
                return CONTAINER_MAX;
            }
            (((1u32 << bit_depth) - 1) << (CONTAINER_BITS - bit_depth)) & CONTAINER_MAX
        }
    }
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
    // SVB_CAMERA_PROPERTY ends here per SVBCameraSDK.h — ONLY MaxBitDepth +
    // IsTriggerCam follow the format array. The previous definition appended
    // ZWO's ASICameraInfo tail (pixel_size/mechanical_shutter/st4_port/
    // is_cooler_cam/is_usb3_*/elec_per_adu), which the SDK never writes: every
    // field past the format array was read from uninitialized stack, so
    // bit_depth came out 0 (→ max_adu=0 on every frame) and cooling read false.
    // Cooling support comes from SVB_CAMERA_PROPERTY_EX.bSupportControlTemp and
    // pixel size from SVBGetSensorPixelSize(), NOT from this struct.
    max_bit_depth: c_int,
    is_trigger_cam: c_int,
}

/// Camera property extended structure (SVB_CAMERA_PROPERTY_EX)
#[repr(C)]
#[derive(Debug)]
struct SvbCameraPropertyEx {
    b_support_pulse_guide: c_int,
    b_support_control_temp: c_int,
    // SVB_CAMERA_PROPERTY_EX has `int Unused[64]` here (SVBCameraSDK.h). The old
    // `[c_int; 8]` under-sized the struct by 224 bytes, so SVBGetCameraPropertyEx
    // wrote past the stack buffer on every connect (UB / stack corruption).
    unused: [c_int; 64],
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
// SVBGetSensorPixelSize(int iCameraID, float *fPixelSize) — pixel size in µm.
// SVB_CAMERA_PROPERTY has NO pixel-size field (unlike ZWO), so this is the only
// source; the reference driver (svbony_base.cpp:760) queries it the same way.
type SvbGetSensorPixelSize = unsafe extern "C" fn(camera_id: c_int, pixel_size: *mut f32) -> c_int;
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

/// Candidate paths for the SVBony camera SDK, in search order.
fn svbony_candidate_paths() -> Vec<std::path::PathBuf> {
    let lib_name = if cfg!(target_os = "windows") {
        "SVBCameraSDK.dll"
    } else if cfg!(target_os = "macos") {
        "libSVBCameraSDK.dylib"
    } else {
        "libSVBCameraSDK.so"
    };
    let system_paths = if cfg!(target_os = "linux") {
        vec![
            format!("/usr/lib/{lib_name}"),
            format!("/usr/local/lib/{lib_name}"),
        ]
    } else if cfg!(target_os = "macos") {
        vec![
            format!("/usr/local/lib/{lib_name}"),
            format!("/opt/homebrew/lib/{lib_name}"),
        ]
    } else {
        Vec::new()
    };
    let system_path_refs = system_paths.iter().map(String::as_str).collect::<Vec<_>>();
    crate::vendor::sdk_loader::vendor_library_candidates(&[lib_name], &system_path_refs)
}

crate::load_vendor_sdk! {
    /// SVBony SDK wrapper with dynamically loaded functions
    vendor_name: "SVBony",
    sdk_struct: SvbonySdk,
    sdk_static: SDK,
    candidate_paths_fn: svbony_candidate_paths,
    symbols: {
        get_num_of_connected_cameras: b"SVBGetNumOfConnectedCameras\0" => SvbGetNumOfConnectedCameras,
        get_camera_info: b"SVBGetCameraInfo\0" => SvbGetCameraInfo,
        get_camera_property: b"SVBGetCameraProperty\0" => SvbGetCameraProperty,
        get_camera_property_ex: b"SVBGetCameraPropertyEx\0" => SvbGetCameraPropertyEx,
        get_sensor_pixel_size: b"SVBGetSensorPixelSize\0" => SvbGetSensorPixelSize,
        open_camera: b"SVBOpenCamera\0" => SvbOpenCamera,
        close_camera: b"SVBCloseCamera\0" => SvbCloseCamera,
        get_num_of_controls: b"SVBGetNumOfControls\0" => SvbGetNumOfControls,
        get_control_caps: b"SVBGetControlCaps\0" => SvbGetControlCaps,
        get_control_value: b"SVBGetControlValue\0" => SvbGetControlValue,
        set_control_value: b"SVBSetControlValue\0" => SvbSetControlValue,
        set_roi_format: b"SVBSetROIFormat\0" => SvbSetROIFormat,
        get_roi_format: b"SVBGetROIFormat\0" => SvbGetROIFormat,
        set_output_image_type: b"SVBSetOutputImageType\0" => SvbSetOutputImageType,
        get_output_image_type: b"SVBGetOutputImageType\0" => SvbGetOutputImageType,
        start_video_capture: b"SVBStartVideoCapture\0" => SvbStartVideoCapture,
        stop_video_capture: b"SVBStopVideoCapture\0" => SvbStopVideoCapture,
        get_video_data: b"SVBGetVideoData\0" => SvbGetVideoData,
        get_sdk_version: b"SVBGetSDKVersion\0" => SvbGetSdkVersion,
    }
}

fn svb_control_value_to_i32(value: i64, label: &str) -> Result<i32, NativeError> {
    i32::try_from(value).map_err(|_| {
        NativeError::SdkError(format!(
            "SVBony SDK returned out-of-range {} value: {}",
            label, value
        ))
    })
}

fn get_sdk() -> Result<&'static SvbonySdk, NativeError> {
    SvbonySdk::get_or_reason().map_err(|reason| NativeError::SdkError(reason.to_string()))
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
    pub sdk_version: Option<String>,
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
    let sdk_version = sdk_version_from_sdk(sdk);

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
                sdk_version: sdk_version.clone(),
                // Why: `i` ranges 0..count where count is c_int >= 0 (loop bound).
                // Negative would not enter the loop. `as usize` is widening with verified
                // non-negative value; total camera count tops out below double digits.
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
        Ok(sdk) => (
            true,
            sdk_version_from_sdk(sdk).unwrap_or_else(|| "SVBony SDK vunknown".to_string()),
        ),
        Err(e) => (false, format!("SDK not available: {}", e)),
    }
}

fn sdk_version_from_sdk(sdk: &SvbonySdk) -> Option<String> {
    // SAFETY: SVBGetSDKVersion returns a pointer to a static, NUL-terminated C string baked into the SDK shared library (per SVBCameraSDK.h); the SDK library is owned by SDK::OnceLock so the pointer is valid for the program's lifetime. We explicitly null-check before reading.
    let ptr = unsafe { (sdk.get_sdk_version)() };
    if ptr.is_null() {
        return None;
    }
    // SAFETY: ptr was just null-checked; the SDK returns a static NUL-terminated
    // version string that outlives this call.
    let version = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .trim()
        .to_string();
    (!version.is_empty()).then_some(format!("SVBony SDK v{version}"))
}

pub fn sdk_version() -> Option<String> {
    get_sdk().ok().and_then(sdk_version_from_sdk)
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
    image_type: SvbImgType,
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
            image_type: SvbImgType::Raw16,
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
        // Why: c_long -> i64 is widening on every Tier 1 target (LP64: c_long is i64;
        // LLP64 Windows: c_long is i32). Value range is preserved.
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
        // Why: c_long -> i64 is widening on every Tier 1 target. Range is preserved.
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
        let (min, max, _default) = self.get_control_caps_async(target_type).await?;
        Ok((min, max))
    }

    /// Get full `(min, max, default)` caps for a control (mutex protected).
    ///
    /// SVBony's `SvbControlCaps` includes a per-control `default_value` field
    /// (matching ZWO's layout). For the Gain control this is the value SVBony's
    /// firmware reports as the recommended starting point — surfaced here so
    /// the bridge can present a unity-gain recommendation when available.
    async fn get_control_caps_async(
        &self,
        target_type: SvbControlType,
    ) -> Result<(i64, i64, i64), NativeError> {
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
                // Why: caps.min_value/max_value/default_value are c_long; widening
                // to i64 is value-preserving on every Tier 1 target
                // (LP64: c_long == i64; LLP64 Windows: i32 -> i64).
                return Ok((
                    caps.min_value as i64,
                    caps.max_value as i64,
                    caps.default_value as i64,
                ));
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
            // Cooling is reported by SVB_CAMERA_PROPERTY_EX.bSupportControlTemp —
            // there is no IsCoolerCam field in SVB_CAMERA_PROPERTY (the old
            // prop.is_cooler_cam read uninitialized stack → always false, so cooled
            // SV405CC/SV605MC/CC never got regulation). Matches svbony_base.cpp.
            can_cool: prop_ex.b_support_control_temp != 0,
            can_set_gain: true,
            can_set_offset: true,
            can_set_binning: max_bin > 1,
            can_subframe: true,
            // SVBony cameras are CMOS with no mechanical shutter and the SDK exposes
            // no such field (the old prop.mechanical_shutter read uninitialized stack).
            has_shutter: false,
            has_guider_port: prop_ex.b_support_pulse_guide != 0,
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

        // Set sensor info.
        // Why: max_width/max_height are c_long (positive sensor dimensions, <= ~16k on
        // SVBony hardware). Use try_into to fail closed on negative or absurd values.
        let width_u32 = u32::try_from(prop.max_width).map_err(|_| {
            NativeError::SdkError(format!(
                "SVBony reported invalid sensor width: {}",
                prop.max_width
            ))
        })?;
        let height_u32 = u32::try_from(prop.max_height).map_err(|_| {
            NativeError::SdkError(format!(
                "SVBony reported invalid sensor height: {}",
                prop.max_height
            ))
        })?;
        let bit_depth_u32 = u32::try_from(prop.max_bit_depth).map_err(|_| {
            NativeError::SdkError(format!(
                "SVBony reported invalid bit_depth: {}",
                prop.max_bit_depth
            ))
        })?;
        // SVB_CAMERA_PROPERTY carries no pixel size; query it separately (µm).
        // The old prop.pixel_size read uninitialized stack. Failure → 0.0
        // (unknown); the reference (svbony_base.cpp:760) queries the same way.
        let pixel_size_um = {
            let mut px: f32 = 0.0;
            // SAFETY: svbony_mutex held; `self.camera_id` valid; `&mut px` is a valid f32 out-pointer.
            let _ = unsafe { (sdk.get_sensor_pixel_size)(self.camera_id, &mut px) };
            f64::from(px)
        };
        self.sensor_info = SensorInfo {
            width: width_u32,
            height: height_u32,
            pixel_size_x: pixel_size_um,
            pixel_size_y: pixel_size_um,
            // Provisional: the container ceiling depends on the output image
            // type, which connect() negotiates a few statements below. It is
            // recomputed there via [`container_max_adu`] once `self.image_type`
            // is known. `bit_depth` is the sensor's ADC precision (SVBony SDK
            // changelog v1.12.7) and is a different quantity — see the
            // `SensorInfo::max_adu` contract.
            max_adu: container_max_adu(self.image_type, bit_depth_u32),
            bit_depth: bit_depth_u32,
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
        self.image_type = if SvbError::from_i32(result) == SvbError::Success {
            SvbImgType::Raw16
        } else {
            tracing::warn!("Could not set 16-bit output, trying 8-bit");
            // SAFETY: svbony_mutex held; `self.camera_id` valid; `SvbImgType::Raw8 as c_int` is a stable discriminant from SVBCameraSDK.h. Fallback path when Raw16 is unsupported by this model.
            let fallback_result =
                unsafe { (sdk.set_output_image_type)(self.camera_id, SvbImgType::Raw8 as c_int) };
            if SvbError::from_i32(fallback_result) != SvbError::Success {
                // SAFETY: svbony_mutex held; the camera was opened above and neither
                // supported RAW format could be configured, so close before failing.
                unsafe { (sdk.close_camera)(self.camera_id) };
                return Err(SvbError::from_i32(fallback_result)
                    .to_native_error("set 8-bit output image type"));
            }
            SvbImgType::Raw8
        };
        // The output image type is what determines the pixel container, so the
        // published ceiling has to be recomputed now that it is settled: RAW16
        // left-justifies the sensor bits into 16 bits (ceiling 65520 for a
        // 12-bit sensor), while the RAW8 fallback above caps every sample at
        // 255. See [`container_max_adu`].
        self.sensor_info.max_adu = container_max_adu(self.image_type, self.sensor_info.bit_depth);
        self.connected = true;
        self.state = CameraState::Idle;

        // Drop the SDK mutex before applying the post-open settle. Control reads
        // performed before this delay can return stale firmware values.
        drop(_lock);

        let quirk_lookup_id = format!("native:svbony:{}", self.name);
        if let Some(delay_ms) = crate::quirks::get_timing_delay(&quirk_lookup_id, "connect") {
            tracing::debug!(
                "Applying DelayAfterConnect quirk: sleeping {}ms before reading controls from {}",
                delay_ms,
                self.name
            );
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
        }

        // Reacquire the SDK mutex before the initial control reads.
        let _lock = svbony_mutex().lock().await;

        // Read initial gain/offset after the firmware settle.
        // Why: SVBony gain/offset values are small non-negative integers (range 0..=720
        // for gain on current SDKs) returned as i64. `as i32` saturating truncation is
        // safe in this range. We don't propagate errors here and keep the default 0
        // fallback for connect-time setup.
        if let Ok(gain) = self.get_control_value(SvbControlType::Gain) {
            self.current_gain = gain as i32;
        }
        if let Ok(offset) = self.get_control_value(SvbControlType::BlackLevel) {
            self.current_offset = offset as i32;
        }

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
        let gain = self.get_gain().await?;
        let offset = self.get_offset().await?;

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
            gain,
            offset,
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

        // Set exposure time (in microseconds).
        // Why: max exposure is configured well below 1 hour (3.6e9 us); f64 -> i64 with
        // saturation handles negative or NaN duration as 0 / i64::MAX respectively, both
        // of which the SDK rejects safely. Real astrophotography exposures cap at ~hours.
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

        // Confirm the current wire format. If the SDK cannot answer, retain the
        // format that connect successfully negotiated.
        let mut image_type = self.image_type as c_int;
        // SAFETY: svbony_mutex held; `self.camera_id` is connected and
        // `&mut image_type` is a valid c_int out-pointer.
        let image_type_result =
            unsafe { (sdk.get_output_image_type)(self.camera_id, &mut image_type) };
        if SvbError::from_i32(image_type_result) == SvbError::Success {
            self.image_type = match image_type {
                value if value == SvbImgType::Raw8 as c_int => SvbImgType::Raw8,
                value if value == SvbImgType::Raw16 as c_int => SvbImgType::Raw16,
                value => {
                    return Err(NativeError::SdkError(format!(
                        "SVBony reported unsupported output image type: {}",
                        value
                    )));
                }
            };
        } else {
            tracing::warn!(
                "Could not confirm SVBony output image type; using negotiated {:?}",
                self.image_type
            );
        }

        // Size and decode according to the actual negotiated wire format.
        let bytes_per_pixel = match self.image_type {
            SvbImgType::Raw8 => 1,
            SvbImgType::Raw16 => 2,
        };
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

        // Convert the negotiated wire format to the pipeline's u16 pixels.
        let data: Vec<u16> = match self.image_type {
            SvbImgType::Raw8 => self.image_buffer[..buffer_size]
                .iter()
                .copied()
                .map(u16::from)
                .collect(),
            SvbImgType::Raw16 => self.image_buffer[..buffer_size]
                .chunks_exact(2)
                .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                .collect(),
        };

        // Get temperature for metadata (while we hold the mutex)
        let temperature = if self.capabilities.can_cool {
            self.get_control_value(SvbControlType::CurrentTemperature)
                .map(|v| v as f64 / 10.0)
                .ok()
        } else {
            None
        };
        let gain = svb_control_value_to_i32(self.get_control_value(SvbControlType::Gain)?, "gain")?;
        let offset = svb_control_value_to_i32(
            self.get_control_value(SvbControlType::BlackLevel)?,
            "offset",
        )?;

        let metadata = ImageMetadata {
            exposure_time: self.exposure_duration,
            gain,
            offset,
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

        // Why: width/height are c_int populated by SVBGetROIFormat above. A negative
        // value indicates SDK corruption; surface via try_into rather than wrap.
        let width_u32 = u32::try_from(width).map_err(|_| {
            NativeError::SdkError(format!("SVBony returned negative ROI width: {}", width))
        })?;
        let height_u32 = u32::try_from(height).map_err(|_| {
            NativeError::SdkError(format!("SVBony returned negative ROI height: {}", height))
        })?;
        Ok(ImageData {
            width: width_u32,
            height: height_u32,
            data,
            bits_per_pixel: match self.image_type {
                SvbImgType::Raw8 => 8,
                SvbImgType::Raw16 => self.sensor_info.bit_depth,
            },
            bayer_pattern: self.sensor_info.bayer_pattern,
            metadata,
        })
    }

    async fn set_cooler(
        &mut self,
        enabled: bool,
        target_temp: Option<f64>,
    ) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        if !self.capabilities.can_cool {
            return Err(NativeError::NotSupported);
        }

        // Use async mutex-protected methods
        self.set_control_value_async(SvbControlType::CoolerEnable, if enabled { 1 } else { 0 })
            .await?;
        // Only when the caller named a setpoint, and only while cooling:
        // switching off needs no target temperature.
        if let Some(target) = target_temp.filter(|_| enabled) {
            // SVBony uses temperature * 10.
            // Why: target is f64 Celsius typically in [-50.0, 50.0]; multiplied by 10
            // it fits trivially in i64. f64 -> i64 saturating cast is well-defined for
            // finite values in this range; NaN sentinel would be clamped to 0.
            self.set_control_value_async(SvbControlType::TargetTemperature, (target * 10.0) as i64)
                .await?;
            self.target_temp = target;
        }

        self.cooler_on = enabled;
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
        // Use async mutex-protected method.
        // Why: i32 -> i64 is widening (sign-extended); always safe.
        self.set_control_value_async(SvbControlType::Gain, gain as i64)
            .await?;
        self.current_gain = gain;
        Ok(())
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        let value = self.get_control_value_async(SvbControlType::Gain).await?;
        svb_control_value_to_i32(value, "gain")
    }

    async fn set_offset(&mut self, offset: i32) -> Result<(), NativeError> {
        // Use async mutex-protected method.
        // Why: i32 -> i64 is widening (sign-extended); always safe.
        self.set_control_value_async(SvbControlType::BlackLevel, offset as i64)
            .await?;
        self.current_offset = offset;
        Ok(())
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        let value = self
            .get_control_value_async(SvbControlType::BlackLevel)
            .await?;
        svb_control_value_to_i32(value, "offset")
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

        if bin < 1 {
            return Err(NativeError::InvalidParameter(format!(
                "SVBony binning must be >= 1, got bin_x={} bin_y={}",
                bin_x, bin_y
            )));
        }
        let sdk = get_sdk()?;

        // Why: sensor_info.width/height are u32 (<= 16k on SVBony hardware); converting
        // to i32 via try_from is the right way to fail closed on any pathological value.
        // bin is already validated > 0.
        let width_i32 = i32::try_from(self.sensor_info.width).map_err(|_| {
            NativeError::SdkError(format!(
                "SVBony sensor width does not fit in i32: {}",
                self.sensor_info.width
            ))
        })?;
        let height_i32 = i32::try_from(self.sensor_info.height).map_err(|_| {
            NativeError::SdkError(format!(
                "SVBony sensor height does not fit in i32: {}",
                self.sensor_info.height
            ))
        })?;
        let width = width_i32 / bin;
        let height = height_i32 / bin;

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

        // Why: SubFrame coordinates are u32, SDK wants c_int (i32). Surface a too-large
        // u32 as InvalidParameter rather than wrap. current_bin_{x,y} must be > 0; we
        // validated this at set_binning entry but defend here in case caller skipped it.
        let (start_x, start_y, width, height) = match &subframe {
            Some(sf) => (
                c_int::try_from(sf.start_x).map_err(|_| {
                    NativeError::InvalidParameter(format!(
                        "SVBony subframe start_x exceeds c_int: {}",
                        sf.start_x
                    ))
                })?,
                c_int::try_from(sf.start_y).map_err(|_| {
                    NativeError::InvalidParameter(format!(
                        "SVBony subframe start_y exceeds c_int: {}",
                        sf.start_y
                    ))
                })?,
                c_int::try_from(sf.width).map_err(|_| {
                    NativeError::InvalidParameter(format!(
                        "SVBony subframe width exceeds c_int: {}",
                        sf.width
                    ))
                })?,
                c_int::try_from(sf.height).map_err(|_| {
                    NativeError::InvalidParameter(format!(
                        "SVBony subframe height exceeds c_int: {}",
                        sf.height
                    ))
                })?,
            ),
            None => {
                let bin_x_u32 = u32::try_from(self.current_bin_x.max(1)).map_err(|_| {
                    NativeError::InvalidParameter(format!(
                        "SVBony current_bin_x not representable as u32: {}",
                        self.current_bin_x
                    ))
                })?;
                let bin_y_u32 = u32::try_from(self.current_bin_y.max(1)).map_err(|_| {
                    NativeError::InvalidParameter(format!(
                        "SVBony current_bin_y not representable as u32: {}",
                        self.current_bin_y
                    ))
                })?;
                let binned_w = self.sensor_info.width / bin_x_u32;
                let binned_h = self.sensor_info.height / bin_y_u32;
                let w_ci = c_int::try_from(binned_w).map_err(|_| {
                    NativeError::SdkError(format!(
                        "SVBony binned width does not fit in c_int: {}",
                        binned_w
                    ))
                })?;
                let h_ci = c_int::try_from(binned_h).map_err(|_| {
                    NativeError::SdkError(format!(
                        "SVBony binned height does not fit in c_int: {}",
                        binned_h
                    ))
                })?;
                (0, 0, w_ci, h_ci)
            }
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

        // Use async mutex-protected method.
        // Why: gain min/max are small non-negative integers (<= ~720 per SVBony spec)
        // returned as i64 from the control range API. `as i32` saturating truncation is
        // safe in this range.
        let (min, max) = self.get_control_range_async(SvbControlType::Gain).await?;
        Ok((min as i32, max as i32))
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // SVBony uses BlackLevel as the offset control (use async mutex-protected method).
        // Why: BlackLevel min/max are small non-negative integers (<= ~512) returned as
        // i64. `as i32` saturating truncation is safe in this range.
        let (min, max) = self
            .get_control_range_async(SvbControlType::BlackLevel)
            .await?;
        Ok((min as i32, max as i32))
    }

    /// Surface the SDK-advertised recommended settings.
    ///
    /// SVBony's `SvbControlCaps` includes a per-control `default_value` field.
    /// For the Gain control this is the value the SDK's auto-exposure logic
    /// starts at — SVBony's per-camera documentation lists this as the
    /// recommended unity-gain starting point. For BlackLevel (offset) it is
    /// the manufacturer-recommended bias value.
    ///
    /// SVBony does not expose an HCG transition through the SDK.
    async fn get_recommended_settings(
        &self,
    ) -> Result<crate::camera::CameraRecommendedSettings, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let mut out = crate::camera::CameraRecommendedSettings::default();
        let mut notes: Vec<String> = Vec::new();

        match self.get_control_caps_async(SvbControlType::Gain).await {
            Ok((_min, _max, default)) => {
                // i64 -> i32 saturating: SVBony gain caps fit in i32 (<= ~720).
                let gain = default.clamp(i32::MIN as i64, i32::MAX as i64) as i32;
                out.unity_gain = Some(gain);
                notes.push(format!("SVBony SDK reports default gain = {}", gain));
            }
            Err(NativeError::NotSupported) => {
                // Camera doesn't expose this control. Honest "no recommendation".
            }
            Err(e) => {
                tracing::warn!("SVBony: failed to query gain control caps: {:?}", e);
            }
        }

        match self
            .get_control_caps_async(SvbControlType::BlackLevel)
            .await
        {
            Ok((_min, _max, default)) => {
                let off = default.clamp(i32::MIN as i64, i32::MAX as i64) as i32;
                out.default_offset = Some(off);
                notes.push(format!("SVBony SDK reports default offset = {}", off));
            }
            Err(NativeError::NotSupported) => {
                // Camera doesn't expose offset control.
            }
            Err(e) => {
                tracing::warn!("SVBony: failed to query offset control caps: {:?}", e);
            }
        }

        out.notes = notes.join("; ");
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// RAW16 ceilings must be the left-justified container full scale, not the
    /// ADC range.
    ///
    /// `(1 << MaxBitDepth) - 1` — what this used to publish — is the ADC range.
    /// Measured on an SV305 (12-bit): once the SVBony SDK started delivering
    /// RAW16, every pixel value became a multiple of 16 and the saturation level
    /// moved from 4096 to 65536 ADU. See [`container_max_adu`] for the citation.
    #[test]
    fn raw16_container_max_adu_accounts_for_left_justification() {
        // 12-bit sensor (SV305/SV305 Pro class): 4095 << 4
        assert_eq!(container_max_adu(SvbImgType::Raw16, 12), 65520);
        // 14-bit sensor: 16383 << 2
        assert_eq!(container_max_adu(SvbImgType::Raw16, 14), 65532);
        // 10-bit sensor: 1023 << 6
        assert_eq!(container_max_adu(SvbImgType::Raw16, 10), 65472);
        // A genuinely 16-bit sensor (SV605MC/SV605CC class) needs no shift.
        assert_eq!(container_max_adu(SvbImgType::Raw16, 16), 65535);
    }

    /// Whatever ceiling we publish must be a value a `u16` sample can hold, and
    /// must land on the sample grid the ADC produces — a 12-bit sensor
    /// left-justified into 16 bits can only emit multiples of 16.
    #[test]
    fn raw16_container_max_adu_is_a_reachable_u16_sample() {
        for bit_depth in 1..=16u32 {
            let max = container_max_adu(SvbImgType::Raw16, bit_depth);
            assert!(
                max <= u32::from(u16::MAX),
                "bit_depth {bit_depth} produced {max}, outside the u16 container"
            );
            let step = 1u32 << (16 - bit_depth.min(16));
            assert_eq!(
                max % step,
                0,
                "bit_depth {bit_depth}: {max} is not a multiple of the {step}-ADU sample step"
            );
        }
    }

    /// The RAW8 fallback in `connect()` caps every sample at 255 no matter how
    /// deep the sensor is. Publishing the sensor-derived ceiling there overstates
    /// an 8-bit frame by up to 16x and breaks flats the same way, just in the
    /// opposite direction.
    #[test]
    fn raw8_fallback_ceiling_is_the_byte_container_not_the_sensor() {
        for bit_depth in [0u32, 8, 10, 12, 14, 16] {
            assert_eq!(
                container_max_adu(SvbImgType::Raw8, bit_depth),
                255,
                "RAW8 must cap at 255 regardless of the {bit_depth}-bit sensor"
            );
        }
    }

    /// An unpopulated / out-of-range `MaxBitDepth` must fall back to the
    /// container ceiling, never to 0 — a 0 ceiling would tell every
    /// percent-of-full-scale consumer the camera cannot produce any signal, and
    /// the old `(1 << bit_depth.min(31)) - 1` returned 2147483647 for 31.
    #[test]
    fn raw16_unknown_bit_depth_falls_back_to_container() {
        assert_eq!(container_max_adu(SvbImgType::Raw16, 0), 65535);
        assert_eq!(container_max_adu(SvbImgType::Raw16, 31), 65535);
        assert_eq!(container_max_adu(SvbImgType::Raw16, u32::MAX), 65535);
    }

    /// The ceiling must agree with the pipeline's own saturation threshold
    /// (`nightshade_imaging::fits` uses 65024, documented as "4064 << 4").
    /// That threshold is unreachable under the old 4095 ceiling, which is what
    /// made flat calibration impossible on ZWO before the same fix landed there.
    #[test]
    fn raw16_container_max_adu_agrees_with_pipeline_saturation_threshold() {
        const PIPELINE_SATURATION_THRESHOLD: u32 = 65024;
        let twelve_bit_ceiling = container_max_adu(SvbImgType::Raw16, 12);
        assert!(
            PIPELINE_SATURATION_THRESHOLD < twelve_bit_ceiling,
            "12-bit ceiling {twelve_bit_ceiling} is below the pipeline saturation threshold"
        );
        // The formula this replaced published the ADC range, which can never
        // reach the threshold — so saturation was undetectable on an SV305-class
        // sensor and a 50% flat target sat below the camera's own bias floor.
        let old_adc_range_formula = |bits: u32| (1u32 << bits) - 1;
        assert!(old_adc_range_formula(12) < PIPELINE_SATURATION_THRESHOLD);
    }

    #[tokio::test]
    async fn svbony_set_gain_error_does_not_mutate_cache() {
        let mut camera = SvbonyCamera::new(0);
        camera.current_gain = 12;

        let err = camera.set_gain(48).await.unwrap_err();

        assert!(matches!(err, NativeError::NotConnected));
        assert_eq!(camera.current_gain, 12);
    }

    #[tokio::test]
    async fn svbony_set_offset_error_does_not_mutate_cache() {
        let mut camera = SvbonyCamera::new(0);
        camera.current_offset = 8;

        let err = camera.set_offset(22).await.unwrap_err();

        assert!(matches!(err, NativeError::NotConnected));
        assert_eq!(camera.current_offset, 8);
    }
}
