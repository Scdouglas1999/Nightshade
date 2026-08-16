//! `cooling.rs` — moved verbatim out of the former single-file `instructions.rs`
//! (release-pass C3 mechanical split). No logic changed; private items were
//! widened to `pub(crate)` so the sibling modules and the tests module still
//! see them, and `super::*` supplies the imports the original file had.

use super::*;

// Camera COOLING/WARMING instructions

/// Execute camera cooling
pub async fn execute_cool_camera(
    config: &CoolConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => {
            tracing::error!("CoolCamera failed: No camera connected");
            return e;
        }
    };

    tracing::info!("Cooling camera to {}°C", config.target_temp);

    // Initial temperature anchors the progress percentage: the user sees
    // "30% cooled" as halfway between start and target rather than a raw
    // °C count that means nothing without context.
    let start_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
        Ok(value) => value,
        Err(e) => {
            return InstructionResult::failure(format!("Failed to read camera temperature: {}", e))
        }
    };
    let target_temp = config.target_temp;
    let temp_range = (start_temp - target_temp).abs();

    // 0.5 °C tolerance covers typical cooler noise on TEC-equipped cameras
    // (ZWO/QHY/PlayerOne all report jitter in the ±0.3 °C range when
    // settled); tighter would force a fake "cooling" loop on a camera
    // that is already where we want it.
    let already_at_target = (start_temp - target_temp).abs() < 0.5;

    if let Err(e) = ctx
        .device_ops
        .camera_set_cooler(&camera_id, true, target_temp)
        .await
    {
        return InstructionResult::failure(format!("Failed to enable cooler: {}", e));
    }

    if already_at_target {
        let cooler_power = match ctx.device_ops.camera_get_cooler_power(&camera_id).await {
            Ok(value) => value,
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Failed to read camera cooler power: {}",
                    e
                ))
            }
        };
        let msg = format!(
            "At target: {:.1}°C ({:.0}% power)",
            start_temp, cooler_power
        );
        tracing::info!("Camera already at target temperature: {}", msg);
        if let Some(cb) = progress_callback {
            cb(100.0, msg.clone());
        }
        return InstructionResult::success_with_message(msg);
    }

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Starting: {:.1}°C → {:.1}°C", start_temp, target_temp),
        );
    }

    // Always wait for the setpoint. The configured duration caps HOW LONG the
    // wait may run — it does not decide WHETHER it happens — and
    // non-convergence within the deadline is a hard failure: returning Success
    // on a `None` duration, or once the duration elapses, lets an unattended
    // sequence start exposing a warm or mis-cooled sensor.
    //
    // When no duration is configured the wait is still bounded by a generous
    // default so a stuck cooler cannot hang the sequence forever.
    const DEFAULT_COOL_TIMEOUT_SECS: f64 = 900.0; // 15 min — ample for any TEC ramp
    const POLL_SECS: f64 = 10.0;
    let deadline_secs = config
        .duration_mins
        .map(|m| (m * 60.0).max(0.0))
        .unwrap_or(DEFAULT_COOL_TIMEOUT_SECS);
    let mut elapsed_secs = 0.0_f64;

    loop {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }

        let current_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
            Ok(value) => value,
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Failed to read camera temperature during cooling: {}",
                    e
                ))
            }
        };
        let cooler_power = match ctx.device_ops.camera_get_cooler_power(&camera_id).await {
            Ok(value) => value,
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Failed to read camera cooler power: {}",
                    e
                ))
            }
        };

        // Direction-agnostic progress: (current - start) / (target - start).
        // Works for both cooling and warming because numerator and denominator
        // share a sign convention. Clamped so transient wobbles don't jump.
        let temp_progress = if temp_range > 0.1 {
            let raw = (current_temp - start_temp) / (target_temp - start_temp) * 100.0;
            raw.clamp(0.0, 100.0)
        } else {
            100.0
        };
        // Time-based progress is the floor: even if the camera struggles to
        // cool, the bar advances toward 100% as the deadline runs out, so the
        // user can see the wait is finite.
        let time_progress = if deadline_secs > 0.0 {
            (elapsed_secs / deadline_secs * 100.0).clamp(0.0, 100.0)
        } else {
            100.0
        };
        let progress = temp_progress.max(time_progress);

        tracing::debug!(
            "Cooling progress: {:.1}%, current temp: {:.1}°C, power: {:.0}%",
            progress,
            current_temp,
            cooler_power
        );

        if let Some(cb) = progress_callback {
            cb(
                progress,
                format!(
                    "Cooling: {:.1}°C → {:.1}°C ({:.0}% power)",
                    current_temp, target_temp, cooler_power
                ),
            );
        }

        if (current_temp - target_temp).abs() < 0.5 {
            let msg = format!(
                "Target reached: {:.1}°C ({:.0}% power)",
                current_temp, cooler_power
            );
            if let Some(cb) = progress_callback {
                cb(100.0, msg.clone());
            }
            return InstructionResult::success_with_message(msg);
        }

        if elapsed_secs >= deadline_secs {
            // Fail closed: the sensor did not reach the setpoint in time.
            return InstructionResult::failure(format!(
                "Camera did not reach target {:.1}°C within {:.0}s \
                 (last {:.1}°C, {:.0}% power)",
                target_temp, deadline_secs, current_temp, cooler_power
            ));
        }

        sleep(Duration::from_secs_f64(POLL_SECS)).await;
        elapsed_secs += POLL_SECS;
    }
}

/// Execute camera warming
pub async fn execute_warm_camera(
    config: &WarmConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!("Warming camera at {}°C/min", config.rate_per_min);

    let start_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
        Ok(value) => value,
        Err(e) => {
            return InstructionResult::failure(format!("Failed to read camera temperature: {}", e))
        }
    };
    // Why: `target_temp: Option<f64>` is a user-override on the
    // WarmCamera instruction; None means "use the conventional ambient-warming default
    // of 20°C", which is the safe shutdown-prep temperature for every cooled-sensor
    // chip in our supported matrix.
    let target_temp = config.target_temp.unwrap_or(20.0);
    let temp_range = target_temp - start_temp;
    let duration_mins = temp_range / config.rate_per_min;
    // Why: duration_mins is a computed temperature ramp; `.max(1.0)` ensures
    // at least one iteration. f64 -> u32 saturates per Rust 1.45 spec.
    let steps = (duration_mins * 6.0).max(1.0) as u32;

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Warming: {:.1}°C → {:.1}°C", start_temp, target_temp),
        );
    }

    for step in 0..steps {
        if let Some(result) = ctx.check_cancelled() {
            // Turn off cooler on cancel
            if let Err(error) = ctx
                .device_ops
                .camera_set_cooler(&camera_id, false, 20.0)
                .await
            {
                tracing::warn!(
                    "Warm camera '{}': switching the cooler off on cancel failed ({}); the \
                     sensor is still being cooled and is not warming for shutdown",
                    camera_id,
                    error
                );
            }
            return result;
        }

        // Why: step and steps are u32 bounded by the warming-loop config; lossless to f64.
        let progress_temp = start_temp + (temp_range * f64::from(step) / f64::from(steps));
        let progress_percent = (f64::from(step) / f64::from(steps)) * 100.0;

        // Gradually increase target temperature
        if let Err(e) = ctx
            .device_ops
            .camera_set_cooler(&camera_id, true, progress_temp)
            .await
        {
            tracing::warn!("Failed to update cooler target: {}", e);
        }

        // Emit progress
        if let Some(cb) = progress_callback {
            cb(
                progress_percent,
                format!("Warming: {:.1}°C → {:.1}°C", progress_temp, target_temp),
            );
        }

        tracing::debug!("Warming progress: {:.1}°C", progress_temp);
        sleep(Duration::from_secs(10)).await;
    }

    // Turn off cooler. The setpoint argument is ignored downstream for a
    // disable (see `DeviceManager::cooler_setpoint_to_command`); the DeviceOps
    // trait just has nowhere to say "none".
    //
    // The outcome is NOT discarded: on the reference rig this exact call
    // failed, and the instruction still reported "Camera warmed to ambient"
    // while the TEC stayed powered. A warm-up that could not switch the cooler
    // off has not warmed anything up.
    if let Err(e) = ctx
        .device_ops
        .camera_set_cooler(&camera_id, false, 20.0)
        .await
    {
        return InstructionResult::failure(format!(
            "Warmed to {:.1}°C but could not switch the cooler off: {}",
            target_temp, e
        ));
    }

    // Emit final progress
    if let Some(cb) = progress_callback {
        cb(100.0, "Warmed to ambient".to_string());
    }

    InstructionResult::success_with_message("Camera warmed to ambient")
}
