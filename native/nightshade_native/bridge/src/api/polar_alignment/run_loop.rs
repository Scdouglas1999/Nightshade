use super::*;

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
    // ...and the number that log line prints is the number the solver is
    // handed. It was computed, logged, and then dropped on the floor for three
    // release waves while every polar solve ran blind against a 0.4° field.
    let solve_scale = solve_hints.arcsec_per_px();

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
        let solve_future = crate::api::plate_solve::plate_solve_blind_scaled(
            temp_path_str.clone(),
            Some(solve_timeout_secs.ceil().clamp(1.0, 3600.0) as u32),
            solve_scale,
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
    // bolts. The axis is measured in the three-point phase from ROTATED points.
    // During
    // adjustment the mount is stationary (the user turns the bolts, not the RA
    // motor), so re-fitting the axis from the now-stationary frames is invalid —
    // three near-identical points give a degenerate plane, which collapses the
    // axis toward the pole and reports ~0 error from a badly misaligned mount.
    //
    // Instead we hold the measured axis and apply the displacement of the
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
        let solve_future = crate::api::plate_solve::plate_solve_blind_scaled(
            temp_path_str.clone(),
            Some(30),
            solve_scale,
        );
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
            // displacement (vs the first adjustment frame) to the measured axis.
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

            // Error in ARCSECONDS: the Dart UI labels these values with `"` and
            // uses 30"/60" colour bands, and the auto-complete threshold is in
            // the same unit. Emitting arcminutes here shows a 5' error as 5" and
            // fires the auto-complete ~60x too early.
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
