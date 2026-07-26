// split from monolithic api.rs
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs.
//
// # `as`-cast policy
//
// Numeric casts in this file are simulator-only device wrappers:
// - **i32 duration_ms → u64 sleep / u32 pulse** (lines 441, 448):
//   simulator-side wrappers; durations are user-supplied milliseconds
//   capped by the same UI as real hardware (typically ≤ ~2000 ms for
//   guide pulses). `as u64` widens; `as u32` is bounded by UI clamp.
// - **i32 step distance → f64 move time** (lines 551, 593): exact widening.
// - **i32 ↔ i32 filter wheel pos** (lines 786, 804): no-op widenings
//   around `Option::map` plumbing.
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
use crate::adaptive_polling::ConsecutiveFailureBackoff;
use std::sync::Mutex as StdMutex;

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

/// Duration of the most recently started simulated exposure, in seconds.
///
/// The simulator does not integrate for real, but the download path still has
/// to report an `ImageMetadata::exposure_time`, and that value becomes the saved
/// frame's `EXPTIME` — the one FITS keyword calibration and stacking tools trust
/// most. It was a hardcoded `1.0`, so every simulated frame claimed a 1-second
/// exposure regardless of what the sequence asked for.
///
/// Kept out of [`SimulatedCamera`] on purpose: that struct is mirrored to Dart
/// by flutter_rust_bridge, and Dart has no use for this.
static SIM_LAST_EXPOSURE_SECS: OnceLock<Arc<RwLock<f64>>> = OnceLock::new();

pub(crate) fn get_sim_last_exposure_secs() -> &'static Arc<RwLock<f64>> {
    SIM_LAST_EXPOSURE_SECS.get_or_init(|| Arc::new(RwLock::new(1.0)))
}

/// Wall-clock start of the in-flight simulated exposure, or `None` when idle.
///
/// The simulator used to report every exposure complete the instant it was
/// asked, which is not a harmless shortcut:
///   * nothing paced the built-in guider's capture loop, so guiding against the
///     simulator ran at ~40 frames/sec and pinned nine CPU cores (897%) running
///     star detection on 1920x1080 frames — with the guide exposure set to 1s;
///   * a 60-second simulated light frame finished in zero seconds, so exposure
///     progress, remaining-time estimates and any "still integrating" UI state
///     could not be exercised without hardware, and a bug in them would ship
///     unseen.
/// Real cameras pace their callers by simply not being finished yet; the
/// simulator has to do the same to be worth testing against.
static SIM_EXPOSURE_START: OnceLock<Arc<RwLock<Option<std::time::Instant>>>> = OnceLock::new();

fn sim_exposure_start() -> &'static Arc<RwLock<Option<std::time::Instant>>> {
    SIM_EXPOSURE_START.get_or_init(|| Arc::new(RwLock::new(None)))
}

/// Record the start of a simulated exposure of `secs`.
pub(crate) async fn begin_sim_exposure(secs: f64) {
    *get_sim_last_exposure_secs().write().await = secs;
    *sim_exposure_start().write().await = Some(std::time::Instant::now());
}

/// Forget any in-flight simulated exposure (abort, or download consumed it).
pub(crate) async fn clear_sim_exposure() {
    *sim_exposure_start().write().await = None;
}

/// Whether the in-flight simulated exposure has finished integrating.
///
/// Idle (no exposure started) reads as complete: a caller polling without having
/// started anything should not be made to wait forever.
pub(crate) async fn sim_exposure_is_complete() -> bool {
    let started = *sim_exposure_start().read().await;
    match started {
        None => true,
        Some(start) => {
            let requested = *get_sim_last_exposure_secs().read().await;
            sim_exposure_elapsed_is_complete(start.elapsed().as_secs_f64(), requested)
        }
    }
}

/// Completion predicate, split out so the boundary is testable without a clock.
///
/// A non-finite or non-positive request completes immediately rather than
/// hanging: a 0-second bias frame is a legitimate request, and a NaN duration is
/// a caller bug that must not wedge the capture loop.
fn sim_exposure_elapsed_is_complete(elapsed_secs: f64, requested_secs: f64) -> bool {
    if !requested_secs.is_finite() || requested_secs <= 0.0 {
        return true;
    }
    elapsed_secs >= requested_secs
}

/// Ambient temperature the simulated sensor drifts back to with the cooler off.
const SIM_AMBIENT_TEMP_C: f64 = 20.0;
/// Cooling slew rate, °C per second.
///
/// Deliberately far brisker than real hardware (a good TEC manages roughly a
/// degree a second): the point is that cooling COMPLETES within a sequence
/// node's normal budget so `CoolCamera` / `WarmCamera`, the cooling UI and the
/// "wait for setpoint" paths are all exercisable without a camera attached.
/// It still ramps rather than snapping, so intermediate states are observable.
const SIM_COOL_RATE_C_PER_SEC: f64 = 8.0;
/// Passive warm-up is slower than active cooling, as on real hardware.
const SIM_WARM_RATE_C_PER_SEC: f64 = 3.0;

static SIM_COOLER_LAST_TICK: OnceLock<Arc<RwLock<Option<std::time::Instant>>>> = OnceLock::new();

fn sim_cooler_last_tick() -> &'static Arc<RwLock<Option<std::time::Instant>>> {
    SIM_COOLER_LAST_TICK.get_or_init(|| Arc::new(RwLock::new(None)))
}

/// Advance the simulated sensor temperature toward its setpoint.
///
/// The singleton used to accept `set_cooler(enabled, target)` and then report
/// 20.0 °C at 0% power forever, so a `CoolCamera` node could NEVER succeed
/// against the simulator — every realistic sequence died on its first node with
/// "Camera did not reach target -5.0°C within 6s (last 20.0°C, 0% power)", and
/// the dashboard's Sensor/Cooler readouts were frozen. Called on every simulated
/// status read, which is what makes the ramp observable.
pub(crate) async fn advance_sim_cooler() {
    let now = std::time::Instant::now();
    let elapsed = {
        let mut last = sim_cooler_last_tick().write().await;
        let elapsed = last.map(|t| now.duration_since(t).as_secs_f64());
        *last = Some(now);
        // First read after launch establishes the baseline instead of jumping.
        match elapsed {
            Some(secs) if secs.is_finite() && secs > 0.0 => secs,
            _ => return,
        }
    };

    let mut guard = get_sim_camera().write().await;
    let current = guard.status.sensor_temp.unwrap_or(SIM_AMBIENT_TEMP_C);
    let (target, rate) = if guard.status.cooler_on {
        (
            guard.status.target_temp.unwrap_or(SIM_AMBIENT_TEMP_C),
            SIM_COOL_RATE_C_PER_SEC,
        )
    } else {
        (SIM_AMBIENT_TEMP_C, SIM_WARM_RATE_C_PER_SEC)
    };

    let delta = target - current;
    let step = rate * elapsed;
    let next = if delta.abs() <= step {
        target
    } else {
        current + step * delta.signum()
    };
    guard.status.sensor_temp = Some(next);
    guard.status.cooler_power = Some(if !guard.status.cooler_on {
        0.0
    } else if (target - next).abs() > 0.5 {
        // Pulling down to the setpoint.
        85.0
    } else {
        // Holding at the setpoint.
        35.0
    });
}

// =============================================================================
// Simulated mount motion (guide pulses + tracking drift)
// =============================================================================

/// Sensor displacement, in pixels, produced by one second of guide pulse.
///
/// Derived rather than invented: a 0.5x-sidereal guide rate moves the sky at
/// 7.5 arcsec/sec, and the simulated guide train is taken to be ~1.25 arcsec per
/// pixel, giving 6 px/sec. At the built-in guider's default 250 ms calibration
/// pulse that is 1.5 px per pulse — comfortably above the routine's 0.2 px
/// "response too small" floor and far inside its 20 px star-match radius, so
/// calibration converges without the field jumping star-to-star.
const SIM_GUIDE_PX_PER_SEC: f64 = 6.0;

/// Uncorrected tracking drift, in pixels per second, on each sensor axis.
///
/// A perfectly still simulated sky would let a guider with an inverted
/// correction sign report a flawless 0.00 px RMS forever, because there would be
/// nothing for a correction to make worse. Giving the mount a slow, honest drift
/// means closed-loop guiding has to actually null it out, so the sign and
/// magnitude of the correction path are exercised end to end. Sized to be a
/// fraction of a pixel per guide cycle: a real guider absorbs this easily, and
/// an unguided sequence shows the gentle field walk you would expect.
const SIM_DRIFT_PX_PER_SEC_X: f64 = 0.05;
const SIM_DRIFT_PX_PER_SEC_Y: f64 = 0.02;

/// Ceiling on accumulated offset magnitude, per axis, in pixels.
///
/// Unbounded drift would eventually walk the whole field off the sensor and
/// leave the simulator producing starless frames after a long idle — a confusing
/// failure that looks like a detector bug. 60 px keeps the field recognisable
/// while still being a visible, correctable excursion.
const SIM_MAX_OFFSET_PX: f64 = 60.0;

/// Longest drift step applied in one advance, in seconds.
///
/// The app can sit idle for hours between simulated captures. Integrating that
/// whole gap at once would slam the offset into its clamp on the very first
/// frame; capping the step keeps the first capture after an idle period looking
/// like the last one.
const SIM_MAX_DRIFT_STEP_SECS: f64 = 5.0;

/// Accumulated sensor-plane offset of the simulated star field, in pixels.
///
/// Primitives in a lock rather than a field on [`SimulatedMount`] on purpose:
/// that struct is mirrored to Dart by flutter_rust_bridge and Dart has no use
/// for this.
static SIM_GUIDE_OFFSET: OnceLock<Arc<RwLock<(f64, f64)>>> = OnceLock::new();
static SIM_DRIFT_LAST_TICK: OnceLock<Arc<RwLock<Option<std::time::Instant>>>> = OnceLock::new();

fn sim_guide_offset() -> &'static Arc<RwLock<(f64, f64)>> {
    SIM_GUIDE_OFFSET.get_or_init(|| Arc::new(RwLock::new((0.0, 0.0))))
}

fn sim_drift_last_tick() -> &'static Arc<RwLock<Option<std::time::Instant>>> {
    SIM_DRIFT_LAST_TICK.get_or_init(|| Arc::new(RwLock::new(None)))
}

/// Pixel delta produced by pulsing `direction` for `duration_ms`.
///
/// East/west move the field along +x/-x and north/south along +y/-y. The axes are
/// deliberately orthogonal and axis-aligned: the guider derives its own rotation
/// matrix from the responses it measures, so a clean basis lets a calibration
/// failure be read as a guider bug rather than an artefact of a contrived
/// simulated camera angle.
fn sim_pulse_delta(direction: &str, duration_ms: u32) -> (f64, f64) {
    let travel = SIM_GUIDE_PX_PER_SEC * (duration_ms as f64) / 1000.0;
    match direction.to_lowercase().as_str() {
        "east" | "e" => (travel, 0.0),
        "west" | "w" => (-travel, 0.0),
        "north" | "n" => (0.0, travel),
        "south" | "s" => (0.0, -travel),
        _ => (0.0, 0.0),
    }
}

/// Accumulate a displacement onto the current offset, clamped to the sensor
/// excursion limit. Pure so the clamp behaviour is testable without the
/// process-global offset.
fn apply_offset_delta(current: (f64, f64), dx: f64, dy: f64) -> (f64, f64) {
    (
        (current.0 + dx).clamp(-SIM_MAX_OFFSET_PX, SIM_MAX_OFFSET_PX),
        (current.1 + dy).clamp(-SIM_MAX_OFFSET_PX, SIM_MAX_OFFSET_PX),
    )
}

/// Seconds of drift to integrate, given the gap since the last advance.
///
/// `None` (first read after launch) and non-positive/non-finite gaps contribute
/// nothing, so the baseline is established rather than jumped.
fn drift_step_secs(elapsed: Option<f64>) -> f64 {
    match elapsed {
        Some(secs) if secs.is_finite() && secs > 0.0 => secs.min(SIM_MAX_DRIFT_STEP_SECS),
        _ => 0.0,
    }
}

/// Apply a guide pulse to the simulated mount.
pub(crate) async fn advance_sim_guide_pulse(direction: &str, duration_ms: u32) {
    let (dx, dy) = sim_pulse_delta(direction, duration_ms);
    if dx == 0.0 && dy == 0.0 {
        return;
    }
    let mut guard = sim_guide_offset().write().await;
    *guard = apply_offset_delta(*guard, dx, dy);
}

/// Current star-field offset, after advancing tracking drift to now.
///
/// Called from the simulated download path, which is what makes the drift
/// observable frame to frame.
pub(crate) async fn sim_guide_offset_px() -> (f64, f64) {
    let now = std::time::Instant::now();
    let elapsed = {
        let mut last = sim_drift_last_tick().write().await;
        let gap = last.map(|t| now.duration_since(t).as_secs_f64());
        *last = Some(now);
        drift_step_secs(gap)
    };

    let mut guard = sim_guide_offset().write().await;
    if elapsed > 0.0 {
        *guard = apply_offset_delta(
            *guard,
            SIM_DRIFT_PX_PER_SEC_X * elapsed,
            SIM_DRIFT_PX_PER_SEC_Y * elapsed,
        );
    }
    *guard
}

/// Re-centre the simulated star field.
///
/// A slew or park repoints the scope entirely, so carrying the previous target's
/// accumulated drift across would be wrong — and would leave a long session's
/// offset pinned at its clamp with no way back.
pub(crate) async fn reset_sim_guide_offset() {
    *sim_guide_offset().write().await = (0.0, 0.0);
    *sim_drift_last_tick().write().await = None;
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
        .map_err(NightshadeError::from)
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
        .map_err(NightshadeError::from)
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
        .map_err(NightshadeError::from)
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
        .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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

    // For the simulator, take the duration AND move the star field.
    //
    // This arm used to only sleep. That made it a second, silently divergent
    // implementation of simulated pulse guiding: the DeviceManager's Simulator
    // arm is what the built-in guider drives, but every caller that goes through
    // the api layer (the HTTP `/api/mount/pulse-guide` route, and so the manual
    // guide-nudge UI) short-circuits here instead — so a nudge reported "ok",
    // waited, and moved nothing.
    if device_id.starts_with("sim_") {
        tokio::time::sleep(std::time::Duration::from_millis(duration_ms as u64)).await;
        advance_sim_guide_pulse(&direction, duration_ms.max(0) as u32).await;
        tracing::info!("Pulse guide complete");
        return Ok(());
    }

    // Route real devices through DeviceManager
    let mgr = get_device_manager();
    mgr.mount_pulse_guide(&device_id, direction, duration_ms as u32)
        .await
        .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)?;
        let moving = mgr
            .focuser_is_moving(&device_id)
            .await
            .map_err(NightshadeError::from)?;
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
            .map_err(NightshadeError::from)?;

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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
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

const FILTER_WHEEL_POSITION_FAILURE_THRESHOLD: u32 = 3;
const FILTER_WHEEL_POSITION_BACKOFF_BASE: Duration = Duration::from_secs(10);
const FILTER_WHEEL_POSITION_BACKOFF_MAX: Duration = Duration::from_secs(120);

#[derive(Debug)]
#[flutter_rust_bridge::frb(ignore)]
struct FilterWheelStatusPollState {
    position_backoff: ConsecutiveFailureBackoff,
    last_position: Option<i32>,
}

impl Default for FilterWheelStatusPollState {
    fn default() -> Self {
        Self {
            position_backoff: ConsecutiveFailureBackoff::new(
                FILTER_WHEEL_POSITION_FAILURE_THRESHOLD,
                FILTER_WHEEL_POSITION_BACKOFF_BASE,
                FILTER_WHEEL_POSITION_BACKOFF_MAX,
                2.0,
            ),
            last_position: None,
        }
    }
}

static FILTER_WHEEL_STATUS_POLL_STATES: OnceLock<
    StdMutex<HashMap<String, FilterWheelStatusPollState>>,
> = OnceLock::new();

fn filter_wheel_status_poll_states(
) -> &'static StdMutex<HashMap<String, FilterWheelStatusPollState>> {
    FILTER_WHEEL_STATUS_POLL_STATES.get_or_init(|| StdMutex::new(HashMap::new()))
}

/// Poll Position without hammering a driver that has demonstrated a sustained
/// failure. The first two consecutive errors propagate so real one-off failures
/// remain visible. From the third failure onward, status polling serves the
/// last good value (or the unknown sentinel) and retries with exponential
/// backoff.
async fn poll_filter_wheel_position(
    manager: &DeviceManager,
    device_id: &str,
) -> Result<i32, NightshadeError> {
    let now = Instant::now();
    let backed_off = {
        let mut states = filter_wheel_status_poll_states()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let state = states.entry(device_id.to_string()).or_default();
        if state.position_backoff.should_attempt(now) {
            None
        } else {
            Some((
                state.last_position.unwrap_or(-1),
                state
                    .position_backoff
                    .retry_after(now)
                    .unwrap_or(Duration::ZERO),
            ))
        }
    };

    if let Some((position, retry_after)) = backed_off {
        tracing::trace!(
            "[filter-wheel poll] Position read for {} backed off for another {:?}",
            device_id,
            retry_after
        );
        return Ok(position);
    }

    match manager.filter_wheel_get_position(device_id).await {
        Ok(position) => {
            let recovered_after = {
                let mut states = filter_wheel_status_poll_states()
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                let state = states.entry(device_id.to_string()).or_default();
                let failures = state.position_backoff.consecutive_failures();
                state.position_backoff.record_success();
                state.last_position = Some(position);
                failures
            };
            if recovered_after >= FILTER_WHEEL_POSITION_FAILURE_THRESHOLD {
                tracing::info!(
                    "[filter-wheel poll] Position read for {} recovered after {} failures",
                    device_id,
                    recovered_after
                );
            }
            Ok(position)
        }
        Err(error) => {
            let (failures, delay, fallback) = {
                let mut states = filter_wheel_status_poll_states()
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                let state = states.entry(device_id.to_string()).or_default();
                let delay = state.position_backoff.record_failure(Instant::now());
                (
                    state.position_backoff.consecutive_failures(),
                    delay,
                    state.last_position.unwrap_or(-1),
                )
            };

            if let Some(delay) = delay {
                tracing::warn!(
                    "[filter-wheel poll] Position read for {} failed {} consecutive times; backing off for {:?}: {}",
                    device_id,
                    failures,
                    delay,
                    error
                );
                Ok(fallback)
            } else {
                Err(NightshadeError::from(error))
            }
        }
    }
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
        let position = poll_filter_wheel_position(mgr, &device_id).await?;
        let is_moving = mgr
            .filter_wheel_poll_is_moving(&device_id, position)
            .await
            .map_err(NightshadeError::from)?;
        // debug, not info: this whole status path is polled every few seconds by
        // the dashboard/companions — at INFO it dominated the log volume.
        tracing::debug!(
            "[api_get_filterwheel_status] device={}, raw position from SDK={}",
            device_id,
            position
        );
        let (filter_count, filter_names) = mgr
            .filter_wheel_get_config(&device_id)
            .await
            .map_err(NightshadeError::from)?;

        tracing::debug!(
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
            .map_err(NightshadeError::from);
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
            .map_err(NightshadeError::from)?;
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
            .map_err(NightshadeError::from)?;
        let is_moving = mgr
            .rotator_is_moving(&device_id)
            .await
            .map_err(NightshadeError::from)?;
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
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)?;
        let target = (current + delta) % 360.0;
        let target = if target < 0.0 { target + 360.0 } else { target };
        mgr.rotator_move_absolute(&device_id, target)
            .await
            .map_err(NightshadeError::from)
    }
}

/// Set the rotator's reverse-direction flag (IRotatorV3 `Reverse`, Alpaca
/// `reverse`, INDI `ROTATOR_REVERSE`).
pub async fn api_rotator_set_reverse(
    device_id: String,
    reverse: bool,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let rotator = get_sim_rotator().read().await;
        if !rotator.status.connected {
            return Err(NightshadeError::NotConnected(device_id));
        }
        if rotator.status.can_reverse {
            // The simulator has no directional behavior to invert; accepting
            // keeps sim rigs exercising the same UI path as real hardware.
            tracing::info!("Simulator rotator reverse set to {}", reverse);
            Ok(())
        } else {
            Err(NightshadeError::OperationFailed(
                "Simulator rotator does not support reverse".to_string(),
            ))
        }
    } else {
        let mgr = get_device_manager();
        mgr.rotator_set_reverse(&device_id, reverse)
            .await
            .map_err(NightshadeError::from)
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
            .map_err(NightshadeError::from)
    }
}

/// Sync rotator's reported sky angle to the supplied position angle without
/// moving the hardware. Used by the "Sync to image PA" workflow after a plate
/// solve: the solver returns the astrometric PA of the captured frame and
/// this call aligns the rotator's reported PA so subsequent absolute moves
/// land at the correct sky angle.
pub async fn api_rotator_sync_to_pa(device_id: String, pa: f64) -> Result<(), NightshadeError> {
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
            .map_err(NightshadeError::from)
    }
}

// =============================================================================
// Observatory accessory simulators
// =============================================================================

/// Backing state for the dome simulator advertised by discovery.
pub(crate) static SIM_DOME: OnceLock<Arc<RwLock<SimulatedDome>>> = OnceLock::new();

pub(crate) struct SimulatedDome {
    pub status: DomeStatus,
}

impl Default for SimulatedDome {
    fn default() -> Self {
        Self {
            status: DomeStatus {
                connected: false,
                azimuth: 0.0,
                altitude: None,
                shutter_status: ShutterState::Closed,
                slewing: false,
                at_home: true,
                at_park: true,
                can_set_altitude: false,
                can_set_azimuth: true,
                can_set_shutter: true,
                can_slave: true,
                is_slaved: false,
            },
        }
    }
}

pub(crate) fn get_sim_dome() -> &'static Arc<RwLock<SimulatedDome>> {
    SIM_DOME.get_or_init(|| Arc::new(RwLock::new(SimulatedDome::default())))
}

/// Backing state for the observing-conditions simulator.
pub(crate) static SIM_WEATHER: OnceLock<Arc<RwLock<SimulatedWeather>>> = OnceLock::new();

pub(crate) struct SimulatedWeather {
    pub connected: bool,
    pub conditions: WeatherConditions,
}

impl Default for SimulatedWeather {
    fn default() -> Self {
        Self {
            connected: false,
            conditions: WeatherConditions {
                temperature: Some(10.0),
                humidity: Some(45.0),
                pressure: Some(1013.25),
                cloud_cover: Some(5.0),
                dew_point: Some(-1.5),
                wind_speed: Some(1.0),
                wind_direction: Some(180.0),
                sky_quality: Some(21.5),
                sky_temperature: Some(-18.0),
                rain_rate: Some(0.0),
            },
        }
    }
}

pub(crate) fn get_sim_weather() -> &'static Arc<RwLock<SimulatedWeather>> {
    SIM_WEATHER.get_or_init(|| Arc::new(RwLock::new(SimulatedWeather::default())))
}

/// Backing state for the safety-monitor simulator. It starts safe so routine
/// simulator smoke tests cannot trigger emergency actions accidentally.
pub(crate) static SIM_SAFETY_MONITOR: OnceLock<Arc<RwLock<SimulatedSafetyMonitor>>> =
    OnceLock::new();

pub(crate) struct SimulatedSafetyMonitor {
    pub status: SafetyStatus,
}

impl Default for SimulatedSafetyMonitor {
    fn default() -> Self {
        Self {
            status: SafetyStatus {
                connected: false,
                is_safe: true,
            },
        }
    }
}

pub(crate) fn get_sim_safety_monitor() -> &'static Arc<RwLock<SimulatedSafetyMonitor>> {
    SIM_SAFETY_MONITOR.get_or_init(|| Arc::new(RwLock::new(SimulatedSafetyMonitor::default())))
}

#[cfg(test)]
mod sim_motion_tests {
    use super::*;

    /// The four cardinal directions must map to distinct, opposed, axis-aligned
    /// displacements. If east and north were parallel the guider's calibration
    /// matrix would be singular and it would (correctly) refuse to guide with
    /// "mount pulse responses were not distinct".
    #[test]
    fn pulse_directions_form_an_orthogonal_basis() {
        let east = sim_pulse_delta("east", 250);
        let west = sim_pulse_delta("west", 250);
        let north = sim_pulse_delta("north", 250);
        let south = sim_pulse_delta("south", 250);

        assert!(east.0 > 0.0 && east.1 == 0.0, "east: {east:?}");
        assert_eq!(west, (-east.0, 0.0), "west must oppose east");
        assert!(north.1 > 0.0 && north.0 == 0.0, "north: {north:?}");
        assert_eq!(south, (0.0, -north.1), "south must oppose north");

        let determinant = east.0 * north.1 - east.1 * north.0;
        assert!(
            determinant.abs() > 1e-3,
            "east/north basis is singular (det {determinant}); calibration would be rejected"
        );
    }

    /// Direction parsing has to accept what the device layer actually passes.
    /// `mount_pulse_guide` lowercases before dispatching, and the guider sends
    /// full words; a silent no-match would revert this to the old
    /// "pulse does nothing" bug rather than failing loudly.
    #[test]
    fn pulse_accepts_the_directions_the_guider_sends() {
        for direction in ["north", "south", "east", "west", "n", "s", "e", "w"] {
            let (dx, dy) = sim_pulse_delta(direction, 250);
            assert!(
                dx != 0.0 || dy != 0.0,
                "direction {direction:?} produced no movement"
            );
        }
        assert_eq!(sim_pulse_delta("sideways", 250), (0.0, 0.0));
    }

    /// Travel is proportional to pulse width — that proportionality is what the
    /// guider converts into its px/ms guide rate.
    #[test]
    fn pulse_travel_scales_with_duration() {
        let short = sim_pulse_delta("east", 250).0;
        let long = sim_pulse_delta("east", 1000).0;
        assert!(
            (long - short * 4.0).abs() < 1e-9,
            "{long} should be 4x {short}"
        );
        assert_eq!(sim_pulse_delta("east", 0), (0.0, 0.0));
    }

    /// The default 250 ms calibration pulse must clear the guider's 0.2 px
    /// "response too small" floor with margin, and two of them must stay inside
    /// its 20 px star-match radius.
    #[test]
    fn default_calibration_pulse_lands_in_the_guiders_usable_band() {
        let per_pulse = sim_pulse_delta("east", 250).0;
        assert!(
            per_pulse > 0.2,
            "per-pulse response {per_pulse}px is at or below the 0.2px floor"
        );
        assert!(
            per_pulse * 2.0 < 20.0,
            "two-pulse Dec forward leg {}px exceeds the 20px match radius",
            per_pulse * 2.0
        );
    }

    /// The api-layer `sim_` short-circuit must move the field, not just sleep.
    /// It bypasses the DeviceManager entirely, so it is a separate call site that
    /// silently regressed to a no-op once before — a manual guide nudge returned
    /// "ok", waited the duration, and left the stars where they were.
    #[tokio::test]
    async fn api_pulse_guide_moves_the_simulated_field() {
        reset_sim_guide_offset().await;
        let before = *sim_guide_offset().read().await;
        api_mount_pulse_guide("sim_mount_1".to_string(), "east".to_string(), 1000)
            .await
            .expect("simulated pulse guide should succeed");
        let after = *sim_guide_offset().read().await;
        assert!(
            after.0 - before.0 > 0.2,
            "api-layer east pulse moved the field only {:.4}px",
            after.0 - before.0
        );
        reset_sim_guide_offset().await;
    }

    /// An unknown direction must be rejected rather than silently sleeping.
    #[tokio::test]
    async fn api_pulse_guide_rejects_an_unknown_direction() {
        let result =
            api_mount_pulse_guide("sim_mount_1".to_string(), "widdershins".to_string(), 10).await;
        assert!(result.is_err(), "unknown direction should be an error");
    }

    /// A simulated exposure must not report complete before its integration
    /// time has elapsed. The unconditional "yes" this replaces gave a capture
    /// loop nothing to wait on: guiding ran at ~40 fps and pinned nine cores.
    #[test]
    fn exposure_completes_only_after_its_integration_time() {
        assert!(!sim_exposure_elapsed_is_complete(0.0, 1.0));
        assert!(!sim_exposure_elapsed_is_complete(0.999, 1.0));
        assert!(sim_exposure_elapsed_is_complete(1.0, 1.0));
        assert!(sim_exposure_elapsed_is_complete(2.5, 1.0));
    }

    /// Degenerate durations must complete rather than wedge the capture loop.
    /// A zero-second bias frame is a legitimate request, and a NaN duration is a
    /// caller bug that must not hang capture forever.
    #[test]
    fn degenerate_exposure_durations_complete_immediately() {
        assert!(sim_exposure_elapsed_is_complete(0.0, 0.0));
        assert!(sim_exposure_elapsed_is_complete(0.0, -1.0));
        assert!(sim_exposure_elapsed_is_complete(0.0, f64::NAN));
        assert!(sim_exposure_elapsed_is_complete(0.0, f64::INFINITY));
    }

    /// Idle reads as complete, a started exposure does not, and abort releases
    /// the caller. Anything else strands a polling loop.
    #[tokio::test]
    async fn exposure_clock_starts_and_clears() {
        clear_sim_exposure().await;
        assert!(
            sim_exposure_is_complete().await,
            "an idle simulator must not make a poller wait"
        );

        begin_sim_exposure(30.0).await;
        assert!(
            !sim_exposure_is_complete().await,
            "a 30s exposure must not be complete the instant it starts"
        );

        clear_sim_exposure().await;
        assert!(
            sim_exposure_is_complete().await,
            "abort/download must release a caller waiting on the exposure"
        );
    }

    #[test]
    fn offset_is_clamped_to_the_sensor_excursion_limit() {
        let far = apply_offset_delta((0.0, 0.0), 10_000.0, -10_000.0);
        assert_eq!(far, (SIM_MAX_OFFSET_PX, -SIM_MAX_OFFSET_PX));
        // And a clamped offset must still be able to come back.
        let back = apply_offset_delta(far, -5.0, 5.0);
        assert!(back.0 < SIM_MAX_OFFSET_PX && back.1 > -SIM_MAX_OFFSET_PX);
    }

    #[test]
    fn offset_accumulates_across_pulses() {
        let one = apply_offset_delta((0.0, 0.0), 1.5, 0.0);
        let two = apply_offset_delta(one, 1.5, 0.0);
        assert!((two.0 - 3.0).abs() < 1e-9, "two pulses should sum: {two:?}");
        // Reversing returns to the origin: without this, calibration's
        // "restore toward baseline" reverse pulses would never recentre.
        let back = apply_offset_delta(two, -3.0, 0.0);
        assert!(
            back.0.abs() < 1e-9,
            "reverse pulses should cancel: {back:?}"
        );
    }

    /// A long idle must not slam the field into its clamp on the next capture,
    /// and the first read after launch must not drift at all.
    #[test]
    fn drift_step_is_capped_and_starts_from_a_baseline() {
        assert_eq!(drift_step_secs(None), 0.0);
        assert_eq!(drift_step_secs(Some(0.0)), 0.0);
        assert_eq!(drift_step_secs(Some(-1.0)), 0.0);
        assert_eq!(drift_step_secs(Some(f64::NAN)), 0.0);
        assert_eq!(drift_step_secs(Some(1.5)), 1.5);
        assert_eq!(drift_step_secs(Some(86_400.0)), SIM_MAX_DRIFT_STEP_SECS);
    }

    /// Drift has to be small enough for a guider to absorb within one cycle,
    /// or closed-loop guiding would diverge against the simulator no matter how
    /// correct the correction path is.
    #[test]
    fn drift_is_correctable_within_one_guide_cycle() {
        // A 2s guide exposure plus the default 200ms settle.
        let cycle_secs = 2.2;
        let drift = SIM_DRIFT_PX_PER_SEC_X * cycle_secs;
        let per_pulse = sim_pulse_delta("east", 250).0;
        assert!(
            drift < per_pulse,
            "drift {drift}px per cycle exceeds one calibration pulse of correction \
             ({per_pulse}px); guiding could never catch up"
        );
        assert!(
            drift > 0.0,
            "zero drift leaves the correction sign untested"
        );
    }
}
