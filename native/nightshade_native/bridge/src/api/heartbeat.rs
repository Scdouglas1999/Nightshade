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
// Device Heartbeat Monitoring
// =============================================================================

/// Start heartbeat monitoring for a device
///
/// This will poll the device status at the specified interval and emit
/// a Disconnected event if the device becomes unresponsive.
///
/// # Arguments
/// * `device_type` - The type of device to monitor (used for validation)
/// * `device_id` - The unique identifier for the device
/// * `interval_ms` - Heartbeat interval in milliseconds (recommended: 10000)
pub async fn api_start_device_heartbeat(
    device_type: DeviceType,
    device_id: String,
    interval_ms: u64,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Starting heartbeat monitoring for {} device: {} (interval: {}ms)",
        device_type.as_str(),
        device_id,
        interval_ms
    );

    // Validate device type matches
    if let Some(device) = get_device_manager().get_device(&device_id).await {
        if device.info.device_type != device_type {
            return Err(NightshadeError::InvalidParameter(format!(
                "Device {} is type {:?}, not {:?}",
                device_id, device.info.device_type, device_type
            )));
        }
    }

    get_device_manager()
        .start_heartbeat(&device_id, std::time::Duration::from_millis(interval_ms))
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Stop heartbeat monitoring for a device
///
/// # Arguments
/// * `device_id` - The unique identifier for the device
pub async fn api_stop_device_heartbeat(device_id: String) -> Result<(), NightshadeError> {
    tracing::info!("Stopping heartbeat monitoring for device: {}", device_id);

    get_device_manager()
        .stop_heartbeat(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Start heartbeat monitoring with custom configuration
///
/// This allows full control over the heartbeat behavior including:
/// - Check interval and maximum interval after backoff
/// - Number of failures before marking device as disconnected
/// - Whether to attempt auto-reconnection
/// - Reconnection attempt limits and delays
///
/// # Arguments
/// * `device_id` - The unique identifier for the device
/// * `interval_secs` - Base interval between heartbeats in seconds
/// * `failure_threshold` - Number of consecutive failures before disconnect
/// * `auto_reconnect` - Whether to attempt automatic reconnection
/// * `max_reconnect_attempts` - Maximum reconnection attempts (0 = unlimited)
pub async fn api_start_device_heartbeat_with_config(
    device_id: String,
    interval_secs: u64,
    failure_threshold: u32,
    auto_reconnect: bool,
    max_reconnect_attempts: u32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Starting heartbeat with config for device: {} (interval={}s, threshold={}, auto_reconnect={}, max_attempts={})",
        device_id,
        interval_secs,
        failure_threshold,
        auto_reconnect,
        max_reconnect_attempts
    );

    let config = crate::device_manager::HeartbeatConfig {
        base_interval_secs: interval_secs,
        max_interval_secs: interval_secs * 6, // 6x base for max backoff
        failure_threshold,
        backoff_multiplier: 2.0,
        auto_reconnect,
        max_reconnect_attempts,
        reconnect_delay_secs: 5,
    };

    get_device_manager()
        .start_heartbeat_with_config(&device_id, config)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the default heartbeat configuration for a device type
///
/// Returns the recommended heartbeat settings for the specified device type.
/// Different device types have different optimal configurations based on
/// their operational characteristics.
///
/// # Arguments
/// * `device_type` - The type of device to get configuration for
///
/// # Returns
/// A tuple of (interval_secs, max_interval_secs, failure_threshold, auto_reconnect)
pub fn api_get_heartbeat_config_for_type(device_type: DeviceType) -> (u64, u64, u32, bool) {
    let config = match device_type {
        DeviceType::Camera => crate::device_manager::HeartbeatConfig::for_camera(),
        DeviceType::Mount => crate::device_manager::HeartbeatConfig::for_mount(),
        DeviceType::Focuser => crate::device_manager::HeartbeatConfig::for_focuser(),
        DeviceType::FilterWheel => crate::device_manager::HeartbeatConfig::for_filter_wheel(),
        DeviceType::Dome => crate::device_manager::HeartbeatConfig::for_dome(),
        DeviceType::Rotator => crate::device_manager::HeartbeatConfig::for_rotator(),
        DeviceType::Weather => crate::device_manager::HeartbeatConfig::for_weather(),
        DeviceType::SafetyMonitor => crate::device_manager::HeartbeatConfig::for_safety_monitor(),
        _ => crate::device_manager::HeartbeatConfig::default(),
    };

    (
        config.base_interval_secs,
        config.max_interval_secs,
        config.failure_threshold,
        config.auto_reconnect,
    )
}

/// Check device health status
///
/// Returns the last successful communication timestamp and whether
/// the device is currently responding to heartbeat checks.
///
/// # Arguments
/// * `device_id` - The unique identifier for the device
///
/// # Returns
/// A tuple of (last_successful_timestamp_ms, is_healthy)
pub async fn api_get_device_health(device_id: String) -> Result<(i64, bool), NightshadeError> {
    get_device_manager()
        .get_device_health(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Detailed heartbeat status for a device
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb]
pub struct DeviceHeartbeatInfo {
    /// Device ID
    pub device_id: String,
    /// Device type (e.g., "Camera", "Mount")
    pub device_type: String,
    /// Whether heartbeat monitoring is currently active
    pub heartbeat_active: bool,
    /// Last successful communication timestamp (milliseconds since epoch)
    pub last_successful_comm_ms: Option<i64>,
    /// Current heartbeat interval in seconds
    pub interval_secs: u64,
    /// Maximum interval after backoff in seconds
    pub max_interval_secs: u64,
    /// Number of failures before marking disconnected
    pub failure_threshold: u32,
    /// Whether auto-reconnect is enabled
    pub auto_reconnect: bool,
    /// Maximum reconnection attempts (0 = unlimited)
    pub max_reconnect_attempts: u32,
}

/// Get detailed heartbeat status for a device
///
/// Returns comprehensive information about the heartbeat monitoring status
/// including configuration, last successful communication, and whether
/// monitoring is active.
///
/// # Arguments
/// * `device_id` - The unique identifier for the device
///
/// # Returns
/// DeviceHeartbeatInfo with all heartbeat details
pub async fn api_get_device_heartbeat_info(
    device_id: String,
) -> Result<DeviceHeartbeatInfo, NightshadeError> {
    let manager = get_device_manager();

    // Check if device exists and get its info using the public API
    let device = manager
        .get_device(&device_id)
        .await
        .ok_or_else(|| NightshadeError::DeviceNotFound(device_id.clone()))?;

    let device_type_enum = device.info.device_type.clone();

    // Get device-type specific configuration
    let config = crate::device_manager::HeartbeatConfig::for_device_type(&device_type_enum);

    Ok(DeviceHeartbeatInfo {
        device_id,
        device_type: device_type_enum.as_str().to_string(),
        heartbeat_active: device.heartbeat_active,
        last_successful_comm_ms: device.last_successful_comm,
        interval_secs: config.base_interval_secs,
        max_interval_secs: config.max_interval_secs,
        failure_threshold: config.failure_threshold,
        auto_reconnect: config.auto_reconnect,
        max_reconnect_attempts: config.max_reconnect_attempts,
    })
}

/// Check if heartbeat monitoring is active for a device
pub async fn api_is_heartbeat_active(device_id: String) -> Result<bool, NightshadeError> {
    Ok(get_device_manager().is_heartbeat_active(&device_id).await)
}