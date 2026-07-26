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
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

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
type GetQhyccdSdkVersion =
    unsafe extern "C" fn(*mut c_uint, *mut c_uint, *mut c_uint, *mut c_uint) -> c_uint;

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

    // SDK metadata. Older QHY SDK builds may not export this, so keep it optional.
    get_sdk_version: Option<GetQhyccdSdkVersion>,
}

// SAFETY: QhySdk holds a libloading::Library plus function pointers. The Library is OS-loaded
// memory pinned for the program lifetime (stored in OnceLock); function pointers are POD. All
// FFI calls go through `qhy_mutex()` so the underlying SDK never sees concurrent traffic.
unsafe impl Send for QhySdk {}
// SAFETY: Same justification as `Send` — every FFI call site holds `qhy_mutex()`, so shared
// references to the function-pointer table cannot trigger concurrent SDK access.
unsafe impl Sync for QhySdk {}

static QHY_SDK: OnceLock<Option<QhySdk>> = OnceLock::new();
static SDK_INITIALIZED: OnceLock<bool> = OnceLock::new();

const QHY_VENDOR_NAME: &str = "QHY Camera";

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

fn qhy_candidate_library_paths() -> Vec<PathBuf> {
    if cfg!(target_os = "windows") {
        vec![
            PathBuf::from("qhyccd.dll"),
            PathBuf::from("C:\\Program Files\\QHYCCD\\AllInOne\\sdk\\x64\\qhyccd.dll"),
            PathBuf::from("C:\\Program Files (x86)\\QHYCCD\\AllInOne\\sdk\\qhyccd.dll"),
        ]
    } else if cfg!(target_os = "macos") {
        vec![
            PathBuf::from("libqhyccd.dylib"),
            PathBuf::from("/usr/local/lib/libqhyccd.dylib"),
            PathBuf::from("/Library/Frameworks/QHYCCD.framework/QHYCCD"),
        ]
    } else {
        crate::vendor::sdk_loader::vendor_library_candidates(
            &["libqhyccd.so", "libqhyccd.so.21"],
            &["/usr/lib/libqhyccd.so", "/usr/local/lib/libqhyccd.so"],
        )
    }
}

unsafe fn resolve_qhy_symbol<T: Copy>(
    library: &libloading::Library,
    library_path: &Path,
    symbol_name_with_nul: &'static [u8],
    symbol_name_for_log: &'static str,
) -> Result<T, crate::vendor::sdk_loader::VendorLoadError> {
    crate::vendor::sdk_loader::resolve_symbol::<T>(
        QHY_VENDOR_NAME,
        library,
        library_path,
        symbol_name_with_nul,
        symbol_name_for_log,
    )
}

fn load_qhy_sdk() -> Option<QhySdk> {
    let candidate_paths = qhy_candidate_library_paths();
    let (lib, library_path) =
        match crate::vendor::sdk_loader::open_vendor_library(QHY_VENDOR_NAME, &candidate_paths) {
            Ok(pair) => pair,
            Err(e) => {
                tracing::debug!("{}: SDK unavailable: {}", QHY_VENDOR_NAME, e);
                return None;
            }
        };

    // SAFETY: each FFI signature below mirrors qhyccd.h for the named symbol.
    // The `lib` handle is stored in QhySdk so resolved function pointers cannot
    // outlive the library that owns them.
    let sdk = unsafe {
        (|| -> Result<QhySdk, crate::vendor::sdk_loader::VendorLoadError> {
            Ok(QhySdk {
                init_sdk: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"InitQHYCCDResource\0",
                    "InitQHYCCDResource",
                )?,
                release_sdk: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"ReleaseQHYCCDResource\0",
                    "ReleaseQHYCCDResource",
                )?,
                scan_qhyccd: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"ScanQHYCCD\0",
                    "ScanQHYCCD",
                )?,
                get_qhyccd_id: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDId\0",
                    "GetQHYCCDId",
                )?,
                open_qhyccd: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"OpenQHYCCD\0",
                    "OpenQHYCCD",
                )?,
                close_qhyccd: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"CloseQHYCCD\0",
                    "CloseQHYCCD",
                )?,
                set_qhyccd_stream_mode: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"SetQHYCCDStreamMode\0",
                    "SetQHYCCDStreamMode",
                )?,
                init_qhyccd: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"InitQHYCCD\0",
                    "InitQHYCCD",
                )?,
                get_qhyccd_chip_info: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDChipInfo\0",
                    "GetQHYCCDChipInfo",
                )?,
                is_qhyccd_control_available: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"IsQHYCCDControlAvailable\0",
                    "IsQHYCCDControlAvailable",
                )?,
                get_qhyccd_effective_area: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDEffectiveArea\0",
                    "GetQHYCCDEffectiveArea",
                )?,
                set_qhyccd_param: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"SetQHYCCDParam\0",
                    "SetQHYCCDParam",
                )?,
                get_qhyccd_param: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDParam\0",
                    "GetQHYCCDParam",
                )?,
                get_qhyccd_param_min_max_step: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDParamMinMaxStep\0",
                    "GetQHYCCDParamMinMaxStep",
                )?,
                set_qhyccd_resolution: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"SetQHYCCDResolution\0",
                    "SetQHYCCDResolution",
                )?,
                set_qhyccd_binmode: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"SetQHYCCDBinMode\0",
                    "SetQHYCCDBinMode",
                )?,
                set_qhyccd_bits_mode: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"SetQHYCCDBitsMode\0",
                    "SetQHYCCDBitsMode",
                )?,
                exp_single_frame: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"ExpQHYCCDSingleFrame\0",
                    "ExpQHYCCDSingleFrame",
                )?,
                get_qhyccd_single_frame: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDSingleFrame\0",
                    "GetQHYCCDSingleFrame",
                )?,
                cancel_qhyccd_exposing_and_readout: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"CancelQHYCCDExposingAndReadout\0",
                    "CancelQHYCCDExposingAndReadout",
                )?,
                get_qhyccd_memory_length: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDMemLength\0",
                    "GetQHYCCDMemLength",
                )?,
                get_qhyccd_read_mode_name: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDReadModeName\0",
                    "GetQHYCCDReadModeName",
                )?,
                get_qhyccd_number_of_read_modes: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDNumberOfReadModes\0",
                    "GetQHYCCDNumberOfReadModes",
                )?,
                set_qhyccd_read_mode: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"SetQHYCCDReadMode\0",
                    "SetQHYCCDReadMode",
                )?,
                get_qhyccd_read_mode: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"GetQHYCCDReadMode\0",
                    "GetQHYCCDReadMode",
                )?,
                is_qhyccd_cfw_plugged: resolve_qhy_symbol(
                    &lib,
                    &library_path,
                    b"IsQHYCCDCFWPlugged\0",
                    "IsQHYCCDCFWPlugged",
                )?,
                get_sdk_version: match lib.get::<GetQhyccdSdkVersion>(b"GetQHYCCDSDKVersion\0") {
                    Ok(symbol) => Some(*symbol),
                    Err(error) => {
                        tracing::debug!(
                            "{}: optional symbol GetQHYCCDSDKVersion unavailable in {}: {}",
                            QHY_VENDOR_NAME,
                            library_path.display(),
                            error
                        );
                        None
                    }
                },
                lib,
            })
        })()
    };

    match sdk {
        Ok(sdk) => {
            tracing::info!("{}: all required symbols resolved", QHY_VENDOR_NAME);
            Some(sdk)
        }
        Err(e) => {
            tracing::error!(
                "{}: SDK present but symbol resolution failed: {}",
                QHY_VENDOR_NAME,
                e
            );
            None
        }
    }
}

impl QhySdk {
    /// Load the QHY SDK library
    fn load() -> Option<Self> {
        load_qhy_sdk()
    }

    /// Get the global SDK instance
    fn get() -> Option<&'static QhySdk> {
        QHY_SDK.get_or_init(Self::load).as_ref()
    }

    /// Initialize the SDK (must be called once before use)
    fn ensure_initialized() -> Result<(), NativeError> {
        if *SDK_INITIALIZED.get_or_init(|| {
            if let Some(sdk) = Self::get() {
                // SAFETY: InitQHYCCDResource takes no arguments and returns a c_uint status.
                // OnceLock::get_or_init guarantees this initializer runs at most once globally,
                // so no concurrent SDK access can occur during initialization.
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

fn sdk_version_from_sdk(sdk: &QhySdk) -> Option<String> {
    let get_sdk_version = sdk.get_sdk_version?;
    let mut year = 0;
    let mut month = 0;
    let mut day = 0;
    let mut subday = 0;

    // SAFETY: GetQHYCCDSDKVersion takes four valid c_uint out-pointers and writes SDK
    // version components. It has no device-handle dependency.
    let result = unsafe { get_sdk_version(&mut year, &mut month, &mut day, &mut subday) };
    if result == 0 && year > 0 {
        Some(format!("QHY SDK v{year}.{month:02}.{day:02}.{subday}"))
    } else {
        tracing::debug!(
            "QHY SDK version query failed or returned an invalid version: result={}, year={}, month={}, day={}, subday={}",
            result,
            year,
            month,
            day,
            subday
        );
        None
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

/// Full-scale ADU of the delivered pixel container for a QHY camera.
///
/// QHY splits this into two separate SDK queries, and the driver historically
/// used neither:
///
/// * `GetQHYCCDChipInfo`'s `bpp` is the **container** depth (8 or 16). The SDK
///   manual calls it "Image data bit depth", and it is what
///   `SetQHYCCDBitsMode`/`CONTROL_TRANSFERBIT` set.
/// * `GetQHYCCDParam(OutputDataActualBits)` is the **ADC precision** — "the
///   actual number of bits of raw data output by the chip" (SDK manual §21).
///
/// The manual is explicit that sub-16-bit ADCs are left-justified into the
/// 16-bit container. §14 ("Set digit and image data format"):
///
/// > Note that the output image data of digits and the original data bits may
/// > not be consistent, such as camera raw data for the 12, then if set camera
/// > output 16-bit data, inside the camera can be in the original data of low
/// > zero padding, converted to 16 bits of data
///
/// and §21 again: "the 16-bit image data can be obtained by adding the low zero
/// position". Zero-padding the *low* bits means the ADC bits sit high, so a
/// 12-bit QHY in 16-bit transfer mode reaches `4095 << 4 = 65520`, not 4095.
/// §22 exposes the same fact at runtime: "Get the alignment format of the camera
/// output data. If the return value is 1, it indicates high alignment; if the
/// return value is 0, it indicates low alignment." (QHYCCD SDK API manual v2.6,
/// `QHYCCD SDK API MENU_EN.pdf`.) An independent user report of a ToupTek camera
/// asks for "scaled 16 bit FITS files like you have with ZWO or QHY cameras"
/// — <https://indilib.org/forum/ccds-dslrs/12316>.
///
/// `container_bits < 16` (the 8-bit transfer mode) is a genuine byte container:
/// the SDK takes the high bits, so the ceiling is 255 regardless of the ADC.
/// Unknown `actual_bits`, or an ADC at least as wide as the container, take the
/// container's own ceiling rather than underflowing to 0, which would report
/// "this camera cannot produce any signal". A `container_bits` outside 1..=16 is
/// an unpopulated SDK field, not a 1-bit sensor, and falls back to 16 for the
/// same reason.
fn container_max_adu(container_bits: u32, actual_bits: Option<u32>, high_aligned: bool) -> u32 {
    let container_bits = if (1..=16).contains(&container_bits) {
        container_bits
    } else {
        16
    };
    let container_max = (1u32 << container_bits) - 1;
    let Some(actual_bits) = actual_bits.filter(|bits| (1..container_bits).contains(bits)) else {
        return container_max;
    };
    if high_aligned {
        ((1u32 << actual_bits) - 1) << (container_bits - actual_bits)
    } else {
        (1u32 << actual_bits) - 1
    }
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

    // Pixel-container description, established in connect() *after* the
    // transfer bit depth is forced. `bits_per_pixel` above comes from
    // GetQHYCCDChipInfo, which the QHY SDK manual calls the "Image data bit
    // depth" — the container, not the ADC — and which is read before that
    // force, so it must not be the source of truth for `max_adu`.
    /// Transfer/container depth actually in force (8 or 16), i.e. the width of
    /// the samples `GetQHYCCDSingleFrame` writes.
    output_container_bits: u32,
    /// ADC precision from `GetQHYCCDParam(OutputDataActualBits)`, or `None`
    /// when the camera does not support that query.
    actual_output_bits: Option<u32>,
    /// `GetQHYCCDParam(OutputDataAlignment)`: 1 = high alignment, 0 = low.
    /// Defaults to high, which is the behaviour the SDK manual documents for
    /// every camera (see [`container_max_adu`]).
    output_high_aligned: bool,

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
    // set_cooler call instead of hardcoding `false`.
    cooler_on: bool,
    cooler_target_c: Option<f64>,
}

// SAFETY: QhyCamera contains a raw `QhyCamHandle` (`Option<*mut c_void>`). All accesses to the
// handle go through `qhy_mutex()` (see every `unsafe { (sdk.*)(handle, ...) }` site in this
// file), serializing FFI calls across threads.
unsafe impl Send for QhyCamera {}
// SAFETY: Same justification — shared references to QhyCamera never invoke the SDK without
// taking `qhy_mutex()` first.
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
            output_container_bits: 16,
            actual_output_bits: None,
            output_high_aligned: true,
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

    /// Read the ADC precision behind the delivered container, or `None` when
    /// this camera cannot report it.
    ///
    /// `OutputDataActualBits` is documented in the QHYCCD SDK API manual §21 as
    /// "the actual number of bits of raw data output by the chip" — the ADC
    /// precision, which `GetQHYCCDChipInfo`'s `bpp` (the container) is not.
    /// `IsQHYCCDControlAvailable` entry 55 is "Check whether the camera can get
    /// the actual bits of output data" and returns QHYCCD_SUCCESS (0) when it can.
    ///
    /// SAFETY (callers): `qhy_mutex()` must be held and `handle` must be an
    /// open, initialized camera handle.
    fn probe_output_data_actual_bits(&self, sdk: &QhySdk, handle: QhyCamHandle) -> Option<u32> {
        // SAFETY: caller holds qhy_mutex() and `handle` came from a successful
        // OpenQHYCCD/InitQHYCCD pair. Both FFI calls take the handle plus a
        // plain control-id integer, with no out-pointers.
        let available = unsafe {
            (sdk.is_qhyccd_control_available)(handle, QhyControl::OutputDataActualBits as c_int)
        };
        if available != 0 {
            return None;
        }
        // SAFETY: as above; GetQHYCCDParam returns the value by f64 return.
        let raw =
            unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::OutputDataActualBits as c_int) };
        // QHY signals a failed read by returning QHYCCD_ERROR (0xFFFFFFFF) widened
        // into the f64; anything outside a plausible ADC width is not usable.
        if !(1.0..=16.0).contains(&raw) {
            tracing::debug!(
                "QHY camera {}: OutputDataActualBits returned {}, outside 1..=16; \
                 falling back to the container ceiling",
                self.camera_id,
                raw
            );
            return None;
        }
        Some(raw as u32)
    }

    /// Whether the ADC bits sit at the top of the container.
    ///
    /// QHYCCD SDK API manual §22: "Get the alignment format of the camera output
    /// data. If the return value is 1, it indicates high alignment; if the return
    /// value is 0, it indicates low alignment." The parameter is optional (the
    /// manual's Get-parameter table marks it "Not enabled" on many models), so
    /// when it is unavailable we use the behaviour §14/§21 document for every
    /// camera: 16-bit output is produced by "low zero padding" of the raw data,
    /// i.e. high alignment.
    ///
    /// SAFETY (callers): `qhy_mutex()` must be held and `handle` must be an
    /// open, initialized camera handle.
    fn probe_output_data_high_aligned(&self, sdk: &QhySdk, handle: QhyCamHandle) -> bool {
        // SAFETY: caller holds qhy_mutex() and `handle` came from a successful
        // OpenQHYCCD/InitQHYCCD pair; control-id integer argument only.
        let available = unsafe {
            (sdk.is_qhyccd_control_available)(handle, QhyControl::OutputDataAlignment as c_int)
        };
        if available != 0 {
            return true;
        }
        // SAFETY: as above.
        let raw =
            unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::OutputDataAlignment as c_int) };
        if raw == 0.0 {
            tracing::info!(
                "QHY camera {}: OutputDataAlignment reports low alignment; \
                 publishing the ADC range as the container ceiling",
                self.camera_id
            );
            return false;
        }
        true
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

        // SAFETY: load_camera_info is a private helper called from connect() and check_cfw_available
        // contexts where qhy_mutex() is already held by the caller; `handle` came from a successful
        // OpenQHYCCD/InitQHYCCD pair (verified above via self.handle.ok_or). All eight out-pointers
        // are valid stack pointers to the SDK-expected types.
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
        // SAFETY: caller holds qhy_mutex(); `handle` validated above; IsQHYCCDControlAvailable
        // takes the handle and a control-id integer with no out-pointers.
        self.has_cooler = unsafe {
            (sdk.is_qhyccd_control_available)(handle, QhyControl::CONTROL_COOLER as c_int)
        } == 0;
        // SAFETY: caller holds qhy_mutex(); handle validated above; same FFI signature as above.
        self.has_st4_port = unsafe {
            (sdk.is_qhyccd_control_available)(handle, QhyControl::CONTROL_ST4PORT as c_int)
        } == 0;
        // SAFETY: caller holds qhy_mutex(); handle validated above; same FFI signature as above.
        self.is_color =
            unsafe { (sdk.is_qhyccd_control_available)(handle, QhyControl::CAM_IS_COLOR as c_int) }
                == 0;

        // Detect bayer pattern for color cameras
        if self.is_color {
            // SAFETY: caller holds qhy_mutex(); handle validated above; GetQHYCCDParam returns a
            // c_double by value with no out-pointers.
            // Why: GetQHYCCDParam returns c_double encoding a small integer Bayer code
            // (1..=4). The match below treats anything outside that range as None, so
            // a saturating truncation here is sound: we only need the value to compare
            // against 1-4. `as i32` on a finite f64 in that range is well-defined.
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
        // SAFETY: qhy_mutex held just above; handle was validated via Option::ok_or; control
        // discriminant fits in c_int. GetQHYCCDParam returns c_double by value, no out-pointers.
        Ok(unsafe { (sdk.get_qhyccd_param)(handle, control as c_int) })
    }

    /// Get a control value (synchronous - caller must hold mutex)
    fn get_control(&self, control: QhyControl) -> Result<f64, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;
        // SAFETY: caller must hold qhy_mutex (documented in the function doc comment above);
        // handle validated; control discriminant fits in c_int. Return by value.
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
        // SAFETY: qhy_mutex held above; handle validated; control discriminant fits in c_int;
        // value is pass-by-value c_double. SDK validates the value internally.
        let result = unsafe { (sdk.set_qhyccd_param)(handle, control as c_int, value) };
        check_qhy_error(result, "SetQHYCCDParam")
    }

    /// Set a control value (synchronous - caller must hold mutex)
    fn set_control(&mut self, control: QhyControl, value: f64) -> Result<(), NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;
        // SAFETY: caller must hold qhy_mutex (per the function doc above); handle validated;
        // control discriminant fits in c_int; value is pass-by-value c_double.
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

        // SAFETY: qhy_mutex held above; handle validated; control discriminant fits in c_int;
        // all three out-pointers are valid stack pointers to c_double.
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

        // SAFETY: caller must hold qhy_mutex (per the function doc above); handle validated;
        // control discriminant fits in c_int; all three out-pointers are valid stack pointers.
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
        if self.connected {
            return Ok(());
        }

        // Ensure SDK is initialized
        QhySdk::ensure_initialized()?;

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Acquire mutex for SDK operations
        let _lock = qhy_mutex().lock().await;

        // Open the camera
        let id_cstring = CString::new(self.camera_id.clone())
            .map_err(|_| NativeError::InvalidDevice("Invalid camera ID".to_string()))?;

        // SAFETY: qhy_mutex held above; id_cstring is a valid NUL-terminated CString that
        // outlives the call (it lives until the end of this function). OpenQHYCCD returns a
        // handle that we null-check immediately below.
        let handle = unsafe { (sdk.open_qhyccd)(id_cstring.as_ptr()) };
        if handle.is_null() {
            return Err(NativeError::InvalidDevice(
                "Failed to open QHY camera".to_string(),
            ));
        }

        // Set single frame mode
        // SAFETY: qhy_mutex held; `handle` is the non-null pointer returned by OpenQHYCCD above;
        // mode=0 (single frame) is a documented constant per qhyccd.h.
        let result = unsafe { (sdk.set_qhyccd_stream_mode)(handle, 0) }; // 0 = single frame
        if result != 0 {
            // SAFETY: qhy_mutex held; handle was successfully opened above. CloseQHYCCD pairs
            // with OpenQHYCCD to release the handle on the error path.
            unsafe { (sdk.close_qhyccd)(handle) };
            self.handle = None;
            self.connected = false;
            return Err(NativeError::SdkError(format!(
                "Failed to set stream mode: {}",
                result
            )));
        }

        // Initialize the camera
        // SAFETY: qhy_mutex held; handle was successfully opened and stream-mode set above.
        let result = unsafe { (sdk.init_qhyccd)(handle) };
        if result != 0 {
            // SAFETY: qhy_mutex held; handle was successfully opened above. CloseQHYCCD pairs
            // with OpenQHYCCD on the error path.
            unsafe { (sdk.close_qhyccd)(handle) };
            self.handle = None;
            self.connected = false;
            return Err(NativeError::SdkError(format!(
                "Failed to init camera: {}",
                result
            )));
        }

        self.handle = Some(handle);

        // Load camera info (mutex is already held)
        if let Err(error) = self.load_camera_info() {
            // SAFETY: qhy_mutex held; handle was successfully opened and initialized above.
            // CloseQHYCCD pairs with OpenQHYCCD on the chip-info error path.
            unsafe { (sdk.close_qhyccd)(handle) };
            self.handle = None;
            self.connected = false;
            return Err(error);
        }

        // Set default settings
        // SAFETY: qhy_mutex held; handle valid (opened + initialized above); 16 is a documented
        // bit-depth value per qhyccd.h.
        // Why the result is captured rather than discarded: load_camera_info()
        // ran *before* this call, so its GetQHYCCDChipInfo `bpp` describes
        // whatever transfer mode the camera powered up in — on a model that
        // defaults to 8-bit it would have us publish a 255 ceiling for frames we
        // then download as 16-bit. Track what we actually negotiated.
        let bits_mode_result = unsafe { (sdk.set_qhyccd_bits_mode)(handle, 16) };
        self.output_container_bits = if bits_mode_result == 0 {
            16
        } else {
            tracing::warn!(
                "QHY camera {}: SetQHYCCDBitsMode(16) failed (error {}); keeping the SDK-reported {}-bit container",
                self.camera_id,
                bits_mode_result,
                self.bits_per_pixel
            );
            self.bits_per_pixel
        };
        // The ADC precision and the alignment of those bits inside the container
        // are separate, optional queries. Both are gated on
        // IsQHYCCDControlAvailable (0 == available) exactly as the SDK manual
        // prescribes; when unavailable we keep the documented default of high
        // alignment with unknown precision, which yields the container ceiling.
        // See [`container_max_adu`].
        self.actual_output_bits = self.probe_output_data_actual_bits(sdk, handle);
        self.output_high_aligned = self.probe_output_data_high_aligned(sdk, handle);
        // SAFETY: qhy_mutex held; handle valid; (1,1) is the documented identity binning.
        let _ = unsafe { (sdk.set_qhyccd_binmode)(handle, 1, 1) }; // 1x1 binning
                                                                   // SAFETY: qhy_mutex held; handle valid; (0,0,image_width,image_height) is the full sensor
                                                                   // window that the SDK just reported via GetQHYCCDChipInfo in load_camera_info().
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
                // SAFETY: qhy_mutex held above; `handle` was successfully opened during
                // connect() and stored in self.handle (None case skipped via if-let).
                // CloseQHYCCD pairs with OpenQHYCCD.
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
            // back cooler enable / target setpoint.
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
        // SAFETY: qhy_mutex held above; handle was validated via Option::ok_or; self.connected
        // was true (checked at entry). ExpQHYCCDSingleFrame takes only the handle.
        let result = unsafe { (sdk.exp_single_frame)(handle) };
        // ExpQHYCCDSingleFrame does NOT return QHYCCD_SUCCESS(0) on every camera:
        // legacy CCD / A-series bodies (QHY9, QHY8L, QHY22, QHY23, QHY16200A)
        // return QHYCCD_READ_DIRECTLY (0x2001) or QHYCCD_DELAY_200MS (0x2000) to
        // signal their readout timing — these are NON-fatal mode signals, not
        // errors. Only QHYCCD_ERROR (0xFFFFFFFF) is a real failure. The reference
        // driver checks exactly this (qhy_ccd.cpp: `if (ExpQHYCCDSingleFrame(...)
        // == QHYCCD_ERROR)`); routing this through the generic error map instead
        // aborted every exposure on those cameras with a bogus "Direct read
        // failed". Match the reference: fail only on QHYCCD_ERROR.
        if result == 0xFFFF_FFFF {
            return Err(NativeError::SdkError(
                "ExpQHYCCDSingleFrame: General error - camera may be in use by another application or disconnected".to_string(),
            ));
        }
        if result == 0x2000 || result == 0x2001 {
            tracing::debug!(
                "QHY ExpQHYCCDSingleFrame returned readout-timing signal 0x{:X} (legacy CCD, non-fatal)",
                result
            );
        }

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

        // SAFETY: qhy_mutex held above; handle was validated via Option::ok_or; self.connected
        // was true (checked at entry). CancelQHYCCDExposingAndReadout takes only the handle.
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

        // Get required buffer size.
        // SAFETY: qhy_mutex held above; handle was validated via Option::ok_or; self.connected
        // was true. GetQHYCCDMemLength returns c_uint by value.
        // Why: c_uint (u32) -> usize is widening on every Tier 1 target (32- or 64-bit usize
        // each holds u32::MAX), so this is always safe.
        let buffer_len = unsafe { (sdk.get_qhyccd_memory_length)(handle) } as usize;
        // Use pooled buffer for efficient memory reuse
        let mut pooled_buffer = global_u8_pool().get_buffer(buffer_len);
        pooled_buffer.resize(buffer_len);

        let mut width: c_uint = 0;
        let mut height: c_uint = 0;
        let mut bpp: c_uint = 0;
        let mut channels: c_uint = 0;

        // SAFETY: qhy_mutex held; handle valid; four out-pointers are valid stack pointers;
        // pooled_buffer was just resized to buffer_len (the SDK's reported memory length above),
        // so the SDK can safely write up to buffer_len bytes through as_mut_ptr().
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

        // Trim buffer to actual size.
        // Why: width/height/bpp/channels are c_uint (u32). On a hypothetical 32K x 32K
        // 16bpp 3-channel sensor we'd hit ~6.4 GB, overflowing u32 silently. Promote to
        // u64 before multiplying and surface overflow as an SdkError. This also rejects
        // pathological bpp=0 returns (channels.max(1) preserves the original guard).
        let width_u64 = u64::from(width);
        let height_u64 = u64::from(height);
        let bpp_bytes_u64 = u64::from(bpp / 8);
        let channels_u64 = u64::from(channels.max(1));
        let actual_size_u64 = width_u64
            .checked_mul(height_u64)
            .and_then(|p| p.checked_mul(bpp_bytes_u64))
            .and_then(|p| p.checked_mul(channels_u64))
            .ok_or_else(|| {
                NativeError::SdkError(format!(
                    "QHY frame size overflow: {}x{} bpp={} channels={}",
                    width, height, bpp, channels
                ))
            })?;
        let actual_size = usize::try_from(actual_size_u64).map_err(|_| {
            NativeError::SdkError(format!(
                "QHY frame size {} does not fit in usize",
                actual_size_u64
            ))
        })?;
        if actual_size > pooled_buffer.len() {
            return Err(NativeError::SdkError(format!(
                "QHY reported frame larger than allocated buffer: {} > {}",
                actual_size,
                pooled_buffer.len()
            )));
        }
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

        if enabled {
            if let Some((min_temp, max_temp)) = crate::quirks::get_cooler_range(&self.device_id) {
                if target_temp < min_temp || target_temp > max_temp {
                    return Err(NativeError::InvalidParameter(format!(
                        "QHY cooler target {target_temp}C is outside the supported range {min_temp}C..={max_temp}C for {}",
                        self.device_id
                    )));
                }
            }
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
        if let Some(delay_ms) = crate::quirks::get_temperature_delay_ms(&self.device_id) {
            tracing::debug!(
                "Applying temperature RequiresDelayMs quirk: sleeping {}ms before reading {}",
                delay_ms,
                self.device_id
            );
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
        }
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
        // Why: QHY gain is a small non-negative integer (0..=~1000 across all current
        // models; range-clamped by SDK). f64 -> i32 with saturation is well-defined for
        // finite values, and only the integer portion is meaningful for a gain step.
        Ok(self.get_control_async(QhyControl::CONTROL_GAIN).await? as i32)
    }

    async fn set_offset(&mut self, offset: i32) -> Result<(), NativeError> {
        self.set_control_async(QhyControl::CONTROL_OFFSET, offset as f64)
            .await?;
        self.current_offset = offset;
        Ok(())
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        // Why: QHY offset is a small non-negative integer (0..=~1000) clamped by the SDK.
        // f64 -> i32 with saturation is well-defined for finite values in this range.
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

        // Why: bin must be >= 1 (you cannot bin by zero or a negative factor). We use
        // try_from to surface a caller error rather than silently wrapping a negative i32
        // into a giant c_uint that would underflow image_width/bin on the next line.
        let bin_max = bin_x.max(bin_y);
        if bin_max < 1 {
            return Err(NativeError::InvalidParameter(format!(
                "QHY binning must be >= 1, got bin_x={} bin_y={}",
                bin_x, bin_y
            )));
        }
        let bin = c_uint::try_from(bin_max).map_err(|_| {
            NativeError::InvalidParameter(format!(
                "QHY binning does not fit in c_uint: {}",
                bin_max
            ))
        })?;
        // SAFETY: qhy_mutex held above; handle was validated via Option::ok_or; self.connected
        // was true. bin is pass-by-value c_uint and the SDK validates the value.
        let result = unsafe { (sdk.set_qhyccd_binmode)(handle, bin, bin) };
        check_qhy_error(result, "SetQHYCCDBinMode")?;

        // Update resolution for new binning
        let new_width = self.image_width / bin;
        let new_height = self.image_height / bin;
        // SAFETY: qhy_mutex held; handle valid; new_width/new_height are derived from
        // self.image_width/height (loaded by GetQHYCCDChipInfo at connect time) divided by the
        // just-applied bin factor — both ≤ original sensor dimensions.
        let result = unsafe { (sdk.set_qhyccd_resolution)(handle, 0, 0, new_width, new_height) };
        check_qhy_error(result, "SetQHYCCDResolution")?;

        // Why: bin was already validated >= 1 above; c_uint -> i32 only fails when value
        // exceeds i32::MAX. A bin > 2^31 is meaningless physically, but propagate the error
        // rather than wrap.
        self.current_bin = i32::try_from(bin).map_err(|_| {
            NativeError::InvalidParameter(format!("QHY bin {} does not fit in i32", bin))
        })?;
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
            // Why: current_bin is i32 validated >= 1 inside set_binning(). A corrupt
            // negative value would wrap to a giant u32 here and crash the division below
            // with image_width/0. Fail loudly instead.
            let bin_u32 = u32::try_from(self.current_bin.max(1)).map_err(|_| {
                NativeError::InvalidParameter(format!(
                    "QHY current_bin not representable as u32: {}",
                    self.current_bin
                ))
            })?;
            (
                0,
                0,
                self.image_width / bin_u32,
                self.image_height / bin_u32,
            )
        };

        // SAFETY: qhy_mutex held above; handle was validated via Option::ok_or; self.connected
        // was true. x/y/width/height come from the user-supplied SubFrame or from sensor
        // dimensions / current bin — both branches produce in-sensor coordinates the SDK clips.
        let result = unsafe { (sdk.set_qhyccd_resolution)(handle, x, y, width, height) };
        check_qhy_error(result, "SetQHYCCDResolution")
    }

    fn get_sensor_info(&self) -> SensorInfo {
        SensorInfo {
            width: self.image_width,
            height: self.image_height,
            pixel_size_x: self.pixel_width,
            pixel_size_y: self.pixel_height,
            // `max_adu` is the pixel-container full scale and `bit_depth` the
            // ADC precision — two different quantities that QHY exposes through
            // two different SDK queries. See [`container_max_adu`] and the
            // `SensorInfo::max_adu` contract. `(1 << bits_per_pixel) - 1` used
            // both the wrong query (GetQHYCCDChipInfo's container `bpp`) and a
            // value read before connect() forced 16-bit transfer mode.
            max_adu: container_max_adu(
                self.output_container_bits,
                self.actual_output_bits,
                self.output_high_aligned,
            ),
            bit_depth: self.actual_output_bits.unwrap_or(self.bits_per_pixel),
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
        // SAFETY: qhy_mutex held above; handle was validated via Option::ok_or; self.connected
        // was true; &mut num_modes is a valid stack pointer to c_uint.
        let result = unsafe { (sdk.get_qhyccd_number_of_read_modes)(handle, &mut num_modes) };
        check_qhy_error(result, "GetQHYCCDNumberOfReadModes")?;

        let mut modes = Vec::new();
        for i in 0..num_modes {
            let mut name_buf = [0 as c_char; 256];
            // SAFETY: qhy_mutex held; handle valid; `i` is in `0..num_modes` reported by the
            // SDK above so it is a valid read-mode index; name_buf is a 256-byte stack array.
            let result =
                unsafe { (sdk.get_qhyccd_read_mode_name)(handle, i, name_buf.as_mut_ptr()) };
            if result == 0 {
                // SAFETY: name_buf is 256 bytes; SDK guarantees NUL-termination on success
                // (result == 0).
                let name = unsafe { CStr::from_ptr(name_buf.as_ptr()) }
                    .to_string_lossy()
                    .to_string();
                modes.push(ReadoutMode {
                    // Why: `i` ranges over `0..num_modes` where num_modes is a c_uint
                    // populated by GetQHYCCDNumberOfReadModes. QHY cameras advertise a
                    // small handful of readout modes (<= 8 across all known SKUs), so
                    // i fits trivially in i32 and `as i32` is well-defined.
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

        // Read the current read mode first so we can restore it if the re-init
        // below fails, leaving the camera in its prior working state.
        let mut prev_mode: c_uint = 0;
        // SAFETY: qhy_mutex is held (acquired above) so no other task is inside the
        // QHY SDK. `handle` was opened by OpenQHYCCD during connect() and is still
        // open: it is only ever taken/closed by disconnect(), which needs both the
        // same mutex and the `&mut self` this method already holds exclusively.
        // `&mut prev_mode` is a live stack local of exactly the c_uint the SDK writes.
        let _ = unsafe { (sdk.get_qhyccd_read_mode)(handle, &mut prev_mode) };

        // SAFETY: qhy_mutex held above; handle was validated via Option::ok_or; self.connected
        // was true. mode.index originated from a ReadoutMode this driver produced in
        // get_readout_modes() above, so it is a valid SDK read-mode index.
        let result = unsafe { (sdk.set_qhyccd_read_mode)(handle, mode.index as c_uint) };
        check_qhy_error(result, "SetQHYCCDReadMode")?;

        // A read-mode change only takes effect after RE-INITIALIZING the camera,
        // and different read modes can expose different sensor geometry, gain and
        // full-well. Without the re-init + geometry refresh, SetQHYCCDReadMode
        // silently no-ops (frames keep read-mode-0 characteristics) or leaves the
        // SDK geometry inconsistent with our cached dimensions → misframed frames.
        // The reference driver does SetReadMode -> InitQHYCCD -> re-read chip info
        // -> reset ROI, reverting on failure (qhy_ccd.cpp:2069-2088).
        // SAFETY: qhy_mutex held; handle valid. InitQHYCCD takes only the handle.
        let init_result = unsafe { (sdk.init_qhyccd)(handle) };
        if check_qhy_error(init_result, "InitQHYCCD (after read-mode change)").is_err() {
            // Restore the previous read mode + re-init so the camera stays usable.
            // SAFETY: qhy_mutex held; handle valid; prev_mode is the mode read above.
            let _ = unsafe { (sdk.set_qhyccd_read_mode)(handle, prev_mode) };
            // SAFETY: same held mutex and same still-open handle as the restore call
            // immediately above; InitQHYCCD takes only that handle, no pointers.
            let _ = unsafe { (sdk.init_qhyccd)(handle) };
            let _ = self.load_camera_info();
            // SAFETY: qhy_mutex held; handle valid; full-frame ROI from refreshed dims.
            let _ = unsafe {
                (sdk.set_qhyccd_resolution)(handle, 0, 0, self.image_width, self.image_height)
            };
            return Err(NativeError::SdkError(format!(
                "Failed to initialize QHY camera after switching to read mode {}; reverted to previous mode",
                mode.index
            )));
        }

        // Refresh cached geometry for the new read mode and reset the full-frame ROI.
        self.load_camera_info()?;
        // SAFETY: qhy_mutex held; handle valid; dimensions just refreshed by load_camera_info().
        let res_result = unsafe {
            (sdk.set_qhyccd_resolution)(handle, 0, 0, self.image_width, self.image_height)
        };
        check_qhy_error(res_result, "SetQHYCCDResolution (after read-mode change)")
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
        // Why: gain min/max are small non-negative integers in practice (<= ~1000),
        // returned as f64 by QHY's range API. f64 -> i32 with saturation is sound here.
        Ok((min as i32, max as i32))
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let (min, max, _step) = self
            .get_control_range_async(QhyControl::CONTROL_OFFSET)
            .await?;
        // Why: offset min/max are small non-negative integers (<= ~1000) returned as
        // f64 by QHY's range API. f64 -> i32 with saturation is sound here.
        Ok((min as i32, max as i32))
    }

    /// Surface the SDK-advertised recommended settings.
    ///
    /// QHY exposes manufacturer-recommended values through two dedicated
    /// control IDs:
    /// - `DefaultGain` (control 53): per-camera recommended unity-gain value.
    /// - `DefaultOffset` (control 54): per-camera recommended offset.
    ///
    /// These are only present on cameras whose firmware publishes them
    /// (modern QHY CMOS cameras like QHY183/268/600/MiniGuider series do; older
    /// CCD cameras do not). We probe with `IsQHYCCDControlAvailable` and
    /// honestly return `None` when the camera doesn't expose them.
    ///
    /// QHY does NOT expose the HCG transition point through the SDK — it's
    /// documented per-camera in the manual.
    async fn get_recommended_settings(
        &self,
    ) -> Result<crate::camera::CameraRecommendedSettings, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let _lock = qhy_mutex().lock().await;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        let mut out = crate::camera::CameraRecommendedSettings::default();
        let mut notes: Vec<String> = Vec::new();

        // QHY returns 0 (QHYCCD_SUCCESS) from IsQHYCCDControlAvailable when the
        // control is present. Anything else means "not available" — that is an
        // honest "no recommendation", not an error.

        // DefaultGain (control 53)
        // SAFETY: qhy_mutex held; handle validated; IsQHYCCDControlAvailable takes (handle, c_int).
        let default_gain_available =
            unsafe { (sdk.is_qhyccd_control_available)(handle, QhyControl::DefaultGain as c_int) };
        if default_gain_available == 0 {
            // SAFETY: qhy_mutex held; handle validated; GetQHYCCDParam returns c_double by value.
            let val = unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::DefaultGain as c_int) };
            // QHY returns a sentinel (0xFFFFFFFF as f64) on failure for some
            // firmware versions. Reject obviously bogus values.
            if val.is_finite() && (0.0..10_000.0).contains(&val) {
                let gain = val as i32;
                out.unity_gain = Some(gain);
                notes.push(format!("QHY DefaultGain control reports {}", gain));
            } else {
                tracing::warn!("QHY: DefaultGain returned out-of-range value {}", val);
            }
        }

        // DefaultOffset (control 54)
        // SAFETY: qhy_mutex held; handle validated; same FFI shape as above.
        let default_offset_available = unsafe {
            (sdk.is_qhyccd_control_available)(handle, QhyControl::DefaultOffset as c_int)
        };
        if default_offset_available == 0 {
            // SAFETY: qhy_mutex held; handle validated; GetQHYCCDParam returns c_double by value.
            let val = unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::DefaultOffset as c_int) };
            if val.is_finite() && (0.0..10_000.0).contains(&val) {
                let off = val as i32;
                out.default_offset = Some(off);
                notes.push(format!("QHY DefaultOffset control reports {}", off));
            } else {
                tracing::warn!("QHY: DefaultOffset returned out-of-range value {}", val);
            }
        }

        out.notes = notes.join("; ");
        Ok(out)
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
    /// QHY SDK version reported by the loaded native library, when available
    pub sdk_version: Option<String>,
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
    let sdk_version = sdk_version_from_sdk(sdk);

    // Scan for cameras
    // SAFETY: This helper is invoked only from discover_devices() (and the catch_unwind path it
    // dispatches), which acquires qhy_mutex() before calling. ScanQHYCCD takes no arguments and
    // returns a c_uint count.
    let num_cameras = unsafe { (sdk.scan_qhyccd)() };
    tracing::info!("Found {} QHY cameras", num_cameras);

    let mut cameras = Vec::new();
    for i in 0..num_cameras {
        let mut id_buf = [0 as c_char; 256];
        // SAFETY: caller (discover_devices) holds qhy_mutex(); `i` is in `0..num_cameras` so
        // ScanQHYCCD's reported index range; id_buf is a 256-byte stack array — qhyccd.h
        // documents the ID as fitting within 32 bytes.
        let result = unsafe { (sdk.get_qhyccd_id)(i, id_buf.as_mut_ptr()) };

        if result == 0 {
            // SAFETY: id_buf is 256 bytes; GetQHYCCDId guarantees NUL-termination on success
            // (result == 0).
            let id = unsafe { CStr::from_ptr(id_buf.as_ptr()) }
                .to_string_lossy()
                .to_string();

            // Parse model name and serial number from ID
            let (name, serial_number) = QhyCameraInfo::parse_id(&id);

            cameras.push(QhyCameraInfo {
                camera_id: id,
                name,
                serial_number,
                sdk_version: sdk_version.clone(),
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

const QHYCCD_ERROR_VALUE: f64 = u32::MAX as f64;
const DEFAULT_QHY_CFW_SLOTS: i32 = 5;
const MAX_QHY_CFW_SLOTS: i32 = 16;
const QHY_CFW_MOVE_TIMEOUT: Duration = Duration::from_secs(25);
const QHY_CFW_POLL_INTERVAL: Duration = Duration::from_millis(500);

fn parse_cfw_slot_count(count: f64) -> Result<i32, NativeError> {
    if !count.is_finite()
        // Rejects both the SDK's u32::MAX error sentinel and a nonsensical
        // sub-one wheel; a real CFW always reports at least one slot.
        || !(1.0..QHYCCD_ERROR_VALUE).contains(&count)
        || count > f64::from(MAX_QHY_CFW_SLOTS)
        || count.fract() != 0.0
    {
        return Err(NativeError::SdkError(format!(
            "GetQHYCCDParam(CONTROL_CFWSLOTSNUM) returned invalid slot count {}",
            count
        )));
    }

    Ok(count as i32)
}

fn parse_cfw_position(position: f64) -> Result<i32, NativeError> {
    if !position.is_finite() || position >= QHYCCD_ERROR_VALUE || position.fract() != 0.0 {
        return Err(NativeError::SdkError(format!(
            "GetQHYCCDParam(CONTROL_CFWPORT) returned invalid position {}",
            position
        )));
    }

    match position as u8 {
        b'0'..=b'9' => Ok(i32::from(position as u8 - b'0')),
        b'A'..=b'F' => Ok(i32::from(position as u8 - b'A') + 10),
        b'a'..=b'f' => Ok(i32::from(position as u8 - b'a') + 10),
        _ => Err(NativeError::SdkError(format!(
            "GetQHYCCDParam(CONTROL_CFWPORT) returned invalid position {}",
            position
        ))),
    }
}

fn encode_cfw_position(position: i32) -> f64 {
    let value = match position {
        0..=9 => b'0' + position as u8,
        10..=15 => b'A' + (position - 10) as u8,
        _ => unreachable!("CFW position was validated against the 16-slot maximum"),
    };
    f64::from(value)
}

/// QHY CFW discovery info
pub struct QhyFilterWheelInfo {
    /// Camera ID that the filter wheel is attached to
    pub camera_id: String,
    /// Display name
    pub name: String,
    /// Number of filter slots
    pub slot_count: i32,
    /// QHY SDK version reported by the loaded native library, when available
    pub sdk_version: Option<String>,
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
    target_position: Option<i32>,
}

// SAFETY: QhyFilterWheel contains a raw `QhyCamHandle` (`Option<*mut c_void>`). Every FFI call
// against the handle takes `qhy_mutex()` first (CFW is controlled through the camera SDK and
// shares the same global mutex), so the handle is never accessed concurrently.
unsafe impl Send for QhyFilterWheel {}
// SAFETY: Same justification — shared references never invoke the SDK without taking
// qhy_mutex() first.
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
            target_position: None,
        }
    }

    /// Check if CFW is available (must be called after connecting to camera)
    fn check_cfw_available(&self) -> Result<bool, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        // SAFETY: caller (connect / move_to_position / get_position) holds qhy_mutex(); handle
        // was validated via Option::ok_or; IsQHYCCDCFWPlugged takes only the handle.
        let result = unsafe { (sdk.is_qhyccd_cfw_plugged)(handle) };
        Ok(result == 0) // QHYCCD_SUCCESS = 0
    }

    /// Get number of filter slots
    fn get_slot_count(&self) -> Result<i32, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        // SAFETY: caller (connect()) holds qhy_mutex(); handle validated above;
        // CONTROL_CFWSLOTSNUM discriminant fits in c_int; GetQHYCCDParam returns c_double.
        let count =
            unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::CONTROL_CFWSLOTSNUM as c_int) };

        parse_cfw_slot_count(count)
    }

    /// Get current position (0-indexed)
    fn get_current_position(&self) -> Result<i32, NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        // QHY returns position as ASCII value (48 = '0', 49 = '1', etc.)
        // SAFETY: caller (get_position()) holds qhy_mutex(); handle validated above;
        // CONTROL_CFWPORT discriminant fits in c_int.
        let pos = unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::CONTROL_CFWPORT as c_int) };

        parse_cfw_position(pos)
    }

    /// Set position (0-indexed)
    fn set_current_position(&self, position: i32) -> Result<(), NativeError> {
        let sdk = QhySdk::get().ok_or(NativeError::SdkNotLoaded)?;
        let handle = self.handle.ok_or(NativeError::NotConnected)?;

        // QHY uses ASCII encoding ('0'..'9', then 'A'..'F').
        let ascii_position = encode_cfw_position(position);

        // SAFETY: caller (move_to_position()) holds qhy_mutex(); handle validated above;
        // CONTROL_CFWPORT discriminant fits in c_int; ascii_position is pass-by-value c_double.
        // The `position` argument was bounds-checked in the caller against self.slot_count.
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

        // SAFETY: qhy_mutex held above; camera_id_cstr is a valid NUL-terminated CString that
        // outlives the call. OpenQHYCCD returns a handle we null-check immediately below.
        let handle = unsafe { (sdk.open_qhyccd)(camera_id_cstr.as_ptr()) };
        if handle.is_null() {
            return Err(NativeError::SdkError(
                "Failed to open QHY camera for CFW".into(),
            ));
        }

        self.handle = Some(handle);

        // Set stream mode and init (required for CFW access)
        // SAFETY: qhy_mutex held; `handle` is the non-null pointer returned by OpenQHYCCD above;
        // mode=0 (single frame) is a documented constant per qhyccd.h; CloseQHYCCD pairs with
        // OpenQHYCCD on the error path inside the block.
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
            // SAFETY: qhy_mutex held; handle was successfully opened and initialized above.
            // CloseQHYCCD pairs with OpenQHYCCD on this CFW-not-available error path.
            unsafe { (sdk.close_qhyccd)(handle) };
            self.handle = None;
            return Err(NativeError::DeviceNotFound(
                "No CFW detected on this QHY camera".into(),
            ));
        }

        // Get slot count (mutex already held)
        self.slot_count = match self.get_slot_count() {
            Ok(count) => count,
            Err(error) => {
                tracing::warn!(
                    "Failed to detect QHY CFW slot count: {}; using {} slots",
                    error,
                    DEFAULT_QHY_CFW_SLOTS
                );
                DEFAULT_QHY_CFW_SLOTS
            }
        }
        .clamp(1, MAX_QHY_CFW_SLOTS);

        let current_position = match self.get_current_position() {
            Ok(position) if position < self.slot_count => position,
            Ok(position) => {
                // SAFETY: qhy_mutex held; handle was successfully opened and initialized above.
                unsafe { (sdk.close_qhyccd)(handle) };
                self.handle = None;
                return Err(NativeError::SdkError(format!(
                    "QHY CFW reported position {} outside its {} slots",
                    position, self.slot_count
                )));
            }
            Err(error) => {
                // SAFETY: qhy_mutex held; handle was successfully opened and initialized above.
                unsafe { (sdk.close_qhyccd)(handle) };
                self.handle = None;
                return Err(error);
            }
        };

        // Initialize filter names with defaults
        self.filter_names = (0..self.slot_count)
            .map(|i| format!("Filter {}", i + 1))
            .collect();
        self.target_position = Some(current_position);

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
                // SAFETY: qhy_mutex held above; handle was successfully opened during connect()
                // and stored in self.handle (None case skipped via if-let). CloseQHYCCD pairs
                // with OpenQHYCCD.
                unsafe { (sdk.close_qhyccd)(handle) };
            }
        }

        self.connected = false;
        self.target_position = None;
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
        self.target_position = Some(position);

        let started = Instant::now();
        loop {
            let current_position = {
                let _lock = qhy_mutex().lock().await;
                self.get_current_position()?
            };
            if current_position == position {
                return Ok(());
            }

            let elapsed = started.elapsed();
            if elapsed >= QHY_CFW_MOVE_TIMEOUT {
                return Err(NativeError::Timeout(format!(
                    "QHY CFW did not reach position {} within {:?} (current position: {})",
                    position, QHY_CFW_MOVE_TIMEOUT, current_position
                )));
            }

            tokio::time::sleep(QHY_CFW_POLL_INTERVAL.min(QHY_CFW_MOVE_TIMEOUT - elapsed)).await;
        }
    }

    async fn is_moving(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let target_position = self.target_position.ok_or_else(|| {
            NativeError::SdkError("QHY CFW target position is unknown".to_string())
        })?;
        let _lock = qhy_mutex().lock().await;
        Ok(self.get_current_position()? != target_position)
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
        // Why: bounds checked `0 <= position < self.slot_count` above; position is i32,
        // self.filter_names is a Vec sized to slot_count, so `as usize` is widening with
        // verified non-negative value.
        self.filter_names[position as usize] = name;
        Ok(())
    }
}

/// Internal function to perform the actual CFW discovery.
fn discover_filter_wheels_internal(sdk: &QhySdk) -> Result<Vec<QhyFilterWheelInfo>, NativeError> {
    let sdk_version = sdk_version_from_sdk(sdk);

    // Scan for cameras
    // SAFETY: caller (discover_filter_wheels) holds qhy_mutex(); ScanQHYCCD takes no args.
    let num_cameras = unsafe { (sdk.scan_qhyccd)() };

    let mut filter_wheels = Vec::new();

    for i in 0..num_cameras {
        let mut id_buf = [0 as c_char; 256];
        // SAFETY: caller holds qhy_mutex(); `i` is in `0..num_cameras`; id_buf is a 256-byte
        // stack array.
        let result = unsafe { (sdk.get_qhyccd_id)(i, id_buf.as_mut_ptr()) };

        if result != 0 {
            continue;
        }

        // SAFETY: id_buf is 256 bytes; GetQHYCCDId guaranteed NUL-termination on success.
        let camera_id = unsafe { CStr::from_ptr(id_buf.as_ptr()) }
            .to_string_lossy()
            .to_string();

        // Open camera temporarily to check for CFW
        let camera_id_cstr = match CString::new(camera_id.clone()) {
            Ok(s) => s,
            Err(_) => continue,
        };

        // SAFETY: caller holds qhy_mutex(); camera_id_cstr is a valid NUL-terminated CString
        // that outlives the call; null-checked immediately below.
        let handle = unsafe { (sdk.open_qhyccd)(camera_id_cstr.as_ptr()) };
        if handle.is_null() {
            continue;
        }

        // Initialize camera to check CFW
        // SAFETY: caller holds qhy_mutex(); `handle` is the non-null pointer returned by
        // OpenQHYCCD above; mode=0 is single-frame per qhyccd.h; CloseQHYCCD pairs with
        // OpenQHYCCD on the init-failed path within this block.
        unsafe {
            (sdk.set_qhyccd_stream_mode)(handle, 0);
            if (sdk.init_qhyccd)(handle) != 0 {
                (sdk.close_qhyccd)(handle);
                continue;
            }
        }

        // Check if CFW is plugged in
        // SAFETY: caller holds qhy_mutex(); handle was opened and initialized above.
        let cfw_result = unsafe { (sdk.is_qhyccd_cfw_plugged)(handle) };

        if cfw_result == 0 {
            // CFW is available
            // SAFETY: caller holds qhy_mutex(); handle was opened and initialized above;
            // CONTROL_CFWSLOTSNUM discriminant fits in c_int.
            let raw_slot_count =
                unsafe { (sdk.get_qhyccd_param)(handle, QhyControl::CONTROL_CFWSLOTSNUM as c_int) };
            let slot_count = parse_cfw_slot_count(raw_slot_count).unwrap_or_else(|error| {
                tracing::warn!(
                    "Failed to detect QHY CFW slot count for {}: {}; using {} slots",
                    camera_id,
                    error,
                    DEFAULT_QHY_CFW_SLOTS
                );
                DEFAULT_QHY_CFW_SLOTS
            });

            let (model_name, _) = QhyCameraInfo::parse_id(&camera_id);

            filter_wheels.push(QhyFilterWheelInfo {
                camera_id: camera_id.clone(),
                name: format!("{} CFW", model_name),
                slot_count,
                sdk_version: sdk_version.clone(),
            });

            tracing::info!(
                "Found QHY CFW on camera {} with {} slots",
                camera_id,
                slot_count
            );
        }

        // Close camera
        // SAFETY: caller holds qhy_mutex(); handle was opened above. CloseQHYCCD pairs with
        // OpenQHYCCD to release the SDK-owned handle at the end of the per-camera probe.
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

    /// A 16-bit transfer of a sub-16-bit ADC must publish the left-justified
    /// container ceiling, because the QHY SDK zero-pads the *low* bits.
    #[test]
    fn container_max_adu_accounts_for_low_zero_padding() {
        // 12-bit ADC (QHY183/QHY294 class) in 16-bit transfer: 4095 << 4
        assert_eq!(container_max_adu(16, Some(12), true), 65520);
        // 14-bit ADC: 16383 << 2
        assert_eq!(container_max_adu(16, Some(14), true), 65532);
        // 10-bit ADC: 1023 << 6
        assert_eq!(container_max_adu(16, Some(10), true), 65472);
        // A genuinely 16-bit ADC (QHY268/QHY600 class) needs no shift.
        assert_eq!(container_max_adu(16, Some(16), true), 65535);
    }

    /// Whatever ceiling we publish must fit the container and land on the sample
    /// grid the ADC produces — a 12-bit ADC left-justified into 16 bits can only
    /// emit multiples of 16.
    #[test]
    fn container_max_adu_is_a_reachable_sample() {
        for actual_bits in 1..=16u32 {
            let max = container_max_adu(16, Some(actual_bits), true);
            assert!(
                max <= u32::from(u16::MAX),
                "actual_bits {actual_bits} produced {max}, outside the 16-bit container"
            );
            let step = 1u32 << (16 - actual_bits);
            assert_eq!(
                max % step,
                0,
                "actual_bits {actual_bits}: {max} is not a multiple of the {step}-ADU sample step"
            );
        }
    }

    /// When `OutputDataAlignment` reports low alignment (return value 0), the
    /// ADC range *is* the reachable ceiling and must not be shifted.
    #[test]
    fn container_max_adu_honours_low_alignment() {
        assert_eq!(container_max_adu(16, Some(12), false), 4095);
        assert_eq!(container_max_adu(16, Some(14), false), 16383);
        assert_eq!(container_max_adu(16, Some(16), false), 65535);
    }

    /// An unavailable `OutputDataActualBits` query must fall back to the
    /// container ceiling, never to 0 — a 0 ceiling would tell every
    /// percent-of-full-scale consumer the camera cannot produce any signal.
    #[test]
    fn container_max_adu_unknown_precision_falls_back_to_container() {
        assert_eq!(container_max_adu(16, None, true), 65535);
        assert_eq!(container_max_adu(16, None, false), 65535);
        // A reported precision at least as wide as the container is also a
        // no-op, and an out-of-range one must not shift by a negative amount.
        assert_eq!(container_max_adu(16, Some(0), true), 65535);
        assert_eq!(container_max_adu(16, Some(32), true), 65535);
    }

    /// The 8-bit transfer mode is a genuine byte container: the SDK takes the
    /// high bits, so the ceiling is 255 regardless of ADC precision. Publishing
    /// the 16-bit ceiling there would overstate a frame 257x.
    #[test]
    fn container_max_adu_eight_bit_transfer_is_a_byte_container() {
        assert_eq!(container_max_adu(8, Some(12), true), 255);
        assert_eq!(container_max_adu(8, None, true), 255);
    }

    /// An unpopulated GetQHYCCDChipInfo `bpp` (0) must not be read as a 1-bit
    /// sensor — a ceiling of 1 is the same "camera cannot produce any signal"
    /// failure as a ceiling of 0.
    #[test]
    fn container_max_adu_unpopulated_container_width_falls_back_to_sixteen() {
        assert_eq!(container_max_adu(0, None, true), 65535);
        assert_eq!(container_max_adu(0, Some(12), true), 65520);
        assert_eq!(container_max_adu(99, None, true), 65535);
    }

    /// A fresh camera must assume the 16-bit container it is about to negotiate,
    /// with unknown ADC precision and the SDK-documented high alignment — i.e.
    /// the full container ceiling, never 0.
    #[test]
    fn new_camera_publishes_the_container_ceiling_before_probing() {
        let cam = QhyCamera::new("test".to_string());
        assert_eq!(cam.output_container_bits, 16);
        assert_eq!(cam.actual_output_bits, None);
        assert!(cam.output_high_aligned);
        assert_eq!(
            container_max_adu(
                cam.output_container_bits,
                cam.actual_output_bits,
                cam.output_high_aligned
            ),
            65535
        );
    }

    /// The ceiling must agree with the pipeline's own saturation threshold
    /// (`nightshade_imaging::fits` uses 65024, documented as "4064 << 4").
    #[test]
    fn container_max_adu_agrees_with_pipeline_saturation_threshold() {
        const PIPELINE_SATURATION_THRESHOLD: u32 = 65024;
        let twelve_bit_ceiling = container_max_adu(16, Some(12), true);
        assert!(
            PIPELINE_SATURATION_THRESHOLD < twelve_bit_ceiling,
            "12-bit ceiling {twelve_bit_ceiling} is below the pipeline saturation threshold"
        );
        // The ADC range alone can never reach the threshold, so a driver that
        // published it would make saturation undetectable on a 12-bit QHY.
        let adc_range_only = |bits: u32| (1u32 << bits) - 1;
        assert!(adc_range_only(12) < PIPELINE_SATURATION_THRESHOLD);
    }

    /// get_status must reflect the locally-tracked cooler state
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
            "get_status must reflect tracked cooler_on=true"
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

    /// "no silent fallbacks": if the SDK call inside
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
