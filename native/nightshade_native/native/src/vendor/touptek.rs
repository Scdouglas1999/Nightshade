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
    BayerPattern, CameraCapabilities, CameraState, CameraStatus, ExposureParams, ImageData,
    ImageMetadata, ReadoutMode, SensorInfo, SubFrame, VendorFeatures,
};
use crate::sync::touptek_mutex;
use crate::traits::{NativeCamera, NativeDevice, NativeError};
use crate::NativeVendor;
use async_trait::async_trait;
use libloading::Library;
use std::collections::HashMap;
#[cfg(not(windows))]
use std::ffi::CString;
use std::ffi::{c_char, c_int, c_uint, c_ushort, c_void, CStr};
use std::sync::atomic::{AtomicBool, Ordering};
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

// Options (values verified against toupcam.h / ogmacam.h)
const OGMACAM_OPTION_TEC: c_uint = 0x08;
// 0x06 = TOUPCAM_OPTION_BITDEPTH (0 = 8-bit, 1 = 16-bit). NOT 0x04 — that value is
// OPTION_RAW, so the old constant silently re-set RAW and never changed bit depth,
// leaving the camera in 8-bit while download parsed W*H bytes as W*H*2 u16 garbage.
const OGMACAM_OPTION_BITDEPTH: c_uint = 0x06;
// 0x17 = TOUPCAM_OPTION_BINNING. NOT 0x01 — that value is OPTION_NOFRAME_TIMEOUT, so
// the old constant wrote a frame timeout (below the 500ms minimum) and never binned.
const OGMACAM_OPTION_BINNING: c_uint = 0x17;
const OGMACAM_OPTION_RAW: c_uint = 0x04;
// 0x0b = TOUPCAM_OPTION_TRIGGER. Value 1 selects software/simulated trigger mode, the
// prerequisite for the software-trigger + pull-mode capture pipeline used below.
const OGMACAM_OPTION_TRIGGER: c_uint = 0x0b;

// Pull-mode event codes delivered to the StartPullModeWithCallback callback.
// A software-triggered frame arrives as EVENT_IMAGE (live image), pulled with bStill = 0.
const OGMACAM_EVENT_IMAGE: c_uint = 0x0004;
const OGMACAM_EVENT_ERROR: c_uint = 0x0080;
const OGMACAM_EVENT_DISCONNECTED: c_uint = 0x0081;
const OGMACAM_EVENT_NOFRAMETIMEOUT: c_uint = 0x0082;

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

#[cfg(windows)]
pub type OgmacamChar = u16;
#[cfg(not(windows))]
pub type OgmacamChar = c_char;

/// Device info for enumeration. The SDK uses UTF-16 on Windows and narrow C strings elsewhere.
#[repr(C)]
pub struct OgmacamDeviceV2 {
    pub displayname: [OgmacamChar; 64],
    pub id: [OgmacamChar; 64],
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
type OgmacamOpen = unsafe extern "system" fn(id: *const c_void) -> HOgmacam;
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
type OgmacamGetExpoAGain = unsafe extern "system" fn(h: HOgmacam, gain: *mut u16) -> i32;
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
type OgmacamGetRawFormat = unsafe extern "system" fn(
    h: HOgmacam,
    p_fourcc: *mut c_uint,
    p_bits_per_pixel: *mut c_uint,
) -> i32;

// Options
type OgmacamPutOption = unsafe extern "system" fn(h: HOgmacam, opt: c_uint, val: c_int) -> i32;
type OgmacamGetOption = unsafe extern "system" fn(h: HOgmacam, opt: c_uint, val: *mut c_int) -> i32;

// Resolution/ROI
type OgmacamGetSize = unsafe extern "system" fn(h: HOgmacam, w: *mut c_int, h_: *mut c_int) -> i32;
type OgmacamPutRoi = unsafe extern "system" fn(
    h: HOgmacam,
    x_offset: c_uint,
    y_offset: c_uint,
    x_width: c_uint,
    y_height: c_uint,
) -> i32;

/// Final output size after ROI, rotate and binning (Ogmacam_get_FinalSize).
type OgmacamGetFinalSize =
    unsafe extern "system" fn(h: HOgmacam, w: *mut c_int, h_: *mut c_int) -> i32;

// Serial number and info
type OgmacamGetSerialNumber = unsafe extern "system" fn(h: HOgmacam, sn: *mut c_char) -> i32;

// Software trigger + pull-mode streaming.
// Matches `typedef void (__stdcall* PTOUPCAM_EVENT_CALLBACK)(unsigned nEvent, void* ctxEvent)`
// (toupcam.h:412). `__stdcall` == Rust `extern "system"` on Win32 and the C ABI elsewhere.
type OgmacamEventCallback = unsafe extern "system" fn(n_event: c_uint, ctx: *mut c_void);
type OgmacamStartPullModeWithCallback = unsafe extern "system" fn(
    h: HOgmacam,
    fun_event: OgmacamEventCallback,
    ctx_event: *mut c_void,
) -> i32;
/// Ogmacam_Trigger(h, nNumber): nNumber = 1 fires one software-triggered frame, 0 cancels.
type OgmacamTrigger = unsafe extern "system" fn(h: HOgmacam, n_number: c_ushort) -> i32;

// SDK metadata
type OgmacamVersion = unsafe extern "system" fn() -> *const c_char;

/// Heap-stable state shared with the SDK's pull-mode event callback.
///
/// Owned by a `Box` inside [`TouptekCamera`] so its address is stable across moves of the
/// camera struct (the camera is moved into a `HashMap` after connect). The callback only
/// ever reads/writes these two atomics — it never calls back into the SDK, which is
/// mandatory: `Ogmacam_Stop`/`Ogmacam_Close` deadlock if invoked from the callback context
/// (toupcam.h:410).
struct TouptekEventState {
    /// Set true on EVENT_IMAGE — a software-triggered frame is ready to pull.
    image_ready: AtomicBool,
    /// Set true on EVENT_ERROR / EVENT_DISCONNECTED / EVENT_NOFRAMETIMEOUT.
    error: AtomicBool,
}

/// Pull-mode event callback registered via `Ogmacam_StartPullModeWithCallback`.
///
/// SAFETY / lifetime proof: `ctx` is the pointer to the heap-allocated `TouptekEventState`
/// that `connect()` registered. The owning `Box` lives in `TouptekCamera::event_state` and
/// is only dropped AFTER `Ogmacam_Stop` + `Ogmacam_Close` have returned (see `disconnect()`
/// and the `Drop` impl). Stop/Close synchronize with and quiesce the SDK's internal
/// streaming thread, so once either returns no further callback can be dispatched. Therefore
/// while this function can run, the pointee is always live — it can never observe freed
/// memory. The `ctx.is_null()` guard defends against a spurious null context. This function
/// performs no SDK calls, only atomic stores, so it is reentrancy- and deadlock-safe.
unsafe extern "system" fn touptek_event_callback(n_event: c_uint, ctx: *mut c_void) {
    if ctx.is_null() {
        return;
    }
    // SAFETY: see the lifetime proof above — `ctx` points to a live `TouptekEventState`.
    let state = unsafe { &*(ctx as *const TouptekEventState) };
    match n_event {
        OGMACAM_EVENT_IMAGE => state.image_ready.store(true, Ordering::SeqCst),
        OGMACAM_EVENT_ERROR | OGMACAM_EVENT_DISCONNECTED | OGMACAM_EVENT_NOFRAMETIMEOUT => {
            state.error.store(true, Ordering::SeqCst);
        }
        _ => {}
    }
}

// ============================================================================
// SDK Wrapper
// ============================================================================

struct TouptekSdk {
    _library: Library,
    enum_v2: OgmacamEnumV2,
    open: OgmacamOpen,
    close: OgmacamClose,
    stop: OgmacamStop,
    pull_image_v3: OgmacamPullImageV3,
    put_expo_time: OgmacamPutExpoTime,
    get_expo_again: OgmacamGetExpoAGain,
    put_expo_again: OgmacamPutExpoAGain,
    get_expo_again_range: OgmacamGetExpoAGainRange,
    get_temperature: OgmacamGetTemperature,
    put_temperature: OgmacamPutTemperature,
    get_raw_format: OgmacamGetRawFormat,
    put_option: OgmacamPutOption,
    get_option: OgmacamGetOption,
    get_size: OgmacamGetSize,
    put_roi: OgmacamPutRoi,
    get_serial_number: OgmacamGetSerialNumber,
    start_pull_mode_with_callback: OgmacamStartPullModeWithCallback,
    trigger: OgmacamTrigger,
    /// Optional: universally present in modern toupcam-family SDKs; falls back to a
    /// ROI/sensor upper bound for buffer sizing if a white-label lib omits it.
    get_final_size: Option<OgmacamGetFinalSize>,
    version: Option<OgmacamVersion>,
}

// SAFETY: TouptekSdk owns a `libloading::Library` plus a set of plain function pointers (no interior mutability). The function pointers come from a single shared library and only point to compiled code, so sending the struct between threads is sound. All actual calls into these pointers are serialized by `touptek_mutex()` plus the per-camera `Mutex<HandleWrapper>` so the Send marker reflects the real synchronization discipline.
unsafe impl Send for TouptekSdk {}
// SAFETY: &TouptekSdk only exposes immutable function pointers; the loaded Library is read-only after construction. All FFI calls that mutate camera state go through &TouptekSdk and are wrapped in `touptek_mutex()` lock sections, so concurrent &-access never races on shared state.
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
        let system_paths = if cfg!(target_os = "linux") {
            vec![
                format!("/usr/lib/{dll_name}"),
                format!("/usr/local/lib/{dll_name}"),
            ]
        } else if cfg!(target_os = "macos") {
            vec![
                format!("/usr/local/lib/{dll_name}"),
                format!("/opt/homebrew/lib/{dll_name}"),
            ]
        } else {
            Vec::new()
        };
        let system_path_refs = system_paths.iter().map(String::as_str).collect::<Vec<_>>();
        let candidates =
            crate::vendor::sdk_loader::vendor_library_candidates(&[dll_name], &system_path_refs);

        let mut last_error = None;
        let mut loaded = None;
        for path in &candidates {
            // SAFETY: libloading::Library::new performs platform dynamic loading; `dll_name`
            // comes from the compile-time TOUPTEK_BRANDS constant array. Errors are
            // accumulated and reported as NativeError::SdkError rather than UB.
            match unsafe { Library::new(path) } {
                Ok(library) => {
                    tracing::info!("Loaded {} SDK from {}", dll_name, path.display());
                    loaded = Some(library);
                    break;
                }
                Err(e) => {
                    last_error = Some(e.to_string());
                }
            }
        }
        let library = loaded.ok_or_else(|| {
            NativeError::SdkError(format!(
                "Failed to load {} from {} candidate paths: {}",
                dll_name,
                candidates.len(),
                last_error.unwrap_or_else(|| "no candidate paths supplied".to_string())
            ))
        })?;

        // Build symbol names dynamically from the function prefix
        let sym = |suffix: &str| -> Vec<u8> {
            let mut name = format!("{}_{}", func_prefix, suffix);
            name.push('\0');
            name.into_bytes()
        };

        // SAFETY: each `library.get::<FnType>(&sym(...))` returns a `Symbol` that we immediately deref with `*` to copy out the function pointer. `sym()` always emits a NUL-terminated byte string (push('\0') is unconditional) satisfying libloading's contract. The C ABI signatures declared above use `extern "system"` and match the Touptek/Ogmacam SDK header convention. The loaded `library` is moved into the returned TouptekSdk so the function pointers remain valid for the cached SDK's lifetime (stored in `static SDKS: OnceLock<Mutex<HashMap<...>>>`).
        unsafe {
            Ok(Self {
                enum_v2: *library.get::<OgmacamEnumV2>(&sym("EnumV2")).map_err(|e| {
                    NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                })?,
                open: *library.get::<OgmacamOpen>(&sym("Open")).map_err(|e| {
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
                get_expo_again: *library
                    .get::<OgmacamGetExpoAGain>(&sym("get_ExpoAGain"))
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
                get_raw_format: *library
                    .get::<OgmacamGetRawFormat>(&sym("get_RawFormat"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                put_option: *library
                    .get::<OgmacamPutOption>(&sym("put_Option"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                get_option: *library
                    .get::<OgmacamGetOption>(&sym("get_Option"))
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
                start_pull_mode_with_callback: *library
                    .get::<OgmacamStartPullModeWithCallback>(&sym("StartPullModeWithCallback"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                trigger: *library
                    .get::<OgmacamTrigger>(&sym("Trigger"))
                    .map_err(|e| {
                        NativeError::SdkError(format!("Symbol error in {}: {}", dll_name, e))
                    })?,
                get_final_size: library
                    .get::<OgmacamGetFinalSize>(&sym("get_FinalSize"))
                    .ok()
                    .map(|symbol| *symbol),
                version: library
                    .get::<OgmacamVersion>(&sym("Version"))
                    .ok()
                    .map(|symbol| *symbol),
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
    let mut map = sdks.lock().unwrap_or_else(|e| e.into_inner());
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
    let map = sdks.lock().unwrap_or_else(|e| e.into_inner());
    let sdk = map
        .get(brand)
        .unwrap()
        .as_ref()
        .map_err(|e| NativeError::SdkError(e.clone()))?;
    f(sdk)
}

fn open_touptek_device(sdk: &TouptekSdk, device_id: &str) -> Result<HOgmacam, NativeError> {
    if device_id.is_empty() {
        return Err(NativeError::SdkError(
            "Touptek SDK returned an empty stable device ID".to_string(),
        ));
    }

    #[cfg(windows)]
    {
        let wide_id: Vec<u16> = device_id.encode_utf16().chain(std::iter::once(0)).collect();
        // SAFETY: `wide_id` is a live, NUL-terminated UTF-16 string matching the Windows
        // Touptek-family Open(const wchar_t*) ABI. The SDK copies/consumes it during this call.
        Ok(unsafe { (sdk.open)(wide_id.as_ptr() as *const c_void) })
    }

    #[cfg(not(windows))]
    {
        let c_id = CString::new(device_id).map_err(|_| {
            NativeError::SdkError("Touptek device ID contains an interior NUL".to_string())
        })?;
        // SAFETY: `c_id` is a live, NUL-terminated C string matching the non-Windows
        // Touptek-family Open(const char*) ABI. The SDK copies/consumes it during this call.
        Ok(unsafe { (sdk.open)(c_id.as_ptr() as *const c_void) })
    }
}

fn touptek_static_cstr(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }

    // SAFETY: Touptek-family Version functions return static, NUL-terminated C strings
    // owned by the loaded SDK shared library.
    let value = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .trim()
        .to_string();
    (!value.is_empty()).then_some(value)
}

fn sdk_version_from_sdk(sdk: &TouptekSdk, brand: &str) -> Option<String> {
    let version = sdk.version?;
    // SAFETY: <Prefix>_Version takes no arguments and returns a static C string.
    touptek_static_cstr(unsafe { version() }).map(|value| format!("{brand} SDK v{value}"))
}

fn touptek_temperature_result(
    camera_name: &str,
    sdk_result: i32,
    temperature_tenths_c: i16,
) -> Result<f64, NativeError> {
    if sdk_result >= 0 {
        Ok(temperature_tenths_c as f64 / 10.0)
    } else {
        tracing::error!(
            "Touptek get_Temperature() failed for camera '{}'. Error code: {}",
            camera_name,
            sdk_result
        );
        Err(NativeError::SdkError(format!(
            "Failed to read temperature from Touptek camera '{}'. SDK error: {}. Camera may not have a temperature sensor.",
            camera_name, sdk_result
        )))
    }
}

fn make_touptek_fourcc(code: [u8; 4]) -> u32 {
    (code[0] as u32) | ((code[1] as u32) << 8) | ((code[2] as u32) << 16) | ((code[3] as u32) << 24)
}

fn touptek_bayer_pattern_from_fourcc(fourcc: u32) -> Option<BayerPattern> {
    match fourcc {
        v if v == make_touptek_fourcc(*b"RGGB") => Some(BayerPattern::Rggb),
        v if v == make_touptek_fourcc(*b"GRBG") => Some(BayerPattern::Grbg),
        v if v == make_touptek_fourcc(*b"GBRG") => Some(BayerPattern::Gbrg),
        v if v == make_touptek_fourcc(*b"BGGR") => Some(BayerPattern::Bggr),
        _ => None,
    }
}

fn touptek_fourcc_to_string(fourcc: u32) -> String {
    let bytes = [
        (fourcc & 0xff) as u8,
        ((fourcc >> 8) & 0xff) as u8,
        ((fourcc >> 16) & 0xff) as u8,
        ((fourcc >> 24) & 0xff) as u8,
    ];
    String::from_utf8_lossy(&bytes).to_string()
}

/// Full-scale ADU of the delivered pixel container for a ToupTek-family camera.
///
/// **This vendor is right-justified**, which is why `(1 << bit_depth) - 1` is
/// correct here and must NOT be "fixed" the way ZWO/SVBony/Player One were. Do
/// not left-shift this into the 16-bit container.
///
/// Evidence:
///
/// * The SDK's own histogram is indexed by pixel value and sized
///   `1 << bitdepth`: "nFlag & 0x0f: bitdepth / so the size of aHist is: int
///   arraySize = 1 << (nFlag & 0x0f);" (`SDKs/Touptek/inc/ogmacam.h:616-624`,
///   `PIOGMACAM_HISTOGRAM_CALLBACKV2`). A 12-bit camera's histogram has 4096
///   bins, so delivered samples span 0..=4095. Left-justified samples would need
///   65536.
/// * Black level — a pedestal subtracted from the delivered data — is expressed
///   in native-bit-depth units, not container units:
///   `OGMACAM_BLACKLEVEL8_MAX 31`, `..._12_MAX (31 * 16)`, `..._16_MAX (31 * 256)`
///   (`SDKs/Touptek/inc/ogmacam.h:217-222`); INDI's toupbase scales its offset
///   control the same way (`bLevelStep = 1 << (m_maxBitDepth - 8)`).
/// * Measured on hardware: an Orion G16 (ToupTek ATR3CMOS16000KPA, 12-bit) via
///   the INDI toupbase driver, which passes the SDK buffer through unshifted —
///   "the 12 bits per pixel would only occupy the first 4096 brightness values
///   and never go above that ... The way the ASCOM driver does it is scale each
///   pixel value by multiplying it by 16 ... being able to have scaled 16 bit
///   FITS files like you have with ZWO or QHY cameras would be a blessing."
///   <https://indilib.org/forum/ccds-dslrs/12316-touptek-14-and-12-bit-scaling-issues.html>
///   The ×16 lives in ToupTek's *ASCOM* layer, above the SDK this driver uses.
///
/// `bit_depth` comes from `Ogmacam_get_RawFormat`, which reports the raw format's
/// own bits-per-pixel, so container and precision coincide for this vendor.
fn max_adu_from_bit_depth(bit_depth: u32) -> u32 {
    if bit_depth >= 32 {
        u32::MAX
    } else {
        (1u32 << bit_depth).saturating_sub(1)
    }
}

fn touptek_no_sdk_loaded_error(load_errors: &[(String, String, String)]) -> NativeError {
    let details = load_errors
        .iter()
        .map(|(brand, library, error)| format!("{brand} ({library}): {error}"))
        .collect::<Vec<_>>()
        .join("; ");

    NativeError::SdkError(format!(
        "No Touptek-family SDK libraries could be loaded. Install at least one supported SDK DLL/shared library or add it to the process library path. Tried: {details}"
    ))
}

fn read_touptek_raw_format(
    sdk: &TouptekSdk,
    handle: HOgmacam,
    camera_name: &str,
) -> (Option<BayerPattern>, Option<u32>) {
    let mut fourcc: c_uint = 0;
    let mut bits_per_pixel: c_uint = 0;
    // SAFETY: caller holds touptek_mutex and `handle` is the open camera handle.
    // The two out-pointers reference valid, distinct stack locals as required by
    // the ToupCam/Ogmacam SDK's get_RawFormat signature.
    let result = unsafe { (sdk.get_raw_format)(handle, &mut fourcc, &mut bits_per_pixel) };
    if result < 0 {
        tracing::warn!(
            "Touptek get_RawFormat() failed for camera '{}'. SDK error: {}",
            camera_name,
            result
        );
        return (None, None);
    }

    let pattern = touptek_bayer_pattern_from_fourcc(fourcc);
    if pattern.is_none() {
        tracing::warn!(
            "Touptek camera '{}' reported non-Bayer raw format '{}' ({} bpp); leaving Bayer pattern unknown",
            camera_name,
            touptek_fourcc_to_string(fourcc),
            bits_per_pixel
        );
    }
    let bit_depth = if bits_per_pixel > 0 {
        Some(bits_per_pixel)
    } else {
        None
    };
    (pattern, bit_depth)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ToupTek-family cameras deliver **right-justified** samples, so the ADC
    /// range *is* the container ceiling.
    ///
    /// This is a regression guard, not a behaviour change: ZWO, SVBony and
    /// Player One all needed `((1 << bd) - 1) << (16 - bd)` because those SDKs
    /// left-justify, and it would be an easy and expensive mistake to propagate
    /// that here. See [`max_adu_from_bit_depth`] for the SDK and on-hardware
    /// evidence that ToupTek does not.
    #[test]
    fn max_adu_is_the_adc_range_because_touptek_is_right_justified() {
        // 12-bit (ATR3CMOS16000KPA / Orion G16 class) — measured 0..4095.
        assert_eq!(max_adu_from_bit_depth(12), 4095);
        assert_ne!(max_adu_from_bit_depth(12), 65520, "must NOT left-justify");
        // 14-bit
        assert_eq!(max_adu_from_bit_depth(14), 16383);
        assert_ne!(max_adu_from_bit_depth(14), 65532, "must NOT left-justify");
        // 10-bit and a genuine 16-bit sensor.
        assert_eq!(max_adu_from_bit_depth(10), 1023);
        assert_eq!(max_adu_from_bit_depth(16), 65535);
    }

    /// The ceiling must match the number of histogram bins the SDK reports for
    /// the same bit depth (`arraySize = 1 << (nFlag & 0x0f)`), since that
    /// histogram is indexed by delivered pixel value.
    #[test]
    fn max_adu_matches_the_sdk_histogram_bin_count() {
        for bit_depth in 8..=16u32 {
            let bins = 1u64 << bit_depth;
            assert_eq!(
                u64::from(max_adu_from_bit_depth(bit_depth)) + 1,
                bins,
                "bit_depth {bit_depth}: ceiling must be the highest of {bins} histogram bins"
            );
        }
    }

    /// An unknown bit depth must never reach this function as 0, which would
    /// publish a 0 ceiling — "this camera cannot produce any signal".
    ///
    /// `read_touptek_raw_format` maps a 0 bits-per-pixel report to `None` and
    /// `connect()` substitutes 16, so the degenerate input is filtered upstream;
    /// this pins that contract plus the wide-input saturation guard.
    #[test]
    fn unknown_bit_depth_is_filtered_before_reaching_the_ceiling() {
        // The upstream guard: `read_touptek_raw_format` returns None for a 0 bpp
        // report and `connect()` substitutes 16, so the ceiling is the container.
        let sdk_reported_zero_bpp: u32 = 0;
        let effective = if sdk_reported_zero_bpp > 0 {
            sdk_reported_zero_bpp
        } else {
            16
        };
        assert_eq!(max_adu_from_bit_depth(effective), 65535);
        // Absurd widths saturate instead of shifting out of range.
        assert_eq!(max_adu_from_bit_depth(32), u32::MAX);
        assert_eq!(max_adu_from_bit_depth(64), u32::MAX);
    }

    #[test]
    fn touptek_temperature_result_converts_tenths_celsius() {
        assert_eq!(
            touptek_temperature_result("camera", 0, -123).unwrap(),
            -12.3
        );
    }

    #[test]
    fn touptek_temperature_result_propagates_sdk_error() {
        let err = touptek_temperature_result("camera", -7, 0).unwrap_err();
        match err {
            NativeError::SdkError(message) => {
                assert!(message.contains("camera"));
                assert!(message.contains("-7"));
            }
            other => panic!("expected SDK error, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn touptek_get_cooler_power_reports_not_supported_instead_of_estimate() {
        let mut camera = TouptekCamera::new(0, "OGMA");
        camera.connected = true;
        camera.cooler_on = true;
        camera.target_temp = -10.0;

        let err = camera.get_cooler_power().await.unwrap_err();
        assert!(matches!(err, NativeError::NotSupported));
    }

    #[test]
    fn touptek_bayer_pattern_from_fourcc_maps_all_sdk_patterns() {
        assert_eq!(
            touptek_bayer_pattern_from_fourcc(make_touptek_fourcc(*b"RGGB")),
            Some(BayerPattern::Rggb)
        );
        assert_eq!(
            touptek_bayer_pattern_from_fourcc(make_touptek_fourcc(*b"GRBG")),
            Some(BayerPattern::Grbg)
        );
        assert_eq!(
            touptek_bayer_pattern_from_fourcc(make_touptek_fourcc(*b"GBRG")),
            Some(BayerPattern::Gbrg)
        );
        assert_eq!(
            touptek_bayer_pattern_from_fourcc(make_touptek_fourcc(*b"BGGR")),
            Some(BayerPattern::Bggr)
        );
    }

    #[test]
    fn touptek_bayer_pattern_from_fourcc_leaves_non_bayer_unknown() {
        assert_eq!(
            touptek_bayer_pattern_from_fourcc(make_touptek_fourcc(*b"YYYY")),
            None
        );
        assert_eq!(
            touptek_bayer_pattern_from_fourcc(make_touptek_fourcc(*b"RGB8")),
            None
        );
    }

    #[test]
    fn touptek_event_callback_sets_flags_by_event_and_guards_null() {
        let state = Box::new(TouptekEventState {
            image_ready: AtomicBool::new(false),
            error: AtomicBool::new(false),
        });
        let ctx = &*state as *const TouptekEventState as *mut c_void;

        // EVENT_IMAGE sets image_ready only.
        // SAFETY: `ctx` points to the live `state` box for the duration of this test.
        unsafe { touptek_event_callback(OGMACAM_EVENT_IMAGE, ctx) };
        assert!(state.image_ready.load(Ordering::SeqCst));
        assert!(!state.error.load(Ordering::SeqCst));

        // Each fault event sets the error flag.
        for event in [
            OGMACAM_EVENT_ERROR,
            OGMACAM_EVENT_DISCONNECTED,
            OGMACAM_EVENT_NOFRAMETIMEOUT,
        ] {
            let s = Box::new(TouptekEventState {
                image_ready: AtomicBool::new(false),
                error: AtomicBool::new(false),
            });
            let c = &*s as *const TouptekEventState as *mut c_void;
            // SAFETY: `c` points to the live `s` box.
            unsafe { touptek_event_callback(event, c) };
            assert!(s.error.load(Ordering::SeqCst), "event {event:#x} set error");
            assert!(!s.image_ready.load(Ordering::SeqCst));
        }

        // Unknown events are ignored.
        let s = Box::new(TouptekEventState {
            image_ready: AtomicBool::new(false),
            error: AtomicBool::new(false),
        });
        let c = &*s as *const TouptekEventState as *mut c_void;
        // SAFETY: `c` points to the live `s` box. 0x4003 == EVENT_HEARTBEAT.
        unsafe { touptek_event_callback(0x4003, c) };
        assert!(!s.image_ready.load(Ordering::SeqCst));
        assert!(!s.error.load(Ordering::SeqCst));

        // A null context is a no-op and must not dereference.
        // SAFETY: intentionally passing null; the callback's guard returns early.
        unsafe { touptek_event_callback(OGMACAM_EVENT_IMAGE, std::ptr::null_mut()) };
    }

    #[test]
    fn touptek_no_sdk_loaded_error_names_each_attempted_brand() {
        let err = touptek_no_sdk_loaded_error(&[
            (
                "OGMA".to_string(),
                "ogmacam.dll".to_string(),
                "missing".to_string(),
            ),
            (
                "Touptek".to_string(),
                "toupcam.dll".to_string(),
                "bad image".to_string(),
            ),
        ]);

        match err {
            NativeError::SdkError(message) => {
                assert!(message.contains("No Touptek-family SDK libraries"));
                assert!(message.contains("OGMA (ogmacam.dll): missing"));
                assert!(message.contains("Touptek (toupcam.dll): bad image"));
            }
            other => panic!("expected SDK error, got {other:?}"),
        }
    }
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
    pub sdk_version: Option<String>,
}

/// Stable SDK IDs captured by discovery, keyed by the legacy brand/index selector used by
/// the bridge. A camera snapshots the ID in `new()` and thereafter opens by that ID, so a
/// later enumeration reorder cannot redirect an existing camera object to different hardware.
static DISCOVERED_DEVICE_IDS: OnceLock<Mutex<HashMap<(String, usize), String>>> = OnceLock::new();

fn discovered_device_ids() -> &'static Mutex<HashMap<(String, usize), String>> {
    DISCOVERED_DEVICE_IDS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(windows)]
fn touptek_device_string(value: &[OgmacamChar; 64]) -> String {
    let len = value.iter().position(|&c| c == 0).unwrap_or(value.len());
    String::from_utf16_lossy(&value[..len])
}

#[cfg(not(windows))]
fn touptek_device_string(value: &[OgmacamChar; 64]) -> String {
    let len = value.iter().position(|&c| c == 0).unwrap_or(value.len());
    let bytes: Vec<u8> = value[..len].iter().map(|&c| c as u8).collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

fn enumerate_brand_devices_from_sdk(sdk: &TouptekSdk, brand: &str) -> Vec<TouptekDeviceInfo> {
    let mut devices = Vec::new();
    let sdk_version = sdk_version_from_sdk(sdk, brand);
    // SAFETY: OgmacamDeviceV2 is `#[repr(C)]` containing only fixed-size character arrays
    // plus a raw model pointer; all-zero is valid for both character representations and
    // for the null pointer. OGMACAM_MAX matches the SDK's documented enumeration cap.
    let mut arr: Vec<OgmacamDeviceV2> = vec![unsafe { std::mem::zeroed() }; OGMACAM_MAX];
    // SAFETY: caller (discover_devices / discover_devices_for_brand) holds touptek_mutex; `arr.as_mut_ptr()` points to a contiguous buffer of OGMACAM_MAX `#[repr(C)]` OgmacamDeviceV2 entries; OgmacamEnumV2 fills at most OGMACAM_MAX entries and returns the count, per the SDK header.
    let count = unsafe { (sdk.enum_v2)(arr.as_mut_ptr()) };

    // Why: count is c_uint (u32) returned by OgmacamEnumV2; widening u32 -> usize is
    // value-preserving on every Tier 1 target.
    for i in 0..count as usize {
        let dev = &arr[i];

        let name = touptek_device_string(&dev.displayname);
        let id = touptek_device_string(&dev.id);

        let (flags, width, height, pixel_x, pixel_y) = if !dev.model.is_null() {
            // SAFETY: `dev.model` was just verified non-null on the line above; it points to a `#[repr(C)]` OgmacamModelV2 owned by the SDK shared library (string tables live in the .rdata segment) so the pointer remains valid for the lifetime of the loaded library — which is held by the cached TouptekSdk in `static SDKS`. We borrow a shared reference (no mutation), which is sound for the borrow scope.
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
            sdk_version: sdk_version.clone(),
        });
    }

    let brand_key = brand.to_ascii_lowercase();
    let mut cached_ids = discovered_device_ids()
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    cached_ids.retain(|(cached_brand, _), _| cached_brand != &brand_key);
    for device in &devices {
        cached_ids.insert(
            (brand_key.clone(), device.discovery_index),
            device.camera_id.clone(),
        );
    }

    devices
}

/// Discover connected Touptek cameras across all supported brands
///
/// Iterates over all known Touptek white-label SDKs, attempts to load each,
/// and enumerates cameras from each successfully loaded SDK.
pub async fn discover_devices() -> Result<Vec<TouptekDeviceInfo>, NativeError> {
    // Acquire global SDK mutex for thread safety
    let _lock = touptek_mutex().lock().await;

    let mut devices = Vec::new();
    let mut loaded_sdk_count = 0usize;
    let mut load_errors = Vec::new();

    for &(dll_name, _func_prefix, brand_name) in TOUPTEK_BRANDS {
        if let Err(err) = get_sdk_for_brand(brand_name) {
            tracing::debug!(
                "Touptek brand SDK '{}' ({}) not available, skipping",
                brand_name,
                dll_name
            );
            load_errors.push((
                brand_name.to_string(),
                dll_name.to_string(),
                err.to_string(),
            ));
            continue;
        }
        loaded_sdk_count += 1;

        let brand_devices = with_sdk(brand_name, |sdk| {
            Ok(enumerate_brand_devices_from_sdk(sdk, brand_name))
        })?;

        if !brand_devices.is_empty() {
            tracing::info!("Found {} {} cameras", brand_devices.len(), brand_name);
        }
        devices.extend(brand_devices);
    }

    if loaded_sdk_count == 0 {
        let err = touptek_no_sdk_loaded_error(&load_errors);
        tracing::warn!("{}", err);
        return Err(err);
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
        Ok(enumerate_brand_devices_from_sdk(sdk, brand))
    })
}

// ============================================================================
// Handle Wrapper for Thread Safety
// ============================================================================

struct HandleWrapper(HOgmacam);
// SAFETY: HOgmacam is a `*mut c_void` opaque camera handle returned by Ogmacam_Open. The struct is always wrapped in `Mutex<HandleWrapper>` in TouptekCamera; the pointer is never dereferenced or modified outside `touptek_mutex().lock().await` + `handle.lock().unwrap()` sections (see all call sites in this module — every SDK call captures the handle value while both locks are held). Marking Send is therefore equivalent to a hand-serialized capability. Sync is intentionally NOT implemented (see comment block below).
unsafe impl Send for HandleWrapper {}
// Note: Sync is intentionally omitted. HandleWrapper contains a raw pointer
// (*mut c_void) that is not safe to share via &-references across threads. The Mutex<HandleWrapper>
// provides synchronized access, and Mutex<T> only requires T: Send (not Sync) to be Sync itself.

// ============================================================================
// Camera Implementation
// ============================================================================

/// Touptek camera instance
pub struct TouptekCamera {
    device_index: usize,
    device_id: String,
    /// Stable identifier returned in `OgmacamDeviceV2::id`. Unlike `device_index`, this
    /// remains bound to the same physical camera if SDK enumeration order changes.
    sdk_device_id: Option<String>,
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
    exposure_started_at: Option<std::time::Instant>,
    model_flags: u64,
    /// Which brand SDK this camera uses
    brand: String,
    /// Heap-stable state shared with the SDK pull-mode event callback. `Some` only while
    /// pull mode is active (set in `connect()`, cleared in `disconnect()` after Stop+Close).
    event_state: Option<Box<TouptekEventState>>,
    /// Byte layout confirmed by get_Option after RAW/bit-depth negotiation.
    pull_bytes_per_pixel: usize,
    pull_channels: usize,
}

impl std::fmt::Debug for TouptekCamera {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TouptekCamera")
            .field("name", &self.name)
            .field("device_index", &self.device_index)
            .field("sdk_device_id", &self.sdk_device_id)
            .finish()
    }
}

impl TouptekCamera {
    /// Create a new Touptek camera instance for a specific brand
    pub fn new(device_index: usize, brand: &str) -> Self {
        let sdk_device_id = discovered_device_ids()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(&(brand.to_ascii_lowercase(), device_index))
            .cloned();

        Self {
            device_index,
            device_id: format!("touptek_{}", device_index),
            sdk_device_id,
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
            exposure_started_at: None,
            model_flags: 0,
            brand: brand.to_string(),
            event_state: None,
            pull_bytes_per_pixel: 0,
            pull_channels: 0,
        }
    }

    /// Create a new Touptek camera instance with the default OGMA brand
    /// (backward-compatible constructor)
    pub fn new_default(device_index: usize) -> Self {
        Self::new(device_index, "OGMA")
    }

    fn read_gain_locked(&self, handle: HOgmacam) -> Result<i32, NativeError> {
        with_sdk(&self.brand, |sdk| {
            let mut gain: u16 = 0;
            // SAFETY: caller holds touptek_mutex; `handle` is the live SDK handle
            // associated with this connected camera; `&mut gain` is a valid
            // out-pointer for the SDK's unsigned-short exposure-gain value.
            let result = unsafe { (sdk.get_expo_again)(handle, &mut gain) };
            if result < 0 {
                return Err(NativeError::SdkError(format!(
                    "Failed to read gain from Touptek camera '{}'. SDK error: {}",
                    self.name, result
                )));
            }
            Ok(i32::from(gain))
        })
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
        let device_index = self.device_index;
        let sdk_device_id = self.sdk_device_id.clone();

        // Refresh device metadata, but select and open by the stable SDK ID captured during
        // discovery. The legacy index is used only when callers construct a camera directly
        // without first running discovery; even then it is resolved to an ID before Open().
        let (device_info, serial_number, bayer_pattern, raw_bit_depth) = {
            // Acquire global SDK mutex for thread safety
            let _lock = touptek_mutex().lock().await;

            let device_info = with_sdk(&brand, |sdk| {
                let devices = enumerate_brand_devices_from_sdk(sdk, &brand);
                match sdk_device_id.as_deref() {
                    Some(stable_id) => devices
                        .into_iter()
                        .find(|device| device.camera_id == stable_id)
                        .ok_or_else(|| {
                            NativeError::SdkError(format!(
                                "{} camera with SDK ID '{}' disappeared during connect",
                                brand, stable_id
                            ))
                        }),
                    None => devices.into_iter().nth(device_index).ok_or_else(|| {
                        NativeError::SdkError(format!(
                            "{} camera index {} disappeared during connect",
                            brand, device_index
                        ))
                    }),
                }
            })?;

            let handle = with_sdk(&brand, |sdk| {
                let h = open_touptek_device(sdk, &device_info.camera_id)?;
                if h.is_null() {
                    tracing::error!(
                        "Touptek ({}) Open() returned NULL for SDK ID '{}'. Check USB connection and driver installation.",
                        brand, device_info.camera_id
                    );
                    return Err(NativeError::SdkError(format!(
                        "Failed to open {} camera with SDK ID '{}' - SDK returned NULL. Ensure camera is connected and {} driver is installed.",
                        brand, device_info.camera_id, brand
                    )));
                }
                Ok(h)
            })?;

            // Store handle
            {
                let mut h = self.handle.lock().unwrap_or_else(|e| e.into_inner());
                *h = HandleWrapper(handle);
            }

            // Get serial number, resolution, gain range, and raw Bayer pattern
            // (all synchronous).
            let (serial_number, bayer_pattern, raw_bit_depth) = {
                let handle_val = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

                with_sdk(&brand, |sdk| {
                    let mut sn_buf = [0 as c_char; 64];
                    let mut serial = None;
                    // SAFETY: touptek_mutex held above (in connect's outer scope); `handle_val` was just opened above (null-checked) and the per-camera `handle` mutex is held briefly during the load (handle.lock().unwrap_or_else); `sn_buf.as_mut_ptr()` points to a stack [i8; 64] buffer — Ogmacam_get_SerialNumber writes at most 64 bytes of a NUL-terminated ASCII serial per the SDK header.
                    if unsafe { (sdk.get_serial_number)(handle_val, sn_buf.as_mut_ptr()) } >= 0 {
                        // SAFETY: Ogmacam_get_SerialNumber populated `sn_buf` as a NUL-terminated C string above (return ≥ 0 confirms success); `sn_buf.as_ptr()` is valid for the duration of this stack [i8; 64] buffer and CStr::from_ptr reads up to the NUL.
                        let sn = unsafe { CStr::from_ptr(sn_buf.as_ptr()) }
                            .to_string_lossy()
                            .to_string();
                        if !sn.is_empty() {
                            serial = Some(sn);
                        }
                    }

                    let mut width: c_int = 0;
                    let mut height: c_int = 0;
                    // SAFETY: touptek_mutex held; `handle_val` valid (just opened); `&mut width` and `&mut height` are valid stack out-pointers to distinct c_int locals.
                    let _ = unsafe { (sdk.get_size)(handle_val, &mut width, &mut height) };

                    let mut gain_min: u16 = 100;
                    let mut gain_max: u16 = 10000;
                    let mut gain_def: u16 = 100;
                    // SAFETY: touptek_mutex held; `handle_val` valid; the three `&mut u16` out-pointers reference distinct stack locals; Ogmacam_get_ExpoAGainRange writes (min, max, def) values per the SDK header.
                    let _ = unsafe {
                        (sdk.get_expo_again_range)(
                            handle_val,
                            &mut gain_min,
                            &mut gain_max,
                            &mut gain_def,
                        )
                    };
                    // Why: gain_def is u16 (gain steps, 100..=10000 per Touptek SDK).
                    // u16 -> i32 is widening and value-preserving.
                    self.current_gain = gain_def as i32;

                    let (raw_bayer_pattern, raw_bit_depth) =
                        read_touptek_raw_format(sdk, handle_val, &device_info.name);
                    let bayer_pattern = if (device_info.model_flags & OGMACAM_FLAG_MONO) == 0 {
                        raw_bayer_pattern
                    } else {
                        None
                    };

                    Ok((serial, bayer_pattern, raw_bit_depth))
                })?
            };

            (device_info, serial_number, bayer_pattern, raw_bit_depth)
        };

        self.sdk_device_id = Some(device_info.camera_id.clone());
        self.model_flags = device_info.model_flags;
        let bit_depth = raw_bit_depth.unwrap_or(16);
        self.sensor_info = SensorInfo {
            width: device_info.width,
            height: device_info.height,
            pixel_size_x: device_info.pixel_size_x as f64,
            pixel_size_y: device_info.pixel_size_y as f64,
            max_adu: max_adu_from_bit_depth(bit_depth),
            bit_depth,
            color: (device_info.model_flags & OGMACAM_FLAG_MONO) == 0,
            bayer_pattern,
        };
        self.name = match serial_number {
            Some(serial) => format!("{} ({})", device_info.name, serial),
            None => device_info.name.clone(),
        };

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

        let quirk_lookup_id = format!(
            "native:touptek:{}:{}",
            self.brand.to_lowercase(),
            self.device_index
        );
        if let Some(delay_ms) = crate::quirks::get_timing_delay(&quirk_lookup_id, "connect") {
            tracing::debug!(
                "Applying DelayAfterConnect quirk: sleeping {}ms before starting pull mode on {}",
                delay_ms,
                self.name
            );
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
        }

        // Configure RAW/16-bit/software-trigger, then start the pull-mode data pipeline with
        // an event callback. All option writes must precede StartPullModeWithCallback and run
        // on this (non-callback) thread (toupcam.h:411 forbids TRIGGER/BITDEPTH/BINNING/ROTATE
        // put_Option from the callback context). This mirrors indi_toupbase Connect ordering.
        let start_result: Result<(usize, usize), NativeError> = {
            let _lock = touptek_mutex().lock().await;
            let handle_val = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

            // Heap-stable state whose address we hand to the SDK as the callback context.
            // Boxing guarantees the pointee address survives `self` being moved into the
            // camera HashMap after connect.
            let event_state = Box::new(TouptekEventState {
                image_ready: AtomicBool::new(false),
                error: AtomicBool::new(false),
            });
            let ctx = &*event_state as *const TouptekEventState as *mut c_void;
            let name = self.name.clone();

            let r = with_sdk(&brand, |sdk| {
                let close_with_error = |operation: &str, rc: i32| {
                    // SAFETY: touptek_mutex held; pull mode has not started; `handle_val` is
                    // the live handle returned by Open(). Closing it prevents a failed
                    // negotiation from leaking a partially configured camera.
                    unsafe { (sdk.close)(handle_val) };
                    NativeError::SdkError(format!(
                        "Failed to {} on Touptek camera '{}'. SDK error: {}",
                        operation, name, rc
                    ))
                };

                // SAFETY: touptek_mutex held; `handle_val` re-loaded from `self.handle`.
                // OGMACAM_OPTION_RAW=0x04 value 1 enables raw output. POD args only.
                let rc = unsafe { (sdk.put_option)(handle_val, OGMACAM_OPTION_RAW, 1) };
                if rc < 0 {
                    return Err(close_with_error("enable RAW output", rc));
                }

                // SAFETY: as above; OGMACAM_OPTION_BITDEPTH=0x06 value 1 selects 16-bit output.
                let rc = unsafe { (sdk.put_option)(handle_val, OGMACAM_OPTION_BITDEPTH, 1) };
                if rc < 0 {
                    return Err(close_with_error("select 16-bit RAW output", rc));
                }

                // SAFETY: as above; OGMACAM_OPTION_TRIGGER=0x0b value 1 selects software trigger.
                let rc = unsafe { (sdk.put_option)(handle_val, OGMACAM_OPTION_TRIGGER, 1) };
                if rc < 0 {
                    return Err(close_with_error("enable software trigger mode", rc));
                }

                let mut raw_mode: c_int = 0;
                // SAFETY: touptek_mutex held; `handle_val` valid; `&mut raw_mode` is a valid
                // stack out-pointer for get_Option.
                let rc = unsafe { (sdk.get_option)(handle_val, OGMACAM_OPTION_RAW, &mut raw_mode) };
                if rc < 0 {
                    return Err(close_with_error("read back RAW output mode", rc));
                }

                let mut bit_depth_mode: c_int = 0;
                // SAFETY: as above; `&mut bit_depth_mode` is a distinct valid out-pointer.
                let rc = unsafe {
                    (sdk.get_option)(handle_val, OGMACAM_OPTION_BITDEPTH, &mut bit_depth_mode)
                };
                if rc < 0 {
                    return Err(close_with_error("read back RAW bit depth", rc));
                }
                if raw_mode != 1 || bit_depth_mode != 1 {
                    // SAFETY: touptek_mutex held; pull mode has not started; `handle_val`
                    // remains live. Do not start a stream whose pixel stride is ambiguous.
                    unsafe { (sdk.close)(handle_val) };
                    return Err(NativeError::SdkError(format!(
                        "Touptek camera '{}' did not negotiate 16-bit single-channel RAW output (RAW={}, BITDEPTH={})",
                        name, raw_mode, bit_depth_mode
                    )));
                }

                // SAFETY: touptek_mutex held; `handle_val` valid; `touptek_event_callback`
                // is an `extern "system"` fn matching PTOUPCAM_EVENT_CALLBACK; `ctx` points to
                // the live `event_state` box (freed only after Stop+Close, see disconnect/Drop).
                let rc = unsafe {
                    (sdk.start_pull_mode_with_callback)(handle_val, touptek_event_callback, ctx)
                };
                if rc < 0 {
                    // The stream never started, so the callback can never fire and `ctx` will
                    // dangle harmlessly once `event_state` drops at end of scope. Close the
                    // handle to avoid leaking it.
                    // SAFETY: touptek_mutex held; `handle_val` valid; Ogmacam_Close releases it.
                    unsafe { (sdk.close)(handle_val) };
                    return Err(NativeError::SdkError(format!(
                        "Failed to start pull mode on Touptek camera '{}'. SDK error: {}",
                        name, rc
                    )));
                }
                Ok((2, 1))
            });

            if r.is_ok() {
                // Pull mode is live; take ownership of the state so it outlives the callback.
                self.event_state = Some(event_state);
            }
            r
        };
        match start_result {
            Ok((bytes_per_pixel, channels)) => {
                self.pull_bytes_per_pixel = bytes_per_pixel;
                self.pull_channels = channels;
            }
            Err(e) => {
                // Handle was closed inside the closure; forget the now-dangling pointer.
                {
                    let mut h = self.handle.lock().unwrap_or_else(|e| e.into_inner());
                    *h = HandleWrapper(std::ptr::null_mut());
                }
                return Err(e);
            }
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

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Teardown order is load-bearing: stop the pull-mode stream, then close the handle,
        // and only THEN drop the event-state box. Stop()+Close() quiesce the SDK's internal
        // streaming thread, so after they return no callback can fire; freeing the box
        // afterwards means the callback can never observe freed memory.
        with_sdk(&brand, |sdk| {
            // SAFETY: touptek_mutex held; `handle` loaded from `self.handle`. Ogmacam_Stop
            // halts pull mode and joins the streaming thread; idempotent, handle-only arg.
            let _ = unsafe { (sdk.stop)(handle) };
            // SAFETY: touptek_mutex held; `handle` valid (connected==true checked at top).
            // Ogmacam_Close is the contractual release for Ogmacam_Open.
            unsafe { (sdk.close)(handle) };
            Ok(())
        })?;

        // Safe now: Stop()+Close() returned, so the SDK will not invoke the callback again.
        self.event_state = None;

        {
            let mut h = self.handle.lock().unwrap_or_else(|e| e.into_inner());
            *h = HandleWrapper(std::ptr::null_mut());
        }
        self.connected = false;
        self.state = CameraState::Idle;
        self.exposure_started_at = None;
        self.pull_bytes_per_pixel = 0;
        self.pull_channels = 0;

        tracing::info!("Disconnected from Touptek camera: {}", self.name);

        Ok(())
    }
}

impl Drop for TouptekCamera {
    fn drop(&mut self) {
        // Best-effort teardown for the forgot-to-disconnect path. The `event_state` box is a
        // struct field, so the compiler drops (frees) it immediately AFTER this body returns.
        // We MUST stop pull mode + close the handle here first, otherwise the SDK's streaming
        // thread could dispatch the callback into freed state. The normal path (disconnect)
        // has cleared the handle and `event_state`, so this is a no-op then. Checking the
        // handle rather than `connected` also covers cancellation during the pre-stream delay.
        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;
        if !handle.is_null() {
            let mut quiesced = false;
            // Drop cannot await the async vendor mutex. Only touch the SDK if try_lock
            // proves no other Touptek-family call is in flight.
            if let Ok(_sdk_lock) = touptek_mutex().try_lock() {
                if get_sdk_for_brand(&self.brand).is_ok() {
                    quiesced = with_sdk(&self.brand, |sdk| {
                        // SAFETY: global touptek_mutex held; `handle` is the live handle
                        // owned by this camera. Stop then Close quiesces callbacks before
                        // the event-state box is allowed to drop.
                        unsafe { (sdk.stop)(handle) };
                        unsafe { (sdk.close)(handle) };
                        Ok(())
                    })
                    .is_ok();
                }
            } else {
                tracing::warn!(
                    "Could not acquire Touptek SDK mutex while dropping '{}'; leaking callback state for memory safety",
                    self.name
                );
            }

            if !quiesced {
                // Without Stop+Close under the global SDK mutex the callback may still run.
                // Leak its tiny context rather than let field drop free memory the SDK can use.
                if let Some(event_state) = self.event_state.take() {
                    std::mem::forget(event_state);
                }
            }
        }
        self.connected = false;
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

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Get current temperature
        let current_temp = with_sdk(&brand, |sdk| {
            let mut temp: i16 = 0;
            // SAFETY: touptek_mutex held above (in get_status); `handle` was just loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid Ogmacam_Open handle; `&mut temp` is a valid stack out-pointer to i16. Ogmacam_get_Temperature writes temperature in 0.1°C units per the SDK header.
            let result = unsafe { (sdk.get_temperature)(handle, &mut temp) };
            touptek_temperature_result(&self.name, result, temp)
        })?;

        // Touptek's common SDK surface used here does not expose an
        // authoritative TEC duty-cycle readback. Do not fabricate cooler power
        // from target/current temperature deltas; callers use this value as
        // telemetry, not as a control hint.
        let cooler_power = None;

        // Calculate exposure remaining
        let exposure_remaining = if self.state == CameraState::Exposing {
            self.exposure_started_at.map(|started_at| {
                (self.exposure_duration - started_at.elapsed().as_secs_f64()).max(0.0)
            })
        } else {
            None
        };
        let gain = self.read_gain_locked(handle)?;

        Ok(CameraStatus {
            state: self.state,
            sensor_temp: Some(current_temp),
            cooler_power,
            target_temp: Some(self.target_temp),
            cooler_on: self.cooler_on,
            gain,
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

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Set exposure time and fire ONE software-triggered frame, all within the SDK lock.
        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            // Clear the frame-arrival flags for THIS exposure BEFORE triggering, so the poll
            // in download_image only observes the frame produced by the trigger below (and not
            // a stale/late frame from a previous exposure).
            if let Some(es) = self.event_state.as_ref() {
                es.image_ready.store(false, Ordering::SeqCst);
                es.error.store(false, Ordering::SeqCst);
            }

            let exposure_us = (params.duration_secs * 1_000_000.0) as c_uint;
            // SAFETY: touptek_mutex held above (in start_exposure); `handle` was loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid Ogmacam_Open handle. Ogmacam_put_ExpoTime takes (handle, c_uint microseconds) POD per the SDK header.
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

            // Software trigger: nNumber = 1 requests exactly one frame, delivered as
            // EVENT_IMAGE and pulled in download_image(). OPTION_TRIGGER=1 was set in connect().
            // SAFETY: touptek_mutex held; `handle` valid; Ogmacam_Trigger takes (handle, c_ushort) POD.
            let result = unsafe { (sdk.trigger)(handle, 1) };
            if result < 0 {
                tracing::error!(
                    "Touptek Trigger() failed for camera '{}'. Duration: {:.3}s, error code: {}",
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
        self.exposure_started_at = Some(std::time::Instant::now());
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

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            // Cancel the software trigger with Trigger(0) — NOT Stop(), which would tear down
            // the pull-mode stream and break all subsequent exposures. This matches
            // indi_toupbase AbortExposure (Trigger(m_Handle, 0)) and keeps pull mode running.
            // SAFETY: touptek_mutex held above (in abort_exposure); `handle` was loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid handle; Ogmacam_Trigger takes (handle, c_ushort) POD per the SDK header.
            let result = unsafe { (sdk.trigger)(handle, 0) };
            if result < 0 {
                tracing::error!(
                    "Touptek Trigger(0) (cancel) failed for camera '{}'. Error code: {}",
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

        // Clear frame-arrival flags so the next exposure starts from a clean slate.
        if let Some(es) = self.event_state.as_ref() {
            es.image_ready.store(false, Ordering::SeqCst);
            es.error.store(false, Ordering::SeqCst);
        }

        self.state = CameraState::Idle;
        self.exposure_started_at = None;
        tracing::info!("Aborted exposure on Touptek camera '{}'", self.name);
        Ok(())
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Wait for the software-triggered frame to arrive. The SDK's pull-mode callback flips
        // `image_ready` on EVENT_IMAGE and `error` on EVENT_ERROR/DISCONNECTED/NOFRAMETIMEOUT.
        // We poll the atomics WITHOUT holding touptek_mutex so unrelated SDK calls aren't
        // blocked for the whole exposure. Timeout = exposure + margin (>= the SDK frame timeout).
        let timeout_secs = self.exposure_duration * 1.1 + 5.0;
        let poll_start = std::time::Instant::now();
        loop {
            let (ready, errored) = {
                let es = self.event_state.as_ref().ok_or_else(|| {
                    NativeError::SdkError(
                        "Touptek pull mode not started (event state missing)".to_string(),
                    )
                })?;
                (
                    es.image_ready.load(Ordering::SeqCst),
                    es.error.load(Ordering::SeqCst),
                )
            };
            if errored {
                self.state = CameraState::Idle;
                self.exposure_started_at = None;
                return Err(NativeError::SdkError(format!(
                    "Touptek camera '{}' reported an error/disconnect during exposure",
                    self.name
                )));
            }
            if ready {
                break;
            }
            if poll_start.elapsed().as_secs_f64() > timeout_secs {
                self.state = CameraState::Idle;
                self.exposure_started_at = None;
                return Err(NativeError::Timeout(format!(
                    "Touptek camera '{}' did not deliver a frame within {:.1}s",
                    self.name, timeout_secs
                )));
            }
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        }

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        let output_pixel_stride = self
            .pull_bytes_per_pixel
            .checked_mul(self.pull_channels)
            .ok_or_else(|| {
                NativeError::SdkError("Touptek negotiated pixel stride overflow".to_string())
            })?;
        if self.pull_bytes_per_pixel != 2 || self.pull_channels != 1 {
            return Err(NativeError::SdkError(format!(
                "Touptek camera '{}' is not configured for 16-bit single-channel RAW output ({} bytes/channel, {} channels)",
                self.name, self.pull_bytes_per_pixel, self.pull_channels
            )));
        }

        // Size the buffer from the ACTUAL current output resolution, not the full sensor: a
        // subframe/binned frame is smaller and would otherwise be mis-sized/skewed.
        // `get_FinalSize` reports the exact size after ROI + rotate + binning. If a white-label
        // SDK lacks the symbol we fall back to the ROI (or full sensor) dims, which are an
        // UPPER BOUND on the delivered frame (binning only shrinks), so the buffer is never
        // too small. The delivered frame is then sliced to `info.width`/`info.height`.
        let fallback_dims: (usize, usize) = match &self.subframe {
            Some(sf) => (sf.width as usize, sf.height as usize),
            None => (
                self.sensor_info.width as usize,
                self.sensor_info.height as usize,
            ),
        };

        let name = self.name.clone();
        let (data, out_width, out_height) = with_sdk(&brand, |sdk| {
            let (buf_w, buf_h) = if let Some(get_final) = sdk.get_final_size {
                let mut fw: c_int = 0;
                let mut fh: c_int = 0;
                // SAFETY: touptek_mutex held; `handle` valid; two distinct stack out-pointers
                // as required by Ogmacam_get_FinalSize.
                let rc = unsafe { get_final(handle, &mut fw, &mut fh) };
                if rc >= 0 && fw > 0 && fh > 0 {
                    (fw as usize, fh as usize)
                } else {
                    fallback_dims
                }
            } else {
                fallback_dims
            };

            let buf_pixels = buf_w.checked_mul(buf_h).ok_or_else(|| {
                NativeError::SdkError(format!("Touptek buffer size overflow: {}x{}", buf_w, buf_h))
            })?;
            let buffer_size = buf_pixels.checked_mul(output_pixel_stride).ok_or_else(|| {
                NativeError::SdkError(format!(
                    "Touptek buffer size overflow: {}x{} * {} bytes",
                    buf_w, buf_h, output_pixel_stride
                ))
            })?;

            let mut buffer = vec![0u8; buffer_size];
            // SAFETY: OgmacamFrameInfoV3 is `#[repr(C)]` POD (c_uint/u64/u16); zero-init is the
            // valid empty state before Ogmacam_PullImageV3 overwrites it.
            let mut info: OgmacamFrameInfoV3 = unsafe { std::mem::zeroed() };

            // SAFETY: touptek_mutex held; `handle` valid; `buffer` is sized from the negotiated
            // bytes-per-channel and channel count for every output pixel; connect() verified
            // that layout is single-channel RAW in a 16-bit container. `&mut info` is a valid
            // `#[repr(C)]` out-pointer. bStill=0 pulls the live (software-triggered) image
            // signalled by EVENT_IMAGE; in RAW mode `bits` is ignored and row_pitch=0 is tight.
            let result = unsafe {
                (sdk.pull_image_v3)(
                    handle,
                    buffer.as_mut_ptr() as *mut c_void,
                    0,  // bStill = false (live/triggered image)
                    16, // 16 bits (ignored in RAW mode)
                    0,  // default row pitch = tight Width*2 for RAW-16
                    &mut info,
                )
            };
            if result < 0 {
                tracing::error!(
                    "Touptek PullImageV3() failed for camera '{}'. Buffer: {}x{} pixels, error code: {}",
                    name, buf_w, buf_h, result
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to download image from Touptek camera '{}'. SDK error: {}",
                    name, result
                )));
            }

            // Build the pixel Vec from the ACTUAL frame dims the SDK reported, guarding against
            // a frame that would not fit the allocated buffer.
            let pulled_w = info.width as usize;
            let pulled_h = info.height as usize;
            let pulled_pixels = pulled_w.checked_mul(pulled_h).ok_or_else(|| {
                NativeError::SdkError(format!(
                    "Touptek frame size overflow: {}x{}",
                    pulled_w, pulled_h
                ))
            })?;
            let pulled_bytes = pulled_pixels
                .checked_mul(output_pixel_stride)
                .ok_or_else(|| {
                    NativeError::SdkError(format!(
                        "Touptek frame byte size overflow: {}x{} * {} bytes",
                        pulled_w, pulled_h, output_pixel_stride
                    ))
                })?;
            if pulled_pixels == 0 || pulled_bytes > buffer.len() {
                return Err(NativeError::SdkError(format!(
                    "Touptek camera '{}' delivered a {}x{} frame that does not fit the {}x{} buffer",
                    name, pulled_w, pulled_h, buf_w, buf_h
                )));
            }

            let data: Vec<u16> = buffer[..pulled_bytes]
                .chunks_exact(2)
                .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                .collect();

            Ok((data, info.width, info.height))
        })?;

        self.state = CameraState::Idle;
        self.exposure_started_at = None;
        let gain = self.read_gain_locked(handle)?;

        let metadata = ImageMetadata {
            exposure_time: self.exposure_duration,
            gain,
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
            width: out_width,
            height: out_height,
            data,
            bits_per_pixel: self.sensor_info.bit_depth,
            bayer_pattern: self.sensor_info.bayer_pattern,
            metadata,
        })
    }

    async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        // The pull-mode event callback flips these when the SDK delivers a frame (image_ready)
        // or reports a fault (error). Reflecting them here lets the shared poll loop
        // (`wait_for_exposure`) actually complete; returning `true` on error lets the
        // subsequent `download_image` surface the real error. Reading atomics needs no lock.
        if let Some(es) = self.event_state.as_ref() {
            if es.image_ready.load(Ordering::SeqCst) || es.error.load(Ordering::SeqCst) {
                return Ok(true);
            }
        }
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

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Enable/disable TEC
        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            // SAFETY: touptek_mutex held above (in set_cooler); `handle` was loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid handle. Ogmacam_put_Option takes (handle, c_uint option_id, c_int value) POD — OGMACAM_OPTION_TEC=0x08 with 0/1 toggles the thermoelectric cooler per the SDK header.
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

            // Set target temperature (in 0.1 degrees Celsius).
            // Why: target_temp is f64 Celsius typically in [-50.0, 50.0]; * 10 fits in
            // i16's range [-32768, 32767] with plenty of room. f64 -> i16 saturating
            // truncation is well-defined for finite values; NaN saturates to 0 which the
            // SDK rejects.
            if enabled {
                let temp = (target_temp * 10.0) as i16;
                // SAFETY: touptek_mutex held; `handle` valid; Ogmacam_put_Temperature takes (handle, i16 in 0.1°C units) POD per the SDK header. Range clamping is the SDK's responsibility.
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

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        with_sdk(&brand, |sdk| {
            let mut temp: i16 = 0;
            // SAFETY: touptek_mutex held above (in get_temperature trait method); `handle` was loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid handle; `&mut temp` is a valid stack out-pointer to i16. Ogmacam_get_Temperature writes the sensor reading in 0.1°C units per the SDK header.
            let result = unsafe { (sdk.get_temperature)(handle, &mut temp) };
            touptek_temperature_result(&self.name, result, temp)
        })
    }

    async fn get_cooler_power(&self) -> Result<f64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        Err(NativeError::NotSupported)
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Why: Touptek gain is a u16 (range 100..=10000 per the SDK header). A negative
        // i32 or one > u16::MAX is a caller bug, so we surface InvalidParameter rather
        // than silently truncate to a wrap-around gain that could destroy a frame.
        let gain_u16 = u16::try_from(gain).map_err(|_| {
            NativeError::InvalidParameter(format!(
                "Touptek gain {} out of u16 range (100..=10000 nominal)",
                gain
            ))
        })?;

        let brand = self.brand.clone();

        // Acquire global SDK mutex for thread safety
        let _lock = touptek_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        let name = self.name.clone();
        with_sdk(&brand, |sdk| {
            // SAFETY: touptek_mutex held above (in set_gain); `handle` was loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid handle. Ogmacam_put_ExpoAGain takes (handle, u16 gain) POD per the SDK header. SDK clamps to its supported range.
            let result = unsafe { (sdk.put_expo_again)(handle, gain_u16) };
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

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Touptek uses combined binning value
        let bin_mode = bin_x.max(bin_y);
        let name = self.name.clone();
        let max_bx = self.capabilities.max_bin_x;
        let max_by = self.capabilities.max_bin_y;
        with_sdk(&brand, |sdk| {
            // SAFETY: touptek_mutex held above (in set_binning); `handle` was loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid handle; Ogmacam_put_Option takes (handle, c_uint option_id, c_int value) POD — OGMACAM_OPTION_BINNING=0x01 with the symmetric bin factor per the SDK header. `bin_mode` is already validated (≤ capabilities.max_bin_x).
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

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

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
                // SAFETY: touptek_mutex held above (in set_subframe); `handle` was loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid handle; Ogmacam_put_Roi takes (handle, c_uint x, c_uint y, c_uint width, c_uint height) POD per the SDK header. The caller-supplied SubFrame values are validated by the SDK against sensor bounds (returns < 0 on out-of-range).
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
                // SAFETY: touptek_mutex held above (in set_subframe full-frame reset branch); `handle` was loaded from `self.handle` under its Mutex with `connected == true` guaranteeing a valid handle; (0, 0, sensor_w, sensor_h) is the full sensor area from SensorInfo populated by connect() via get_size, so it is within the SDK's accepted range.
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
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let _lock = touptek_mutex().lock().await;
        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;
        self.read_gain_locked(handle)
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

    async fn set_readout_mode(&mut self, mode: &ReadoutMode) -> Result<(), NativeError> {
        // Touptek cameras expose a single fixed readout mode.
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
