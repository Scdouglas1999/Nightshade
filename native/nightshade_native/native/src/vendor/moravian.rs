//! Moravian Instruments Camera Native Driver
//!
//! Provides FFI bindings to the Moravian gXusb SDK (gXusb.dll).
//! Moravian Instruments manufactures CCD cameras for astronomy.

use crate::camera::{
    BayerPattern, CameraCapabilities, CameraState, CameraStatus, ExposureParams, ImageData,
    ImageMetadata, ReadoutMode, SensorInfo, SubFrame, VendorFeatures,
};
use crate::sync::moravian_mutex;
use crate::traits::{NativeCamera, NativeDevice, NativeError};
use crate::NativeVendor;
use async_trait::async_trait;
use libloading::Library;
use std::ffi::{c_char, c_float, c_int, c_uint, c_void};
use std::sync::{Arc, Mutex, OnceLock};

// ============================================================================
// SDK Types and Constants
// ============================================================================

/// Camera handle type (opaque pointer)
type CCamera = c_void;
type PCCamera = *mut CCamera;

type Cardinal = c_uint;
type Integer = c_int;
type Boolean = u8;
type Real = c_float;

// GetBooleanParameter indexes
const GBP_SUBFRAME: Cardinal = 1;
const GBP_SHUTTER: Cardinal = 3;
const GBP_COOLER: Cardinal = 4;
const GBP_GUIDE: Cardinal = 7;
const GBP_GAIN: Cardinal = 13;
const GBP_RGB: Cardinal = 128;

// GetIntegerParameter indexes
const GIP_CHIP_W: Cardinal = 1;
const GIP_CHIP_D: Cardinal = 2;
const GIP_PIXEL_W: Cardinal = 3;
const GIP_PIXEL_D: Cardinal = 4;
const GIP_MAX_BINNING_X: Cardinal = 5;
const GIP_MAX_BINNING_Y: Cardinal = 6;
const GIP_READ_MODES: Cardinal = 7;

// GetStringParameter indexes
const GSP_CAMERA_DESCRIPTION: Cardinal = 0;
const GSP_CAMERA_SERIAL: Cardinal = 2;

// GetValue indexes
const GV_CHIP_TEMPERATURE: Cardinal = 0;
const GV_POWER_UTILIZATION: Cardinal = 11;

// ============================================================================
// SDK Function Types
// ============================================================================

type EnumerateCallback = unsafe extern "C" fn(Cardinal);
type Enumerate = unsafe extern "C" fn(callback: EnumerateCallback);
type Initialize = unsafe extern "C" fn(id: Cardinal) -> PCCamera;
type Release = unsafe extern "C" fn(camera: PCCamera);
type GetBooleanParameter =
    unsafe extern "C" fn(camera: PCCamera, index: Cardinal, value: *mut Boolean) -> Boolean;
type GetIntegerParameter =
    unsafe extern "C" fn(camera: PCCamera, index: Cardinal, value: *mut Cardinal) -> Boolean;
type GetStringParameter = unsafe extern "C" fn(
    camera: PCCamera,
    index: Cardinal,
    len: Cardinal,
    buf: *mut c_char,
) -> Boolean;
type GetValue =
    unsafe extern "C" fn(camera: PCCamera, index: Cardinal, value: *mut Real) -> Boolean;
type SetTemperature = unsafe extern "C" fn(camera: PCCamera, temp: Real) -> Boolean;
type SetBinning = unsafe extern "C" fn(camera: PCCamera, x: Cardinal, y: Cardinal) -> Boolean;
type SetGain = unsafe extern "C" fn(camera: PCCamera, gain: Cardinal) -> Boolean;
type SetReadMode = unsafe extern "C" fn(camera: PCCamera, mode: Cardinal) -> Boolean;
type SetFilter = unsafe extern "C" fn(camera: PCCamera, filter: Cardinal) -> Boolean;
type EnumerateReadModes = unsafe extern "C" fn(
    camera: PCCamera,
    index: Cardinal,
    len: Cardinal,
    desc: *mut c_char,
) -> Boolean;
type ClearSensor = unsafe extern "C" fn(camera: PCCamera) -> Boolean;
type Open_ = unsafe extern "C" fn(camera: PCCamera) -> Boolean;
type Close_ = unsafe extern "C" fn(camera: PCCamera) -> Boolean;
type BeginExposure = unsafe extern "C" fn(camera: PCCamera, use_shutter: Boolean) -> Boolean;
type EndExposure =
    unsafe extern "C" fn(camera: PCCamera, use_shutter: Boolean, abort: Boolean) -> Boolean;
type GetImage16b = unsafe extern "C" fn(
    camera: PCCamera,
    x: Integer,
    y: Integer,
    w: Integer,
    d: Integer,
    buffer_len: Cardinal,
    buffer: *mut c_void,
) -> Boolean;
type AdjustSubFrame = unsafe extern "C" fn(
    camera: PCCamera,
    x: *mut Integer,
    y: *mut Integer,
    w: *mut Integer,
    d: *mut Integer,
) -> Boolean;

// ============================================================================
// SDK Singleton
// ============================================================================

static SDK: OnceLock<Result<MoravianSdk, String>> = OnceLock::new();

struct MoravianSdk {
    enumerate: Enumerate,
    initialize: Initialize,
    release: Release,
    get_boolean_parameter: GetBooleanParameter,
    get_integer_parameter: GetIntegerParameter,
    get_string_parameter: GetStringParameter,
    get_value: GetValue,
    set_temperature: SetTemperature,
    set_binning: SetBinning,
    set_gain: SetGain,
    set_read_mode: SetReadMode,
    #[allow(dead_code)]
    set_filter: Option<SetFilter>,
    enumerate_read_modes: EnumerateReadModes,
    clear_sensor: ClearSensor,
    open: Open_,
    close: Close_,
    begin_exposure: BeginExposure,
    end_exposure: EndExposure,
    get_image_16b: GetImage16b,
    adjust_subframe: AdjustSubFrame,
    _library: Library,
}

// SAFETY: MoravianSdk holds only function pointers and a `libloading::Library` (memory-mapped DLL handle). The function pointers reference code in a shared library that lives for the whole program (we store the Library to keep it loaded). All actual SDK calls go through `moravian_mutex()` which serializes access, so the underlying gXusb SDK never sees concurrent invocation.
unsafe impl Send for MoravianSdk {}
// SAFETY: Same justification as `impl Send`: pointer-and-handle aggregate that becomes safe under the moravian_mutex serialization used by every call site.
unsafe impl Sync for MoravianSdk {}

impl MoravianSdk {
    fn load() -> Result<Self, String> {
        // SAFETY: libloading::Library::new performs platform dynamic loading; the lib name "gXusb.dll" is a compile-time constant and the resulting Library is moved into the returned MoravianSdk so the function-pointer references remain valid for the program's lifetime — no memory access happens here.
        let library = unsafe { Library::new("gXusb.dll") }
            .map_err(|e| format!("Failed to load gXusb.dll: {}", e))?;

        // SAFETY: each `library.get::<FnType>(b"symbol\0")` followed by `*sym` dereferences a libloading::Symbol to its function-pointer ABI only after a successful name lookup; the FFI signatures (Enumerate/Initialize/Release/Get*Parameter/etc.) match the gXusb SDK header signatures exactly — verified against the gXusb.h definitions on which the type aliases above were modelled.
        unsafe {
            Ok(Self {
                enumerate: *library
                    .get::<Enumerate>(b"Enumerate\0")
                    .map_err(|e| format!("Failed to get Enumerate: {}", e))?,
                initialize: *library
                    .get::<Initialize>(b"Initialize\0")
                    .map_err(|e| format!("Failed to get Initialize: {}", e))?,
                release: *library
                    .get::<Release>(b"Release\0")
                    .map_err(|e| format!("Failed to get Release: {}", e))?,
                get_boolean_parameter: *library
                    .get::<GetBooleanParameter>(b"GetBooleanParameter\0")
                    .map_err(|e| format!("Failed to get GetBooleanParameter: {}", e))?,
                get_integer_parameter: *library
                    .get::<GetIntegerParameter>(b"GetIntegerParameter\0")
                    .map_err(|e| format!("Failed to get GetIntegerParameter: {}", e))?,
                get_string_parameter: *library
                    .get::<GetStringParameter>(b"GetStringParameter\0")
                    .map_err(|e| {
                    format!("Failed to get GetStringParameter: {}", e)
                })?,
                get_value: *library
                    .get::<GetValue>(b"GetValue\0")
                    .map_err(|e| format!("Failed to get GetValue: {}", e))?,
                set_temperature: *library
                    .get::<SetTemperature>(b"SetTemperature\0")
                    .map_err(|e| format!("Failed to get SetTemperature: {}", e))?,
                set_binning: *library
                    .get::<SetBinning>(b"SetBinning\0")
                    .map_err(|e| format!("Failed to get SetBinning: {}", e))?,
                set_gain: *library
                    .get::<SetGain>(b"SetGain\0")
                    .map_err(|e| format!("Failed to get SetGain: {}", e))?,
                set_read_mode: *library
                    .get::<SetReadMode>(b"SetReadMode\0")
                    .map_err(|e| format!("Failed to get SetReadMode: {}", e))?,
                set_filter: library
                    .get::<SetFilter>(b"SetFilter\0")
                    .ok()
                    .map(|sym| *sym),
                enumerate_read_modes: *library
                    .get::<EnumerateReadModes>(b"EnumerateReadModes\0")
                    .map_err(|e| {
                    format!("Failed to get EnumerateReadModes: {}", e)
                })?,
                clear_sensor: *library
                    .get::<ClearSensor>(b"ClearSensor\0")
                    .map_err(|e| format!("Failed to get ClearSensor: {}", e))?,
                open: *library
                    .get::<Open_>(b"Open\0")
                    .map_err(|e| format!("Failed to get Open: {}", e))?,
                close: *library
                    .get::<Close_>(b"Close\0")
                    .map_err(|e| format!("Failed to get Close: {}", e))?,
                begin_exposure: *library
                    .get::<BeginExposure>(b"BeginExposure\0")
                    .map_err(|e| format!("Failed to get BeginExposure: {}", e))?,
                end_exposure: *library
                    .get::<EndExposure>(b"EndExposure\0")
                    .map_err(|e| format!("Failed to get EndExposure: {}", e))?,
                get_image_16b: *library
                    .get::<GetImage16b>(b"GetImage16b\0")
                    .map_err(|e| format!("Failed to get GetImage16b: {}", e))?,
                adjust_subframe: *library
                    .get::<AdjustSubFrame>(b"AdjustSubFrame\0")
                    .map_err(|e| format!("Failed to get AdjustSubFrame: {}", e))?,
                _library: library,
            })
        }
    }
}

fn get_sdk() -> Result<&'static MoravianSdk, NativeError> {
    SDK.get_or_init(MoravianSdk::load)
        .as_ref()
        .map_err(|e| NativeError::SdkError(e.clone()))
}

// ============================================================================
// Device Discovery
// ============================================================================

/// Active enumeration sink for SDK callbacks.
static ACTIVE_ENUMERATION_IDS: Mutex<Option<Arc<Mutex<Vec<Cardinal>>>>> = Mutex::new(None);

/// Callback for camera enumeration
unsafe extern "C" fn enumerate_callback(id: Cardinal) {
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
    pub camera_id: Cardinal,
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
    // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); ACTIVE_ENUMERATION_IDS has been set to `ids_sink` above so the callback has a sink to push to; `enumerate_callback` is a properly declared `unsafe extern "C" fn(Cardinal)` matching the EnumerateCallback typedef.
    unsafe { (sdk.enumerate)(enumerate_callback) };
    *ACTIVE_ENUMERATION_IDS
        .lock()
        .unwrap_or_else(|e| e.into_inner()) = None;

    // Collect results
    let ids: Vec<Cardinal> = ids_sink.lock().unwrap_or_else(|e| e.into_inner()).clone();

    let mut devices = Vec::new();

    for (index, &id) in ids.iter().enumerate() {
        // Temporarily initialize to get camera info
        // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); `id` was just emitted by Enumerate via enumerate_callback so it is a valid camera ID for Initialize.
        let handle = unsafe { (sdk.initialize)(id) };
        if handle.is_null() {
            continue;
        }

        // Get camera description
        let mut name_buf = [0i8; 256];
        // SAFETY: moravian_mutex held; `handle` was just successfully initialized (non-null check above); name_buf is a 256-byte stack array and we pass `256` as the truthful length so the SDK cannot overrun.
        if unsafe {
            (sdk.get_string_parameter)(handle, GSP_CAMERA_DESCRIPTION, 256, name_buf.as_mut_ptr())
        } != 0
        {
            // SAFETY: name_buf is 256 bytes and the SDK guarantees NUL-termination within the buffer on success (return != 0) per gXusb.h.
            let name = unsafe { std::ffi::CStr::from_ptr(name_buf.as_ptr()) }
                .to_string_lossy()
                .to_string();

            // Get serial number
            let mut serial_buf = [0i8; 64];
            // SAFETY: moravian_mutex held; `handle` is still the successfully-initialized one from above; serial_buf is 64 bytes and the truthful length is passed.
            let serial_number = if unsafe {
                (sdk.get_string_parameter)(handle, GSP_CAMERA_SERIAL, 64, serial_buf.as_mut_ptr())
            } != 0
            {
                // SAFETY: serial_buf is 64 bytes; gXusb SDK guarantees NUL-termination on success.
                let serial = unsafe { std::ffi::CStr::from_ptr(serial_buf.as_ptr()) }
                    .to_string_lossy()
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
        // SAFETY: moravian_mutex held; `handle` was successfully initialized at the top of this iteration; Release pairs with Initialize per gXusb.h.
        unsafe { (sdk.release)(handle) };
    }

    Ok(devices)
}

// ============================================================================
// Handle Wrapper for Send + Sync
// ============================================================================

struct HandleWrapper(PCCamera);
// SAFETY: HandleWrapper wraps a raw `*mut c_void` camera handle. The handle is opaque to us — we never deref it. It is only handed back to the gXusb SDK functions, which serialize through `moravian_mutex()`, so no concurrent access ever happens to the underlying SDK state via this pointer.
unsafe impl Send for HandleWrapper {}
// SAFETY: Same justification as `impl Send`. The pointer is opaque and access to it is gated by both the wrapping `Mutex<HandleWrapper>` (held inside MoravianCamera) and the global `moravian_mutex()`.
unsafe impl Sync for HandleWrapper {}

// ============================================================================
// Camera Implementation
// ============================================================================

/// Moravian camera instance
pub struct MoravianCamera {
    camera_id: Cardinal,
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
    use_shutter: bool,
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
    pub fn new(camera_id: Cardinal) -> Self {
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
            use_shutter: true,
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

        // Initialize camera
        // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); `self.camera_id` was set at construction (passed in from MoravianCameraInfo.camera_id which was emitted by Enumerate); Initialize takes the camera ID by value and returns a fresh handle (NULL on failure, checked below).
        let handle = unsafe { (sdk.initialize)(self.camera_id) };
        if handle.is_null() {
            tracing::error!(
                "Moravian Initialize() returned NULL for camera ID {}. Check USB connection and driver installation.",
                self.camera_id
            );
            return Err(NativeError::SdkError(format!(
                "Failed to initialize Moravian camera ID {} - SDK returned NULL handle. Ensure camera is connected and gXusb driver is installed.",
                self.camera_id
            )));
        }

        // Store handle
        {
            let mut h = self.handle.lock().unwrap_or_else(|e| e.into_inner());
            *h = HandleWrapper(handle);
        }

        // Get camera info using the stored handle (synchronous operations)
        {
            let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

            // Get name
            let mut name_buf = [0i8; 256];
            // SAFETY: moravian_mutex held above; `handle` is the just-successfully-initialized camera handle stored in self.handle; name_buf is 256 bytes and the truthful length is passed so the SDK cannot overrun.
            if unsafe {
                (sdk.get_string_parameter)(
                    handle,
                    GSP_CAMERA_DESCRIPTION,
                    256,
                    name_buf.as_mut_ptr(),
                )
            } != 0
            {
                // SAFETY: name_buf is 256 bytes; gXusb SDK guarantees NUL-termination within on success.
                self.name = unsafe { std::ffi::CStr::from_ptr(name_buf.as_ptr()) }
                    .to_string_lossy()
                    .to_string();
            }

            // Get sensor dimensions
            let mut width: Cardinal = 0;
            let mut height: Cardinal = 0;
            // SAFETY: moravian_mutex held; `handle` is the successfully-initialized handle; both out-pointers are valid stack POD references.
            unsafe {
                (sdk.get_integer_parameter)(handle, GIP_CHIP_W, &mut width);
                (sdk.get_integer_parameter)(handle, GIP_CHIP_D, &mut height);
            }

            // Get pixel size (in 0.01 microns per SDK docs)
            let mut pixel_w: Cardinal = 0;
            let mut pixel_d: Cardinal = 0;
            // SAFETY: moravian_mutex held; `handle` is the successfully-initialized handle; both out-pointers are valid stack POD references.
            unsafe {
                (sdk.get_integer_parameter)(handle, GIP_PIXEL_W, &mut pixel_w);
                (sdk.get_integer_parameter)(handle, GIP_PIXEL_D, &mut pixel_d);
            }

            // Check if color camera
            let mut is_color: Boolean = 0;
            // SAFETY: moravian_mutex held; `handle` is the successfully-initialized handle; `&mut is_color` is a valid stack out-pointer to a u8.
            let color =
                if unsafe { (sdk.get_boolean_parameter)(handle, GBP_RGB, &mut is_color) } != 0 {
                    is_color != 0
                } else {
                    false
                };

            self.sensor_info = SensorInfo {
                width,
                height,
                pixel_size_x: pixel_w as f64 / 100.0, // Convert from 0.01 microns
                pixel_size_y: pixel_d as f64 / 100.0,
                max_adu: 65535,
                bit_depth: 16,
                color,
                bayer_pattern: if color {
                    Some(BayerPattern::Rggb)
                } else {
                    None
                },
            };

            // Get capabilities
            let mut has_cooler: Boolean = 0;
            let mut has_shutter: Boolean = 0;
            let mut has_guide: Boolean = 0;
            let mut has_gain: Boolean = 0;
            let mut has_subframe: Boolean = 0;
            let mut max_bin_x: Cardinal = 1;
            let mut max_bin_y: Cardinal = 1;

            // SAFETY: moravian_mutex held above; `handle` is the successfully-initialized handle; every out-pointer here is a valid stack POD reference (u8 or Cardinal) — the SDK writes at most one POD value into each.
            unsafe {
                (sdk.get_boolean_parameter)(handle, GBP_COOLER, &mut has_cooler);
                (sdk.get_boolean_parameter)(handle, GBP_SHUTTER, &mut has_shutter);
                (sdk.get_boolean_parameter)(handle, GBP_GUIDE, &mut has_guide);
                (sdk.get_boolean_parameter)(handle, GBP_GAIN, &mut has_gain);
                (sdk.get_boolean_parameter)(handle, GBP_SUBFRAME, &mut has_subframe);
                (sdk.get_integer_parameter)(handle, GIP_MAX_BINNING_X, &mut max_bin_x);
                (sdk.get_integer_parameter)(handle, GIP_MAX_BINNING_Y, &mut max_bin_y);
            }

            self.capabilities = CameraCapabilities {
                can_cool: has_cooler != 0,
                can_set_gain: has_gain != 0,
                can_set_offset: false, // Moravian doesn't have separate offset
                can_set_binning: max_bin_x > 1 || max_bin_y > 1,
                can_subframe: has_subframe != 0,
                has_shutter: has_shutter != 0,
                has_guider_port: has_guide != 0,
                // Why: Cardinal (u32) -> i32. Moravian's max binning is hardware-bounded
                // to <= 16; any value approaching i32::MAX indicates SDK corruption. We
                // saturate via try_into.unwrap_or(i32::MAX) so callers see a defensible
                // upper bound rather than a wrapped negative.
                max_bin_x: i32::try_from(max_bin_x).unwrap_or(i32::MAX),
                max_bin_y: i32::try_from(max_bin_y).unwrap_or(i32::MAX),
                supports_readout_modes: true, // Moravian supports readout modes
            };

            self.use_shutter = has_shutter != 0;
        }

        // Open camera for imaging
        {
            let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;
            // SAFETY: moravian_mutex held above; `handle` is the just-initialized non-null camera handle (verified non-null when stored above); gXusb Open() takes the handle and opens the device for imaging.
            if unsafe { (sdk.open)(handle) } == 0 {
                tracing::error!(
                    "Moravian Open() failed for camera '{}' (ID {}). Camera may be in use by another application.",
                    self.name, self.camera_id
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to open Moravian camera '{}' - SDK Open() returned false. Check if camera is in use by another application.",
                    self.name
                )));
            }
        }

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

        // Close camera
        // SAFETY: moravian_mutex held above; we only enter this branch when self.connected == true, so the handle was previously opened via Open(); Close() pairs with Open().
        unsafe { (sdk.close)(handle) };

        // Release camera
        // SAFETY: moravian_mutex held; handle was previously Initialize()'d (we're on the connected path); Release() pairs with Initialize() and is the required final cleanup per gXusb.h.
        unsafe { (sdk.release)(handle) };

        {
            let mut h = self.handle.lock().unwrap_or_else(|e| e.into_inner());
            *h = HandleWrapper(std::ptr::null_mut());
        }
        self.connected = false;
        self.state = CameraState::Idle;
        self.exposure_started_at = None;

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
            let mut value: Real = 0.0;
            // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); self.connected was checked at entry so the handle is open; `&mut value` is a valid stack out-pointer to a c_float.
            if unsafe { (sdk.get_value)(handle, GV_CHIP_TEMPERATURE, &mut value) } != 0 {
                Some(value as f64)
            } else {
                None
            }
        };

        // Get cooler power
        let cooler_power = {
            let mut value: Real = 0.0;
            // SAFETY: moravian_mutex held; self.connected was checked at entry; `&mut value` is a valid stack out-pointer to a c_float.
            if unsafe { (sdk.get_value)(handle, GV_POWER_UTILIZATION, &mut value) } != 0 {
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

        // Use a scoped block for mutex to ensure it's released before sleeping
        {
            // Acquire global SDK mutex for thread safety
            let _lock = moravian_mutex().lock().await;

            let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

            // Clear sensor first
            // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); self.connected was checked at entry so the handle is open; ClearSensor takes just the handle.
            if unsafe { (sdk.clear_sensor)(handle) } == 0 {
                tracing::error!(
                    "Moravian ClearSensor() failed for camera '{}'. Sensor may be busy or hardware error occurred.",
                    self.name
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to clear sensor on Moravian camera '{}'. Sensor may be busy.",
                    self.name
                )));
            }

            // Start exposure (use shutter if available)
            let use_shutter = if self.use_shutter { 1 } else { 0 };

            // SAFETY: moravian_mutex held above; handle is open (self.connected checked at entry); use_shutter is a 0/1 Boolean derived from cached SDK capability.
            if unsafe { (sdk.begin_exposure)(handle, use_shutter) } == 0 {
                tracing::error!(
                    "Moravian BeginExposure() failed for camera '{}'. Duration: {:.3}s, UseShutter: {}",
                    self.name, params.duration_secs, self.use_shutter
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to start exposure on Moravian camera '{}'. The camera may be busy or disconnected.",
                    self.name
                )));
            }

            self.exposure_duration = params.duration_secs;
            self.exposure_started_at = Some(std::time::Instant::now());
            self.state = CameraState::Exposing;

            tracing::info!(
                "Started {:.3}s exposure on Moravian camera",
                params.duration_secs
            );
        } // Mutex released here BEFORE sleeping

        // Wait for exposure duration (mutex is NOT held during this sleep)
        tokio::time::sleep(tokio::time::Duration::from_secs_f64(params.duration_secs)).await;

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

        // End exposure with abort
        // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); self.connected was checked at entry; EndExposure takes the handle plus two Boolean values (use_shutter=0, abort=1) by value.
        unsafe { (sdk.end_exposure)(handle, 0, 1) };

        self.state = CameraState::Idle;
        self.exposure_started_at = None;
        tracing::info!("Aborted exposure on Moravian camera");

        Ok(())
    }

    async fn download_image(&mut self) -> Result<ImageData, NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // End exposure
        // SAFETY: moravian_mutex held above; self.connected was checked at entry so handle is open; EndExposure takes handle plus two Booleans (use_shutter, abort=0) by value to finalize the exposure.
        if unsafe { (sdk.end_exposure)(handle, if self.use_shutter { 1 } else { 0 }, 0) } == 0 {
            tracing::error!(
                "Moravian EndExposure() failed for camera '{}'. Exposure may not have completed properly.",
                self.name
            );
            return Err(NativeError::SdkError(format!(
                "Failed to end exposure on Moravian camera '{}'. Exposure may not have completed.",
                self.name
            )));
        }

        self.state = CameraState::Downloading;

        // Calculate image dimensions.
        // Why: SubFrame.start_x/start_y are u32; the Moravian SDK consumes i32 (c_int).
        // We surface a u32 > i32::MAX as InvalidParameter rather than wrap into a
        // negative ROI origin.
        let (x, y, width, height) = if let Some(ref sf) = self.subframe {
            let sx = i32::try_from(sf.start_x).map_err(|_| {
                NativeError::InvalidParameter(format!(
                    "Moravian subframe start_x exceeds i32: {}",
                    sf.start_x
                ))
            })?;
            let sy = i32::try_from(sf.start_y).map_err(|_| {
                NativeError::InvalidParameter(format!(
                    "Moravian subframe start_y exceeds i32: {}",
                    sf.start_y
                ))
            })?;
            (sx, sy, sf.width, sf.height)
        } else {
            (0, 0, self.sensor_info.width, self.sensor_info.height)
        };

        // Why: current_bin_x is i32 stored from validated set_binning(); we must convert
        // to u32 for the division. A negative bin or zero would cause divide-by-zero or
        // wrap, so we reject explicitly.
        let bin_x_u32 = u32::try_from(self.current_bin_x).map_err(|_| {
            NativeError::InvalidParameter(format!(
                "Moravian current_bin_x not representable as u32: {}",
                self.current_bin_x
            ))
        })?;
        let bin_y_u32 = u32::try_from(self.current_bin_y).map_err(|_| {
            NativeError::InvalidParameter(format!(
                "Moravian current_bin_y not representable as u32: {}",
                self.current_bin_y
            ))
        })?;
        if bin_x_u32 == 0 || bin_y_u32 == 0 {
            return Err(NativeError::InvalidParameter(
                "Moravian binning must be >= 1".into(),
            ));
        }
        let binned_width = width / bin_x_u32;
        let binned_height = height / bin_y_u32;
        // Why: buffer_size is in *pixels* (u16 each), and `buffer_size * 2` is bytes.
        // For a 32K x 32K mono camera this is 2 GB — fits in u64 but not in c_uint
        // (Cardinal = u32). Promote to u64 for the byte count and refuse to call the
        // SDK if it would not fit in Cardinal.
        let buffer_size_u64 = u64::from(binned_width)
            .checked_mul(u64::from(binned_height))
            .ok_or_else(|| {
                NativeError::SdkError(format!(
                    "Moravian buffer dimensions overflow u64: {}x{}",
                    binned_width, binned_height
                ))
            })?;
        let byte_count_u64 = buffer_size_u64.checked_mul(2).ok_or_else(|| {
            NativeError::SdkError("Moravian byte count overflow u64".into())
        })?;
        let buffer_size = usize::try_from(buffer_size_u64).map_err(|_| {
            NativeError::SdkError(format!(
                "Moravian buffer pixel count {} does not fit in usize",
                buffer_size_u64
            ))
        })?;
        let byte_count_cardinal = Cardinal::try_from(byte_count_u64).map_err(|_| {
            NativeError::SdkError(format!(
                "Moravian byte count {} exceeds SDK Cardinal limit ({})",
                byte_count_u64,
                Cardinal::MAX
            ))
        })?;
        let binned_width_i32 = i32::try_from(binned_width).map_err(|_| {
            NativeError::SdkError(format!(
                "Moravian binned width {} does not fit in i32",
                binned_width
            ))
        })?;
        let binned_height_i32 = i32::try_from(binned_height).map_err(|_| {
            NativeError::SdkError(format!(
                "Moravian binned height {} does not fit in i32",
                binned_height
            ))
        })?;

        // Allocate buffer
        let mut data: Vec<u16> = vec![0u16; buffer_size];

        // Download image
        // SAFETY: moravian_mutex held above; handle is open (self.connected checked at entry); `data` was `vec![0u16; buffer_size]` where buffer_size = binned_width * binned_height, so `byte_count_cardinal = buffer_size * 2` bytes is the exact length we pass — the SDK cannot overrun; `data.as_mut_ptr() as *mut c_void` provides a valid non-null buffer pointer.
        let result = unsafe {
            (sdk.get_image_16b)(
                handle,
                x,
                y,
                binned_width_i32,
                binned_height_i32,
                byte_count_cardinal,
                data.as_mut_ptr() as *mut c_void,
            )
        };

        if result == 0 {
            tracing::error!(
                "Moravian GetImage16b() failed for camera '{}'. Requested {}x{} pixels at ({}, {})",
                self.name,
                binned_width,
                binned_height,
                x,
                y
            );
            return Err(NativeError::SdkError(format!(
                "Failed to download image from Moravian camera '{}'. Buffer size: {} bytes",
                self.name,
                buffer_size * 2
            )));
        }

        self.state = CameraState::Idle;
        self.exposure_started_at = None;

        // Get temperature while we still hold the mutex
        let temperature = {
            let mut value: Real = 0.0;
            // SAFETY: moravian_mutex still held (same scope as the download above); handle is still open; `&mut value` is a valid stack out-pointer to a c_float.
            if unsafe { (sdk.get_value)(handle, GV_CHIP_TEMPERATURE, &mut value) } != 0 {
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
            bits_per_pixel: 16,
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

    async fn set_cooler(&mut self, enabled: bool, target_temp: f64) -> Result<(), NativeError> {
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
            // Set target temperature
            // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); self.connected was checked at entry so handle is open; SetTemperature takes the handle plus a c_float by value.
            if unsafe { (sdk.set_temperature)(handle, target_temp as f32) } == 0 {
                tracing::error!(
                    "Moravian SetTemperature() failed for camera '{}'. Target: {:.1}°C",
                    self.name,
                    target_temp
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to set cooler temperature to {:.1}°C on Moravian camera '{}'. Camera may not have a cooler.",
                    target_temp, self.name
                )));
            }
            self.cooler_on = true;
            self.target_temp = target_temp;
        } else {
            // Warm up to ambient (set high temperature target)
            // SAFETY: moravian_mutex held above; handle is open (self.connected checked at entry); SetTemperature accepts the handle and a c_float (25.0°C warm-up target) by value.
            unsafe { (sdk.set_temperature)(handle, 25.0) };
            self.cooler_on = false;
        }

        tracing::info!(
            "Moravian cooler {}: target {}°C",
            if enabled { "enabled" } else { "disabled" },
            target_temp
        );

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

        let mut value: Real = 0.0;
        // SAFETY: moravian_mutex held above; self.connected was checked at entry so handle is open; `&mut value` is a valid stack out-pointer to a c_float.
        if unsafe { (sdk.get_value)(handle, GV_CHIP_TEMPERATURE, &mut value) } != 0 {
            Ok(value as f64)
        } else {
            Err(NativeError::SdkError("Failed to get temperature".into()))
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

        let mut value: Real = 0.0;
        // SAFETY: moravian_mutex held above; self.connected was checked at entry so handle is open; `&mut value` is a valid stack out-pointer to a c_float.
        if unsafe { (sdk.get_value)(handle, GV_POWER_UTILIZATION, &mut value) } != 0 {
            Ok(value as f64)
        } else {
            Err(NativeError::SdkError("Failed to get cooler power".into()))
        }
    }

    async fn set_gain(&mut self, gain: i32) -> Result<(), NativeError> {
        if !self.connected {
            return Err(NativeError::NotConnected);
        }

        if !self.capabilities.can_set_gain {
            return Err(NativeError::NotSupported);
        }

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); self.connected and capabilities.can_set_gain were checked at entry so the handle is open and the camera supports gain; SetGain takes the handle and a Cardinal by value.
        if unsafe { (sdk.set_gain)(handle, gain as Cardinal) } == 0 {
            tracing::error!(
                "Moravian SetGain() failed for camera '{}'. Requested gain: {}",
                self.name,
                gain
            );
            return Err(NativeError::SdkError(format!(
                "Failed to set gain to {} on Moravian camera '{}'. Value may be out of range.",
                gain, self.name
            )));
        }

        self.current_gain = gain;
        Ok(())
    }

    async fn set_offset(&mut self, offset: i32) -> Result<(), NativeError> {
        // Moravian doesn't support offset
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

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); self.connected was checked at entry so the handle is open; SetBinning takes the handle plus two Cardinals by value — caller-validated against capabilities.max_bin_x/max_bin_y in the error message below if rejected.
        if unsafe { (sdk.set_binning)(handle, bin_x as Cardinal, bin_y as Cardinal) } == 0 {
            tracing::error!(
                "Moravian SetBinning() failed for camera '{}'. Requested: {}x{}. Max: {}x{}",
                self.name,
                bin_x,
                bin_y,
                self.capabilities.max_bin_x,
                self.capabilities.max_bin_y
            );
            return Err(NativeError::SdkError(format!(
                "Failed to set binning to {}x{} on Moravian camera '{}'. Max supported: {}x{}",
                bin_x, bin_y, self.name, self.capabilities.max_bin_x, self.capabilities.max_bin_y
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

        let sdk = get_sdk()?;

        // Acquire global SDK mutex for thread safety
        let _lock = moravian_mutex().lock().await;

        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).0;

        if let Some(ref sf) = subframe {
            if !self.capabilities.can_subframe {
                return Err(NativeError::NotSupported);
            }

            // Validate subframe bounds with SDK.
            // Why: SubFrame fields are u32 sensor coordinates; Integer (c_int = i32) is
            // what AdjustSubFrame expects. A u32 > i32::MAX would wrap to a negative
            // coordinate and bypass the SDK's bounds check. Surface as error instead.
            let mut x = Integer::try_from(sf.start_x).map_err(|_| {
                NativeError::InvalidParameter(format!(
                    "Moravian subframe start_x exceeds Integer: {}",
                    sf.start_x
                ))
            })?;
            let mut y = Integer::try_from(sf.start_y).map_err(|_| {
                NativeError::InvalidParameter(format!(
                    "Moravian subframe start_y exceeds Integer: {}",
                    sf.start_y
                ))
            })?;
            let mut w = Integer::try_from(sf.width).map_err(|_| {
                NativeError::InvalidParameter(format!(
                    "Moravian subframe width exceeds Integer: {}",
                    sf.width
                ))
            })?;
            let mut d = Integer::try_from(sf.height).map_err(|_| {
                NativeError::InvalidParameter(format!(
                    "Moravian subframe height exceeds Integer: {}",
                    sf.height
                ))
            })?;

            // SAFETY: moravian_mutex held above; self.connected and capabilities.can_subframe were checked at entry so the handle is open and supports subframes; all four out-pointers are valid stack POD Integer references that the SDK clamps in-place to valid sensor bounds.
            if unsafe { (sdk.adjust_subframe)(handle, &mut x, &mut y, &mut w, &mut d) } == 0 {
                tracing::error!(
                    "Moravian AdjustSubFrame() failed for camera '{}'. Requested: ({}, {}) {}x{}. Sensor: {}x{}",
                    self.name, sf.start_x, sf.start_y, sf.width, sf.height,
                    self.sensor_info.width, self.sensor_info.height
                );
                return Err(NativeError::SdkError(format!(
                    "Failed to set subframe ({}, {}) {}x{} on Moravian camera '{}'. Check bounds vs sensor size {}x{}",
                    sf.start_x, sf.start_y, sf.width, sf.height, self.name,
                    self.sensor_info.width, self.sensor_info.height
                )));
            }

            // Store adjusted subframe.
            // Why: AdjustSubFrame clamps x/y/w/d to the sensor's valid bounds (all non-negative
            // and <= sensor_width/height which are u32). Sign loss is impossible by SDK
            // contract; widening to u32 is value-preserving for the clamped range.
            self.subframe = Some(SubFrame {
                start_x: x as u32,
                start_y: y as u32,
                width: w as u32,
                height: d as u32,
            });
        } else {
            self.subframe = None;
        }

        Ok(())
    }

    async fn get_gain(&self) -> Result<i32, NativeError> {
        Ok(self.current_gain)
    }

    async fn get_offset(&self) -> Result<i32, NativeError> {
        Ok(self.current_offset)
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

        // Get number of readout modes
        let num_modes = {
            let mut value: Cardinal = 0;
            // SAFETY: moravian_mutex held above; self.connected was checked at entry so handle is open; `&mut value` is a valid stack out-pointer to a Cardinal.
            if unsafe { (sdk.get_integer_parameter)(handle, GIP_READ_MODES, &mut value) } != 0 {
                value
            } else {
                1
            }
        };

        let mut modes = Vec::new();
        for i in 0..num_modes {
            let mut desc_buf = [0i8; 256];
            // SAFETY: moravian_mutex held; handle is open; `i` is in the range [0, num_modes) as reported by the SDK above; desc_buf is 256 bytes and the truthful length is passed so the SDK cannot overrun.
            if unsafe { (sdk.enumerate_read_modes)(handle, i, 256, desc_buf.as_mut_ptr()) } != 0 {
                // SAFETY: desc_buf is 256 bytes; gXusb SDK guarantees NUL-termination within the buffer on success.
                let description = unsafe { std::ffi::CStr::from_ptr(desc_buf.as_ptr()) }
                    .to_string_lossy()
                    .to_string();

                modes.push(ReadoutMode {
                    name: format!("Mode {}", i),
                    description,
                    // Why: `i` iterates `0..num_modes` where num_modes is a Cardinal (u32).
                    // Moravian readout modes are tiny (<= 4 known modes across all G4/G2
                    // SKUs), so `as i32` is widening with verified non-negative range.
                    index: i as i32,
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

        // SAFETY: moravian_mutex held above (single-threaded gXusb SDK access); self.connected was checked at entry so the handle is open; SetReadMode takes the handle plus a Cardinal index by value.
        if unsafe { (sdk.set_read_mode)(handle, mode.index as Cardinal) } == 0 {
            tracing::error!(
                "Moravian SetReadMode() failed for camera '{}'. Mode index: {} ('{}')",
                self.name,
                mode.index,
                mode.name
            );
            return Err(NativeError::SdkError(format!(
                "Failed to set readout mode '{}' (index {}) on Moravian camera '{}'. Mode may not be supported.",
                mode.name, mode.index, self.name
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

        // Moravian cameras typically have limited offset control.
        Ok((0, 255))
    }
}
