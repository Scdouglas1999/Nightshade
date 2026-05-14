// CQ-W3-API-RS: split from monolithic api.rs (audit-rust §9 / audit-arch §1.2)
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs (audit-rust §9).
use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
use crate::filter_matching::find_filter_match;
use crate::state::*;
use crate::storage::{AppSettings, ObserverLocation};
use crate::unified_device_ops::create_unified_device_ops;
use nightshade_imaging::{
    calculate_airmass, validate_fits_header, validate_image, write_fits, BayerPattern,
    DebayerAlgorithm, FitsHeader, ImageData,
};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::sync::RwLock;
// Sibling-module items via the parent's pub use re-exports.
use super::super::*;
use super::*;

// =============================================================================
// Mount Control
// =============================================================================

/// Slew mount to coordinates
pub async fn mount_slew(device_id: String, ra: f64, dec: f64) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_slew(&device_id, ra, dec)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Sync mount to coordinates
pub async fn mount_sync(device_id: String, ra: f64, dec: f64) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_sync(&device_id, ra, dec)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Park mount
pub async fn mount_park(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_park(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Unpark mount
pub async fn mount_unpark(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_unpark(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get mount coordinates
pub async fn mount_get_coordinates(device_id: String) -> Result<(f64, f64), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_get_coordinates(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Abort mount slew
pub async fn mount_abort(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_abort(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Stop mount motion (abort slew without disconnecting)
pub async fn mount_stop(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_stop(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Query whether a mount supports parking
pub async fn mount_can_park(device_id: String) -> Result<bool, NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_can_park(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set mount tracking
pub async fn mount_set_tracking(device_id: String, enabled: u8) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_set_tracking(&device_id, enabled != 0)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
pub async fn mount_set_tracking_rate(device_id: String, rate: i32) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_set_tracking_rate(&device_id, rate)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Pulse guide mount
pub async fn mount_pulse_guide(
    device_id: String,
    direction: String,
    duration_ms: u32,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_pulse_guide(&device_id, direction, duration_ms)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get mount status
pub async fn mount_get_status(device_id: String) -> Result<MountStatus, NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_get_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
pub async fn mount_get_tracking_rate(device_id: String) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_get_tracking_rate(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Move mount axis at specified rate (degrees/second)
/// axis: 0=RA/Azimuth (primary), 1=Dec/Altitude (secondary)
/// rate: degrees per second (positive = N/E, negative = S/W), 0 to stop
pub async fn mount_move_axis(
    device_id: String,
    axis: i32,
    rate: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_move_axis(&device_id, axis, rate)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Slew mount to alt/az coordinates (altitude in degrees, azimuth in degrees)
pub async fn mount_slew_alt_az(
    device_id: String,
    altitude: f64,
    azimuth: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_slew_alt_az(&device_id, altitude, azimuth)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Find mount home position
pub async fn mount_find_home(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_find_home(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}