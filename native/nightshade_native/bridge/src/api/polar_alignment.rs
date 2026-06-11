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

/// Track whether polar alignment is running
pub(crate) static POLAR_ALIGN_RUNNING: OnceLock<PolarAtomicBool> = OnceLock::new();
pub(crate) static POLAR_ALIGN_CANCEL: OnceLock<PolarAtomicBool> = OnceLock::new();

pub(crate) fn get_polar_align_flag() -> &'static PolarAtomicBool {
    POLAR_ALIGN_RUNNING.get_or_init(|| PolarAtomicBool::new(false))
}

pub(crate) fn get_polar_align_cancel() -> &'static PolarAtomicBool {
    POLAR_ALIGN_CANCEL.get_or_init(|| PolarAtomicBool::new(false))
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
    // Check if already running
    if get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Err(NightshadeError::OperationFailed(
            "Polar alignment already running".to_string(),
        ));
    }

    get_polar_align_flag().store(true, PolarOrdering::Relaxed);
    get_polar_align_cancel().store(false, PolarOrdering::Relaxed);

    tracing::info!(
        "Starting polar alignment: exposure={}s, step={}°, binning={}, north={}, manual={}, east={}",
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
        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        NightshadeError::DeviceNotFound("No camera connected".to_string())
    })?;

    let mount_id = mount_id.ok_or_else(|| {
        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        NightshadeError::DeviceNotFound("No mount connected".to_string())
    })?;

    // Spawn background task for polar alignment.
    // Why: each unwrap_or here applies the documented
    // Nightshade default surfaced in the Polar-Align wizard UI when the
    // FFI caller omits the optional field:
    //   - gain/offset 0 → "keep camera's current value" (start_exposure
    //     wrapper short-circuits when the requested value equals cached)
    //   - solve_timeout 60s → matches the plate-solve panel's default
    //   - start_from_current true → standard "use mount's current pointing"
    //   - auto_complete_threshold 1.0 arcmin → the recommended PA accuracy
    //     for typical 1000mm-focal-length imaging (per the wizard UI tooltip)
    let gain_val = gain.unwrap_or(0);
    let offset_val = offset.unwrap_or(0);
    let solve_timeout_val = solve_timeout.unwrap_or(60.0);
    let start_from_current_val = start_from_current.unwrap_or(true);
    let auto_complete_threshold_val = auto_complete_threshold.unwrap_or(1.0); // Default 1 arcminute

    crate::util::supervisor::spawn_supervised_oneshot(
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
                gain_val,
                offset_val,
                solve_timeout_val,
                auto_complete_threshold_val,
            )
            .await;

            if let Err(e) = result {
                tracing::error!("Polar alignment failed: {}", e);
                emit_polar_status(&format!("Error: {}", e), "error", 0);
            }

            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        },
        // If the polar-align task panics, the busy flag would otherwise
        // remain stuck `true` forever and the user could never restart it.
        // Clear the flag and surface the panic via the status channel.
        Some(|panic_msg: &str| {
            emit_polar_status(&format!("Polar alignment crashed: {panic_msg}"), "error", 0);
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        }),
    );

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
    gain: i32,
    offset: i32,
    solve_timeout_secs: f64,
    auto_complete_threshold: f64,
) -> Result<(), String> {
    if !start_from_current {
        return Err(
            "Polar alignment with start_from_current=false is not supported by this workflow"
                .to_string(),
        );
    }

    let mut solved_points: Vec<(f64, f64)> = Vec::new();

    // Phase 1: Capture and solve 3 points
    for point in 1..=3 {
        // Check for cancellation
        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Cancelled by user", "idle", 0);
            return Ok(());
        }

        emit_polar_status(
            &format!("Capturing point {}/3...", point),
            "measuring",
            point as i32,
        );

        // Capture image using existing API
        // api_camera_start_exposure(device_id, duration_secs, gain, offset, bin_x, bin_y)
        api_camera_start_exposure(
            camera_id.clone(),
            exposure_time,
            gain,
            offset,
            binning,
            binning,
        )
        .await
        .map_err(|e| format!("Failed to capture: {:?}", e))?;

        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Cancelled by user", "idle", 0);
            return Ok(());
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
        if let Err(e) = write_temp_fits_for_solve(&image, &temp_path_str) {
            return Err(format!("Failed to write temp FITS: {}", e));
        }

        // Plate solve with configurable timeout
        let solve_future = api_plate_solve_blind(temp_path_str.clone());
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
            let ra_degrees = solve_result.ra * 15.0; // RA hours to degrees
            solved_points.push((ra_degrees, solve_result.dec));
            tracing::info!(
                "Point {} solved: RA={:.4}h ({:.4}°), Dec={:.4}°",
                point,
                solve_result.ra,
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

    let (mut center_ra, mut center_dec) = calculate_rotation_center(&solved_points);
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
        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Stopped", "idle", 0);
            return Ok(());
        }

        // Capture and solve to get current position
        emit_polar_status("Capturing...", "adjusting", 0);
        if let Err(e) = api_camera_start_exposure(
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

        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Stopped", "idle", 0);
            return Ok(());
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

        if let Err(e) = write_temp_fits_for_solve(&image, &temp_path_str) {
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
        let solve_future = api_plate_solve_blind(temp_path_str.clone());
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

            let ra_degrees = solve_result.ra * 15.0; // hours to degrees

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

            // Displacement of the boresight since the reference frame. RA is
            // scaled by cos(dec) to convert to a true angular offset and the
            // shortest-arc convention is applied so a wrap across 0/360° does
            // not produce a spurious ~360° jump.
            let mut d_ra = ra_degrees - ref_ra;
            if d_ra > 180.0 {
                d_ra -= 360.0;
            } else if d_ra < -180.0 {
                d_ra += 360.0;
            }
            let d_ra_ang = d_ra * ref_dec.to_radians().cos();
            let d_dec = solve_result.dec - ref_dec;

            // Apply the same displacement to the measured axis to get the
            // current axis. (First-order rigid-shift model of a small mount
            // adjustment; exact enough at the sub-degree errors PA targets.)
            let cur_axis_ra =
                initial_axis.0 + d_ra_ang / initial_axis.1.to_radians().cos().max(1e-6);
            let cur_axis_dec = initial_axis.1 + d_dec;

            tracing::debug!(
                "Adjustment: boresight Δ=({:.4}°,{:.4}°) → current axis RA={:.4}°, Dec={:.4}°",
                d_ra_ang,
                d_dec,
                cur_axis_ra,
                cur_axis_dec
            );

            // Error in ARCSECONDS (Dart UI labels values with `"` and uses
            // 30"/60" colour bands; the old code emitted arcMINUTES, so a real
            // 5' error displayed as 5" — 60x too small — and the auto-complete
            // fired ~60x too early).
            let (az_error, alt_error, total_error) =
                polar_axis_error_arcsec(cur_axis_ra, cur_axis_dec, pole_dec);
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

/// Helper to write a temp FITS file for plate solving
pub(crate) fn write_temp_fits_for_solve(
    image: &CapturedImageResult,
    path: &str,
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

    let header = FitsHeader::new();

    write_fits(Path::new(path), &image_data, &header)
        .map_err(|e| format!("FITS write error: {:?}", e))
}

/// Polar-alignment error of a measured rotation axis relative to the pole,
/// expressed in ARCSECONDS to match the Dart UI (which labels every value with
/// `"` and uses 30"/60" colour bands) and the arcsecond `auto_complete_threshold`.
///
/// Returns `(azimuth_error_arcsec, altitude_error_arcsec, total_error_arcsec)`.
///
/// Geometry: the mount's RA axis points at `(axis_ra_deg, axis_dec_deg)`; a
/// perfectly aligned mount points its axis at the celestial pole
/// (`dec = ±90°`). The TOTAL error is the true angular separation between the
/// axis unit vector and the pole unit vector — `90° − axis_dec` for the north
/// pole — which is robust and only reaches 0 when the axis genuinely sits on
/// the pole (the previous `(0 − center_ra)·cos(dec)` formula collapsed to ~0
/// whenever the rolling fit drifted toward the pole, under-reporting the error).
///
/// The total offset is decomposed into two orthogonal tangent-plane components
/// at the pole so that `sqrt(alt² + az²) == total` exactly:
///   - altitude component along the RA=0/12h meridian: `θ·cos(axis_ra)`
///   - azimuth component along the RA=6h/18h meridian: `θ·sin(axis_ra)`
///
/// NOTE (needs on-mount validation): this decomposition is in the equatorial
/// tangent frame, not the observer's local horizontal alt/az frame (which would
/// require latitude + LST). The TOTAL magnitude and the convergence-to-zero
/// behaviour are correct; the alt-vs-az split direction must be confirmed
/// against a real mount so the "move up/down vs left/right" guidance matches.
pub(crate) fn polar_axis_error_arcsec(
    axis_ra_deg: f64,
    axis_dec_deg: f64,
    pole_dec_deg: f64,
) -> (f64, f64, f64) {
    // Total angular separation between the axis and the pole, in degrees.
    // For the north pole this is (90 - axis_dec); for the south pole the axis
    // dec is negative, so the separation is (axis_dec - (-90)) = axis_dec + 90,
    // i.e. |pole_dec - axis_dec| with both on the same hemisphere. Use the
    // dot-product form to stay correct for any axis_dec.
    let axis_dec = axis_dec_deg.to_radians();
    let axis_ra = axis_ra_deg.to_radians();
    let pole_z = if pole_dec_deg >= 0.0 { 1.0 } else { -1.0 };
    // a·p where p = (0, 0, ±1) and a = (cos d cos r, cos d sin r, sin d)
    let cos_sep = (axis_dec.sin() * pole_z).clamp(-1.0, 1.0);
    let sep_rad = cos_sep.acos();
    let sep_arcsec = sep_rad.to_degrees() * 3600.0;

    // Tangent-plane decomposition at the pole. cos/sin of the axis RA give the
    // direction of the offset around the pole; for the south pole the RA sense
    // mirrors, so flip the azimuth sign to keep a right-handed local frame.
    let alt_arcsec = sep_arcsec * axis_ra.cos();
    let az_arcsec = sep_arcsec * axis_ra.sin() * pole_z;

    (az_arcsec, alt_arcsec, sep_arcsec)
}

/// Calculate the center of rotation from 3 solved points using 3D plane fitting
pub(crate) fn calculate_rotation_center(points: &[(f64, f64)]) -> (f64, f64) {
    if points.len() < 3 {
        return (0.0, 90.0);
    }

    // Convert spherical (RA, Dec) to Cartesian unit vectors
    let vectors: Vec<(f64, f64, f64)> = points
        .iter()
        .map(|(ra, dec)| {
            let ra_rad = ra.to_radians();
            let dec_rad = dec.to_radians();
            (
                dec_rad.cos() * ra_rad.cos(),
                dec_rad.cos() * ra_rad.sin(),
                dec_rad.sin(),
            )
        })
        .collect();

    // The three points define a plane. The rotation axis is the normal to this plane.
    let p1 = vectors[0];
    let p2 = vectors[1];
    let p3 = vectors[2];

    let v1 = (p2.0 - p1.0, p2.1 - p1.1, p2.2 - p1.2);
    let v2 = (p3.0 - p1.0, p3.1 - p1.1, p3.2 - p1.2);

    // Cross product for normal
    let nx = v1.1 * v2.2 - v1.2 * v2.1;
    let ny = v1.2 * v2.0 - v1.0 * v2.2;
    let nz = v1.0 * v2.1 - v1.1 * v2.0;

    // Normalize
    let mag = (nx * nx + ny * ny + nz * nz).sqrt();
    if mag < 1e-9 {
        return (0.0, 90.0);
    }

    let nx = nx / mag;
    let ny = ny / mag;
    let nz = nz / mag;

    // Convert back to RA/Dec
    let center_dec_rad = nz.asin();
    let mut center_ra_rad = ny.atan2(nx);

    if center_ra_rad < 0.0 {
        center_ra_rad += 2.0 * std::f64::consts::PI;
    }

    (center_ra_rad.to_degrees(), center_dec_rad.to_degrees())
}

/// Stop the polar alignment process
pub async fn api_stop_polar_alignment() -> Result<(), NightshadeError> {
    if !get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Ok(()); // Already stopped
    }

    // Signal cancellation
    get_polar_align_cancel().store(true, PolarOrdering::Relaxed);

    tracing::info!("Stopping polar alignment");

    // Give the background task time to clean up
    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

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

    // Reject re-entrant starts.
    if get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Err(NightshadeError::OperationFailed(
            "Polar alignment already running".to_string(),
        ));
    }

    // Fail loudly if the plate solver isn't installed — the all-sky
    // algorithm is plate-solve-only by design.
    if !nightshade_imaging::is_solver_available() {
        return Err(NightshadeError::OperationFailed(
            "Plate solver required — install ASTAP and re-run all-sky polar alignment".to_string(),
        ));
    }

    get_polar_align_flag().store(true, PolarOrdering::Relaxed);
    get_polar_align_cancel().store(false, PolarOrdering::Relaxed);

    tracing::info!(
        "Starting all-sky polar alignment: exposure={}s, threshold={}\", cadence={}s, north={}",
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
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::DeviceNotFound("No camera connected".to_string())
        })?;
    let mount_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Mount)
        .map(|d| d.id.clone())
        .ok_or_else(|| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::DeviceNotFound("No mount connected".to_string())
        })?;

    // Observer location is mandatory for the horizontal-frame projection.
    let location = get_state()
        .get_observer_location()
        .map_err(|e| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::OperationFailed(format!("Failed to read observer location: {}", e))
        })?
        .ok_or_else(|| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
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

    tokio::spawn(async move {
        let ctx = InstructionContext {
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

        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
    });

    Ok(())
}

#[cfg(test)]
mod polar_error_tests {
    use super::polar_axis_error_arcsec;

    /// A perfectly aligned axis (sitting on the north pole) reports ~0 error.
    #[test]
    fn aligned_axis_reports_zero() {
        let (az, alt, total) = polar_axis_error_arcsec(0.0, 90.0, 90.0);
        assert!(total.abs() < 1e-6, "total should be ~0, got {total}");
        assert!(az.abs() < 1e-6 && alt.abs() < 1e-6);
    }

    /// The emitted error is in ARCSECONDS, not arcminutes. An axis 1° below the
    /// pole must report 3600", NOT 60. This is the core 60x bug: the old code
    /// multiplied degrees by 60 (arcmin), but the Dart UI labels values with `"`.
    #[test]
    fn error_is_in_arcseconds_not_arcminutes() {
        // Axis at dec = 89° (1° from the pole). Total separation = 1° = 3600".
        let (_, _, total) = polar_axis_error_arcsec(0.0, 89.0, 90.0);
        assert!(
            (total - 3600.0).abs() < 1.0,
            "1° offset must be 3600 arcsec, got {total}"
        );
        // Sanity: definitely not the old arcminute value (60).
        assert!(total > 1000.0, "must not be the old arcminute scale");
    }

    /// The decomposition is consistent: sqrt(alt² + az²) == total exactly, so
    /// the displayed components never disagree with the displayed total.
    #[test]
    fn components_compose_to_total() {
        for &(ra, dec) in &[(45.0, 89.5), (123.0, 88.0), (270.0, 89.9), (310.0, 85.0)] {
            let (az, alt, total) = polar_axis_error_arcsec(ra, dec, 90.0);
            let composed = (az * az + alt * alt).sqrt();
            assert!(
                (composed - total).abs() < 1e-6,
                "sqrt(alt^2+az^2)={composed} must equal total={total} (ra={ra},dec={dec})"
            );
        }
    }

    /// The error grows monotonically as the axis drifts further from the pole —
    /// it does NOT collapse to ~0 for a misaligned axis (the old 3-point re-fit
    /// reported ~0 from a stationary, badly-aligned mount).
    #[test]
    fn error_grows_with_misalignment_no_collapse() {
        let small = polar_axis_error_arcsec(30.0, 89.9, 90.0).2;
        let medium = polar_axis_error_arcsec(30.0, 89.0, 90.0).2;
        let large = polar_axis_error_arcsec(30.0, 87.0, 90.0).2;
        assert!(small < medium && medium < large, "{small} {medium} {large}");
        assert!(
            large > 10_000.0,
            "3° misalignment must be a large arcsec value"
        );
    }

    /// Works for the south celestial pole too (axis_dec near -90).
    #[test]
    fn south_pole_alignment() {
        let aligned = polar_axis_error_arcsec(0.0, -90.0, -90.0).2;
        assert!(aligned.abs() < 1e-6, "south-pole aligned should be ~0");
        let off = polar_axis_error_arcsec(0.0, -89.0, -90.0).2;
        assert!(
            (off - 3600.0).abs() < 1.0,
            "1° south offset = 3600\", got {off}"
        );
    }
}
