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
// REAL PHD2 GUIDING INTEGRATION
// =============================================================================

/// PHD2 connection state
#[derive(Debug, Clone)]
pub struct Phd2Status {
    pub connected: bool,
    pub state: String, // "Disconnected", "Connected", "Calibrating", "Guiding", "Looping", "Paused"
    pub rms_ra: f64,
    pub rms_dec: f64,
    pub rms_total: f64,
    pub snr: f64,
    pub star_mass: f64,
    pub pixel_scale: f64,
}

/// PHD2 calibration data
#[derive(Debug, Clone)]
pub struct Phd2CalibrationData {
    /// Whether the mount is calibrated
    pub is_calibrated: bool,
    /// RA axis rotation angle (degrees)
    pub ra_angle: Option<f64>,
    /// Dec axis rotation angle (degrees)
    pub dec_angle: Option<f64>,
    /// RA guide rate (pixels/second)
    pub ra_rate: Option<f64>,
    /// Dec guide rate (pixels/second)
    pub dec_rate: Option<f64>,
}

/// PHD2 star image data
#[derive(Debug, Clone)]
pub struct Phd2StarImage {
    /// Frame number
    pub frame: u32,
    /// Image width in pixels
    pub width: u32,
    /// Image height in pixels
    pub height: u32,
    /// Star centroid X position
    pub star_x: f64,
    /// Star centroid Y position
    pub star_y: f64,
    /// Raw pixel data (16-bit grayscale as bytes)
    pub pixels: Vec<u8>,
}

/// PHD2 Brain algorithm parameter
#[derive(Debug, Clone)]
pub struct Phd2AlgoParam {
    /// Parameter name
    pub name: String,
    /// Parameter value
    pub value: f64,
}

/// Check if PHD2 is running
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_phd2_running() -> bool {
    nightshade_imaging::is_phd2_running()
}

/// Static PHD2 client storage
pub(crate) static PHD2_CLIENT: OnceLock<Arc<RwLock<Option<nightshade_imaging::Phd2Client>>>> =
    OnceLock::new();

#[flutter_rust_bridge::frb(ignore)]
pub fn get_phd2_storage() -> &'static Arc<RwLock<Option<nightshade_imaging::Phd2Client>>> {
    PHD2_CLIENT.get_or_init(|| Arc::new(RwLock::new(None)))
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn get_active_guider_id_for_ops() -> Option<String> {
    if let Some(profile_guider) = get_state().get_profile_device_id(DeviceType::Guider).await {
        return Some(profile_guider);
    }
    if get_state()
        .is_device_connected(DeviceType::Guider, crate::builtin_guider::device_id())
        .await
    {
        return Some(crate::builtin_guider::device_id().to_string());
    }
    if get_state()
        .is_device_connected(DeviceType::Guider, "phd2_guider")
        .await
    {
        return Some("phd2_guider".to_string());
    }
    get_state()
        .get_devices(DeviceType::Guider)
        .await
        .into_iter()
        .map(|device| device.id)
        .next()
}

/// Connect to PHD2
pub async fn api_phd2_connect(
    host: Option<String>,
    port: Option<u16>,
) -> Result<(), NightshadeError> {
    // Why (audit-rust §4.3): localhost + PHD2 default port 4400 are the
    // documented PHD2 defaults from the PHD2 EventMonitoring wiki and the
    // Nightshade PHD2-settings UI placeholder values.
    let host = host.unwrap_or_else(|| "127.0.0.1".to_string());
    let port = port.unwrap_or(4400);

    tracing::info!("Connecting to PHD2 at {}:{}", host, port);

    let mut client = nightshade_imaging::Phd2Client::new(&host, port);

    // Set up event callback to forward PHD2 events to the main event stream.
    // This callback runs on the PHD2 reader std::thread, NOT on the tokio runtime.
    // It publishes to the broadcast channel which is picked up by api_event_stream.
    client.set_event_callback(move |event| {
        let subscriber_count = get_state().event_bus.subscriber_count();
        tracing::info!(
            "PHD2 event callback received: {:?} (event bus subscribers: {})",
            std::mem::discriminant(&event),
            subscriber_count
        );

        let guiding_event = match event {
            nightshade_imaging::Phd2Event::GuideStep(ref frame) => {
                tracing::info!(
                    "PHD2 GuideStep: RA={:.3}, Dec={:.3}, SNR={:.1}",
                    frame.ra_distance,
                    frame.dec_distance,
                    frame.snr
                );
                // Forward guide step correction data
                let event_id = get_state().publish_guiding_event(
                    GuidingEvent::Correction {
                        ra: frame.ra_distance,
                        dec: frame.dec_distance,
                        ra_raw: frame.ra_distance,
                        dec_raw: frame.dec_distance,
                    },
                    EventSeverity::Info,
                );
                tracing::info!("PHD2: Published Correction event (id={})", event_id);
                // Also forward guide stats (SNR and star mass)
                let stats_id = get_state().publish_guiding_event(
                    GuidingEvent::GuideStats {
                        snr: frame.snr,
                        star_mass: frame.star_mass,
                    },
                    EventSeverity::Info,
                );
                tracing::info!("PHD2: Published GuideStats event (id={})", stats_id);
                return;
            }
            nightshade_imaging::Phd2Event::StateChanged(state) => {
                tracing::info!("PHD2 state changed: {:?}", state);
                match state {
                    nightshade_imaging::Phd2State::Guiding => GuidingEvent::GuidingStarted,
                    nightshade_imaging::Phd2State::Connected => GuidingEvent::GuidingStopped,
                    nightshade_imaging::Phd2State::Disconnected => GuidingEvent::Disconnected,
                    nightshade_imaging::Phd2State::Paused => GuidingEvent::Paused,
                    nightshade_imaging::Phd2State::LostLock => GuidingEvent::LostStar,
                    nightshade_imaging::Phd2State::Looping => GuidingEvent::Looping,
                    nightshade_imaging::Phd2State::Calibrating => GuidingEvent::Calibrating,
                    nightshade_imaging::Phd2State::Settling => GuidingEvent::Settling,
                    // Why: PHD2 occasionally introduces new app-states; we
                    // forward the raw name as a generic `Disconnected` event
                    // (the safest superset for sequencer logic) but the
                    // warning is already emitted upstream in
                    // `parse_phd2_app_state`. Surfacing the literal string in
                    // the GuidingEvent stream would require extending the
                    // FFI enum, which is out of scope here.
                    nightshade_imaging::Phd2State::Unknown(raw) => {
                        tracing::warn!(
                            "PHD2: unrecognised state {:?} bubbled into bridge — \
                             treating as Disconnected for guiding-event mapping",
                            raw
                        );
                        GuidingEvent::Disconnected
                    }
                }
            }
            nightshade_imaging::Phd2Event::StarLost => GuidingEvent::LostStar,
            nightshade_imaging::Phd2Event::StarSelected { x, y } => {
                GuidingEvent::StarSelected { x, y }
            }
            nightshade_imaging::Phd2Event::SettleBegin => GuidingEvent::Settling,
            nightshade_imaging::Phd2Event::SettleDone {
                total_frames: _,
                dropped_frames: _,
            } => GuidingEvent::Settled { rms: 0.0 },
            nightshade_imaging::Phd2Event::CalibrationComplete => {
                tracing::info!("PHD2: Calibration complete");
                GuidingEvent::CalibrationComplete
            }
            nightshade_imaging::Phd2Event::Disconnected => GuidingEvent::Disconnected,
            nightshade_imaging::Phd2Event::Alert {
                message,
                alert_type,
            } => {
                tracing::warn!("PHD2 Alert [{}]: {}", alert_type, message);
                return; // Alerts are not forwarded as GuidingEvent
            }
            nightshade_imaging::Phd2Event::Error(msg) => {
                tracing::error!("PHD2 Error: {}", msg);
                return; // Errors are not forwarded as GuidingEvent
            }
        };

        let severity = match &guiding_event {
            GuidingEvent::LostStar | GuidingEvent::Disconnected => EventSeverity::Warning,
            _ => EventSeverity::Info,
        };

        let event_id = get_state().publish_guiding_event(guiding_event.clone(), severity);
        tracing::info!(
            "PHD2: Published {:?} to event bus (event_id={}, subscribers={})",
            guiding_event,
            event_id,
            subscriber_count
        );
    });

    client
        .connect()
        .map_err(|e| NightshadeError::connection_failed("phd2_guider", format!("PHD2: {}", e)))?;

    // Store the client
    let mut storage = get_phd2_storage().write().await;
    *storage = Some(client);

    // Register PHD2 as a connected guider device in AppState
    // This ensures api_get_connected_devices() returns the guider
    let phd2_device_info = DeviceInfo {
        id: "phd2_guider".to_string(),
        name: "PHD2".to_string(),
        device_type: DeviceType::Guider,
        driver_type: DriverType::Native,
        description: format!("PHD2 Guiding at {}:{}", host, port),
        driver_version: String::new(),
        serial_number: None,
        unique_id: None,
        display_name: "PHD2 Guiding".to_string(),
    };
    get_state()
        .register_device(phd2_device_info, ConnectionState::Connected)
        .await;

    // Publish event
    get_state().publish_guiding_event(GuidingEvent::Connected, EventSeverity::Info);

    Ok(())
}

/// Disconnect from PHD2
pub async fn api_phd2_disconnect() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    if let Some(mut client) = storage.take() {
        client.disconnect();
    }

    // Remove PHD2 from connected devices in AppState
    get_state()
        .remove_device(DeviceType::Guider, "phd2_guider")
        .await;

    get_state().publish_guiding_event(GuidingEvent::Disconnected, EventSeverity::Info);

    Ok(())
}

/// Start guiding in PHD2
pub async fn api_phd2_start_guiding(
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .guide(settle_pixels, settle_time, settle_timeout)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to start guiding: {}", e)))?;

    get_state().publish_guiding_event(GuidingEvent::GuidingStarted, EventSeverity::Info);

    Ok(())
}

/// Stop guiding in PHD2
pub async fn api_phd2_stop_guiding() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .stop_capture()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to stop guiding: {}", e)))?;

    get_state().publish_guiding_event(GuidingEvent::GuidingStopped, EventSeverity::Info);

    Ok(())
}

/// Dither in PHD2
pub async fn api_phd2_dither(
    amount: f64,
    ra_only: u8,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let ra_only_bool = ra_only != 0;
    client
        .dither(
            amount,
            ra_only_bool,
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to dither: {}", e)))?;

    get_state().publish_guiding_event(
        GuidingEvent::DitherStarted { pixels: amount },
        EventSeverity::Info,
    );

    Ok(())
}

/// Get PHD2 status
pub async fn api_phd2_get_status() -> Result<Phd2Status, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let state = client.get_app_state().map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get PHD2 state: {}", e))
    })?;

    // Why (audit-rust §4.3): pixel scale is reported only after PHD2 has
    // selected a star and run a calibration; before that, the RPC errors.
    // 0.0 communicates "not yet calibrated" to the UI guiding panel, which
    // hides the arc-sec/pixel readout when the value is non-positive.
    let pixel_scale = client.get_pixel_scale().unwrap_or(0.0);

    // Why: forward the raw PHD2 state name when unrecognised so the desktop
    // UI can render "PHD2 says: GuidingPaused" instead of pretending
    // everything is fine. Known variants stay as &'static str literals;
    // Unknown owns its String, so we convert to String at the join point.
    let state_str: String = match state {
        nightshade_imaging::Phd2State::Disconnected => "Disconnected".to_string(),
        nightshade_imaging::Phd2State::Connected => "Connected".to_string(),
        nightshade_imaging::Phd2State::Calibrating => "Calibrating".to_string(),
        nightshade_imaging::Phd2State::Guiding => "Guiding".to_string(),
        nightshade_imaging::Phd2State::Looping => "Looping".to_string(),
        nightshade_imaging::Phd2State::Paused => "Paused".to_string(),
        nightshade_imaging::Phd2State::Settling => "Settling".to_string(),
        nightshade_imaging::Phd2State::LostLock => "LostLock".to_string(),
        nightshade_imaging::Phd2State::Unknown(raw) => raw,
    };

    Ok(Phd2Status {
        connected: true,
        state: state_str,
        rms_ra: 0.0, // Would need to track from events
        rms_dec: 0.0,
        rms_total: 0.0,
        snr: 0.0,
        star_mass: 0.0,
        pixel_scale,
    })
}

/// Get PHD2 star image with metadata
pub async fn api_phd2_get_star_image(size: u32) -> Result<Phd2StarImage, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let image_data = client.get_star_image_data(size).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get star image: {}", e))
    })?;

    Ok(Phd2StarImage {
        frame: image_data.frame,
        width: image_data.width,
        height: image_data.height,
        star_x: image_data.star_x,
        star_y: image_data.star_y,
        pixels: image_data.pixels,
    })
}

/// Get PHD2 algorithm parameter names for an axis
pub async fn api_phd2_get_algo_param_names(axis: String) -> Result<Vec<String>, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.get_algo_param_names(&axis).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get algo param names: {}", e))
    })
}

/// Get PHD2 algorithm parameter value
pub async fn api_phd2_get_algo_param(axis: String, name: String) -> Result<f64, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_algo_param(&axis, &name)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get algo param: {}", e)))
}

/// Set PHD2 algorithm parameter value
pub async fn api_phd2_set_algo_param(
    axis: String,
    name: String,
    value: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_algo_param(&axis, &name, value)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set algo param: {}", e)))
}

/// Get all PHD2 algorithm parameters for an axis
pub async fn api_phd2_get_all_algo_params(
    axis: String,
) -> Result<Vec<Phd2AlgoParam>, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let params = client.get_all_algo_params(&axis).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get all algo params: {}", e))
    })?;

    Ok(params
        .into_iter()
        .map(|p| Phd2AlgoParam {
            name: p.name,
            value: p.value,
        })
        .collect())
}

/// Pause or resume PHD2 guiding
pub async fn api_phd2_set_paused(paused: bool) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_paused(paused)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set paused: {}", e)))?;

    get_state().publish_guiding_event(
        if paused {
            GuidingEvent::Paused
        } else {
            GuidingEvent::Resumed
        },
        EventSeverity::Info,
    );

    Ok(())
}

/// Clear PHD2 calibration
pub async fn api_phd2_clear_calibration(which: String) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.clear_calibration(&which).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to clear calibration: {}", e))
    })
}

/// Flip PHD2 calibration (after meridian flip)
pub async fn api_phd2_flip_calibration() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .flip_calibration()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to flip calibration: {}", e)))
}

/// Get PHD2 calibration data
/// Returns calibration info including whether calibrated and calibration parameters
pub async fn api_phd2_get_calibration_data() -> Result<Phd2CalibrationData, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    // Get calibration data for both axes - "both" returns combined info
    let result = client.get_calibration_data("both").map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get calibration data: {}", e))
    })?;

    // PHD2 returns null if not calibrated, otherwise returns calibration parameters
    let is_calibrated = !result.is_null();

    // Extract calibration parameters if available
    let (ra_angle, dec_angle, ra_rate, dec_rate) = if is_calibrated {
        let xangle = result.get("xAngle").and_then(|v| v.as_f64());
        let yangle = result.get("yAngle").and_then(|v| v.as_f64());
        let xrate = result.get("xRate").and_then(|v| v.as_f64());
        let yrate = result.get("yRate").and_then(|v| v.as_f64());
        (xangle, yangle, xrate, yrate)
    } else {
        (None, None, None, None)
    };

    Ok(Phd2CalibrationData {
        is_calibrated,
        ra_angle,
        dec_angle,
        ra_rate,
        dec_rate,
    })
}

/// Find a guide star automatically
pub async fn api_phd2_find_star() -> Result<(f64, f64), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .find_star()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to find star: {}", e)))
}

/// Set guide star lock position
pub async fn api_phd2_set_lock_position(
    x: f64,
    y: f64,
    exact: bool,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.set_lock_position(x, y, exact).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to set lock position: {}", e))
    })
}

/// Get current guide star lock position
pub async fn api_phd2_get_lock_position() -> Result<(f64, f64), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.get_lock_position().map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get lock position: {}", e))
    })
}

/// Start looping exposures (without guiding)
pub async fn api_phd2_loop() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .loop_exposures()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to start looping: {}", e)))
}

/// Deselect the current guide star
pub async fn api_phd2_deselect_star() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .deselect_star()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to deselect star: {}", e)))
}

/// Get PHD2 guide exposure time (ms)
pub async fn api_phd2_get_exposure() -> Result<u32, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_exposure()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get exposure: {}", e)))
}

/// Set PHD2 guide exposure time (ms)
pub async fn api_phd2_set_exposure(exposure_ms: u32) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_exposure(exposure_ms)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set exposure: {}", e)))
}

/// Get current PHD2 profile name
pub async fn api_phd2_get_profile() -> Result<String, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_profile()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get profile: {}", e)))
}

/// Launch PHD2 application
pub fn api_launch_phd2() -> Result<(), NightshadeError> {
    nightshade_imaging::launch_phd2()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to launch PHD2: {}", e)))
}

pub async fn api_guider_start_guiding(
    device_id: String,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_start_guiding(settle_pixels, settle_time, settle_timeout).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::start_guiding(settle_pixels, settle_time, settle_timeout)
            .await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_stop(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_stop_guiding().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::stop().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_dither(
    device_id: String,
    amount: f64,
    ra_only: u8,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_dither(amount, ra_only, settle_pixels, settle_time, settle_timeout).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::dither(
            amount,
            ra_only != 0,
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_loop(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_loop().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::loop_exposures().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_find_star(device_id: String) -> Result<(f64, f64), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_find_star().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::find_star().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_set_lock_position(
    device_id: String,
    x: f64,
    y: f64,
    exact: bool,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_set_lock_position(x, y, exact).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::set_lock_position(x, y).await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_lock_position(
    device_id: String,
) -> Result<(f64, f64), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_lock_position().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_lock_position().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_deselect_star(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_deselect_star().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::deselect_star().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_star_image(
    device_id: String,
    size: u32,
) -> Result<Phd2StarImage, NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_star_image(size).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_star_image(size).await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_status(device_id: String) -> Result<Phd2Status, NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_status().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_status().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

// =============================================================================
// BUILT-IN GUIDER CONFIGURATION
// =============================================================================

/// Get the current built-in guider configuration.
/// Returns a flat struct with all configurable parameters.
pub async fn api_builtin_guider_get_config() -> Result<BuiltinGuiderConfig, NightshadeError> {
    let config = crate::builtin_guider::get_config().await;
    Ok(BuiltinGuiderConfig {
        exposure_secs: config.exposure_secs,
        gain: config.gain,
        offset: config.offset,
        binning: config.binning,
        calibration_ms: config.calibration_ms,
        settle_sleep_ms: config.settle_sleep_ms,
        min_pulse_ms: config.min_pulse_ms,
        max_pulse_ms: config.max_pulse_ms,
    })
}

/// Set the built-in guider configuration.
/// Can be called while guiding is active; changes apply to subsequent frames.
pub async fn api_builtin_guider_set_config(
    exposure_secs: f64,
    gain: i32,
    offset: i32,
    binning: i32,
    calibration_ms: u32,
    settle_sleep_ms: u64,
    min_pulse_ms: f64,
    max_pulse_ms: f64,
) -> Result<(), NightshadeError> {
    let config = crate::builtin_guider::GuiderConfig {
        exposure_secs,
        gain,
        offset,
        binning,
        calibration_ms,
        settle_sleep_ms,
        min_pulse_ms,
        max_pulse_ms,
    };
    crate::builtin_guider::set_config(config).await;
    Ok(())
}

/// FRB-friendly struct for the built-in guider configuration.
#[derive(Clone, Debug)]
pub struct BuiltinGuiderConfig {
    pub exposure_secs: f64,
    pub gain: i32,
    pub offset: i32,
    pub binning: i32,
    pub calibration_ms: u32,
    pub settle_sleep_ms: u64,
    pub min_pulse_ms: f64,
    pub max_pulse_ms: f64,
}
