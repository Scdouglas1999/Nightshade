//! Built-in multi-star guider.
//!
//! # `as`-cast policy (audit-rust §1.4)
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
//! # `unwrap_or` policy (audit-rust §4.3)
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
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tokio::task::JoinHandle;

const BUILTIN_GUIDER_ID: &str = "native:builtin_guider:multi_star";
const GUIDE_MAX_MATCH_DISTANCE_PX: f64 = 20.0;
const GUIDE_MAX_TRACKED_STARS: usize = 8;
const GUIDE_MIN_STAR_SEPARATION_PX: f64 = 10.0;

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
}

#[derive(Clone, Copy, Debug)]
struct GuideCalibration {
    east: Vec2,
    north: Vec2,
    pulse_ms: f64,
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
            stop_flag: None,
            task: None,
            config: GuiderConfig::default(),
        }
    }
}

static BUILTIN_GUIDER: OnceLock<Arc<RwLock<BuiltinGuiderState>>> = OnceLock::new();

fn state() -> &'static Arc<RwLock<BuiltinGuiderState>> {
    BUILTIN_GUIDER.get_or_init(|| Arc::new(RwLock::new(BuiltinGuiderState::default())))
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
    stop().await?;
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
    stop().await?;

    {
        let mut guard = state().write().await;
        guard.guiding = true;
        guard.looping = false;
        guard.calibrating = true;
        guard.last_status.state = "Calibrating".to_string();
        guard.last_status.connected = true;
    }

    get_state().publish_guiding_event(GuidingEvent::Calibrating, EventSeverity::Info);

    let controller = state().clone();
    let stop_flag = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let stop_flag_for_task = stop_flag.clone();

    let task = tokio::spawn(async move {
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
            get_state().publish_guiding_event(GuidingEvent::Disconnected, EventSeverity::Warning);
        }
    });

    let mut guard = state().write().await;
    guard.stop_flag = Some(stop_flag);
    guard.task = Some(task);
    Ok(())
}

pub async fn loop_exposures() -> Result<(), NightshadeError> {
    ensure_connected().await?;
    stop().await?;

    {
        let mut guard = state().write().await;
        guard.guiding = false;
        guard.looping = true;
        guard.calibrating = false;
        guard.last_status.state = "Looping".to_string();
        guard.last_status.connected = true;
    }

    get_state().publish_guiding_event(GuidingEvent::Looping, EventSeverity::Info);

    let controller = state().clone();
    let stop_flag = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let stop_flag_for_task = stop_flag.clone();

    let task = tokio::spawn(async move {
        loop {
            if stop_flag_for_task.load(std::sync::atomic::Ordering::Relaxed) {
                break;
            }
            if let Err(error) = capture_and_store_loop_frame(controller.clone()).await {
                tracing::warn!("Built-in guider looping frame failed: {}", error);
                tokio::time::sleep(Duration::from_millis(500)).await;
            }
        }
    });

    let mut guard = state().write().await;
    guard.stop_flag = Some(stop_flag);
    guard.task = Some(task);
    Ok(())
}

pub async fn stop() -> Result<(), NightshadeError> {
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

pub async fn dither(
    amount: f64,
    ra_only: bool,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    ensure_connected().await?;
    let seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as f64;
    let angle = if ra_only {
        0.0
    } else {
        (seed % 6283.185307179586) / 1000.0
    };
    let offset = Vec2 {
        x: amount * angle.cos(),
        y: if ra_only { 0.0 } else { amount * angle.sin() },
    };

    let mut guard = state().write().await;
    guard.desired_offset = Vec2 {
        x: guard.desired_offset.x + offset.x,
        y: guard.desired_offset.y + offset.y,
    };
    guard.dither_pending = true;
    // Reset settle state and arm the timeout for this dither settle
    guard.settle_deadline = None;
    let timeout_secs = settle_timeout.max(settle_time + 1.0);
    guard.settle_timeout_deadline = Some(Instant::now() + Duration::from_secs_f64(timeout_secs));
    // Store settle params so the guiding loop's apply_settle_state can use them
    // (settle_pixels and settle_time are already threaded through run_guiding_loop)
    let _ = (settle_pixels, settle_time); // used by the guiding loop that's already running
    get_state().publish_guiding_event(
        GuidingEvent::DitherStarted { pixels: amount },
        EventSeverity::Info,
    );
    Ok(())
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
    guard.reference_stars = select_reference_stars(&guide_frame.stars);
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
    guard.reference_stars = select_reference_stars(&guide_frame.stars);
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

pub fn device_id() -> &'static str {
    BUILTIN_GUIDER_ID
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

    if !app_state
        .is_device_connected(DeviceType::Camera, &camera_id)
        .await
    {
        return Err(NightshadeError::NotConnected(camera_id));
    }
    if !app_state
        .is_device_connected(DeviceType::Mount, &mount_id)
        .await
    {
        return Err(NightshadeError::NotConnected(mount_id));
    }

    Ok((camera_id, mount_id))
}

async fn first_connected_device(device_type: DeviceType) -> Option<String> {
    get_state()
        .get_devices(device_type)
        .await
        .into_iter()
        .map(|device| device.id)
        .next()
}

async fn capture_guide_frame() -> Result<GuideFrame, NightshadeError> {
    let (camera_id, _) = resolve_devices().await?;
    let config = state().read().await.config.clone();
    let device_manager = get_device_manager();

    device_manager
        .camera_start_exposure(
            &camera_id,
            config.exposure_secs,
            config.gain,
            config.offset,
            config.binning,
            config.binning,
        )
        .await
        .map_err(NightshadeError::OperationFailed)?;

    loop {
        if device_manager
            .camera_is_exposure_complete(&camera_id)
            .await
            .map_err(NightshadeError::OperationFailed)?
        {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    let native_image = device_manager
        .camera_download_image(&camera_id)
        .await
        .map_err(NightshadeError::OperationFailed)?;
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
                guard.reference_stars = select_reference_stars(&frame.stars);
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

        apply_settle_state(
            controller.clone(),
            offset.magnitude(),
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .await?;
        apply_guide_correction(calibration, offset).await?;
    }

    Ok(())
}

async fn calibrate_mount_response(
    controller: Arc<RwLock<BuiltinGuiderState>>,
) -> Result<GuideCalibration, NightshadeError> {
    let baseline = capture_guide_frame().await?;
    {
        let mut guard = controller.write().await;
        guard.reference_stars = select_reference_stars(&baseline.stars);
        guard.manual_lock = choose_lock_star(&baseline.stars, None, None).map(|star| Vec2 {
            x: star.x,
            y: star.y,
        });
        update_snapshot_from_frame(&mut guard, &baseline, 50);
        guard.last_frame = Some(baseline.clone());
    }

    let east = calibrate_axis_response("east", "west", &baseline).await?;
    let north = calibrate_axis_response("north", "south", &baseline).await?;

    let determinant = east.x * north.y - east.y * north.x;
    if determinant.abs() < 1e-3 {
        return Err(NightshadeError::OperationFailed(
            "Built-in guider calibration is singular; mount pulse responses were not distinct"
                .to_string(),
        ));
    }

    let config = controller.read().await.config.clone();
    Ok(GuideCalibration {
        east,
        north,
        pulse_ms: config.calibration_ms as f64,
    })
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
        .map_err(NightshadeError::OperationFailed)?;
    tokio::time::sleep(Duration::from_millis(config.settle_sleep_ms)).await;
    let moved_frame = capture_guide_frame().await?;
    let offset = measure_offset(
        &select_reference_stars(&baseline.stars),
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
        .map_err(NightshadeError::OperationFailed)?;
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

fn measure_offset(
    reference_stars: &[GuideReferenceStar],
    current_stars: &[DetectedStar],
    desired_offset: Vec2,
) -> Option<Vec2> {
    let mut weighted_x = 0.0;
    let mut weighted_y = 0.0;
    let mut total_weight = 0.0;
    for reference in reference_stars {
        let expected = Vec2 {
            x: reference.x + desired_offset.x,
            y: reference.y + desired_offset.y,
        };
        if let Some(star) = nearest_star(current_stars, expected, GUIDE_MAX_MATCH_DISTANCE_PX) {
            let weight = guide_reference_weight(reference);
            weighted_x += (star.x - expected.x) * weight;
            weighted_y += (star.y - expected.y) * weight;
            total_weight += weight;
        }
    }

    if total_weight <= 0.0 {
        return None;
    }

    Some(Vec2 {
        x: weighted_x / total_weight,
        y: weighted_y / total_weight,
    })
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

async fn apply_guide_correction(
    calibration: GuideCalibration,
    offset: Vec2,
) -> Result<(), NightshadeError> {
    let determinant =
        calibration.east.x * calibration.north.y - calibration.east.y * calibration.north.x;
    if determinant.abs() < 1e-6 {
        return Ok(());
    }

    let target = Vec2 {
        x: -offset.x,
        y: -offset.y,
    };
    let east_scale =
        (target.x * calibration.north.y - target.y * calibration.north.x) / determinant;
    let north_scale = (calibration.east.x * target.y - calibration.east.y * target.x) / determinant;

    pulse_from_scale("east", "west", east_scale * calibration.pulse_ms).await?;
    pulse_from_scale("north", "south", north_scale * calibration.pulse_ms).await?;
    Ok(())
}

async fn pulse_from_scale(
    positive_direction: &str,
    negative_direction: &str,
    pulse_ms: f64,
) -> Result<(), NightshadeError> {
    let config = state().read().await.config.clone();
    let magnitude = pulse_ms.abs();
    if magnitude < config.min_pulse_ms {
        return Ok(());
    }

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
        .map_err(NightshadeError::OperationFailed)
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

fn select_reference_stars(stars: &[DetectedStar]) -> Vec<GuideReferenceStar> {
    let mut selected = Vec::new();
    for star in stars {
        if selected.len() >= GUIDE_MAX_TRACKED_STARS {
            break;
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
        let refs = select_reference_stars(&stars);
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
            },
            GuideReferenceStar {
                x: 30.0,
                y: 30.0,
                flux: 900.0,
                snr: 9.0,
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
            },
            GuideReferenceStar {
                x: 30.0,
                y: 30.0,
                flux: 100.0,
                snr: 2.0,
            },
        ];
        let stars = vec![star(12.0, 10.0, 10000.0), star(30.0, 40.0, 100.0)];
        let offset = measure_offset(&refs, &stars, Vec2::default()).expect("offset");

        assert!(offset.x > 1.8);
        assert!(offset.y < 1.0);
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
}
