//! QHY Camera SDK Wrapper
//!
//! Provides native support for QHY cameras by wrapping the QHY SDK.
//! QHY cameras support advanced features like readout modes and sensor chamber readings.
//!
//! ## Thread Safety
//!
//! The QHY SDK is NOT thread-safe. All SDK operations are protected by `qhy_mutex()`
//! from `crate::sync` to prevent concurrent access. Note that QHY filter wheels (CFW)
//! are controlled through the camera SDK, so they share the same mutex.
//!
//! ## Timeout Handling
//!
//! All SDK operations that can potentially hang (exposure polling, image download)
//! have configurable timeouts via `NativeTimeoutConfig`.
//!
//! ## Safety Measures for Discovery
//!
//! The QHY SDK has been known to crash or hang during device enumeration on certain
//! systems. This module includes several safety measures:
//!
//! 1. **Enable/Disable Flag**: Discovery can be globally disabled if it causes issues
//! 2. **Panic Protection**: Discovery is wrapped in `catch_unwind` to prevent crashes
//! 3. **Timeout**: Discovery has a configurable timeout (default 10 seconds)
//! 4. **Mutex Serialization**: All discovery calls are serialized via `qhy_mutex()`
//! 5. **Quirks Integration**: Discovery respects quirks from the vendor database

#![allow(dead_code)] // FFI types must match SDK headers even if not all variants are used

use crate::camera::*;
use crate::sync::qhy_mutex;
use crate::traits::*;
use crate::utils::wait_for_exposure;
use crate::NativeVendor;
use async_trait::async_trait;
use nightshade_imaging::buffer_pool::global_u8_pool;
use std::ffi::{c_char, c_double, c_int, c_uint, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;
use std::time::Duration;

// =============================================================================
// QHY SDK TYPE DEFINITIONS
// =============================================================================

/// QHY Camera handle type
type QhyCamHandle = *mut c_void;

/// QHY Bayer patterns
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum QhyBayer {
    Mono = 0,
    Rggb = 1,
    Grbg = 2,
    Gbrg = 3,
    Bggr = 4,
}

/// QHY Control IDs - matches CONTROL_ID enum from qhyccdstruct.h
#[repr(C)]
#[derive(Debug, Clone, Copy)]
#[allow(non_camel_case_types)]
pub enum QhyControl {
    CONTROL_BRIGHTNESS = 0,
    CONTROL_CONTRAST = 1,
    CONTROL_WBR = 2,
    CONTROL_WBB = 3,
    CONTROL_WBG = 4,
    CONTROL_GAMMA = 5,
    CONTROL_GAIN = 6,
    CONTROL_OFFSET = 7,
    CONTROL_EXPOSURE = 8,
    CONTROL_SPEED = 9,
    CONTROL_TRANSFERBIT = 10,
    CONTROL_CHANNELS = 11,
    CONTROL_USBTRAFFIC = 12,
    CONTROL_ROWNOISERE = 13,
    CONTROL_CURTEMP = 14,
    CONTROL_CURPWM = 15,
    CONTROL_MANULPWM = 16,
    CONTROL_CFWPORT = 17,
    CONTROL_COOLER = 18,
    CONTROL_ST4PORT = 19,
    CAM_COLOR = 20,
    CAM_BIN1X1MODE = 21,
    CAM_BIN2X2MODE = 22,
    CAM_BIN3X3MODE = 23,
    CAM_BIN4X4MODE = 24,
    CAM_MECHANICALSHUTTER = 25,
    CAM_TRIGER_INTERFACE = 26,
    CAM_TECOVERPROTECT_INTERFACE = 27,
    CAM_SINGNALCLAMP_INTERFACE = 28,
    CAM_FINETONE_INTERFACE = 29,
    CAM_SHUTTERMOTORHEATING_INTERFACE = 30,
    CAM_CALIBRATEFPN_INTERFACE = 31,
    CAM_CHIPTEMPERATURESENSOR_INTERFACE = 32,
    CAM_USBREADOUTSLOWEST_INTERFACE = 33,
    CAM_8BITS = 34,
    CAM_16BITS = 35,
    CAM_GPS = 36,
    CAM_IGNOREOVERSCAN_INTERFACE = 37,
    QHYCCD_3A_AUTOEXPOSURE = 39,
    QHYCCD_3A_AUTOFOCUS = 40,
    CONTROL_AMPV = 41,
    CONTROL_VCAM = 42,
    CAM_VIEW_MODE = 43,
    CONTROL_CFWSLOTSNUM = 44,
    IS_EXPOSING_DONE = 45,
    ScreenStretchB = 46,
    ScreenStretchW = 47,
    CONTROL_DDR = 48,
    CAM_LIGHT_PERFORMANCE_MODE = 49,
    CAM_QHY5II_GUIDE_MODE = 50,
    DDR_BUFFER_CAPACITY = 51,
    DDR_BUFFER_READ_THRESHOLD = 52,
    DefaultGain = 53,
    DefaultOffset = 54,
    OutputDataActualBits = 55,
    OutputDataAlignment = 56,
    CAM_SINGLEFRAMEMODE = 57,
    CAM_LIVEVIDEOMODE = 58,
    CAM_IS_COLOR = 59,
    hasHardwareFrameCounter = 60,
    CAM_HUMIDITY = 62,
    CAM_PRESSURE = 63,
}

// =============================================================================
// SDK LIBRARY LOADING
// =============================================================================

/// QHY SDK library wrapper
struct QhySdk {
    #[allow(dead_code)]
    lib: libloading::Library,

    // Function pointers - Core
    init_sdk: unsafe extern "C" fn() -> c_uint,
    release_sdk: unsafe extern "C" fn() -> c_uint,
    scan_qhyccd: unsafe extern "C" fn() -> c_uint,
    get_qhyccd_id: unsafe extern "C" fn(c_uint, *mut c_char) -> c_uint,
    open_qhyccd: unsafe extern "C" fn(*const c_char) -> QhyCamHandle,
    close_qhyccd: unsafe extern "C" fn(QhyCamHandle) -> c_uint,

    // Camera initialization
    set_qhyccd_stream_mode: unsafe extern "C" fn(QhyCamHandle, c_uint) -> c_uint,
    init_qhyccd: unsafe extern "C" fn(QhyCamHandle) -> c_uint,

    // Camera info
    get_qhyccd_chip_info: unsafe extern "C" fn(
        QhyCamHandle,
        *mut c_double,
        *mut c_double, // chip_w, chip_h
        *mut c_uint,
        *mut c_uint, // image_w, image_h
        *mut c_double,
        *mut c_double, // pixel_w, pixel_h
        *mut c_uint,   // bpp
    ) -> c_uint,
    is_qhyccd_control_available: unsafe extern "C" fn(QhyCamHandle, c_int) -> c_uint,
    get_qhyccd_effective_area: unsafe extern "C" fn(
        QhyCamHandle,
        *mut c_uint,
        *mut c_uint,
        *mut c_uint,
        *mut c_uint,
    ) -> c_uint,

    // Camera control
    set_qhyccd_param: unsafe extern "C" fn(QhyCamHandle, c_int, c_double) -> c_uint,
    get_qhyccd_param: unsafe extern "C" fn(QhyCamHandle, c_int) -> c_double,
    get_qhyccd_param_min_max_step: unsafe extern "C" fn(
        QhyCamHandle,
        c_int,
        *mut c_double,
        *mut c_double,
        *mut c_double,
    ) -> c_uint,
    set_qhyccd_resolution:
        unsafe extern "C" fn(QhyCamHandle, c_uint, c_uint, c_uint, c_uint) -> c_uint,
    set_qhyccd_binmode: unsafe extern "C" fn(QhyCamHandle, c_uint, c_uint) -> c_uint,
    set_qhyccd_bits_mode: unsafe extern "C" fn(QhyCamHandle, c_uint) -> c_uint,

    // Exposure control
    exp_single_frame: unsafe extern "C" fn(QhyCamHandle) -> c_uint,
    get_qhyccd_single_frame: unsafe extern "C" fn(
        QhyCamHandle,
        *mut c_uint,
        *mut c_uint,
        *mut c_uint,
        *mut c_uint,
        *mut u8,
    ) -> c_uint,
    cancel_qhyccd_exposing_and_readout: unsafe extern "C" fn(QhyCamHandle) -> c_uint,
    get_qhyccd_memory_length: unsafe extern "C" fn(QhyCamHandle) -> c_uint,

    // Readout modes
    get_qhyccd_read_mode_name: unsafe extern "C" fn(QhyCamHandle, c_uint, *mut c_char) -> c_uint,
    get_qhyccd_number_of_read_modes: unsafe extern "C" fn(QhyCamHandle, *mut c_uint) -> c_uint,
    set_qhyccd_read_mode: unsafe extern "C" fn(QhyCamHandle, c_uint) -> c_uint,
    get_qhyccd_read_mode: unsafe extern "C" fn(QhyCamHandle, *mut c_uint) -> c_uint,

    // Color Filter Wheel (CFW) control
    is_qhyccd_cfw_plugged: unsafe extern "C" fn(QhyCamHandle) -> c_uint,
}

unsafe impl Send for QhySdk {}
unsafe impl Sync for QhySdk {}

static QHY_SDK: OnceLock<Option<QhySdk>> = OnceLock::new();
static SDK_INITIALIZED: OnceLock<bool> = OnceLock::new();

// =============================================================================
// QHY DISCOVERY CONFIGURATION
// =============================================================================

/// Global flag to enable/disable QHY discovery.
///
/// QHY discovery can be disabled if it causes crashes or hangs on a particular system.
/// Default is `true` (enabled).
static QHY_DISCOVERY_ENABLED: AtomicBool = AtomicBool::new(true);

/// Default timeout for QHY discovery operations in milliseconds.
/// This can be overridden by the quirks database.
const DEFAULT_DISCOVERY_TIMEOUT_MS: u64 = 10000;

/// Configuration for QHY discovery safety measures
#[derive(Debug, Clone)]
pub struct QhyDiscoveryConfig {
    /// Whether discovery is enabled
    pub enabled: bool,
    /// Timeout for discovery operations in milliseconds
    pub timeout_ms: u64,
    /// Whether to use catch_unwind for crash protection
    pub catch_panics: bool,
}

impl Default for QhyDiscoveryConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            timeout_ms: DEFAULT_DISCOVERY_TIMEOUT_MS,
            catch_panics: true,
        }
    }
}

/// Check if QHY discovery is enabled.
pub fn is_qhy_discovery_enabled() -> bool {
    QHY_DISCOVERY_ENABLED.load(Ordering::SeqCst)
}

/// Enable or disable QHY discovery.
///
/// When disabled, `discover_devices()` will return an empty list without
/// attempting to scan for cameras. This is useful if the QHY SDK causes
/// crashes or hangs on a particular system.
///
/// # Arguments
/// * `enabled` - Whether to enable QHY discovery
pub fn set_qhy_discovery_enabled(enabled: bool) {
    let previous = QHY_DISCOVERY_ENABLED.swap(enabled, Ordering::SeqCst);
    if previous != enabled {
        tracing::info!(
            "QHY discovery {} -> {}",
            if previous { "enabled" } else { "disabled" },
            if enabled { "enabled" } else { "disabled" }
        );
    }
}

/// Get the current QHY discovery configuration, including quirks from the database.
fn get_discovery_config() -> QhyDiscoveryConfig {
    let mut timeout_ms = DEFAULT_DISCOVERY_TIMEOUT_MS;

    // Check quirks database for QHY-specific discovery settings
    let vendor_quirks = crate::quirks::get_quirks_for_vendor(&crate::NativeVendor::Qhy);
    for quirk in vendor_quirks {
        if let crate::quirks::Quirk::Discovery(crate::quirks::DiscoveryQuirk::DiscoveryTimeoutMs(
            timeout,
        )) = quirk
        {
            timeout_ms = timeout;
        }
    }

    QhyDiscoveryConfig {
        enabled: is_qhy_discovery_enabled(),
        timeout_ms,
        catch_panics: true,
    }
}

impl QhySdk {
    /// Load the QHY SDK library
    fn load() -> Option<Self> {
        let lib_paths = if cfg!(target_os = "windows") {
            vec![
                "qhyccd.dll",
                "C:\\Program Files\\QHYCCD\\AllInOne\\sdk\\x64\\qhyccd.dll",
                "C:\\Program Files (x86)\\QHYCCD\\AllInOne\\sdk\\qhyccd.dll",
            ]
        } else if cfg!(target_os = "macos") {
            vec![
                "libqhyccd.dylib",
                "/usr/local/lib/libqhyccd.dylib",
                "/Library/Frameworks/QHYCCD.framework/QHYCCD",
            ]
        } else {
            vec![
                "libqhyccd.so",
                "libqhyccd.so.21",
                "/usr/lib/libqhyccd.so",
                "/usr/local/lib/libqhyccd.so",
            ]
        };

        for path in lib_paths {
            unsafe {
                if let Ok(lib) = libloading::Library::new(path) {
                    tracing::info!("Loaded QHY SDK from: {}", path);

                    // Load all function pointers
                    let sdk = Self {
                        init_sdk: *lib.get(b"InitQHYCCDResource\0").ok()?,
                        release_sdk: *lib.get(b"ReleaseQHYCCDResource\0").ok()?,
                        scan_qhyccd: *lib.get(b"ScanQHYCCD\0").ok()?,
                        get_qhyccd_id: *lib.get(b"GetQHYCCDId\0").ok()?,
                        open_qhyccd: *lib.get(b"OpenQHYCCD\0").ok()?,
                        close_qhyccd: *lib.get(b"CloseQHYCCD\0").ok()?,
                        set_qhyccd_stream_mode: *lib.get(b"SetQHYCCDStreamMode\0").ok()?,
                        init_qhyccd: *lib.get(b"InitQHYCCD\0").ok()?,
                        get_qhyccd_chip_info: *lib.get(b"GetQHYCCDChipInfo\0").ok()?,
                        is_qhyccd_control_available: *lib
                            .get(b"IsQHYCCDControlAvailable\0")
                            .ok()?,
                        get_qhyccd_effective_area: *lib.get(b"GetQHYCCDEffectiveArea\0").ok()?,
                        set_qhyccd_param: *lib.get(b"SetQHYCCDParam\0").ok()?,
                        get_qhyccd_param: *lib.get(b"GetQHYCCDParam\0").ok()?,
                        get_qhyccd_param_min_max_step: *lib
                            .get(b"GetQHYCCDParamMinMaxStep\0")
                            .ok()?,
                        set_qhyccd_resolution: *lib.get(b"SetQHYCCDResolution\0").ok()?,
                        set_qhyccd_binmode: *lib.get(b"SetQHYCCDBinMode\0").ok()?,
                        set_qhyccd_bits_mode: *lib.get(b"SetQHYCCDBitsMode\0").ok()?,
                        exp_single_frame: *lib.get(b"ExpQHYCCDSingleFrame\0").ok()?,
                        get_qhyccd_single_frame: *lib.get(b"GetQHYCCDSingleFrame\0").ok()?,
                        cancel_qhyccd_exposing_and_readout: *lib
                            .get(b"CancelQHYCCDExposingAndReadout\0")
                            .ok()?,
                        get_qhyccd_memory_length: *lib.get(b"GetQHYCCDMemLength\0").ok()?,
                        get_qhyccd_read_mode_name: *lib.get(b"GetQHYCCDReadModeName\0").ok()?,
                        get_qhyccd_number_of_read_modes: *lib
                            .get(b"GetQHYCCDNumberOfReadModes\0")
                            .ok()?,
                        set_qhyccd_read_mode: *lib.get(b"SetQHYCCDReadMode\0").ok()?,
                        get_qhyccd_read_mode: *lib.get(b"GetQHYCCDReadMode\0").ok()?,
                        is_qhyccd_cfw_plugged: *lib.get(b"IsQHYCCDCFWPlugged\0").ok()?,
                        lib,
                    };

                    return Some(sdk);
                }
            }
        }

        tracing::debug!("QHY SDK not found");
        None
    }

    /// Get the global SDK instance
    fn get() -> Option<&'static QhySdk> {
        QHY_SDK.get_or_init(Self::load).as_ref()
    }

    /// Initialize the SDK (must be called once before use)
    fn ensure_initialized() -> Result<(), NativeError> {
        if *SDK_INITIALIZED.get_or_init(|| {
            if let Some(sdk) = Self::get() {
                let result = unsafe { (sdk.init_sdk)() };
                if result == 0 {
                    // QHYCCD_SUCCESS
                    tracing::info!("QHY SDK initialized successfully");
                    true
                } else {
                    tracing::error!("Failed to initialize QHY SDK: error {}", result);
                    false
                }
            } else {
                false
            }
        }) {
            Ok(())
        } else {
            Err(NativeError::SdkNotLoaded)
        }
    }
}

/// QHY SDK error codes (from qhyccdstruct.h)
/// These error codes are returned by QHYCCD SDK functions.
#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
enum QhyError {
    Success = 0,
    Error = 0xFFFFFFFF,
    ReadDirectly = 0x2001,
    ReadOpenMem = 0x2002,
    ReadError = 0x2003,
    InitResource = 0x0001,
    ReleaseResource = 0x0002,
    InitCamera = 0x0003,
    CloseCamera = 0x0004,
    InitClass = 0x0005,
    SetFWError = 0x0006,
    SetHDR = 0x0007,
    GetMemLength = 0x0008,
}

/// Check QHY error and convert to NativeError with detailed error mapping
fn check_qhy_error(code: c_uint, operation: &str) -> Result<(), NativeError> {
    match code {
        0 => Ok(()), // QHYCCD_SUCCESS

        // Initialization errors
        0x0001 => Err(NativeError::SdkError(format!(
            "{}: Failed to initialize QHYCCD resources - SDK may not be properly installed",
            operation
        ))),
        0x0002 => Err(NativeError::SdkError(format!(
            "{}: Failed to release QHYCCD resources",
            operation
        ))),
        0x0003 => Err(NativeError::SdkError(format!(
            "{}: Failed to initialize camera - check USB connection",
            operation
        ))),
        0x0004 => Err(NativeError::Disconnected),
        0x0005 => Err(NativeError::SdkError(format!(
            "{}: Failed to initialize camera class",
            operation
        ))),
        0x0006 => Err(NativeError::SdkError(format!(
            "{}: Filter wheel operation failed",
            operation
        ))),
        0x0007 => Err(NativeError::SdkError(format!(
            "{}: HDR mode setting failed",
            operation
        ))),
        0x0008 => Err(NativeError::SdkError(format!(
            "{}: Failed to get memory length for image buffer",
            operation
        ))),

        // Read errors
        0x2001 => Err(NativeError::SdkError(format!(
            "{}: Direct read failed",
            operation
        ))),
        0x2002 => Err(NativeError::SdkError(format!(
            "{}: Memory open read failed",
            operation
        ))),
        0x2003 => Err(NativeError::SdkError(format!(
            "{}: Read operation failed - check USB connection",
            operation
        ))),

        // Timeout (common error)
        11 => Err(NativeError::Timeout(format!(
            "{}: Operation timed out - exposure may be in progress or camera unresponsive",
            operation
        ))),

        // Generic error (0xFFFFFFFF)
        0xFFFFFFFF => Err(NativeError::SdkError(format!(
            "{}: General error - camera may be in use by another application or disconnected",
            operation
        ))),

        // Unknown error
        _ => Err(NativeError::SdkError(format!(
            "{}: Unknown QHY error code 0x{:X}",
            operation, code
        ))),
    }
}

// =============================================================================
// QHY CAMERA IMPLEMENTATION
// =============================================================================

/// QHY Camera implementation
#[derive(Debug)]
pub struct QhyCamera {
    camera_id: String,
    device_id: String,
    handle: Option<QhyCamHandle>,
    connected: bool,

    // Camera info
    chip_width: f64,
    chip_height: f64,
    image_width: u32,
    image_height: u32,
    pixel_width: f64,
    pixel_height: f64,
    bits_per_pixel: u32,

    // Current settings
    current_bin: i32,
    current_gain: i32,
    current_offset: i32,

    // Exposure tracking for timeout handling
    current_exposure_time: f64,

    // Capabilities
    has_cooler: bool,
    has_st4_port: bool,
    is_color: bool,
    bayer_pattern: Option<BayerPattern>,

    // Why: QHY SDK has no register to read the cooler enable state back —
    // CONTROL_COOLER is the target-temperature setpoint, not an on/off flag.
    // Track locally (mirrors Atik pattern) so get_status reflects the last
    // set_cooler call instead of hardcoding `false` (audit §5.7).
    cooler_on: bool,
    cooler_target_c: Option<f64>,
}

unsafe impl Send for QhyCamera {}
unsafe impl Sync for QhyCamera {}

impl QhyCamera {
    pub fn new(camera_id: String) -> Self {
        let device_id = format!("native:qhy:{}", camera_id);
        Self {
            camera_id,
            device_id,
            handle: None,
            connected: false,
            chip_width: 0.0,
            chip_height: 0.0,
            image_width: 0,
            image_height: 0,
            pixel_width: 0.0,
            pixel_height: 0.0,
            bits_per_pixel: 16,
            current_bin: 1,
            current_gain: 0,
            current_offset: 0,
            current_exposure_time: 0.0,
            has_cooler: false,
            has_st4_port: false,
            is_color: false,
            bayer_pattern: None,
            cooler_on: false,
            cooler_target_c: None,
        }
    }

    /// Load camera chip info from SDK
    fn load_camera_info(&mut self) -> Result<(), NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let mut chip_w: c_double = 0.0;
        let mut chip_h: c_double = 0.0;
        let mut img_w: c_uint = 0;
        let mut img_h: c_uint = 0;
        let mut pixel_w: c_double = 0.0;
        let mut pixel_h: c_double = 0.0;
        let mut bpp: c_uint = 0;

        let result = unsafe {
            (sdk.get_qhyccd_chip_info)(
                handle,
                &mut chip_w,
                &mut chip_h,
                &mut img_w,
                &mut img_h,
                &mut pixel_w,
                &mut pixel_h,
                &mut bpp,
            )
        };
        check_qhy_error(result, "GetQHYCCDChipInfo")?;

        self.chip_width = chip_w;
        self.chip_height = chip_h;
        self.image_width = img_w;
        self.image_height = img_h;
        self.pixel_width = pixel_w;
        self.pixel_height = pixel_h;
        self.bits_per_pixel = bpp;

        // Check capabilities
        self.has_cooler = unsafe {
            (sdk.is_qhyccd_control_available)(handle, QhyControl::CONTROL_COOLER as c_int)
        } == 0;
        self.has_st4_port = unsafe {
            (sdk.is_qhyccd_control_available)(handle, QhyControl::CONTROL_ST4PORT as c_int)
        } == 0;
        self.is_color =
            unsafe { (sdk.is_qhyccd_control_available)(handle, QhyControl::CAM_IS_COLOR as c_int) }
                == 0;

        // Detect bayer pattern for color cameras
        if self.is_color {
            let bayer_val =
                unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::CAM_COLOR as c_int) } as i32;
            self.bayer_pattern = match bayer_val {
                1 => Some(BayerPattern::Rggb),
                2 => Some(BayerPattern::Grbg),
                3 => Some(BayerPattern::Gbrg),
                4 => Some(BayerPattern::Bggr),
                _ => None,
            };
        }

        Ok(())
    }

    /// Get a control value (mutex protected)
    async fn get_control_async(&self, control: QhyControl) -> Result<f64, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;
        Ok(unsafe { (sdk.get_qhyccd_param)(handle, control as c_int) })
    }

    /// Get a control value (synchronous - caller must hold mutex)
    fn get_control(&self, control: QhyControl) -> Result<f64, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;
        Ok(unsafe { (sdk.get_qhyccd_param)(handle, control as c_int) })
    }

    /// Set a control value (mutex protected)
    async fn set_control_async(
        &mut self,
        control: QhyControl,
        value: f64,
    ) -> Result<(), NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;
        let result = unsafe { (sdk.set_qhyccd_param)(handle, control as c_int, value) };
        check_qhy_error(result, "SetQHYCCDParam")
    }

    /// Set a control value (synchronous - caller must hold mutex)
    fn set_control(&mut self, control: QhyControl, value: f64) -> Result<(), NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;
        let result = unsafe { (sdk.set_qhyccd_param)(handle, control as c_int, value) };
        check_qhy_error(result, "SetQHYCCDParam")
    }

    /// Get the min/max/step range for a control (mutex protected)
    async fn get_control_range_async(
        &self,
        control: QhyControl,
    ) -> Result<(f64, f64, f64), NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let mut min_val: c_double = 0.0;
        let mut max_val: c_double = 0.0;
        let mut step: c_double = 0.0;

        let result = unsafe {
            (sdk.get_qhyccd_param_min_max_step)(
                handle,
                control as c_int,
                &mut min_val,
                &mut max_val,
                &mut step,
            )
        };
        check_qhy_error(result, "GetQHYCCDParamMinMaxStep")?;

        Ok((min_val, max_val, step))
    }

    /// Get the min/max/step range for a control (synchronous - caller must hold mutex)
    fn get_control_range(&self, control: QhyControl) -> Result<(f64, f64, f64), NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let mut min_val: c_double = 0.0;
        let mut max_val: c_double = 0.0;
        let mut step: c_double = 0.0;

        let result = unsafe {
            (sdk.get_qhyccd_param_min_max_step)(
                handle,
                control as c_int,
                &mut min_val,
                &mut max_val,
                &mut step,
            )
        };
        check_qhy_error(result, "GetQHYCCDParamMinMaxStep")?;

        Ok((min_val, max_val, step))
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
            self.current_exposure_time,
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
                tracing::error!("QHY image download timed out after {:?}", timeout_duration);
                Err(NativeError::download_timeout(
                    timeout_duration,
                    self.image_width,
                    self.image_height,
                ))
            }
        }
    }
}

#[async_trait]
impl NativeDevice for QhyCamera {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.camera_id
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Qhy
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        // Ensure SDK is initialized
        QhySdk::ensure_initialized()?;

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = qhy_mutex().lock().await;

        // Open the camera
        let id_cstring = CString::new(self.camera_id.clone())
            .map_err(|_| NativeError::InvalidDevice("Invalid camera ID".to_string()))?;

        let handle = unsafe { (sdk.open_qhyccd)(id_cstring.as_ptr()) };
        if handle.is_null() {
            return Err(NativeError::InvalidDevice(
                "Failed to open QHY camera".to_string(),
            ));
        }

        // Set single frame mode
        let result = unsafe { (sdk.set_qhyccd_stream_mode)(handle, 0) }; // 0 = single frame
        if result != 0 {
            unsafe { (sdk.close_qhyccd)(handle) };
            return Err(NativeError::SdkError(format!(
                "Failed to set stream mode: {}",
                result
            )));
        }

        // Initialize the camera
        let result = unsafe { (sdk.init_qhyccd)(handle) };
        if result != 0 {
            unsafe { (sdk.close_qhyccd)(handle) };
            return Err(NativeError::SdkError(format!(
                "Failed to init camera: {}",
                result
            )));
        }

        self.handle = Some(handle);

        // Load camera info (mutex is already held)
        self.load_camera_info()?;

        // Set default settings
        let _ = unsafe { (sdk.set_qhyccd_bits_mode)(handle, 16) }; // 16-bit mode
        let _ = unsafe { (sdk.set_qhyccd_binmode)(handle, 1, 1) }; // 1x1 binning
        let _ = unsafe {
            (sdk.set_qhyccd_resolution)(handle, 0, 0, self.image_width, self.image_height)
        };

        self.connected = true;
        tracing::info!("Connected to QHY camera: {}", self.camera_id);
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        // Acquire mutex first to avoid Send issues with raw pointer
        let _lock = qhy_mutex().lock().await;
        if let Some(handle) = self.handle.take() {
            if let Some(sdk) = QhySdk::get() {
                let result = unsafe { (sdk.close_qhyccd)(handle) };
                check_qhy_error(result, "CloseQHYCCD")?;
            }
        }
        self.connected = false;
        tracing::info!("Disconnected from QHY camera: {}", self.camera_id);
        Ok(())
    }
}

#[async_trait]
impl NativeCamera for QhyCamera {
    fn capabilities(&self) -> CameraCapabilities {
        CameraCapabilities {
            can_cool: self.has_cooler,
            can_set_gain: true,
            can_set_offset: true,
            can_set_binning: true,
            can_subframe: true,
            has_shutter: false, // Would need to check MECHANICAL_SHUTTER control
            has_guider_port: self.has_st4_port,
            max_bin_x: 4,
            max_bin_y: 4,
            supports_readout_modes: true, // QHY supports readout modes
        }
    }

    async fn get_status(&self) -> Result<CameraStatus, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Use async versions with mutex protection
        let temp = self
            .get_control_async(QhyControl::CONTROL_CURTEMP)
            .await
            .ok();
        let cooler_power = if self.has_cooler {
            self.get_control_async(QhyControl::CONTROL_CURPWM)
                .await
                .ok()
        } else {
            None
        };

        Ok(CameraStatus {
            state: CameraState::Idle, // QHY doesn't have a simple exposure status query
            sensor_temp: temp,
            // Why: tracked locally because QHY SDK has no register to read
            // back cooler enable / target setpoint (audit §5.7).
            target_temp: self.cooler_target_c,
            cooler_on: self.cooler_on,
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

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        // Set exposure time (in microseconds) - use sync version since we hold mutex
        let exposure_us = params.duration_secs * 1_000_000.0;
        self.set_control(QhyControl::CONTROL_EXPOSURE, exposure_us)?;

        // Track exposure time for timeout handling
        self.current_exposure_time = params.duration_secs;

        // Set gain
        if let Some(gain) = params.gain {
            self.set_control(QhyControl::CONTROL_GAIN, gain as f64)?;
            self.current_gain = gain;
        }

        // Set offset if provided
        if let Some(offset) = params.offset {
            self.set_control(QhyControl::CONTROL_OFFSET, offset as f64)?;
            self.current_offset = offset;
        }

        // Start exposure
        let result = unsafe { (sdk.exp_single_frame)(handle) };
        check_qhy_error(result, "ExpQHYCCDSingleFrame")?;

        tracing::info!("Started {}s exposure on QHY camera", params.duration_secs);
        Ok(())
    }

    async fn abort_exposure(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let result = unsafe { (sdk.cancel_qhyccd_exposing_and_readout)(handle) };
        check_qhy_error(result, "CancelExposure")?;

        tracing::info!("Aborted exposure");
        Ok(())
    }

    async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
        // QHY SDK uses blocking exposure with GetQHYCCDSingleFrame
        // This is called after the exposure completes
        Ok(true)
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        // Get required buffer size
        let buffer_len = unsafe { (sdk.get_qhyccd_memory_length)(handle) } as usize;
        // Use pooled buffer for efficient memory reuse
        let mut pooled_buffer = global_u8_pool().get_buffer(buffer_len);
        pooled_buffer.resize(buffer_len);

        let mut width: c_uint = 0;
        let mut height: c_uint = 0;
        let mut bpp: c_uint = 0;
        let mut channels: c_uint = 0;

        let result = unsafe {
            (sdk.get_qhyccd_single_frame)(
                handle,
                &mut width,
                &mut height,
                &mut bpp,
                &mut channels,
                pooled_buffer.as_mut_ptr(),
            )
        };
        check_qhy_error(result, "GetQHYCCDSingleFrame")?;

        // Trim buffer to actual size
        let actual_size = (width * height * (bpp / 8) * channels.max(1)) as usize;
        pooled_buffer.truncate(actual_size);

        // Why: GetQHYCCDSingleFrame writes raw sensor bytes into the SDK-owned byte buffer
        // we provided. QHY documents the on-wire framing as little-endian regardless of host
        // architecture, and the pooled buffer is *not* guaranteed to be u16-aligned (we
        // hand the SDK a u8 buffer from a pool). We decode each pixel via from_le_bytes so
        // alignment and host endianness are both irrelevant — only SDK length matters,
        // and we already truncated the buffer to actual_size = width*height*(bpp/8)*channels.
        let data: Vec<u16> = if bpp == 16 {
            pooled_buffer
                .chunks_exact(2)
                .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                .collect()
        } else {
            // 8-bit to 16-bit scaling
            pooled_buffer.iter().map(|&x| (x as u16) * 256).collect()
        };

        // Get temperature and vendor features while still holding mutex
        let temperature = self.get_control(QhyControl::CONTROL_CURTEMP).ok();
        let vendor_data = {
            let mut features = VendorFeatures::default();
            if let Ok(usb_bw) = self.get_control(QhyControl::CONTROL_USBTRAFFIC) {
                features.usb_bandwidth = Some(usb_bw);
            }
            if let Ok(humidity) = self.get_control(QhyControl::CAM_HUMIDITY) {
                if (0.0..=100.0).contains(&humidity) {
                    features.sensor_chamber_humidity = Some(humidity);
                }
            }
            if let Ok(pressure) = self.get_control(QhyControl::CAM_PRESSURE) {
                if pressure > 0.0 {
                    features.sensor_chamber_pressure = Some(pressure);
                }
            }
            features
        };

        tracing::info!(
            "Downloaded {}x{} image ({} bytes, {} bpp)",
            width,
            height,
            actual_size,
            bpp
        );

        Ok(ImageData {
            width,
            height,
            data,
            bits_per_pixel: bpp,
            bayer_pattern: self.bayer_pattern,
            metadata: ImageMetadata {
                exposure_time: 0.0, // Need to track this
                gain: self.current_gain,
                offset: self.current_offset,
                bin_x: self.current_bin,
                bin_y: self.current_bin,
                temperature,
                timestamp: chrono::Utc::now(),
                subframe: None, // Need to track this
                readout_mode: None,
                vendor_data,
            },
        })
    }

    async fn set_cooler(&mut self, enabled: bool, target_temp: f64) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.has_cooler {
            return Err(NativeError::NotSupported);
        }

        // Use async versions with mutex protection
        if enabled {
            self.set_control_async(QhyControl::CONTROL_MANULPWM, 0.0)
                .await?;
            self.set_control_async(QhyControl::CONTROL_COOLER, target_temp)
                .await?;
        } else {
            self.set_control_async(QhyControl::CONTROL_MANULPWM, 0.0)
                .await?;
            self.set_control_async(QhyControl::CONTROL_CURPWM, 0.0)
                .await?;
        }

        // Why: only commit tracked state after SDK calls succeed so a failed
        // setpoint write leaves the previous state intact (no silent fallback).
        // QHY SDK has no register to read cooler enable back — CONTROL_COOLER
        // is the target setpoint, not an on/off flag — so we mirror locally.
        self.cooler_on = enabled;
        self.cooler_target_c = if enabled { Some(target_temp) } else { None };

        Ok(())
    }

    async fn get_temperature(&self) -> Result<f64, NativeError> {
        self.get_control_async(QhyControl::CONTROL_CURTEMP).await
    }

    async fn get_cooler_power(&self) -> Result<f64, NativeError> {
        if !self.has_cooler {
            return Err(NativeError::NotSupported);
        }
        self.get_control_async(QhyControl::CONTROL_CURPWM).await
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        self.set_control_async(QhyControl::CONTROL_GAIN, gain as f64)
            .await?;
        self.current_gain = gain;
        Ok(())
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        Ok(self.get_control_async(QhyControl::CONTROL_GAIN).await? as i32)
    }

    async fn set_offset(&mut self, offset: i32) -> Result<(), NativeError> {
        self.set_control_async(QhyControl::CONTROL_OFFSET, offset as f64)
            .await?;
        self.current_offset = offset;
        Ok(())
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        Ok(self.get_control_async(QhyControl::CONTROL_OFFSET).await? as i32)
    }

    async fn set_binning(&mut self, bin_x: i32, bin_y: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let bin = bin_x.max(bin_y) as c_uint;
        let result = unsafe { (sdk.set_qhyccd_binmode)(handle, bin, bin) };
        check_qhy_error(result, "SetQHYCCDBinMode")?;

        // Update resolution for new binning
        let new_width = self.image_width / bin;
        let new_height = self.image_height / bin;
        let result = unsafe { (sdk.set_qhyccd_resolution)(handle, 0, 0, new_width, new_height) };
        check_qhy_error(result, "SetQHYCCDResolution")?;

        self.current_bin = bin as i32;
        Ok(())
    }

    async fn get_binning(&self) -> Result<(i32, i32), NativeError> {
        Ok((self.current_bin, self.current_bin))
    }

    async fn set_subframe(&mut self, subframe: Option<SubFrame>) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let (x, y, width, height) = if let Some(sf) = subframe {
            (sf.start_x, sf.start_y, sf.width, sf.height)
        } else {
            (
                0,
                0,
                self.image_width / self.current_bin as u32,
                self.image_height / self.current_bin as u32,
            )
        };

        let result = unsafe { (sdk.set_qhyccd_resolution)(handle, x, y, width, height) };
        check_qhy_error(result, "SetQHYCCDResolution")
    }

    fn get_sensor_info(&self) -> SensorInfo {
        SensorInfo {
            width: self.image_width,
            height: self.image_height,
            pixel_size_x: self.pixel_width,
            pixel_size_y: self.pixel_height,
            max_adu: (1u32 << self.bits_per_pixel) - 1,
            bit_depth: self.bits_per_pixel,
            color: self.is_color,
            bayer_pattern: self.bayer_pattern,
        }
    }

    async fn get_readout_modes(&self) -> Result<Vec<ReadoutMode>, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let mut num_modes: c_uint = 0;
        let result = unsafe { (sdk.get_qhyccd_number_of_read_modes)(handle, &mut num_modes) };
        check_qhy_error(result, "GetQHYCCDNumberOfReadModes")?;

        let mut modes = Vec::new();
        for i in 0..num_modes {
            let mut name_buf = [0i8; 256];
            let result =
                unsafe { (sdk.get_qhyccd_read_mode_name)(handle, i, name_buf.as_mut_ptr()) };
            if result == 0 {
                let name = unsafe { CStr::from_ptr(name_buf.as_ptr()) }
                    .to_string_lossy()
                    .to_string();
                modes.push(ReadoutMode {
                    index: i as i32,
                    name,
                    description: "QHY Readout Mode".to_string(),
                    gain_min: None,
                    gain_max: None,
                    offset_min: None,
                    offset_max: None,
                });
            }
        }

        Ok(modes)
    }

    async fn set_readout_mode(&mut self, mode: &ReadoutMode) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex before extracting handle to avoid Send issues
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let result = unsafe { (sdk.set_qhyccd_read_mode)(handle, mode.index as c_uint) };
        check_qhy_error(result, "SetQHYCCDReadMode")
    }

    async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
        let mut features = VendorFeatures::default();

        // QHY-specific features - use async versions with mutex protection
        if let Ok(usb_bw) = self.get_control_async(QhyControl::CONTROL_USBTRAFFIC).await {
            features.usb_bandwidth = Some(usb_bw);
        }

        // QHY-specific: Sensor chamber humidity and pressure (if available)
        if let Ok(humidity) = self.get_control_async(QhyControl::CAM_HUMIDITY).await {
            if (0.0..=100.0).contains(&humidity) {
                features.sensor_chamber_humidity = Some(humidity);
            }
        }

        if let Ok(pressure) = self.get_control_async(QhyControl::CAM_PRESSURE).await {
            if pressure > 0.0 {
                features.sensor_chamber_pressure = Some(pressure);
            }
        }

        Ok(features)
    }

    async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let (min, max, _step) = self
            .get_control_range_async(QhyControl::CONTROL_GAIN)
            .await?;
        Ok((min as i32, max as i32))
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let (min, max, _step) = self
            .get_control_range_async(QhyControl::CONTROL_OFFSET)
            .await?;
        Ok((min as i32, max as i32))
    }
}

// =============================================================================
// QHY CAMERA DISCOVERY
// =============================================================================

/// QHY camera discovery info
pub struct QhyCameraInfo {
    /// Full camera ID string (e.g., "QHY183M-123456789")
    pub camera_id: String,
    /// Model name parsed from ID (e.g., "QHY183M")
    pub name: String,
    /// Serial number parsed from ID (e.g., "123456789")
    pub serial_number: Option<String>,
}

impl QhyCameraInfo {
    /// Parse a QHY camera ID string into model name and serial number
    /// Format: "ModelName-SerialNumber" e.g., "QHY183M-123456789"
    fn parse_id(id: &str) -> (String, Option<String>) {
        if let Some(dash_pos) = id.rfind('-') {
            let model = id[..dash_pos].to_string();
            let serial = id[dash_pos + 1..].to_string();
            // Only treat as serial if it looks like a number/serial
            if !serial.is_empty() && serial.chars().all(|c| c.is_alphanumeric()) {
                return (model, Some(serial));
            }
        }
        // No serial number found, use full ID as name
        (id.to_string(), None)
    }
}

/// Check if QHY SDK is available
pub fn is_sdk_available() -> bool {
    QhySdk::get().is_some()
}

/// Internal function to perform the actual SDK discovery.
/// This is separated out to allow catch_unwind wrapping.
fn discover_devices_internal(sdk: &QhySdk) -> Result<Vec<QhyCameraInfo>, NativeError> {
    // Scan for cameras
    let num_cameras = unsafe { (sdk.scan_qhyccd)() };
    tracing::info!("Found {} QHY cameras", num_cameras);

    let mut cameras = Vec::new();
    for i in 0..num_cameras {
        let mut id_buf = [0i8; 256];
        let result = unsafe { (sdk.get_qhyccd_id)(i, id_buf.as_mut_ptr()) };

        if result == 0 {
            let id = unsafe { CStr::from_ptr(id_buf.as_ptr()) }
                .to_string_lossy()
                .to_string();

            // Parse model name and serial number from ID
            let (name, serial_number) = QhyCameraInfo::parse_id(&id);

            cameras.push(QhyCameraInfo {
                camera_id: id,
                name,
                serial_number,
            });
        }
    }

    Ok(cameras)
}

/// Discover QHY cameras with safety measures.
///
/// This function includes several safety measures to handle potential SDK issues:
///
/// 1. **Enable/Disable Check**: Returns empty if discovery is disabled via
///    `set_qhy_discovery_enabled(false)`
/// 2. **Panic Protection**: SDK calls are wrapped in `catch_unwind` to prevent
///    crashes from propagating
/// 3. **Timeout**: Discovery has a configurable timeout (default 10s, can be
///    overridden via quirks database)
/// 4. **Mutex Serialization**: All SDK calls are serialized via `qhy_mutex()`
///
/// # Returns
/// * `Ok(cameras)` - List of discovered cameras (may be empty)
/// * `Err(NativeError::SdkNotLoaded)` - SDK not available or discovery disabled
/// * `Err(NativeError::Timeout)` - Discovery timed out
/// * `Err(NativeError::SdkError)` - SDK panicked during discovery
pub async fn discover_devices() -> Result<Vec<QhyCameraInfo>, NativeError> {
    let config = get_discovery_config();

    // Check if discovery is enabled
    if !config.enabled {
        tracing::debug!("QHY discovery is disabled, returning empty list");
        return Ok(Vec::new());
    }

    // Ensure SDK is initialized first (before timeout starts)
    QhySdk::ensure_initialized()?;

    // Verify SDK is available before proceeding
    if QhySdk::get().is_none() {
        return Ok(Vec::new());
    }

    // Acquire mutex for SDK discovery operations
    let _lock = qhy_mutex().lock().await;

    // Create the timeout duration from config
    let timeout_duration = Duration::from_millis(config.timeout_ms);

    // Perform discovery with timeout
    let catch_panics = config.catch_panics;
    let discovery_future = async move {
        if catch_panics {
            // Wrap SDK calls in catch_unwind for crash protection
            // We use spawn_blocking because catch_unwind works best in sync context
            // We get the SDK inside the blocking task to avoid Send issues with raw pointers
            tokio::task::spawn_blocking(move || {
                // Get SDK inside the blocking task - this is safe because SDK is 'static
                let sdk = match QhySdk::get() {
                    Some(s) => s,
                    None => return Err(NativeError::SdkNotLoaded),
                };
                catch_unwind(AssertUnwindSafe(|| discover_devices_internal(sdk)))
                    .map_err(|panic_info| {
                        let panic_msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                            s.to_string()
                        } else if let Some(s) = panic_info.downcast_ref::<String>() {
                            s.clone()
                        } else {
                            "Unknown panic".to_string()
                        };
                        tracing::error!("QHY SDK panicked during discovery: {}", panic_msg);
                        NativeError::SdkError(format!(
                            "QHY SDK crashed during discovery: {}. Discovery has been disabled. \
                             Re-enable with api_set_qhy_discovery_enabled(true) if you want to try again.",
                            panic_msg
                        ))
                    })?
            })
            .await
            .map_err(|e| {
                NativeError::SdkError(format!("QHY discovery task failed: {:?}", e))
            })?
        } else {
            // No panic protection, just call directly (SDK is 'static, so we can get it again)
            let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
            discover_devices_internal(sdk)
        }
    };

    // Apply timeout
    match tokio::time::timeout(timeout_duration, discovery_future).await {
        Ok(result) => {
            match &result {
                Ok(cameras) => {
                    tracing::debug!(
                        "QHY discovery completed successfully, found {} cameras",
                        cameras.len()
                    );
                }
                Err(e) => {
                    tracing::warn!("QHY discovery failed: {}", e);
                    // On failure, disable discovery to prevent repeated crashes
                    set_qhy_discovery_enabled(false);
                }
            }
            result
        }
        Err(_) => {
            tracing::error!(
                "QHY discovery timed out after {}ms. Disabling QHY discovery.",
                config.timeout_ms
            );
            // Disable discovery to prevent repeated timeouts
            set_qhy_discovery_enabled(false);
            Err(NativeError::Timeout(format!(
                "QHY discovery timed out after {}ms. Discovery has been disabled. \
                 Re-enable with api_set_qhy_discovery_enabled(true) if you want to try again.",
                config.timeout_ms
            )))
        }
    }
}

// =============================================================================
// QHY FILTER WHEEL (CFW) IMPLEMENTATION
// =============================================================================

/// QHY CFW discovery info
pub struct QhyFilterWheelInfo {
    /// Camera ID that the filter wheel is attached to
    pub camera_id: String,
    /// Display name
    pub name: String,
    /// Number of filter slots
    pub slot_count: i32,
}

/// QHY Filter Wheel implementation
/// Note: QHY CFW is controlled through the camera handle
#[derive(Debug)]
pub struct QhyFilterWheel {
    camera_id: String,
    device_id: String,
    name: String,
    handle: Option<QhyCamHandle>,
    connected: bool,
    slot_count: i32,
    filter_names: Vec<String>,
}

unsafe impl Send for QhyFilterWheel {}
unsafe impl Sync for QhyFilterWheel {}

impl QhyFilterWheel {
    /// Create a new QHY filter wheel instance
    pub fn new(camera_id: String) -> Self {
        let (model_name, _) = QhyCameraInfo::parse_id(&camera_id);
        let name = format!("{} CFW", model_name);
        let device_id = format!("native:qhy_cfw:{}", camera_id);
        Self {
            camera_id,
            device_id,
            name,
            handle: None,
            connected: false,
            slot_count: 0,
            filter_names: Vec::new(),
        }
    }

    /// Check if CFW is available (must be called after connecting to camera)
    fn check_cfw_available(&self) -> Result<bool, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let result = unsafe { (sdk.is_qhyccd_cfw_plugged)(handle) };
        Ok(result == 0) // QHYCCD_SUCCESS = 0
    }

    /// Get number of filter slots
    fn get_slot_count(&self) -> Result<i32, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let count =
            unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::CONTROL_CFWSLOTSNUM as c_int) };

        Ok(count as i32)
    }

    /// Get current position (0-indexed)
    fn get_current_position(&self) -> Result<i32, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        // QHY returns position as ASCII value (48 = '0', 49 = '1', etc.)
        let pos = unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::CONTROL_CFWPORT as c_int) };

        // Convert from ASCII to 0-indexed position
        let position = (pos as i32) - 48;
        Ok(position.max(0)) // Ensure non-negative
    }

    /// Set position (0-indexed)
    fn set_current_position(&self, position: i32) -> Result<(), NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        // QHY uses ASCII encoding (48 = '0', 49 = '1', etc.)
        let ascii_position = (position + 48) as f64;

        let result = unsafe {
            (sdk.set_qhyccd_param)(handle, QhyControl::CONTROL_CFWPORT as c_int, ascii_position)
        };

        check_qhy_error(result, "SetCFWPosition")
    }
}

#[async_trait]
impl NativeDevice for QhyFilterWheel {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Qhy
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        if self.connected {
            return Ok(());
        }

        QhySdk::ensure_initialized()?;
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = qhy_mutex().lock().await;

        // Open the camera to access CFW
        let camera_id_cstr = CString::new(self.camera_id.clone())
            .map_err(|_| NativeError::InvalidParameter("Invalid camera ID".into()))?;

        let handle = unsafe { (sdk.open_qhyccd)(camera_id_cstr.as_ptr()) };
        if handle.is_null() {
            return Err(NativeError::SdkError(
                "Failed to open QHY camera for CFW".into(),
            ));
        }

        self.handle = Some(handle);

        // Set stream mode and init (required for CFW access)
        unsafe {
            (sdk.set_qhyccd_stream_mode)(handle, 0); // Single frame mode
            let init_result = (sdk.init_qhyccd)(handle);
            if init_result != 0 {
                (sdk.close_qhyccd)(handle);
                self.handle = None;
                return Err(NativeError::SdkError(
                    "Failed to initialize QHY camera for CFW".into(),
                ));
            }
        }

        // Check if CFW is available (mutex already held)
        if !self.check_cfw_available()? {
            unsafe { (sdk.close_qhyccd)(handle) };
            self.handle = None;
            return Err(NativeError::DeviceNotFound(
                "No CFW detected on this QHY camera".into(),
            ));
        }

        // Get slot count (mutex already held)
        self.slot_count = self.get_slot_count()?;
        if self.slot_count <= 0 {
            self.slot_count = 5; // Default to 5 slots if detection fails
        }

        // Initialize filter names with defaults
        self.filter_names = (0..self.slot_count)
            .map(|i| format!("Filter {}", i + 1))
            .collect();

        self.connected = true;
        tracing::info!("Connected to QHY CFW with {} slots", self.slot_count);

        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Ok(());
        }

        // Acquire mutex first to avoid Send issues with raw pointer
        let _lock = qhy_mutex().lock().await;
        if let Some(handle) = self.handle.take() {
            if let Some(sdk) = QhySdk::get() {
                unsafe { (sdk.close_qhyccd)(handle) };
            }
        }

        self.connected = false;
        tracing::info!("Disconnected from QHY CFW");

        Ok(())
    }
}

#[async_trait]
impl NativeFilterWheel for QhyFilterWheel {
    fn get_filter_count(&self) -> i32 {
        self.slot_count
    }

    async fn get_position(&self) -> Result<i32, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        let _lock = qhy_mutex().lock().await;
        self.get_current_position()
    }

    async fn move_to_position(&mut self, position: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if position < 0 || position >= self.slot_count {
            return Err(NativeError::InvalidParameter(format!(
                "Position {} out of range (0-{})",
                position,
                self.slot_count - 1
            )));
        }

        tracing::info!("Moving QHY CFW to position {}", position);
        {
            let _lock = qhy_mutex().lock().await;
            self.set_current_position(position)?;
        }

        // Wait for filter wheel to settle (QHY CFW doesn't report moving status well)
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        Ok(())
    }

    async fn is_moving(&self) -> Result<bool, NativeError> {
        // QHY CFW doesn't have a reliable "is moving" indicator
        // We'll just return false as moves are typically fast
        Ok(false)
    }

    async fn get_filter_names(&self) -> Result<Vec<String>, NativeError> {
        Ok(self.filter_names.clone())
    }

    async fn set_filter_name(&mut self, position: i32, name: String) -> Result<(), NativeError> {
        if position < 0 || position >= self.slot_count {
            return Err(NativeError::InvalidParameter(format!(
                "Position {} out of range (0-{})",
                position,
                self.slot_count - 1
            )));
        }
        self.filter_names[position as usize] = name;
        Ok(())
    }
}

/// Internal function to perform the actual CFW discovery.
fn discover_filter_wheels_internal(sdk: &QhySdk) -> Result<Vec<QhyFilterWheelInfo>, NativeError> {
    // Scan for cameras
    let num_cameras = unsafe { (sdk.scan_qhyccd)() };

    let mut filter_wheels = Vec::new();

    for i in 0..num_cameras {
        let mut id_buf = [0i8; 256];
        let result = unsafe { (sdk.get_qhyccd_id)(i, id_buf.as_mut_ptr()) };

        if result != 0 {
            continue;
        }

        let camera_id = unsafe { CStr::from_ptr(id_buf.as_ptr()) }
            .to_string_lossy()
            .to_string();

        // Open camera temporarily to check for CFW
        let camera_id_cstr = match CString::new(camera_id.clone()) {
            Ok(s) => s,
            Err(_) => continue,
        };

        let handle = unsafe { (sdk.open_qhyccd)(camera_id_cstr.as_ptr()) };
        if handle.is_null() {
            continue;
        }

        // Initialize camera to check CFW
        unsafe {
            (sdk.set_qhyccd_stream_mode)(handle, 0);
            if (sdk.init_qhyccd)(handle) != 0 {
                (sdk.close_qhyccd)(handle);
                continue;
            }
        }

        // Check if CFW is plugged in
        let cfw_result = unsafe { (sdk.is_qhyccd_cfw_plugged)(handle) };

        if cfw_result == 0 {
            // CFW is available
            let slot_count = unsafe {
                (sdk.get_qhyccd_param)(handle, QhyControl::CONTROL_CFWSLOTSNUM as c_int) as i32
            };

            let slot_count = if slot_count > 0 { slot_count } else { 5 };

            let (model_name, _) = QhyCameraInfo::parse_id(&camera_id);

            filter_wheels.push(QhyFilterWheelInfo {
                camera_id: camera_id.clone(),
                name: format!("{} CFW", model_name),
                slot_count,
            });

            tracing::info!(
                "Found QHY CFW on camera {} with {} slots",
                camera_id,
                slot_count
            );
        }

        // Close camera
        unsafe { (sdk.close_qhyccd)(handle) };
    }

    Ok(filter_wheels)
}

/// Discover QHY filter wheels (CFW attached to cameras) with safety measures.
///
/// Uses the same safety measures as `discover_devices()`:
/// - Enable/disable check
/// - Panic protection via catch_unwind
/// - Timeout from quirks database
/// - Mutex serialization
pub async fn discover_filter_wheels() -> Result<Vec<QhyFilterWheelInfo>, NativeError> {
    let config = get_discovery_config();

    // Check if discovery is enabled
    if !config.enabled {
        tracing::debug!("QHY discovery is disabled, returning empty filter wheel list");
        return Ok(Vec::new());
    }

    // Ensure SDK is initialized
    QhySdk::ensure_initialized()?;

    // Verify SDK is available before proceeding
    if QhySdk::get().is_none() {
        return Ok(Vec::new());
    }

    // Acquire mutex for SDK discovery operations
    let _lock = qhy_mutex().lock().await;

    // Create the timeout duration from config
    let timeout_duration = Duration::from_millis(config.timeout_ms);

    // Perform discovery with timeout
    let catch_panics = config.catch_panics;
    let discovery_future = async move {
        if catch_panics {
            // Wrap SDK calls in catch_unwind for crash protection
            // We get the SDK inside the blocking task to avoid Send issues with raw pointers
            tokio::task::spawn_blocking(move || {
                // Get SDK inside the blocking task - this is safe because SDK is 'static
                let sdk = match QhySdk::get() {
                    Some(s) => s,
                    None => return Err(NativeError::SdkNotLoaded),
                };
                catch_unwind(AssertUnwindSafe(|| discover_filter_wheels_internal(sdk))).map_err(
                    |panic_info| {
                        let panic_msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                            s.to_string()
                        } else if let Some(s) = panic_info.downcast_ref::<String>() {
                            s.clone()
                        } else {
                            "Unknown panic".to_string()
                        };
                        tracing::error!("QHY SDK panicked during CFW discovery: {}", panic_msg);
                        NativeError::SdkError(format!(
                            "QHY SDK crashed during CFW discovery: {}",
                            panic_msg
                        ))
                    },
                )?
            })
            .await
            .map_err(|e| NativeError::SdkError(format!("QHY CFW discovery task failed: {:?}", e)))?
        } else {
            // No panic protection, just call directly (SDK is 'static, so we can get it again)
            let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
            discover_filter_wheels_internal(sdk)
        }
    };

    // Apply timeout
    match tokio::time::timeout(timeout_duration, discovery_future).await {
        Ok(result) => result,
        Err(_) => {
            tracing::error!("QHY CFW discovery timed out after {}ms", config.timeout_ms);
            Err(NativeError::Timeout(format!(
                "QHY CFW discovery timed out after {}ms",
                config.timeout_ms
            )))
        }
    }
}

// =============================================================================
// TESTS
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Audit §5.7: get_status must reflect the locally-tracked cooler state
    /// after a successful set_cooler, not hardcode `cooler_on: false`.
    ///
    /// The QHY SDK is not loaded in unit tests, so we cannot drive set_cooler
    /// end-to-end through the SDK call path. Instead we exercise the read
    /// side directly: mutate the tracked fields the same way set_cooler does
    /// after a successful SDK round-trip, then assert get_status surfaces them.
    #[tokio::test]
    async fn get_status_reflects_tracked_cooler_state() {
        let mut cam = QhyCamera::new("TEST-COOLER".to_string());
        // Pretend connect/load_camera_info already succeeded.
        cam.connected = true;
        cam.has_cooler = true;

        // Baseline: never-set cooler is reported as off.
        let status = cam.get_status().await.expect("get_status should succeed");
        assert!(!status.cooler_on, "default cooler_on must be false");
        assert_eq!(status.target_temp, None, "default target_temp must be None");

        // Simulate a successful set_cooler(true, -10.0) commit.
        cam.cooler_on = true;
        cam.cooler_target_c = Some(-10.0);

        let status = cam.get_status().await.expect("get_status should succeed");
        assert!(
            status.cooler_on,
            "get_status must reflect tracked cooler_on=true (audit §5.7)"
        );
        assert_eq!(
            status.target_temp,
            Some(-10.0),
            "get_status must reflect tracked target temperature"
        );

        // Simulate a successful set_cooler(false, _) commit.
        cam.cooler_on = false;
        cam.cooler_target_c = None;

        let status = cam.get_status().await.expect("get_status should succeed");
        assert!(!status.cooler_on, "get_status must reflect cooler_on=false");
        assert_eq!(status.target_temp, None);
    }

    /// Audit §5.7 + CLAUDE.md "no silent fallbacks": if the SDK call inside
    /// set_cooler fails, the tracked state must NOT advance — otherwise the
    /// dashboard would lie that the cooler is on while the hardware is cold-off.
    #[tokio::test]
    async fn set_cooler_propagates_sdk_failure_without_mutating_state() {
        let mut cam = QhyCamera::new("TEST-NO-SDK".to_string());
        cam.connected = true;
        cam.has_cooler = true;
        // handle is None and the QHY SDK is not loaded in tests, so
        // set_control_async fails at QhySdk::get() with SdkNotLoaded.

        let result = cam.set_cooler(true, -15.0).await;
        assert!(
            result.is_err(),
            "set_cooler must propagate SDK errors, not swallow them"
        );

        // State must not have advanced.
        assert!(
            !cam.cooler_on,
            "cooler_on must remain false after a failed set_cooler"
        );
        assert_eq!(
            cam.cooler_target_c, None,
            "cooler_target_c must remain unset after a failed set_cooler"
        );
    }

    /// Guard rail: set_cooler on a disconnected camera must return
    /// NotConnected and leave tracked state alone.
    #[tokio::test]
    async fn set_cooler_rejects_disconnected_camera() {
        let mut cam = QhyCamera::new("TEST-DISCONNECTED".to_string());
        // connected stays false.

        let result = cam.set_cooler(true, -10.0).await;
        assert!(matches!(result, Err(NativeError::NotConnected)));
        assert!(!cam.cooler_on);
        assert_eq!(cam.cooler_target_c, None);
    }

    /// Guard rail: set_cooler on a camera without a cooler must return
    /// NotSupported and leave tracked state alone.
    #[tokio::test]
    async fn set_cooler_rejects_camera_without_cooler() {
        let mut cam = QhyCamera::new("TEST-NO-COOLER".to_string());
        cam.connected = true;
        // has_cooler stays false (e.g. a non-cooled QHY model).

        let result = cam.set_cooler(true, -10.0).await;
        assert!(matches!(result, Err(NativeError::NotSupported)));
        assert!(!cam.cooler_on);
        assert_eq!(cam.cooler_target_c, None);
    }
}
