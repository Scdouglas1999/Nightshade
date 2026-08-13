// split from monolithic api.rs
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs.
//
// # `as`-cast policy
//
// Numeric casts in this file cluster into:
// - **Image dim u32 → u32** (lines 109, 110, 135, 136, 792, 793): `image.width`
//   and `image.height` are already u32; the `as u32` is a no-op widening
//   useful only for clippy disambiguation when builders accept ambiguous
//   types. Kept as documentation.
// - **PolarAlignmentPoint enum → i32** (lines 302, 326, 335, 385, 401, 403,
//   411): the enum has 3 discriminants {0, 1, 2}; `as i32` extracts the
//   value — SAFE narrowing from default isize repr.
// - **Step size f64 → i32** (line 401): bounded by mount slew step (≤ 90°
//   typical); used only in a display string, not a hardware command.
// - **RGBA u8 → u32/u16 luminance** (lines 775, 785): u8 → u32 is exact
//   widening; the average of three u8 values is ≤ 255 so `as u16 * 256`
//   stays well inside u16. SAFE.
use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
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
// Polar Alignment
// =============================================================================

use std::sync::atomic::{AtomicBool as PolarAtomicBool, Ordering as PolarOrdering};
use tokio::task::JoinHandle;

/// Track whether polar alignment is running
pub(crate) static POLAR_ALIGN_RUNNING: OnceLock<PolarAtomicBool> = OnceLock::new();
pub(crate) static POLAR_ALIGN_CANCEL: OnceLock<PolarAtomicBool> = OnceLock::new();

/// Monotonic per-run generation. Bumped when a run is admitted; the spawned
/// task carries the value it was born with and treats a mismatch as "a newer
/// run now owns the hardware — exit silently without clearing its flag or
/// emitting over its status". This is the belt-and-suspenders that makes a
/// stale, force-aborted task unable to corrupt a subsequent run.
static POLAR_ALIGN_GENERATION: AtomicU64 = AtomicU64::new(0);

/// The currently-owned alignment task handle. [`api_stop_polar_alignment`]
/// takes and awaits it (bounded) so stop returns only once the run is actually
/// terminated — never while the old task can still touch the camera/mount.
static POLAR_ALIGN_TASK: OnceLock<Mutex<Option<JoinHandle<()>>>> = OnceLock::new();

/// Serializes start setup with stop teardown. The running atomic alone cannot
/// protect the interval between admitting a run and storing its task handle:
/// without this lock, Stop can observe `running=true`, find no handle yet,
/// clear the flag, and return while Start subsequently launches an orphaned
/// camera/mount task.
static POLAR_ALIGN_CONTROL: OnceLock<Mutex<()>> = OnceLock::new();

/// Bounded grace for a cooperative stop before we force-abort the task.
const POLAR_STOP_CLEAN_GRACE_SECS: u64 = 6;
/// Bounded grace to confirm the task unwound after a force-abort.
const POLAR_STOP_ABORT_GRACE_SECS: u64 = 4;

pub(crate) fn get_polar_align_flag() -> &'static PolarAtomicBool {
    POLAR_ALIGN_RUNNING.get_or_init(|| PolarAtomicBool::new(false))
}

pub(crate) fn get_polar_align_cancel() -> &'static PolarAtomicBool {
    POLAR_ALIGN_CANCEL.get_or_init(|| PolarAtomicBool::new(false))
}

fn polar_generation() -> &'static AtomicU64 {
    &POLAR_ALIGN_GENERATION
}

fn polar_task_slot() -> &'static Mutex<Option<JoinHandle<()>>> {
    POLAR_ALIGN_TASK.get_or_init(|| Mutex::new(None))
}

fn polar_control_lock() -> &'static Mutex<()> {
    POLAR_ALIGN_CONTROL.get_or_init(|| Mutex::new(()))
}

/// Atomically admit a new run. Returns `None` when another run already owns
/// the hardware. A load-then-store check is insufficient because two FRB calls
/// may execute concurrently on Tokio and both observe `false`.
fn try_admit_polar_run() -> Option<u64> {
    get_polar_align_flag()
        .compare_exchange(false, true, PolarOrdering::AcqRel, PolarOrdering::Acquire)
        .ok()?;
    get_polar_align_cancel().store(false, PolarOrdering::Relaxed);
    // fetch_add returns the previous value; our generation is that + 1.
    Some(polar_generation().fetch_add(1, PolarOrdering::Relaxed) + 1)
}

/// Clear the running flag only if `generation` is still the current run. A
/// task that has been superseded must not clear a newer run's flag.
fn release_polar_run_if_current(generation: u64) {
    if polar_generation().load(PolarOrdering::Relaxed) == generation {
        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
    }
}

/// Store the owning task handle for the current run, replacing (and dropping)
/// any finished handle left from a prior run.
async fn store_polar_task(handle: JoinHandle<()>) {
    *polar_task_slot().lock().await = Some(handle);
}

/// Outcome of a per-iteration stop check inside a running alignment task.
enum PolarLoopControl {
    /// Keep running — this task still owns the run and no cancel is pending.
    Continue,
    /// A newer run has taken the generation; exit silently so we neither stomp
    /// its status nor clear its running flag.
    Superseded,
    /// The user cancelled this run; exit and emit an idle status.
    Cancelled,
}

/// Combined generation + cancellation checkpoint. Prefer this over a bare
/// cancel-flag read inside alignment loops so a superseded task bails without
/// emitting over a newer run.
fn polar_loop_control(generation: u64) -> PolarLoopControl {
    if polar_generation().load(PolarOrdering::Relaxed) != generation {
        PolarLoopControl::Superseded
    } else if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
        PolarLoopControl::Cancelled
    } else {
        PolarLoopControl::Continue
    }
}

// =============================================================================
// Slew-to-pole start mode (start_from_current = false)
// =============================================================================

/// Max wall-clock for the pole-region slew to settle before we abort + fail.
const POLE_SLEW_TIMEOUT_SECS: u64 = 120;
/// Fallback settle wait when the driver cannot report `slewing`.
const POLE_SLEW_SETTLE_SECS: u64 = 8;
/// How far from the true pole the pole-region target sits, in degrees. 30° puts
/// the scope at the outer edge of the classic TPPA region (≈30° around the
/// pole) while keeping the 3-point rotation-arc geometry well conditioned
/// (cos 60° = 0.5 of the RA step projects onto the sky, versus a near-degenerate
/// projection right at the pole).
const POLE_REGION_OFFSET_DEG: f64 = 30.0;

/// Outcome of the pole-region slew preamble.
enum SlewOutcome {
    /// The mount reached and settled on the pole-region target.
    Settled,
    /// The user cancelled during the slew (the mount was aborted).
    Cancelled,
    /// A newer run took over during the slew (the mount was aborted).
    Superseded,
}

/// Compute the "slew to pole region" target `(ra_hours, dec_degrees)`.
///
/// The target sits on the local meridian (RA == LST, i.e. hour angle 0) so it
/// culminates — highest above the horizon, least atmosphere, best for plate
/// solving — and [`POLE_REGION_OFFSET_DEG`] from the celestial pole toward the
/// equator so the subsequent three-point RA arc keeps good geometry. Northern
/// observers point at +Dec, southern at −Dec.
///
/// Pure and deterministic given `(lst_hours, is_north)` so it can be unit
/// tested without hardware.
pub(crate) fn pole_region_target(lst_hours: f64, is_north: bool) -> (f64, f64) {
    let ra_hours = lst_hours.rem_euclid(24.0);
    let dec_degrees = if is_north {
        90.0 - POLE_REGION_OFFSET_DEG
    } else {
        -90.0 + POLE_REGION_OFFSET_DEG
    };
    (ra_hours, dec_degrees)
}

/// Slew the mount to the pole region and wait — with abort ordering — until the
/// motion actually settles.
///
/// Ordering guarantees (adversarially important): a cancellation or supersession
/// observed *while slewing* issues `mount_abort_slew` BEFORE returning, so the
/// mount is commanded to stop before the caller settles/idles. A driver that
/// cannot report `slewing` falls back to a bounded fixed settle rather than
/// spinning. A hard timeout also aborts and fails truthfully — it never reports
/// the slew as done early.
async fn slew_to_pole_region(
    mount_id: &str,
    is_north: bool,
    longitude_deg: f64,
    generation: u64,
) -> Result<SlewOutcome, String> {
    use nightshade_sequencer::meridian::{julian_day, local_sidereal_time};

    let now = chrono::Utc::now();
    let jd = julian_day(&now);
    let lst = local_sidereal_time(jd, longitude_deg);
    let (target_ra_h, target_dec) = pole_region_target(lst, is_north);

    emit_polar_status(
        &format!(
            "Slewing to pole region (RA {:.2}h, Dec {:.0}°)...",
            target_ra_h, target_dec
        ),
        "measuring",
        0,
    );

    let device_ops = create_unified_device_ops();

    // Honour a cancel/supersede that arrives before the slew is even issued.
    match polar_loop_control(generation) {
        PolarLoopControl::Continue => {}
        PolarLoopControl::Superseded => return Ok(SlewOutcome::Superseded),
        PolarLoopControl::Cancelled => return Ok(SlewOutcome::Cancelled),
    }

    device_ops
        .mount_slew_to_coordinates(mount_id, target_ra_h, target_dec)
        .await
        .map_err(|e| format!("Failed to slew to pole region: {}", e))?;

    // Wait for settle. `mount_slew_to_coordinates` may return before the mount
    // physically stops (async drivers), so poll `slewing`.
    let deadline = Instant::now() + Duration::from_secs(POLE_SLEW_TIMEOUT_SECS);
    loop {
        match polar_loop_control(generation) {
            PolarLoopControl::Continue => {}
            PolarLoopControl::Superseded => {
                let _ = device_ops.mount_abort_slew(mount_id).await;
                return Ok(SlewOutcome::Superseded);
            }
            PolarLoopControl::Cancelled => {
                let _ = device_ops.mount_abort_slew(mount_id).await;
                return Ok(SlewOutcome::Cancelled);
            }
        }

        match device_ops.mount_is_slewing(mount_id).await {
            Ok(false) => break, // settled
            Ok(true) => {}      // keep waiting
            Err(e) => {
                // Driver can't report slew state — do a bounded fixed settle
                // rather than busy-looping forever, then proceed.
                tracing::warn!(
                    "mount_is_slewing failed ({}); using {}s fixed settle",
                    e,
                    POLE_SLEW_SETTLE_SECS
                );
                tokio::time::sleep(Duration::from_secs(POLE_SLEW_SETTLE_SECS)).await;
                break;
            }
        }

        if Instant::now() >= deadline {
            let _ = device_ops.mount_abort_slew(mount_id).await;
            return Err(format!(
                "Timed out after {}s waiting for the mount to reach the pole region",
                POLE_SLEW_TIMEOUT_SECS
            ));
        }

        tokio::time::sleep(Duration::from_millis(500)).await;
    }

    // Short mechanical settle after motion stops before the first exposure.
    tokio::time::sleep(Duration::from_secs(1)).await;
    Ok(SlewOutcome::Settled)
}

/// Emit a polar alignment status update (JSON-serializable for Dart)
pub(crate) fn emit_polar_status(status: &str, phase: &str, point: i32) {
    tracing::info!(
        "Polar alignment: {} (phase={}, point={})",
        status,
        phase,
        point
    );
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignmentStatus(PolarAlignmentStatus {
            status: status.to_string(),
            phase: phase.to_string(),
            point,
        }),
    ));
}

/// Emit polar alignment error update
pub(crate) fn emit_polar_error(
    az: f64,
    alt: f64,
    total: f64,
    cur_ra: f64,
    cur_dec: f64,
    tgt_ra: f64,
    tgt_dec: f64,
) {
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignment(PolarAlignmentEvent {
            azimuth_error: az,
            altitude_error: alt,
            total_error: total,
            current_ra: cur_ra,
            current_dec: cur_dec,
            target_ra: tgt_ra,
            target_dec: tgt_dec,
        }),
    ));
}

/// Unit boundary for plate-solve output consumed by polar geometry. The
/// bridge result already reports RA in degrees; keep that explicit so this
/// path cannot silently reintroduce the historical hours-to-degrees multiply.
fn plate_solve_ra_degrees(ra_degrees: f64) -> f64 {
    ra_degrees
}

/// Emit polar alignment image for UI display
/// Encodes the display data to JPEG for efficient transmission
pub(crate) fn emit_polar_image(
    image: &CapturedImageResult,
    point: i32,
    phase: &str,
    solved_ra: Option<f64>,
    solved_dec: Option<f64>,
) {
    use image::ImageEncoder;

    // Encode display_data (RGBA) to JPEG
    let mut buffer = Vec::new();
    {
        let mut cursor = std::io::Cursor::new(&mut buffer);
        let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, 85);
        if let Err(e) = encoder.write_image(
            &image.display_data,
            image.width as u32,
            image.height as u32,
            image::ColorType::Rgba8,
        ) {
            tracing::warn!("Failed to encode polar alignment image: {}", e);
            return;
        }
    }
    let color_type = image::ColorType::Rgba8;
    let jpeg_data = buffer;

    tracing::debug!(
        "Emitting polar alignment image: {}x{}, {:?}, point={}, phase={}, solved={:?}",
        image.width,
        image.height,
        color_type,
        point,
        phase,
        solved_ra.is_some()
    );

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignmentImage(PolarAlignmentImageEvent {
            image_data: jpeg_data,
            width: image.width as u32,
            height: image.height as u32,
            solved_ra,
            solved_dec,
            point,
            phase: phase.to_string(),
        }),
    ));
}

/// Start three-point polar alignment
///
/// This initiates the polar alignment process which will:
/// 1. Capture 3 images at different mount rotations
/// 2. Plate solve each image
/// 3. Calculate the center of rotation
/// 4. Enter adjustment mode with real-time error updates
///
/// Note: Requires connected camera and mount devices.
pub async fn api_start_polar_alignment(
    exposure_time: f64,
    step_size: f64,
    binning: i32,
    is_north: bool,
    manual_rotation: bool,
    rotate_east: bool,
    gain: Option<i32>,
    offset: Option<i32>,
    solve_timeout: Option<f64>,
    start_from_current: Option<bool>,
    auto_complete_threshold: Option<f64>,
) -> Result<(), NightshadeError> {
    // Hold through task-handle publication so Stop cannot clear ownership in
    // the admission→spawn gap and leave an untracked task running.
    let _control = polar_control_lock().lock().await;

    let generation = try_admit_polar_run().ok_or_else(|| {
        NightshadeError::OperationFailed("Polar alignment already running".to_string())
    })?;

    tracing::info!(
        "Starting polar alignment (gen {generation}): exposure={}s, step={}°, binning={}, north={}, manual={}, east={}",
        exposure_time, step_size, binning, is_north, manual_rotation, rotate_east
    );

    // Get connected devices using existing API
    let connected = api_get_connected_devices().await;

    // Find connected camera
    let camera_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Camera)
        .map(|d| d.id.clone());

    // Find connected mount
    let mount_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Mount)
        .map(|d| d.id.clone());

    let camera_id = camera_id.ok_or_else(|| {
        release_polar_run_if_current(generation);
        NightshadeError::DeviceNotFound("No camera connected".to_string())
    })?;

    let mount_id = mount_id.ok_or_else(|| {
        release_polar_run_if_current(generation);
        NightshadeError::DeviceNotFound("No mount connected".to_string())
    })?;

    // Only the non-hardware options carry a fixed default. gain/offset stay
    // `Option` and are threaded through so `None` means "use the camera's
    // current value" — never forced to 0.
    let solve_timeout_val = solve_timeout.unwrap_or(60.0);
    let start_from_current_val = start_from_current.unwrap_or(true);
    let auto_complete_threshold_val = auto_complete_threshold.unwrap_or(1.0); // Default 1 arcminute

    // Accurate physical altitude/azimuth correction directions require the
    // observer's horizontal frame, even when measuring from the current
    // pointing. Resolve the site up front instead of labelling equatorial
    // tangent components as mount-bolt directions.
    let location_for_run = get_state()
        .get_observer_location()
        .map_err(|e| {
            release_polar_run_if_current(generation);
            NightshadeError::OperationFailed(format!("Failed to read observer location: {}", e))
        })?
        .ok_or_else(|| {
            release_polar_run_if_current(generation);
            NightshadeError::OperationFailed(
                "Observer latitude/longitude is required for polar alignment correction directions. \
                 Set your site location before starting."
                    .to_string(),
            )
        })?;

    let handle = crate::util::supervisor::spawn_supervised_oneshot(
        "polar_align_monitor",
        async move {
            let result = run_polar_alignment(
                camera_id,
                mount_id,
                exposure_time,
                step_size,
                binning,
                is_north,
                manual_rotation,
                rotate_east,
                start_from_current_val,
                gain,
                offset,
                solve_timeout_val,
                auto_complete_threshold_val,
                location_for_run.latitude,
                location_for_run.longitude,
                generation,
            )
            .await;

            if let Err(e) = result {
                // Only surface an error over the status channel if we still own
                // the run; a superseded/aborted task must stay silent.
                if polar_generation().load(PolarOrdering::Relaxed) == generation {
                    tracing::error!("Polar alignment failed: {}", e);
                    emit_polar_status(&format!("Error: {}", e), "error", 0);
                }
            }

            release_polar_run_if_current(generation);
        },
        // If the polar-align task panics, the busy flag would otherwise remain
        // stuck `true` forever and the user could never restart it. Clear the
        // flag (only if still ours) and surface the panic via the status
        // channel.
        Some(move |panic_msg: &str| {
            if polar_generation().load(PolarOrdering::Relaxed) == generation {
                emit_polar_status(&format!("Polar alignment crashed: {panic_msg}"), "error", 0);
            }
            release_polar_run_if_current(generation);
        }),
    );

    // Hand the owned task handle to the stop path so a subsequent stop can
    // await real termination.
    store_polar_task(handle).await;

    Ok(())
}

/// Internal function to run the polar alignment process
pub(crate) async fn run_polar_alignment(
    camera_id: String,
    mount_id: String,
    exposure_time: f64,
    step_size: f64,
    binning: i32,
    is_north: bool,
    manual_rotation: bool,
    rotate_east: bool,
    start_from_current: bool,
    gain: Option<i32>,
    offset: Option<i32>,
    solve_timeout_secs: f64,
    auto_complete_threshold: f64,
    observer_latitude: f64,
    observer_longitude: f64,
    generation: u64,
) -> Result<(), String> {
    // Slew-to-pole start mode: point the mount at the pole region before
    // measuring, instead of measuring from wherever it currently points.
    if !start_from_current {
        match slew_to_pole_region(&mount_id, is_north, observer_longitude, generation).await? {
            SlewOutcome::Settled => {}
            SlewOutcome::Cancelled => {
                emit_polar_status("Cancelled by user", "idle", 0);
                return Ok(());
            }
            SlewOutcome::Superseded => return Ok(()),
        }
    }

    let mut solved_points: Vec<(f64, f64)> = Vec::new();

    // The field scale, read once for the run: the optics and the sensor do not
    // change between the three measurement frames. The pitch is asked of the
    // camera this run is imaging through — not the profile's imaging camera,
    // which polar alignment is often not using — and scaled by the binning
    // these frames are actually being taken at, which the camera has not been
    // set to yet at this point.
    let mut solve_hints = gather_solve_hints_for_camera(Some(&camera_id)).await;
    if binning > 0 {
        solve_hints.binning = (binning, binning);
    }
    solve_hints.log_scale("Polar alignment solve");

    // Phase 1: Capture and solve 3 points
    for point in 1..=3 {
        // Check for cancellation / supersession before starting hardware work.
        match polar_loop_control(generation) {
            PolarLoopControl::Continue => {}
            PolarLoopControl::Superseded => return Ok(()),
            PolarLoopControl::Cancelled => {
                emit_polar_status("Cancelled by user", "idle", 0);
                return Ok(());
            }
        }

        emit_polar_status(
            &format!("Capturing point {}/3...", point),
            "measuring",
            point as i32,
        );

        // Capture image. gain/offset are Option — None leaves the camera's
        // current value untouched (never forced to 0).
        crate::api::imaging::camera_start_exposure_opt(
            camera_id.clone(),
            exposure_time,
            gain,
            offset,
            binning,
            binning,
        )
        .await
        .map_err(|e| format!("Failed to capture: {:?}", e))?;

        match polar_loop_control(generation) {
            PolarLoopControl::Continue => {}
            PolarLoopControl::Superseded => return Ok(()),
            PolarLoopControl::Cancelled => {
                emit_polar_status("Cancelled by user", "idle", 0);
                return Ok(());
            }
        }

        emit_polar_status(
            &format!("Plate solving point {}/3...", point),
            "measuring",
            point as i32,
        );

        // Get the captured image
        let image = api_get_last_image(camera_id.clone())
            .await
            .map_err(|e| format!("Failed to get image: {:?}", e))?;

        // Emit polar alignment image (before plate solve, no coordinates yet)
        emit_polar_image(&image, point as i32, "measuring", None, None);

        // Save temp file for plate solving
        let temp_path = create_unique_temp_fits_path(&format!("polar_align_point_{}", point));
        let temp_path_str = temp_path.to_string_lossy().to_string();

        // Write FITS file for plate solving
        if let Err(e) = write_temp_fits_for_solve(&image, &temp_path_str, &solve_hints) {
            return Err(format!("Failed to write temp FITS: {}", e));
        }

        // Plate solve with configurable timeout
        let solve_future = api_plate_solve_blind(
            temp_path_str.clone(),
            Some(solve_timeout_secs.ceil().clamp(1.0, 3600.0) as u32),
        );
        let solve_result = match tokio::time::timeout(
            tokio::time::Duration::from_secs_f64(solve_timeout_secs),
            solve_future,
        )
        .await
        {
            Ok(Ok(result)) => result,
            Ok(Err(e)) => {
                let _ = std::fs::remove_file(&temp_path);
                return Err(format!("Plate solve error: {:?}", e));
            }
            Err(_) => {
                let _ = std::fs::remove_file(&temp_path);
                return Err(format!(
                    "Plate solve timed out after {:.1} seconds for point {}",
                    solve_timeout_secs, point
                ));
            }
        };

        // Clean up temp file
        let _ = std::fs::remove_file(&temp_path);

        if solve_result.success {
            // PlateSolveResult follows the native solver contract: RA is
            // already degrees. Multiplying by 15 here corrupted both the
            // rotation-center fit and the next mount slew target.
            let ra_degrees = plate_solve_ra_degrees(solve_result.ra);
            solved_points.push((ra_degrees, solve_result.dec));
            tracing::info!(
                "Point {} solved: RA={:.4}°, Dec={:.4}°",
                point,
                ra_degrees,
                solve_result.dec
            );

            // Emit image again with plate solve coordinates
            emit_polar_image(
                &image,
                point as i32,
                "measuring",
                Some(ra_degrees),
                Some(solve_result.dec),
            );
        } else {
            return Err(format!(
                "Plate solve failed for point {}: {:?}",
                point, solve_result.error
            ));
        }

        // Rotate mount for next point (if not last point)
        if point < 3 {
            if manual_rotation {
                emit_polar_status(
                    &format!("Rotate mount {}° and wait...", step_size as i32),
                    "measuring",
                    point as i32,
                );
                // Wait for user to rotate manually
                tokio::time::sleep(tokio::time::Duration::from_secs(15)).await;
            } else {
                emit_polar_status(
                    &format!("Slewing to point {}...", point + 1),
                    "measuring",
                    point as i32,
                );

                // Calculate new position (in degrees)
                // Safe to get last() because we just pushed to solved_points above
                let (current_ra_deg, current_dec) = match solved_points.last() {
                    Some(coords) => coords,
                    None => {
                        return Err("No solved points available for slew calculation".to_string());
                    }
                };
                let move_amount = if rotate_east { step_size } else { -step_size };
                let target_ra_deg = (current_ra_deg + move_amount + 360.0) % 360.0;

                // Slew mount (API takes RA in hours, Dec in degrees)
                api_mount_slew_to_coordinates(mount_id.clone(), target_ra_deg / 15.0, *current_dec)
                    .await
                    .map_err(|e| format!("Failed to slew: {:?}", e))?;

                // Wait for slew to complete
                tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
            }
        }
    }

    // Phase 2: Calculate center of rotation
    emit_polar_status("Calculating polar alignment error...", "adjusting", 3);

    let (mut center_ra, mut center_dec) =
        nightshade_sequencer::calculate_center_of_rotation(&solved_points);
    let pole_dec = if is_north { 90.0 } else { -90.0 };

    tracing::info!(
        "Rotation center: RA={:.4}°, Dec={:.4}°",
        center_ra,
        center_dec
    );

    // Geometric validation: check if calculated center is within 15° of expected pole
    let dec_diff = (center_dec - pole_dec).abs();
    if dec_diff > 15.0 {
        let error_msg = format!(
            "Calculated rotation center (Dec={:.2}°) is {:.1}° away from expected pole (Dec={:.0}°). \
            This suggests poor plate solves or insufficient mount rotation. \
            Please ensure: 1) Clear view of pole area, 2) Mount rotates at least {}° between points, \
            3) Plate solving is accurate. Try increasing step size or checking camera focus.",
            center_dec, dec_diff, pole_dec, step_size
        );
        tracing::error!("{}", error_msg);
        emit_polar_status(&format!("Error: {}", error_msg), "error", 0);
        return Err(error_msg);
    }

    // Phase 3: Adjustment loop - continuously update error as the user adjusts.
    emit_polar_status("Adjustment mode - make corrections", "adjusting", 0);

    // Track the measured mount RA axis as the user physically adjusts the alt/az
    // bolts. The axis was measured in Phase 1 from three ROTATED points. During
    // adjustment the mount is stationary (the user turns the bolts, not the RA
    // motor), so re-fitting the axis from the now-stationary frames is invalid —
    // three near-identical points give a degenerate plane and the old code
    // collapsed the axis toward the pole, reporting ~0 error from a badly
    // misaligned mount.
    //
    // Instead we hold the Phase-1 axis and apply the displacement of the
    // boresight (how far the current solved position has moved from the first
    // adjustment frame) to the axis. Any physical mount adjustment shifts the
    // whole sky-to-mount mapping by the same small rotation, so the boresight
    // displacement equals the axis displacement to first order. `reference_solve`
    // is captured on the first successful adjustment solve below.
    let initial_axis = (center_ra, center_dec);
    let mut reference_solve: Option<(f64, f64)> = None;

    // Auto-complete timer: tracks when error first dropped below threshold
    let mut auto_complete_start: Option<std::time::Instant> = None;
    const AUTO_COMPLETE_DURATION_SECS: u64 = 3;

    let mut consecutive_failures = 0;
    const MAX_FAILURES: i32 = 5;

    loop {
        match polar_loop_control(generation) {
            PolarLoopControl::Continue => {}
            PolarLoopControl::Superseded => return Ok(()),
            PolarLoopControl::Cancelled => {
                emit_polar_status("Stopped", "idle", 0);
                return Ok(());
            }
        }

        // Capture and solve to get current position
        emit_polar_status("Capturing...", "adjusting", 0);
        if let Err(e) = crate::api::imaging::camera_start_exposure_opt(
            camera_id.clone(),
            exposure_time,
            gain,
            offset,
            binning,
            binning,
        )
        .await
        {
            consecutive_failures += 1;
            tracing::warn!("Capture failed in adjustment loop: {:?}", e);
            emit_polar_status(
                &format!(
                    "Capture failed: {:?} (retry {}/{})",
                    e, consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            continue;
        }

        match polar_loop_control(generation) {
            PolarLoopControl::Continue => {}
            PolarLoopControl::Superseded => return Ok(()),
            PolarLoopControl::Cancelled => {
                emit_polar_status("Stopped", "idle", 0);
                return Ok(());
            }
        }

        // Get the captured image
        let image = match api_get_last_image(camera_id.clone()).await {
            Ok(img) => img,
            Err(e) => {
                consecutive_failures += 1;
                tracing::warn!("Failed to get image in adjustment loop: {:?}", e);
                emit_polar_status(
                    &format!(
                        "Image retrieval failed (retry {}/{})",
                        consecutive_failures, MAX_FAILURES
                    ),
                    "adjusting",
                    0,
                );
                if consecutive_failures >= MAX_FAILURES {
                    return Err(format!(
                        "Too many consecutive failures ({}) in adjustment loop",
                        MAX_FAILURES
                    ));
                }
                tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                continue;
            }
        };

        // Emit polar alignment image (adjustment phase, no coordinates yet)
        emit_polar_image(&image, 0, "adjusting", None, None);

        let temp_path = create_unique_temp_fits_path("polar_align_adjust");
        let temp_path_str = temp_path.to_string_lossy().to_string();

        if let Err(e) = write_temp_fits_for_solve(&image, &temp_path_str, &solve_hints) {
            consecutive_failures += 1;
            tracing::warn!("Failed to write temp FITS: {}", e);
            emit_polar_status(
                &format!(
                    "FITS write failed (retry {}/{})",
                    consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            continue;
        }

        emit_polar_status("Solving...", "adjusting", 0);

        // Plate solve with 30 second timeout (shorter for adjustment loop)
        let solve_future = api_plate_solve_blind(temp_path_str.clone(), Some(30));
        let solve_result =
            match tokio::time::timeout(tokio::time::Duration::from_secs(30), solve_future).await {
                Ok(Ok(result)) => {
                    let _ = std::fs::remove_file(&temp_path);
                    result
                }
                Ok(Err(e)) => {
                    let _ = std::fs::remove_file(&temp_path);
                    consecutive_failures += 1;
                    tracing::warn!("Plate solve error in adjustment loop: {:?}", e);
                    emit_polar_status(
                        &format!(
                            "Solve failed: {:?} (retry {}/{})",
                            e, consecutive_failures, MAX_FAILURES
                        ),
                        "adjusting",
                        0,
                    );
                    if consecutive_failures >= MAX_FAILURES {
                        return Err(format!(
                            "Too many consecutive failures ({}) in adjustment loop",
                            MAX_FAILURES
                        ));
                    }
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                    continue;
                }
                Err(_) => {
                    let _ = std::fs::remove_file(&temp_path);
                    consecutive_failures += 1;
                    tracing::warn!("Plate solve timed out in adjustment loop");
                    emit_polar_status(
                        &format!(
                            "Solve timed out (retry {}/{})",
                            consecutive_failures, MAX_FAILURES
                        ),
                        "adjusting",
                        0,
                    );
                    if consecutive_failures >= MAX_FAILURES {
                        return Err(format!(
                            "Too many consecutive failures ({}) in adjustment loop",
                            MAX_FAILURES
                        ));
                    }
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                    continue;
                }
            };

        if solve_result.success {
            // Reset failure counter on success
            consecutive_failures = 0;

            // Native plate-solve results report RA in degrees.
            let ra_degrees = plate_solve_ra_degrees(solve_result.ra);

            // Emit image again with plate solve coordinates
            emit_polar_image(
                &image,
                0,
                "adjusting",
                Some(ra_degrees),
                Some(solve_result.dec),
            );

            // Track the current mount axis by applying the boresight
            // displacement (vs the first adjustment frame) to the Phase-1 axis.
            // This reflects the user's physical alt/az adjustments WITHOUT the
            // degenerate re-fit-from-stationary-points collapse.
            let (ref_ra, ref_dec) = *reference_solve.get_or_insert((ra_degrees, solve_result.dec));

            // Apply the exact geodesic rotation that moved the solved
            // boresight to the measured mechanical axis. This remains stable
            // near the pole where dividing a first-order RA delta by cos(dec)
            // becomes singular and can explode a tiny adjustment.
            let (cur_axis_ra, cur_axis_dec) = nightshade_sequencer::rotate_axis_by_star_motion(
                initial_axis,
                (ref_ra, ref_dec),
                (ra_degrees, solve_result.dec),
            );

            tracing::debug!(
                "Adjustment: boresight Δ=({:.4}°,{:.4}°) → current axis RA={:.4}°, Dec={:.4}°",
                ra_degrees - ref_ra,
                solve_result.dec - ref_dec,
                cur_axis_ra,
                cur_axis_dec
            );

            // Error in ARCSECONDS (Dart UI labels values with `"` and uses
            // 30"/60" colour bands; the old code emitted arcMINUTES, so a real
            // 5' error displayed as 5" — 60x too small — and the auto-complete
            // fired ~60x too early).
            let (az_arcmin, alt_arcmin, total_arcmin) =
                nightshade_sequencer::calculate_alignment_error_arcmin(
                    cur_axis_ra,
                    cur_axis_dec,
                    is_north,
                    observer_latitude,
                    observer_longitude,
                    chrono::Utc::now(),
                );
            let (az_error, alt_error, total_error) =
                (az_arcmin * 60.0, alt_arcmin * 60.0, total_arcmin * 60.0);
            center_ra = cur_axis_ra;
            center_dec = cur_axis_dec;

            // Auto-complete logic: check if error is below threshold
            if total_error <= auto_complete_threshold {
                match auto_complete_start {
                    Some(start_time) => {
                        let elapsed = start_time.elapsed();
                        if elapsed.as_secs() >= AUTO_COMPLETE_DURATION_SECS {
                            // Error has been below threshold for required duration
                            tracing::info!(
                                "Polar alignment complete! Total error {:.1} arcsec below threshold {:.1} for {} seconds",
                                total_error, auto_complete_threshold, AUTO_COMPLETE_DURATION_SECS
                            );
                            emit_polar_status(
                                &format!(
                                    "Complete! Error {:.1}\" below threshold for {}s",
                                    total_error, AUTO_COMPLETE_DURATION_SECS
                                ),
                                "complete",
                                0,
                            );
                            emit_polar_error(
                                az_error,
                                alt_error,
                                total_error,
                                ra_degrees,
                                solve_result.dec,
                                center_ra,
                                center_dec,
                            );
                            return Ok(());
                        } else {
                            // Still within threshold, update status with countdown
                            let remaining = AUTO_COMPLETE_DURATION_SECS - elapsed.as_secs();
                            emit_polar_status(
                                &format!("Below threshold - completing in {}s...", remaining),
                                "adjusting",
                                0,
                            );
                        }
                    }
                    None => {
                        // First time below threshold, start timer
                        auto_complete_start = Some(std::time::Instant::now());
                        tracing::info!(
                            "Error {:.1} arcsec dropped below threshold {:.1}, starting auto-complete timer",
                            total_error, auto_complete_threshold
                        );
                        emit_polar_status(
                            &format!(
                                "Below threshold - completing in {}s...",
                                AUTO_COMPLETE_DURATION_SECS
                            ),
                            "adjusting",
                            0,
                        );
                    }
                }
            } else {
                // Error above threshold, reset timer if it was running
                if auto_complete_start.is_some() {
                    tracing::debug!(
                        "Error {:.1} arcsec went back above threshold {:.1}, resetting auto-complete timer",
                        total_error, auto_complete_threshold
                    );
                    auto_complete_start = None;
                }
                emit_polar_status("Adjusting - make corrections", "adjusting", 0);
            }

            emit_polar_error(
                az_error,
                alt_error,
                total_error,
                ra_degrees,
                solve_result.dec,
                center_ra,
                center_dec,
            );
        } else {
            consecutive_failures += 1;
            // Failed solve means we can't track error, reset auto-complete timer
            auto_complete_start = None;
            emit_polar_status(
                &format!(
                    "Solve unsuccessful (retry {}/{})",
                    consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
        }

        // Brief pause before next update
        tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
    }
}

/// Write the temp FITS a polar-alignment frame is solved from.
///
/// `hints` carries the field scale (see [`SolveHints`]). Polar alignment
/// solves blind on purpose — it runs before the mount's pointing can be
/// trusted, so no position hint is stamped — but the scale is known from the
/// operator's profile and the camera, and without it ASTAP has to sweep for
/// the field of view on all three measurement frames plus every frame of the
/// adjustment loop.
pub(crate) fn write_temp_fits_for_solve(
    image: &CapturedImageResult,
    path: &str,
    hints: &SolveHints,
) -> Result<(), String> {
    use nightshade_imaging::{write_fits, FitsHeader, ImageData, PixelType};
    use std::path::Path;

    // Convert RGBA display_data to grayscale 16-bit for FITS plate solving.
    // display_data is always RGBA (4 bytes per pixel).
    let raw_bytes: Vec<u8> = if image.is_color {
        // For color RGBA, convert to grayscale (luminance) and scale to 16-bit
        image
            .display_data
            .chunks(4)
            .flat_map(|rgba| {
                let lum = ((rgba[0] as u32 + rgba[1] as u32 + rgba[2] as u32) / 3) as u16 * 256;
                lum.to_le_bytes().to_vec()
            })
            .collect()
    } else {
        // For grayscale RGBA, take the R channel (all RGB channels are the same) and scale to 16-bit
        image
            .display_data
            .chunks(4)
            .flat_map(|rgba| {
                let scaled = (rgba[0] as u16) * 256;
                scaled.to_le_bytes().to_vec()
            })
            .collect()
    };

    let mut image_data = ImageData::new(
        image.width as u32,
        image.height as u32,
        1, // grayscale
        PixelType::U16,
    );
    image_data.data = raw_bytes;

    let mut header = FitsHeader::new();
    header.set_float("EXPTIME", image.exposure_time);
    hints.apply_to_fits_header(&mut header);

    write_fits(Path::new(path), &image_data, &header)
        .map_err(|e| format!("FITS write error: {:?}", e))
}

/// Stop the polar alignment process.
///
/// Returns only once the run is actually terminated. Signals cooperative
/// cancellation, then awaits the owned task handle with a bounded grace; if the
/// task is still mid-exposure it force-aborts (dropping the in-flight future)
/// and confirms termination. If termination cannot be confirmed it returns a
/// truthful timeout error and, crucially, leaves the running flag set and never
/// publishes idle — so a new Start stays blocked until the run truly settles.
///
/// This is applied to *both* TPPA and all-sky, which share this stop path and
/// the single owned task slot, so neither can leave a task running under a new
/// run.
pub async fn api_stop_polar_alignment() -> Result<(), NightshadeError> {
    // Serialize with Start until its task handle is stored; Stop must never
    // report success while an admitted task can still appear afterward.
    let _control = polar_control_lock().lock().await;
    if !get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Ok(()); // Already stopped
    }

    // Signal cooperative cancellation.
    get_polar_align_cancel().store(true, PolarOrdering::Relaxed);
    tracing::info!("Stopping polar alignment; awaiting task termination");

    // Take the owned task handle and await bounded termination. We never
    // publish idle (or admit a new Start) while the old task could still touch
    // the camera/mount.
    let handle = { polar_task_slot().lock().await.take() };
    if let Some(mut h) = handle {
        let abort = h.abort_handle();

        // First give the task a bounded chance to exit cooperatively at one of
        // its cancel/generation checkpoints.
        let terminated =
            match tokio::time::timeout(Duration::from_secs(POLAR_STOP_CLEAN_GRACE_SECS), &mut h)
                .await
            {
                Ok(_join) => true,
                Err(_elapsed) => {
                    // Likely blocked in a long exposure. Force-abort to drop the
                    // in-flight future, then confirm the task actually unwound.
                    tracing::warn!(
                        "Polar alignment did not stop cooperatively in {}s; aborting task",
                        POLAR_STOP_CLEAN_GRACE_SECS
                    );
                    abort.abort();
                    tokio::time::timeout(Duration::from_secs(POLAR_STOP_ABORT_GRACE_SECS), &mut h)
                        .await
                        .is_ok()
                }
            };

        if !terminated {
            // Could not confirm termination. Keep the run blocked: leave the
            // running flag set, do NOT publish idle, and put the handle back so
            // a later stop can try again.
            *polar_task_slot().lock().await = Some(h);
            return Err(NightshadeError::OperationFailed(
                "Polar alignment stop timed out; task is still terminating".to_string(),
            ));
        }
    }

    get_polar_align_flag().store(false, PolarOrdering::Relaxed);
    emit_polar_status("Stopped", "idle", 0);
    Ok(())
}

// =============================================================================
// All-Sky Polar Alignment (Sharpcap-style)
// =============================================================================

/// Polar alignment mode selector.
///
/// The traditional `ThreePoint` mode (TPPA) requires a clear view of the
/// celestial pole region. `AllSky` mode performs Sharpcap-style polar
/// alignment from any point in the sky using a single solved frame plus
/// live drift feedback.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PolarAlignmentMode {
    /// Three-Point Polar Alignment — requires pole region visible.
    ThreePoint,
    /// Sharpcap-style all-sky polar alignment — works from any sky direction.
    AllSky,
}

/// Start all-sky polar alignment.
///
/// Unlike TPPA this routine does not require the celestial pole region to
/// be visible. It takes a single exposure anywhere in the sky, plate-solves
/// it to anchor a baseline, then re-solves every `iteration_cadence_secs`
/// to measure drift relative to that baseline. From the drift signature
/// and the observer's geographic location it recovers the polar-axis
/// azimuth and altitude error.
///
/// # Arguments
/// * `exposure_time` — exposure duration per frame, seconds.
/// * `solve_timeout` — plate-solve timeout per frame, seconds.
/// * `binning` — camera binning factor (1, 2, or 4 typical).
/// * `is_north` — northern hemisphere observer flag.
/// * `acceptance_threshold_arcsec` — alignment auto-completes when the
///   total error stays below this for 3 seconds (default 30″ = good for
///   ~3-minute unguided subs).
/// * `iteration_cadence_secs` — re-solve cadence (default 3s).
/// * `gain`, `offset` — optional camera parameters.
///
/// # Errors
/// Returns `NightshadeError::OperationFailed` if a plate solver is not
/// available (the user must install ASTAP), if no camera/mount is
/// connected, or if the observer location is not configured.
pub async fn api_start_all_sky_polar_alignment(
    exposure_time: f64,
    solve_timeout: f64,
    binning: i32,
    is_north: bool,
    acceptance_threshold_arcsec: f64,
    iteration_cadence_secs: f64,
    gain: Option<i32>,
    offset: Option<i32>,
) -> Result<(), NightshadeError> {
    use nightshade_sequencer::all_sky_polar::{
        perform_all_sky_polar_alignment, AllSkyPolarAlignConfig, PolarAlignError,
    };
    use nightshade_sequencer::{Binning, InstructionContext};

    let _control = polar_control_lock().lock().await;

    // Fail loudly if the plate solver isn't installed — the all-sky
    // algorithm is plate-solve-only by design.
    if !nightshade_imaging::is_solver_available() {
        return Err(NightshadeError::OperationFailed(
            "Plate solver required — install ASTAP and re-run all-sky polar alignment".to_string(),
        ));
    }

    let generation = try_admit_polar_run().ok_or_else(|| {
        NightshadeError::OperationFailed("Polar alignment already running".to_string())
    })?;

    tracing::info!(
        "Starting all-sky polar alignment (gen {generation}): exposure={}s, threshold={}\", cadence={}s, north={}",
        exposure_time,
        acceptance_threshold_arcsec,
        iteration_cadence_secs,
        is_north
    );

    // Resolve connected devices.
    let connected = api_get_connected_devices().await;
    let camera_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Camera)
        .map(|d| d.id.clone())
        .ok_or_else(|| {
            release_polar_run_if_current(generation);
            NightshadeError::DeviceNotFound("No camera connected".to_string())
        })?;
    let mount_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Mount)
        .map(|d| d.id.clone())
        .ok_or_else(|| {
            release_polar_run_if_current(generation);
            NightshadeError::DeviceNotFound("No mount connected".to_string())
        })?;

    // Observer location is mandatory for the horizontal-frame projection.
    let location = get_state()
        .get_observer_location()
        .map_err(|e| {
            release_polar_run_if_current(generation);
            NightshadeError::OperationFailed(format!("Failed to read observer location: {}", e))
        })?
        .ok_or_else(|| {
            release_polar_run_if_current(generation);
            NightshadeError::OperationFailed(
                "Observer latitude/longitude is required for all-sky polar alignment".to_string(),
            )
        })?;

    let config = AllSkyPolarAlignConfig {
        exposure_time,
        solve_timeout,
        gain,
        offset,
        binning: Some(binning),
        is_north,
        acceptance_threshold_arcsec,
        iteration_cadence_secs,
    };

    // Spawn the alignment task. Errors are emitted on the polar alignment
    // event stream so the UI can present them clearly.
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let cancel_flag_outer = cancel_flag.clone();

    // Bridge between the global cancel flag (set by `api_stop_polar_alignment`)
    // and the per-task cancellation token used by InstructionContext.
    tokio::spawn(async move {
        loop {
            if polar_generation().load(PolarOrdering::Relaxed) != generation {
                break;
            }
            if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
                cancel_flag_outer.store(true, Ordering::Relaxed);
                break;
            }
            if !get_polar_align_flag().load(PolarOrdering::Relaxed) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(250)).await;
        }
    });

    let device_ops = create_unified_device_ops();

    // hand the alignment task its own executor-event bridge
    // so instruction-level failures (e.g. FITS-save error on a polar-align
    // exposure) reach the same NightshadeEvent stream the rest of the app
    // listens to. The status_cb/image_cb callbacks below cover the alignment
    // workflow itself, but anything emitted directly by the instructions
    // layer (write_fits failure, etc.) was previously silent.
    //
    // `event_tx` is moved into the spawned task; the background bridge task
    // exits when the task drops the sender after the alignment finishes.
    let event_tx_for_align =
        crate::util::executor_event_bridge::spawn_executor_event_bridge(get_state().clone());

    let align_handle = tokio::spawn(async move {
        let ctx = InstructionContext {
            node_id: String::new(),
            target_ra: None,
            target_dec: None,
            target_name: None,
            target_rotation: None,
            current_filter: None,
            current_binning: Binning::One,
            cancellation_token: cancel_flag,
            camera_id: Some(camera_id.clone()),
            mount_id: Some(mount_id.clone()),
            focuser_id: None,
            filterwheel_id: None,
            rotator_id: None,
            dome_id: None,
            cover_calibrator_id: None,
            save_path: None,
            latitude: Some(location.latitude),
            longitude: Some(location.longitude),
            device_ops,
            trigger_state: None,
            filter_focus_offsets: std::collections::HashMap::new(),
            event_tx: Some(event_tx_for_align),
            recovery_request_tx: None,
            // Image Grading: polar alignment does not write FITS
            // frames into the sequencer's save_path; the alignment images
            // go through a separate dedicated channel. Empty defaults
            // satisfy the InstructionContext shape without lying.
            session_id: String::new(),
            target_id: None,
            mosaic_panel: None,
            current_filter_index: None,
            set_temp_c: None,
            bayer_pattern: None,
            observer_name: None,
            site_elevation_m: None,
            camera_make: None,
            camera_model: None,
            telescope_name: None,
            telescope_focal_length_mm: None,
            telescope_aperture_mm: None,
            last_plate_solve: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
            hfr_baseline: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
            hfr_baseline_samples: std::sync::Arc::new(tokio::sync::RwLock::new(Vec::new())),
            consecutive_rejects: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
            frames_accepted: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
            frames_rejected: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
            default_quality_check: None,
            reject_folder_path: None,
            // defect map state. Polar alignment captures
            // do not go through the sequencer save_path; defect maps are
            // not applied here, so pass an empty slot.
            defect_map_apply: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
            // Forensics: polar alignment does not grade frames.
            forensics_history: std::sync::Arc::new(tokio::sync::RwLock::new(
                std::collections::VecDeque::new(),
            )),
            current_sky_brightness_mag: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
            cloud_motion_snapshot: std::sync::Arc::new(tokio::sync::RwLock::new(
                nightshade_sequencer::CloudMotionSnapshot::default(),
            )),
            current_wind_kph: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
            current_sensor_temp_c: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
            // Replay Debug — one-shot bridge API doesn't emit
            // decisions (no associated sequence_runs row).
            decision_tx: None,
            active_sequence_run_id: std::sync::Arc::new(parking_lot::RwLock::new(None)),
            // Polar alignment is not driven by the node-runtime disconnect-retry
            // loop, so this one-shot context owns a fresh, unshared flag.
            device_disconnect_recovery_pending: std::sync::Arc::new(
                std::sync::atomic::AtomicBool::new(false),
            ),
            // Dual-rig — polar alignment runs standalone, no secondary coord.
            dither_barrier: None,
        };

        let status_cb = |status: String, _progress: Option<f64>| {
            emit_polar_status(&status, "adjusting", 0);
        };
        let image_cb = |image_data: nightshade_sequencer::PolarAlignmentImageData| {
            get_state().publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::PolarAlignment,
                EventPayload::PolarAlignmentImage(PolarAlignmentImageEvent {
                    image_data: image_data.image_data,
                    width: image_data.width,
                    height: image_data.height,
                    solved_ra: image_data.solved_ra,
                    solved_dec: image_data.solved_dec,
                    point: image_data.point,
                    phase: image_data.phase,
                }),
            ));
        };
        let error_cb = |result: &nightshade_sequencer::PolarAlignResult| {
            emit_polar_error(
                result.azimuth_error,
                result.altitude_error,
                result.total_error,
                result.current_ra,
                result.current_dec,
                result.target_ra,
                result.target_dec,
            );
        };

        let result =
            perform_all_sky_polar_alignment(&config, &ctx, status_cb, image_cb, error_cb).await;

        // Only emit terminal status if we still own the run; a superseded /
        // force-aborted task must stay silent so it can't stomp a newer run.
        if polar_generation().load(PolarOrdering::Relaxed) == generation {
            match result {
                Ok(()) => {
                    emit_polar_status("All-sky polar alignment complete", "complete", 0);
                }
                Err(PolarAlignError::Cancelled) => {
                    emit_polar_status("Stopped", "idle", 0);
                }
                Err(PolarAlignError::SolverUnavailable) => {
                    emit_polar_status(
                        "Plate solver required — install ASTAP and re-run all-sky polar alignment",
                        "error",
                        0,
                    );
                    tracing::error!("All-sky polar alignment aborted: plate solver not available");
                }
                Err(e) => {
                    emit_polar_status(&format!("Error: {}", e), "error", 0);
                    tracing::error!("All-sky polar alignment failed: {}", e);
                }
            }
        }

        release_polar_run_if_current(generation);
    });

    // Hand the owned alignment task to the stop path so a subsequent stop can
    // await real termination (same owned slot as TPPA — one run at a time).
    store_polar_task(align_handle).await;

    Ok(())
}

#[cfg(test)]
mod polar_run_control_tests {
    use super::{
        get_polar_align_cancel, get_polar_align_flag, plate_solve_ra_degrees, polar_generation,
        polar_loop_control, pole_region_target, release_polar_run_if_current, try_admit_polar_run,
        PolarLoopControl, PolarOrdering, POLE_REGION_OFFSET_DEG,
    };

    #[test]
    fn plate_solve_ra_is_already_degrees_for_polar_geometry() {
        assert_eq!(plate_solve_ra_degrees(10.0), 10.0);
    }

    /// IMG-14: the frame polar alignment hands the solver must carry the field
    /// scale the operator already told us about. Without `FOCALLEN` and the
    /// binned pixel pitch, ASTAP has no scale to work from and sweeps its
    /// field-of-view ladder — the slow path that fails on fields it would
    /// otherwise solve, three times per alignment run.
    #[test]
    fn polar_solve_frame_carries_the_field_scale_hints() {
        use super::{write_temp_fits_for_solve, SolveHints};
        use crate::api::imaging::{CapturedImageResult, ImageStatsResult};

        let width = 8u32;
        let height = 6u32;
        let image = CapturedImageResult {
            width,
            height,
            display_data: vec![32u8; (width * height * 4) as usize],
            histogram: vec![0; 256],
            stats: ImageStatsResult {
                min: 0.0,
                max: 1.0,
                mean: 0.5,
                median: 0.5,
                std_dev: 0.1,
                hfr: None,
                eccentricity: None,
                fwhm: None,
                star_count: 0,
            },
            exposure_time: 2.0,
            timestamp: "2026-08-13T00:00:00Z".to_string(),
            is_color: false,
        };

        let path = crate::api::create_unique_temp_fits_path("polar_hint_test");
        let path_str = path.to_string_lossy().to_string();
        // A 416 mm scope and a 3.76 um sensor binned 2x2 — the operator's own
        // profile entry and what the camera reports.
        let hints = SolveHints {
            focal_length_mm: Some(416.0),
            pixel_size_um: Some((3.76, 3.76)),
            binning: (2, 2),
        };
        write_temp_fits_for_solve(&image, &path_str, &hints).expect("temp FITS write");

        let (_data, header) = nightshade_imaging::read_fits(&path).expect("read back temp FITS");
        assert_eq!(header.get_float("FOCALLEN"), Some(416.0));
        let xpixsz = header.get_float("XPIXSZ").expect("XPIXSZ card");
        let ypixsz = header.get_float("YPIXSZ").expect("YPIXSZ card");
        assert!(
            (xpixsz - 7.52).abs() < 1e-6 && (ypixsz - 7.52).abs() < 1e-6,
            "a 3.76 um sensor binned 2x2 has 7.52 um effective pixels, got {xpixsz} x {ypixsz}"
        );

        let _ = std::fs::remove_file(&path);
    }

    /// A rig that reports neither optic nor pitch contributes no card, and the
    /// solver behaves exactly as it did before — no invented numbers.
    #[test]
    fn polar_solve_frame_omits_scale_cards_when_nothing_is_known() {
        use super::{write_temp_fits_for_solve, SolveHints};
        use crate::api::imaging::{CapturedImageResult, ImageStatsResult};

        let image = CapturedImageResult {
            width: 4,
            height: 4,
            display_data: vec![0u8; 4 * 4 * 4],
            histogram: vec![0; 256],
            stats: ImageStatsResult {
                min: 0.0,
                max: 0.0,
                mean: 0.0,
                median: 0.0,
                std_dev: 0.0,
                hfr: None,
                eccentricity: None,
                fwhm: None,
                star_count: 0,
            },
            exposure_time: 1.0,
            timestamp: "2026-08-13T00:00:00Z".to_string(),
            is_color: false,
        };

        let path = crate::api::create_unique_temp_fits_path("polar_hint_absent_test");
        let path_str = path.to_string_lossy().to_string();
        write_temp_fits_for_solve(&image, &path_str, &SolveHints::default()).expect("write");

        let (_data, header) = nightshade_imaging::read_fits(&path).expect("read back temp FITS");
        assert_eq!(header.get_float("FOCALLEN"), None);
        assert_eq!(header.get_float("XPIXSZ"), None);

        let _ = std::fs::remove_file(&path);
    }

    /// The pole-region slew target sits on the meridian (RA == LST, wrapped into
    /// [0,24)) and `POLE_REGION_OFFSET_DEG` from the pole toward the equator,
    /// with the correct sign per hemisphere.
    #[test]
    fn pole_region_target_on_meridian_and_offset_from_pole() {
        let (ra, dec) = pole_region_target(6.5, true);
        assert!((ra - 6.5).abs() < 1e-9, "north RA should equal LST");
        assert!(
            (dec - (90.0 - POLE_REGION_OFFSET_DEG)).abs() < 1e-9,
            "north dec should be 90 - offset, got {dec}"
        );

        let (_, dec_s) = pole_region_target(6.5, false);
        assert!(
            (dec_s - (-90.0 + POLE_REGION_OFFSET_DEG)).abs() < 1e-9,
            "south dec should be -90 + offset, got {dec_s}"
        );

        // LST wraps into [0, 24) both above 24 and below 0.
        assert!((pole_region_target(25.0, true).0 - 1.0).abs() < 1e-9);
        assert!((pole_region_target(-1.0, true).0 - 23.0).abs() < 1e-9);

        // The offset keeps the target within the ≈30° pole region but off the
        // degenerate pole itself.
        let (_, dec_n) = pole_region_target(0.0, true);
        assert!(
            (60.0..90.0).contains(&dec_n),
            "north dec in pole region: {dec_n}"
        );
    }

    /// The generation + owned-run primitives that back the no-overlap guarantee:
    /// admitting a run bumps the generation and sets the flag; a superseding run
    /// makes the old generation stale; and a *stale* release must never clear a
    /// newer run's flag (which would let a third Start overlap the live run).
    ///
    /// All the global-state assertions live in ONE test so they can't race with
    /// each other over the process-wide statics.
    #[test]
    fn generation_admission_and_release_no_overlap() {
        // Clean baseline.
        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        get_polar_align_cancel().store(false, PolarOrdering::Relaxed);

        // Admitting a run flips the flag and clears cancel.
        let g1 = try_admit_polar_run().expect("first run admitted");
        assert!(get_polar_align_flag().load(PolarOrdering::Relaxed));
        assert!(!get_polar_align_cancel().load(PolarOrdering::Relaxed));
        assert!(matches!(polar_loop_control(g1), PolarLoopControl::Continue));

        // Atomic admission rejects a concurrent second owner.
        assert!(try_admit_polar_run().is_none());

        // Once the first run releases, a new generation can be admitted.
        release_polar_run_if_current(g1);
        let g2 = try_admit_polar_run().expect("second run admitted after release");
        assert!(g2 > g1, "generation must be monotonic: {g1} -> {g2}");
        assert!(matches!(
            polar_loop_control(g1),
            PolarLoopControl::Superseded
        ));
        assert!(matches!(polar_loop_control(g2), PolarLoopControl::Continue));

        // Cancellation only cancels the *current* generation; a stale gen still
        // reports Superseded (generation is checked before cancel).
        get_polar_align_cancel().store(true, PolarOrdering::Relaxed);
        assert!(matches!(
            polar_loop_control(g2),
            PolarLoopControl::Cancelled
        ));
        assert!(matches!(
            polar_loop_control(g1),
            PolarLoopControl::Superseded
        ));

        // A stale-generation release must NOT clear the live run's flag —
        // otherwise a superseded/aborted task could unblock a third Start while
        // the current run still owns the hardware.
        release_polar_run_if_current(g1);
        assert!(
            get_polar_align_flag().load(PolarOrdering::Relaxed),
            "stale release cleared the live run's flag"
        );

        // The current generation's release clears the flag.
        release_polar_run_if_current(g2);
        assert!(!get_polar_align_flag().load(PolarOrdering::Relaxed));

        // Leave globals clean for any other test.
        get_polar_align_cancel().store(false, PolarOrdering::Relaxed);
        // Nudge the generation so a later admission is still strictly greater.
        let _ = polar_generation().load(PolarOrdering::Relaxed);
    }
}
