//! Built-in multi-star guider.
//!
//! # `as`-cast policy
//!
//! - **Timing nanoseconds u128 → f64** (line 361): wall-clock elapsed in
//!   nanoseconds; f64 holds nanosecond precision for ~104 days of
//!   monotonic elapsed time, far longer than any guiding session.
//! - **u32 image coords → f64** (lines 438, 439, 1142, 1143, 1165, 1166):
//!   exact widening; pixel coordinates are bounded by sensor size.
//! - **Calibration ms u32 → f64** (line 813): exact widening; pulse width
//!   ≤ a few thousand ms in practice.
//! - **Rounded f64 → u32 frame rate** (line 943): bounded by FPS measured
//!   over the calibration window; reasonable values ≤ thousands.
//! - **Crop / sensor i32/u32 box math** (lines 1112-1166): every cast is
//!   either i32 → u32 after explicit `>= 0` clamps (x_start/y_start are
//!   bounded by `max(0)`) or u32 → usize widening for indexing. Per-pixel
//!   index `((y * width + x) * 2) as usize` is bounded by the buffer
//!   length we then `<` -check against `expected_data_len`.
//!
//! Sites with a local `Why:` comment override the module-level reasoning.
//!
//! # `unwrap_or` policy
//!
//! * `unwrap_or(Ordering::Equal)` — required because `f64::partial_cmp`
//!   returns `Option` (NaN handling). Star detection upstream filters NaN
//!   centroids; the fallback only protects the sort from a malformed
//!   `StarMass`/`StarSnr` produced by a misbehaving SDK.
//! * `unwrap_or(0.0)` on selected star SNR/flux — when no star is currently
//!   tracked (between frames, or before lock acquisition), the public
//!   status struct reports `snr = 0.0, star_mass = 0.0`. The UI's "guiding
//!   inactive" badge keys off `selected.is_none()`, not these numbers, so
//!   the zero is a display-only convention.
//! * `unwrap_or(1)` (frame width when image-format probe absent) — falls
//!   through to the post-validation pipeline; 1×1 image immediately fails
//!   star detection with a real `NoStarsDetected` error.
//! * `unwrap_or_default()` on profile-name lookup — guider profile may not
//!   yet exist on first run; empty name flows through to default config.
use crate::api::{get_device_manager, get_state, Phd2StarImage, Phd2Status};
use crate::device::DeviceType;
use crate::error::NightshadeError;
use crate::event::{EventSeverity, GuidingEvent};
use nightshade_imaging::{detect_stars_with_stats, DetectedStar, ImageData, StarDetectionConfig};
use serde::Serialize;
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::{Mutex, RwLock};
use tokio::task::JoinHandle;

const BUILTIN_GUIDER_ID: &str = "native:builtin_guider:multi_star";
const GUIDE_MAX_MATCH_DISTANCE_PX: f64 = 20.0;
/// Up to this many guide stars are tracked per frame. Raised from 8 to 12 so the
/// sigma-clipped weighted centroid (see [`measure_offset`]) has enough samples
/// to drop one or two outliers and still average over a healthy set.
const GUIDE_MAX_TRACKED_STARS: usize = 12;
const GUIDE_MIN_STAR_SEPARATION_PX: f64 = 10.0;
/// A tracked star whose centroid lands within this many pixels of the frame edge
/// is rejected at selection time: stars partially off-sensor have biased
/// centroids and are the first to vanish under field rotation.
const GUIDE_EDGE_MARGIN_PX: f64 = 12.0;
/// Stars dimmer than this SNR are not used as guide references — too noisy to
/// contribute a reliable per-star displacement.
const GUIDE_MIN_REFERENCE_SNR: f64 = 6.0;
/// Stars rounder-than-this (eccentricity) are preferred; above this they are
/// rejected because an elongated detection (blended pair / hot column) gives a
/// centroid that walks with seeing rather than with the mount.
const GUIDE_MAX_REFERENCE_ECCENTRICITY: f64 = 0.6;
/// Peak ADU at/above which a star is treated as saturated and rejected: a
/// clipped core flattens the centroid and biases the displacement toward zero.
const GUIDE_SATURATION_PEAK_ADU: f64 = 60000.0;
/// Sigma multiplier for the robust (sigma-clipped) offset: per-star
/// displacements more than this many MADs from the median are dropped as
/// outliers (a star that jumped — cloud edge, cosmic ray, misassociation).
const GUIDE_OUTLIER_SIGMA: f64 = 2.5;
/// Below this many surviving stars the robust centroid is not trustworthy; the
/// guider falls back to the plain weighted mean over whatever matched.
const GUIDE_MIN_STARS_FOR_CLIP: usize = 4;
/// 1.4826 * MAD ≈ standard deviation for a normal distribution. Used to scale
/// the median-absolute-deviation into a sigma-equivalent for outlier rejection.
const MAD_TO_SIGMA: f64 = 1.4826;

/// Configurable parameters for the built-in guider.
///
/// All fields have sensible defaults matching the original hardcoded values.
#[derive(Clone, Debug)]
pub struct GuiderConfig {
    /// Guide camera exposure time in seconds
    pub exposure_secs: f64,
    /// Guide camera gain
    pub gain: i32,
    /// Guide camera offset
    pub offset: i32,
    /// Guide camera binning
    pub binning: i32,
    /// Calibration pulse duration in milliseconds
    pub calibration_ms: u32,
    /// Sleep between settle checks in milliseconds
    pub settle_sleep_ms: u64,
    /// Minimum guide pulse length in milliseconds (pulses smaller than this are skipped)
    pub min_pulse_ms: f64,
    /// Maximum guide pulse length in milliseconds (pulses are clamped to this)
    pub max_pulse_ms: f64,
    /// RA correction aggressiveness (0..1+). Each computed RA pulse is scaled by
    /// this before clamping. 1.0 = full correction; lower values damp chasing
    /// seeing. Defaults to a slightly conservative value.
    pub ra_aggressiveness: f64,
    /// Dec correction aggressiveness (0..1+). Dec is usually run softer than RA
    /// because it only fights drift and is the axis with backlash.
    pub dec_aggressiveness: f64,
    /// Minimum guide displacement (pixels) below which no correction is issued.
    /// Avoids chasing centroid noise frame-to-frame.
    pub min_move_px: f64,
}

impl Default for GuiderConfig {
    fn default() -> Self {
        Self {
            exposure_secs: 1.0,
            gain: 100,
            offset: 10,
            binning: 1,
            calibration_ms: 250,
            settle_sleep_ms: 200,
            min_pulse_ms: 75.0,
            max_pulse_ms: 1200.0,
            ra_aggressiveness: 0.7,
            dec_aggressiveness: 0.6,
            min_move_px: 0.15,
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct Vec2 {
    x: f64,
    y: f64,
}

impl Vec2 {
    fn magnitude(self) -> f64 {
        (self.x * self.x + self.y * self.y).sqrt()
    }
}

#[derive(Clone, Debug)]
struct GuideReferenceStar {
    x: f64,
    y: f64,
    flux: f64,
    snr: f64,
    /// Per-star residual against this reference's expected position on the most
    /// recent matched frame, in pixels. `None` until the star is matched at
    /// least once (e.g. immediately after `select_reference_stars`). Populated
    /// by [`measure_offset`] each guide frame so the per-star UI can show how
    /// far each tracked star drifted, not just the aggregate centroid offset.
    last_residual: Option<Vec2>,
}

#[derive(Clone, Copy, Debug)]
struct GuideCalibration {
    /// Measured pixel displacement produced by one `pulse_ms` pulse on the RA+
    /// (east) axis. Direction encodes the RA axis angle; magnitude/`pulse_ms`
    /// gives the RA rate (px/ms).
    east: Vec2,
    /// Measured pixel displacement produced by one `pulse_ms` pulse on the Dec+
    /// (north) axis.
    north: Vec2,
    pulse_ms: f64,
    /// Dec backlash, in pulse-milliseconds: the dead-band the Dec gear takes up
    /// on the first pulse after a direction reversal. Measured during
    /// calibration as the shortfall of the first reverse pulse versus the
    /// established forward rate. 0 when no backlash was detected.
    dec_backlash_ms: f64,
    /// Angle between the measured RA and Dec axes, in degrees. A healthy mount is
    /// near 90°; large departures are logged as a calibration-quality warning but
    /// do not block guiding (the full 2×2 solve still applies).
    orthogonality_deg: f64,
}

impl GuideCalibration {
    /// RA rate in pixels per millisecond (magnitude of the east response per ms).
    fn ra_rate(&self) -> f64 {
        if self.pulse_ms > 0.0 {
            self.east.magnitude() / self.pulse_ms
        } else {
            0.0
        }
    }

    /// Dec rate in pixels per millisecond.
    fn dec_rate(&self) -> f64 {
        if self.pulse_ms > 0.0 {
            self.north.magnitude() / self.pulse_ms
        } else {
            0.0
        }
    }
}

/// Which way Dec was last commanded, so the next correction can pay the backlash
/// dead-band exactly once on a reversal (not every Dec pulse).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum DecDirection {
    North,
    South,
}

#[derive(Clone, Debug)]
struct GuideFrame {
    frame: u32,
    image: ImageData,
    stars: Vec<DetectedStar>,
}

#[derive(Clone, Debug)]
struct GuideSnapshot {
    frame: u32,
    width: u32,
    height: u32,
    pixels: Vec<u8>,
    crop_origin_x: i32,
    crop_origin_y: i32,
    star_x: f64,
    star_y: f64,
}

#[derive(Clone, Debug)]
pub struct BuiltinGuideStatus {
    pub connected: bool,
    pub state: String,
    pub rms_ra: f64,
    pub rms_dec: f64,
    pub rms_total: f64,
    pub snr: f64,
    pub star_mass: f64,
    pub pixel_scale: f64,
}

impl Default for BuiltinGuideStatus {
    fn default() -> Self {
        Self {
            connected: false,
            state: "Disconnected".to_string(),
            rms_ra: 0.0,
            rms_dec: 0.0,
            rms_total: 0.0,
            snr: 0.0,
            star_mass: 0.0,
            pixel_scale: 0.0,
        }
    }
}

// =============================================================================
// Per-star tracked-star export (Phase F, guider-ui)
//
// The built-in guider tracks up to `GUIDE_MAX_TRACKED_STARS` reference stars,
// but `get_status()` only returns the PHD2-shaped *aggregate* `Phd2Status`
// (rms/snr/star_mass), so the 8 tracked stars never reached the Dart UI and its
// star-list panel rendered empty.
//
// These DTOs surface the per-star list. They are `#[frb(ignore)]` and serialize
// to a JSON *string* so they ride alongside the existing guiding-status path
// without changing any flutter_rust_bridge-generated struct shape (no regen).
// The same `*_json: String` convention is used by the typed event payloads in
// `event.rs` (FRB does not bridge `serde_json::Value` directly).
// =============================================================================

/// One tracked reference star, as surfaced to the per-star guider UI.
#[flutter_rust_bridge::frb(ignore)]
#[derive(Clone, Debug, Serialize)]
pub struct BuiltinGuideTrackedStar {
    /// Stable index within the tracked-star list (0-based), used by the UI as
    /// the per-star identity / lock-star key.
    pub id: usize,
    /// Centroid X in guide-camera pixels.
    pub x: f64,
    /// Centroid Y in guide-camera pixels.
    pub y: f64,
    /// Integrated flux (star mass / brightness).
    pub flux: f64,
    /// Signal-to-noise ratio.
    pub snr: f64,
    /// Whether this is the active lock star (the centroid the corrections key
    /// off). `None` when no lock has been established yet.
    pub is_lock: bool,
    /// Per-star residual magnitude (pixels) on the most recent matched frame, or
    /// `None` before the star has been matched at least once.
    pub residual: Option<f64>,
    /// Relative weight this star carries in the sigma-clipped weighted centroid
    /// (flux/SNR derived). Higher means a brighter, cleaner star that pulls the
    /// aggregate offset harder. Surfaced so the UI can show contribution.
    pub weight: f64,
}

/// Per-star tracked-star snapshot. Serialized to JSON and exposed through the
/// guiding-status path so the Dart guider UI can populate its star list + feed
/// the same `CompactGuidingGraph` the PHD2 path uses.
#[flutter_rust_bridge::frb(ignore)]
#[derive(Clone, Debug, Serialize, Default)]
pub struct BuiltinGuideTrackedStars {
    /// Number of stars currently tracked (mirrors `stars.len()`; convenience for
    /// consumers that only need the count).
    pub count: usize,
    /// The tracked reference stars, brightest-first as selected.
    pub stars: Vec<BuiltinGuideTrackedStar>,
}

/// Build the per-star tracked-star DTO from the current reference-star set.
///
/// The lock star is the reference nearest the active manual lock position (the
/// centroid the guider corrects to); ties fall back to the first/brightest star
/// when no lock has been set.
#[flutter_rust_bridge::frb(ignore)]
fn build_tracked_stars(state: &BuiltinGuiderState) -> BuiltinGuideTrackedStars {
    let lock = state.manual_lock;
    // Choose the lock-star index: the reference closest to the manual lock.
    let lock_index = lock.and_then(|target| {
        state
            .reference_stars
            .iter()
            .enumerate()
            .map(|(i, r)| {
                let dx = r.x - target.x;
                let dy = r.y - target.y;
                (i, (dx * dx + dy * dy).sqrt())
            })
            .min_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(i, _)| i)
    });

    let stars = state
        .reference_stars
        .iter()
        .enumerate()
        .map(|(i, r)| BuiltinGuideTrackedStar {
            id: i,
            x: r.x,
            y: r.y,
            flux: r.flux,
            snr: r.snr,
            is_lock: Some(i) == lock_index,
            residual: r.last_residual.map(|v| v.magnitude()),
            weight: guide_reference_weight(r),
        })
        .collect::<Vec<_>>();

    BuiltinGuideTrackedStars {
        count: stars.len(),
        stars,
    }
}

/// Per-star tracked-star list, serialized to a JSON string.
///
/// `#[frb(ignore)]` so it never touches the generated bridge: the JSON rides
/// through the existing guiding-status network path (the headless API embeds it
/// as a `trackedStars` array) where the Dart `Phd2Status`/`GuideStar` models
/// decode it. Returns `{"count":0,"stars":[]}` when nothing is tracked.
#[flutter_rust_bridge::frb(ignore)]
pub async fn get_tracked_stars_json() -> String {
    let guard = state().read().await;
    let dto = build_tracked_stars(&guard);
    serde_json::to_string(&dto).unwrap_or_else(|_| "{\"count\":0,\"stars\":[]}".to_string())
}

struct BuiltinGuiderState {
    connected: bool,
    guiding: bool,
    looping: bool,
    calibrating: bool,
    camera_id: Option<String>,
    mount_id: Option<String>,
    reference_stars: Vec<GuideReferenceStar>,
    manual_lock: Option<Vec2>,
    desired_offset: Vec2,
    calibration: Option<GuideCalibration>,
    last_frame: Option<GuideFrame>,
    last_snapshot: Option<GuideSnapshot>,
    last_status: BuiltinGuideStatus,
    settle_deadline: Option<Instant>,
    /// Absolute deadline after which settling is considered failed
    settle_timeout_deadline: Option<Instant>,
    dither_pending: bool,
    /// Last Dec direction actually pulsed, used to apply backlash compensation
    /// exactly on a reversal. `None` until the first Dec correction.
    last_dec_direction: Option<DecDirection>,
    /// Monotonic dither step count, advancing the spiral pattern so successive
    /// dithers walk to fresh pixels instead of re-treading the same ones.
    dither_step: u32,
    /// Recent per-frame total RMS (pixels), newest last, capped in length. Drives
    /// adaptive dither settle tolerance (poorer seeing -> looser settle).
    rms_history: Vec<f64>,
    stop_flag: Option<Arc<std::sync::atomic::AtomicBool>>,
    task: Option<JoinHandle<()>>,
    config: GuiderConfig,
}

impl Default for BuiltinGuiderState {
    fn default() -> Self {
        Self {
            connected: false,
            guiding: false,
            looping: false,
            calibrating: false,
            camera_id: None,
            mount_id: None,
            reference_stars: Vec::new(),
            manual_lock: None,
            desired_offset: Vec2::default(),
            calibration: None,
            last_frame: None,
            last_snapshot: None,
            last_status: BuiltinGuideStatus::default(),
            settle_deadline: None,
            settle_timeout_deadline: None,
            dither_pending: false,
            last_dec_direction: None,
            dither_step: 0,
            rms_history: Vec::new(),
            stop_flag: None,
            task: None,
            config: GuiderConfig::default(),
        }
    }
}

/// Maximum number of recent RMS samples retained for adaptive dither.
const RMS_HISTORY_LEN: usize = 20;

static BUILTIN_GUIDER: OnceLock<Arc<RwLock<BuiltinGuiderState>>> = OnceLock::new();

fn state() -> &'static Arc<RwLock<BuiltinGuiderState>> {
    BUILTIN_GUIDER.get_or_init(|| Arc::new(RwLock::new(BuiltinGuiderState::default())))
}

/// Serializes the loop-lifecycle entry points (`start_guiding`, `loop_exposures`,
/// `stop`, `disconnect`) so a start and a concurrent stop can never interleave.
///
/// The per-operation `state()` write-lock is released between "set guiding=true"
/// and "spawn the loop", so it alone cannot make start/stop atomic. Without this
/// mutex a `stop()` landing in the window after the loop is spawned but before its
/// `JoinHandle`/`stop_flag` is recorded would take `None`, signal nothing, return
/// Ok, and orphan a mount-pulsing loop (v4 review blocker #7). Holding this mutex
/// across the whole start (lock → spawn → record handle) and the whole stop
/// guarantees stop always observes a live loop and cancels it.
static GUIDER_OP_LOCK: OnceLock<Arc<Mutex<()>>> = OnceLock::new();

fn op_lock() -> &'static Arc<Mutex<()>> {
    GUIDER_OP_LOCK.get_or_init(|| Arc::new(Mutex::new(())))
}

/// Set the guider configuration. Must be called before `connect()` or will apply
/// to subsequent operations. Calling while guiding is active will update the config
/// for future frames.
pub async fn set_config(config: GuiderConfig) {
    state().write().await.config = config;
}

/// Get the current guider configuration.
pub async fn get_config() -> GuiderConfig {
    state().read().await.config.clone()
}

pub async fn connect() -> Result<(), NightshadeError> {
    let (camera_id, mount_id) = resolve_devices().await?;
    let mut guard = state().write().await;
    guard.connected = true;
    guard.camera_id = Some(camera_id);
    guard.mount_id = Some(mount_id);
    guard.last_status = BuiltinGuideStatus {
        connected: true,
        state: "Connected".to_string(),
        ..BuiltinGuideStatus::default()
    };
    Ok(())
}

pub async fn disconnect() -> Result<(), NightshadeError> {
    // Serialize against start/stop so disconnect cannot race a loop spawn.
    let _op = op_lock().lock().await;
    stop_locked().await?;
    let mut guard = state().write().await;
    *guard = BuiltinGuiderState::default();
    Ok(())
}

pub async fn start_guiding(
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    ensure_connected().await?;
    // Hold the op-lock across the ENTIRE start (stop-previous → set guiding=true
    // → spawn loop → record handle). This is what makes start atomic with respect
    // to a concurrent `stop()`: a stop cannot land in the window between the loop
    // being spawned and its handle being recorded, so it can never observe `None`
    // and orphan a live mount-pulsing loop (v4 review blocker #7).
    let _op = op_lock().lock().await;
    stop_locked().await?;

    begin_loop(
        |guard| {
            guard.guiding = true;
            guard.looping = false;
            guard.calibrating = true;
            guard.last_status.state = "Calibrating".to_string();
            guard.last_status.connected = true;
        },
        GuidingEvent::Calibrating,
        move |controller, stop_flag_for_task| async move {
            if let Err(error) = run_guiding_loop(
                controller.clone(),
                stop_flag_for_task,
                settle_pixels,
                settle_time,
                settle_timeout,
            )
            .await
            {
                tracing::error!("Built-in guider task failed: {}", error);
                let mut guard = controller.write().await;
                guard.guiding = false;
                guard.looping = false;
                guard.calibrating = false;
                guard.last_status.state = "Disconnected".to_string();
                get_state()
                    .publish_guiding_event(GuidingEvent::Disconnected, EventSeverity::Warning);
            }
        },
    )
    .await;
    Ok(())
}

pub async fn loop_exposures() -> Result<(), NightshadeError> {
    ensure_connected().await?;
    // See `start_guiding` for why the op-lock is held across the whole operation.
    let _op = op_lock().lock().await;
    stop_locked().await?;

    begin_loop(
        |guard| {
            guard.guiding = false;
            guard.looping = true;
            guard.calibrating = false;
            guard.last_status.state = "Looping".to_string();
            guard.last_status.connected = true;
        },
        GuidingEvent::Looping,
        |controller, stop_flag_for_task| async move {
            loop {
                if stop_flag_for_task.load(std::sync::atomic::Ordering::Relaxed) {
                    break;
                }
                if let Err(error) = capture_and_store_loop_frame(controller.clone()).await {
                    tracing::warn!("Built-in guider looping frame failed: {}", error);
                    tokio::time::sleep(Duration::from_millis(500)).await;
                }
            }
        },
    )
    .await;
    Ok(())
}

/// Shared start path for `start_guiding`/`loop_exposures`. The caller MUST already
/// hold the [`op_lock`] and have torn down any previous loop via `stop_locked()`.
///
/// The atomicity guarantee for the start/stop race (v4 review blocker #7) lives
/// here: the stop flag is created and stored into state inside the SAME write-lock
/// critical section that flips `guiding`/`looping`, BEFORE the loop is spawned, so
/// the invariant "an active loop always has a live `stop_flag` in state" holds for
/// the entire lifetime of the loop. Because the caller holds the op-lock for the
/// whole start, no `stop()` can interleave between spawning the loop and recording
/// its `JoinHandle`.
async fn begin_loop<S, F, Fut>(set_state: S, event: GuidingEvent, make_loop: F)
where
    S: FnOnce(&mut BuiltinGuiderState),
    F: FnOnce(Arc<RwLock<BuiltinGuiderState>>, Arc<std::sync::atomic::AtomicBool>) -> Fut,
    Fut: std::future::Future<Output = ()> + Send + 'static,
{
    let stop_flag = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let stop_flag_for_task = stop_flag.clone();
    {
        let mut guard = state().write().await;
        set_state(&mut guard);
        // Store the stop flag together with the run-state flip so `stop()` always
        // observes a live flag for an active loop. The previous handle was already
        // joined by the caller's `stop_locked()`.
        guard.stop_flag = Some(stop_flag);
        guard.task = None;
    }

    get_state().publish_guiding_event(event, EventSeverity::Info);

    let controller = state().clone();
    let task = tokio::spawn(make_loop(controller, stop_flag_for_task));

    // Safe under the op-lock: no concurrent stop can have run since we set
    // `stop_flag`, so recording the handle cannot resurrect a torn-down loop.
    state().write().await.task = Some(task);
}

/// Test-only: start a synthetic loop through the real lifecycle machinery
/// (`op_lock` + `stop_locked` + `begin_loop`). The loop holds no hardware. While
/// alive it keeps `live_loops` incremented (decremented on exit), so a test can
/// detect ANY orphaned loop — including one stranded when a later start overwrote
/// its handle, which is exactly how the pre-fix race permanently lost the stop
/// signal. Returns once the loop is registered, like the real `start_guiding`.
#[cfg(test)]
async fn start_synthetic_loop(live_loops: Arc<std::sync::atomic::AtomicUsize>) {
    let _op = op_lock().lock().await;
    let _ = stop_locked().await;
    begin_loop(
        |guard| {
            guard.guiding = true;
            guard.looping = false;
            guard.calibrating = true;
        },
        GuidingEvent::Calibrating,
        move |_controller, stop_flag_for_task| async move {
            live_loops.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            // Mirror the real loops: exit only when the stop flag is set. An
            // orphaned loop (stop signal lost / handle overwritten) keeps the
            // live-loop count above zero forever.
            while !stop_flag_for_task.load(std::sync::atomic::Ordering::Relaxed) {
                tokio::time::sleep(Duration::from_millis(1)).await;
            }
            live_loops.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
        },
    )
    .await;
}

pub async fn stop() -> Result<(), NightshadeError> {
    // Serialize against start so a stop landing mid-start still observes (and
    // cancels) the live loop rather than racing the handle/flag bookkeeping.
    let _op = op_lock().lock().await;
    stop_locked().await
}

/// Stop the active loop. The caller MUST already hold the [`op_lock`]; this is the
/// shared body used by `stop`, `start_guiding`, `loop_exposures`, and `disconnect`
/// so the lifecycle entry points cannot interleave.
async fn stop_locked() -> Result<(), NightshadeError> {
    let (stop_flag, task) = {
        let mut guard = state().write().await;
        guard.guiding = false;
        guard.looping = false;
        guard.calibrating = false;
        guard.reference_stars.clear();
        guard.desired_offset = Vec2::default();
        guard.settle_deadline = None;
        guard.settle_timeout_deadline = None;
        guard.dither_pending = false;
        guard.last_dec_direction = None;
        guard.rms_history.clear();
        guard.last_status.state = if guard.connected {
            "Connected".to_string()
        } else {
            "Disconnected".to_string()
        };
        (guard.stop_flag.take(), guard.task.take())
    };

    if let Some(flag) = stop_flag {
        flag.store(true, std::sync::atomic::Ordering::Relaxed);
    }
    if let Some(handle) = task {
        let _ = handle.await;
    }

    get_state().publish_guiding_event(GuidingEvent::GuidingStopped, EventSeverity::Info);
    Ok(())
}

/// Golden angle (radians) — successive multiples spread points evenly around the
/// circle without ever repeating, the basis of the sunflower/spiral dither.
const DITHER_GOLDEN_ANGLE: f64 = 2.399_963_229_728_653;

/// Compute the next dither offset.
///
/// Uses a sunflower spiral: step `n`'s angle is `n * golden_angle` and its radius
/// grows as `amount * sqrt(n+1)`, so consecutive dithers land on fresh,
/// non-overlapping pixels rather than re-walking a fixed grid or random jitter
/// around one spot. The radius is additionally scaled up when `recent_rms` shows
/// poor seeing (adaptive: a bigger move stays distinguishable from guiding noise
/// and gives a cleaner settle target). `ra_only` collapses the move to the RA
/// (x) axis with a deterministic sign alternation so it still walks both ways.
fn dither_offset(amount: f64, ra_only: bool, step: u32, recent_rms: Option<f64>) -> Vec2 {
    // Adaptive scale: 1.0 in good seeing, growing with recent RMS up to ~2x.
    let rms = recent_rms.unwrap_or(0.0).max(0.0);
    let adaptive = (1.0 + rms.min(amount.max(1.0)) / amount.max(1.0)).clamp(1.0, 2.0);
    let base = amount * adaptive;

    if ra_only {
        // Alternate sign and grow slowly so repeated RA-only dithers still spread.
        let sign = if step % 2 == 0 { 1.0 } else { -1.0 };
        let radius = base * (1.0 + (step / 2) as f64 * 0.5);
        return Vec2 {
            x: sign * radius,
            y: 0.0,
        };
    }

    let n = step as f64;
    let angle = n * DITHER_GOLDEN_ANGLE;
    let radius = base * (n + 1.0).sqrt();
    Vec2 {
        x: radius * angle.cos(),
        y: radius * angle.sin(),
    }
}

pub async fn dither(
    amount: f64,
    ra_only: bool,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    ensure_connected().await?;

    let timeout_secs = settle_timeout.max(settle_time + 1.0);
    let offset;
    {
        let mut guard = state().write().await;
        // A dither only settles if the guiding loop is actually running to drive
        // `apply_settle_state`; otherwise nothing ever clears `dither_pending`
        // and we would block forever. Fail closed.
        if !guard.guiding {
            return Err(NightshadeError::OperationFailed(
                "Built-in guider dither requires active guiding; not guiding".to_string(),
            ));
        }
        // Spiral step: advance a monotonic counter so each dither walks to fresh
        // pixels instead of re-treading the same spot (a fixed/random small jump
        // re-walks the same neighbourhood). Adaptive: scale by recent RMS so the
        // dither moves further when seeing is poor, keeping it distinguishable
        // from guiding noise.
        let step = guard.dither_step;
        guard.dither_step = step.wrapping_add(1);
        let rms = recent_rms(&guard.rms_history);
        offset = dither_offset(amount, ra_only, step, rms);

        guard.desired_offset = Vec2 {
            x: guard.desired_offset.x + offset.x,
            y: guard.desired_offset.y + offset.y,
        };
        guard.dither_pending = true;
        // Reset settle state and arm the timeout for this dither settle
        guard.settle_deadline = None;
        guard.settle_timeout_deadline =
            Some(Instant::now() + Duration::from_secs_f64(timeout_secs));
        // Store settle params so the guiding loop's apply_settle_state can use them
        // (settle_pixels and settle_time are already threaded through run_guiding_loop)
        let _ = (settle_pixels, settle_time); // used by the guiding loop that's already running
    }
    get_state().publish_guiding_event(
        GuidingEvent::DitherStarted {
            pixels: offset.magnitude(),
        },
        EventSeverity::Info,
    );

    // BLOCK until the guiding loop reports the dither settled, mirroring the
    // PHD2 path. Without this, the sequencer resumed exposing immediately after
    // arming the offset and trailed the sub. Fail closed on settle failure or
    // timeout: the loop clears `dither_pending` (and emits Settled) on success,
    // and on a settle timeout the loop task aborts and clears `guiding`.
    //
    // Bound the wait by the settle timeout plus a grace margin so a stalled
    // loop (no frames arriving) cannot hang the caller indefinitely.
    let deadline = Instant::now() + Duration::from_secs_f64(timeout_secs + 10.0);
    loop {
        {
            let guard = state().read().await;
            if !guard.dither_pending {
                // Cleared by apply_settle_state on a successful settle.
                if guard.guiding {
                    return Ok(());
                }
                // Loop is no longer guiding: the dither settle could not be
                // completed (loop aborted / was stopped). Fail closed.
                return Err(NightshadeError::OperationFailed(
                    "Built-in guider dither did not settle: guiding stopped before settle completed"
                        .to_string(),
                ));
            }
            if !guard.guiding {
                return Err(NightshadeError::OperationFailed(
                    "Built-in guider dither did not settle: guiding loop stopped".to_string(),
                ));
            }
        }
        if Instant::now() >= deadline {
            // Clear the dangling dither flag so a later operation isn't confused.
            let mut guard = state().write().await;
            guard.dither_pending = false;
            guard.settle_deadline = None;
            guard.settle_timeout_deadline = None;
            return Err(NightshadeError::OperationFailed(format!(
                "Built-in guider dither did not settle within {:.0}s",
                timeout_secs + 10.0
            )));
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

pub async fn find_star() -> Result<(f64, f64), NightshadeError> {
    ensure_connected().await?;
    let guide_frame = ensure_frame_available().await?;
    let selected = choose_lock_star(&guide_frame.stars, state().read().await.manual_lock, None)
        .ok_or_else(|| NightshadeError::OperationFailed("No guide star found".to_string()))?;

    let selected_pos = Vec2 {
        x: selected.x,
        y: selected.y,
    };

    let mut guard = state().write().await;
    guard.manual_lock = Some(selected_pos);
    guard.reference_stars = select_reference_stars(
        &guide_frame.stars,
        guide_frame.image.width,
        guide_frame.image.height,
    );
    update_snapshot_from_frame(&mut guard, &guide_frame, 50);
    get_state().publish_guiding_event(
        GuidingEvent::StarSelected {
            x: selected.x,
            y: selected.y,
        },
        EventSeverity::Info,
    );

    if let Some(snapshot) = &guard.last_snapshot {
        Ok((snapshot.star_x, snapshot.star_y))
    } else {
        Ok((selected.x, selected.y))
    }
}

pub async fn deselect_star() -> Result<(), NightshadeError> {
    let mut guard = state().write().await;
    guard.manual_lock = None;
    guard.reference_stars.clear();
    guard.last_snapshot = None;
    Ok(())
}

pub async fn set_lock_position(x: f64, y: f64) -> Result<(), NightshadeError> {
    ensure_connected().await?;
    let guide_frame = ensure_frame_available().await?;

    let target = {
        let guard = state().read().await;
        if let Some(snapshot) = &guard.last_snapshot {
            Vec2 {
                x: snapshot.crop_origin_x as f64 + x,
                y: snapshot.crop_origin_y as f64 + y,
            }
        } else {
            Vec2 { x, y }
        }
    };

    let selected = nearest_star(
        &guide_frame.stars,
        target,
        GUIDE_MAX_MATCH_DISTANCE_PX * 1.5,
    )
    .ok_or_else(|| {
        NightshadeError::OperationFailed("No star near requested lock position".to_string())
    })?;

    let selected_pos = Vec2 {
        x: selected.x,
        y: selected.y,
    };

    let mut guard = state().write().await;
    guard.manual_lock = Some(selected_pos);
    guard.reference_stars = select_reference_stars(
        &guide_frame.stars,
        guide_frame.image.width,
        guide_frame.image.height,
    );
    update_snapshot_from_frame(&mut guard, &guide_frame, 50);
    get_state().publish_guiding_event(
        GuidingEvent::StarSelected {
            x: selected.x,
            y: selected.y,
        },
        EventSeverity::Info,
    );
    Ok(())
}

pub async fn get_lock_position() -> Result<(f64, f64), NightshadeError> {
    let guard = state().read().await;
    if let Some(snapshot) = &guard.last_snapshot {
        return Ok((snapshot.star_x, snapshot.star_y));
    }
    if let Some(lock) = guard.manual_lock {
        return Ok((lock.x, lock.y));
    }
    Err(NightshadeError::OperationFailed(
        "No guide star is selected".to_string(),
    ))
}

pub async fn get_star_image(size: u32) -> Result<Phd2StarImage, NightshadeError> {
    let mut guard = state().write().await;
    if guard.last_snapshot.is_none() {
        let guide_frame = capture_guide_frame().await?;
        update_snapshot_from_frame(&mut guard, &guide_frame, size);
        guard.last_frame = Some(guide_frame);
    } else if let Some(frame) = guard.last_frame.clone() {
        update_snapshot_from_frame(&mut guard, &frame, size);
    }

    let snapshot = guard
        .last_snapshot
        .clone()
        .ok_or_else(|| NightshadeError::OperationFailed("No guide frame available".to_string()))?;

    Ok(Phd2StarImage {
        frame: snapshot.frame,
        width: snapshot.width,
        height: snapshot.height,
        star_x: snapshot.star_x,
        star_y: snapshot.star_y,
        pixels: snapshot.pixels,
    })
}

pub async fn get_status() -> Result<Phd2Status, NightshadeError> {
    let guard = state().read().await;
    let status = &guard.last_status;
    Ok(Phd2Status {
        connected: status.connected,
        state: status.state.clone(),
        rms_ra: status.rms_ra,
        rms_dec: status.rms_dec,
        rms_total: status.rms_total,
        snr: status.snr,
        star_mass: status.star_mass,
        pixel_scale: status.pixel_scale,
    })
}

/// Convert the built-in guider's `east`/`north` calibration vectors into the
/// PHD2-shaped `Phd2CalibrationData` (degrees, possibly None) so the unified
/// `api_guider_get_calibration` can return one type across backends.
pub async fn get_calibration_data() -> Result<crate::api::phd2::Phd2CalibrationData, NightshadeError>
{
    let guard = state().read().await;
    let calib = match guard.calibration {
        Some(c) => c,
        None => {
            return Ok(crate::api::phd2::Phd2CalibrationData {
                is_calibrated: false,
                ra_angle: None,
                dec_angle: None,
                ra_rate: None,
                dec_rate: None,
            });
        }
    };
    // atan2 returns radians in (-π, π]; convert to degrees in (-180, 180].
    let ra_angle = calib.east.y.atan2(calib.east.x).to_degrees();
    let dec_angle = calib.north.y.atan2(calib.north.x).to_degrees();
    // Pulse magnitude divided by configured calibration_ms gives pixels/ms,
    // which we surface in the same shape PHD2 uses (rate as pixels/ms).
    let ra_rate = if calib.pulse_ms > 0.0 {
        Some(calib.ra_rate())
    } else {
        None
    };
    let dec_rate = if calib.pulse_ms > 0.0 {
        Some(calib.dec_rate())
    } else {
        None
    };
    Ok(crate::api::phd2::Phd2CalibrationData {
        is_calibrated: true,
        ra_angle: Some(ra_angle),
        dec_angle: Some(dec_angle),
        ra_rate,
        dec_rate,
    })
}

pub fn device_id() -> &'static str {
    BUILTIN_GUIDER_ID
}

/// Whether the built-in guider session is active (heartbeat liveness).
pub async fn is_connected() -> bool {
    state().read().await.connected
}

async fn ensure_connected() -> Result<(), NightshadeError> {
    let connected = state().read().await.connected;
    if connected {
        Ok(())
    } else {
        Err(NightshadeError::NotConnected(
            "Built-in multi-star guider".to_string(),
        ))
    }
}

async fn resolve_devices() -> Result<(String, String), NightshadeError> {
    let app_state = get_state();
    let camera_id =
        if let Some(device_id) = app_state.get_profile_device_id(DeviceType::Camera).await {
            device_id
        } else if let Some(device_id) = first_connected_device(DeviceType::Camera).await {
            device_id
        } else {
            return Err(NightshadeError::OperationFailed(
                "Built-in guider requires a connected camera in the active profile".to_string(),
            ));
        };

    let mount_id = if let Some(device_id) = app_state.get_profile_device_id(DeviceType::Mount).await
    {
        device_id
    } else if let Some(device_id) = first_connected_device(DeviceType::Mount).await {
        device_id
    } else {
        return Err(NightshadeError::OperationFailed(
            "Built-in guider requires a connected mount in the active profile".to_string(),
        ));
    };

    let device_manager = get_device_manager();
    if !device_manager
        .is_device_connected(DeviceType::Camera, &camera_id)
        .await
    {
        return Err(NightshadeError::NotConnected(camera_id));
    }
    if !device_manager
        .is_device_connected(DeviceType::Mount, &mount_id)
        .await
    {
        return Err(NightshadeError::NotConnected(mount_id));
    }

    Ok((camera_id, mount_id))
}

async fn first_connected_device(device_type: DeviceType) -> Option<String> {
    get_device_manager()
        .first_connected_device_id(device_type)
        .await
}

async fn capture_guide_frame() -> Result<GuideFrame, NightshadeError> {
    let (camera_id, _) = resolve_devices().await?;
    let config = state().read().await.config.clone();
    let device_manager = get_device_manager();

    device_manager
        .camera_start_exposure(
            &camera_id,
            config.exposure_secs,
            Some(config.gain),
            Some(config.offset),
            config.binning,
            config.binning,
        )
        .await
        .map_err(NightshadeError::from)?;

    loop {
        if device_manager
            .camera_is_exposure_complete(&camera_id)
            .await
            .map_err(NightshadeError::from)?
        {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    let native_image = device_manager
        .camera_download_image(&camera_id)
        .await
        .map_err(NightshadeError::from)?;
    let image = ImageData::from_u16(
        native_image.width,
        native_image.height,
        1,
        &native_image.data,
    );
    let summary = detect_stars_with_stats(&image, &StarDetectionConfig::default());
    let mut stars = summary.stars.clone();
    stars.sort_by(|a, b| {
        b.flux
            .partial_cmp(&a.flux)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let frame_counter = {
        let guard = state().read().await;
        guard
            .last_frame
            .as_ref()
            .map(|frame| frame.frame + 1)
            .unwrap_or(1)
    };

    Ok(GuideFrame {
        frame: frame_counter,
        image,
        stars,
    })
}

async fn ensure_frame_available() -> Result<GuideFrame, NightshadeError> {
    if let Some(frame) = state().read().await.last_frame.clone() {
        return Ok(frame);
    }
    capture_guide_frame().await
}

async fn capture_and_store_loop_frame(
    controller: Arc<RwLock<BuiltinGuiderState>>,
) -> Result<(), NightshadeError> {
    let frame = capture_guide_frame().await?;
    let selected = choose_lock_star(&frame.stars, controller.read().await.manual_lock, None)
        .or_else(|| frame.stars.first())
        .cloned();

    let mut guard = controller.write().await;
    if let Some(star) = selected.as_ref() {
        guard.manual_lock = Some(Vec2 {
            x: star.x,
            y: star.y,
        });
    }
    update_snapshot_from_frame(&mut guard, &frame, 50);
    guard.last_status.connected = true;
    guard.last_status.state = if guard.looping {
        "Looping".to_string()
    } else {
        "Connected".to_string()
    };
    guard.last_status.snr = selected.as_ref().map(|star| star.snr).unwrap_or(0.0);
    guard.last_status.star_mass = selected.as_ref().map(|star| star.flux).unwrap_or(0.0);
    guard.last_frame = Some(frame);
    Ok(())
}

async fn run_guiding_loop(
    controller: Arc<RwLock<BuiltinGuiderState>>,
    stop_flag: Arc<std::sync::atomic::AtomicBool>,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    let calibration = calibrate_mount_response(controller.clone()).await?;
    {
        let mut guard = controller.write().await;
        guard.calibration = Some(calibration);
        guard.calibrating = false;
        guard.last_status.state = "Guiding".to_string();
        // Arm the settle timeout for the initial settle after calibration
        let timeout_secs = settle_timeout.max(settle_time + 1.0);
        guard.settle_timeout_deadline =
            Some(Instant::now() + Duration::from_secs_f64(timeout_secs));
    }
    get_state().publish_guiding_event(GuidingEvent::CalibrationComplete, EventSeverity::Info);
    get_state().publish_guiding_event(GuidingEvent::GuidingStarted, EventSeverity::Info);

    loop {
        if stop_flag.load(std::sync::atomic::Ordering::Relaxed) {
            break;
        }

        let frame = capture_guide_frame().await?;
        let current_lock = {
            let guard = controller.read().await;
            guard.manual_lock
        };
        let selected = choose_lock_star(&frame.stars, current_lock, None)
            .or_else(|| frame.stars.first())
            .cloned()
            .ok_or_else(|| {
                NightshadeError::OperationFailed("No guide stars detected".to_string())
            })?;

        let offset = {
            let mut guard = controller.write().await;
            if guard.reference_stars.is_empty() {
                guard.reference_stars =
                    select_reference_stars(&frame.stars, frame.image.width, frame.image.height);
            }
            guard.manual_lock = Some(Vec2 {
                x: selected.x,
                y: selected.y,
            });
            let desired = guard.desired_offset;
            let offset =
                measure_offset(&guard.reference_stars, &frame.stars, desired).ok_or_else(|| {
                    NightshadeError::OperationFailed("Unable to match guide stars".to_string())
                })?;
            // Record per-star residuals so the per-star UI can show how far each
            // tracked star drifted this frame, not just the aggregate centroid.
            record_per_star_residuals(&mut guard.reference_stars, &frame.stars, desired);
            update_snapshot_from_frame(&mut guard, &frame, 50);
            guard.last_status.connected = true;
            guard.last_status.state = "Guiding".to_string();
            guard.last_status.rms_ra = offset.x.abs();
            guard.last_status.rms_dec = offset.y.abs();
            guard.last_status.rms_total = offset.magnitude();
            guard.last_status.snr = selected.snr;
            guard.last_status.star_mass = selected.flux;
            guard.last_frame = Some(frame.clone());
            offset
        };

        get_state().publish_guiding_event(
            GuidingEvent::Correction {
                ra: offset.x,
                dec: offset.y,
                ra_raw: offset.x,
                dec_raw: offset.y,
            },
            EventSeverity::Info,
        );
        get_state().publish_guiding_event(
            GuidingEvent::GuideStats {
                snr: selected.snr,
                star_mass: selected.flux,
            },
            EventSeverity::Info,
        );

        // Record this frame's RMS so adaptive dither can loosen settle tolerance
        // when recent seeing is poor.
        push_rms_sample(&controller, offset.magnitude()).await;

        apply_settle_state(
            controller.clone(),
            offset.magnitude(),
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .await?;
        apply_guide_correction(calibration, offset, &controller).await?;
    }

    Ok(())
}

async fn calibrate_mount_response(
    controller: Arc<RwLock<BuiltinGuiderState>>,
) -> Result<GuideCalibration, NightshadeError> {
    let baseline = capture_guide_frame().await?;
    {
        let mut guard = controller.write().await;
        guard.reference_stars =
            select_reference_stars(&baseline.stars, baseline.image.width, baseline.image.height);
        guard.manual_lock = choose_lock_star(&baseline.stars, None, None).map(|star| Vec2 {
            x: star.x,
            y: star.y,
        });
        update_snapshot_from_frame(&mut guard, &baseline, 50);
        guard.last_frame = Some(baseline.clone());
    }

    let east = calibrate_axis_response("east", "west", &baseline).await?;
    // After the RA round-trip the scope is back near baseline. Recapture so the
    // Dec calibration measures from the current position (RA backlash/PE during
    // the RA round-trip would otherwise contaminate the Dec baseline).
    let dec_baseline = capture_guide_frame().await?;
    let (north, dec_backlash_ms) = calibrate_dec_response("north", "south", &dec_baseline).await?;

    let config = controller.read().await.config.clone();
    let pulse_ms = config.calibration_ms as f64;
    let calibration = build_calibration(east, north, pulse_ms, dec_backlash_ms)?;

    if (calibration.orthogonality_deg - 90.0).abs() > 25.0 {
        tracing::warn!(
            "Built-in guider calibration axes are non-orthogonal ({:.1}°); guiding will still \
             apply the full 2x2 solve but accuracy may be degraded",
            calibration.orthogonality_deg
        );
    }
    if dec_backlash_ms > 0.0 {
        tracing::info!(
            "Built-in guider measured Dec backlash of {:.0}ms",
            dec_backlash_ms
        );
    }

    Ok(calibration)
}

/// Pure construction of the calibration model from the two measured axis-response
/// vectors. Validates non-singularity, derives the inter-axis angle, and carries
/// the measured Dec backlash. Extracted from [`calibrate_mount_response`] so the
/// calibration math (angles/rates/orthogonality/backlash plumbing) is unit
/// testable without driving a mount.
fn build_calibration(
    east: Vec2,
    north: Vec2,
    pulse_ms: f64,
    dec_backlash_ms: f64,
) -> Result<GuideCalibration, NightshadeError> {
    let determinant = east.x * north.y - east.y * north.x;
    if determinant.abs() < 1e-3 {
        return Err(NightshadeError::OperationFailed(
            "Built-in guider calibration is singular; mount pulse responses were not distinct"
                .to_string(),
        ));
    }

    // Angle between the RA and Dec response vectors, in [0, 180].
    let dot = east.x * north.x + east.y * north.y;
    let mag = east.magnitude() * north.magnitude();
    let orthogonality_deg = if mag > 1e-9 {
        (dot / mag).clamp(-1.0, 1.0).acos().to_degrees()
    } else {
        90.0
    };

    Ok(GuideCalibration {
        east,
        north,
        pulse_ms,
        dec_backlash_ms: dec_backlash_ms.max(0.0),
        orthogonality_deg,
    })
}

/// Calibrate the Dec axis and measure first-reversal backlash.
///
/// Pulses Dec+ twice (to establish the forward rate past any initial slack),
/// then reverses to Dec- and measures the FIRST reverse-pulse response. The
/// shortfall of that first reverse displacement versus the established
/// per-pulse forward rate is the backlash dead-band: the gear took up slack
/// before the scope moved, so it travelled less than a clean pulse would. The
/// backlash is reported in equivalent pulse-milliseconds (`shortfall_px /
/// rate_px_per_ms`).
async fn calibrate_dec_response(
    positive_direction: &str,
    negative_direction: &str,
    baseline: &GuideFrame,
) -> Result<(Vec2, f64), NightshadeError> {
    let (_, mount_id) = resolve_devices().await?;
    let config = state().read().await.config.clone();
    let device_manager = get_device_manager();
    let refs = select_reference_stars(&baseline.stars, baseline.image.width, baseline.image.height);

    // --- Forward leg: two pulses to get past initial slack and establish rate.
    for _ in 0..2 {
        device_manager
            .mount_pulse_guide(
                &mount_id,
                positive_direction.to_string(),
                config.calibration_ms,
            )
            .await
            .map_err(NightshadeError::from)?;
        tokio::time::sleep(Duration::from_millis(config.settle_sleep_ms)).await;
    }
    let fwd_frame = capture_guide_frame().await?;
    let fwd_offset = measure_offset(&refs, &fwd_frame.stars, Vec2::default()).ok_or_else(|| {
        NightshadeError::OperationFailed("Dec calibration forward star match failed".to_string())
    })?;
    // Per-pulse forward response (two pulses were issued).
    let north = Vec2 {
        x: fwd_offset.x / 2.0,
        y: fwd_offset.y / 2.0,
    };

    if north.magnitude() < 0.2 {
        return Err(NightshadeError::OperationFailed(format!(
            "Calibration response on {positive_direction} axis was too small ({:.3}px/pulse)",
            north.magnitude()
        )));
    }

    // --- Reverse leg: one pulse, measure the first-reversal response.
    let refs_after_fwd = select_reference_stars(
        &fwd_frame.stars,
        fwd_frame.image.width,
        fwd_frame.image.height,
    );
    device_manager
        .mount_pulse_guide(
            &mount_id,
            negative_direction.to_string(),
            config.calibration_ms,
        )
        .await
        .map_err(NightshadeError::from)?;
    tokio::time::sleep(Duration::from_millis(config.settle_sleep_ms)).await;
    let rev_frame = capture_guide_frame().await?;
    let rev_offset =
        measure_offset(&refs_after_fwd, &rev_frame.stars, Vec2::default()).unwrap_or_default();

    let dec_backlash_ms = estimate_dec_backlash_ms(north, rev_offset, config.calibration_ms as f64);

    // Restore toward baseline: issue a second reverse pulse so we end roughly
    // where we started (the forward leg moved two pulses, we have reversed one).
    device_manager
        .mount_pulse_guide(
            &mount_id,
            negative_direction.to_string(),
            config.calibration_ms,
        )
        .await
        .map_err(NightshadeError::from)?;
    tokio::time::sleep(Duration::from_millis(config.settle_sleep_ms)).await;

    Ok((north, dec_backlash_ms))
}

/// Estimate Dec backlash (in pulse-ms) from the per-pulse forward response and
/// the measured first-reversal response, given the calibration pulse width.
///
/// The first reverse pulse travels less than a clean pulse by the dead band the
/// gear takes up. We project the reverse displacement onto the (negated) forward
/// axis to get the effective reverse travel, compute the shortfall versus the
/// clean per-pulse magnitude, and convert that pixel shortfall back to ms using
/// the forward rate. A negative/zero shortfall means no measurable backlash.
fn estimate_dec_backlash_ms(forward_per_pulse: Vec2, reverse_first: Vec2, pulse_ms: f64) -> f64 {
    let fwd_mag = forward_per_pulse.magnitude();
    if fwd_mag < 1e-6 || pulse_ms <= 0.0 {
        return 0.0;
    }
    // Unit vector along the reverse (negative-forward) direction.
    let inv = 1.0 / fwd_mag;
    let rx = -forward_per_pulse.x * inv;
    let ry = -forward_per_pulse.y * inv;
    // Effective reverse travel along the axis (projection).
    let reverse_travel = reverse_first.x * rx + reverse_first.y * ry;
    let shortfall = fwd_mag - reverse_travel;
    if shortfall <= 0.0 {
        return 0.0;
    }
    let rate_px_per_ms = fwd_mag / pulse_ms;
    if rate_px_per_ms <= 0.0 {
        return 0.0;
    }
    (shortfall / rate_px_per_ms).max(0.0)
}

async fn calibrate_axis_response(
    positive_direction: &str,
    negative_direction: &str,
    baseline: &GuideFrame,
) -> Result<Vec2, NightshadeError> {
    let (_, mount_id) = resolve_devices().await?;
    let config = state().read().await.config.clone();
    let device_manager = get_device_manager();

    device_manager
        .mount_pulse_guide(
            &mount_id,
            positive_direction.to_string(),
            config.calibration_ms,
        )
        .await
        .map_err(NightshadeError::from)?;
    tokio::time::sleep(Duration::from_millis(config.settle_sleep_ms)).await;
    let moved_frame = capture_guide_frame().await?;
    let offset = measure_offset(
        &select_reference_stars(&baseline.stars, baseline.image.width, baseline.image.height),
        &moved_frame.stars,
        Vec2::default(),
    )
    .ok_or_else(|| NightshadeError::OperationFailed("Calibration star match failed".to_string()))?;

    device_manager
        .mount_pulse_guide(
            &mount_id,
            negative_direction.to_string(),
            config.calibration_ms,
        )
        .await
        .map_err(NightshadeError::from)?;
    tokio::time::sleep(Duration::from_millis(config.settle_sleep_ms)).await;

    if offset.magnitude() < 0.2 {
        return Err(NightshadeError::OperationFailed(format!(
            "Calibration response on {} axis was too small ({:.3}px)",
            positive_direction,
            offset.magnitude()
        )));
    }

    Ok(offset)
}

/// One reference star's matched per-frame displacement plus its weight, the raw
/// material for the robust centroid.
#[derive(Clone, Copy)]
struct StarDisplacement {
    delta: Vec2,
    weight: f64,
}

/// Match each reference star to its nearest detection on the current frame and
/// return the per-star displacement (`detected - expected`) with its weight.
/// Unmatched references (star lost behind cloud / off-edge under rotation) are
/// simply omitted, which is what lets the guider tolerate individual star loss.
fn matched_displacements(
    reference_stars: &[GuideReferenceStar],
    current_stars: &[DetectedStar],
    desired_offset: Vec2,
) -> Vec<StarDisplacement> {
    let mut out = Vec::with_capacity(reference_stars.len());
    for reference in reference_stars {
        let expected = Vec2 {
            x: reference.x + desired_offset.x,
            y: reference.y + desired_offset.y,
        };
        if let Some(star) = nearest_star(current_stars, expected, GUIDE_MAX_MATCH_DISTANCE_PX) {
            out.push(StarDisplacement {
                delta: Vec2 {
                    x: star.x - expected.x,
                    y: star.y - expected.y,
                },
                weight: guide_reference_weight(reference),
            });
        }
    }
    out
}

/// Median of a slice (sorted copy). Empty slice -> 0.0.
fn median(values: &[f64]) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mid = sorted.len() / 2;
    if sorted.len() % 2 == 0 {
        (sorted[mid - 1] + sorted[mid]) / 2.0
    } else {
        sorted[mid]
    }
}

/// Robust, mass-weighted guide offset.
///
/// The aggregate offset is the SIGMA-CLIPPED, flux/SNR-WEIGHTED mean of the
/// per-star displacements: per-star distances from the median displacement are
/// scaled by 1.4826·MAD into a sigma-equivalent, and any star beyond
/// [`GUIDE_OUTLIER_SIGMA`] is dropped before the weighted mean is taken. This
/// makes a single star that jumps (cloud edge, cosmic ray, misassociation) not
/// move the reported offset.
///
/// Clipping only engages with at least [`GUIDE_MIN_STARS_FOR_CLIP`] matched
/// stars; below that (down to a single star) it degrades gracefully to the plain
/// weighted mean so the guider keeps running on a sparse field. Returns `None`
/// only when no reference matched at all.
fn measure_offset(
    reference_stars: &[GuideReferenceStar],
    current_stars: &[DetectedStar],
    desired_offset: Vec2,
) -> Option<Vec2> {
    let displacements = matched_displacements(reference_stars, current_stars, desired_offset);
    robust_weighted_offset(&displacements)
}

/// Compute the sigma-clipped, weighted-mean offset from a set of matched per-star
/// displacements. Factored out of [`measure_offset`] so the tests can exercise
/// the robust-centroid math directly without constructing detection lists.
fn robust_weighted_offset(displacements: &[StarDisplacement]) -> Option<Vec2> {
    if displacements.is_empty() {
        return None;
    }

    // Sigma-clip on displacement magnitude relative to the median, but only when
    // we have enough samples for the spread estimate to be meaningful.
    let kept: Vec<&StarDisplacement> = if displacements.len() >= GUIDE_MIN_STARS_FOR_CLIP {
        let mags: Vec<f64> = displacements.iter().map(|d| d.delta.magnitude()).collect();
        let med = median(&mags);
        let abs_dev: Vec<f64> = mags.iter().map(|m| (m - med).abs()).collect();
        let mad = median(&abs_dev);
        let mut sigma = mad * MAD_TO_SIGMA;
        // Robustness fallback: MAD collapses to ~0 when a majority of stars share
        // an identical displacement (a clean field with one outlier — the common
        // "one star jumped" case, and what synthetic tests produce). In that
        // degenerate case fall back to the standard deviation about the median so
        // the lone outlier is still clipped.
        if sigma <= 1e-9 {
            let n = mags.len() as f64;
            let var = abs_dev.iter().map(|d| d * d).sum::<f64>() / n;
            sigma = var.sqrt();
        }
        if sigma > 1e-9 {
            let cutoff = GUIDE_OUTLIER_SIGMA * sigma;
            let kept: Vec<&StarDisplacement> = displacements
                .iter()
                .zip(mags.iter())
                .filter(|(_, &m)| (m - med).abs() <= cutoff)
                .map(|(d, _)| d)
                .collect();
            // Never clip everything away; if the cutoff was pathologically tight
            // keep the full set.
            if kept.is_empty() {
                displacements.iter().collect()
            } else {
                kept
            }
        } else {
            // All displacements essentially identical: nothing to clip.
            displacements.iter().collect()
        }
    } else {
        displacements.iter().collect()
    };

    let mut weighted_x = 0.0;
    let mut weighted_y = 0.0;
    let mut total_weight = 0.0;
    for d in kept {
        weighted_x += d.delta.x * d.weight;
        weighted_y += d.delta.y * d.weight;
        total_weight += d.weight;
    }
    if total_weight <= 0.0 {
        return None;
    }
    Some(Vec2 {
        x: weighted_x / total_weight,
        y: weighted_y / total_weight,
    })
}

/// Append a frame's total RMS to the rolling history (capped length), for
/// adaptive dither sizing.
async fn push_rms_sample(controller: &Arc<RwLock<BuiltinGuiderState>>, rms: f64) {
    if !rms.is_finite() {
        return;
    }
    let mut guard = controller.write().await;
    guard.rms_history.push(rms);
    let len = guard.rms_history.len();
    if len > RMS_HISTORY_LEN {
        guard.rms_history.drain(0..len - RMS_HISTORY_LEN);
    }
}

/// Mean of the recent RMS history, or `None` when no samples yet.
fn recent_rms(history: &[f64]) -> Option<f64> {
    if history.is_empty() {
        None
    } else {
        Some(history.iter().sum::<f64>() / history.len() as f64)
    }
}

/// Update each reference star's `last_residual` from its matched detection on
/// the current frame. Mirrors the matching done in [`measure_offset`] but per
/// star (no flux weighting): the residual is the vector from the star's
/// expected position to its nearest detected centroid. Stars with no match this
/// frame keep their previous residual (the per-star UI shows the last good
/// value rather than flicking to "—").
fn record_per_star_residuals(
    reference_stars: &mut [GuideReferenceStar],
    current_stars: &[DetectedStar],
    desired_offset: Vec2,
) {
    for reference in reference_stars.iter_mut() {
        let expected = Vec2 {
            x: reference.x + desired_offset.x,
            y: reference.y + desired_offset.y,
        };
        if let Some(star) = nearest_star(current_stars, expected, GUIDE_MAX_MATCH_DISTANCE_PX) {
            reference.last_residual = Some(Vec2 {
                x: star.x - expected.x,
                y: star.y - expected.y,
            });
        }
    }
}

fn guide_reference_weight(reference: &GuideReferenceStar) -> f64 {
    let flux_weight = reference.flux.max(1.0).sqrt();
    let snr_weight = reference.snr.max(1.0);
    let weight = flux_weight * snr_weight;
    if weight.is_finite() && weight > 0.0 {
        weight
    } else {
        1.0
    }
}

/// A single computed pulse command for one axis: signed milliseconds (sign =
/// direction) after aggressiveness, min-move, max-clamp, and (for Dec) backlash
/// compensation. `None` means "no pulse" (below min-move / min-pulse).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct AxisPulse {
    ra_ms: Option<f64>,
    dec_ms: Option<f64>,
    /// The Dec direction this correction commands, if any — recorded so the next
    /// correction can detect a reversal and avoid re-paying backlash.
    new_dec_direction: Option<DecDirection>,
}

/// Pure correction math: convert a measured guide `offset` (pixels) into signed
/// per-axis pulse durations using the calibration model.
///
/// Steps: invert the 2×2 calibration to get RA/Dec pulse-ms that would null the
/// offset; apply per-axis aggressiveness; drop the axis when the corresponding
/// offset component is below `min_move_px` (noise floor); clamp magnitude to
/// `[min_pulse_ms, max_pulse_ms]` (dropping sub-min pulses); and, on a Dec
/// direction reversal versus `last_dec_direction`, add the calibrated backlash
/// dead-band to the Dec pulse so the first reverse pulse actually moves the
/// scope.
///
/// Extracted as a pure function so aggressiveness, clamps, and backlash
/// compensation are unit-testable without a mount.
fn compute_pulse_durations(
    calibration: GuideCalibration,
    offset: Vec2,
    config: &GuiderConfig,
    last_dec_direction: Option<DecDirection>,
) -> AxisPulse {
    let determinant =
        calibration.east.x * calibration.north.y - calibration.east.y * calibration.north.x;
    if determinant.abs() < 1e-6 {
        return AxisPulse::default();
    }

    // Solve for the pulse scales (in units of one calibration pulse) that move
    // the scope by `-offset`, then convert to milliseconds.
    let target = Vec2 {
        x: -offset.x,
        y: -offset.y,
    };
    let east_scale =
        (target.x * calibration.north.y - target.y * calibration.north.x) / determinant;
    let north_scale = (calibration.east.x * target.y - calibration.east.y * target.x) / determinant;

    let ra_ms_raw = east_scale * calibration.pulse_ms * config.ra_aggressiveness;
    let mut dec_ms_raw = north_scale * calibration.pulse_ms * config.dec_aggressiveness;

    // Project the measured offset onto each calibration axis so the min-move
    // threshold is evaluated in the axis frame (matches how the correction is
    // applied), not the raw pixel x/y.
    let ra_axis_move = project_offset(offset, calibration.east);
    let dec_axis_move = project_offset(offset, calibration.north);

    // --- Dec backlash compensation on direction reversal.
    let new_dec_direction = if dec_ms_raw >= 0.0 {
        DecDirection::North
    } else {
        DecDirection::South
    };
    let reversing = last_dec_direction
        .map(|prev| prev != new_dec_direction)
        .unwrap_or(true); // first-ever Dec pulse pays backlash once
    if reversing && calibration.dec_backlash_ms > 0.0 && dec_ms_raw.abs() >= 1e-9 {
        let sign = if dec_ms_raw >= 0.0 { 1.0 } else { -1.0 };
        dec_ms_raw += sign * calibration.dec_backlash_ms;
    }

    let ra_ms = clamp_axis_pulse(ra_ms_raw, ra_axis_move, config);
    let dec_ms = clamp_axis_pulse(dec_ms_raw, dec_axis_move, config);

    AxisPulse {
        ra_ms,
        dec_ms,
        new_dec_direction: dec_ms.map(|_| new_dec_direction),
    }
}

/// Signed projection of a pixel offset onto a calibration axis vector, giving the
/// offset component along that axis in pixels.
fn project_offset(offset: Vec2, axis: Vec2) -> f64 {
    let mag = axis.magnitude();
    if mag < 1e-9 {
        return 0.0;
    }
    (offset.x * axis.x + offset.y * axis.y) / mag
}

/// Apply min-move (in pixels along the axis) and min/max pulse clamps to a signed
/// pulse duration. Returns `None` when the axis move is below the noise floor or
/// the resulting pulse is below the minimum pulse length.
fn clamp_axis_pulse(pulse_ms: f64, axis_move_px: f64, config: &GuiderConfig) -> Option<f64> {
    if axis_move_px.abs() < config.min_move_px {
        return None;
    }
    let magnitude = pulse_ms.abs();
    if magnitude < config.min_pulse_ms {
        return None;
    }
    let clamped = magnitude.clamp(config.min_pulse_ms, config.max_pulse_ms);
    Some(if pulse_ms >= 0.0 { clamped } else { -clamped })
}

async fn apply_guide_correction(
    calibration: GuideCalibration,
    offset: Vec2,
    controller: &Arc<RwLock<BuiltinGuiderState>>,
) -> Result<(), NightshadeError> {
    let (config, last_dec) = {
        let guard = controller.read().await;
        (guard.config.clone(), guard.last_dec_direction)
    };

    let plan = compute_pulse_durations(calibration, offset, &config, last_dec);

    if let Some(ra_ms) = plan.ra_ms {
        pulse_axis("east", "west", ra_ms, &config).await?;
    }
    if let Some(dec_ms) = plan.dec_ms {
        pulse_axis("north", "south", dec_ms, &config).await?;
    }
    if let Some(dir) = plan.new_dec_direction {
        controller.write().await.last_dec_direction = Some(dir);
    }
    Ok(())
}

/// Issue a single mount pulse for an already-computed signed duration. The
/// duration has already passed min-move/min-pulse gating in
/// [`compute_pulse_durations`]; this only resolves direction and rounds to ms.
async fn pulse_axis(
    positive_direction: &str,
    negative_direction: &str,
    pulse_ms: f64,
    config: &GuiderConfig,
) -> Result<(), NightshadeError> {
    let magnitude = pulse_ms.abs();
    let (_, mount_id) = resolve_devices().await?;
    let duration = magnitude
        .clamp(config.min_pulse_ms, config.max_pulse_ms)
        .round() as u32;
    let direction = if pulse_ms >= 0.0 {
        positive_direction
    } else {
        negative_direction
    };
    get_device_manager()
        .mount_pulse_guide(&mount_id, direction.to_string(), duration)
        .await
        .map_err(NightshadeError::from)
}

async fn apply_settle_state(
    controller: Arc<RwLock<BuiltinGuiderState>>,
    rms_total: f64,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    let mut guard = controller.write().await;

    // Check if the overall settle timeout has been exceeded
    if let Some(timeout_deadline) = guard.settle_timeout_deadline {
        if Instant::now() >= timeout_deadline {
            guard.settle_deadline = None;
            guard.settle_timeout_deadline = None;
            let was_dithering = guard.dither_pending;
            guard.dither_pending = false;
            let context = if was_dithering {
                "dither settle"
            } else {
                "guide settle"
            };
            return Err(NightshadeError::OperationFailed(format!(
                "Settle timeout exceeded ({:.0}s) during {}; guiding RMS {:.2}px still above threshold {:.2}px",
                settle_timeout, context, rms_total, settle_pixels,
            )));
        }
    }

    if rms_total <= settle_pixels {
        match guard.settle_deadline {
            Some(deadline) if Instant::now() >= deadline => {
                guard.settle_deadline = None;
                guard.settle_timeout_deadline = None;
                if guard.dither_pending {
                    guard.dither_pending = false;
                    get_state()
                        .publish_guiding_event(GuidingEvent::DitherCompleted, EventSeverity::Info);
                }
                get_state().publish_guiding_event(
                    GuidingEvent::Settled { rms: rms_total },
                    EventSeverity::Info,
                );
            }
            None => {
                guard.settle_deadline =
                    Some(Instant::now() + Duration::from_secs_f64(settle_time.max(0.1)));
                // If no timeout deadline is set yet, arm one now
                if guard.settle_timeout_deadline.is_none() {
                    let timeout_secs = settle_timeout.max(settle_time + 1.0);
                    guard.settle_timeout_deadline =
                        Some(Instant::now() + Duration::from_secs_f64(timeout_secs));
                }
                get_state().publish_guiding_event(GuidingEvent::Settling, EventSeverity::Info);
            }
            _ => {}
        }
    } else {
        // RMS exceeded threshold, reset the settle timer (but keep the timeout deadline)
        guard.settle_deadline = None;
    }

    Ok(())
}

/// Decide whether a detected star is usable as a guide reference. Rejects
/// saturated cores (clipped centroid), too-faint stars (noisy displacement),
/// elongated/blended detections (centroid walks with seeing, not the mount), and
/// stars too close to the frame edge (partial PSF + first to leave under field
/// rotation). `width`/`height` are the guide-frame dimensions in pixels; when
/// both are 0 the edge check is skipped (e.g. unit tests that work in star-space).
fn is_usable_reference(star: &DetectedStar, width: u32, height: u32) -> bool {
    if star.snr < GUIDE_MIN_REFERENCE_SNR {
        return false;
    }
    if star.peak >= GUIDE_SATURATION_PEAK_ADU {
        return false;
    }
    if star.eccentricity > GUIDE_MAX_REFERENCE_ECCENTRICITY {
        return false;
    }
    if !star.x.is_finite() || !star.y.is_finite() {
        return false;
    }
    if width > 0 && height > 0 {
        let w = width as f64;
        let h = height as f64;
        if star.x < GUIDE_EDGE_MARGIN_PX
            || star.y < GUIDE_EDGE_MARGIN_PX
            || star.x > w - GUIDE_EDGE_MARGIN_PX
            || star.y > h - GUIDE_EDGE_MARGIN_PX
        {
            return false;
        }
    }
    true
}

/// Select up to [`GUIDE_MAX_TRACKED_STARS`] guide references from a detected-star
/// list. Input is assumed brightest-first (callers sort by flux). Stars are
/// filtered by [`is_usable_reference`] and spaced at least
/// [`GUIDE_MIN_STAR_SEPARATION_PX`] apart so two detections of a blended pair are
/// not both tracked. `width`/`height` are the frame dimensions for edge rejection.
fn select_reference_stars(
    stars: &[DetectedStar],
    width: u32,
    height: u32,
) -> Vec<GuideReferenceStar> {
    let mut selected = Vec::new();
    for star in stars {
        if selected.len() >= GUIDE_MAX_TRACKED_STARS {
            break;
        }
        if !is_usable_reference(star, width, height) {
            continue;
        }
        let is_far_enough = selected.iter().all(|existing: &GuideReferenceStar| {
            let dx = existing.x - star.x;
            let dy = existing.y - star.y;
            (dx * dx + dy * dy).sqrt() >= GUIDE_MIN_STAR_SEPARATION_PX
        });
        if is_far_enough {
            selected.push(GuideReferenceStar {
                x: star.x,
                y: star.y,
                flux: star.flux,
                snr: star.snr,
                last_residual: None,
            });
        }
    }
    selected
}

fn choose_lock_star<'a>(
    stars: &'a [DetectedStar],
    preferred: Option<Vec2>,
    fallback: Option<Vec2>,
) -> Option<&'a DetectedStar> {
    let target = preferred.or(fallback);
    match target {
        Some(target_pos) => nearest_star(stars, target_pos, GUIDE_MAX_MATCH_DISTANCE_PX * 2.0)
            .or_else(|| stars.first()),
        None => stars.first(),
    }
}

fn nearest_star(stars: &[DetectedStar], target: Vec2, max_distance: f64) -> Option<&DetectedStar> {
    stars
        .iter()
        .filter_map(|star| {
            let dx = star.x - target.x;
            let dy = star.y - target.y;
            let distance = (dx * dx + dy * dy).sqrt();
            if distance <= max_distance {
                Some((distance, star))
            } else {
                None
            }
        })
        .min_by(|(left_distance, _), (right_distance, _)| {
            left_distance
                .partial_cmp(right_distance)
                .unwrap_or(std::cmp::Ordering::Equal)
        })
        .map(|(_, star)| star)
}

fn update_snapshot_from_frame(state: &mut BuiltinGuiderState, frame: &GuideFrame, crop_size: u32) {
    let selected = choose_lock_star(
        &frame.stars,
        state.manual_lock,
        frame.stars.first().map(|star| Vec2 {
            x: star.x,
            y: star.y,
        }),
    );

    if let Some(star) = selected {
        let snapshot = crop_raw_u16_image(&frame.image, star, crop_size);
        state.last_snapshot = Some(GuideSnapshot {
            frame: frame.frame,
            width: snapshot.width,
            height: snapshot.height,
            pixels: snapshot.pixels,
            crop_origin_x: snapshot.crop_origin_x,
            crop_origin_y: snapshot.crop_origin_y,
            star_x: snapshot.star_x,
            star_y: snapshot.star_y,
        });
    }
}

struct RawCrop {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
    crop_origin_x: i32,
    crop_origin_y: i32,
    star_x: f64,
    star_y: f64,
}

fn crop_raw_u16_image(image: &ImageData, star: &DetectedStar, crop_size: u32) -> RawCrop {
    let width = image.width as i32;
    let height = image.height as i32;
    let half = crop_size as i32 / 2;
    let center_x = star.x.round() as i32;
    let center_y = star.y.round() as i32;
    let x_start = (center_x - half).clamp(0, width.saturating_sub(1));
    let y_start = (center_y - half).clamp(0, height.saturating_sub(1));
    let x_end = (center_x + half).clamp(1, width);
    let y_end = (center_y + half).clamp(1, height);
    let crop_width = (x_end - x_start) as u32;
    let crop_height = (y_end - y_start) as u32;

    // Validate that the raw data buffer has even length (required for U16 pixel pairs)
    // and is large enough for the image dimensions claimed.
    let expected_data_len = (image.width as usize) * (image.height as usize) * 2;
    if image.data.len() < expected_data_len || image.data.len() % 2 != 0 {
        tracing::warn!(
            "crop_raw_u16_image: image data length {} does not match expected {} ({}x{} U16), \
             returning empty crop",
            image.data.len(),
            expected_data_len,
            image.width,
            image.height,
        );
        return RawCrop {
            width: 0,
            height: 0,
            pixels: Vec::new(),
            crop_origin_x: x_start,
            crop_origin_y: y_start,
            star_x: star.x - x_start as f64,
            star_y: star.y - y_start as f64,
        };
    }

    let mut pixels = Vec::with_capacity((crop_width * crop_height * 2) as usize);

    for y in y_start..y_end {
        for x in x_start..x_end {
            let index = ((y as u32 * image.width + x as u32) * 2) as usize;
            // Safe: we validated data length covers width*height*2 above,
            // and x/y are clamped within [0, width) / [0, height).
            pixels.push(image.data[index]);
            pixels.push(image.data[index + 1]);
        }
    }

    RawCrop {
        width: crop_width,
        height: crop_height,
        pixels,
        crop_origin_x: x_start,
        crop_origin_y: y_start,
        star_x: star.x - x_start as f64,
        star_y: star.y - y_start as f64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn star(x: f64, y: f64, flux: f64) -> DetectedStar {
        DetectedStar {
            x,
            y,
            flux,
            hfr: 2.0,
            fwhm: 4.7,
            peak: flux,
            background: 100.0,
            snr: flux / 100.0,
            eccentricity: 0.1,
            sharpness: 0.4,
        }
    }

    #[test]
    fn select_reference_stars_enforces_spacing() {
        let stars = vec![
            star(10.0, 10.0, 1000.0),
            star(12.0, 11.0, 900.0),
            star(40.0, 40.0, 800.0),
        ];
        let refs = select_reference_stars(&stars, 0, 0);
        assert_eq!(refs.len(), 2);
    }

    #[test]
    fn measure_offset_uses_matched_star_delta() {
        let refs = vec![
            GuideReferenceStar {
                x: 10.0,
                y: 10.0,
                flux: 1000.0,
                snr: 10.0,
                last_residual: None,
            },
            GuideReferenceStar {
                x: 30.0,
                y: 30.0,
                flux: 900.0,
                snr: 9.0,
                last_residual: None,
            },
        ];
        let stars = vec![star(11.5, 8.5, 1000.0), star(31.5, 28.5, 900.0)];
        let offset = measure_offset(&refs, &stars, Vec2::default()).expect("offset");
        assert!((offset.x - 1.5).abs() < 1e-6);
        assert!((offset.y + 1.5).abs() < 1e-6);
    }

    #[test]
    fn measure_offset_weights_higher_quality_reference_stars() {
        let refs = vec![
            GuideReferenceStar {
                x: 10.0,
                y: 10.0,
                flux: 10000.0,
                snr: 20.0,
                last_residual: None,
            },
            GuideReferenceStar {
                x: 30.0,
                y: 30.0,
                flux: 100.0,
                snr: 2.0,
                last_residual: None,
            },
        ];
        let stars = vec![star(12.0, 10.0, 10000.0), star(30.0, 40.0, 100.0)];
        let offset = measure_offset(&refs, &stars, Vec2::default()).expect("offset");

        assert!(offset.x > 1.8);
        assert!(offset.y < 1.0);
    }

    #[test]
    fn record_per_star_residuals_sets_matched_star_delta() {
        let mut refs = vec![
            GuideReferenceStar {
                x: 10.0,
                y: 10.0,
                flux: 1000.0,
                snr: 10.0,
                last_residual: None,
            },
            GuideReferenceStar {
                x: 30.0,
                y: 30.0,
                flux: 900.0,
                snr: 9.0,
                last_residual: None,
            },
        ];
        // First reference drifts +1.5/-1.5; second has no nearby detection so it
        // retains its (None) residual.
        let stars = vec![star(11.5, 8.5, 1000.0), star(80.0, 80.0, 900.0)];
        record_per_star_residuals(&mut refs, &stars, Vec2::default());

        let r0 = refs[0].last_residual.expect("first star matched");
        assert!((r0.x - 1.5).abs() < 1e-6);
        assert!((r0.y + 1.5).abs() < 1e-6);
        assert!(refs[1].last_residual.is_none());
    }

    #[test]
    fn build_tracked_stars_flags_lock_and_serializes() {
        let mut state = BuiltinGuiderState {
            reference_stars: vec![
                GuideReferenceStar {
                    x: 10.0,
                    y: 12.0,
                    flux: 5000.0,
                    snr: 18.0,
                    last_residual: Some(Vec2 { x: 0.3, y: -0.4 }),
                },
                GuideReferenceStar {
                    x: 60.0,
                    y: 64.0,
                    flux: 2000.0,
                    snr: 9.0,
                    last_residual: None,
                },
            ],
            ..Default::default()
        };
        // Lock sits on top of the second reference star.
        state.manual_lock = Some(Vec2 { x: 60.0, y: 64.0 });

        let dto = build_tracked_stars(&state);
        assert_eq!(dto.count, 2);
        assert_eq!(dto.stars[0].id, 0);
        assert!(!dto.stars[0].is_lock);
        assert!(
            dto.stars[1].is_lock,
            "nearest reference to lock is the lock"
        );
        // residual magnitude of (0.3,-0.4) is 0.5
        assert!((dto.stars[0].residual.expect("residual") - 0.5).abs() < 1e-6);
        assert!(dto.stars[1].residual.is_none());

        let json = serde_json::to_string(&dto).expect("serialize");
        assert!(json.contains("\"count\":2"));
        assert!(json.contains("\"is_lock\":true"));
    }

    #[test]
    fn build_tracked_stars_empty_is_zero_count() {
        let state = BuiltinGuiderState::default();
        let dto = build_tracked_stars(&state);
        assert_eq!(dto.count, 0);
        assert!(dto.stars.is_empty());
    }

    #[test]
    fn nearest_star_respects_max_distance() {
        let stars = vec![star(10.0, 10.0, 1000.0), star(30.0, 30.0, 900.0)];
        let near = nearest_star(&stars, Vec2 { x: 11.0, y: 11.0 }, 5.0).expect("near");
        assert_eq!(near.x, 10.0);
        assert!(nearest_star(&stars, Vec2 { x: 100.0, y: 100.0 }, 5.0).is_none());
    }

    #[test]
    fn crop_raw_image_returns_16bit_payload() {
        let image = ImageData::from_u16(4, 4, 1, &(0..16).collect::<Vec<u16>>());
        let crop = crop_raw_u16_image(&image, &star(1.0, 1.0, 1000.0), 2);
        assert_eq!(crop.width, 2);
        assert_eq!(crop.height, 2);
        assert_eq!(crop.pixels.len(), 8);
    }

    // =========================================================================
    // Multi-star guider math (star selection, robust centroid, calibration,
    // backlash, correction clamps, adaptive/spiral dither).
    //
    // These exercise the pure functions directly with synthetic star fields so
    // the guiding-quality logic is validated without a mount or camera. Honest
    // gap: none of this is a substitute for an on-sky calibration/guiding run,
    // which belongs in the on-sky campaign.
    // =========================================================================

    /// Build a `DetectedStar` with explicit quality fields for selection tests.
    fn star_q(x: f64, y: f64, flux: f64, snr: f64, peak: f64, ecc: f64) -> DetectedStar {
        DetectedStar {
            x,
            y,
            flux,
            hfr: 2.0,
            fwhm: 4.7,
            peak,
            background: 100.0,
            snr,
            eccentricity: ecc,
            sharpness: 0.4,
        }
    }

    /// A clean synthetic star field: a grid of well-separated, good-quality
    /// stars away from the edges of a `w x h` frame.
    fn synthetic_field(w: u32, h: u32, count: usize) -> Vec<DetectedStar> {
        let mut stars = Vec::new();
        let cols = (count as f64).sqrt().ceil() as usize;
        let mut i = 0;
        for r in 0..cols {
            for c in 0..cols {
                if i >= count {
                    break;
                }
                let x = 40.0 + c as f64 * 40.0;
                let y = 40.0 + r as f64 * 40.0;
                // Brightest first is enforced by the caller's sort; vary flux a bit.
                let flux = 5000.0 - i as f64 * 50.0;
                stars.push(star_q(x, y, flux, 20.0, flux, 0.1));
                i += 1;
            }
        }
        let _ = (w, h);
        stars
    }

    /// Shift every star by `(dx, dy)` to simulate a known mount/field displacement.
    fn shift_field(stars: &[DetectedStar], dx: f64, dy: f64) -> Vec<DetectedStar> {
        stars
            .iter()
            .map(|s| {
                let mut s = s.clone();
                s.x += dx;
                s.y += dy;
                s
            })
            .collect()
    }

    fn refs_from(stars: &[DetectedStar]) -> Vec<GuideReferenceStar> {
        select_reference_stars(stars, 800, 800)
    }

    // --- Star selection ------------------------------------------------------

    #[test]
    fn selection_rejects_saturated_faint_elongated_and_edge_stars() {
        let stars = vec![
            star_q(100.0, 100.0, 5000.0, 20.0, 5000.0, 0.1), // good
            star_q(200.0, 200.0, 5000.0, 20.0, 65000.0, 0.1), // saturated peak
            star_q(300.0, 300.0, 50.0, 3.0, 50.0, 0.1),      // too faint (SNR<6)
            star_q(400.0, 400.0, 5000.0, 20.0, 5000.0, 0.9), // too elongated
            star_q(2.0, 400.0, 5000.0, 20.0, 5000.0, 0.1),   // off left edge
            star_q(400.0, 799.0, 5000.0, 20.0, 5000.0, 0.1), // off bottom edge
        ];
        let refs = select_reference_stars(&stars, 800, 800);
        assert_eq!(refs.len(), 1, "only the one good star should be selected");
        assert_eq!(refs[0].x, 100.0);
    }

    #[test]
    fn selection_caps_at_max_tracked_stars() {
        let mut stars = synthetic_field(800, 800, 30);
        stars.sort_by(|a, b| b.flux.partial_cmp(&a.flux).unwrap());
        let refs = select_reference_stars(&stars, 800, 800);
        assert_eq!(refs.len(), GUIDE_MAX_TRACKED_STARS);
    }

    // --- Robust weighted centroid -------------------------------------------

    #[test]
    fn weighted_centroid_recovers_known_displacement() {
        let field = synthetic_field(800, 800, 9);
        let refs = refs_from(&field);
        let moved = shift_field(&field, 2.3, -1.1);
        let offset = measure_offset(&refs, &moved, Vec2::default()).expect("offset");
        assert!((offset.x - 2.3).abs() < 1e-6, "x={}", offset.x);
        assert!((offset.y + 1.1).abs() < 1e-6, "y={}", offset.y);
    }

    #[test]
    fn one_star_jump_does_not_move_robust_offset() {
        // All stars shifted by a true (1.0, 0.5); one star additionally "jumps"
        // by a large spurious amount. The sigma-clipped offset must reject it.
        let field = synthetic_field(800, 800, 9);
        let refs = refs_from(&field);
        let mut moved = shift_field(&field, 1.0, 0.5);
        // Make the first detection jump far (within match distance of its ref+true
        // shift so it still associates, but as an outlier displacement).
        moved[0].x += 8.0;
        moved[0].y += 8.0;

        let robust = measure_offset(&refs, &moved, Vec2::default()).expect("offset");
        assert!(
            (robust.x - 1.0).abs() < 0.15 && (robust.y - 0.5).abs() < 0.15,
            "robust offset should reject the jumped star: got ({}, {})",
            robust.x,
            robust.y
        );

        // A naive (non-clipped) mean would be visibly pulled by the outlier.
        let naive = {
            let disps = matched_displacements(&refs, &moved, Vec2::default());
            let mut sx = 0.0;
            let mut sy = 0.0;
            for d in &disps {
                sx += d.delta.x;
                sy += d.delta.y;
            }
            Vec2 {
                x: sx / disps.len() as f64,
                y: sy / disps.len() as f64,
            }
        };
        assert!(
            naive.x > robust.x + 0.3,
            "naive mean should be pulled by the outlier (naive={}, robust={})",
            naive.x,
            robust.x
        );
    }

    #[test]
    fn star_loss_continuity_keeps_guiding_with_two_stars() {
        let field = synthetic_field(800, 800, 9);
        let refs = refs_from(&field);
        // Only two of the nine stars are still detectable (clouds ate the rest).
        let moved_full = shift_field(&field, 1.5, -2.0);
        let surviving: Vec<DetectedStar> = moved_full.into_iter().take(2).collect();
        let offset = measure_offset(&refs, &surviving, Vec2::default())
            .expect("offset should survive on two stars");
        assert!((offset.x - 1.5).abs() < 1e-6);
        assert!((offset.y + 2.0).abs() < 1e-6);
    }

    #[test]
    fn no_matched_stars_yields_no_offset() {
        let field = synthetic_field(800, 800, 9);
        let refs = refs_from(&field);
        // Detections far from every reference: nothing matches.
        let far = vec![star_q(2000.0, 2000.0, 5000.0, 20.0, 5000.0, 0.1)];
        assert!(measure_offset(&refs, &far, Vec2::default()).is_none());
    }

    #[test]
    fn single_star_falls_back_to_plain_weighted_mean() {
        // Below the clip threshold, a single matched star is used directly.
        let refs = vec![GuideReferenceStar {
            x: 100.0,
            y: 100.0,
            flux: 5000.0,
            snr: 20.0,
            last_residual: None,
        }];
        let moved = vec![star_q(103.0, 98.0, 5000.0, 20.0, 5000.0, 0.1)];
        let offset = measure_offset(&refs, &moved, Vec2::default()).expect("offset");
        assert!((offset.x - 3.0).abs() < 1e-6);
        assert!((offset.y + 2.0).abs() < 1e-6);
    }

    // --- Calibration math ----------------------------------------------------

    #[test]
    fn calibration_recovers_angles_rates_and_orthogonality() {
        // RA along +x at 4 px/pulse, Dec along +y at 3 px/pulse: orthogonal.
        let east = Vec2 { x: 4.0, y: 0.0 };
        let north = Vec2 { x: 0.0, y: 3.0 };
        let calib = build_calibration(east, north, 250.0, 0.0).expect("calib");
        assert!((calib.ra_rate() - 4.0 / 250.0).abs() < 1e-9);
        assert!((calib.dec_rate() - 3.0 / 250.0).abs() < 1e-9);
        assert!((calib.orthogonality_deg - 90.0).abs() < 1e-6);
    }

    #[test]
    fn calibration_measures_non_orthogonal_axes() {
        // RA along +x, Dec at 60° from RA.
        let east = Vec2 { x: 4.0, y: 0.0 };
        let north = Vec2 {
            x: 3.0 * 60f64.to_radians().cos(),
            y: 3.0 * 60f64.to_radians().sin(),
        };
        let calib = build_calibration(east, north, 250.0, 0.0).expect("calib");
        assert!((calib.orthogonality_deg - 60.0).abs() < 1e-6);
    }

    #[test]
    fn calibration_rejects_singular_axes() {
        // Both axes parallel -> singular -> error.
        let east = Vec2 { x: 4.0, y: 0.0 };
        let north = Vec2 { x: 2.0, y: 0.0 };
        assert!(build_calibration(east, north, 250.0, 0.0).is_err());
    }

    #[test]
    fn dec_backlash_recovered_from_short_first_reversal() {
        // Forward 3 px/pulse; the first reverse pulse only travelled 2.1 px, i.e.
        // 0.9 px short. At 3 px / 250 ms = 0.012 px/ms, that is 75 ms of backlash.
        let fwd = Vec2 { x: 0.0, y: 3.0 };
        let rev_first = Vec2 { x: 0.0, y: -2.1 };
        let backlash = estimate_dec_backlash_ms(fwd, rev_first, 250.0);
        assert!((backlash - 75.0).abs() < 1.0, "backlash={backlash}");
    }

    #[test]
    fn no_backlash_when_reversal_is_full() {
        let fwd = Vec2 { x: 0.0, y: 3.0 };
        let rev_first = Vec2 { x: 0.0, y: -3.0 };
        assert_eq!(estimate_dec_backlash_ms(fwd, rev_first, 250.0), 0.0);
    }

    // --- Corrections: aggressiveness, clamps, backlash compensation ----------

    fn ortho_calib(backlash_ms: f64) -> GuideCalibration {
        // RA +x, Dec +y, 1 px/pulse on each, pulse = 100 ms.
        build_calibration(
            Vec2 { x: 1.0, y: 0.0 },
            Vec2 { x: 0.0, y: 1.0 },
            100.0,
            backlash_ms,
        )
        .expect("calib")
    }

    #[test]
    fn correction_applies_aggressiveness() {
        let calib = ortho_calib(0.0);
        let mut config = GuiderConfig {
            ra_aggressiveness: 0.5,
            dec_aggressiveness: 0.5,
            min_move_px: 0.0,
            min_pulse_ms: 0.0,
            ..GuiderConfig::default()
        };
        config.max_pulse_ms = 100000.0;
        // Offset of (10, 10) px -> to null it, pulse -10 px each axis = -1000 ms
        // raw; at 0.5 aggressiveness => -500 ms.
        let plan = compute_pulse_durations(calib, Vec2 { x: 10.0, y: 10.0 }, &config, None);
        let ra = plan.ra_ms.expect("ra");
        // First Dec pulse pays backlash, but backlash=0 here.
        let dec = plan.dec_ms.expect("dec");
        assert!((ra + 500.0).abs() < 1e-6, "ra={ra}");
        assert!((dec + 500.0).abs() < 1e-6, "dec={dec}");
    }

    #[test]
    fn correction_min_move_suppresses_tiny_offset() {
        let calib = ortho_calib(0.0);
        let config = GuiderConfig {
            min_move_px: 0.5,
            ..GuiderConfig::default()
        };
        // 0.1 px offset is below min_move -> no pulses.
        let plan = compute_pulse_durations(calib, Vec2 { x: 0.1, y: 0.1 }, &config, None);
        assert!(plan.ra_ms.is_none());
        assert!(plan.dec_ms.is_none());
    }

    #[test]
    fn correction_clamps_to_max_pulse() {
        let calib = ortho_calib(0.0);
        let config = GuiderConfig {
            ra_aggressiveness: 1.0,
            dec_aggressiveness: 1.0,
            min_move_px: 0.0,
            max_pulse_ms: 300.0,
            ..GuiderConfig::default()
        };
        // 50 px offset -> 5000 ms raw, clamped to 300 ms.
        let plan = compute_pulse_durations(calib, Vec2 { x: 50.0, y: 0.0 }, &config, None);
        assert!((plan.ra_ms.expect("ra").abs() - 300.0).abs() < 1e-6);
    }

    #[test]
    fn dec_backlash_added_only_on_reversal() {
        let calib = ortho_calib(120.0); // 120 ms backlash
        let config = GuiderConfig {
            ra_aggressiveness: 1.0,
            dec_aggressiveness: 1.0,
            min_move_px: 0.0,
            min_pulse_ms: 0.0,
            max_pulse_ms: 100000.0,
            ..GuiderConfig::default()
        };
        // Offset (0, 5) -> null with Dec -500 ms (South). Coming from North => reversal.
        let reversal = compute_pulse_durations(
            calib,
            Vec2 { x: 0.0, y: 5.0 },
            &config,
            Some(DecDirection::North),
        );
        let dec_rev = reversal.dec_ms.expect("dec");
        assert!(
            (dec_rev + 620.0).abs() < 1e-6,
            "reversal should add 120ms backlash: {dec_rev}"
        );
        assert_eq!(reversal.new_dec_direction, Some(DecDirection::South));

        // Same correction but already moving South => no backlash added.
        let same_dir = compute_pulse_durations(
            calib,
            Vec2 { x: 0.0, y: 5.0 },
            &config,
            Some(DecDirection::South),
        );
        assert!((same_dir.dec_ms.expect("dec") + 500.0).abs() < 1e-6);
    }

    // --- Adaptive / spiral dither -------------------------------------------

    #[test]
    fn dither_spiral_walks_to_fresh_pixels() {
        let p0 = dither_offset(5.0, false, 0, None);
        let p1 = dither_offset(5.0, false, 1, None);
        let p2 = dither_offset(5.0, false, 2, None);
        // Successive steps are well separated (not re-treading one spot).
        let d01 = (Vec2 {
            x: p0.x - p1.x,
            y: p0.y - p1.y,
        })
        .magnitude();
        let d12 = (Vec2 {
            x: p1.x - p2.x,
            y: p1.y - p2.y,
        })
        .magnitude();
        assert!(d01 > 1.0 && d12 > 1.0, "steps too close: {d01}, {d12}");
        // Radius grows with step (sunflower spiral expands).
        assert!(p2.magnitude() > p0.magnitude());
    }

    #[test]
    fn dither_adapts_to_poor_seeing() {
        let good = dither_offset(5.0, false, 3, Some(0.0));
        let poor = dither_offset(5.0, false, 3, Some(10.0));
        assert!(
            poor.magnitude() > good.magnitude(),
            "poor seeing should dither larger: good={}, poor={}",
            good.magnitude(),
            poor.magnitude()
        );
    }

    #[test]
    fn dither_ra_only_stays_on_ra_axis_and_alternates() {
        let s0 = dither_offset(4.0, true, 0, None);
        let s1 = dither_offset(4.0, true, 1, None);
        assert_eq!(s0.y, 0.0);
        assert_eq!(s1.y, 0.0);
        assert!(
            s0.x.signum() != s1.x.signum(),
            "RA-only should alternate sign"
        );
    }

    // =========================================================================
    // start/stop lifecycle race (v4 review blocker #7)
    //
    // The built-in guider stores the loop's `stop_flag`/`task` AFTER spawning the
    // loop, so a concurrent `stop()` in that window found `None`, signalled
    // nothing, and orphaned a mount-pulsing loop. The fix stores the stop flag in
    // the same write-lock critical section that flips the run-state (before the
    // spawn) and serializes every lifecycle entry point with `op_lock`, so a stop
    // can never interleave a start and lose the cancel. These tests use a
    // synthetic loop (no hardware) that reports liveness so an orphan is directly
    // observable.
    // =========================================================================

    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Serializes the lifecycle race tests, which all mutate the same
    /// process-global guider singleton. Cargo runs tests in parallel by default;
    /// without this, one test's `reset_guider_state` would wipe another's loop
    /// mid-flight. (Distinct from the production `op_lock`, which serializes
    /// lifecycle ops but does not stop one test from resetting another's state.)
    static TEST_SERIAL: OnceLock<Arc<Mutex<()>>> = OnceLock::new();

    fn test_serial() -> &'static Arc<Mutex<()>> {
        TEST_SERIAL.get_or_init(|| Arc::new(Mutex::new(())))
    }

    /// Reset the shared guider state between race tests (they all touch the same
    /// process-global singleton).
    async fn reset_guider_state() {
        let _op = op_lock().lock().await;
        let _ = stop_locked().await;
        *state().write().await = BuiltinGuiderState::default();
    }

    /// Spin until `cond()` is true or the deadline elapses; returns whether the
    /// condition held.
    async fn wait_until<F: Fn() -> bool>(cond: F, max: Duration) -> bool {
        let deadline = Instant::now() + max;
        while Instant::now() < deadline {
            if cond() {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        cond()
    }

    #[tokio::test]
    async fn start_then_immediate_stop_cancels_loop() {
        let _serial = test_serial().lock().await;
        reset_guider_state().await;
        let live = Arc::new(AtomicUsize::new(0));

        start_synthetic_loop(live.clone()).await;
        // The loop is live (or about to be); `stop()` must cancel it regardless of
        // exactly where it is between spawn and handle-record.
        stop().await.expect("stop");

        // After stop returns, the loop must be gone: its handle was joined, so the
        // spinning task observed the flag and exited.
        assert_eq!(
            live.load(Ordering::SeqCst),
            0,
            "loop still alive after stop — orphaned mount-pulsing task"
        );
        let guard = state().read().await;
        assert!(!guard.guiding, "guiding must be cleared by stop");
        assert!(
            guard.stop_flag.is_none(),
            "stop must consume the stop_flag (no dead handle left behind)"
        );
        assert!(guard.task.is_none(), "stop must consume the task handle");
    }

    #[tokio::test]
    async fn active_loop_always_has_a_live_stop_flag() {
        let _serial = test_serial().lock().await;
        // The invariant the old ordering violated: whenever the run-state says a
        // loop is active, a `stop_flag` is present for `stop()` to signal. The old
        // code set `guiding=true`, released the lock, spawned, and only THEN stored
        // the flag — leaving a window where `guiding==true && stop_flag==None`.
        reset_guider_state().await;
        let live = Arc::new(AtomicUsize::new(0));
        start_synthetic_loop(live.clone()).await;

        {
            let guard = state().read().await;
            assert!(guard.guiding || guard.looping || guard.calibrating);
            assert!(
                guard.stop_flag.is_some(),
                "active loop must always carry a live stop_flag"
            );
            assert!(
                guard.task.is_some(),
                "active loop must have its JoinHandle recorded"
            );
        }

        stop().await.expect("stop");
        assert_eq!(live.load(Ordering::SeqCst), 0, "loop must be cancelled");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_start_stop_start_never_orphans_loop() {
        let _serial = test_serial().lock().await;
        // Reproduce the permanent-orphan window: two starts and a stop fired
        // concurrently. With the pre-fix ordering, a stop landing in start1's
        // spawn→record window dropped start1's cancel, then start2 OVERWROTE the
        // stored flag/handle — stranding loop1 forever (its flag clone is no longer
        // reachable from any future stop). `live` (loops currently running) must
        // return to 0 after a final stop; a non-zero count is a leaked
        // mount-pulsing loop. The op-lock makes start1/stop/start2 atomic, so each
        // start's `stop_locked()` joins the prior loop and nothing leaks.
        for round in 0..150 {
            reset_guider_state().await;
            let live = Arc::new(AtomicUsize::new(0));

            let l1 = live.clone();
            let l2 = live.clone();
            let start1 = tokio::spawn(async move { start_synthetic_loop(l1).await });
            let stopper = tokio::spawn(async move {
                let _ = stop().await;
            });
            let start2 = tokio::spawn(async move { start_synthetic_loop(l2).await });
            let _ = tokio::join!(start1, stopper, start2);

            // A final stop must guarantee no loop is left running.
            stop().await.expect("final stop");

            let settled =
                wait_until(|| live.load(Ordering::SeqCst) == 0, Duration::from_secs(2)).await;
            assert!(
                settled,
                "round {round}: {} loop(s) survived a final stop() — orphaned mount-pulsing task",
                live.load(Ordering::SeqCst)
            );

            let guard = state().read().await;
            assert!(
                !guard.guiding && !guard.looping && !guard.calibrating,
                "round {round}: run-state still active after final stop"
            );
            assert!(
                guard.stop_flag.is_none() && guard.task.is_none(),
                "round {round}: dead handle/flag left in state after final stop"
            );
        }
    }
}
