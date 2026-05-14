// CQ-W3-API-RS: split from monolithic api.rs (audit-rust §9 / audit-arch §1.2)
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs (audit-rust §9).
use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::devices::DeviceManager;
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
// Focuser Control
// =============================================================================

/// Move focuser to absolute position
pub async fn focuser_move_abs(device_id: String, position: i32) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_move_abs(&device_id, position)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Move focuser relative
pub async fn focuser_move_rel(device_id: String, steps: i32) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_move_rel(&device_id, steps)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Halt focuser
pub async fn focuser_halt(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_halt(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get focuser position
pub async fn focuser_get_position(device_id: String) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_get_position(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get focuser temperature
pub async fn focuser_get_temp(device_id: String) -> Result<Option<f64>, NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_get_temp(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get focuser details (max pos, step size)
pub async fn focuser_get_details(device_id: String) -> Result<(i32, f64), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_get_details(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}