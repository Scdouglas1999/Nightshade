//! ZWO camera discovery and SDK status.

use super::*;

// =============================================================================
// ZWO CAMERA DISCOVERY
// =============================================================================

/// ZWO camera discovery info
pub struct ZwoDiscoveryInfo {
    /// Stable SDK CameraID used by ASIOpenCamera and all subsequent operations.
    pub camera_id: i32,
    pub name: String,
    /// Discovery index (0-based) for disambiguation when multiple same-model cameras
    /// ZWO SDK doesn't expose serial numbers, so we use index instead
    pub discovery_index: usize,
    /// ZWO ASI SDK version reported by the loaded native library
    pub sdk_version: Option<String>,
}

/// Check if ZWO SDK is available
pub fn is_sdk_available() -> bool {
    AsiSdk::get().is_some()
}

/// Check if ZWO SDK is loaded and return status message
pub fn get_sdk_status() -> (bool, String) {
    match AsiSdk::get() {
        Some(sdk) => (
            true,
            asi_sdk_version_from_sdk(sdk)
                .map(|version| format!("{version} loaded successfully"))
                .unwrap_or_else(|| "ZWO ASI SDK loaded successfully".to_string()),
        ),
        None => (false, "ZWO ASI SDK (ASICamera2.dll) not found. Install the ASI SDK or use ASCOM drivers instead.".to_string()),
    }
}

pub(crate) fn asi_sdk_version_from_sdk(sdk: &AsiSdk) -> Option<String> {
    // SAFETY: ASIGetSDKVersion takes no arguments and returns a static C string.
    sdk_static_cstr(unsafe { (sdk.get_sdk_version)() })
        .map(|version| format!("ZWO ASI SDK v{version}"))
}

/// Discover ZWO cameras
pub async fn discover_devices() -> Result<Vec<ZwoDiscoveryInfo>, NativeError> {
    let sdk = match AsiSdk::get() {
        Some(sdk) => sdk,
        None => {
            // Log prominently so users know why discovery returned nothing
            tracing::debug!("ZWO native camera discovery skipped: ASI SDK not loaded");
            return Ok(Vec::new());
        }
    };

    // Acquire mutex for SDK discovery operations
    let _lock = zwo_camera_mutex().lock().await;
    let sdk_version = asi_sdk_version_from_sdk(sdk);

    tracing::debug!("Discovering ZWO cameras via native ASI SDK...");
    // SAFETY: zwo_camera_mutex held above; ASIGetNumOfConnectedCameras takes no arguments and only reads internal SDK state.
    let num_cameras = unsafe { (sdk.get_num_cameras)() };
    tracing::debug!("ASI SDK reports {} connected camera(s)", num_cameras);

    let mut cameras = Vec::new();
    let mut failed_count = 0;

    for i in 0..num_cameras {
        // SAFETY: ASICameraInfo is `#[repr(C)]` POD; zeroed is a valid initial state before SDK populates it.
        let mut info: ASICameraInfo = unsafe { std::mem::zeroed() };
        // ASIGetCameraProperty(ASI_CAMERA_INFO *pASICameraInfo, int iCameraIndex)
        // SAFETY: zwo_camera_mutex held above; `i` is bounded by num_cameras returned by the SDK; `info` is a valid stack pointer.
        let result = unsafe { (sdk.get_camera_property)(&mut info, i) };

        if result == 0 {
            // SAFETY: ASI SDK guarantees `info.name` is a NUL-terminated UTF-8 string within the 64-byte array; to_string_lossy handles any non-UTF8 bytes by replacing them.
            let name = unsafe {
                CStr::from_ptr(info.name.as_ptr())
                    .to_string_lossy()
                    .to_string()
            };
            tracing::info!(
                "Found ZWO camera: {} (ID: {}, index: {})",
                name,
                info.camera_id,
                i
            );

            cameras.push(ZwoDiscoveryInfo {
                camera_id: info.camera_id,
                name,
                // Why: `i` ranges 0..num_cameras (c_int) and is non-negative by loop
                // bound; ZWO advertises a small camera count (<= ~10). `as usize` is
                // widening with verified non-negative value.
                discovery_index: i as usize,
                sdk_version: sdk_version.clone(),
            });
        } else {
            failed_count += 1;
            let error_desc = match result {
                1 => "INVALID_INDEX - camera may be in use by another application",
                2 => "INVALID_ID",
                3 => "INVALID_CONTROL_TYPE",
                4 => "CAMERA_CLOSED",
                5 => "CAMERA_REMOVED - camera was disconnected",
                6 => "INVALID_PATH",
                7 => "INVALID_FILEFORMAT",
                8 => "INVALID_SIZE",
                9 => "INVALID_IMGTYPE",
                10 => "OUTOF_BOUNDARY",
                11 => "TIMEOUT",
                12 => "INVALID_SEQUENCE",
                13 => "BUFFER_TOO_SMALL",
                14 => "VIDEO_MODE_ACTIVE",
                15 => "EXPOSURE_IN_PROGRESS",
                16 => "GENERAL_ERROR - camera may be in use by another application",
                17 => "INVALID_MODE",
                18 => "GPS_NOT_SUPPORTED",
                19 => "GPS_VER_ERROR",
                20 => "GPS_FPGA_ERROR",
                21 => "GPS_DATA_ERROR",
                22 => "END",
                _ => "UNKNOWN",
            };
            tracing::warn!(
                "Failed to query camera index {}: ASI error {} ({})",
                i,
                result,
                error_desc
            );
        }
    }

    if cameras.is_empty() && num_cameras > 0 {
        tracing::error!(
            "ASI SDK detected {} camera(s) but none could be queried. \
            This usually means the cameras are in use by another application \
            (NINA, SharpCap, APT, PHD2, etc.). Close other astrophotography software and try again.",
            num_cameras
        );
    } else if failed_count > 0 {
        tracing::warn!(
            "Successfully discovered {} of {} cameras. {} camera(s) may be in use by other software.",
            cameras.len(), num_cameras, failed_count
        );
    }

    Ok(cameras)
}
