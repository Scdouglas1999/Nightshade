//! `FliCamera` state and inherent helpers.

use super::*;

// =============================================================================
// FLI Camera Implementation
// =============================================================================

/// FLI camera native driver
pub struct FliCamera {
    pub(crate) device_path: String,
    pub(crate) device_id: String,
    pub(crate) name: String,
    pub(crate) handle: FliDev,
    pub(crate) connected: bool,
    pub(crate) capabilities: CameraCapabilities,
    pub(crate) sensor_info: SensorInfo,
    pub(crate) state: CameraState,
    // Visible area (where actual image is)
    pub(crate) visible_ul_x: i32,
    pub(crate) visible_ul_y: i32,
    pub(crate) visible_lr_x: i32,
    pub(crate) visible_lr_y: i32,
    // Current settings
    pub(crate) current_bin_x: i32,
    pub(crate) current_bin_y: i32,
    pub(crate) subframe: Option<SubFrame>,
    pub(crate) cooler_on: bool,
    pub(crate) target_temp: f64,
    // Exposure tracking
    pub(crate) exposure_duration: f64,
}

impl std::fmt::Debug for FliCamera {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FliCamera")
            .field("device_id", &self.device_id)
            .field("name", &self.name)
            .field("device_path", &self.device_path)
            .finish()
    }
}

impl FliCamera {
    /// Create a new FLI camera instance
    pub fn new(device_path: String) -> Self {
        let device_id = device_path.replace("/", "_").replace("\\", "_");
        Self {
            device_path: device_path.clone(),
            device_id: format!("fli_{}", device_id),
            name: "FLI Camera".to_string(),
            handle: FLI_INVALID_DEVICE,
            connected: false,
            capabilities: CameraCapabilities::default(),
            sensor_info: SensorInfo::default(),
            state: CameraState::Idle,
            visible_ul_x: 0,
            visible_ul_y: 0,
            visible_lr_x: 0,
            visible_lr_y: 0,
            current_bin_x: 1,
            current_bin_y: 1,
            subframe: None,
            cooler_on: false,
            target_temp: -10.0,
            exposure_duration: 0.0,
        }
    }
}

#[async_trait]
impl NativeDevice for FliCamera {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Fli
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
        let _lock = fli_mutex().lock().await;

        // Open device
        let path_cstr = CString::new(self.device_path.clone()).map_err(|_| {
            tracing::error!(
                "FLI camera device path contains null bytes: '{}'",
                self.device_path
            );
            NativeError::SdkError(format!(
                "Invalid device path '{}' contains null bytes",
                self.device_path
            ))
        })?;
        let domain = FLIDOMAIN_USB | FLIDEVICE_CAMERA;

        // SAFETY: fli_mutex held above; `self.handle` is a valid pointer into Self (caller holds &mut self); path_cstr is a NUL-terminated CString that outlives the call.
        let result = unsafe { (sdk.open)(&mut self.handle, path_cstr.as_ptr(), domain) };
        if result != 0 {
            tracing::error!(
                "FLI Open() failed for camera at '{}'. Error code: {}. Check USB connection and driver.",
                self.device_path, result
            );
            return Err(NativeError::SdkError(format!(
                "Failed to open FLI camera at '{}'. SDK error: {}. Ensure camera is connected and not in use.",
                self.device_path, result
            )));
        }

        // Get model name
        let mut model_buf = [0 as c_char; 128];
        // SAFETY: fli_mutex held; self.handle was just successfully opened above; model_buf is a 128-byte stack array with truthful length passed to SDK.
        if unsafe { (sdk.get_model)(self.handle, model_buf.as_mut_ptr(), model_buf.len()) } == 0 {
            // SAFETY: model_buf is 128 bytes; FLI SDK guarantees NUL-termination on success.
            self.name = unsafe { CStr::from_ptr(model_buf.as_ptr()) }
                .to_string_lossy()
                .to_string();
        }

        // Get pixel size
        let mut pixel_x: c_double = 0.0;
        let mut pixel_y: c_double = 0.0;
        // SAFETY: fli_mutex held; self.handle was successfully opened above; both out-pointers are valid stack pointers.
        let _ = unsafe { (sdk.get_pixel_size)(self.handle, &mut pixel_x, &mut pixel_y) };

        // Get visible area (the actual image area)
        let mut ul_x: c_long = 0;
        let mut ul_y: c_long = 0;
        let mut lr_x: c_long = 0;
        let mut lr_y: c_long = 0;
        // SAFETY: fli_mutex held; self.handle is open; all four out-pointers are valid stack pointers.
        let result = unsafe {
            (sdk.get_visible_area)(self.handle, &mut ul_x, &mut ul_y, &mut lr_x, &mut lr_y)
        };
        if let Err(error) = check_fli_error(result, "get visible area") {
            close_fli_handle(sdk, &mut self.handle);
            return Err(error);
        }

        // Why: FLIGetVisibleArea returns c_long (i32 on Windows MSVC LLP64, i64 on most
        // *nix LP64). FLI hardware tops out around 8192x8192 pixels so the values are
        // tiny. We use a helper to validate fit in i32 on platforms where c_long is wider
        // (no-op clamp on Windows where c_long == i32).
        // Why: lr >= ul is guaranteed by FLI's visible-area contract (lower-right is
        // strictly bottom-right of upper-left). Subtract first, then convert via try_into
        // to fail closed if the SDK ever returns an inverted rectangle.
        let visible_area: Result<(i32, i32, i32, i32, u32, u32), NativeError> = (|| {
            let visible_ul_x = fli_c_long_to_i32(ul_x, "ul_x")?;
            let visible_ul_y = fli_c_long_to_i32(ul_y, "ul_y")?;
            let visible_lr_x = fli_c_long_to_i32(lr_x, "lr_x")?;
            let visible_lr_y = fli_c_long_to_i32(lr_y, "lr_y")?;
            let raw_width = lr_x - ul_x;
            let raw_height = lr_y - ul_y;
            let width = u32::try_from(raw_width).map_err(|_| {
                NativeError::SdkError(format!(
                    "FLI visible-area width is negative or > u32::MAX: {}",
                    raw_width
                ))
            })?;
            let height = u32::try_from(raw_height).map_err(|_| {
                NativeError::SdkError(format!(
                    "FLI visible-area height is negative or > u32::MAX: {}",
                    raw_height
                ))
            })?;
            Ok((
                visible_ul_x,
                visible_ul_y,
                visible_lr_x,
                visible_lr_y,
                width,
                height,
            ))
        })();
        let (visible_ul_x, visible_ul_y, visible_lr_x, visible_lr_y, width, height) =
            match visible_area {
                Ok(area) => area,
                Err(error) => {
                    close_fli_handle(sdk, &mut self.handle);
                    return Err(error);
                }
            };
        self.visible_ul_x = visible_ul_x;
        self.visible_ul_y = visible_ul_y;
        self.visible_lr_x = visible_lr_x;
        self.visible_lr_y = visible_lr_y;

        // Set sensor info
        self.sensor_info = SensorInfo {
            width,
            height,
            pixel_size_x: pixel_x,
            pixel_size_y: pixel_y,
            max_adu: 65535,
            bit_depth: 16,
            color: false, // FLI cameras are typically monochrome
            bayer_pattern: None,
        };

        // Set capabilities
        self.capabilities = CameraCapabilities {
            can_cool: true,      // FLI cameras typically have cooling
            can_set_gain: false, // FLI doesn't expose gain control
            can_set_offset: false,
            can_set_binning: true,
            can_subframe: true,
            has_shutter: true,
            has_guider_port: false,
            max_bin_x: 16, // FLI typically supports up to 16x binning
            max_bin_y: 16,
            supports_readout_modes: false,
        };

        // Set 16-bit mode
        // SAFETY: fli_mutex held; self.handle is open; FLI_MODE_16BIT is a pass-by-value constant.
        let _ = unsafe { (sdk.set_bit_depth)(self.handle, FLI_MODE_16BIT) };

        // Set full frame
        // SAFETY: fli_mutex held; self.handle is open; ul_x/ul_y/lr_x/lr_y came from the SDK-reported visible area above so they are valid sensor coordinates.
        let result = unsafe { (sdk.set_image_area)(self.handle, ul_x, ul_y, lr_x, lr_y) };
        if let Err(error) = check_fli_error(result, "set image area") {
            close_fli_handle(sdk, &mut self.handle);
            return Err(error);
        }

        self.connected = true;
        self.state = CameraState::Idle;

        tracing::info!(
            "Connected to FLI camera: {} ({}x{})",
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
        let _lock = fli_mutex().lock().await;

        // Cancel any exposure
        // SAFETY: fli_mutex held; self.handle is valid because self.connected was true (only set after successful connect()).
        let _ = unsafe { (sdk.cancel_exposure)(self.handle) };

        // Close device
        // SAFETY: fli_mutex held; self.handle was successfully opened during connect(). FLIClose pairs with FLIOpen.
        let result = unsafe { (sdk.close)(self.handle) };
        check_fli_error(result, "close camera")?;

        self.handle = FLI_INVALID_DEVICE;
        self.connected = false;
        self.state = CameraState::Idle;

        tracing::info!("Disconnected from FLI camera: {}", self.name);

        Ok(())
    }
}
