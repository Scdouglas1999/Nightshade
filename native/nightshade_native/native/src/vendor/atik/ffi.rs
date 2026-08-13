//! Atik SDK FFI types (from AtikDefs.h / AtikCameras.h).

use super::*;

// =============================================================================
// Atik SDK Types (from AtikDefs.h and AtikCameras.h)
// =============================================================================

/// Atik SDK handle type
pub(crate) type ArtemisHandle = *mut c_void;

/// Wrapper to make raw pointer Send + Sync
/// SAFETY: The Atik SDK requires that all calls to a given camera handle
/// be serialized, which we ensure through the Mutex wrapper in AtikCamera.
pub(crate) struct HandleWrapper(pub(crate) ArtemisHandle);
// SAFETY: HandleWrapper is only ever accessed while holding the per-camera
// `handle: Mutex<HandleWrapper>` AND the global `atik_mutex()` async lock, so
// no two threads ever touch the raw ArtemisHandle concurrently.
unsafe impl Send for HandleWrapper {}
// SAFETY: Same justification as `Send` above — the wrapped raw pointer is
// never dereferenced outside the global Atik SDK mutex, so shared references
// across threads cannot trigger concurrent FFI calls.
unsafe impl Sync for HandleWrapper {}

/// Atik error codes
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ArtemisError {
    Ok = 0,
    InvalidParameter = 1,
    NotConnected = 2,
    NotImplemented = 3,
    NoResponse = 4,
    InvalidFunction = 5,
    NotInitialized = 6,
    OperationFailed = 7,
    InvalidPassword = 8,
}

impl ArtemisError {
    pub(crate) fn from_i32(code: i32) -> Self {
        match code {
            0 => ArtemisError::Ok,
            1 => ArtemisError::InvalidParameter,
            2 => ArtemisError::NotConnected,
            3 => ArtemisError::NotImplemented,
            4 => ArtemisError::NoResponse,
            5 => ArtemisError::InvalidFunction,
            6 => ArtemisError::NotInitialized,
            7 => ArtemisError::OperationFailed,
            8 => ArtemisError::InvalidPassword,
            _ => ArtemisError::OperationFailed,
        }
    }

    pub(crate) fn to_native_error(self, msg: &str) -> NativeError {
        tracing::error!(
            "Atik SDK error during '{}': {:?}. Check camera connection and SDK installation.",
            msg,
            self
        );
        NativeError::SdkError(format!(
            "Atik {}: {:?}. Ensure camera is connected and AtikCameras driver is installed.",
            msg, self
        ))
    }
}

/// Camera properties structure (ARTEMISPROPERTIES)
#[repr(C)]
#[derive(Debug)]
pub(crate) struct ArtemisProperties {
    pub(crate) protocol: c_int,
    pub(crate) pixels_x: c_int,
    pub(crate) pixels_y: c_int,
    pub(crate) pixel_microns_x: c_float,
    pub(crate) pixel_microns_y: c_float,
    pub(crate) ccd_flags: c_int,
    pub(crate) camera_flags: c_int,
    pub(crate) description: [c_char; 40],
    pub(crate) manufacturer: [c_char; 40],
}

// Camera flags from ARTEMISPROPERTIESCAMERAFLAGS
pub(crate) const ARTEMIS_CAMERA_HAS_SHUTTER: c_int = 16;
pub(crate) const ARTEMIS_CAMERA_HAS_GUIDE_PORT: c_int = 32;
pub(crate) const ARTEMIS_COLOUR_RGGB: c_int = 2;
