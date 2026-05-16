//! libgphoto2 DSLR/Mirrorless Camera Driver
//!
//! Provides native support for DSLR and mirrorless cameras via the libgphoto2 library.
//! Supports Canon, Nikon, Sony, Pentax, and many other camera brands.
//!
//! ## Thread Safety
//!
//! libgphoto2 is NOT thread-safe. All library operations are protected by
//! `gphoto2_mutex()` from `crate::sync`.
//!
//! ## Important Behaviors
//!
//! 1. **Bulb mode**: For exposures > 30s, the camera must be set to Bulb mode.
//!    The driver holds the shutter open via `gp_camera_trigger_capture` + timed release.
//! 2. **ISO mapping**: ISO values are mapped to/from the gain parameter.
//!    ISO 100 = gain 0, ISO 200 = gain 1, etc. (index into available ISO list).
//! 3. **Image download**: After capture, the image is downloaded from camera storage
//!    as a RAW file and decoded to 16-bit pixel data via the raw pixel extraction path.
//! 4. **Live view**: Some cameras support live view preview via `gp_camera_capture_preview`.
//!
//! ## Library Requirements
//!
//! - libgphoto2 (libgphoto2.so / libgphoto2.dylib / libgphoto2.dll)
//! - libgphoto2_port (loaded automatically by libgphoto2)
//!
//! On Linux: `apt install libgphoto2-dev`
//! On macOS: `brew install libgphoto2`
//! On Windows: Install from https://github.com/gphoto/libgphoto2/releases

#![allow(dead_code)] // FFI types must match library headers even if not all are used

use crate::camera::*;
use crate::sync::gphoto2_mutex;
use crate::traits::*;
use crate::NativeVendor;
use async_trait::async_trait;
use std::ffi::{c_char, c_float, c_int, c_void, CStr, CString};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

// =============================================================================
// LIBGPHOTO2 TYPE DEFINITIONS
// =============================================================================

/// Opaque camera handle
type GPCamera = c_void;

/// Opaque context handle
type GPContext = c_void;

/// Opaque camera list handle
type CameraList = c_void;

/// Opaque camera file handle
type CameraFile = c_void;

/// Opaque camera widget handle (for configuration)
type CameraWidget = c_void;

/// Camera file type enum (GP_FILE_TYPE_*)
#[repr(C)]
#[derive(Debug, Clone, Copy)]
enum CameraFileType {
    Preview = 0,
    Normal = 1,
    Raw = 2,
    Audio = 3,
    Exif = 4,
    Metadata = 5,
}

/// Camera capture type
#[repr(C)]
#[derive(Debug, Clone, Copy)]
enum CameraCaptureType {
    Image = 0,
    Movie = 1,
    Sound = 2,
}

/// Camera widget type
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
enum CameraWidgetType {
    Window = 0,
    Section = 1,
    Text = 2,
    Range = 3,
    Toggle = 4,
    Radio = 5,
    Menu = 6,
    Button = 7,
    Date = 8,
}

/// Camera file path - returned by gp_camera_capture
#[repr(C)]
#[derive(Debug, Clone)]
struct CameraFilePath {
    name: [c_char; 128],
    folder: [c_char; 1024],
}

impl Default for CameraFilePath {
    fn default() -> Self {
        Self {
            name: [0; 128],
            folder: [0; 1024],
        }
    }
}

/// Camera abilities (partial - we only need a few fields)
#[repr(C)]
#[derive(Debug, Clone)]
struct CameraAbilities {
    model: [c_char; 128],
    status: c_int,
    port: c_int,
    speed: [c_int; 64],
    operations: c_int,
    file_operations: c_int,
    folder_operations: c_int,
    usb_vendor: c_int,
    usb_product: c_int,
    usb_class: c_int,
    usb_subclass: c_int,
    usb_protocol: c_int,
    library: [c_char; 1024],
    id: [c_char; 1024],
    device_type: c_int,
    reserved2: c_int,
    reserved3: c_int,
    reserved4: c_int,
    reserved5: c_int,
    reserved6: c_int,
    reserved7: c_int,
    reserved8: c_int,
}

impl Default for CameraAbilities {
    fn default() -> Self {
        Self {
            model: [0; 128],
            status: 0,
            port: 0,
            speed: [0; 64],
            operations: 0,
            file_operations: 0,
            folder_operations: 0,
            usb_vendor: 0,
            usb_product: 0,
            usb_class: 0,
            usb_subclass: 0,
            usb_protocol: 0,
            library: [0; 1024],
            id: [0; 1024],
            device_type: 0,
            reserved2: 0,
            reserved3: 0,
            reserved4: 0,
            reserved5: 0,
            reserved6: 0,
            reserved7: 0,
            reserved8: 0,
        }
    }
}

// GP error codes
const GP_OK: c_int = 0;
const GP_ERROR: c_int = -1;
const GP_ERROR_IO: c_int = -7;
const GP_ERROR_NOT_SUPPORTED: c_int = -5;
const GP_ERROR_CAMERA_BUSY: c_int = -110;
const GP_ERROR_MODEL_NOT_FOUND: c_int = -105;

// Camera operations flags
const GP_OPERATION_CAPTURE_IMAGE: c_int = 1 << 1;
const GP_OPERATION_CAPTURE_PREVIEW: c_int = 1 << 3;
const GP_OPERATION_CONFIG: c_int = 1 << 2;
const GP_OPERATION_TRIGGER_CAPTURE: c_int = 1 << 4;

// =============================================================================
// SDK LIBRARY LOADING
// =============================================================================

/// libgphoto2 SDK library wrapper
struct GPhoto2Sdk {
    #[allow(dead_code)]
    lib: libloading::Library,

    // Context management
    context_new: unsafe extern "C" fn() -> *mut GPContext,
    context_unref: unsafe extern "C" fn(*mut GPContext),

    // Camera lifecycle
    camera_new: unsafe extern "C" fn(*mut *mut GPCamera) -> c_int,
    camera_init: unsafe extern "C" fn(*mut GPCamera, *mut GPContext) -> c_int,
    camera_exit: unsafe extern "C" fn(*mut GPCamera, *mut GPContext) -> c_int,
    camera_unref: unsafe extern "C" fn(*mut GPCamera) -> c_int,
    camera_free: unsafe extern "C" fn(*mut GPCamera) -> c_int,

    // Camera detection/autodetect
    camera_autodetect: unsafe extern "C" fn(*mut CameraList, *mut GPContext) -> c_int,

    // Capture
    camera_capture:
        unsafe extern "C" fn(*mut GPCamera, c_int, *mut CameraFilePath, *mut GPContext) -> c_int,
    camera_capture_preview:
        unsafe extern "C" fn(*mut GPCamera, *mut CameraFile, *mut GPContext) -> c_int,
    camera_trigger_capture: unsafe extern "C" fn(*mut GPCamera, *mut GPContext) -> c_int,
    camera_wait_for_event: unsafe extern "C" fn(
        *mut GPCamera,
        c_int,
        *mut c_int,
        *mut *mut c_void,
        *mut GPContext,
    ) -> c_int,

    // File operations
    camera_file_get: unsafe extern "C" fn(
        *mut GPCamera,
        *const c_char,
        *const c_char,
        c_int,
        *mut CameraFile,
        *mut GPContext,
    ) -> c_int,
    camera_file_delete:
        unsafe extern "C" fn(*mut GPCamera, *const c_char, *const c_char, *mut GPContext) -> c_int,

    // File object
    file_new: unsafe extern "C" fn(*mut *mut CameraFile) -> c_int,
    file_unref: unsafe extern "C" fn(*mut CameraFile) -> c_int,
    file_get_data_and_size:
        unsafe extern "C" fn(*mut CameraFile, *mut *const c_char, *mut u64) -> c_int,
    file_free: unsafe extern "C" fn(*mut CameraFile) -> c_int,

    // Camera list
    list_new: unsafe extern "C" fn(*mut *mut CameraList) -> c_int,
    list_count: unsafe extern "C" fn(*mut CameraList) -> c_int,
    list_get_name: unsafe extern "C" fn(*mut CameraList, c_int, *mut *const c_char) -> c_int,
    list_get_value: unsafe extern "C" fn(*mut CameraList, c_int, *mut *const c_char) -> c_int,
    list_free: unsafe extern "C" fn(*mut CameraList) -> c_int,

    // Configuration
    camera_get_config:
        unsafe extern "C" fn(*mut GPCamera, *mut *mut CameraWidget, *mut GPContext) -> c_int,
    camera_set_config:
        unsafe extern "C" fn(*mut GPCamera, *mut CameraWidget, *mut GPContext) -> c_int,

    // Widget operations
    widget_get_child_by_name:
        unsafe extern "C" fn(*mut CameraWidget, *const c_char, *mut *mut CameraWidget) -> c_int,
    widget_get_type: unsafe extern "C" fn(*mut CameraWidget, *mut c_int) -> c_int,
    widget_get_value: unsafe extern "C" fn(*mut CameraWidget, *mut c_void) -> c_int,
    widget_set_value: unsafe extern "C" fn(*mut CameraWidget, *const c_void) -> c_int,
    widget_count_choices: unsafe extern "C" fn(*mut CameraWidget) -> c_int,
    widget_get_choice: unsafe extern "C" fn(*mut CameraWidget, c_int, *mut *const c_char) -> c_int,
    widget_get_range:
        unsafe extern "C" fn(*mut CameraWidget, *mut c_float, *mut c_float, *mut c_float) -> c_int,
    widget_free: unsafe extern "C" fn(*mut CameraWidget) -> c_int,

    // Camera abilities
    camera_get_abilities: unsafe extern "C" fn(*mut GPCamera, *mut CameraAbilities) -> c_int,

    // Summary
    camera_get_summary:
        unsafe extern "C" fn(*mut GPCamera, *mut GPCameraText, *mut GPContext) -> c_int,
}

/// Camera text struct for summary
#[repr(C)]
#[derive(Clone)]
struct GPCameraText {
    text: [c_char; 32 * 1024],
}

impl Default for GPCameraText {
    fn default() -> Self {
        Self {
            text: [0; 32 * 1024],
        }
    }
}

static GPHOTO2_SDK: OnceLock<Option<GPhoto2Sdk>> = OnceLock::new();

impl GPhoto2Sdk {
    /// Load the libgphoto2 library
    fn load() -> Option<Self> {
        let mut lib_paths: Vec<String> = Vec::new();

        if cfg!(target_os = "windows") {
            lib_paths.push("libgphoto2.dll".to_string());
            lib_paths.push("gphoto2.dll".to_string());
            // Common installation paths
            lib_paths.push("C:\\Program Files\\libgphoto2\\bin\\libgphoto2.dll".to_string());
            lib_paths.push("C:\\msys64\\mingw64\\bin\\libgphoto2.dll".to_string());

            if let Ok(exe_path) = std::env::current_exe() {
                if let Some(exe_dir) = exe_path.parent() {
                    lib_paths.push(exe_dir.join("libgphoto2.dll").to_string_lossy().to_string());
                }
            }
        } else if cfg!(target_os = "macos") {
            lib_paths.push("libgphoto2.dylib".to_string());
            lib_paths.push("/usr/local/lib/libgphoto2.dylib".to_string());
            lib_paths.push("/opt/homebrew/lib/libgphoto2.dylib".to_string());
            // Homebrew Cellar paths
            lib_paths.push("/usr/local/opt/libgphoto2/lib/libgphoto2.dylib".to_string());
            lib_paths.push("/opt/homebrew/opt/libgphoto2/lib/libgphoto2.dylib".to_string());
        } else {
            // Linux
            lib_paths.push("libgphoto2.so".to_string());
            lib_paths.push("libgphoto2.so.6".to_string());
            lib_paths.push("libgphoto2.so.2".to_string());
            lib_paths.push("/usr/lib/libgphoto2.so".to_string());
            lib_paths.push("/usr/lib/x86_64-linux-gnu/libgphoto2.so".to_string());
            lib_paths.push("/usr/local/lib/libgphoto2.so".to_string());
            lib_paths.push("/usr/lib64/libgphoto2.so".to_string());
        }

        for path in &lib_paths {
            tracing::debug!("Trying to load libgphoto2 from: {}", path);
            // SAFETY: `libloading::Library::new(path)` is unsafe because the dynamic
            // linker may execute initializer code from the loaded shared object. The
            // candidate paths come from a hard-coded list of standard libgphoto2
            // install locations (no caller-supplied input), and each resolved symbol
            // signature below is hand-derived from the libgphoto2 C headers, so the
            // function-pointer ABI matches what we cast it to.
            unsafe {
                match libloading::Library::new(path) {
                    Ok(lib) => {
                        tracing::info!("Found libgphoto2 at: {}", path);

                        fn load_symbol<T: Copy>(
                            lib: &libloading::Library,
                            name: &[u8],
                            name_str: &str,
                        ) -> Option<T> {
                            // SAFETY: `Library::get::<T>(name)` is unsafe because the
                            // caller asserts the symbol's foreign signature matches `T`.
                            // Every call site below passes the libgphoto2 C-header-derived
                            // function-pointer type as `T`, and the returned symbol is
                            // immediately copied out by `*sym` (the underlying `lib` is
                            // retained by the enclosing match arm so the function pointer
                            // remains valid for the SDK's lifetime).
                            match unsafe { lib.get::<T>(name) } {
                                Ok(sym) => Some(*sym),
                                Err(e) => {
                                    tracing::error!(
                                        "Failed to load gphoto2 function '{}': {}",
                                        name_str,
                                        e
                                    );
                                    None
                                }
                            }
                        }

                        let context_new = load_symbol(&lib, b"gp_context_new\0", "gp_context_new")?;
                        let context_unref =
                            load_symbol(&lib, b"gp_context_unref\0", "gp_context_unref")?;
                        let camera_new = load_symbol(&lib, b"gp_camera_new\0", "gp_camera_new")?;
                        let camera_init = load_symbol(&lib, b"gp_camera_init\0", "gp_camera_init")?;
                        let camera_exit = load_symbol(&lib, b"gp_camera_exit\0", "gp_camera_exit")?;
                        let camera_unref =
                            load_symbol(&lib, b"gp_camera_unref\0", "gp_camera_unref")?;
                        let camera_free = load_symbol(&lib, b"gp_camera_free\0", "gp_camera_free")?;
                        let camera_autodetect =
                            load_symbol(&lib, b"gp_camera_autodetect\0", "gp_camera_autodetect")?;
                        let camera_capture =
                            load_symbol(&lib, b"gp_camera_capture\0", "gp_camera_capture")?;
                        let camera_capture_preview = load_symbol(
                            &lib,
                            b"gp_camera_capture_preview\0",
                            "gp_camera_capture_preview",
                        )?;
                        let camera_trigger_capture = load_symbol(
                            &lib,
                            b"gp_camera_trigger_capture\0",
                            "gp_camera_trigger_capture",
                        )?;
                        let camera_wait_for_event = load_symbol(
                            &lib,
                            b"gp_camera_wait_for_event\0",
                            "gp_camera_wait_for_event",
                        )?;
                        let camera_file_get =
                            load_symbol(&lib, b"gp_camera_file_get\0", "gp_camera_file_get")?;
                        let camera_file_delete =
                            load_symbol(&lib, b"gp_camera_file_delete\0", "gp_camera_file_delete")?;
                        let file_new = load_symbol(&lib, b"gp_file_new\0", "gp_file_new")?;
                        let file_unref = load_symbol(&lib, b"gp_file_unref\0", "gp_file_unref")?;
                        let file_get_data_and_size = load_symbol(
                            &lib,
                            b"gp_file_get_data_and_size\0",
                            "gp_file_get_data_and_size",
                        )?;
                        let file_free = load_symbol(&lib, b"gp_file_free\0", "gp_file_free")?;
                        let list_new = load_symbol(&lib, b"gp_list_new\0", "gp_list_new")?;
                        let list_count = load_symbol(&lib, b"gp_list_count\0", "gp_list_count")?;
                        let list_get_name =
                            load_symbol(&lib, b"gp_list_get_name\0", "gp_list_get_name")?;
                        let list_get_value =
                            load_symbol(&lib, b"gp_list_get_value\0", "gp_list_get_value")?;
                        let list_free = load_symbol(&lib, b"gp_list_free\0", "gp_list_free")?;
                        let camera_get_config =
                            load_symbol(&lib, b"gp_camera_get_config\0", "gp_camera_get_config")?;
                        let camera_set_config =
                            load_symbol(&lib, b"gp_camera_set_config\0", "gp_camera_set_config")?;
                        let widget_get_child_by_name = load_symbol(
                            &lib,
                            b"gp_widget_get_child_by_name\0",
                            "gp_widget_get_child_by_name",
                        )?;
                        let widget_get_type =
                            load_symbol(&lib, b"gp_widget_get_type\0", "gp_widget_get_type")?;
                        let widget_get_value =
                            load_symbol(&lib, b"gp_widget_get_value\0", "gp_widget_get_value")?;
                        let widget_set_value =
                            load_symbol(&lib, b"gp_widget_set_value\0", "gp_widget_set_value")?;
                        let widget_count_choices = load_symbol(
                            &lib,
                            b"gp_widget_count_choices\0",
                            "gp_widget_count_choices",
                        )?;
                        let widget_get_choice =
                            load_symbol(&lib, b"gp_widget_get_choice\0", "gp_widget_get_choice")?;
                        let widget_get_range =
                            load_symbol(&lib, b"gp_widget_get_range\0", "gp_widget_get_range")?;
                        let widget_free = load_symbol(&lib, b"gp_widget_free\0", "gp_widget_free")?;
                        let camera_get_abilities = load_symbol(
                            &lib,
                            b"gp_camera_get_abilities\0",
                            "gp_camera_get_abilities",
                        )?;
                        let camera_get_summary =
                            load_symbol(&lib, b"gp_camera_get_summary\0", "gp_camera_get_summary")?;

                        let sdk = Self {
                            lib,
                            context_new,
                            context_unref,
                            camera_new,
                            camera_init,
                            camera_exit,
                            camera_unref,
                            camera_free,
                            camera_autodetect,
                            camera_capture,
                            camera_capture_preview,
                            camera_trigger_capture,
                            camera_wait_for_event,
                            camera_file_get,
                            camera_file_delete,
                            file_new,
                            file_unref,
                            file_get_data_and_size,
                            file_free,
                            list_new,
                            list_count,
                            list_get_name,
                            list_get_value,
                            list_free,
                            camera_get_config,
                            camera_set_config,
                            widget_get_child_by_name,
                            widget_get_type,
                            widget_get_value,
                            widget_set_value,
                            widget_count_choices,
                            widget_get_choice,
                            widget_get_range,
                            widget_free,
                            camera_get_abilities,
                            camera_get_summary,
                        };

                        tracing::info!(
                            "Successfully loaded all libgphoto2 functions from: {}",
                            path
                        );
                        return Some(sdk);
                    }
                    Err(e) => {
                        tracing::debug!("libgphoto2 not found at {}: {}", path, e);
                    }
                }
            }
        }

        tracing::error!(
            "libgphoto2 not found! Checked {} locations. DSLR/mirrorless camera support will be unavailable.",
            lib_paths.len()
        );
        tracing::error!(
            "To use DSLR cameras, install libgphoto2: Linux: apt install libgphoto2-dev | macOS: brew install libgphoto2 | Windows: see https://github.com/gphoto/libgphoto2"
        );
        None
    }

    /// Get the global SDK instance
    fn get() -> Option<&'static GPhoto2Sdk> {
        GPHOTO2_SDK.get_or_init(Self::load).as_ref()
    }
}

/// Check gphoto2 error and convert to NativeError
fn check_gp_error(code: c_int, operation: &str) -> Result<(), NativeError> {
    if code >= GP_OK {
        return Ok(());
    }
    match code {
        GP_ERROR => Err(NativeError::SdkError(format!(
            "gPhoto2 {}: general error",
            operation
        ))),
        GP_ERROR_IO => Err(NativeError::SdkError(format!(
            "gPhoto2 {}: I/O error - camera may be disconnected or in use by another application",
            operation
        ))),
        GP_ERROR_NOT_SUPPORTED => Err(NativeError::NotSupported),
        GP_ERROR_CAMERA_BUSY => Err(NativeError::SdkError(format!(
            "gPhoto2 {}: camera busy - another operation is in progress",
            operation
        ))),
        GP_ERROR_MODEL_NOT_FOUND => Err(NativeError::DeviceNotFound(format!(
            "gPhoto2 {}: camera model not found",
            operation
        ))),
        _ => Err(NativeError::SdkError(format!(
            "gPhoto2 {}: error code {}",
            operation, code
        ))),
    }
}

// =============================================================================
// DSLR/MIRRORLESS CAMERA DETECTION
// =============================================================================

/// Detected DSLR/mirrorless camera info from autodetect
#[derive(Debug, Clone)]
pub struct DetectedGPhoto2Camera {
    pub model: String,
    pub port: String,
    pub index: usize,
    pub device_id: String,
}

/// Detect all connected gPhoto2-compatible cameras.
///
/// Returns a list of detected cameras with their model names and USB ports.
/// This function uses `gp_camera_autodetect` to find all connected PTP cameras.
pub fn detect_gphoto2_cameras() -> Vec<DetectedGPhoto2Camera> {
    let sdk = match GPhoto2Sdk::get() {
        Some(sdk) => sdk,
        None => return Vec::new(),
    };

    // SAFETY: gphoto2_mutex is implicitly held because `detect_gphoto2_cameras` runs
    // on the discovery code path that serializes SDK access (libgphoto2 is not
    // thread-safe). All `gp_*` calls are paired with their explicit free/unref calls
    // before this block exits — `context_unref` matches `context_new`, `list_free`
    // matches `list_new`. Out-pointers (`list`) and the stack-owned `count` are valid
    // local addresses for the duration of the call.
    unsafe {
        let context = (sdk.context_new)();
        if context.is_null() {
            tracing::error!("gPhoto2: Failed to create context");
            return Vec::new();
        }

        let mut list: *mut CameraList = std::ptr::null_mut();
        let ret = (sdk.list_new)(&mut list);
        if ret < GP_OK || list.is_null() {
            tracing::error!("gPhoto2: Failed to create camera list: {}", ret);
            (sdk.context_unref)(context);
            return Vec::new();
        }

        let ret = (sdk.camera_autodetect)(list, context);
        if ret < GP_OK {
            tracing::debug!("gPhoto2: No cameras detected (code {})", ret);
            (sdk.list_free)(list);
            (sdk.context_unref)(context);
            return Vec::new();
        }

        let count = (sdk.list_count)(list);
        let mut cameras = Vec::new();

        for i in 0..count {
            let mut name_ptr: *const c_char = std::ptr::null();
            let mut value_ptr: *const c_char = std::ptr::null();

            if (sdk.list_get_name)(list, i, &mut name_ptr) >= GP_OK
                && (sdk.list_get_value)(list, i, &mut value_ptr) >= GP_OK
            {
                let model = if !name_ptr.is_null() {
                    CStr::from_ptr(name_ptr).to_string_lossy().to_string()
                } else {
                    format!("Unknown Camera {}", i)
                };

                let port = if !value_ptr.is_null() {
                    CStr::from_ptr(value_ptr).to_string_lossy().to_string()
                } else {
                    String::new()
                };

                cameras.push(DetectedGPhoto2Camera {
                    device_id: build_device_id(i as usize, &model, &port),
                    model,
                    port,
                    index: i as usize,
                });
            }
        }

        (sdk.list_free)(list);
        (sdk.context_unref)(context);

        tracing::info!("gPhoto2: Detected {} cameras", cameras.len());
        for cam in &cameras {
            tracing::info!("  - {} on {}", cam.model, cam.port);
        }

        cameras
    }
}

// =============================================================================
// GPHOTO2 CAMERA IMPLEMENTATION
// =============================================================================

/// Known DSLR shutter speed values mapped to durations in seconds.
/// Used to find the closest matching shutter speed for exposures <= 30s.
const SHUTTER_SPEEDS: &[(f64, &str)] = &[
    (0.000125, "1/8000"),
    (0.00025, "1/4000"),
    (0.0005, "1/2000"),
    (0.001, "1/1000"),
    (0.002, "1/500"),
    (0.004, "1/250"),
    (0.005, "1/200"),
    (0.008, "1/125"),
    (0.01, "1/100"),
    (0.0125, "1/80"),
    (0.01667, "1/60"),
    (0.025, "1/40"),
    (0.03333, "1/30"),
    (0.04, "1/25"),
    (0.05, "1/20"),
    (0.066667, "1/15"),
    (0.076923, "1/13"),
    (0.1, "1/10"),
    (0.125, "1/8"),
    (0.166667, "1/6"),
    (0.2, "1/5"),
    (0.25, "1/4"),
    (0.3, "0.3"),
    (0.4, "0.4"),
    (0.5, "0.5"),
    (0.625, "0.625"),
    (0.7692, "0.7692"),
    (1.0, "1"),
    (1.3, "1.3"),
    (1.6, "1.6"),
    (2.0, "2"),
    (2.5, "2.5"),
    (3.2, "3.2"),
    (4.0, "4"),
    (5.0, "5"),
    (6.0, "6"),
    (8.0, "8"),
    (10.0, "10"),
    (13.0, "13"),
    (15.0, "15"),
    (20.0, "20"),
    (25.0, "25"),
    (30.0, "30"),
];

/// Exposure state tracking
#[derive(Debug, Clone, Copy, PartialEq)]
enum ExposureState {
    Idle,
    /// Normal exposure via gp_camera_capture — the library blocks until done,
    /// so from the driver's perspective the exposure completes synchronously.
    /// We track the start time so `is_exposure_complete` can signal when the
    /// expected duration has elapsed.
    Exposing {
        start: Instant,
        duration_secs: f64,
    },
    /// Bulb exposure triggered via gp_camera_trigger_capture.
    /// Needs explicit stop after the desired duration.
    BulbExposing {
        start: Instant,
        duration_secs: f64,
    },
    /// Exposure done, image waiting to be downloaded from camera storage.
    Complete,
    /// Exposure failed.
    Failed,
}

/// gPhoto2 DSLR/Mirrorless Camera implementation
pub struct GPhoto2Camera {
    /// Camera index from autodetect
    camera_index: usize,
    /// Camera model name
    model_name: String,
    /// USB port path
    port_path: String,
    /// Unique device ID
    device_id: String,
    /// Connected state
    connected: bool,

    /// gPhoto2 camera handle (owned, must be freed on disconnect)
    gp_camera: *mut GPCamera,
    /// gPhoto2 context handle (owned, must be freed on disconnect)
    gp_context: *mut GPContext,

    // Cached sensor info (populated on connect from EXIF/config)
    sensor_width: u32,
    sensor_height: u32,
    pixel_size: f64,
    bit_depth: u32,
    is_color: bool,

    // Camera capabilities (populated on connect)
    can_capture: bool,
    can_preview: bool,
    can_configure: bool,
    can_bulb: bool,

    // Available ISO values (populated on connect)
    iso_values: Vec<String>,
    current_iso_index: i32,

    // Available shutter speed values (populated on connect)
    shutter_speed_values: Vec<String>,

    // Exposure tracking
    exposure_state: ExposureState,
    exposure_time: f64,
    current_gain: i32,   // Maps to ISO index
    current_offset: i32, // Not used for DSLRs, always 0

    // Last captured file path on camera (for download)
    last_capture_path: Option<CameraFilePath>,

    // Last downloaded raw image bytes (for decoding)
    last_raw_data: Option<Vec<u8>>,
}

// Implement Debug manually since raw pointers don't implement Debug
impl std::fmt::Debug for GPhoto2Camera {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("GPhoto2Camera")
            .field("camera_index", &self.camera_index)
            .field("model_name", &self.model_name)
            .field("port_path", &self.port_path)
            .field("device_id", &self.device_id)
            .field("connected", &self.connected)
            .field("sensor_width", &self.sensor_width)
            .field("sensor_height", &self.sensor_height)
            .field("exposure_state", &self.exposure_state)
            .finish()
    }
}

// SAFETY: GPhoto2Camera is Send+Sync because all gphoto2 SDK calls are protected
// by the gphoto2_mutex, ensuring only one thread accesses the camera at a time.
// The raw `gp_camera` / `gp_context` pointers stored in this struct are only
// dereferenced inside lock-held `unsafe` blocks in the impls below.
unsafe impl Send for GPhoto2Camera {}
// SAFETY: Same justification as the `Send` impl above — gphoto2_mutex serializes all
// SDK access, so concurrent `&GPhoto2Camera` references never reach libgphoto2 at the
// same time.
unsafe impl Sync for GPhoto2Camera {}

impl GPhoto2Camera {
    /// Create a new gPhoto2 camera instance from a detected camera.
    pub fn new(index: usize, model: &str, port: &str) -> Self {
        Self {
            camera_index: index,
            model_name: model.to_string(),
            port_path: port.to_string(),
            device_id: build_device_id(index, model, port),
            connected: false,
            gp_camera: std::ptr::null_mut(),
            gp_context: std::ptr::null_mut(),
            sensor_width: 0,
            sensor_height: 0,
            pixel_size: 0.0,
            bit_depth: 14,  // Most DSLRs are 14-bit
            is_color: true, // All DSLRs are color
            can_capture: false,
            can_preview: false,
            can_configure: false,
            can_bulb: false,
            iso_values: Vec::new(),
            current_iso_index: 0,
            shutter_speed_values: Vec::new(),
            exposure_state: ExposureState::Idle,
            exposure_time: 0.0,
            current_gain: 0,
            current_offset: 0,
            last_capture_path: None,
            last_raw_data: None,
        }
    }

    /// Get the closest shutter speed string for a given duration.
    /// Returns None if the duration is longer than 30s (use Bulb mode).
    fn find_shutter_speed(&self, duration_secs: f64) -> Option<String> {
        // First check if the camera has reported available shutter speeds
        if !self.shutter_speed_values.is_empty() {
            // Try to find exact or closest match from the camera's available values
            let mut best_match: Option<(f64, &str)> = None;

            for speed_str in &self.shutter_speed_values {
                if let Some(secs) = parse_shutter_speed_to_secs(speed_str) {
                    let ratio = if secs > 0.0 && duration_secs > 0.0 {
                        (secs / duration_secs).ln().abs()
                    } else {
                        f64::MAX
                    };
                    if best_match.is_none() || ratio < best_match.unwrap().0 {
                        best_match = Some((ratio, speed_str));
                    }
                }
            }

            if let Some((_, speed_str)) = best_match {
                return Some(speed_str.to_string());
            }
        }

        // Fall back to the known speed table
        if duration_secs > 30.0 {
            return None; // Use Bulb
        }

        let mut best: Option<(f64, &str)> = None;
        for &(secs, name) in SHUTTER_SPEEDS {
            let ratio = (secs / duration_secs).ln().abs();
            if best.is_none() || ratio < best.unwrap().0 {
                best = Some((ratio, name));
            }
        }
        best.map(|(_, name)| name.to_string())
    }

    /// Read a string configuration value from the camera.
    /// Caller must hold gphoto2_mutex.
    fn get_config_value_str(&self, name: &str) -> Result<String, NativeError> {
        let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // SAFETY: caller holds gphoto2_mutex (documented in the doc-comment above and
        // checked by all call sites). `self.gp_camera`/`self.gp_context` are non-null
        // valid pointers obtained from `camera_new`/`context_new` while connected.
        // `root` is a stack out-pointer; `widget_free(root)` runs on every exit path.
        // `CStr::from_ptr(value_ptr)` is gated on a successful (`ret >= GP_OK`) widget
        // read and a non-null `value_ptr`, so the pointer is a NUL-terminated C string
        // borrowed from libgphoto2 internals.
        unsafe {
            let mut root: *mut CameraWidget = std::ptr::null_mut();
            let ret = (sdk.camera_get_config)(self.gp_camera, &mut root, self.gp_context);
            if ret < GP_OK {
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: get_config failed for '{}': code {}",
                    name, ret
                )));
            }

            let c_name = CString::new(name).map_err(|_| {
                NativeError::InvalidParameter(format!("Invalid config name: {}", name))
            })?;

            let mut child: *mut CameraWidget = std::ptr::null_mut();
            let ret = (sdk.widget_get_child_by_name)(root, c_name.as_ptr(), &mut child);
            if ret < GP_OK {
                (sdk.widget_free)(root);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: config '{}' not found on this camera",
                    name
                )));
            }

            let mut value_ptr: *const c_char = std::ptr::null();
            let ret =
                (sdk.widget_get_value)(child, &mut value_ptr as *mut *const c_char as *mut c_void);
            if ret < GP_OK || value_ptr.is_null() {
                (sdk.widget_free)(root);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: failed to read config '{}': code {}",
                    name, ret
                )));
            }

            let value = CStr::from_ptr(value_ptr).to_string_lossy().to_string();
            (sdk.widget_free)(root);
            Ok(value)
        }
    }

    /// Set a string configuration value on the camera.
    /// Caller must hold gphoto2_mutex.
    fn set_config_value_str(&self, name: &str, value: &str) -> Result<(), NativeError> {
        let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // SAFETY: caller holds gphoto2_mutex (per doc-comment). `self.gp_camera` /
        // `self.gp_context` are valid non-null pointers post-connect. `root` is a stack
        // out-pointer; `widget_free(root)` is called on every exit path. `c_name` /
        // `c_value` are CString owners that outlive their `.as_ptr()` use inside the
        // block. `widget_set_value` followed by `camera_set_config` is the libgphoto2
        // configured-write sequence.
        unsafe {
            let mut root: *mut CameraWidget = std::ptr::null_mut();
            let ret = (sdk.camera_get_config)(self.gp_camera, &mut root, self.gp_context);
            check_gp_error(ret, "get_config")?;

            let c_name = CString::new(name).map_err(|_| {
                NativeError::InvalidParameter(format!("Invalid config name: {}", name))
            })?;

            let mut child: *mut CameraWidget = std::ptr::null_mut();
            let ret = (sdk.widget_get_child_by_name)(root, c_name.as_ptr(), &mut child);
            if ret < GP_OK {
                (sdk.widget_free)(root);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: config '{}' not found on this camera",
                    name
                )));
            }

            let c_value = CString::new(value).map_err(|_| {
                NativeError::InvalidParameter(format!("Invalid config value: {}", value))
            })?;

            let ret = (sdk.widget_set_value)(child, c_value.as_ptr() as *const c_void);
            if ret < GP_OK {
                (sdk.widget_free)(root);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: failed to set config '{}' to '{}': code {}",
                    name, value, ret
                )));
            }

            let ret = (sdk.camera_set_config)(self.gp_camera, root, self.gp_context);
            (sdk.widget_free)(root);
            check_gp_error(ret, "set_config")?;

            Ok(())
        }
    }

    /// Get all available choices for a radio/menu configuration value.
    /// Caller must hold gphoto2_mutex.
    fn get_config_choices(&self, name: &str) -> Result<Vec<String>, NativeError> {
        let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // SAFETY: caller holds gphoto2_mutex (per doc-comment). `gp_camera`/`gp_context`
        // are valid non-null post-connect; `root` is a stack out-pointer freed on
        // every exit path. Each `widget_get_choice` call's out-pointer (`choice_ptr`)
        // is only dereferenced via `CStr::from_ptr` after the return code is checked
        // and non-null guard passes; the choice C-string is owned by the widget tree.
        unsafe {
            let mut root: *mut CameraWidget = std::ptr::null_mut();
            let ret = (sdk.camera_get_config)(self.gp_camera, &mut root, self.gp_context);
            check_gp_error(ret, "get_config")?;

            let c_name = CString::new(name).map_err(|_| {
                NativeError::InvalidParameter(format!("Invalid config name: {}", name))
            })?;

            let mut child: *mut CameraWidget = std::ptr::null_mut();
            let ret = (sdk.widget_get_child_by_name)(root, c_name.as_ptr(), &mut child);
            if ret < GP_OK {
                (sdk.widget_free)(root);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: config '{}' not found",
                    name
                )));
            }

            let count = (sdk.widget_count_choices)(child);
            let mut choices = Vec::new();

            for i in 0..count {
                let mut choice_ptr: *const c_char = std::ptr::null();
                if (sdk.widget_get_choice)(child, i, &mut choice_ptr) >= GP_OK
                    && !choice_ptr.is_null()
                {
                    let choice = CStr::from_ptr(choice_ptr).to_string_lossy().to_string();
                    choices.push(choice);
                }
            }

            (sdk.widget_free)(root);
            Ok(choices)
        }
    }

    /// Populate camera info (sensor dims, ISO values, etc.) after connecting.
    /// Caller must hold gphoto2_mutex.
    fn populate_camera_info(&mut self) -> Result<(), NativeError> {
        let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Query camera abilities to determine supported operations
        // SAFETY: caller holds gphoto2_mutex (per doc-comment on populate_camera_info).
        // `gp_camera` is valid non-null post-connect; `abilities` is a stack-allocated
        // POD struct (`#[derive(Default)]`) whose address is passed as the out-pointer
        // — libgphoto2 fills the struct by value, no internal pointers retained.
        unsafe {
            let mut abilities: CameraAbilities = CameraAbilities::default();
            let ret = (sdk.camera_get_abilities)(self.gp_camera, &mut abilities);
            if ret >= GP_OK {
                self.can_capture = (abilities.operations & GP_OPERATION_CAPTURE_IMAGE) != 0;
                self.can_preview = (abilities.operations & GP_OPERATION_CAPTURE_PREVIEW) != 0;
                self.can_configure = (abilities.operations & GP_OPERATION_CONFIG) != 0;
                self.can_bulb = (abilities.operations & GP_OPERATION_TRIGGER_CAPTURE) != 0;

                tracing::info!(
                    "gPhoto2 camera abilities: capture={}, preview={}, config={}, bulb={}",
                    self.can_capture,
                    self.can_preview,
                    self.can_configure,
                    self.can_bulb
                );
            }
        }

        // Try to read ISO values
        match self.get_config_choices("iso") {
            Ok(isos) => {
                tracing::info!("gPhoto2: Available ISO values: {:?}", isos);
                self.iso_values = isos;
            }
            Err(e) => {
                tracing::warn!("gPhoto2: Could not read ISO values: {}", e);
                // Use a reasonable default set
                self.iso_values = vec![
                    "100".to_string(),
                    "200".to_string(),
                    "400".to_string(),
                    "800".to_string(),
                    "1600".to_string(),
                    "3200".to_string(),
                    "6400".to_string(),
                ];
            }
        }

        // Get current ISO and map to gain index
        match self.get_config_value_str("iso") {
            Ok(current_iso) => {
                self.current_iso_index = self
                    .iso_values
                    .iter()
                    .position(|v| v == &current_iso)
                    .unwrap_or(0) as i32;
                self.current_gain = self.current_iso_index;
                tracing::info!(
                    "gPhoto2: Current ISO: {} (index {})",
                    current_iso,
                    self.current_iso_index
                );
            }
            Err(e) => {
                tracing::warn!("gPhoto2: Could not read current ISO: {}", e);
            }
        }

        // Try to read available shutter speeds
        match self.get_config_choices("shutterspeed") {
            Ok(speeds) => {
                tracing::info!("gPhoto2: Available shutter speeds: {:?}", speeds);
                self.shutter_speed_values = speeds;
            }
            Err(_) => {
                // Some cameras use "shutterspeed2" or other names
                match self.get_config_choices("shutterspeed2") {
                    Ok(speeds) => {
                        self.shutter_speed_values = speeds;
                    }
                    Err(_) => {
                        tracing::warn!("gPhoto2: Could not read shutter speed choices");
                    }
                }
            }
        }

        // Try to detect sensor dimensions from image format or camera model
        // Most DSLRs don't report sensor dims via PTP; we use common values
        self.detect_sensor_dimensions();

        Ok(())
    }

    /// Detect sensor dimensions based on camera model or image quality settings.
    /// Most DSLRs don't expose raw sensor dimensions via PTP, so we use a lookup
    /// of known models. Falls back to reasonable defaults.
    fn detect_sensor_dimensions(&mut self) {
        let model_lower = self.model_name.to_lowercase();

        // Common DSLR sensor dimensions by model family
        // (width, height, pixel_size_um, bit_depth)
        let (w, h, px, bits) = if model_lower.contains("6d mark ii") || model_lower.contains("6d2")
        {
            (6240, 4160, 5.7, 14)
        } else if model_lower.contains("5d mark iv") || model_lower.contains("5d4") {
            (6720, 4480, 5.4, 14)
        } else if model_lower.contains("5d mark iii") || model_lower.contains("5d3") {
            (5760, 3840, 6.3, 14)
        } else if model_lower.contains("eos r5") {
            (8192, 5464, 4.4, 14)
        } else if model_lower.contains("eos r6") || model_lower.contains("eos r6 ii") {
            (5472, 3648, 6.5, 14)
        } else if model_lower.contains("eos r")
            && !model_lower.contains("eos r5")
            && !model_lower.contains("eos r6")
            && !model_lower.contains("eos rp")
        {
            (6720, 4480, 5.4, 14)
        } else if model_lower.contains("eos rp") {
            (6240, 4160, 5.7, 14)
        } else if model_lower.contains("eos ra") {
            (6720, 4480, 5.4, 14) // Same as EOS R, H-alpha modified
        } else if model_lower.contains("d850") {
            (8256, 5504, 4.3, 14)
        } else if model_lower.contains("d810") {
            (7360, 4912, 4.9, 14)
        } else if model_lower.contains("d750") {
            (6016, 4016, 5.9, 14)
        } else if model_lower.contains("d610") || model_lower.contains("d600") {
            (6016, 4016, 5.9, 14)
        } else if model_lower.contains("z5") || model_lower.contains("z 5") {
            (6016, 4016, 5.9, 14)
        } else if model_lower.contains("z6") || model_lower.contains("z 6") {
            (6048, 4024, 5.9, 14)
        } else if model_lower.contains("z7") || model_lower.contains("z 7") {
            (8256, 5504, 4.3, 14)
        } else if model_lower.contains("a7r iv") || model_lower.contains("ilce-7rm4") {
            (9504, 6336, 3.7, 14)
        } else if model_lower.contains("a7r iii") || model_lower.contains("ilce-7rm3") {
            (7952, 5304, 4.5, 14)
        } else if model_lower.contains("a7 iii") || model_lower.contains("ilce-7m3") {
            (6000, 4000, 5.9, 14)
        } else if model_lower.contains("a7s") || model_lower.contains("ilce-7s") {
            (4240, 2832, 8.4, 14)
        } else if model_lower.contains("a6600") || model_lower.contains("ilce-6600") {
            (6000, 4000, 3.9, 14)
        } else if model_lower.contains("1000d") || model_lower.contains("rebel xs") {
            (3888, 2592, 5.7, 12)
        } else if model_lower.contains("1100d") || model_lower.contains("rebel t3") {
            (4272, 2848, 5.2, 12)
        } else if model_lower.contains("1200d") || model_lower.contains("rebel t5") {
            (5184, 3456, 4.3, 14)
        } else if model_lower.contains("1300d") || model_lower.contains("rebel t6") {
            (5184, 3456, 4.3, 14)
        } else if model_lower.contains("600d") || model_lower.contains("rebel t3i") {
            (5184, 3456, 4.3, 14)
        } else if model_lower.contains("700d") || model_lower.contains("rebel t5i") {
            (5184, 3456, 4.3, 14)
        } else if model_lower.contains("800d") || model_lower.contains("rebel t7i") {
            (6000, 4000, 3.7, 14)
        } else if model_lower.contains("200d") || model_lower.contains("rebel sl2") {
            (6000, 4000, 3.7, 14)
        } else if model_lower.contains("60da") || model_lower.contains("60d") {
            (5184, 3456, 4.3, 14)
        } else if model_lower.contains("k-70") || model_lower.contains("k70") {
            (6000, 4000, 3.9, 14)
        } else if model_lower.contains("k-1") || model_lower.contains("k1") {
            (7360, 4912, 4.9, 14)
        } else {
            // Reasonable defaults for an unknown full-frame DSLR
            tracing::warn!(
                "gPhoto2: Unknown camera model '{}', using default 6000x4000 sensor dimensions",
                self.model_name
            );
            (6000, 4000, 5.9, 14)
        };

        self.sensor_width = w;
        self.sensor_height = h;
        self.pixel_size = px;
        self.bit_depth = bits;

        tracing::info!(
            "gPhoto2: Sensor dimensions: {}x{}, pixel size: {:.1}um, bit depth: {}",
            w,
            h,
            px,
            bits
        );
    }

    /// Perform a standard (non-bulb) capture. Blocks until the camera completes the exposure.
    /// Caller must hold gphoto2_mutex.
    fn do_capture(&mut self) -> Result<(), NativeError> {
        let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;

        let mut file_path = CameraFilePath::default();

        // SAFETY: caller holds gphoto2_mutex (per doc-comment). `gp_camera` and
        // `gp_context` are valid non-null pointers post-connect. `file_path` is a stack
        // POD that libgphoto2 fills in-place with the folder/name buffers.
        unsafe {
            let ret = (sdk.camera_capture)(
                self.gp_camera,
                CameraCaptureType::Image as c_int,
                &mut file_path,
                self.gp_context,
            );
            check_gp_error(ret, "camera_capture")?;
        }

        tracing::info!(
            "gPhoto2: Captured image: {}/{}",
            cstr_from_array(&file_path.folder),
            cstr_from_array(&file_path.name)
        );

        self.last_capture_path = Some(file_path);
        Ok(())
    }

    /// Start a bulb exposure by triggering the shutter.
    /// Caller must hold gphoto2_mutex.
    fn do_bulb_start(&mut self) -> Result<(), NativeError> {
        let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;

        // Set camera to Bulb shutter speed
        if let Err(e) = self.set_config_value_str("shutterspeed", "Bulb") {
            // Try alternate names
            if let Err(e2) = self.set_config_value_str("shutterspeed", "bulb") {
                tracing::warn!(
                    "gPhoto2: Could not set Bulb mode (tried 'Bulb' and 'bulb'): {}, {}",
                    e,
                    e2
                );
                return Err(NativeError::SdkError(
                    "gPhoto2: Camera does not support Bulb mode for long exposures".to_string(),
                ));
            }
        }

        // Trigger capture (opens shutter, does not wait for completion)
        // SAFETY: caller holds gphoto2_mutex. `gp_camera`/`gp_context` are valid
        // non-null pointers post-connect; `camera_trigger_capture` takes them by-value
        // and returns a result code we check.
        unsafe {
            let ret = (sdk.camera_trigger_capture)(self.gp_camera, self.gp_context);
            check_gp_error(ret, "trigger_capture (bulb start)")?;
        }

        tracing::info!("gPhoto2: Bulb exposure started");
        Ok(())
    }

    /// Stop a bulb exposure by releasing the shutter via eosremoterelease or bulb toggle.
    /// Caller must hold gphoto2_mutex.
    fn do_bulb_stop(&mut self) -> Result<(), NativeError> {
        // Canon EOS cameras use eosremoterelease config to control bulb:
        // "None" -> "Immediate" opens shutter, "Release Full" closes it.
        // Nikon cameras may use "bulb" toggle config.
        // We try multiple approaches.

        // Approach 1: Canon EOS remote release
        if self
            .set_config_value_str("eosremoterelease", "Release Full")
            .is_ok()
        {
            tracing::info!("gPhoto2: Bulb stopped via eosremoterelease");
            // Reset to "None" after release
            let _ = self.set_config_value_str("eosremoterelease", "None");
            return Ok(());
        }

        // Approach 2: Nikon bulb toggle
        if self.set_config_value_str("bulb", "0").is_ok() {
            tracing::info!("gPhoto2: Bulb stopped via bulb toggle");
            return Ok(());
        }

        // Approach 3: Generic - send a second trigger to stop
        let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;
        // SAFETY: caller holds gphoto2_mutex (per do_bulb_stop's doc-comment).
        // `gp_camera`/`gp_context` are valid non-null. `event_type`/`event_data` are
        // stack out-pointers filled by libgphoto2. We do NOT dereference `event_data`
        // here (it would require a tag-typed cast); only `event_type` is read after.
        unsafe {
            // Wait for file-added event which signals the capture completed
            let mut event_type: c_int = 0;
            let mut event_data: *mut c_void = std::ptr::null_mut();
            let ret = (sdk.camera_wait_for_event)(
                self.gp_camera,
                2000, // 2 second timeout
                &mut event_type,
                &mut event_data,
                self.gp_context,
            );
            if ret >= GP_OK {
                tracing::info!("gPhoto2: Bulb stop - received event type {}", event_type);
            }
        }

        tracing::info!("gPhoto2: Bulb exposure stopped");
        Ok(())
    }

    /// Download the last captured image from the camera as raw bytes.
    /// Caller must hold gphoto2_mutex.
    fn download_from_camera(&mut self) -> Result<Vec<u8>, NativeError> {
        let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;

        let file_path = self.last_capture_path.as_ref().ok_or_else(|| {
            NativeError::SdkError("gPhoto2: No captured image to download".to_string())
        })?;

        let folder_str = cstr_from_array(&file_path.folder);
        let name_str = cstr_from_array(&file_path.name);

        let c_folder = CString::new(folder_str.as_str())
            .map_err(|_| NativeError::SdkError("gPhoto2: Invalid folder path".to_string()))?;
        let c_name = CString::new(name_str.as_str())
            .map_err(|_| NativeError::SdkError("gPhoto2: Invalid file name".to_string()))?;

        // SAFETY: caller holds gphoto2_mutex (per download_from_camera's doc-comment).
        // `gp_camera`/`gp_context` are valid non-null post-connect. `gp_file` is a
        // stack out-pointer paired with `file_free` on every exit path. `c_folder`/
        // `c_name` are CString owners that outlive their `.as_ptr()` use. The
        // `data_ptr` / `data_size` out-pointers are read only after checking the
        // return code and non-null guard; the slice we build is immediately copied
        // into a Vec before `file_free` invalidates the underlying buffer.
        unsafe {
            // Create a CameraFile to receive the data
            let mut gp_file: *mut CameraFile = std::ptr::null_mut();
            let ret = (sdk.file_new)(&mut gp_file);
            check_gp_error(ret, "file_new")?;

            // Download the file from camera
            let ret = (sdk.camera_file_get)(
                self.gp_camera,
                c_folder.as_ptr(),
                c_name.as_ptr(),
                CameraFileType::Normal as c_int,
                gp_file,
                self.gp_context,
            );
            if ret < GP_OK {
                (sdk.file_free)(gp_file);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: Failed to download image {}/{}: code {}",
                    folder_str, name_str, ret
                )));
            }

            // Get the data pointer and size
            let mut data_ptr: *const c_char = std::ptr::null();
            let mut data_size: u64 = 0;
            let ret = (sdk.file_get_data_and_size)(gp_file, &mut data_ptr, &mut data_size);
            if ret < GP_OK || data_ptr.is_null() || data_size == 0 {
                (sdk.file_free)(gp_file);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: Failed to read image data: code {}",
                    ret
                )));
            }

            // Copy data into our own buffer (gp_file owns the pointer)
            let data = std::slice::from_raw_parts(data_ptr as *const u8, data_size as usize);
            let raw_bytes = data.to_vec();

            tracing::info!(
                "gPhoto2: Downloaded {} bytes from {}/{}",
                raw_bytes.len(),
                folder_str,
                name_str
            );

            // Free the CameraFile
            (sdk.file_free)(gp_file);

            // Delete the file from camera to free space (optional, but good practice)
            let del_ret = (sdk.camera_file_delete)(
                self.gp_camera,
                c_folder.as_ptr(),
                c_name.as_ptr(),
                self.gp_context,
            );
            if del_ret < GP_OK {
                tracing::warn!(
                    "gPhoto2: Could not delete image from camera (code {}), card may fill up",
                    del_ret
                );
            }

            Ok(raw_bytes)
        }
    }

    /// Decode raw camera file (CR2, NEF, ARW, etc.) to 16-bit pixel data.
    /// Uses the raw bytes downloaded from the camera.
    fn decode_raw_to_image_data(&self, raw_bytes: &[u8]) -> Result<ImageData, NativeError> {
        // Detect the RAW format from magic bytes to get the correct file extension
        let extension = nightshade_imaging::raw_format_extension(raw_bytes).unwrap_or("raw");

        // Use nightshade_imaging's LibRaw wrapper to decode the RAW file
        let (imaging_data, metadata) =
            nightshade_imaging::read_raw_from_bytes(raw_bytes, extension, None).map_err(|e| {
                NativeError::SdkError(format!("gPhoto2: Failed to decode RAW image: {}", e))
            })?;

        tracing::info!(
            "gPhoto2: Decoded RAW image: {}x{}, camera: {} {}",
            imaging_data.width,
            imaging_data.height,
            metadata.camera_make,
            metadata.camera_model,
        );

        // Convert the imaging crate's ImageData (Vec<u8> with PixelType) to
        // the camera crate's ImageData (Vec<u16>).
        // LibRaw typically returns U16 pixel data for RAW files.
        let pixel_data_u16: Vec<u16> =
            if imaging_data.pixel_type == nightshade_imaging::PixelType::U16 {
                // Data is already 16-bit, reinterpret bytes as u16 (little-endian)
                imaging_data
                    .data
                    .chunks_exact(2)
                    .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                    .collect()
            } else if imaging_data.pixel_type == nightshade_imaging::PixelType::U8 {
                // 8-bit data, scale up to 16-bit
                imaging_data.data.iter().map(|&b| (b as u16) << 8).collect()
            } else {
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: Unexpected pixel type {:?} from LibRaw",
                    imaging_data.pixel_type
                )));
            };

        // Determine bit depth from the decoded data
        let bit_depth = if imaging_data.pixel_type == nightshade_imaging::PixelType::U16 {
            self.bit_depth // Use the camera's known bit depth (typically 14)
        } else {
            8
        };

        // Determine Bayer pattern from the color description
        let bayer_pattern = match metadata.color_desc.as_str() {
            "RGBG" | "RGGB" => Some(BayerPattern::Rggb),
            "GRBG" => Some(BayerPattern::Grbg),
            "GBRG" => Some(BayerPattern::Gbrg),
            "BGGR" => Some(BayerPattern::Bggr),
            _ => Some(BayerPattern::Rggb), // Default to RGGB (most common)
        };

        Ok(ImageData {
            width: imaging_data.width,
            height: imaging_data.height,
            data: pixel_data_u16,
            bits_per_pixel: bit_depth,
            bayer_pattern,
            metadata: ImageMetadata {
                exposure_time: self.exposure_time,
                gain: self.current_gain,
                offset: self.current_offset,
                bin_x: 1,
                bin_y: 1,
                temperature: None, // DSLRs don't report sensor temp
                timestamp: chrono::Utc::now(),
                subframe: None,
                readout_mode: None,
                vendor_data: VendorFeatures {
                    custom_data: {
                        let mut map = std::collections::HashMap::new();
                        if let Some(iso_str) = self.iso_values.get(self.current_gain as usize) {
                            map.insert(
                                "iso".to_string(),
                                serde_json::Value::String(iso_str.clone()),
                            );
                        }
                        map.insert(
                            "camera_model".to_string(),
                            serde_json::Value::String(self.model_name.clone()),
                        );
                        if metadata.iso_speed.is_some() {
                            map.insert(
                                "exif_iso".to_string(),
                                serde_json::json!(metadata.iso_speed),
                            );
                        }
                        if metadata.shutter_speed.is_some() {
                            map.insert(
                                "exif_shutter".to_string(),
                                serde_json::json!(metadata.shutter_speed),
                            );
                        }
                        map
                    },
                    ..Default::default()
                },
            },
        })
    }
}

// =============================================================================
// NativeDevice IMPLEMENTATION
// =============================================================================

#[async_trait]
impl NativeDevice for GPhoto2Camera {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.model_name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::GPhoto2
    }

    fn is_connected(&self) -> bool {
        self.connected
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        tracing::info!(
            "Connecting to gPhoto2 camera: {} on {}",
            self.model_name,
            self.port_path
        );

        let sdk = GPhoto2Sdk::get().ok_or_else(|| {
            tracing::error!("Cannot connect to DSLR camera: libgphoto2 not loaded");
            NativeError::SdkNotLoaded
        })?;

        let _lock = gphoto2_mutex().lock().await;

        let detected = detect_gphoto2_cameras();
        if self.port_path.is_empty() {
            if detected.len() > 1 {
                return Err(NativeError::InvalidDevice(format!(
                    "gPhoto2 device '{}' does not encode a stable USB port and cannot be safely selected while multiple cameras are connected",
                    self.model_name
                )));
            }
        } else {
            let desired = detected
                .iter()
                .find(|camera| camera.port == self.port_path)
                .ok_or_else(|| {
                    NativeError::DeviceNotFound(format!(
                        "gPhoto2 camera '{}' on '{}' is no longer present",
                        self.model_name, self.port_path
                    ))
                })?;

            self.camera_index = desired.index;
            if detected.len() > 1 && desired.index != 0 {
                return Err(NativeError::InvalidDevice(format!(
                    "gPhoto2 cannot safely bind '{}' on '{}' while another camera is enumerated first",
                    self.model_name, self.port_path
                )));
            }
        }

        // SAFETY: caller holds gphoto2_mutex (this method is invoked from `connect`,
        // which acquires the lock). All `gp_*` allocations are paired with their
        // corresponding free/unref on every error path; on success the resources are
        // stored in `self.gp_camera` / `self.gp_context` and live until `disconnect`.
        // Out-pointer (`camera`) is a stack local.
        unsafe {
            // Create context
            let context = (sdk.context_new)();
            if context.is_null() {
                return Err(NativeError::SdkError(
                    "gPhoto2: Failed to create context".to_string(),
                ));
            }

            // Create camera
            let mut camera: *mut GPCamera = std::ptr::null_mut();
            let ret = (sdk.camera_new)(&mut camera);
            if ret < GP_OK || camera.is_null() {
                (sdk.context_unref)(context);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: Failed to create camera object: code {}",
                    ret
                )));
            }

            // Initialize camera (auto-detects and connects to first available camera)
            let ret = (sdk.camera_init)(camera, context);
            if ret < GP_OK {
                (sdk.camera_free)(camera);
                (sdk.context_unref)(context);
                return Err(NativeError::SdkError(format!(
                    "gPhoto2: Failed to initialize camera '{}': code {} - camera may be in use by another application or not connected via USB",
                    self.model_name, ret
                )));
            }

            self.gp_camera = camera;
            self.gp_context = context;
        }

        // Read camera info (ISO values, abilities, sensor dimensions)
        if let Err(e) = self.populate_camera_info() {
            tracing::warn!("gPhoto2: Failed to populate camera info: {}", e);
            // Non-fatal — we can still capture with defaults
        }

        self.connected = true;
        tracing::info!(
            "Successfully connected to gPhoto2 camera: {} ({}x{}, {}-bit)",
            self.model_name,
            self.sensor_width,
            self.sensor_height,
            self.bit_depth
        );
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if self.connected {
            let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;
            let _lock = gphoto2_mutex().lock().await;

            // SAFETY: `_lock` (gphoto2_mutex guard) is held for the entire block. Each
            // raw pointer is non-null-checked before use and set to null after free so
            // a subsequent drop does not double-free. `camera_exit`+`camera_free` is
            // the libgphoto2-documented teardown sequence; `context_unref` releases
            // the context refcount.
            unsafe {
                if !self.gp_camera.is_null() {
                    let _ = (sdk.camera_exit)(self.gp_camera, self.gp_context);
                    (sdk.camera_free)(self.gp_camera);
                    self.gp_camera = std::ptr::null_mut();
                }

                if !self.gp_context.is_null() {
                    (sdk.context_unref)(self.gp_context);
                    self.gp_context = std::ptr::null_mut();
                }
            }

            self.connected = false;
            self.exposure_state = ExposureState::Idle;
            self.last_capture_path = None;
            self.last_raw_data = None;

            tracing::info!("Disconnected from gPhoto2 camera: {}", self.model_name);
        }
        Ok(())
    }
}

// =============================================================================
// NativeCamera IMPLEMENTATION
// =============================================================================

#[async_trait]
impl NativeCamera for GPhoto2Camera {
    fn capabilities(&self) -> CameraCapabilities {
        CameraCapabilities {
            can_cool: false,        // DSLRs don't have coolers
            can_set_gain: true,     // ISO mapped to gain
            can_set_offset: false,  // DSLRs don't have offset control
            can_set_binning: false, // DSLRs don't support binning
            can_subframe: false,    // DSLRs capture full frame only
            has_shutter: true,      // DSLRs have mechanical shutters
            has_guider_port: false, // DSLRs don't have ST-4 ports
            max_bin_x: 1,
            max_bin_y: 1,
            supports_readout_modes: false,
        }
    }

    async fn get_status(&self) -> Result<CameraStatus, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let state = match self.exposure_state {
            ExposureState::Idle => CameraState::Idle,
            ExposureState::Exposing {
                start,
                duration_secs,
            } => {
                let elapsed = start.elapsed().as_secs_f64();
                if elapsed >= duration_secs {
                    CameraState::Downloading
                } else {
                    CameraState::Exposing
                }
            }
            ExposureState::BulbExposing { .. } => CameraState::Exposing,
            ExposureState::Complete => CameraState::Idle,
            ExposureState::Failed => CameraState::Error,
        };

        let exposure_remaining = match self.exposure_state {
            ExposureState::Exposing {
                start,
                duration_secs,
            }
            | ExposureState::BulbExposing {
                start,
                duration_secs,
            } => {
                let remaining = duration_secs - start.elapsed().as_secs_f64();
                Some(remaining.max(0.0))
            }
            _ => None,
        };

        Ok(CameraStatus {
            state,
            sensor_temp: None, // DSLRs don't report sensor temp
            cooler_power: None,
            target_temp: None,
            cooler_on: false,
            gain: self.current_gain,
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

        let _lock = gphoto2_mutex().lock().await;

        // Set ISO (gain) if provided
        if let Some(gain) = params.gain {
            if gain >= 0 && (gain as usize) < self.iso_values.len() {
                let iso_str = &self.iso_values[gain as usize].clone();
                self.set_config_value_str("iso", iso_str)?;
                self.current_gain = gain;
                self.current_iso_index = gain;
                tracing::info!("gPhoto2: Set ISO to {} (gain index {})", iso_str, gain);
            } else {
                return Err(NativeError::InvalidParameter(format!(
                    "gPhoto2: Invalid gain/ISO index {}. Valid range: 0-{}",
                    gain,
                    self.iso_values.len().saturating_sub(1)
                )));
            }
        }

        self.exposure_time = params.duration_secs;
        let use_bulb = params.duration_secs > 30.0;

        if use_bulb {
            // Bulb mode for long exposures
            if !self.can_bulb {
                return Err(NativeError::SdkError(
                    "gPhoto2: Camera does not support Bulb mode for exposures > 30s".to_string(),
                ));
            }

            self.do_bulb_start()?;
            self.exposure_state = ExposureState::BulbExposing {
                start: Instant::now(),
                duration_secs: params.duration_secs,
            };

            tracing::info!(
                "gPhoto2: Started bulb exposure for {:.1}s",
                params.duration_secs
            );
        } else {
            // Standard capture: set shutter speed first, then capture
            if let Some(speed_str) = self.find_shutter_speed(params.duration_secs) {
                if let Err(e) = self.set_config_value_str("shutterspeed", &speed_str) {
                    tracing::warn!(
                        "gPhoto2: Could not set shutter speed to '{}': {}. Camera will use current setting.",
                        speed_str, e
                    );
                } else {
                    tracing::info!("gPhoto2: Set shutter speed to {}", speed_str);
                }
            }

            self.exposure_state = ExposureState::Exposing {
                start: Instant::now(),
                duration_secs: params.duration_secs,
            };

            // gp_camera_capture blocks until the exposure completes and the image is saved
            // on the camera's storage card. We run it in a blocking task so we don't block
            // the async runtime.
            //
            // Note: We need to release the mutex before spawning the blocking task,
            // then re-acquire it inside. However, since gp_camera_capture is a blocking
            // call that needs the mutex, we handle this by keeping the mutex and running
            // synchronously. The exposure polling system will check is_exposure_complete.
            self.do_capture()?;
            self.exposure_state = ExposureState::Complete;

            tracing::info!(
                "gPhoto2: Capture complete for {:.3}s exposure",
                params.duration_secs
            );
        }

        Ok(())
    }

    async fn abort_exposure(&mut self) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let _lock = gphoto2_mutex().lock().await;

        match self.exposure_state {
            ExposureState::BulbExposing { .. } => {
                self.do_bulb_stop()?;
                self.exposure_state = ExposureState::Idle;
                tracing::info!("gPhoto2: Bulb exposure aborted");
            }
            ExposureState::Exposing { .. } => {
                // Standard captures can't be interrupted mid-exposure on most DSLRs
                tracing::warn!("gPhoto2: Cannot abort a standard (non-bulb) exposure in progress");
                return Err(NativeError::SdkError(
                    "gPhoto2: Standard exposures cannot be aborted. Use Bulb mode for interruptible long exposures.".to_string(),
                ));
            }
            _ => {
                tracing::debug!("gPhoto2: No exposure in progress to abort");
            }
        }

        Ok(())
    }

    async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        match self.exposure_state {
            ExposureState::Idle => Ok(true),
            ExposureState::Complete => Ok(true),
            ExposureState::Failed => Err(NativeError::SdkError(
                "gPhoto2: Previous exposure failed".to_string(),
            )),
            ExposureState::Exposing {
                start,
                duration_secs,
            } => {
                // For standard captures, the capture already completed synchronously
                // in start_exposure. If we're still in Exposing state, it means
                // the duration hasn't elapsed yet (for UI progress tracking).
                Ok(start.elapsed().as_secs_f64() >= duration_secs)
            }
            ExposureState::BulbExposing {
                start,
                duration_secs,
            } => {
                // Check if the bulb exposure duration has elapsed
                Ok(start.elapsed().as_secs_f64() >= duration_secs)
            }
        }
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let _lock = gphoto2_mutex().lock().await;

        // If bulb exposure is complete, we need to stop it and wait for the file
        if let ExposureState::BulbExposing {
            start,
            duration_secs,
        } = self.exposure_state
        {
            if start.elapsed().as_secs_f64() >= duration_secs {
                self.do_bulb_stop()?;

                // After bulb stop, wait for the camera to save the file
                // and send us the file-added event
                let sdk = GPhoto2Sdk::get().ok_or(NativeError::SdkNotLoaded)?;
                let wait_start = Instant::now();
                let max_wait = Duration::from_secs(30);

                loop {
                    if wait_start.elapsed() > max_wait {
                        return Err(NativeError::Timeout(
                            "gPhoto2: Timed out waiting for camera to save image after bulb exposure".to_string(),
                        ));
                    }

                    // SAFETY: caller holds gphoto2_mutex (acquired in the outer
                    // method that contains this loop). `gp_camera`/`gp_context` are
                    // valid non-null. `event_data` is libgphoto2-owned and only
                    // dereferenced after both (a) `event_type == 2` confirms it is a
                    // GP_EVENT_FILE_ADDED payload (i.e. `*CameraFilePath`) and (b)
                    // the non-null guard passes; the borrow is then cloned into
                    // `self.last_capture_path` before the next loop iteration.
                    unsafe {
                        let mut event_type: c_int = 0;
                        let mut event_data: *mut c_void = std::ptr::null_mut();
                        let ret = (sdk.camera_wait_for_event)(
                            self.gp_camera,
                            1000, // 1 second timeout per poll
                            &mut event_type,
                            &mut event_data,
                            self.gp_context,
                        );

                        if ret < GP_OK {
                            tracing::warn!("gPhoto2: wait_for_event returned {}", ret);
                            break;
                        }

                        // Event type 2 = GP_EVENT_FILE_ADDED
                        if event_type == 2 && !event_data.is_null() {
                            // event_data points to a CameraFilePath
                            let path = &*(event_data as *const CameraFilePath);
                            self.last_capture_path = Some(path.clone());
                            tracing::info!(
                                "gPhoto2: Bulb image saved: {}/{}",
                                cstr_from_array(&path.folder),
                                cstr_from_array(&path.name)
                            );
                            break;
                        }
                    }
                }

                self.exposure_state = ExposureState::Complete;
            }
        }

        if self.exposure_state != ExposureState::Complete {
            return Err(NativeError::SdkError(
                "gPhoto2: No completed exposure to download".to_string(),
            ));
        }

        // Download the raw file from camera
        let raw_bytes = self.download_from_camera()?;

        // Reset state
        self.exposure_state = ExposureState::Idle;
        self.last_capture_path = None;

        // Decode the RAW file to 16-bit image data
        self.decode_raw_to_image_data(&raw_bytes)
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

        if gain < 0 || (gain as usize) >= self.iso_values.len() {
            return Err(NativeError::InvalidParameter(format!(
                "gPhoto2: Invalid gain/ISO index {}. Valid range: 0-{}",
                gain,
                self.iso_values.len().saturating_sub(1)
            )));
        }

        let _lock = gphoto2_mutex().lock().await;
        let iso_str = self.iso_values[gain as usize].clone();
        self.set_config_value_str("iso", &iso_str)?;
        self.current_gain = gain;
        self.current_iso_index = gain;

        tracing::info!("gPhoto2: Set ISO to {} (gain index {})", iso_str, gain);
        Ok(())
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        Ok(self.current_gain)
    }

    async fn set_offset(&mut self, _offset: i32) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        Ok(0) // DSLRs don't have offset control
    }

    async fn set_binning(&mut self, _bin_x: i32, _bin_y: i32) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_binning(&self) -> Result<(i32, i32), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }
        Ok((1, 1))
    }

    async fn set_subframe(&mut self, _subframe: Option<SubFrame>) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }

    fn get_sensor_info(&self) -> SensorInfo {
        SensorInfo {
            width: self.sensor_width,
            height: self.sensor_height,
            pixel_size_x: self.pixel_size,
            pixel_size_y: self.pixel_size,
            max_adu: (1u32 << self.bit_depth) - 1,
            bit_depth: self.bit_depth,
            color: self.is_color,
            bayer_pattern: Some(BayerPattern::Rggb),
        }
    }

    async fn get_readout_modes(&self) -> Result<Vec<ReadoutMode>, NativeError> {
        Ok(vec![ReadoutMode {
            name: "Standard".to_string(),
            description: "Standard DSLR readout".to_string(),
            index: 0,
            gain_min: Some(0),
            gain_max: Some(self.iso_values.len().saturating_sub(1) as i32),
            offset_min: None,
            offset_max: None,
        }])
    }

    async fn set_readout_mode(&mut self, _mode: &ReadoutMode) -> Result<(), NativeError> {
        // DSLRs only have one readout mode
        Ok(())
    }

    async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
        let mut features = VendorFeatures::default();
        let mut custom = std::collections::HashMap::new();

        custom.insert(
            "camera_model".to_string(),
            serde_json::Value::String(self.model_name.clone()),
        );

        if let Some(iso_str) = self.iso_values.get(self.current_gain as usize) {
            custom.insert(
                "iso".to_string(),
                serde_json::Value::String(iso_str.clone()),
            );
        }

        custom.insert(
            "can_bulb".to_string(),
            serde_json::Value::Bool(self.can_bulb),
        );
        custom.insert(
            "can_preview".to_string(),
            serde_json::Value::Bool(self.can_preview),
        );

        if !self.iso_values.is_empty() {
            custom.insert(
                "available_isos".to_string(),
                serde_json::Value::Array(
                    self.iso_values
                        .iter()
                        .map(|s| serde_json::Value::String(s.clone()))
                        .collect(),
                ),
            );
        }

        features.custom_data = custom;
        Ok(features)
    }

    async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
        if self.iso_values.is_empty() {
            return Err(NativeError::NotSupported);
        }
        Ok((0, self.iso_values.len().saturating_sub(1) as i32))
    }

    async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
        Err(NativeError::NotSupported)
    }
}

impl Drop for GPhoto2Camera {
    fn drop(&mut self) {
        // Ensure camera resources are cleaned up
        if self.connected {
            if let Some(sdk) = GPhoto2Sdk::get() {
                // SAFETY: Drop is best-effort cleanup. We do NOT acquire gphoto2_mutex
                // here because (a) Drop cannot await, and (b) Drop only runs when the
                // last owner is releasing the camera, so no other thread should be
                // touching `gp_camera`/`gp_context`. Each pointer is non-null-checked
                // before its corresponding free/unref. This is the same defensive
                // teardown pattern used by other vendor Drop impls.
                unsafe {
                    if !self.gp_camera.is_null() {
                        let _ = (sdk.camera_exit)(self.gp_camera, self.gp_context);
                        (sdk.camera_free)(self.gp_camera);
                    }
                    if !self.gp_context.is_null() {
                        (sdk.context_unref)(self.gp_context);
                    }
                }
            }
        }
    }
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/// Convert a fixed-size c_char array to a Rust String.
fn cstr_from_array(arr: &[c_char]) -> String {
    let bytes: Vec<u8> = arr.iter().map(|&c| c as u8).collect();
    let null_pos = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
    String::from_utf8_lossy(&bytes[..null_pos]).to_string()
}

/// Sanitize a camera model name into a safe ID component.
fn sanitize_id(model: &str) -> String {
    model
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' {
                c.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .collect()
}

fn encode_port_component(port: &str) -> String {
    let mut encoded = String::with_capacity(port.len() * 2);
    for byte in port.as_bytes() {
        encoded.push_str(&format!("{:02x}", byte));
    }
    encoded
}

pub fn decode_port_component(encoded: &str) -> Option<String> {
    if !encoded.len().is_multiple_of(2) {
        return None;
    }

    let mut bytes = Vec::with_capacity(encoded.len() / 2);
    let mut idx = 0;
    while idx < encoded.len() {
        let next = idx + 2;
        let chunk = &encoded[idx..next];
        let byte = u8::from_str_radix(chunk, 16).ok()?;
        bytes.push(byte);
        idx = next;
    }

    String::from_utf8(bytes).ok()
}

pub fn build_device_id(index: usize, model: &str, port: &str) -> String {
    format!(
        "native:gphoto2:{}:{}:{}",
        index,
        encode_port_component(port),
        sanitize_id(model)
    )
}

/// Parse a shutter speed string (e.g., "1/250", "2.5", "30") to seconds.
fn parse_shutter_speed_to_secs(speed: &str) -> Option<f64> {
    let speed = speed.trim();

    // Handle "Bulb" or "bulb"
    if speed.eq_ignore_ascii_case("bulb") {
        return None;
    }

    // Handle fractional speeds like "1/250"
    if let Some(pos) = speed.find('/') {
        let num: f64 = speed[..pos].parse().ok()?;
        let den: f64 = speed[pos + 1..].parse().ok()?;
        if den != 0.0 {
            return Some(num / den);
        }
        return None;
    }

    // Handle decimal speeds like "2.5" or "30"
    speed.parse().ok()
}
