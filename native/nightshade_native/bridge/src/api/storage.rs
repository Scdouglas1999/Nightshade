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
use super::*;

// =============================================================================
// Equipment Profiles
// =============================================================================

/// Initialize profile storage
#[flutter_rust_bridge::frb(sync)]
pub fn api_init_profile_storage(storage_path: String) -> Result<(), NightshadeError> {
    crate::state::init_profile_storage(std::path::PathBuf::from(storage_path))
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get all equipment profiles
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_profiles() -> Result<Vec<EquipmentProfile>, NightshadeError> {
    get_state()
        .load_profiles()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Save an equipment profile
#[flutter_rust_bridge::frb(sync)]
pub fn api_save_profile(profile: EquipmentProfile) -> Result<(), NightshadeError> {
    get_state()
        .save_profile_to_storage(&profile)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Delete an equipment profile
#[flutter_rust_bridge::frb(sync)]
pub fn api_delete_profile(profile_id: String) -> Result<(), NightshadeError> {
    get_state()
        .delete_profile_from_storage(&profile_id)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Load a profile and set as active
pub async fn api_load_profile(profile_id: String) -> Result<(), NightshadeError> {
    get_state()
        .load_and_set_profile(&profile_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the currently active profile
pub async fn api_get_active_profile() -> Result<Option<EquipmentProfile>, NightshadeError> {
    Ok(get_state().get_profile().await)
}

// =============================================================================
// Settings & Location
// =============================================================================

/// Initialize settings storage and load observer location into memory
#[flutter_rust_bridge::frb(sync)]
pub fn api_init_settings_storage(storage_path: String) -> Result<(), NightshadeError> {
    let path = std::path::PathBuf::from(storage_path);
    crate::state::init_settings_storage(path.clone())
        .map_err(|e| NightshadeError::OperationFailed(e))?;
    // Plate-solver preferences share the settings directory. Errors here are
    // not fatal — the API falls back to in-memory defaults if storage is
    // unavailable — but a hard failure to initialise still surfaces.
    crate::state::init_platesolver_storage(path)
        .map_err(|e| NightshadeError::OperationFailed(e))?;

    // Load observer location from persisted settings into in-memory state
    // This ensures the sequencer and other Rust components have access to location
    get_state().load_observer_location_from_settings();

    Ok(())
}

/// Get application settings
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_settings() -> Result<AppSettings, NightshadeError> {
    get_state()
        .get_settings()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Update application settings
#[flutter_rust_bridge::frb(sync)]
pub fn api_update_settings(settings: AppSettings) -> Result<(), NightshadeError> {
    get_state()
        .update_settings(&settings)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get observer location
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_location() -> Result<Option<ObserverLocation>, NightshadeError> {
    get_state()
        .get_observer_location()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set observer location
#[flutter_rust_bridge::frb(sync)]
pub fn api_set_location(location: Option<ObserverLocation>) -> Result<(), NightshadeError> {
    match &location {
        Some(loc) => {
            tracing::info!(
                "[API] api_set_location called with lat={}, lon={}, elev={}",
                loc.latitude,
                loc.longitude,
                loc.elevation
            );
        }
        None => {
            tracing::info!("[API] api_set_location called with None");
        }
    }
    let result = get_state().set_observer_location(location);
    match &result {
        Ok(_) => {
            tracing::debug!("[API] api_set_location succeeded");
        }
        Err(ref e) => {
            tracing::error!("[API] api_set_location failed: {}", e);
        }
    }
    result.map_err(|e| NightshadeError::OperationFailed(e))
}
