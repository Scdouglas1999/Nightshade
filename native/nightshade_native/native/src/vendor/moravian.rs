//! Moravian Instruments Camera Native Driver
//!
//! Provides FFI bindings to the current Moravian gxccd SDK (`libgxccd.so` /
//! `gxccd.dll`) used by G2/G3/G4/C-series cameras.
//!
//! ABI ground truth is the vendor header `gxccd.h`. The snake_case `gxccd_*`
//! API is handle-based: `gxccd_enumerate_usb(callback)` yields integer camera
//! IDs, `gxccd_initialize_usb(id)` returns an opaque `camera_t*` (NULL on
//! error), and `gxccd_release(cam)` tears it down. Every other call takes the
//! handle and returns `0` on success / `-1` on error (NOT a boolean TRUE); on
//! `-1` the human-readable reason is fetched with `gxccd_get_last_error()`.
//!
//! Capture model (gxccd.h:365-435): the ROI is supplied to
//! `gxccd_start_exposure(cam, seconds, use_shutter, x, y, w, h)` in *binned*
//! coordinates, the exposure is polled with `gxccd_image_ready(cam, &ready)`,
//! and the digitized frame is copied out with `gxccd_read_image(cam, buf, size)`
//! where `size = binned_w * binned_h * 2` bytes. The returned buffer is
//! bottom-up (pixel [0,0] at bottom-left, gxccd.h:416-434); we vertically mirror
//! it to the top-down orientation the rest of the pipeline expects, mirroring
//! the reference driver (indi-mi/mi_ccd.cpp `mirror_image`, lines 609-627,657).

use crate::camera::{
    BayerPattern, CameraCapabilities, CameraState, CameraStatus, ExposureParams, ImageData,
    ImageMetadata, ReadoutMode, SensorInfo, SubFrame, VendorFeatures,
};
use crate::sync::moravian_mutex;
use crate::traits::{NativeCamera, NativeDevice, NativeError};
use crate::utils::CleanupGuard;
use crate::NativeVendor;
use async_trait::async_trait;
use std::ffi::{c_char, c_double, c_float, c_int, c_void};
use std::sync::{Arc, Mutex};

// ============================================================================
// SDK Types and Constants
// ============================================================================

/// Camera handle type (opaque `camera_t`, gxccd.h:66).
type CCamera = c_void;
type PCCamera = *mut CCamera;

/// C `bool` (stdbool.h) is a single byte. We bind it as `u8` rather than Rust
/// `bool` so that reading an out-parameter the SDK may have written with any
/// non-`{0,1}` byte is never undefined behaviour; we treat `!= 0` as true and
/// pass `1`/`0` for in-parameters (ABI-identical 1-byte value).
type GxBool = u8;

// gxccd_get_boolean_parameter() indexes (gxccd.h:221-257).
const GBP_SUB_FRAME: c_int = 1;
const GBP_SHUTTER: c_int = 3;
const GBP_COOLER: c_int = 4;
const GBP_GUIDE: c_int = 7;
const GBP_GAIN: c_int = 13;
const GBP_RGB: c_int = 128;
const GBP_CMY: c_int = 129;
const GBP_CMYG: c_int = 130;
const GBP_DEBAYER_X_ODD: c_int = 131;
const GBP_DEBAYER_Y_ODD: c_int = 132;

// gxccd_get_integer_parameter() indexes (gxccd.h:262-293).
const GIP_CHIP_W: c_int = 1;
const GIP_CHIP_D: c_int = 2;
const GIP_PIXEL_W: c_int = 3;
const GIP_PIXEL_D: c_int = 4;
const GIP_MAX_BINNING_X: c_int = 5;
const GIP_MAX_BINNING_Y: c_int = 6;
const GIP_READ_MODES: c_int = 7;
const GIP_MAX_PIXEL_VALUE: c_int = 17;

// gxccd_get_string_parameter() indexes (gxccd.h:298-304).
const GSP_CAMERA_DESCRIPTION: c_int = 0;
const GSP_CAMERA_SERIAL: c_int = 2;

// gxccd_get_value() indexes (gxccd.h:313-326).
const GV_CHIP_TEMPERATURE: c_int = 0;
const GV_POWER_UTILIZATION: c_int = 11;

/// Warm-up target (deg C) high enough for the cooler to turn fully off.
/// Matches the reference driver's `TEMP_COOLER_OFF` (mi_ccd.cpp:35).
const TEMP_COOLER_OFF: c_float = 100.0;

/// Upper bound on how long we wait for the chip to finish digitizing after the
/// exposure integration elapses (readout can take many seconds on large CCDs).
const READOUT_TIMEOUT_SECS: u64 = 120;
/// Poll interval for `gxccd_image_ready` during readout. Kept coarse per the
/// header's admonition against busy-spinning (gxccd.h:400-404).
const READOUT_POLL_MS: u64 = 200;

/// Candidate shared-library names, tried in order. The reference driver links
/// `libgxccd`; Windows ships `gxccd.dll`.
const LIB_CANDIDATES: &[&str] = &[
    "gxccd.dll",
    "libgxccd.so",
    "libgxccd.so.2",
    "libgxccd.so.1",
    "libgxccd.dylib",
];

// ============================================================================
// SDK Function Types (signatures verbatim from gxccd.h)
// ============================================================================

/// `typedef void (*enum_callback_t)(int device_id);` (gxccd.h:63)
type EnumCallback = unsafe extern "C" fn(camera_id: c_int);
/// `void gxccd_enumerate_usb(enum_callback_t callback);` (gxccd.h:188)
type EnumerateUsb = unsafe extern "C" fn(callback: EnumCallback);
/// `camera_t *gxccd_initialize_usb(int camera_id);` (gxccd.h:202)
type InitializeUsb = unsafe extern "C" fn(camera_id: c_int) -> PCCamera;
/// `void gxccd_release(camera_t *camera);` (gxccd.h:211)
type Release = unsafe extern "C" fn(camera: PCCamera);
/// `int gxccd_get_boolean_parameter(camera_t*, int index, bool *value);` (gxccd.h:260)
type GetBooleanParameter =
    unsafe extern "C" fn(camera: PCCamera, index: c_int, value: *mut GxBool) -> c_int;
/// `int gxccd_get_integer_parameter(camera_t*, int index, int *value);` (gxccd.h:296)
type GetIntegerParameter =
    unsafe extern "C" fn(camera: PCCamera, index: c_int, value: *mut c_int) -> c_int;
/// `int gxccd_get_string_parameter(camera_t*, int index, char *buf, size_t size);` (gxccd.h:310)
type GetStringParameter =
    unsafe extern "C" fn(camera: PCCamera, index: c_int, buf: *mut c_char, size: usize) -> c_int;
/// `int gxccd_get_value(camera_t*, int index, float *value);` (gxccd.h:329)
type GetValue = unsafe extern "C" fn(camera: PCCamera, index: c_int, value: *mut c_float) -> c_int;
/// `int gxccd_set_temperature(camera_t*, float temp);` (gxccd.h:336)
type SetTemperature = unsafe extern "C" fn(camera: PCCamera, temp: c_float) -> c_int;
/// `int gxccd_set_binning(camera_t*, int x, int y);` (gxccd.h:349)
type SetBinning = unsafe extern "C" fn(camera: PCCamera, x: c_int, y: c_int) -> c_int;
/// `int gxccd_set_gain(camera_t*, uint16_t gain);` (gxccd.h:478)
type SetGain = unsafe extern "C" fn(camera: PCCamera, gain: u16) -> c_int;
/// `int gxccd_set_read_mode(camera_t*, int mode);` (gxccd.h:469)
type SetReadMode = unsafe extern "C" fn(camera: PCCamera, mode: c_int) -> c_int;
/// `int gxccd_enumerate_read_modes(camera_t*, int index, char *buf, size_t size);` (gxccd.h:462)
type EnumerateReadModes =
    unsafe extern "C" fn(camera: PCCamera, index: c_int, buf: *mut c_char, size: usize) -> c_int;
/// `int gxccd_start_exposure(camera_t*, double exp_time, bool use_shutter, int x, int y, int w, int h);` (gxccd.h:374)
type StartExposure = unsafe extern "C" fn(
    camera: PCCamera,
    exp_time: c_double,
    use_shutter: GxBool,
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
) -> c_int;
/// `int gxccd_abort_exposure(camera_t*, bool download);` (gxccd.h:391)
type AbortExposure = unsafe extern "C" fn(camera: PCCamera, download: GxBool) -> c_int;
/// `int gxccd_image_ready(camera_t*, bool *ready);` (gxccd.h:405)
type ImageReady = unsafe extern "C" fn(camera: PCCamera, ready: *mut GxBool) -> c_int;
/// `int gxccd_read_image(camera_t*, void *buf, size_t size);` (gxccd.h:435)
type ReadImage = unsafe extern "C" fn(camera: PCCamera, buf: *mut c_void, size: usize) -> c_int;
/// `void gxccd_get_last_error(camera_t*, char *buf, size_t size);` (gxccd.h:583)
type GetLastError = unsafe extern "C" fn(camera: PCCamera, buf: *mut c_char, size: usize);

// ============================================================================
// SDK Singleton
// ============================================================================

/// Candidate paths for the Moravian gxccd library, in search order.
fn moravian_candidate_paths() -> Vec<std::path::PathBuf> {
    crate::vendor::sdk_loader::vendor_library_candidates(LIB_CANDIDATES, &[])
}

crate::load_vendor_sdk! {
    /// Moravian gxccd SDK wrapper with dynamically loaded functions
    vendor_name: "Moravian",
    sdk_struct: MoravianSdk,
    sdk_static: SDK,
    candidate_paths_fn: moravian_candidate_paths,
    symbols: {
        enumerate_usb: b"gxccd_enumerate_usb\0" => EnumerateUsb,
        initialize_usb: b"gxccd_initialize_usb\0" => InitializeUsb,
        release: b"gxccd_release\0" => Release,
        get_boolean_parameter: b"gxccd_get_boolean_parameter\0" => GetBooleanParameter,
        get_integer_parameter: b"gxccd_get_integer_parameter\0" => GetIntegerParameter,
        get_string_parameter: b"gxccd_get_string_parameter\0" => GetStringParameter,
        get_value: b"gxccd_get_value\0" => GetValue,
        set_temperature: b"gxccd_set_temperature\0" => SetTemperature,
        set_binning: b"gxccd_set_binning\0" => SetBinning,
        set_gain: b"gxccd_set_gain\0" => SetGain,
        set_read_mode: b"gxccd_set_read_mode\0" => SetReadMode,
        enumerate_read_modes: b"gxccd_enumerate_read_modes\0" => EnumerateReadModes,
        start_exposure: b"gxccd_start_exposure\0" => StartExposure,
        abort_exposure: b"gxccd_abort_exposure\0" => AbortExposure,
        image_ready: b"gxccd_image_ready\0" => ImageReady,
        read_image: b"gxccd_read_image\0" => ReadImage,
        get_last_error: b"gxccd_get_last_error\0" => GetLastError,
    }
}

// SAFETY: MoravianSdk holds only function pointers and a `libloading::Library` (memory-mapped shared object). The function pointers reference code in a library kept alive for the program's lifetime (we store the Library). Every actual SDK call is serialized through `moravian_mutex()`, so the underlying gxccd SDK never sees concurrent invocation.
unsafe impl Send for MoravianSdk {}
// SAFETY: Same justification as `impl Send`: pointer-and-handle aggregate that becomes safe under the moravian_mutex serialization used by every call site.
unsafe impl Sync for MoravianSdk {}

fn get_sdk() -> Result<&'static MoravianSdk, NativeError> {
    MoravianSdk::get_or_reason().map_err(|reason| NativeError::SdkError(reason.to_string()))
}

/// Fetch the SDK's human-readable description of the last failing call.
///
/// SAFETY: caller must hold `moravian_mutex()` and pass a valid, initialized
/// camera handle. `gxccd_get_last_error` writes a NUL-terminated string of at
/// most `size` bytes into `buf`.
unsafe fn sdk_last_error(sdk: &MoravianSdk, handle: PCCamera) -> String {
    let mut buf = [0 as c_char; 256];
    (sdk.get_last_error)(handle, buf.as_mut_ptr(), buf.len());
    std::ffi::CStr::from_ptr(buf.as_ptr())
        .to_string_lossy()
        .trim()
        .to_string()
}

// ============================================================================
// Pure helpers (unit-tested)
// ============================================================================

/// Binned ROI in the coordinate system `gxccd_start_exposure` expects: origin
/// is bottom-up (y grows up), matching `gxccd_read_image`'s Cartesian output.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct BinnedRoi {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
}

/// Convert a top-down, unbinned subframe (or full frame) into the binned,
/// y-flipped ROI `gxccd_start_exposure` requires.
///
/// The reference driver does exactly this at mi_ccd.cpp:510-517:
/// send binned coords, then `fy = (YRes / binY) - y - h` because "libgxccd has
/// 0 on the bottom". The full-frame case collapses to `fy = 0` (unaffected).
fn compute_binned_roi(
    sensor_w: u32,
    sensor_h: u32,
    bin_x: u32,
    bin_y: u32,
    subframe: Option<(u32, u32, u32, u32)>,
) -> Result<BinnedRoi, String> {
    if bin_x == 0 || bin_y == 0 {
        return Err("binning must be >= 1".to_string());
    }
    let full_bw = sensor_w / bin_x;
    let full_bh = sensor_h / bin_y;

    // Subframe origin/size are top-down and in UNBINNED sensor pixels; divide by
    // the bin factor to reach binned coordinates (mi_ccd.cpp:510-513).
    let (xb, yb_top, wb, hb) = match subframe {
        Some((sx, sy, sw, sh)) => (sx / bin_x, sy / bin_y, sw / bin_x, sh / bin_y),
        None => (0, 0, full_bw, full_bh),
    };

    if wb == 0 || hb == 0 {
        return Err("ROI width/height must be > 0 after binning".to_string());
    }
    let x_end = xb
        .checked_add(wb)
        .ok_or_else(|| "ROI x extent overflow".to_string())?;
    let y_end = yb_top
        .checked_add(hb)
        .ok_or_else(|| "ROI y extent overflow".to_string())?;
    if x_end > full_bw || y_end > full_bh {
        return Err(format!(
            "ROI {}x{}+{}+{} exceeds binned sensor {}x{}",
            wb, hb, xb, yb_top, full_bw, full_bh
        ));
    }

    // Top-down y origin -> bottom-up y origin.
    let fy = full_bh - yb_top - hb;

    let to_i32 = |v: u32, what: &str| {
        i32::try_from(v).map_err(|_| format!("Moravian ROI {} value {} exceeds i32", what, v))
    };
    Ok(BinnedRoi {
        x: to_i32(xb, "x")?,
        y: to_i32(fy, "y")?,
        w: to_i32(wb, "w")?,
        h: to_i32(hb, "h")?,
    })
}

/// Vertically mirror a tightly-packed 16-bit image in place (row 0 <-> last
/// row). `gxccd_read_image` returns rows bottom-up (gxccd.h:416-434); the rest
/// of the pipeline expects top-down. Equivalent to mi_ccd.cpp `mirror_image`.
fn mirror_vertical_u16(buf: &mut [u16], width: usize, height: usize) {
    if width == 0 || height < 2 {
        return;
    }
    // Only touch the region we actually own; never index past the slice.
    if width.saturating_mul(height) > buf.len() {
        return;
    }
    for row in 0..(height / 2) {
        let top = row * width;
        let bot = (height - 1 - row) * width;
        for col in 0..width {
            buf.swap(top + col, bot + col);
        }
    }
}

/// RGB Bayer pattern implied by the debayer phase bits, expressed in the SDK's
/// *native* (bottom-up) orientation. `x_odd`/`y_odd` are `GBP_DEBAYER_X_ODD` /
/// `GBP_DEBAYER_Y_ODD` (gxccd.h:249-252).
fn native_bayer(x_odd: bool, y_odd: bool) -> BayerPattern {
    match (x_odd, y_odd) {
        (false, false) => BayerPattern::Rggb,
        (true, false) => BayerPattern::Grbg,
        (false, true) => BayerPattern::Gbrg,
        (true, true) => BayerPattern::Bggr,
    }
}

/// Adjust a Bayer pattern for the vertical mirror we apply to every frame.
/// Reversing the row order of an even-height frame swaps the two Bayer rows.
fn flip_bayer_vertical(p: BayerPattern) -> BayerPattern {
    match p {
        BayerPattern::Rggb => BayerPattern::Gbrg,
        BayerPattern::Gbrg => BayerPattern::Rggb,
        BayerPattern::Grbg => BayerPattern::Bggr,
        BayerPattern::Bggr => BayerPattern::Grbg,
    }
}

// ============================================================================
// Device Discovery
// ============================================================================

/// Active enumeration sink for SDK callbacks.
static ACTIVE_ENUMERATION_IDS: Mutex<Option<Arc<Mutex<Vec<c_int>>>>> = Mutex::new(None);

/// Callback for camera enumeration (`enum_callback_t`, gxccd.h:63).
unsafe extern "C" fn enumerate_callback(id: c_int) {
    let target = ACTIVE_ENUMERATION_IDS
        .lock()
        .ok()
        .and_then(|guard| guard.as_ref().cloned());
    if let Some(ids) = target {
        if let Ok(mut ids) = ids.lock() {
            ids.push(id);
        }
    }
}

/// Discovered Moravian camera info
#[derive(Debug, Clone)]
pub struct MoravianCameraInfo {
    pub camera_id: c_int,
    pub name: String,
    pub serial_number: Option<String>,
    pub discovery_index: usize,
}

/// Discover all connected Moravian cameras
pub async fn discover_devices() -> Result<Vec<MoravianCameraInfo>, NativeError> {
    let sdk = get_sdk()?;

    // Acquire global SDK mutex for thread safety
    let _lock = moravian_mutex().lock().await;

    let ids_sink = Arc::new(Mutex::new(Vec::new()));
    *ACTIVE_ENUMERATION_IDS
        .lock()
        .unwrap_or_else(|e| e.into_inner()) = Some(ids_sink.clone());

    // Enumerate cameras
    // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); ACTIVE_ENUMERATION_IDS has been set to `ids_sink` so the callback has a sink to push to; `enumerate_callback` is a properly declared `unsafe extern "C" fn(c_int)` matching the enum_callback_t typedef.
    unsafe { (sdk.enumerate_usb)(enumerate_callback) };
    *ACTIVE_ENUMERATION_IDS
        .lock()
        .unwrap_or_else(|e| e.into_inner()) = None;

    // Collect results
    let ids: Vec<c_int> = ids_sink.lock().unwrap_or_else(|e| e.into_inner()).clone();

    let mut devices = Vec::new();

    for (index, &id) in ids.iter().enumerate() {
        // Temporarily initialize to read camera info, then release.
        // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); `id` was just emitted by gxccd_enumerate_usb via enumerate_callback so it is a valid camera ID for gxccd_initialize_usb.
        let handle = unsafe { (sdk.initialize_usb)(id) };
        if handle.is_null() {
            continue;
        }

        // Get camera description
        let mut name_buf = [0 as c_char; 256];
        // SAFETY: moravian_mutex held; `handle` was just successfully initialized (non-null check above); name_buf is a 256-byte stack array and we pass its truthful length as `size_t` so the SDK cannot overrun.
        if unsafe {
            (sdk.get_string_parameter)(
                handle,
                GSP_CAMERA_DESCRIPTION,
                name_buf.as_mut_ptr(),
                name_buf.len(),
            )
        } >= 0
        {
            // SAFETY: name_buf is 256 bytes and the SDK guarantees NUL-termination within the buffer on success (>= 0) per gxccd.h:306-311.
            let name = unsafe { std::ffi::CStr::from_ptr(name_buf.as_ptr()) }
                .to_string_lossy()
                .trim()
                .to_string();

            // Get serial number
            let mut serial_buf = [0 as c_char; 64];
            // SAFETY: moravian_mutex held; `handle` is still the successfully-initialized one from above; serial_buf is 64 bytes and its truthful length is passed as `size_t`.
            let serial_number = if unsafe {
                (sdk.get_string_parameter)(
                    handle,
                    GSP_CAMERA_SERIAL,
                    serial_buf.as_mut_ptr(),
                    serial_buf.len(),
                )
            } >= 0
            {
                // SAFETY: serial_buf is 64 bytes; the SDK guarantees NUL-termination on success.
                let serial = unsafe { std::ffi::CStr::from_ptr(serial_buf.as_ptr()) }
                    .to_string_lossy()
                    .trim()
                    .to_string();
                if !serial.is_empty() {
                    Some(serial)
                } else {
                    None
                }
            } else {
                None
            };

            devices.push(MoravianCameraInfo {
                camera_id: id,
                name,
                serial_number,
                discovery_index: index,
            });
        }

        // Release temporary handle
        // SAFETY: moravian_mutex held; `handle` was successfully initialized at the top of this iteration; gxccd_release pairs with gxccd_initialize_usb per gxccd.h:206-211.
        unsafe { (sdk.release)(handle) };
    }

    Ok(devices)
}

// ============================================================================
// Handle Wrapper for Send + Sync
// ============================================================================

struct HandleWrapper(PCCamera);
// SAFETY: HandleWrapper wraps a raw `*mut c_void` camera handle. The handle is opaque to us — we never deref it. It is only handed back to the gxccd SDK functions, which serialize through `moravian_mutex()`, so no concurrent access ever happens to the underlying SDK state via this pointer.
unsafe impl Send for HandleWrapper {}
// SAFETY: Same justification as `impl Send`. The pointer is opaque and access to it is gated by both the wrapping `Mutex<HandleWrapper>` (held inside MoravianCamera) and the global `moravian_mutex()`.
unsafe impl Sync for HandleWrapper {}

// ============================================================================
// Camera Implementation
// ============================================================================

/// Moravian camera instance
pub struct MoravianCamera {
    camera_id: c_int,
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
    exposure_started_at: Option<std::time::Instant>,
    /// Binned (width, height) requested at the last `start_exposure`; used to
    /// size the `gxccd_read_image` buffer (which takes no ROI of its own).
    last_frame_dims: Option<(u32, u32)>,
}

impl std::fmt::Debug for MoravianCamera {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MoravianCamera")
            .field("name", &self.name)
            .field("camera_id", &self.camera_id)
            .finish()
    }
}

impl MoravianCamera {
    /// Create a new Moravian camera instance
    pub fn new(camera_id: c_int) -> Self {
        Self {
            camera_id,
            device_id: format!("moravian_{}", camera_id),
            name: format!("Moravian Camera {}", camera_id),
            handle: Mutex::new(HandleWrapper(std::ptr::null_mut())),
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
            target_temp: 0.0,
            exposure_duration: 0.0,
            exposure_started_at: None,
            last_frame_dims: None,
        }
    }
}

#[async_trait]
impl NativeDevice for MoravianCamera {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Moravian
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        if self.connected {
            return Ok(());
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        // Initialize camera (gxccd_initialize_usb returns NULL on failure).
        // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); `self.camera_id` was set at construction (from MoravianCameraInfo.camera_id emitted by gxccd_enumerate_usb); gxccd_initialize_usb takes the camera ID by value and returns a fresh handle (NULL on failure, checked below).
        let handle = unsafe { (sdk.initialize_usb)(self.camera_id) };
        if handle.is_null() {
            tracing::error!(
                "Moravian gxccd_initialize_usb() returned NULL for camera ID {}. Check USB connection and driver installation.",
                self.camera_id
            );
            return Err(NativeError::SdkError(format!(
                "Failed to initialize Moravian camera ID {} - SDK returned NULL handle. Ensure camera is connected and the gxccd driver is installed.",
                self.camera_id
            )));
        }

        let cleanup_guard = CleanupGuard::new(|| {
            // SAFETY: moravian_mutex remains held for this guard's lifetime and
            // handle was returned by the successful gxccd_initialize_usb call above.
            unsafe { (sdk.release)(handle) };
        });

        // Probe camera info before publishing the handle as connected.
        {
            // Name
            let mut name_buf = [0 as c_char; 256];
            // SAFETY: moravian_mutex held above; `handle` is the
            // just-successfully-initialized camera handle; name_buf is 256 bytes and
            // its truthful length is passed as `size_t`.
            if unsafe {
                (sdk.get_string_parameter)(
                    handle,
                    GSP_CAMERA_DESCRIPTION,
                    name_buf.as_mut_ptr(),
                    name_buf.len(),
                )
            } >= 0
            {
                // SAFETY: name_buf is 256 bytes; the SDK guarantees NUL-termination within on success.
                self.name = unsafe { std::ffi::CStr::from_ptr(name_buf.as_ptr()) }
                    .to_string_lossy()
                    .trim()
                    .to_string();
            }

            // Integer + boolean parameters. Every status must be checked: a
            // failed SDK query leaves its out-parameter unchanged.
            let mut width_i: c_int = 0;
            let mut height_i: c_int = 0;
            let mut pixel_w: c_int = 0;
            let mut pixel_d: c_int = 0;
            let mut max_bin_x: c_int = 1;
            let mut max_bin_y: c_int = 1;
            let mut max_pixel_value: c_int = 0;
            let mut is_rgb: GxBool = 0;
            let mut is_cmy: GxBool = 0;
            let mut is_cmyg: GxBool = 0;
            let mut deb_x_odd: GxBool = 0;
            let mut deb_y_odd: GxBool = 0;
            let mut has_cooler: GxBool = 0;
            let mut has_shutter: GxBool = 0;
            let mut has_guide: GxBool = 0;
            let mut has_gain: GxBool = 0;
            let mut has_subframe: GxBool = 0;

            let query_integer =
                |index: c_int, value: &mut c_int, name: &str| -> Result<(), NativeError> {
                    // SAFETY: moravian_mutex held; handle is initialized and value is a
                    // valid c_int out-pointer for gxccd_get_integer_parameter.
                    let result = unsafe { (sdk.get_integer_parameter)(handle, index, value) };
                    if result < 0 {
                        // SAFETY: handle remains valid on this error path.
                        let detail = unsafe { sdk_last_error(sdk, handle) };
                        return Err(NativeError::SdkError(format!(
                            "Moravian failed to query {}: {}",
                            name, detail
                        )));
                    }
                    Ok(())
                };
            let query_boolean =
                |index: c_int, value: &mut GxBool, name: &str| -> Result<(), NativeError> {
                    // SAFETY: moravian_mutex held; handle is initialized and value is a
                    // valid GxBool out-pointer for gxccd_get_boolean_parameter.
                    let result = unsafe { (sdk.get_boolean_parameter)(handle, index, value) };
                    if result < 0 {
                        // SAFETY: handle remains valid on this error path.
                        let detail = unsafe { sdk_last_error(sdk, handle) };
                        return Err(NativeError::SdkError(format!(
                            "Moravian failed to query {}: {}",
                            name, detail
                        )));
                    }
                    Ok(())
                };

            query_integer(GIP_CHIP_W, &mut width_i, "sensor width")?;
            query_integer(GIP_CHIP_D, &mut height_i, "sensor height")?;
            query_integer(GIP_PIXEL_W, &mut pixel_w, "pixel width")?;
            query_integer(GIP_PIXEL_D, &mut pixel_d, "pixel height")?;
            query_integer(GIP_MAX_BINNING_X, &mut max_bin_x, "maximum X binning")?;
            query_integer(GIP_MAX_BINNING_Y, &mut max_bin_y, "maximum Y binning")?;
            query_integer(
                GIP_MAX_PIXEL_VALUE,
                &mut max_pixel_value,
                "maximum pixel value",
            )?;
            query_boolean(GBP_RGB, &mut is_rgb, "RGB sensor capability")?;
            query_boolean(GBP_CMY, &mut is_cmy, "CMY sensor capability")?;
            query_boolean(GBP_CMYG, &mut is_cmyg, "CMYG sensor capability")?;
            query_boolean(GBP_DEBAYER_X_ODD, &mut deb_x_odd, "horizontal Bayer phase")?;
            query_boolean(GBP_DEBAYER_Y_ODD, &mut deb_y_odd, "vertical Bayer phase")?;
            query_boolean(GBP_COOLER, &mut has_cooler, "cooler capability")?;
            query_boolean(GBP_SHUTTER, &mut has_shutter, "shutter capability")?;
            query_boolean(GBP_GUIDE, &mut has_guide, "guider capability")?;
            query_boolean(GBP_GAIN, &mut has_gain, "gain capability")?;
            query_boolean(GBP_SUB_FRAME, &mut has_subframe, "subframe capability")?;

            if width_i <= 0
                || height_i <= 0
                || pixel_w <= 0
                || pixel_d <= 0
                || max_bin_x <= 0
                || max_bin_y <= 0
                || max_pixel_value <= 0
            {
                return Err(NativeError::SdkError(format!(
                    "Moravian reported invalid camera parameters: sensor={}x{}, pixel={}x{}nm, max_bin={}x{}, max_adu={}",
                    width_i,
                    height_i,
                    pixel_w,
                    pixel_d,
                    max_bin_x,
                    max_bin_y,
                    max_pixel_value
                )));
            }

            let width = width_i as u32;
            let height = height_i as u32;

            // GIP_PIXEL_W/D are in NANOMETERS (gxccd.h:267-268); the reference
            // converts to microns with /1000.0 (mi_ccd.cpp:435).
            let pixel_size_x = pixel_w.max(0) as f64 / 1000.0;
            let pixel_size_y = pixel_d.max(0) as f64 / 1000.0;

            // GIP_MAX_PIXEL_VALUE is the saturation ADU (gxccd.h:282). Data is
            // always delivered 16-bit (gxccd_read_image), so bit_depth stays 16.
            let max_adu = max_pixel_value as u32;

            // Color: only RGB Bayer is representable by BayerPattern. For CMY/CMYG
            // we flag color but leave the pattern None (an honest "unknown CFA"
            // rather than a wrong RGGB).
            let color = is_rgb != 0 || is_cmy != 0 || is_cmyg != 0;
            let bayer_pattern = if is_rgb != 0 {
                let native = native_bayer(deb_x_odd != 0, deb_y_odd != 0);
                // We vertically mirror every frame; for even sensor height that
                // mirror swaps the two Bayer rows, so report the flipped phase.
                if height.is_multiple_of(2) {
                    Some(flip_bayer_vertical(native))
                } else {
                    Some(native)
                }
            } else {
                None
            };

            self.sensor_info = SensorInfo {
                width,
                height,
                pixel_size_x,
                pixel_size_y,
                max_adu,
                bit_depth: 16,
                color,
                bayer_pattern,
            };

            self.capabilities = CameraCapabilities {
                can_cool: has_cooler != 0,
                can_set_gain: has_gain != 0,
                can_set_offset: false, // Moravian doesn't have separate offset
                can_set_binning: max_bin_x > 1 || max_bin_y > 1,
                can_subframe: has_subframe != 0,
                has_shutter: has_shutter != 0,
                has_guider_port: has_guide != 0,
                max_bin_x: max_bin_x.max(1),
                max_bin_y: max_bin_y.max(1),
                supports_readout_modes: true,
            };
        }

        {
            let mut h = self.handle.lock().unwrap_or_else(|e| e.into_inner());
            *h = HandleWrapper(handle);
        }
        cleanup_guard.defuse();

        // The current gxccd SDK has no separate Open() step — the handle from
        // gxccd_initialize_usb is ready for imaging.
        self.connected = true;
        self.state = CameraState::Idle;

        tracing::info!(
            "Connected to Moravian camera: {} ({}x{})",
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

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Release camera (no separate Close() in the current SDK).
        // SAFETY: moravian_mutex held above; handle was previously Initialize()'d (we're on the connected path); gxccd_release() pairs with gxccd_initialize_usb() and is the required final cleanup per gxccd.h:206-211.
        unsafe { (sdk.release)(handle) };

        {
            let mut h = self.handle.lock().unwrap_or_else(|e| e.into_inner());
            *h = HandleWrapper(std::ptr::null_mut());
        }
        self.connected = false;
        self.state = CameraState::Idle;
        self.exposure_started_at = None;
        self.last_frame_dims = None;

        tracing::info!("Disconnected from Moravian camera: {}", self.name);

        Ok(())
    }
}

#[async_trait]
impl NativeCamera for MoravianCamera {
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

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Get temperature
        let current_temp = {
            let mut value: c_float = 0.0;
            // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); self.connected was checked at entry so the handle is open; `&mut value` is a valid stack out-pointer to a c_float.
            if unsafe { (sdk.get_value)(handle, GV_CHIP_TEMPERATURE, &mut value) } >= 0 {
                Some(value as f64)
            } else {
                None
            }
        };

        // Get cooler power
        let cooler_power = {
            let mut value: c_float = 0.0;
            // SAFETY: moravian_mutex held; self.connected was checked at entry; `&mut value` is a valid stack out-pointer to a c_float.
            if unsafe { (sdk.get_value)(handle, GV_POWER_UTILIZATION, &mut value) } >= 0 {
                Some(value as f64)
            } else {
                None
            }
        };

        // Calculate exposure remaining from elapsed time when exposing.
        let exposure_remaining = if self.state == CameraState::Exposing {
            match self.exposure_started_at {
                Some(started) => {
                    let elapsed_secs = started.elapsed().as_secs_f64();
                    Some((self.exposure_duration - elapsed_secs).max(0.0))
                }
                None => {
                    tracing::warn!(
                        "Moravian camera is exposing but exposure start timestamp is unavailable; cannot compute remaining exposure time."
                    );
                    None
                }
            }
        } else {
            None
        };

        Ok(CameraStatus {
            state: self.state,
            sensor_temp: current_temp,
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

        if self.state == CameraState::Exposing {
            return Err(NativeError::SdkError("Camera is already exposing".into()));
        }

        let sdk = get_sdk()?;

        // Compute the binned, y-flipped ROI the current SDK expects on
        // start_exposure (the legacy SDK applied the ROI at download time).
        let bin_x = u32::try_from(self.current_bin_x).map_err(|_| {
            NativeError::InvalidParameter(format!(
                "Moravian current_bin_x not representable as u32: {}",
                self.current_bin_x
            ))
        })?;
        let bin_y = u32::try_from(self.current_bin_y).map_err(|_| {
            NativeError::InvalidParameter(format!(
                "Moravian current_bin_y not representable as u32: {}",
                self.current_bin_y
            ))
        })?;
        let subframe = self
            .subframe
            .as_ref()
            .map(|sf| (sf.start_x, sf.start_y, sf.width, sf.height));
        let roi = compute_binned_roi(
            self.sensor_info.width,
            self.sensor_info.height,
            bin_x,
            bin_y,
            subframe,
        )
        .map_err(NativeError::InvalidParameter)?;

        // Shutter policy lives on this ONE line: Light/Flat open the mechanical
        // shutter; Dark/Bias/DarkFlat keep it closed so calibration frames are not
        // contaminated (camera.rs `FrameType::opens_shutter`, whose doc names the
        // Moravian G-series). Bodies without a shutter simply ignore the flag.
        let use_shutter: GxBool = params.frame_type.opens_shutter() as GxBool;

        {
            // Acquire global SDK mutex for thread safety
            let _lock = moravian_mutex().lock().await;

            let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

            // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); self.connected was checked at entry so the handle is open; exp_time/use_shutter/x/y/w/h are passed by value and the ROI was bounds-checked by compute_binned_roi against the binned sensor extent.
            let ret = unsafe {
                (sdk.start_exposure)(
                    handle,
                    params.duration_secs,
                    use_shutter,
                    roi.x,
                    roi.y,
                    roi.w,
                    roi.h,
                )
            };
            if ret < 0 {
                // SAFETY: moravian_mutex held; handle is the open camera handle.
                let msg = unsafe { sdk_last_error(sdk, handle) };
                tracing::error!(
                    "Moravian gxccd_start_exposure() failed for camera '{}': {} (duration {:.3}s, ROI {}x{}+{}+{})",
                    self.name, msg, params.duration_secs, roi.w, roi.h, roi.x, roi.y
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to start exposure on Moravian camera '{}': {}",
                    self.name, msg
                )));
            }

            self.exposure_duration = params.duration_secs;
            self.exposure_started_at = Some(std::time::Instant::now());
            self.last_frame_dims = Some((roi.w as u32, roi.h as u32));
            self.state = CameraState::Exposing;

            tracing::info!(
                "Started {:.3}s exposure on Moravian camera '{}' (ROI {}x{})",
                params.duration_secs,
                self.name,
                roi.w,
                roi.h
            );
        } // Mutex released here BEFORE sleeping

        // Wait for the exposure integration (mutex is NOT held during this sleep).
        // The chip readout that follows is awaited via gxccd_image_ready in
        // download_image.
        tokio::time::sleep(tokio::time::Duration::from_secs_f64(
            params.duration_secs.max(0.0),
        ))
        .await;

        Ok(())
    }

    async fn abort_exposure(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Abort, discarding the frame (download = false), matching the reference
        // (mi_ccd.cpp:534). Abort is a best-effort cleanup path: log a failure
        // but still reset local state so the orchestrator is not wedged.
        // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); self.connected was checked at entry so the handle is open; gxccd_abort_exposure takes the handle plus a GxBool (download=0) by value.
        let ret = unsafe { (sdk.abort_exposure)(handle, 0) };
        if ret < 0 {
            // SAFETY: moravian_mutex held; handle is the open camera handle.
            let msg = unsafe { sdk_last_error(sdk, handle) };
            tracing::warn!(
                "Moravian gxccd_abort_exposure() failed for camera '{}': {}",
                self.name,
                msg
            );
        }

        self.state = CameraState::Idle;
        self.exposure_started_at = None;
        self.last_frame_dims = None;
        tracing::info!("Aborted exposure on Moravian camera '{}'", self.name);

        Ok(())
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Binned dimensions requested at start_exposure. gxccd_read_image takes
        // no ROI of its own; the buffer must match exactly what start_exposure
        // requested.
        let (binned_width, binned_height) = self.last_frame_dims.ok_or_else(|| {
            NativeError::SdkError(
                "Moravian download_image called without an active exposure".into(),
            )
        })?;

        // Buffer sizing, overflow-guarded. size is a size_t (usize); on 64-bit
        // targets the pixel/byte counts fit comfortably.
        let pixel_count_u64 = u64::from(binned_width)
            .checked_mul(u64::from(binned_height))
            .ok_or_else(|| {
                NativeError::SdkError(format!(
                    "Moravian buffer dimensions overflow u64: {}x{}",
                    binned_width, binned_height
                ))
            })?;
        let byte_count_u64 = pixel_count_u64
            .checked_mul(2)
            .ok_or_else(|| NativeError::SdkError("Moravian byte count overflow u64".into()))?;
        let buffer_size = usize::try_from(pixel_count_u64).map_err(|_| {
            NativeError::SdkError(format!(
                "Moravian buffer pixel count {} does not fit in usize",
                pixel_count_u64
            ))
        })?;
        let byte_count = usize::try_from(byte_count_u64).map_err(|_| {
            NativeError::SdkError(format!(
                "Moravian byte count {} does not fit in usize",
                byte_count_u64
            ))
        })?;

        // Wait for the chip to finish digitizing (readout follows the exposure
        // integration). gxccd_read_image fails if called before the image is
        // ready, so we poll gxccd_image_ready with a bounded timeout, releasing
        // the SDK mutex between polls (mi_ccd.cpp:682-700).
        let deadline =
            std::time::Instant::now() + std::time::Duration::from_secs(READOUT_TIMEOUT_SECS);
        loop {
            let ready = {
                let _lock = moravian_mutex().lock().await;
                let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;
                let mut ready: GxBool = 0;
                // SAFETY: moravian_mutex held; self.connected was checked at entry so the handle is open; `&mut ready` is a valid stack out-pointer to a GxBool.
                let ret = unsafe { (sdk.image_ready)(handle, &mut ready) };
                if ret < 0 {
                    // SAFETY: moravian_mutex held; handle is the open camera handle.
                    let msg = unsafe { sdk_last_error(sdk, handle) };
                    self.state = CameraState::Error;
                    return Err(NativeError::SdkError(format!(
                        "Moravian gxccd_image_ready() failed for camera '{}': {}",
                        self.name, msg
                    )));
                }
                ready != 0
            };
            if ready {
                break;
            }
            if std::time::Instant::now() >= deadline {
                self.state = CameraState::Error;
                return Err(NativeError::SdkError(format!(
                    "Timed out after {}s waiting for Moravian camera '{}' image readout",
                    READOUT_TIMEOUT_SECS, self.name
                )));
            }
            tokio::time::sleep(tokio::time::Duration::from_millis(READOUT_POLL_MS)).await;
        }

        self.state = CameraState::Downloading;

        // Read the frame and capture temperature under a single mutex hold.
        let _lock = moravian_mutex().lock().await;
        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Allocate the exact buffer (binned_w * binned_h pixels, 16-bit each).
        let mut data: Vec<u16> = vec![0u16; buffer_size];

        // Download image.
        // SAFETY: moravian_mutex held above; handle is open (self.connected checked at entry); `data` is `vec![0u16; buffer_size]` where buffer_size = binned_width * binned_height, so `byte_count = buffer_size * 2` is the exact byte length passed as `size_t` — the SDK cannot overrun; `data.as_mut_ptr() as *mut c_void` provides a valid non-null buffer pointer.
        let ret = unsafe { (sdk.read_image)(handle, data.as_mut_ptr() as *mut c_void, byte_count) };
        if ret < 0 {
            // SAFETY: moravian_mutex held; handle is the open camera handle.
            let msg = unsafe { sdk_last_error(sdk, handle) };
            tracing::error!(
                "Moravian gxccd_read_image() failed for camera '{}': {} ({}x{} pixels, {} bytes)",
                self.name,
                msg,
                binned_width,
                binned_height,
                byte_count
            );
            self.state = CameraState::Error;
            return Err(NativeError::SdkError(format!(
                "Failed to download image from Moravian camera '{}': {}",
                self.name, msg
            )));
        }

        // gxccd_read_image returns rows bottom-up (gxccd.h:416-434). Flip to
        // top-down so orientation matches the sky and every other vendor
        // (mi_ccd.cpp:657 `mirror_image`).
        mirror_vertical_u16(&mut data, binned_width as usize, binned_height as usize);

        self.state = CameraState::Idle;
        self.exposure_started_at = None;
        self.last_frame_dims = None;

        // Get temperature while we still hold the mutex.
        let temperature = {
            let mut value: c_float = 0.0;
            // SAFETY: moravian_mutex still held (same scope as the download above); handle is still open; `&mut value` is a valid stack out-pointer to a c_float.
            if unsafe { (sdk.get_value)(handle, GV_CHIP_TEMPERATURE, &mut value) } >= 0 {
                Some(value as f64)
            } else {
                None
            }
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

        Ok(ImageData {
            width: binned_width,
            height: binned_height,
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

        if self.state != CameraState::Exposing {
            return Ok(true);
        }

        let started_at = match self.exposure_started_at {
            Some(started) => started,
            None => return Ok(false),
        };
        Ok(started_at.elapsed().as_secs_f64() >= self.exposure_duration.max(0.0))
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

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        if enabled {
            // gxccd_set_temperature *is* the enable here, so cooling needs a
            // setpoint; when the caller names none we reuse the one this
            // driver already holds rather than inventing a temperature.
            let target = target_temp.unwrap_or(self.target_temp);
            // Set target temperature.
            // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); self.connected was checked at entry so handle is open; gxccd_set_temperature takes the handle plus a c_float by value.
            let ret = unsafe { (sdk.set_temperature)(handle, target as c_float) };
            if ret < 0 {
                // SAFETY: moravian_mutex held; handle is the open camera handle.
                let msg = unsafe { sdk_last_error(sdk, handle) };
                tracing::error!(
                    "Moravian gxccd_set_temperature() failed for camera '{}': {} (target {:.1} C)",
                    self.name,
                    msg,
                    target
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to set cooler temperature to {:.1} C on Moravian camera '{}': {}",
                    target, self.name, msg
                )));
            }
            self.cooler_on = true;
            self.target_temp = target;
            tracing::info!("Moravian cooler enabled: target {} C", target);
        } else {
            // Warm up: a high setpoint turns the cooler fully off (mi_ccd.cpp:35).
            // No caller setpoint is involved or needed.
            // SAFETY: moravian_mutex held above; handle is open (self.connected checked at entry); gxccd_set_temperature accepts the handle and a c_float by value.
            unsafe { (sdk.set_temperature)(handle, TEMP_COOLER_OFF) };
            self.cooler_on = false;
            tracing::info!("Moravian cooler disabled");
        }

        Ok(())
    }

    async fn get_temperature(&self) -> Result<f64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        let mut value: c_float = 0.0;
        // SAFETY: moravian_mutex held above; self.connected was checked at entry so handle is open; `&mut value` is a valid stack out-pointer to a c_float.
        if unsafe { (sdk.get_value)(handle, GV_CHIP_TEMPERATURE, &mut value) } >= 0 {
            Ok(value as f64)
        } else {
            // SAFETY: moravian_mutex held; handle is the open camera handle.
            let msg = unsafe { sdk_last_error(sdk, handle) };
            Err(NativeError::SdkError(format!(
                "Failed to get temperature: {}",
                msg
            )))
        }
    }

    async fn get_cooler_power(&self) -> Result<f64, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        let mut value: c_float = 0.0;
        // SAFETY: moravian_mutex held above; self.connected was checked at entry so handle is open; `&mut value` is a valid stack out-pointer to a c_float.
        if unsafe { (sdk.get_value)(handle, GV_POWER_UTILIZATION, &mut value) } >= 0 {
            Ok(value as f64)
        } else {
            // SAFETY: moravian_mutex held; handle is the open camera handle.
            let msg = unsafe { sdk_last_error(sdk, handle) };
            Err(NativeError::SdkError(format!(
                "Failed to get cooler power: {}",
                msg
            )))
        }
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.capabilities.can_set_gain {
            return Err(NativeError::NotSupported);
        }

        // gxccd_set_gain takes a uint16_t register value (gxccd.h:472-478).
        let gain_u16 = u16::try_from(gain).map_err(|_| {
            NativeError::InvalidParameter(format!("Moravian gain {} out of range 0..=65535", gain))
        })?;

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); self.connected and capabilities.can_set_gain were checked at entry so the handle is open and the camera supports gain; gxccd_set_gain takes the handle and a u16 by value.
        let ret = unsafe { (sdk.set_gain)(handle, gain_u16) };
        if ret < 0 {
            // SAFETY: moravian_mutex held; handle is the open camera handle.
            let msg = unsafe { sdk_last_error(sdk, handle) };
            tracing::error!(
                "Moravian gxccd_set_gain() failed for camera '{}': {} (requested {})",
                self.name,
                msg,
                gain
            );
            return Err(NativeError::SdkError(format!(
                "Failed to set gain to {} on Moravian camera '{}': {}",
                gain, self.name, msg
            )));
        }

        self.current_gain = gain;
        Ok(())
    }

    async fn set_offset(&mut self, _offset: i32) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn set_binning(&mut self, bin_x: i32, bin_y: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.capabilities.can_set_binning && (bin_x > 1 || bin_y > 1) {
            return Err(NativeError::NotSupported);
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); self.connected was checked at entry so the handle is open; gxccd_set_binning takes the handle plus two c_int values by value.
        let ret = unsafe { (sdk.set_binning)(handle, bin_x as c_int, bin_y as c_int) };
        if ret < 0 {
            // SAFETY: moravian_mutex held; handle is the open camera handle.
            let msg = unsafe { sdk_last_error(sdk, handle) };
            tracing::error!(
                "Moravian gxccd_set_binning() failed for camera '{}': {} (requested {}x{}, max {}x{})",
                self.name,
                msg,
                bin_x,
                bin_y,
                self.capabilities.max_bin_x,
                self.capabilities.max_bin_y
            );
            return Err(NativeError::SdkError(format!(
                "Failed to set binning to {}x{} on Moravian camera '{}': {} (max {}x{})",
                bin_x,
                bin_y,
                self.name,
                msg,
                self.capabilities.max_bin_x,
                self.capabilities.max_bin_y
            )));
        }

        self.current_bin_x = bin_x;
        self.current_bin_y = bin_y;
        Ok(())
    }

    async fn set_subframe(&mut self, subframe: Option<SubFrame>) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // The current SDK validates the ROI on gxccd_start_exposure, so there is
        // no separate "adjust subframe" call. We validate the top-down, unbinned
        // request against the sensor extent and store it; the binned, y-flipped
        // ROI is derived at start_exposure (compute_binned_roi).
        match subframe {
            Some(sf) => {
                if !self.capabilities.can_subframe {
                    return Err(NativeError::NotSupported);
                }
                if sf.width == 0 || sf.height == 0 {
                    return Err(NativeError::InvalidParameter(
                        "Moravian subframe width/height must be > 0".into(),
                    ));
                }
                let x_end = sf.start_x.checked_add(sf.width).ok_or_else(|| {
                    NativeError::InvalidParameter("Moravian subframe x extent overflow".into())
                })?;
                let y_end = sf.start_y.checked_add(sf.height).ok_or_else(|| {
                    NativeError::InvalidParameter("Moravian subframe y extent overflow".into())
                })?;
                if x_end > self.sensor_info.width || y_end > self.sensor_info.height {
                    return Err(NativeError::InvalidParameter(format!(
                        "Moravian subframe ({}, {}) {}x{} exceeds sensor {}x{}",
                        sf.start_x,
                        sf.start_y,
                        sf.width,
                        sf.height,
                        self.sensor_info.width,
                        self.sensor_info.height
                    )));
                }
                self.subframe = Some(sf);
            }
            None => {
                self.subframe = None;
            }
        }

        Ok(())
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        Ok(self.current_gain)
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_binning(&self) -> Result<(i32, i32), NativeError> {
        Ok((self.current_bin_x, self.current_bin_y))
    }

    async fn get_readout_modes(&self) -> Result<Vec<ReadoutMode>, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // Number of read modes.
        let num_modes = {
            let mut value: c_int = 0;
            // SAFETY: moravian_mutex held above; self.connected was checked at entry so handle is open; `&mut value` is a valid stack out-pointer to a c_int.
            if unsafe { (sdk.get_integer_parameter)(handle, GIP_READ_MODES, &mut value) } >= 0 {
                value
            } else {
                1
            }
        };

        let mut modes = Vec::new();
        for i in 0..num_modes.max(0) {
            let mut desc_buf = [0 as c_char; 256];
            // SAFETY: moravian_mutex held; handle is open; `i` is in [0, num_modes) as reported above; desc_buf is 256 bytes and its truthful length is passed as `size_t`. gxccd_enumerate_read_modes returns -1 once the index is past the end.
            if unsafe {
                (sdk.enumerate_read_modes)(handle, i, desc_buf.as_mut_ptr(), desc_buf.len())
            } >= 0
            {
                // SAFETY: desc_buf is 256 bytes; the SDK guarantees NUL-termination within the buffer on success.
                let description = unsafe { std::ffi::CStr::from_ptr(desc_buf.as_ptr()) }
                    .to_string_lossy()
                    .trim()
                    .to_string();

                modes.push(ReadoutMode {
                    name: if description.is_empty() {
                        format!("Mode {}", i)
                    } else {
                        description.clone()
                    },
                    description,
                    index: i,
                    gain_min: None,
                    gain_max: None,
                    offset_min: None,
                    offset_max: None,
                });
            }
        }

        if modes.is_empty() {
            modes.push(ReadoutMode {
                name: "Normal".to_string(),
                description: "Standard readout mode".to_string(),
                index: 0,
                gain_min: None,
                gain_max: None,
                offset_min: None,
                offset_max: None,
            });
        }

        Ok(modes)
    }

    async fn set_readout_mode(&mut self, mode: &ReadoutMode) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // SAFETY: moravian_mutex held above (single-threaded gxccd SDK access); self.connected was checked at entry so the handle is open; gxccd_set_read_mode takes the handle plus a c_int index by value.
        let ret = unsafe { (sdk.set_read_mode)(handle, mode.index as c_int) };
        if ret < 0 {
            // SAFETY: moravian_mutex held; handle is the open camera handle.
            let msg = unsafe { sdk_last_error(sdk, handle) };
            tracing::error!(
                "Moravian gxccd_set_read_mode() failed for camera '{}': {} (mode {} '{}')",
                self.name,
                msg,
                mode.index,
                mode.name
            );
            return Err(NativeError::SdkError(format!(
                "Failed to set readout mode '{}' (index {}) on Moravian camera '{}': {}",
                mode.name, mode.index, self.name, msg
            )));
        }

        Ok(())
    }

    async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
        // Moravian has hot side temp available but VendorFeatures doesn't have this field
        // Could use custom_data in future if needed
        Ok(VendorFeatures::default())
    }

    async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        // Moravian cameras (mostly CCD) typically have limited or no gain control.
        // CMOS Moravian cameras would have adjustable gain.
        // Return a nominal range that works for most.
        Ok((0, 100))
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        Err(NativeError::NotSupported)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn moravian_offset_write_reports_not_supported_without_mutating_cache() {
        let mut camera = MoravianCamera::new(0);
        camera.current_offset = 7;

        let err = camera.set_offset(22).await.unwrap_err();

        assert!(matches!(err, NativeError::NotSupported));
        assert_eq!(camera.current_offset, 7);
    }

    #[tokio::test]
    async fn moravian_gain_write_reports_not_supported_without_mutating_cache() {
        let mut camera = MoravianCamera::new(0);
        camera.connected = true;
        camera.capabilities.can_set_gain = false;
        camera.current_gain = 11;

        let err = camera.set_gain(42).await.unwrap_err();

        assert!(matches!(err, NativeError::NotSupported));
        assert_eq!(camera.current_gain, 11);
    }

    // ---- ROI / bin math ----------------------------------------------------

    #[test]
    fn full_frame_roi_has_zero_origin_and_full_binned_size() {
        // Full frame (no subframe): origin (0,0), y-flip collapses to fy=0.
        let roi = compute_binned_roi(4032, 2688, 1, 1, None).unwrap();
        assert_eq!(
            roi,
            BinnedRoi {
                x: 0,
                y: 0,
                w: 4032,
                h: 2688
            }
        );
    }

    #[test]
    fn full_frame_roi_binned_divides_by_bin() {
        let roi = compute_binned_roi(4032, 2688, 2, 2, None).unwrap();
        assert_eq!(
            roi,
            BinnedRoi {
                x: 0,
                y: 0,
                w: 2016,
                h: 1344
            }
        );
    }

    #[test]
    fn subframe_roi_flips_y_origin_bottom_up() {
        // Sensor 100x100, bin 1, top-down subframe at (10,20) size 30x40.
        // Bottom-up y origin = 100 - 20 - 40 = 40.
        let roi = compute_binned_roi(100, 100, 1, 1, Some((10, 20, 30, 40))).unwrap();
        assert_eq!(
            roi,
            BinnedRoi {
                x: 10,
                y: 40,
                w: 30,
                h: 40
            }
        );
    }

    #[test]
    fn subframe_roi_binned_origin_and_flip() {
        // Sensor 100x100, bin 2. Top-down subframe (unbinned) at (20,40) size 40x20.
        // Binned: x=10, y_top=20, w=20, h=10; full_bh=50; fy = 50 - 20 - 10 = 20.
        let roi = compute_binned_roi(100, 100, 2, 2, Some((20, 40, 40, 20))).unwrap();
        assert_eq!(
            roi,
            BinnedRoi {
                x: 10,
                y: 20,
                w: 20,
                h: 10
            }
        );
    }

    #[test]
    fn subframe_top_row_maps_to_correct_bottom_up_region() {
        // A subframe starting at the very top (y=0) must map to the top of the
        // bottom-up frame: fy = H - 0 - h = H - h.
        let roi = compute_binned_roi(64, 48, 1, 1, Some((0, 0, 64, 10))).unwrap();
        assert_eq!(roi.y, 48 - 10);
    }

    #[test]
    fn roi_rejects_out_of_bounds_subframe() {
        // Extends past the right edge.
        assert!(compute_binned_roi(100, 100, 1, 1, Some((80, 0, 40, 10))).is_err());
        // Extends past the bottom edge.
        assert!(compute_binned_roi(100, 100, 1, 1, Some((0, 80, 10, 40))).is_err());
    }

    #[test]
    fn roi_rejects_zero_binning() {
        assert!(compute_binned_roi(100, 100, 0, 1, None).is_err());
        assert!(compute_binned_roi(100, 100, 1, 0, None).is_err());
    }

    // ---- orientation -------------------------------------------------------

    #[test]
    fn mirror_vertical_reverses_row_order() {
        // width=2, height=3: rows [0,1] [2,3] [4,5] -> [4,5] [2,3] [0,1].
        let mut buf = vec![0u16, 1, 2, 3, 4, 5];
        mirror_vertical_u16(&mut buf, 2, 3);
        assert_eq!(buf, vec![4, 5, 2, 3, 0, 1]);
    }

    #[test]
    fn mirror_vertical_even_height() {
        // width=3, height=2: rows [1,2,3] [4,5,6] -> [4,5,6] [1,2,3].
        let mut buf = vec![1u16, 2, 3, 4, 5, 6];
        mirror_vertical_u16(&mut buf, 3, 2);
        assert_eq!(buf, vec![4, 5, 6, 1, 2, 3]);
    }

    #[test]
    fn mirror_vertical_is_involutive() {
        // Applying the flip twice returns the original image.
        let original = vec![9u16, 8, 7, 6, 5, 4, 3, 2, 1, 0, 11, 12];
        let mut buf = original.clone();
        mirror_vertical_u16(&mut buf, 4, 3);
        mirror_vertical_u16(&mut buf, 4, 3);
        assert_eq!(buf, original);
    }

    #[test]
    fn mirror_vertical_ignores_undersized_buffer() {
        // Never panic / index OOB if the buffer is smaller than claimed dims.
        let mut buf = vec![1u16, 2, 3];
        mirror_vertical_u16(&mut buf, 4, 4);
        assert_eq!(buf, vec![1, 2, 3]);
    }

    // ---- Bayer phase -------------------------------------------------------

    #[test]
    fn native_bayer_phase_table() {
        assert_eq!(native_bayer(false, false), BayerPattern::Rggb);
        assert_eq!(native_bayer(true, false), BayerPattern::Grbg);
        assert_eq!(native_bayer(false, true), BayerPattern::Gbrg);
        assert_eq!(native_bayer(true, true), BayerPattern::Bggr);
    }

    #[test]
    fn flip_bayer_vertical_swaps_rows() {
        assert_eq!(flip_bayer_vertical(BayerPattern::Rggb), BayerPattern::Gbrg);
        assert_eq!(flip_bayer_vertical(BayerPattern::Gbrg), BayerPattern::Rggb);
        assert_eq!(flip_bayer_vertical(BayerPattern::Grbg), BayerPattern::Bggr);
        assert_eq!(flip_bayer_vertical(BayerPattern::Bggr), BayerPattern::Grbg);
    }

    #[test]
    fn flip_bayer_vertical_is_involutive() {
        for p in [
            BayerPattern::Rggb,
            BayerPattern::Grbg,
            BayerPattern::Gbrg,
            BayerPattern::Bggr,
        ] {
            assert_eq!(flip_bayer_vertical(flip_bayer_vertical(p)), p);
        }
    }
}
