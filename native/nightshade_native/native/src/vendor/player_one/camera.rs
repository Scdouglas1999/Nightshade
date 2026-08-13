//! `PlayerOneCamera` state and inherent helpers.

use super::*;

// =============================================================================
// PLAYER ONE CAMERA IMPLEMENTATION
// =============================================================================

/// Player One Camera implementation
#[derive(Debug)]
pub struct PlayerOneCamera {
    pub(crate) camera_id: i32,
    pub(crate) camera_info: Option<POACameraProperties>,
    pub(crate) device_id: String,
    pub(crate) connected: bool,
    pub(crate) current_bin: i32,
    pub(crate) current_width: i32,
    pub(crate) current_height: i32,
    pub(crate) image_format: POAImgFormat,
    // Exposure metadata tracking
    pub(crate) exposure_time: f64,
    pub(crate) current_subframe: Option<SubFrame>,
    // Driver-level cooler state. Used by `get_status` (`&self`) when the SDK
    // read-back is unavailable; written by `set_cooler` after the SDK accepts
    // the change. `Mutex` provides interior mutability across the immutable
    // `get_status` call path.
    pub(crate) cooler_state: Mutex<CoolerState>,
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
    pub(crate) fn load_camera_info(&mut self) -> Result<(), NativeError> {
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
    pub(crate) fn camera_name(&self) -> String {
        if let Some(info) = &self.camera_info {
            safe_cstr_to_string(info.camera_model_name.as_ptr(), 256)
        } else {
            format!("Player One Camera {}", self.camera_id)
        }
    }

    /// Get a control value as integer (mutex protected)
    pub(crate) async fn get_control_int_async(
        &self,
        control: POAConfig,
    ) -> Result<c_long, NativeError> {
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
    pub(crate) fn get_control_int(&self, control: POAConfig) -> Result<c_long, NativeError> {
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
    pub(crate) async fn get_control_float_async(
        &self,
        control: POAConfig,
    ) -> Result<f64, NativeError> {
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
    pub(crate) fn get_control_float(&self, control: POAConfig) -> Result<f64, NativeError> {
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
    pub(crate) fn get_control_bool(&self, control: POAConfig) -> Result<bool, NativeError> {
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
    pub(crate) async fn set_control_int_async(
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
    pub(crate) fn set_control_int(
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
    pub(crate) async fn set_control_bool_async(
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
    pub(crate) fn set_control_bool(
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
                // Why: current_width/height are i32 dimensions set from validated SDK ROI;
                // they are always non-negative for a connected camera. Use try_into with a
                // 0 fallback for the diagnostic message (we already failed; don't compound).
                Err(NativeError::download_timeout(
                    timeout_duration,
                    u32::try_from(self.current_width).unwrap_or(0),
                    u32::try_from(self.current_height).unwrap_or(0),
                ))
            }
        }
    }
}
