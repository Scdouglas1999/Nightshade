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
// Camera Control (Simulator implementation)
// =============================================================================

/// Simulated camera state
pub(crate) static SIM_CAMERA: OnceLock<Arc<RwLock<SimulatedCamera>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedCamera {
    pub status: CameraStatus,
}

impl Default for SimulatedCamera {
    fn default() -> Self {
        Self {
            status: CameraStatus {
                connected: false,
                state: CameraState::Idle,
                sensor_temp: Some(20.0),
                cooler_power: Some(0.0),
                target_temp: Some(-10.0),
                cooler_on: false,
                gain: 100,
                offset: 10,
                bin_x: 1,
                bin_y: 1,
                sensor_width: 4144,
                sensor_height: 2822,
                pixel_size_x: 3.76,
                pixel_size_y: 3.76,
                max_adu: 65535,
                can_cool: true,
                can_set_gain: true,
                can_set_offset: true,
            },
        }
    }
}

pub(crate) fn get_sim_camera() -> &'static Arc<RwLock<SimulatedCamera>> {
    SIM_CAMERA.get_or_init(|| Arc::new(RwLock::new(SimulatedCamera::default())))
}

/// Get camera status
pub async fn api_get_camera_status(device_id: String) -> Result<CameraStatus, NightshadeError> {
    // Handle simulator devices with local simulated state
    if device_id.starts_with("sim_") {
        let camera = get_sim_camera().read().await;
        return Ok(camera.status.clone());
    }

    // Route real devices through the DeviceManager
    let mgr = get_device_manager();
    mgr.camera_get_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera cooling target
pub async fn api_set_camera_cooler(
    device_id: String,
    enabled: u8,
    target_temp: Option<f64>,
) -> Result<(), NightshadeError> {
    // Handle simulator devices with local simulated state
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.cooler_on = enabled != 0;
        if let Some(temp) = target_temp {
            camera.status.target_temp = Some(temp);
        }
        tracing::info!(
            "Simulator camera cooler: enabled={}, target={:?}",
            enabled,
            target_temp
        );
        return Ok(());
    }

    // Route real devices through the DeviceManager
    tracing::info!(
        "Setting camera cooler for {}: enabled={}, target={:?}",
        device_id,
        enabled,
        target_temp
    );
    let mgr = get_device_manager();
    mgr.camera_set_cooler(&device_id, enabled != 0, target_temp)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera gain
pub async fn api_set_camera_gain(device_id: String, gain: i32) -> Result<(), NightshadeError> {
    // Handle simulator devices with local simulated state
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.gain = gain;
        tracing::info!("Simulator camera gain set to: {}", gain);
        return Ok(());
    }

    // Route real devices through the DeviceManager
    tracing::info!("Setting camera gain for {}: {}", device_id, gain);
    let mgr = get_device_manager();
    mgr.camera_set_gain(&device_id, gain)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera offset
pub async fn api_set_camera_offset(device_id: String, offset: i32) -> Result<(), NightshadeError> {
    // Handle simulator devices with local simulated state
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.offset = offset;
        tracing::info!("Simulator camera offset set to: {}", offset);
        return Ok(());
    }

    // Route real devices through the DeviceManager
    tracing::info!("Setting camera offset for {}: {}", device_id, offset);
    let mgr = get_device_manager();
    mgr.camera_set_offset(&device_id, offset)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Mount Control (Simulator implementation)
// =============================================================================

/// Simulated mount state
pub(crate) static SIM_MOUNT: OnceLock<Arc<RwLock<SimulatedMount>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedMount {
    pub status: MountStatus,
}

impl Default for SimulatedMount {
    fn default() -> Self {
        // Simulator pretends to be a fully-capable mount: every optional field
        // is reported `Available` so UI rendering paths exercise the populated
        // case during development without needing real hardware.
        use crate::device::{mount_status_field as f, FieldAvailability};
        let mut availability = std::collections::HashMap::new();
        availability.insert(f::AT_HOME.to_string(), FieldAvailability::Available);
        availability.insert(f::SIDE_OF_PIER.to_string(), FieldAvailability::Available);
        availability.insert(f::ALTITUDE.to_string(), FieldAvailability::Available);
        availability.insert(f::AZIMUTH.to_string(), FieldAvailability::Available);
        availability.insert(f::SIDEREAL_TIME.to_string(), FieldAvailability::Available);
        availability.insert(f::TRACKING_RATE.to_string(), FieldAvailability::Available);
        Self {
            status: MountStatus {
                connected: false,
                tracking: false,
                slewing: false,
                parked: true,
                at_home: Some(false),
                side_of_pier: Some(PierSide::Unknown),
                right_ascension: 0.0,
                declination: 0.0,
                altitude: Some(0.0),
                azimuth: Some(0.0),
                sidereal_time: Some(0.0),
                tracking_rate: Some(TrackingRate::Sidereal),
                can_park: true,
                can_slew: true,
                can_sync: true,
                can_pulse_guide: true,
                can_set_tracking_rate: true,
                availability,
            },
        }
    }
}

pub(crate) fn get_sim_mount() -> &'static Arc<RwLock<SimulatedMount>> {
    SIM_MOUNT.get_or_init(|| Arc::new(RwLock::new(SimulatedMount::default())))
}

/// Get mount status
pub async fn api_get_mount_status(device_id: String) -> Result<MountStatus, NightshadeError> {
    if device_id.starts_with("sim_") {
        let mount = get_sim_mount().read().await;
        Ok(mount.status.clone())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_get_status(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Slew mount to coordinates
pub async fn api_mount_slew_to_coordinates(
    device_id: String,
    ra: f64,
    dec: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Slewing to RA: {:.4}h, Dec: {:.4}°", ra, dec);

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = true;
        }

        // Simulate slew time
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = false;
            mount.status.right_ascension = ra;
            mount.status.declination = dec;
            mount.status.parked = false;
        }

        tracing::info!("Slew complete");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_slew(&device_id, ra, dec)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Sync mount to coordinates
pub async fn api_mount_sync_to_coordinates(
    device_id: String,
    ra: f64,
    dec: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Syncing to RA: {:.4}h, Dec: {:.4}°", ra, dec);

        let mut mount = get_sim_mount().write().await;
        mount.status.right_ascension = ra;
        mount.status.declination = dec;

        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_sync(&device_id, ra, dec)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Park the mount
pub async fn api_mount_park(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Parking mount");

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = true;
        }

        // Simulate park time
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = false;
            mount.status.parked = true;
            mount.status.tracking = false;
        }

        tracing::info!("Mount parked");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_park(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Unpark the mount
pub async fn api_mount_unpark(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let mut mount = get_sim_mount().write().await;
        mount.status.parked = false;

        tracing::info!("Mount unparked");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_unpark(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Set mount tracking
pub async fn api_mount_set_tracking(device_id: String, enabled: u8) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let mut mount = get_sim_mount().write().await;
        mount.status.tracking = enabled != 0;

        tracing::info!("Mount tracking: {}", enabled);
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_set_tracking(&device_id, enabled != 0)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Slew mount to alt/az coordinates (simulator handler)
pub async fn api_mount_slew_alt_az(
    device_id: String,
    altitude: f64,
    azimuth: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Slewing to Alt: {:.4}°, Az: {:.4}°", altitude, azimuth);

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = true;
        }

        // Simulate slew time
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = false;
            mount.status.altitude = Some(altitude);
            mount.status.azimuth = Some(azimuth);
            mount.status.parked = false;
        }

        tracing::info!("Alt/Az slew complete");
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.mount_slew_alt_az(&device_id, altitude, azimuth)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Find mount home position (simulator handler)
pub async fn api_mount_find_home(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Finding mount home position");

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = true;
        }

        // Simulate home-finding time
        tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = false;
            mount.status.at_home = Some(true);
            mount.status.parked = false;
        }

        tracing::info!("Mount home found");
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.mount_find_home(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Pulse guide the mount in a direction for a duration
pub async fn api_mount_pulse_guide(
    device_id: String,
    direction: String,
    duration_ms: i32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Pulse guiding {} for {}ms in direction {}",
        device_id,
        duration_ms,
        direction
    );

    // Validate direction
    match direction.to_lowercase().as_str() {
        "north" | "n" | "south" | "s" | "east" | "e" | "west" | "w" => {}
        _ => {
            return Err(NightshadeError::InvalidParameter(format!(
                "Unknown direction: {}",
                direction
            )))
        }
    };

    // For simulator, just wait the duration
    if device_id.starts_with("sim_") {
        tokio::time::sleep(std::time::Duration::from_millis(duration_ms as u64)).await;
        tracing::info!("Pulse guide complete");
        return Ok(());
    }

    // Route real devices through DeviceManager
    let mgr = get_device_manager();
    mgr.mount_pulse_guide(&device_id, direction, duration_ms as u32)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Focuser Control (Simulator implementation)
// =============================================================================

/// Simulated focuser state
pub(crate) static SIM_FOCUSER: OnceLock<Arc<RwLock<SimulatedFocuser>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedFocuser {
    pub status: FocuserStatus,
}

impl Default for SimulatedFocuser {
    fn default() -> Self {
        Self {
            status: FocuserStatus {
                connected: false,
                position: 25000,
                moving: false,
                temperature: Some(20.0),
                max_position: 50000,
                step_size: 1.0,
                is_absolute: true,
                has_temperature: true,
            },
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub fn get_sim_focuser() -> &'static Arc<RwLock<SimulatedFocuser>> {
    SIM_FOCUSER.get_or_init(|| Arc::new(RwLock::new(SimulatedFocuser::default())))
}

/// Get focuser status
pub async fn api_get_focuser_status(device_id: String) -> Result<FocuserStatus, NightshadeError> {
    if device_id.starts_with("sim_") {
        let focuser = get_sim_focuser().read().await;
        Ok(focuser.status.clone())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();

        // Get all focuser status components
        let position = mgr
            .focuser_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let moving = mgr
            .focuser_is_moving(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let temperature = mgr.focuser_get_temp(&device_id).await.unwrap_or(None);
        let (max_position, step_size) = match mgr.focuser_get_details(&device_id).await {
            Ok(details) => details,
            Err(e) => {
                tracing::warn!(
                    "Failed to get focuser details for {}: {:?}. Returning unknown max/step values.",
                    device_id,
                    e
                );
                (0, 0.0)
            }
        };
        let is_absolute = mgr
            .focuser_is_absolute(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;

        Ok(FocuserStatus {
            connected: true,
            position,
            moving,
            temperature,
            max_position,
            step_size,
            is_absolute,
            has_temperature: temperature.is_some(),
        })
    }
}

/// Move focuser to position
pub async fn api_focuser_move_to(device_id: String, position: i32) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Moving simulator focuser to position: {}", position);

        {
            let mut focuser = get_sim_focuser().write().await;
            focuser.status.moving = true;
        }

        // Simulate move time based on distance
        let current_pos = {
            let focuser = get_sim_focuser().read().await;
            focuser.status.position
        };
        let distance = (position - current_pos).abs();
        let move_time = (distance as f64 / 1000.0).max(0.5);

        tokio::time::sleep(tokio::time::Duration::from_secs_f64(move_time)).await;

        {
            let mut focuser = get_sim_focuser().write().await;
            focuser.status.moving = false;
            focuser.status.position = position;
        }

        tracing::info!("Focuser move complete");
        Ok(())
    } else {
        // Real device - use DeviceManager for proper driver routing
        let mgr = get_device_manager();
        mgr.focuser_move_abs(&device_id, position)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Move focuser by relative amount
pub async fn api_focuser_move_relative(
    device_id: String,
    delta: i32,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // Atomically read current position and set target while under write lock
        // This prevents race conditions where two relative moves could read the same position
        let (current_pos, target_pos) = {
            let mut focuser = get_sim_focuser().write().await;
            let current = focuser.status.position;
            let target = current + delta;
            // Set moving=true and update position atomically while we hold the lock
            // This ensures another move_relative sees the updated position
            focuser.status.moving = true;
            focuser.status.position = target; // Pre-commit the target position
            (current, target)
        };

        // Simulate move time based on distance (lock released during sleep)
        let distance = delta.abs();
        let move_time = (distance as f64 / 1000.0).max(0.5);
        tokio::time::sleep(tokio::time::Duration::from_secs_f64(move_time)).await;

        // Mark move as complete
        {
            let mut focuser = get_sim_focuser().write().await;
            focuser.status.moving = false;
            // Position was already set above, no need to set again
        }

        tracing::info!(
            "Focuser relative move complete: {} + {} = {}",
            current_pos,
            delta,
            target_pos
        );
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.focuser_move_rel(&device_id, delta)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Halt focuser
pub async fn api_focuser_halt(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // For simulator, just stop moving
        let mut focuser = get_sim_focuser().write().await;
        focuser.status.moving = false;
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.focuser_halt(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

// =============================================================================
// Filter Wheel Control (Simulator implementation)
// =============================================================================

/// Simulated filter wheel state
pub(crate) static SIM_FILTERWHEEL: OnceLock<Arc<RwLock<SimulatedFilterWheel>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedFilterWheel {
    pub status: FilterWheelStatus,
}

impl Default for SimulatedFilterWheel {
    fn default() -> Self {
        Self {
            status: FilterWheelStatus {
                connected: false,
                position: 1,
                moving: false,
                filter_count: 7,
                filter_names: vec![
                    "L".to_string(),
                    "R".to_string(),
                    "G".to_string(),
                    "B".to_string(),
                    "Ha".to_string(),
                    "OIII".to_string(),
                    "SII".to_string(),
                ],
            },
        }
    }
}

pub(crate) fn get_sim_filterwheel() -> &'static Arc<RwLock<SimulatedFilterWheel>> {
    SIM_FILTERWHEEL.get_or_init(|| Arc::new(RwLock::new(SimulatedFilterWheel::default())))
}

/// Get filter wheel status
pub async fn api_get_filterwheel_status(
    device_id: String,
) -> Result<FilterWheelStatus, NightshadeError> {
    if device_id.starts_with("sim_") {
        let fw = get_sim_filterwheel().read().await;
        Ok(fw.status.clone())
    } else {
        // Real device - use DeviceManager for proper driver routing
        let mgr = get_device_manager();
        let position = mgr
            .filter_wheel_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        tracing::info!(
            "[api_get_filterwheel_status] device={}, raw position from SDK={}",
            device_id,
            position
        );
        let is_moving = mgr
            .filter_wheel_is_moving(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let (filter_count, filter_names) = mgr
            .filter_wheel_get_config(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;

        tracing::info!(
            "[api_get_filterwheel_status] Returning: position={}, moving={}, filter_count={}, names={:?}",
            position,
            is_moving,
            filter_count,
            filter_names
        );

        Ok(FilterWheelStatus {
            connected: true,
            position,
            moving: is_moving,
            filter_count,
            filter_names,
        })
    }
}

/// Set filter wheel position
pub async fn api_filterwheel_set_position(
    device_id: String,
    position: i32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "[API] api_filterwheel_set_position called: device_id={}, position={}",
        device_id,
        position
    );
    if device_id.starts_with("sim_") {
        tracing::info!("[API] Using simulator filter wheel");
        let mut fw = get_sim_filterwheel().write().await;

        // Simulate move
        fw.status.moving = true;
        fw.status.position = -1; // Unknown while moving

        // Instant move for sim
        fw.status.moving = false;
        fw.status.position = position;

        Ok(())
    } else {
        // Real device - use DeviceManager for proper driver routing
        tracing::info!("[API] Using real device via DeviceManager");
        let mgr = get_device_manager();
        let result = mgr
            .filter_wheel_set_position(&device_id, position)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e));
        match &result {
            Ok(_) => tracing::info!("[API] Filter wheel position set successfully"),
            Err(e) => tracing::error!("[API] Filter wheel set position failed: {:?}", e),
        }
        result
    }
}

/// Get filter names
pub async fn api_filterwheel_get_names(device_id: String) -> Result<Vec<String>, NightshadeError> {
    if device_id.starts_with("sim_") {
        let fw = get_sim_filterwheel().read().await;
        Ok(fw.status.filter_names.clone())
    } else {
        // Real device - use DeviceManager for proper driver routing
        let mgr = get_device_manager();
        let (_, filter_names) = mgr
            .filter_wheel_get_config(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        Ok(filter_names)
    }
}

/// Set filter by name
pub async fn api_filterwheel_set_by_name(
    device_id: String,
    name: String,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let position = {
            let fw = get_sim_filterwheel().read().await;
            fw.status.filter_names.iter().position(|n| n == &name)
        };

        if let Some(pos) = position {
            api_filterwheel_set_position(device_id, pos as i32).await
        } else {
            Err(NightshadeError::OperationFailed(format!(
                "Filter {} not found",
                name
            )))
        }
    } else {
        // Real device - find position by name and use DeviceManager
        let mgr = get_device_manager();

        // Get filter names from device
        let (_, filter_names) = mgr.filter_wheel_get_config(&device_id).await.map_err(|e| {
            NightshadeError::OperationFailed(format!("Failed to get filter config: {}", e))
        })?;

        // Find filter position by name (case-insensitive)
        let position = find_filter_match(&filter_names, &name)
            .map(|p| p as i32)
            .ok_or_else(|| {
                NightshadeError::OperationFailed(format!(
                    "Filter '{}' not found. Available: {:?}",
                    name, filter_names
                ))
            })?;

        // Set the filter position
        mgr.filter_wheel_set_position(&device_id, position)
            .await
            .map_err(|e| {
                NightshadeError::OperationFailed(format!("Failed to set filter: {}", e))
            })?;

        Ok(())
    }
}

/// Set filter names on a filter wheel
/// This pushes user-defined filter names from the equipment profile to the hardware driver.
pub async fn api_filterwheel_set_filter_names(
    device_id: String,
    names: Vec<String>,
) -> Result<(), NightshadeError> {
    tracing::info!("API: Setting filter names for '{}': {:?}", device_id, names);

    if device_id.starts_with("sim_") {
        // Simulator - update the simulated filter wheel's names
        let mut fw = get_sim_filterwheel().write().await;
        // Only update up to the existing count
        let count = fw.status.filter_names.len().min(names.len());
        for i in 0..count {
            fw.status.filter_names[i] = names[i].clone();
        }
        tracing::info!("API: Set {} filter names on simulator", count);
        Ok(())
    } else {
        // Real device - use DeviceManager
        let mgr = get_device_manager();
        mgr.filter_wheel_set_filter_names(&device_id, names)
            .await
            .map_err(|e| {
                NightshadeError::OperationFailed(format!("Failed to set filter names: {}", e))
            })?;
        Ok(())
    }
}

// =============================================================================
// Rotator Control (Simulator implementation)
// =============================================================================

/// Simulated rotator state
pub(crate) static SIM_ROTATOR: OnceLock<Arc<RwLock<SimulatedRotator>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedRotator {
    pub status: RotatorStatus,
}

impl Default for SimulatedRotator {
    fn default() -> Self {
        Self {
            status: RotatorStatus {
                connected: false,
                position: 0.0,
                moving: false,
                mechanical_position: 0.0,
                is_moving: false,
                can_reverse: true,
            },
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub fn get_sim_rotator() -> &'static Arc<RwLock<SimulatedRotator>> {
    SIM_ROTATOR.get_or_init(|| Arc::new(RwLock::new(SimulatedRotator::default())))
}

/// Get rotator status
pub async fn api_get_rotator_status(device_id: String) -> Result<RotatorStatus, NightshadeError> {
    if device_id.starts_with("sim_") {
        let rotator = get_sim_rotator().read().await;
        Ok(rotator.status.clone())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();

        let position = mgr
            .rotator_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let is_moving = mgr
            .rotator_is_moving(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let can_reverse = match api_get_rotator_capabilities(device_id.clone()).await {
            Ok(caps) => caps.can_reverse,
            Err(e) => {
                tracing::warn!(
                    "Failed to query rotator capabilities for {}: {:?}. Treating reverse as unsupported.",
                    device_id,
                    e
                );
                false
            }
        };

        Ok(RotatorStatus {
            connected: true,
            position,
            moving: is_moving,
            mechanical_position: position,
            is_moving,
            can_reverse,
        })
    }
}

/// Move rotator to angle
pub async fn api_rotator_move_to(device_id: String, angle: f64) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Moving simulator rotator to {}°", angle);

        {
            let mut rotator = get_sim_rotator().write().await;
            rotator.status.moving = true;
            rotator.status.is_moving = true;
        }

        // Simulate move time
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        {
            let mut rotator = get_sim_rotator().write().await;
            rotator.status.moving = false;
            rotator.status.is_moving = false;
            rotator.status.position = angle;
            rotator.status.mechanical_position = angle;
        }

        Ok(())
    } else {
        // Real device - use DeviceManager for proper driver routing
        let mgr = get_device_manager();
        mgr.rotator_move_absolute(&device_id, angle)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Move rotator relative
pub async fn api_rotator_move_relative(
    device_id: String,
    delta: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let current = {
            let rotator = get_sim_rotator().read().await;
            rotator.status.position
        };
        let target = (current + delta) % 360.0;
        let target = if target < 0.0 { target + 360.0 } else { target };

        api_rotator_move_to(device_id, target).await
    } else {
        // Real device - calculate target angle and use DeviceManager
        let mgr = get_device_manager();
        let current = mgr
            .rotator_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let target = (current + delta) % 360.0;
        let target = if target < 0.0 { target + 360.0 } else { target };
        mgr.rotator_move_absolute(&device_id, target)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Halt rotator
pub async fn api_rotator_halt(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // For simulator, just stop moving
        let mut rotator = get_sim_rotator().write().await;
        rotator.status.moving = false;
        rotator.status.is_moving = false;
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.rotator_halt(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Sync rotator's reported sky angle to the supplied position angle without
/// moving the hardware. Used by the "Sync to image PA" workflow after a plate
/// solve: the solver returns the astrometric PA of the captured frame and
/// this call aligns the rotator's reported PA so subsequent absolute moves
/// land at the correct sky angle.
pub async fn api_rotator_sync_to_pa(
    device_id: String,
    pa: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // Simulator has no mechanical offset — just snap the reported angle.
        let mut rotator = get_sim_rotator().write().await;
        rotator.status.position = pa;
        rotator.status.mechanical_position = pa;
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.rotator_sync(&device_id, pa)
            .await
            .map_err(NightshadeError::OperationFailed)
    }
}