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
// - **f64 panel brightness → i32** (`SimulatedCoverCalibrator::brightness`):
//   the simulated panel ramps on a continuous scale but the ASCOM
//   `Brightness` property is an integer, so the reported value is rounded
//   before the cast. The ramp is clamped to `0..=max_brightness`, so the
//   rounded value is always inside `i32`.
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
                sensor_width: crate::sim_frame::SIM_W as u32,
                sensor_height: crate::sim_frame::SIM_H as u32,
                pixel_size_x: 3.76,
                pixel_size_y: 3.76,
                max_adu: crate::sim_frame::SIM_MAX_ADU as u32,
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

/// What the most recently started simulated exposure was asked for.
///
/// The simulator does not integrate for real, but the download path still has
/// to report an `ImageMetadata::exposure_time`, and that value becomes the saved
/// frame's `EXPTIME` — the one FITS keyword calibration and stacking tools trust
/// most. It was a hardcoded `1.0`, so every simulated frame claimed a 1-second
/// exposure regardless of what the sequence asked for.
///
/// `frame_type` and `subframe` live here for the same reason: the download op
/// takes only a device id, so without them a DARK was generated as a star field
/// and announced itself as a light, and a subframe request came back full-frame.
///
/// Kept out of [`SimulatedCamera`] on purpose: that struct is mirrored to Dart
/// by flutter_rust_bridge, and Dart has no use for this.
///
/// `frb(ignore)` enforces that. Living under `api::` is enough for the codegen
/// to try to bridge it anyway, and it cannot: `frame_type` is
/// `nightshade_native::camera::FrameType`, which the generator resolves by bare
/// name to the unrelated `crate::device::FrameType`, emitting a
/// `frb_generated.rs` that does not compile. The committed generated file
/// predates this struct and so hid the problem until the next regeneration.
#[flutter_rust_bridge::frb(ignore)]
#[derive(Debug, Clone)]
pub(crate) struct SimExposureRequest {
    pub secs: f64,
    pub frame_type: nightshade_native::camera::FrameType,
    pub subframe: Option<(u32, u32, u32, u32)>,
}

impl Default for SimExposureRequest {
    fn default() -> Self {
        Self {
            secs: 1.0,
            frame_type: nightshade_native::camera::FrameType::Light,
            subframe: None,
        }
    }
}

static SIM_LAST_EXPOSURE: OnceLock<Arc<RwLock<SimExposureRequest>>> = OnceLock::new();

pub(crate) fn get_sim_last_exposure() -> &'static Arc<RwLock<SimExposureRequest>> {
    SIM_LAST_EXPOSURE.get_or_init(|| Arc::new(RwLock::new(SimExposureRequest::default())))
}

/// Monotonic frame counter feeding the noise seed of each simulated read.
///
/// Successive frames must not be bit-identical or a stack cannot exercise
/// sigma-clipping, while a fixed starting point keeps a run reproducible.
static SIM_FRAME_SEED: AtomicU64 = AtomicU64::new(0);

pub(crate) fn next_sim_frame_seed() -> u64 {
    SIM_FRAME_SEED.fetch_add(1, Ordering::Relaxed)
}

/// Reset the frame-noise sequence so a test can reproduce a run exactly.
#[cfg(test)]
pub(crate) fn reset_sim_frame_seed(seed: u64) {
    SIM_FRAME_SEED.store(seed, Ordering::Relaxed);
}

/// Serializes every test that drives the process-global simulator singletons.
///
/// `SIM_CAMERA`, `SIM_MOUNT` and the exposure/slew clocks are one shared
/// instance per process, and cargo runs tests in parallel threads, so without
/// this one test's abort lands in the middle of another's exposure. It is
/// deliberately a SINGLE lock covering all the singletons: the connection-gate
/// tests flip several device types at once, so per-device locks would not
/// actually exclude each other.
#[cfg(test)]
static SIM_SINGLETON_TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

#[cfg(test)]
pub(crate) fn sim_singleton_test_lock() -> &'static Mutex<()> {
    SIM_SINGLETON_TEST_LOCK.get_or_init(|| Mutex::new(()))
}

/// Where the simulated camera is in its exposure cycle.
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
///
/// Real cameras pace their callers by simply not being finished yet; the
/// simulator has to do the same to be worth testing against.
///
/// `Aborted` is distinct from `Idle` on purpose. Both release a caller polling
/// for completion, but only `Idle` follows a frame that was actually read out —
/// collapsing them let a download after an abort hand back a full frame, so an
/// aborted exposure was indistinguishable from a successful one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SimExposurePhase {
    Idle,
    Integrating(std::time::Instant),
    Aborted,
}

static SIM_EXPOSURE_PHASE: OnceLock<Arc<RwLock<SimExposurePhase>>> = OnceLock::new();

fn sim_exposure_phase() -> &'static Arc<RwLock<SimExposurePhase>> {
    SIM_EXPOSURE_PHASE.get_or_init(|| Arc::new(RwLock::new(SimExposurePhase::Idle)))
}

/// Record the start of a simulated exposure.
pub(crate) async fn begin_sim_exposure(request: SimExposureRequest) {
    *get_sim_last_exposure().write().await = request;
    *sim_exposure_phase().write().await = SimExposurePhase::Integrating(std::time::Instant::now());
}

/// Return the camera to idle without consuming a frame.
///
/// Production code never needs this — the download claims the frame via
/// [`take_sim_exposure_for_download`] and an abort goes through
/// [`abort_sim_exposure`] — but a test that drives the singleton has to be able
/// to start from a known phase.
#[cfg(test)]
pub(crate) async fn clear_sim_exposure() {
    *sim_exposure_phase().write().await = SimExposurePhase::Idle;
}

/// Abandon the in-flight exposure. The frame is gone — a later download must
/// fail rather than synthesize one.
pub(crate) async fn abort_sim_exposure() {
    *sim_exposure_phase().write().await = SimExposurePhase::Aborted;
}

/// Whether the in-flight simulated exposure has finished integrating.
///
/// Idle and aborted both read as complete: a caller polling without having
/// started anything, or after abandoning what it started, must not be made to
/// wait forever.
pub(crate) async fn sim_exposure_is_complete() -> bool {
    match *sim_exposure_phase().read().await {
        SimExposurePhase::Idle | SimExposurePhase::Aborted => true,
        SimExposurePhase::Integrating(start) => {
            let requested = get_sim_last_exposure().read().await.secs;
            sim_exposure_elapsed_is_complete(start.elapsed().as_secs_f64(), requested)
        }
    }
}

/// The camera state a status read should report right now.
///
/// The device layer never drove this, so `camera_get_status` answered `Idle`
/// for the whole of an exposure while `camera_is_exposure_complete` answered
/// "not yet" — two contradictory answers on the same polling cycle.
pub(crate) async fn sim_camera_state() -> CameraState {
    match *sim_exposure_phase().read().await {
        SimExposurePhase::Idle | SimExposurePhase::Aborted => CameraState::Idle,
        SimExposurePhase::Integrating(start) => {
            let requested = get_sim_last_exposure().read().await.secs;
            if sim_exposure_elapsed_is_complete(start.elapsed().as_secs_f64(), requested) {
                CameraState::Reading
            } else {
                CameraState::Exposing
            }
        }
    }
}

/// Claim the finished frame for download, moving the camera back to idle.
///
/// Returns the reason the frame is not available when it is not: downloading
/// mid-exposure, after an abort, or without having started anything at all are
/// all caller errors that a real driver reports rather than satisfying.
pub(crate) async fn take_sim_exposure_for_download() -> Result<(), String> {
    let mut phase = sim_exposure_phase().write().await;
    match *phase {
        SimExposurePhase::Idle => Err(
            "No exposure is available to download from the simulated camera. \
             Start an exposure first."
                .to_string(),
        ),
        SimExposurePhase::Aborted => Err(
            "The simulated camera's exposure was aborted, so there is no frame to download."
                .to_string(),
        ),
        SimExposurePhase::Integrating(start) => {
            let requested = get_sim_last_exposure().read().await.secs;
            let elapsed = start.elapsed().as_secs_f64();
            if !sim_exposure_elapsed_is_complete(elapsed, requested) {
                return Err(format!(
                    "The simulated camera is still integrating ({:.1}s of {:.1}s elapsed); \
                     wait for the exposure to complete before downloading.",
                    elapsed, requested
                ));
            }
            *phase = SimExposurePhase::Idle;
            Ok(())
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
    tracing::info!("Setting camera gain for {}: {}", device_id, gain);
    let mgr = get_device_manager();
    mgr.camera_set_gain(&device_id, gain)
        .await
        .map_err(NightshadeError::from)
}

/// Set camera offset
pub async fn api_set_camera_offset(device_id: String, offset: i32) -> Result<(), NightshadeError> {
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

/// Simulated slew rate, degrees of arc per second.
///
/// Far brisker than real hardware (a good GEM manages 3-6 °/s) for the same
/// reason the cooler ramp is: the motion has to COMPLETE inside a test or a
/// sequence node's budget. It still takes time, which is the point — RA/Dec
/// used to snap to the target and `slewing` was never true, so every
/// wait-for-motion path in the app completed before the mount had moved and
/// none of them could be exercised without hardware.
const SIM_SLEW_DEG_PER_SEC: f64 = 180.0;

/// Floor on how long any commanded slew takes.
///
/// A meridian flip re-slews to the SAME coordinates, so a pure
/// distance/rate model would make the largest mechanical motion a GEM
/// performs finish instantly.
const SIM_MIN_SLEW_SECS: f64 = 0.2;

/// How long the simulated mount keeps reporting `slewing` AFTER its axes have
/// reached the commanded coordinates.
///
/// Real drivers hold `Slewing` true through a mechanical settle: the axes
/// arrive, the tube rings down, and only then does the driver report idle.
/// Without a tail here `slewing` fell to false in the very same status read
/// that first reported the target coordinates, so "arrived" and "stopped
/// moving" were one event and no caller could ever observe them out of order.
/// Every wait-for-motion path in the app — the sequencer's
/// `wait_for_mount_idle_with_progress`, centering's
/// `wait_for_centering_correction_slew` (and the
/// `CenteringSlewTimeoutException` behind it), the polar-alignment poll and
/// the post-flip guiding settle — was therefore satisfied on its first poll.
/// This project has already shipped a post-flip guiding-settle bug that a
/// settle-free simulator cannot reproduce.
///
/// Sized in the same family as [`SIM_CALIBRATOR_SETTLE_SECS`]: long enough
/// that a poller has to go round at least once more, short enough that it
/// still fits inside a sequence node's budget.
const SIM_SLEW_SETTLE_SECS: f64 = 0.6;

/// Extra arc a slew covers when it also crosses the mount to the other side of
/// the pier: the tube swings through roughly half a turn of the RA axis on top
/// of whatever the coordinate change asks for.
const SIM_FLIP_TRAVERSE_DEG: f64 = 180.0;

/// An in-flight simulated slew.
///
/// Kept out of [`SimulatedMount`] because that struct is mirrored to Dart by
/// flutter_rust_bridge and Dart has no use for the interpolation state.
#[derive(Debug, Clone, Copy)]
struct SimSlew {
    start: std::time::Instant,
    duration_secs: f64,
    from: (f64, f64),
    to: (f64, f64),
    to_pier: PierSide,
}

static SIM_SLEW: OnceLock<Arc<RwLock<Option<SimSlew>>>> = OnceLock::new();

fn sim_slew() -> &'static Arc<RwLock<Option<SimSlew>>> {
    SIM_SLEW.get_or_init(|| Arc::new(RwLock::new(None)))
}

/// Great-circle separation between two equatorial positions, in degrees.
fn angular_separation_deg(from: (f64, f64), to: (f64, f64)) -> f64 {
    let (ra1, dec1) = ((from.0 * 15.0).to_radians(), from.1.to_radians());
    let (ra2, dec2) = ((to.0 * 15.0).to_radians(), to.1.to_radians());
    let cos_sep = dec1.sin() * dec2.sin() + dec1.cos() * dec2.cos() * (ra2 - ra1).cos();
    cos_sep.clamp(-1.0, 1.0).acos().to_degrees()
}

/// How long a slew covering `separation_deg` takes, given whether it also
/// crosses the pier.
fn sim_slew_duration_secs(separation_deg: f64, crosses_pier: bool) -> f64 {
    let arc = separation_deg
        + if crosses_pier {
            SIM_FLIP_TRAVERSE_DEG
        } else {
            0.0
        };
    (arc / SIM_SLEW_DEG_PER_SEC).max(SIM_MIN_SLEW_SECS)
}

/// Interpolate right ascension the short way around the 24h wrap, so a slew
/// from 23h to 1h travels two hours forward rather than 22 hours backward.
fn interpolate_ra(from: f64, to: f64, fraction: f64) -> f64 {
    let mut delta = (to - from).rem_euclid(24.0);
    if delta > 12.0 {
        delta -= 24.0;
    }
    (from + delta * fraction).rem_euclid(24.0)
}

/// The side of the pier a German equatorial ends up on after slewing to `ra`,
/// given the local sidereal time at the moment the slew is commanded.
///
/// Pier side is MECHANICAL STATE, not a projection of where the mount is
/// pointing: a GEM tracks straight through the meridian without flipping, so
/// the side only changes when a slew puts it on the other one. Deriving it from
/// the current pointing instead made it change with the clock while the mount
/// stood still, and made a meridian flip — whose entire signature is "the side
/// changed" — impossible to detect, because re-slewing to the same coordinates
/// re-derived the same answer.
fn pier_side_after_slew_to(ra_hours: f64, lst_hours: f64) -> PierSide {
    match nightshade_sequencer::meridian::expected_pier_side(
        nightshade_sequencer::meridian::hour_angle(ra_hours, lst_hours),
    ) {
        nightshade_sequencer::meridian::PierSide::East => PierSide::East,
        nightshade_sequencer::meridian::PierSide::West => PierSide::West,
        nightshade_sequencer::meridian::PierSide::Unknown => PierSide::Unknown,
    }
}

/// Local sidereal time now for the configured site, if there is one.
fn sim_local_sidereal_time(now: chrono::DateTime<chrono::Utc>) -> Option<f64> {
    let longitude = crate::api::get_state()
        .get_observer_location()
        .ok()
        .flatten()?
        .longitude;
    Some(nightshade_sequencer::meridian::local_sidereal_time(
        nightshade_sequencer::meridian::julian_day(&now),
        longitude,
    ))
}

/// Start a simulated slew to `(ra, dec)`, deciding the pier side it will land
/// on from the local sidereal time at `now`.
///
/// Without a configured site there is no hour angle and therefore no honest
/// answer for the pier side, so the mount keeps the side it was already on.
pub(crate) async fn begin_sim_slew(ra: f64, dec: f64, now: chrono::DateTime<chrono::Utc>) {
    let (from, current_pier) = {
        let mount = get_sim_mount().read().await;
        (
            (mount.status.right_ascension, mount.status.declination),
            mount.status.side_of_pier.unwrap_or(PierSide::Unknown),
        )
    };
    let to_pier = match sim_local_sidereal_time(now) {
        Some(lst) => pier_side_after_slew_to(ra, lst),
        None => current_pier,
    };
    let duration_secs = sim_slew_duration_secs(
        angular_separation_deg(from, (ra, dec)),
        to_pier != current_pier && current_pier != PierSide::Unknown,
    );

    *sim_slew().write().await = Some(SimSlew {
        start: std::time::Instant::now(),
        duration_secs,
        from,
        to: (ra, dec),
        to_pier,
    });
    let mut mount = get_sim_mount().write().await;
    mount.status.slewing = true;
    mount.status.parked = false;
    mount.status.at_home = Some(false);
}

/// Advance an in-flight slew to now, updating the mount's pointing and, on
/// arrival, its pier side.
///
/// Called from every simulated mount status read, which is what makes the
/// motion observable to a caller polling `slewing`.
pub(crate) async fn advance_sim_slew() {
    let Some(slew) = *sim_slew().read().await else {
        return;
    };
    let elapsed_secs = slew.start.elapsed().as_secs_f64();
    let fraction = if slew.duration_secs > 0.0 {
        (elapsed_secs / slew.duration_secs).clamp(0.0, 1.0)
    } else {
        1.0
    };

    let mut mount = get_sim_mount().write().await;
    if fraction >= 1.0 {
        // The axes are on target and the pier side is committed from here on,
        // but the driver does not report idle until the settle tail expires —
        // see SIM_SLEW_SETTLE_SECS for why "arrived" and "stopped" must be two
        // observable events rather than one.
        mount.status.right_ascension = slew.to.0;
        mount.status.declination = slew.to.1;
        mount.status.side_of_pier = Some(slew.to_pier);
        if elapsed_secs >= slew.duration_secs + SIM_SLEW_SETTLE_SECS {
            mount.status.slewing = false;
            drop(mount);
            *sim_slew().write().await = None;
        } else {
            mount.status.slewing = true;
        }
    } else {
        mount.status.right_ascension = interpolate_ra(slew.from.0, slew.to.0, fraction);
        mount.status.declination = slew.from.1 + (slew.to.1 - slew.from.1) * fraction;
        mount.status.slewing = true;
    }
}

/// Drop any in-flight slew, leaving the mount wherever it had reached.
///
/// Abort/stop/park all need this: without it the interpolation would carry the
/// mount on to the target it was told to stop travelling to.
pub(crate) async fn cancel_sim_slew() {
    *sim_slew().write().await = None;
}

/// Whether a commanded slew — including its [`SIM_SLEW_SETTLE_SECS`] tail — is
/// still in flight as of the last [`advance_sim_slew`].
///
/// Reads only: callers reach this through `sim_gate::require_mount_connected`,
/// which has already advanced the motion under the fault gate. Advancing again
/// here would let a caller step a mount that `sim_faults` has deliberately
/// stalled.
pub(crate) async fn sim_slew_in_flight() -> bool {
    sim_slew().read().await.is_some()
}

/// The equatorial coordinates a parked simulated mount reports.
///
/// A parked German equatorial sits with the counterweights down pointing at the
/// celestial pole, which is a fixed point in the horizon frame — altitude
/// equals the site latitude and azimuth is due pole, whatever the time. Park
/// used to leave RA/Dec at the previous target, so a parked mount reported the
/// altitude of whatever it had been imaging, and that altitude went on tracking
/// the sky.
pub(crate) fn sim_park_position() -> (f64, f64) {
    let southern = crate::api::get_state()
        .get_observer_location()
        .ok()
        .flatten()
        .is_some_and(|site| site.latitude < 0.0);
    (0.0, if southern { -90.0 } else { 90.0 })
}

/// Get mount status
pub async fn api_get_mount_status(device_id: String) -> Result<MountStatus, NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_get_status(&device_id)
        .await
        .map_err(NightshadeError::from)
}

/// Slew mount to coordinates
pub async fn api_mount_slew_to_coordinates(
    device_id: String,
    ra: f64,
    dec: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_slew(&device_id, ra, dec)
        .await
        .map_err(NightshadeError::from)
}

/// Sync mount to coordinates
pub async fn api_mount_sync_to_coordinates(
    device_id: String,
    ra: f64,
    dec: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_sync(&device_id, ra, dec)
        .await
        .map_err(NightshadeError::from)
}

/// Park the mount
pub async fn api_mount_park(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_park(&device_id)
        .await
        .map_err(NightshadeError::from)
}

/// Unpark the mount
pub async fn api_mount_unpark(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_unpark(&device_id)
        .await
        .map_err(NightshadeError::from)
}

/// Set mount tracking
pub async fn api_mount_set_tracking(device_id: String, enabled: u8) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_set_tracking(&device_id, enabled != 0)
        .await
        .map_err(NightshadeError::from)
}

/// Slew mount to alt/az coordinates (simulator handler)
pub async fn api_mount_slew_alt_az(
    device_id: String,
    altitude: f64,
    azimuth: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_slew_alt_az(&device_id, altitude, azimuth)
        .await
        .map_err(NightshadeError::from)
}

/// Find mount home position (simulator handler)
pub async fn api_mount_find_home(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_find_home(&device_id)
        .await
        .map_err(NightshadeError::from)
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

/// Move focuser to position
pub async fn api_focuser_move_to(device_id: String, position: i32) -> Result<(), NightshadeError> {
    // Real device - use DeviceManager for proper driver routing
    let mgr = get_device_manager();
    mgr.focuser_move_abs(&device_id, position)
        .await
        .map_err(NightshadeError::from)
}

/// Move focuser by relative amount
pub async fn api_focuser_move_relative(
    device_id: String,
    delta: i32,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_move_rel(&device_id, delta)
        .await
        .map_err(NightshadeError::from)
}

/// Halt focuser
pub async fn api_focuser_halt(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_halt(&device_id)
        .await
        .map_err(NightshadeError::from)
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

/// Get filter names
pub async fn api_filterwheel_get_names(device_id: String) -> Result<Vec<String>, NightshadeError> {
    // Real device - use DeviceManager for proper driver routing
    let mgr = get_device_manager();
    let (_, filter_names) = mgr
        .filter_wheel_get_config(&device_id)
        .await
        .map_err(NightshadeError::from)?;
    Ok(filter_names)
}

/// Set filter by name
pub async fn api_filterwheel_set_by_name(
    device_id: String,
    name: String,
) -> Result<(), NightshadeError> {
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
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set filter: {}", e)))?;

    Ok(())
}

/// Set filter names on a filter wheel
/// This pushes user-defined filter names from the equipment profile to the hardware driver.
pub async fn api_filterwheel_set_filter_names(
    device_id: String,
    names: Vec<String>,
) -> Result<(), NightshadeError> {
    tracing::info!("API: Setting filter names for '{}': {:?}", device_id, names);

    // Real device - use DeviceManager
    let mgr = get_device_manager();
    mgr.filter_wheel_set_filter_names(&device_id, names)
        .await
        .map_err(|e| {
            NightshadeError::OperationFailed(format!("Failed to set filter names: {}", e))
        })?;
    Ok(())
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

/// Move rotator to angle
pub async fn api_rotator_move_to(device_id: String, angle: f64) -> Result<(), NightshadeError> {
    // Real device - use DeviceManager for proper driver routing
    let mgr = get_device_manager();
    mgr.rotator_move_absolute(&device_id, angle)
        .await
        .map_err(NightshadeError::from)
}

/// Move rotator relative
pub async fn api_rotator_move_relative(
    device_id: String,
    delta: f64,
) -> Result<(), NightshadeError> {
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

/// Set the rotator's reverse-direction flag (IRotatorV3 `Reverse`, Alpaca
/// `reverse`, INDI `ROTATOR_REVERSE`).
pub async fn api_rotator_set_reverse(
    device_id: String,
    reverse: bool,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.rotator_set_reverse(&device_id, reverse)
        .await
        .map_err(NightshadeError::from)
}

/// Halt rotator
pub async fn api_rotator_halt(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.rotator_halt(&device_id)
        .await
        .map_err(NightshadeError::from)
}

/// Sync rotator's reported sky angle to the supplied position angle without
/// moving the hardware. Used by the "Sync to image PA" workflow after a plate
/// solve: the solver returns the astrometric PA of the captured frame and
/// this call aligns the rotator's reported PA so subsequent absolute moves
/// land at the correct sky angle.
pub async fn api_rotator_sync_to_pa(device_id: String, pa: f64) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.rotator_sync(&device_id, pa)
        .await
        .map_err(NightshadeError::from)
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

// =============================================================================
// Switch and cover calibrator simulators
// =============================================================================

/// Why a simulated device refused an operation.
///
/// A category rather than a formatted string for the same reason
/// [`crate::dispatch::DeviceOpError`] is an enum: the ops layer has to pick
/// `not_connected` vs `invalid_parameter` vs `driver`, and doing that by
/// matching on message text is how the wrong error class ships.
#[derive(Debug, Clone, PartialEq, Eq)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) enum SimDeviceError {
    /// The singleton's `connected` flag is false — nothing was ever opened.
    NotConnected(String),
    /// The caller asked for something the device cannot represent: a switch
    /// index that does not exist, a value outside a channel's range, a write to
    /// a read-only channel. Real ASCOM drivers raise `InvalidValueException` /
    /// `MethodNotImplementedException` here rather than quietly clamping.
    InvalidParameter(String),
    /// An injected driver fault; see [`crate::device_manager::ops::sim_faults`].
    Driver(String),
}

impl std::fmt::Display for SimDeviceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SimDeviceError::NotConnected(m)
            | SimDeviceError::InvalidParameter(m)
            | SimDeviceError::Driver(m) => f.write_str(m),
        }
    }
}

/// Preserve the category across the ops boundary.
///
/// Flattening everything to `DeviceOpError::driver` would mark a rejected
/// brightness or a bad switch index as a hardware failure, which
/// `DeviceOpError::is_retryable` then tells the app to retry — forever, since
/// the caller's argument is not going to get better on its own. The device id
/// is left `None` to match the other simulator arms (`ops/filter_wheel.rs`),
/// whose messages already name the simulated device type rather than an id.
impl From<SimDeviceError> for crate::dispatch::DeviceOpError {
    fn from(err: SimDeviceError) -> Self {
        use crate::dispatch::DeviceOpError;
        match err {
            SimDeviceError::NotConnected(m) => DeviceOpError::not_connected(None, m),
            SimDeviceError::InvalidParameter(m) => DeviceOpError::invalid_parameter(m),
            SimDeviceError::Driver(m) => DeviceOpError::driver(m),
        }
    }
}

/// Consult the fault registry, mapping a fired fault onto [`SimDeviceError`].
async fn sim_fault(key: &str) -> Result<(), SimDeviceError> {
    crate::device_manager::ops::sim_faults::check(key)
        .await
        .map_err(SimDeviceError::Driver)
}

/// A mechanism travelling from one value to another over a known time.
///
/// Shared by the cover's lid and the panel's brightness because both have the
/// same property that matters here: the value a caller reads mid-flight is
/// somewhere in between, not the commanded endpoint. Modelled as a start
/// instant plus a duration (like `SimSlew`) rather than a per-tick integrator
/// so there is no "first read establishes the baseline" hazard — the motion is
/// fully determined by the command that started it.
#[derive(Debug, Clone, Copy)]
#[flutter_rust_bridge::frb(ignore)]
struct SimRamp {
    start: Instant,
    duration_secs: f64,
    from: f64,
    to: f64,
}

impl SimRamp {
    fn fraction(&self) -> f64 {
        if self.duration_secs <= 0.0 {
            return 1.0;
        }
        (self.start.elapsed().as_secs_f64() / self.duration_secs).clamp(0.0, 1.0)
    }

    fn value(&self) -> f64 {
        self.from + (self.to - self.from) * self.fraction()
    }

    fn is_complete(&self) -> bool {
        self.fraction() >= 1.0
    }
}

/// End-to-end travel time of the simulated dust cover, in seconds.
///
/// An Alnitak Flip-Flat takes two to four seconds to swing its lid. The
/// simulator is quicker so the motion still completes inside the sequencer's
/// 60 s cover budget and inside a test, but it must not be INSTANT: the only
/// reason `CoverState::Moving` exists is that a caller has to wait through it,
/// and a cover that reads `Open` on the same poll that commanded it means
/// `wait_for_cover_state` returns before real hardware would have started
/// moving. That is the same class of bug as a slew that completes in zero time.
const SIM_COVER_TRAVEL_SECS: f64 = 1.5;

/// How far past its expected travel time the simulated controller waits before
/// declaring the lid jammed.
///
/// Real cover controllers run their own move timeout and report
/// `CoverState::Error` when a lid does not arrive — which is why
/// `wait_for_cover_state` has an `Error` branch at all. Without this the branch
/// is unreachable without hardware: a stalled cover would read `Moving` until
/// the sequence node's own timeout and the driver-detected-jam path would ship
/// unexercised.
const SIM_COVER_JAM_TIMEOUT_MULTIPLE: f64 = 3.0;

/// Tolerance, in units of full travel, for calling the lid fully open/closed.
const SIM_COVER_ENDSTOP_EPS: f64 = 1e-6;

/// Time the simulated panel takes to settle after a full-scale brightness
/// change, in seconds.
///
/// Electroluminescent panels ramp; `CalibratorState::NotReady` exists precisely
/// because a flat taken before the panel settles is at the wrong level. A
/// simulator that jumped straight to `Ready` would leave both the wait in
/// `execute_calibrator_on` and the flat wizard's readiness handling unexercised.
const SIM_CALIBRATOR_SETTLE_SECS: f64 = 0.8;

/// Brightness ceiling the simulated panel advertises.
///
/// 255 is the ASCOM default that `ops/cover.rs` already falls back to when a
/// driver will not answer, and it is what an Alnitak reports. Deliberately not
/// 100: `CalibratorOnConfig` documents brightness as "0-max, typically 0-255"
/// while the instruction's own progress text renders the same number as a
/// percentage, and a panel whose scale is not 0-100 is the only way that
/// discrepancy can surface without hardware.
const SIM_CALIBRATOR_MAX_BRIGHTNESS: i32 = 255;

/// Backing state for the flat-panel-plus-dust-cover simulator.
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct SimulatedCoverCalibrator {
    pub connected: bool,
    /// Lid travel, 0.0 fully closed through 1.0 fully open.
    ///
    /// A position rather than a state so a halt mid-travel is representable at
    /// all: the lid is then genuinely neither open nor closed, which is exactly
    /// what `CoverState::Unknown` means and what a real controller reports after
    /// `HaltCover`. Storing only the state would have forced halt to be either a
    /// no-op or a lie about where the lid is.
    cover_position: f64,
    cover_travel: Option<SimRamp>,
    /// Latched jam: the controller gave up on a lid that stopped moving.
    cover_jammed: bool,
    /// Whether the panel has been commanded on. Kept separate from the
    /// brightness so `CalibratorOn(0)` — a legal ASCOM call — still reads
    /// `Ready` rather than being indistinguishable from `CalibratorOff`.
    calibrator_on: bool,
    brightness: f64,
    brightness_ramp: Option<SimRamp>,
}

impl Default for SimulatedCoverCalibrator {
    fn default() -> Self {
        // Starts closed and dark: that is where a flat panel sits at the start
        // of a night, and it means a sequence that forgets to open the cover
        // gets black frames rather than a simulator that was helpfully already
        // open.
        Self {
            connected: false,
            cover_position: 0.0,
            cover_travel: None,
            cover_jammed: false,
            calibrator_on: false,
            brightness: 0.0,
            brightness_ramp: None,
        }
    }
}

impl SimulatedCoverCalibrator {
    fn require_connected(&self) -> Result<(), SimDeviceError> {
        if self.connected {
            return Ok(());
        }
        Err(SimDeviceError::NotConnected(
            "Simulator cover calibrator is not connected. Call connect_device first.".to_string(),
        ))
    }

    fn cover_state(&self) -> CoverState {
        if self.cover_jammed {
            return CoverState::Error;
        }
        if self.cover_travel.is_some() {
            return CoverState::Moving;
        }
        if self.cover_position >= 1.0 - SIM_COVER_ENDSTOP_EPS {
            CoverState::Open
        } else if self.cover_position <= SIM_COVER_ENDSTOP_EPS {
            CoverState::Closed
        } else {
            // Stopped part-way. The controller knows the lid is not on either
            // endstop and cannot say which side it will end up on.
            CoverState::Unknown
        }
    }

    fn calibrator_state(&self) -> CalibratorState {
        if self.brightness_ramp.is_some() {
            // Also covers the way down: ASCOM keeps a calibrator `NotReady`
            // until it is safely off, not just while it is warming up.
            CalibratorState::NotReady
        } else if self.calibrator_on {
            CalibratorState::Ready
        } else {
            CalibratorState::Off
        }
    }

    fn reported_brightness(&self) -> i32 {
        self.brightness.round() as i32
    }

    /// Start the panel moving toward `target`, taking time proportional to how
    /// far it has to travel — a nudge from 200 to 210 settles far quicker than
    /// a jump from dark to full, as on a real panel.
    fn begin_brightness_ramp(&mut self, target: f64) {
        let span = f64::from(SIM_CALIBRATOR_MAX_BRIGHTNESS);
        let duration = SIM_CALIBRATOR_SETTLE_SECS * ((target - self.brightness).abs() / span);
        if duration <= 0.0 {
            self.brightness = target;
            self.brightness_ramp = None;
            return;
        }
        self.brightness_ramp = Some(SimRamp {
            start: Instant::now(),
            duration_secs: duration,
            from: self.brightness,
            to: target,
        });
    }
}

pub(crate) static SIM_COVER_CALIBRATOR: OnceLock<Arc<RwLock<SimulatedCoverCalibrator>>> =
    OnceLock::new();

pub(crate) fn get_sim_cover_calibrator() -> &'static Arc<RwLock<SimulatedCoverCalibrator>> {
    SIM_COVER_CALIBRATOR.get_or_init(|| Arc::new(RwLock::new(SimulatedCoverCalibrator::default())))
}

/// Return the panel to its start-of-night state.
///
/// The singleton is process-global, so a test that opened the lid would
/// otherwise hand the next one a cover that is already open — and "commanding
/// open when already open" is a legitimately different path from "opening a
/// closed cover", so the next test would silently stop testing what it names.
#[cfg(test)]
pub(crate) async fn reset_sim_cover_calibrator() {
    *get_sim_cover_calibrator().write().await = SimulatedCoverCalibrator::default();
}

/// Advance the lid and the panel to now.
///
/// Called from every simulated cover-calibrator op, which is what makes the
/// motion observable to a caller polling `cover_state` — the same arrangement
/// that drives `advance_sim_slew` from every mount status read.
pub(crate) async fn advance_sim_cover_calibrator() {
    // A stalled lid does not move. The command that stalled it still returned
    // `Ok`, so the only evidence is that the state never becomes `Open` — which
    // is precisely the failure mode a real jammed Flip-Flat presents.
    let stalled = crate::device_manager::ops::sim_faults::is_stalled("covercalibrator.cover");
    let mut cc = get_sim_cover_calibrator().write().await;

    if let Some(travel) = cc.cover_travel {
        if stalled {
            if travel.start.elapsed().as_secs_f64()
                > travel.duration_secs * SIM_COVER_JAM_TIMEOUT_MULTIPLE
            {
                cc.cover_travel = None;
                cc.cover_jammed = true;
            }
        } else if travel.is_complete() {
            cc.cover_position = travel.to;
            cc.cover_travel = None;
        } else {
            cc.cover_position = travel.value();
        }
    }

    if let Some(ramp) = cc.brightness_ramp {
        if ramp.is_complete() {
            cc.brightness = ramp.to;
            cc.brightness_ramp = None;
        } else {
            cc.brightness = ramp.value();
        }
    }
}

/// Read the simulated panel's combined status.
pub(crate) async fn sim_cover_status() -> Result<CoverCalibratorStatus, SimDeviceError> {
    sim_fault("covercalibrator.status").await?;
    advance_sim_cover_calibrator().await;
    let cc = get_sim_cover_calibrator().read().await;
    cc.require_connected()?;
    Ok(CoverCalibratorStatus {
        connected: true,
        cover_state: cc.cover_state(),
        calibrator_state: cc.calibrator_state(),
        brightness: cc.reported_brightness(),
        max_brightness: SIM_CALIBRATOR_MAX_BRIGHTNESS,
    })
}

/// Command the lid open (`open == true`) or closed.
///
/// Reversing mid-travel is honest about where the lid actually is: a half-open
/// cover takes half the travel time to close again, because the ramp starts
/// from the advanced position rather than from the endstop it last left.
pub(crate) async fn sim_cover_move(open: bool) -> Result<(), SimDeviceError> {
    sim_fault("covercalibrator.command").await?;
    // Arms the stall latch the advancer consults; see `sim_faults` for why a
    // stall returns `Ok` rather than an error.
    sim_fault("covercalibrator.cover").await?;
    advance_sim_cover_calibrator().await;

    let mut cc = get_sim_cover_calibrator().write().await;
    cc.require_connected()?;
    // Commanding the mechanism again re-arms the controller, exactly as
    // power-cycling a jammed lid or re-issuing the move does on real hardware.
    cc.cover_jammed = false;

    let target = if open { 1.0 } else { 0.0 };
    let distance = (target - cc.cover_position).abs();
    if distance <= SIM_COVER_ENDSTOP_EPS {
        // Already there. A real controller answers immediately rather than
        // driving the motor into the endstop for a second and a half.
        cc.cover_travel = None;
        return Ok(());
    }
    cc.cover_travel = Some(SimRamp {
        start: Instant::now(),
        duration_secs: SIM_COVER_TRAVEL_SECS * distance,
        from: cc.cover_position,
        to: target,
    });
    Ok(())
}

/// Stop the lid where it is.
pub(crate) async fn sim_cover_halt() -> Result<(), SimDeviceError> {
    sim_fault("covercalibrator.command").await?;
    advance_sim_cover_calibrator().await;
    let mut cc = get_sim_cover_calibrator().write().await;
    cc.require_connected()?;
    cc.cover_travel = None;
    Ok(())
}

/// Turn the panel on at `brightness`.
pub(crate) async fn sim_calibrator_on(brightness: i32) -> Result<(), SimDeviceError> {
    sim_fault("covercalibrator.command").await?;
    advance_sim_cover_calibrator().await;
    let mut cc = get_sim_cover_calibrator().write().await;
    cc.require_connected()?;

    // ASCOM requires a brightness outside 0..=MaxBrightness to raise
    // InvalidValueException. Clamping instead would hide the app sending a
    // 0-100 percentage to a 0-255 panel (or the reverse) — it would simply
    // produce the wrong flat level and nothing would say so.
    if !(0..=SIM_CALIBRATOR_MAX_BRIGHTNESS).contains(&brightness) {
        return Err(SimDeviceError::InvalidParameter(format!(
            "Calibrator brightness {} is outside the panel's 0-{} range",
            brightness, SIM_CALIBRATOR_MAX_BRIGHTNESS
        )));
    }

    cc.calibrator_on = true;
    cc.begin_brightness_ramp(f64::from(brightness));
    Ok(())
}

/// Turn the panel off.
pub(crate) async fn sim_calibrator_off() -> Result<(), SimDeviceError> {
    sim_fault("covercalibrator.command").await?;
    advance_sim_cover_calibrator().await;
    let mut cc = get_sim_cover_calibrator().write().await;
    cc.require_connected()?;
    cc.calibrator_on = false;
    cc.begin_brightness_ramp(0.0);
    Ok(())
}

/// How long a commanded switch change takes to appear in the device's own
/// telemetry, in seconds.
///
/// A Pegasus powerbox acknowledges a command immediately but reports state from
/// its own status poll, so a read issued straight after a write returns the
/// PREVIOUS value. That race is where a whole class of UI bugs lives — toggle a
/// port, re-read, see the old state, snap the control back — and a simulator
/// that applies writes instantly can never produce it.
const SIM_SWITCH_SETTLE_SECS: f64 = 0.25;

/// Draw of the controller itself with every output off, in amps.
const SIM_SWITCH_QUIESCENT_AMPS: f64 = 0.4;
/// Draw added by the switched 12 V bank (mount plus camera), in amps.
const SIM_SWITCH_QUAD_AMPS: f64 = 1.8;
/// Draw added by the DSLR output, in amps.
const SIM_SWITCH_DSLR_AMPS: f64 = 0.9;
/// Draw added per percent of dew-heater duty cycle, in amps. A dew strap at
/// full duty pulls about 3 A, which is what sizes this.
const SIM_SWITCH_DEW_AMPS_PER_PERCENT: f64 = 0.03;
/// Open-circuit supply voltage, in volts.
const SIM_SWITCH_SUPPLY_VOLTS: f64 = 13.8;
/// Supply sag per amp drawn, in volts. Real cabling has resistance, and the
/// voltage readout dropping under load is what makes an undersized supply
/// diagnosable from the app.
const SIM_SWITCH_SAG_VOLTS_PER_AMP: f64 = 0.05;

/// Indices of the simulated powerbox's channels. Named because the derived
/// sensor channels below read the controllable ones by position.
const SIM_SWITCH_QUAD: usize = 0;
const SIM_SWITCH_DSLR: usize = 1;
const SIM_SWITCH_DEW_A: usize = 3;
const SIM_SWITCH_DEW_B: usize = 4;
const SIM_SWITCH_VOLTAGE: usize = 5;
const SIM_SWITCH_CURRENT: usize = 6;

/// One channel of the simulated powerbox.
#[flutter_rust_bridge::frb(ignore)]
struct SimSwitchChannel {
    name: &'static str,
    description: &'static str,
    min: f64,
    max: f64,
    /// Resolution the controller can actually produce. A commanded value is
    /// quantised to this, because a real DAC/PWM register cannot hold 30.7 %.
    step: f64,
    writable: bool,
    value: f64,
    /// A commanded value that has not yet appeared in the device's telemetry.
    pending: Option<(f64, Instant)>,
}

impl SimSwitchChannel {
    /// Apply any commanded change that has had time to land, then report the
    /// value a read sees now.
    fn settle(&mut self) -> f64 {
        if let Some((value, at)) = self.pending {
            if at.elapsed().as_secs_f64() >= SIM_SWITCH_SETTLE_SECS {
                self.value = value;
                self.pending = None;
            }
        }
        self.value
    }

    fn quantise(&self, value: f64) -> f64 {
        if self.step <= 0.0 {
            return value;
        }
        self.min + ((value - self.min) / self.step).round() * self.step
    }
}

/// ASCOM `ISwitchV2` boolean projection: a multi-state switch reads `true` when
/// its value sits in the upper half of its range.
///
/// This coupling is not cosmetic. A dew heater set to 30 % reads back as
/// `false`, so an app that remembers "I turned it on" instead of re-reading the
/// device will disagree with the hardware — and against a simulator that kept
/// an independent boolean, it never would.
fn sim_switch_value_as_bool(value: f64, min: f64, max: f64) -> bool {
    value - min >= (max - min) / 2.0
}

/// Backing state for the switch simulator.
///
/// Shaped after a Pegasus Astro Ultimate Powerbox — switched outputs, PWM dew
/// channels, and read-only voltage/current sensors — because that is what a
/// switch device on this app actually is. The read-only channels are the point:
/// with every channel writable, `CanWrite == false` and the UI's read-only
/// rendering could never be exercised without hardware.
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct SimulatedSwitch {
    pub connected: bool,
    channels: Vec<SimSwitchChannel>,
}

impl Default for SimulatedSwitch {
    fn default() -> Self {
        Self {
            connected: false,
            channels: vec![
                SimSwitchChannel {
                    name: "Quad 12V Output",
                    description: "Switched 12 V bank (mount, camera, focuser)",
                    min: 0.0,
                    max: 1.0,
                    step: 1.0,
                    writable: true,
                    value: 1.0,
                    pending: None,
                },
                SimSwitchChannel {
                    name: "DSLR Output",
                    description: "Switched auxiliary 12 V output",
                    min: 0.0,
                    max: 1.0,
                    step: 1.0,
                    writable: true,
                    value: 0.0,
                    pending: None,
                },
                SimSwitchChannel {
                    name: "Adjustable Output",
                    description: "Variable output, volts",
                    min: 3.0,
                    max: 12.0,
                    step: 1.0,
                    writable: true,
                    value: 12.0,
                    pending: None,
                },
                SimSwitchChannel {
                    name: "Dew Heater A",
                    description: "Dew heater duty cycle, percent",
                    min: 0.0,
                    max: 100.0,
                    step: 1.0,
                    writable: true,
                    value: 0.0,
                    pending: None,
                },
                SimSwitchChannel {
                    name: "Dew Heater B",
                    description: "Dew heater duty cycle, percent",
                    min: 0.0,
                    max: 100.0,
                    step: 1.0,
                    writable: true,
                    value: 0.0,
                    pending: None,
                },
                SimSwitchChannel {
                    name: "Input Voltage",
                    description: "Supply voltage, volts (read-only sensor)",
                    min: 0.0,
                    max: 15.0,
                    step: 0.1,
                    writable: false,
                    value: SIM_SWITCH_SUPPLY_VOLTS,
                    pending: None,
                },
                SimSwitchChannel {
                    name: "Total Current",
                    description: "Total draw, amps (read-only sensor)",
                    min: 0.0,
                    max: 20.0,
                    step: 0.1,
                    writable: false,
                    value: SIM_SWITCH_QUIESCENT_AMPS,
                    pending: None,
                },
            ],
        }
    }
}

impl SimulatedSwitch {
    fn require_connected(&self) -> Result<(), SimDeviceError> {
        if self.connected {
            return Ok(());
        }
        Err(SimDeviceError::NotConnected(
            "Simulator switch is not connected. Call connect_device first.".to_string(),
        ))
    }

    /// Resolve a caller-supplied switch id.
    ///
    /// Out of range is an error, not a clamp: ASCOM raises
    /// `InvalidValueException` for an id outside `0..MaxSwitch`, and an app that
    /// iterates one too far has an off-by-one that a clamping simulator would
    /// swallow.
    fn index_of(&self, switch_id: i32) -> Result<usize, SimDeviceError> {
        usize::try_from(switch_id)
            .ok()
            .filter(|i| *i < self.channels.len())
            .ok_or_else(|| {
                SimDeviceError::InvalidParameter(format!(
                    "Switch index {} is out of range for the simulated switch (0-{})",
                    switch_id,
                    self.channels.len() - 1
                ))
            })
    }

    /// Settle every channel and recompute the derived sensors.
    ///
    /// Voltage and current are DERIVED from what is switched on rather than
    /// stored, for the same reason the mount's altitude is derived from its
    /// RA/Dec: a stored constant is a reading that never responds to anything
    /// the app does, so a power dashboard wired to nothing still looks alive.
    fn advance(&mut self) {
        for channel in &mut self.channels {
            channel.settle();
        }

        let bool_at = |i: usize| {
            let c = &self.channels[i];
            sim_switch_value_as_bool(c.value, c.min, c.max)
        };
        let mut amps = SIM_SWITCH_QUIESCENT_AMPS;
        if bool_at(SIM_SWITCH_QUAD) {
            amps += SIM_SWITCH_QUAD_AMPS;
        }
        if bool_at(SIM_SWITCH_DSLR) {
            amps += SIM_SWITCH_DSLR_AMPS;
        }
        amps += (self.channels[SIM_SWITCH_DEW_A].value + self.channels[SIM_SWITCH_DEW_B].value)
            * SIM_SWITCH_DEW_AMPS_PER_PERCENT;

        self.channels[SIM_SWITCH_CURRENT].value = amps;
        self.channels[SIM_SWITCH_VOLTAGE].value =
            SIM_SWITCH_SUPPLY_VOLTS - amps * SIM_SWITCH_SAG_VOLTS_PER_AMP;
    }
}

pub(crate) static SIM_SWITCH: OnceLock<Arc<RwLock<SimulatedSwitch>>> = OnceLock::new();

pub(crate) fn get_sim_switch() -> &'static Arc<RwLock<SimulatedSwitch>> {
    SIM_SWITCH.get_or_init(|| Arc::new(RwLock::new(SimulatedSwitch::default())))
}

/// Return the powerbox to its power-on state; see
/// [`reset_sim_cover_calibrator`] for why a process-global singleton needs one.
#[cfg(test)]
pub(crate) async fn reset_sim_switch() {
    *get_sim_switch().write().await = SimulatedSwitch::default();
}

/// One switch channel as a caller sees it.
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct SimSwitchReading {
    pub name: String,
    pub description: String,
    pub value: f64,
    pub state: bool,
    pub min: f64,
    pub max: f64,
    pub writable: bool,
}

/// Number of channels the simulated switch device exposes.
pub(crate) async fn sim_switch_count() -> Result<i32, SimDeviceError> {
    sim_fault("switch.status").await?;
    let sw = get_sim_switch().read().await;
    sw.require_connected()?;
    // Why: channel count is a fixed, single-digit literal in `Default`.
    Ok(i32::try_from(sw.channels.len()).unwrap_or(i32::MAX))
}

/// Read one channel.
pub(crate) async fn sim_switch_read(switch_id: i32) -> Result<SimSwitchReading, SimDeviceError> {
    sim_fault("switch.status").await?;
    let mut sw = get_sim_switch().write().await;
    sw.require_connected()?;
    let index = sw.index_of(switch_id)?;
    sw.advance();
    let channel = &sw.channels[index];
    Ok(SimSwitchReading {
        name: channel.name.to_string(),
        description: channel.description.to_string(),
        value: channel.value,
        state: sim_switch_value_as_bool(channel.value, channel.min, channel.max),
        min: channel.min,
        max: channel.max,
        writable: channel.writable,
    })
}

/// What a caller asked a channel to become.
enum SimSwitchCommand {
    /// A numeric value, validated against the channel's own range.
    Value(f64),
    /// On or off. ASCOM defines these in terms of the numeric value — `true`
    /// drives the channel to its maximum and `false` to its minimum — so both
    /// commands land in the same place rather than a boolean living beside the
    /// value and drifting out of agreement with it.
    State(bool),
}

async fn sim_switch_apply(switch_id: i32, command: SimSwitchCommand) -> Result<(), SimDeviceError> {
    let mut sw = get_sim_switch().write().await;
    sw.require_connected()?;
    let index = sw.index_of(switch_id)?;
    sw.advance();

    let channel = &mut sw.channels[index];
    if !channel.writable {
        return Err(SimDeviceError::InvalidParameter(format!(
            "Switch '{}' is a read-only sensor and cannot be set",
            channel.name
        )));
    }

    let value = match command {
        SimSwitchCommand::Value(value) => value,
        SimSwitchCommand::State(true) => channel.max,
        SimSwitchCommand::State(false) => channel.min,
    };
    if !value.is_finite() || value < channel.min || value > channel.max {
        return Err(SimDeviceError::InvalidParameter(format!(
            "Value {} is outside switch '{}' range {}-{}",
            value, channel.name, channel.min, channel.max
        )));
    }

    // The write is accepted now and observable later; see SIM_SWITCH_SETTLE_SECS.
    let landed = channel.quantise(value);
    channel.pending = Some((landed, Instant::now()));
    Ok(())
}

/// Command a channel's numeric value.
pub(crate) async fn sim_switch_write_value(
    switch_id: i32,
    value: f64,
) -> Result<(), SimDeviceError> {
    sim_fault("switch.command").await?;
    sim_switch_apply(switch_id, SimSwitchCommand::Value(value)).await
}

/// Command a channel on or off.
pub(crate) async fn sim_switch_write_state(
    switch_id: i32,
    state: bool,
) -> Result<(), SimDeviceError> {
    sim_fault("switch.command").await?;
    sim_switch_apply(switch_id, SimSwitchCommand::State(state)).await
}

#[cfg(test)]
mod sim_motion_tests {
    use super::*;

    /// Successive frames must draw different noise, and the sequence must be
    /// resettable so a run can be reproduced exactly.
    #[test]
    fn frame_seed_sequence_is_reproducible_after_reset() {
        reset_sim_frame_seed(100);
        let first: Vec<u64> = (0..3).map(|_| next_sim_frame_seed()).collect();
        reset_sim_frame_seed(100);
        let second: Vec<u64> = (0..3).map(|_| next_sim_frame_seed()).collect();

        assert_eq!(first, second, "a reset seed must replay the same sequence");
        assert_eq!(
            first.len(),
            first.iter().collect::<std::collections::HashSet<_>>().len(),
            "successive frames must not reuse a seed, or a stack is identical frames"
        );
    }

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

    /// Register and connect a simulated mount in the process-wide DeviceManager,
    /// the way discovery plus a connect does for a real one.
    async fn attach_sim_mount(device_id: &str) {
        let info = DeviceInfo {
            id: device_id.to_string(),
            name: "Simulated Mount".to_string(),
            device_type: DeviceType::Mount,
            driver_type: DriverType::Simulator,
            description: "Simulated mount".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Simulated Mount".to_string(),
        };
        get_device_manager().register_device(info, false).await;
        get_sim_mount().write().await.status.connected = true;
    }

    /// A manual guide nudge must move the field, not just sleep: it silently
    /// regressed to a no-op once before, returning "ok" and leaving the stars
    /// where they were.
    #[tokio::test]
    async fn api_pulse_guide_moves_the_simulated_field() {
        let _serialized = sim_singleton_test_lock().lock().await;
        attach_sim_mount("sim_mount_pulse").await;
        reset_sim_guide_offset().await;
        let before = *sim_guide_offset().read().await;
        api_mount_pulse_guide("sim_mount_pulse".to_string(), "east".to_string(), 1000)
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

    /// An unknown direction must be rejected rather than silently sleeping —
    /// and rejected for THAT reason, not because the device was missing.
    #[tokio::test]
    async fn api_pulse_guide_rejects_an_unknown_direction() {
        attach_sim_mount("sim_mount_direction").await;
        let result = api_mount_pulse_guide(
            "sim_mount_direction".to_string(),
            "widdershins".to_string(),
            10,
        )
        .await;
        let err = result.expect_err("unknown direction should be an error");
        assert!(
            err.to_string().contains("direction: widdershins"),
            "expected a direction rejection, got: {err}"
        );
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
        let _serialized = sim_singleton_test_lock().lock().await;
        clear_sim_exposure().await;
        assert!(
            sim_exposure_is_complete().await,
            "an idle simulator must not make a poller wait"
        );

        begin_sim_exposure(SimExposureRequest {
            secs: 30.0,
            ..Default::default()
        })
        .await;
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
