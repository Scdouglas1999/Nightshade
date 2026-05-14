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
use super::*;

// =============================================================================
// DEVICE CAPABILITY REPORTING API
// =============================================================================

/// Get capabilities for any device by its device ID.
///
/// This function queries the actual device to determine what features it supports.
/// The result varies by device type (camera, mount, focuser, filter wheel).
///
/// # Arguments
/// * `device_id` - The full device ID string (e.g., "ascom:ASCOM.Camera.Simulator")
///
/// # Returns
/// * `DeviceCapabilities` - An enum containing the appropriate capability struct
///
/// # Errors
/// * Returns error if device type is unsupported or device cannot be queried
pub async fn api_get_device_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::DeviceCapabilities, NightshadeError> {
    crate::device_capabilities::get_device_capabilities(&device_id).await
}

/// Get camera capabilities for a specific camera device.
///
/// This is a convenience wrapper that returns only camera capabilities.
///
/// # Arguments
/// * `device_id` - The camera device ID
///
/// # Returns
/// * `CameraCapabilities` - Camera-specific capability information
pub async fn api_get_camera_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::CameraCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Camera(c) => Ok(c),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a camera",
        )),
    }
}

/// Get mount capabilities for a specific mount device.
///
/// This is a convenience wrapper that returns only mount capabilities.
///
/// # Arguments
/// * `device_id` - The mount/telescope device ID
///
/// # Returns
/// * `MountCapabilities` - Mount-specific capability information
pub async fn api_get_mount_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::MountCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Mount(m) => Ok(m),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a mount",
        )),
    }
}

/// Get focuser capabilities for a specific focuser device.
///
/// This is a convenience wrapper that returns only focuser capabilities.
///
/// # Arguments
/// * `device_id` - The focuser device ID
///
/// # Returns
/// * `FocuserCapabilities` - Focuser-specific capability information
pub async fn api_get_focuser_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::FocuserCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Focuser(f) => Ok(f),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a focuser",
        )),
    }
}

/// Get filter wheel capabilities for a specific filter wheel device.
///
/// This is a convenience wrapper that returns only filter wheel capabilities.
///
/// # Arguments
/// * `device_id` - The filter wheel device ID
///
/// # Returns
/// * `FilterWheelCapabilities` - Filter wheel-specific capability information
pub async fn api_get_filterwheel_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::FilterWheelCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::FilterWheel(fw) => Ok(fw),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a filter wheel",
        )),
    }
}

/// Get rotator capabilities for a specific rotator device.
///
/// This is a convenience wrapper that returns only rotator capabilities.
///
/// # Arguments
/// * `device_id` - The rotator device ID
///
/// # Returns
/// * `RotatorCapabilities` - Rotator-specific capability information
pub async fn api_get_rotator_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::RotatorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Rotator(r) => Ok(r),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a rotator",
        )),
    }
}

/// Get dome capabilities for a specific dome device.
///
/// This is a convenience wrapper that returns only dome capabilities.
///
/// # Arguments
/// * `device_id` - The dome device ID
///
/// # Returns
/// * `DomeCapabilities` - Dome-specific capability information
pub async fn api_get_dome_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::DomeCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Dome(d) => Ok(d),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a dome",
        )),
    }
}

/// Get cover calibrator capabilities for a specific cover calibrator device.
///
/// This is a convenience wrapper that returns only cover calibrator capabilities.
///
/// # Arguments
/// * `device_id` - The cover calibrator device ID
///
/// # Returns
/// * `CoverCalibratorCapabilities` - Cover calibrator-specific capability information
pub async fn api_get_cover_calibrator_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::CoverCalibratorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::CoverCalibrator(cc) => Ok(cc),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a cover calibrator",
        )),
    }
}

/// Get weather capabilities for a specific weather/observing conditions device.
///
/// This is a convenience wrapper that returns only weather capabilities.
///
/// # Arguments
/// * `device_id` - The weather device ID
///
/// # Returns
/// * `WeatherCapabilities` - Weather-specific capability information
pub async fn api_get_weather_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::WeatherCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Weather(w) => Ok(w),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a weather station",
        )),
    }
}

/// Get safety monitor capabilities for a specific safety monitor device.
///
/// This is a convenience wrapper that returns only safety monitor capabilities.
///
/// # Arguments
/// * `device_id` - The safety monitor device ID
///
/// # Returns
/// * `SafetyMonitorCapabilities` - Safety monitor-specific capability information
pub async fn api_get_safety_monitor_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::SafetyMonitorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::SafetyMonitor(sm) => Ok(sm),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a safety monitor",
        )),
    }
}

/// Get switch capabilities for a specific switch device.
///
/// This is a convenience wrapper that returns only switch capabilities.
///
/// # Arguments
/// * `device_id` - The switch device ID
///
/// # Returns
/// * `SwitchCapabilities` - Switch-specific capability information
pub async fn api_get_switch_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::SwitchCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Switch(s) => Ok(s),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a switch",
        )),
    }
}

// =============================================================================
// DEVICE QUIRKS
// =============================================================================

/// Information about a known device quirk, suitable for UI display.
pub struct QuirkInfo {
    /// Quirk category (e.g. "Temperature", "Timing", "Discovery")
    pub category: String,
    /// Human-readable description of the quirk
    pub description: String,
}

/// Get known quirks for a connected device.
///
/// Returns a list of known device characteristics and workarounds that are
/// automatically applied. This information can be displayed in the equipment
/// screen to inform users about device-specific behaviors.
///
/// # Arguments
/// * `device_id` - The device identifier (e.g., "native:zwo:ASI294MC Pro")
///
/// # Returns
/// * `Vec<QuirkInfo>` - List of quirks with categories and descriptions
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_device_quirks(device_id: String) -> Vec<QuirkInfo> {
    let quirks = nightshade_native::quirks::get_quirks_for_device(&device_id);
    quirks
        .into_iter()
        .map(|q| QuirkInfo {
            category: q.category().to_string(),
            description: q.description(),
        })
        .collect()
}

// =============================================================================
// QHY DISCOVERY CONTROL
// =============================================================================

/// Check if QHY camera discovery is enabled.
///
/// QHY discovery can be disabled if the QHY SDK causes crashes or hangs on the
/// user's system. When disabled, QHY cameras will not appear in device discovery.
///
/// # Returns
/// * `true` - QHY discovery is enabled (default)
/// * `false` - QHY discovery is disabled
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_qhy_discovery_enabled() -> bool {
    nightshade_native::vendor::qhy::is_qhy_discovery_enabled()
}

/// Enable or disable QHY camera discovery.
///
/// Use this function to disable QHY discovery if it causes problems:
/// - SDK crashes during enumeration
/// - Discovery hangs and never completes
/// - Conflicts with other camera SDKs
///
/// When disabled:
/// - `discover_devices()` returns empty for QHY cameras/filter wheels
/// - Existing QHY camera connections are not affected
/// - The setting persists for the session but resets on restart
///
/// # Arguments
/// * `enabled` - Whether to enable QHY discovery
///
/// # Example Use Cases
/// 1. Disable if QHY SDK not installed to speed up discovery
/// 2. Disable if QHY SDK crashes on this system
/// 3. Disable temporarily to troubleshoot conflicts
#[flutter_rust_bridge::frb(sync)]
pub fn api_set_qhy_discovery_enabled(enabled: bool) {
    nightshade_native::vendor::qhy::set_qhy_discovery_enabled(enabled);
}

/// Get information about QHY SDK availability and discovery status.
///
/// # Returns
/// * `QhyDiscoveryStatus` - Status information about QHY discovery
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_qhy_discovery_status() -> QhyDiscoveryStatus {
    QhyDiscoveryStatus {
        sdk_available: nightshade_native::vendor::qhy::is_sdk_available(),
        discovery_enabled: nightshade_native::vendor::qhy::is_qhy_discovery_enabled(),
        timeout_ms: get_qhy_discovery_timeout_ms(),
    }
}

/// Helper to get the QHY discovery timeout from quirks
pub(crate) fn get_qhy_discovery_timeout_ms() -> u64 {
    use nightshade_native::quirks::{get_quirks_for_vendor, DiscoveryQuirk, Quirk};
    use nightshade_native::NativeVendor;

    let quirks = get_quirks_for_vendor(&NativeVendor::Qhy);
    for quirk in quirks {
        if let Quirk::Discovery(DiscoveryQuirk::DiscoveryTimeoutMs(timeout)) = quirk {
            return timeout;
        }
    }
    10000 // Default timeout
}

/// Status information about QHY discovery
#[derive(Debug, Clone)]
pub struct QhyDiscoveryStatus {
    /// Whether the QHY SDK DLL/SO was loaded successfully
    pub sdk_available: bool,
    /// Whether QHY discovery is currently enabled
    pub discovery_enabled: bool,
    /// The timeout for discovery operations in milliseconds
    pub timeout_ms: u64,
}