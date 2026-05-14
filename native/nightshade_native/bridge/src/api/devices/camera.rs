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
// Camera Exposure Control (Real Cameras)
// =============================================================================

/// Start camera exposure
/// This delegates to api_camera_start_exposure which handles the full exposure
/// workflow including waiting for completion, image processing, and storage.
pub async fn start_exposure(
    device_id: String,
    duration_secs: f64,
    gain: i32,
    offset: i32,
    bin_x: i32,
    bin_y: i32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "API: start_exposure called for {} duration={}",
        device_id,
        duration_secs
    );

    // Delegate to the full implementation which handles:
    // - Starting the exposure
    // - Publishing progress events
    // - Waiting for completion
    // - Downloading and processing the image
    // - Storing the result for get_last_image()
    api_camera_start_exposure(device_id, duration_secs, gain, offset, bin_x, bin_y).await
}

/// Abort/cancel camera exposure
pub async fn cancel_exposure(device_id: String) -> Result<(), NightshadeError> {
    tracing::info!("API: cancel_exposure called for {}", device_id);

    let mgr = get_device_manager();
    mgr.camera_abort_exposure(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))?;

    // Publish ExposureCancelled event
    let state = get_state();
    let event = crate::event::create_event_auto_id(
        crate::event::EventSeverity::Info,
        crate::event::EventCategory::Imaging,
        crate::event::EventPayload::Imaging(crate::event::ImagingEvent::ExposureCancelled),
    );
    state.event_bus.publish(event);

    Ok(())
}

/// Get camera status
pub async fn get_camera_status(device_id: String) -> Result<CameraStatus, NightshadeError> {
    let mgr = get_device_manager();
    mgr.camera_get_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera cooler
pub async fn set_camera_cooler(
    device_id: String,
    enabled: u8,
    target_temp: Option<f64>,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.camera_set_cooler(&device_id, enabled != 0, target_temp)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Camera Readout Mode
// =============================================================================

/// Set camera readout mode by index
///
/// mode_index: 0 = default/high quality, 1 = fast readout, etc.
/// The available modes are camera-dependent.
pub async fn api_camera_set_readout_mode(
    device_id: String,
    mode_index: i32,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Simulator camera readout mode set to index: {}", mode_index);
        return Ok(());
    }

    tracing::info!(
        "Setting camera readout mode for {}: index={}",
        device_id,
        mode_index
    );
    let mgr = get_device_manager();
    mgr.camera_set_readout_mode(&device_id, mode_index)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Camera Binning (Legacy API - keeping for compatibility)
// =============================================================================

/// Set camera binning
pub async fn api_set_camera_binning(
    device_id: String,
    bin_x: i32,
    bin_y: i32,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.bin_x = bin_x;
        camera.status.bin_y = bin_y;
        tracing::info!("Camera binning set to: {}x{}", bin_x, bin_y);
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.camera_set_binning(&device_id, bin_x, bin_y)
            .await
            .map_err(NightshadeError::OperationFailed)
    }
}