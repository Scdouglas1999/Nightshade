//! `autofocus.rs` — moved verbatim out of the former single-file `instructions.rs`
//! (release-pass C3 mechanical split). No logic changed; private items were
//! widened to `pub(crate)` so the sibling modules and the tests module still
//! see them, and `super::*` supplies the imports the original file had.

use super::*;

// Autofocus instruction

/// Process-wide hardware admission for autofocus. Every entry path ultimately
/// calls this module (standalone bridge, sequence node, recovery, meridian
/// flip), so a single atomic gate prevents two callers from sweeping the same
/// camera/focuser pair concurrently.
pub(crate) static AUTOFOCUS_RUN_ACTIVE: AtomicBool = AtomicBool::new(false);

pub struct AutofocusRunGuard;

impl Drop for AutofocusRunGuard {
    fn drop(&mut self) {
        AUTOFOCUS_RUN_ACTIVE.store(false, Ordering::Release);
    }
}

pub fn try_admit_autofocus_run() -> Option<AutofocusRunGuard> {
    AUTOFOCUS_RUN_ACTIVE
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .ok()
        .map(|_| AutofocusRunGuard)
}

/// Execute autofocus using V-curve or curve fitting, acquiring the shared
/// camera/focuser admission gate first.
///
/// Fail-fast: if the gate is already held, returns immediately with the
/// "already running" error so the one-shot / REST layer can surface a typed
/// `DeviceBusy`. Sequence NODES should use [execute_autofocus_for_node]
/// instead, which waits for an in-flight run rather than aborting the run.
pub async fn execute_autofocus(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let Some(guard) = try_admit_autofocus_run() else {
        return InstructionResult::failure(
            "Autofocus is already running on this equipment host".to_string(),
        );
    };
    execute_autofocus_admitted(config, ctx, progress_callback, guard).await
}

/// Execute autofocus for a SEQUENCE NODE, waiting for any in-flight autofocus
/// to release the shared admission gate before running.
///
/// An explicit `Autofocus` node routinely races a concurrently-fired
/// trigger-autofocus: the HFR-degradation / focus-invalidation trigger fires
/// its own run (grabbing the gate) at the same tick the node is dispatched.
/// With plain fail-fast [execute_autofocus] the node then failed with
/// "Autofocus is already running", which aborted the ENTIRE sequence — a
/// benign scheduling race turning into a night-ending failure. A node must
/// never abort the run for this reason: wait for the in-flight run to finish
/// (the operator asked for an autofocus HERE), then perform this node's own
/// run. Bounded so a leaked/stuck gate can't hang the sequence forever.
pub async fn execute_autofocus_for_node(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    pause: &crate::node::context::PauseGate,
) -> InstructionResult {
    // An autofocus run is at most a few minutes (per-node timeout); cap the
    // admission wait generously above that so a genuine concurrent run always
    // completes first, while a leaked gate still surfaces as a failure rather
    // than hanging.
    const MAX_ADMISSION_WAIT: Duration = Duration::from_secs(600);
    let Some(guard) = admit_autofocus_run_waiting(MAX_ADMISSION_WAIT).await else {
        return InstructionResult::failure(
            "Autofocus could not start: another autofocus held the \
             equipment for over 10 minutes"
                .to_string(),
        );
    };
    execute_autofocus_admitted_with_pause(config, ctx, progress_callback, guard, pause).await
}

/// Acquire the shared autofocus admission gate, waiting (bounded) for any
/// in-flight run to release it. Returns the guard, or `None` on timeout.
///
/// Uses `tokio::time` so the deadline honours a paused test clock (and so the
/// timeout is driven by the same runtime as the poll sleeps).
pub(crate) async fn admit_autofocus_run_waiting(max_wait: Duration) -> Option<AutofocusRunGuard> {
    tokio::time::timeout(max_wait, async {
        let mut announced = false;
        loop {
            if let Some(guard) = try_admit_autofocus_run() {
                return guard;
            }
            if !announced {
                announced = true;
                tracing::info!(
                    "Autofocus node deferring to an in-flight autofocus run; \
                     waiting for it to finish before starting this node's run"
                );
            }
            sleep(Duration::from_millis(200)).await;
        }
    })
    .await
    .ok()
}

/// Execute a run for a caller that already owns [AutofocusRunGuard]. This is
/// public so the bridge can translate an admission rejection into the typed
/// `DeviceBusy` error expected by the REST layer.
///
/// One-shot callers have no run to pause, so this entry point uses the
/// never-paused gate. Sequence callers go through
/// [execute_autofocus_admitted_with_pause].
pub async fn execute_autofocus_admitted(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    guard: AutofocusRunGuard,
) -> InstructionResult {
    execute_autofocus_admitted_with_pause(
        config,
        ctx,
        progress_callback,
        guard,
        &crate::node::context::PauseGate::default(),
    )
    .await
}

/// [execute_autofocus_admitted] with the run's operator-pause handle attached,
/// so the V-curve sweep holds between sample points instead of driving the
/// focuser and opening the shutter for the rest of the sweep while the UI
/// says PAUSED.
pub async fn execute_autofocus_admitted_with_pause(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    _guard: AutofocusRunGuard,
    pause: &crate::node::context::PauseGate,
) -> InstructionResult {
    let mut effective_config = config.clone();

    // Resolve the imaging filter at runtime. A sequence can reach the same AF
    // node through different filter branches, so choosing per-filter exposure,
    // binning, gain, and offset during Dart serialization would be wrong.
    let mut original_filter: Option<(String, i32)> = None;
    let mut filter_names = Vec::new();
    let needs_filter_context = !config.filter_settings.is_empty()
        || config
            .filter
            .as_deref()
            .is_some_and(|name| !name.trim().is_empty());
    if needs_filter_context {
        if let Some(filterwheel_id) = ctx.filterwheel_id.as_deref() {
            let position = match ctx
                .device_ops
                .filterwheel_get_position(filterwheel_id)
                .await
            {
                Ok(position) if position >= 0 => position,
                Ok(position) => {
                    return InstructionResult::failure(format!(
                        "Cannot start autofocus while the filter wheel reports moving position {}",
                        position
                    ))
                }
                Err(error) => {
                    return InstructionResult::failure(format!(
                        "Cannot read the current filter before autofocus: {}",
                        error
                    ))
                }
            };
            filter_names = match ctx.device_ops.filterwheel_get_names(filterwheel_id).await {
                Ok(names) => names,
                Err(error) => {
                    return InstructionResult::failure(format!(
                        "Cannot read filter names before autofocus: {}",
                        error
                    ))
                }
            };
            let Some(name) = filter_names.get(position as usize).cloned() else {
                return InstructionResult::failure(format!(
                    "Filter wheel position {} has no configured name; autofocus cannot apply per-filter settings safely",
                    position
                ));
            };
            original_filter = Some((name, position));
        } else if config
            .filter
            .as_deref()
            .is_some_and(|name| !name.trim().is_empty())
        {
            return InstructionResult::failure(format!(
                "Autofocus is configured to use filter \"{}\", but no filter wheel is connected",
                config.filter.as_deref().unwrap_or_default().trim()
            ));
        }
    }

    let active_filter_name = original_filter
        .as_ref()
        .map(|(name, _)| name.as_str())
        .or(ctx.current_filter.as_deref());
    let active_override = active_filter_name
        .and_then(|name| config.filter_settings.get(name))
        .cloned();
    if let Some(filter_config) = &active_override {
        if let Some(exposure) = filter_config.af_exposure_time {
            effective_config.exposure_duration = exposure;
        }
        effective_config.binning = filter_config.binning;
        effective_config.gain = filter_config.gain;
        effective_config.offset = filter_config.offset;
    }

    let requested_filter = active_override
        .as_ref()
        .and_then(|settings| settings.af_filter_name.as_deref())
        .filter(|name| !name.trim().is_empty())
        .or(effective_config.filter.as_deref())
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_string);

    if let Err(message) = validate_autofocus_config(&effective_config) {
        return InstructionResult::failure(message);
    }

    let mut guiding_was_paused = false;
    if effective_config.disable_guiding_during_af {
        let guider_status = match ctx.device_ops.guider_get_status().await {
            Ok(status) => status,
            Err(error) => {
                return InstructionResult::failure(format!(
                "Autofocus is configured to pause guiding, but guider status could not be read: {}",
                error
            ))
            }
        };
        if guider_status.is_guiding {
            if let Err(error) = ctx.device_ops.guider_stop().await {
                return InstructionResult::failure(format!(
                    "Autofocus is configured to pause guiding, but guiding could not be stopped: {}",
                    error
                ));
            }
            guiding_was_paused = true;
            if let Some(trigger_state) = &ctx.trigger_state {
                let mut state = trigger_state.write().await;
                state.set_guiding_enabled(false);
                state.set_guide_star_lost(false);
            }
        }
    }

    let mut filter_restore_required = false;
    let mut pre_run_error = None;
    if let Some(target_name) = requested_filter.as_deref() {
        match &original_filter {
            Some((original_name, _original_position)) if original_name != target_name => {
                if let Some(target_position) =
                    filter_names.iter().position(|name| name == target_name)
                {
                    // The wheel may move before verification fails, so restoration
                    // responsibility begins before the command is sent.
                    filter_restore_required = true;
                    if let Err(error) =
                        move_autofocus_filter(ctx, target_name, target_position as i32).await
                    {
                        pre_run_error = Some(format!(
                            "Failed to switch to autofocus filter \"{}\": {}",
                            target_name, error
                        ));
                    }
                } else {
                    pre_run_error = Some(format!(
                        "Configured autofocus filter \"{}\" is not present in the connected wheel",
                        target_name
                    ));
                }
            }
            Some(_) => {}
            None => {
                pre_run_error = Some(format!(
                    "Autofocus is configured to use filter \"{}\", but no filter wheel is connected",
                    target_name
                ));
            }
        }
    }

    let mut result = match pre_run_error {
        Some(error) => InstructionResult::failure(error),
        None => execute_autofocus_attempts(&effective_config, ctx, progress_callback, pause).await,
    };

    if filter_restore_required {
        if let Some((original_name, original_position)) = &original_filter {
            if let Err(error) = move_autofocus_filter(ctx, original_name, *original_position).await
            {
                result = append_autofocus_cleanup_failure(
                    result,
                    format!(
                        "failed to restore original filter \"{}\" at position {}: {}",
                        original_name, original_position, error
                    ),
                );
            }
        }
    }

    if guiding_was_paused {
        result = resume_guiding_after_autofocus(ctx, result).await;
    }

    result
}

pub(crate) async fn execute_autofocus_attempts(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    pause: &crate::node::context::PauseGate,
) -> InstructionResult {
    let attempts = config.number_of_attempts.max(1);
    for attempt in 1..=attempts {
        if !pause.wait_while_paused(&ctx.cancellation_token).await {
            return InstructionResult::cancelled("Autofocus cancelled while paused");
        }
        let result = execute_autofocus_once(config, ctx, progress_callback, pause).await;
        if !matches!(result.status, NodeStatus::Failure) || attempt == attempts {
            return result;
        }
        if result
            .data
            .as_ref()
            .and_then(|data| data.get("autofocus_origin_restored"))
            .and_then(serde_json::Value::as_bool)
            == Some(false)
        {
            return result;
        }
        if let Some(cb) = progress_callback {
            cb(
                0.0,
                format!("Autofocus attempt {attempt}/{attempts} failed; retrying full sweep"),
            );
        }
        tracing::warn!(
            "Autofocus attempt {}/{} failed; starting the next configured attempt",
            attempt,
            attempts
        );
    }
    unreachable!("attempt count is clamped to at least one")
}

pub(crate) async fn move_autofocus_filter(
    ctx: &InstructionContext,
    filter_name: &str,
    target_position: i32,
) -> Result<(), String> {
    let filterwheel_id = ctx
        .filterwheel_id
        .as_deref()
        .filter(|id| !id.is_empty())
        .ok_or_else(|| "no filter wheel is connected".to_string())?;

    ctx.device_ops
        .filterwheel_set_position(filterwheel_id, target_position)
        .await
        .map_err(|error| format!("filter move command failed: {}", error))?;

    // Cleanup still owns the wheel after cancellation, so this verification
    // intentionally does not consult the sequence cancellation token.
    let start = std::time::Instant::now();
    let timeout = Duration::from_secs(DEFAULT_FILTER_WHEEL_TIMEOUT_SECS);
    sleep(Duration::from_millis(100)).await;
    loop {
        match ctx
            .device_ops
            .filterwheel_get_position(filterwheel_id)
            .await
        {
            Ok(position) if position == target_position => break,
            Ok(_) => {}
            Err(error) => tracing::warn!(
                "Error verifying autofocus filter move to {}: {}",
                target_position,
                error
            ),
        }
        if start.elapsed() > timeout {
            return Err(format!(
                "filter wheel did not reach position {} within {} seconds",
                target_position,
                timeout.as_secs()
            ));
        }
        sleep(Duration::from_millis(200)).await;
    }

    apply_filter_focus_offset(filter_name, ctx, None)
        .await
        .map_err(|error| format!("focus offset failed: {}", error))
}

pub(crate) async fn resume_guiding_after_autofocus(
    ctx: &InstructionContext,
    result: InstructionResult,
) -> InstructionResult {
    if let Err(error) = ctx.device_ops.guider_start(1.0, 10.0, 60.0).await {
        return append_autofocus_cleanup_failure(
            result,
            format!("failed to resume guiding after autofocus: {}", error),
        );
    }
    match ctx.device_ops.guider_get_status().await {
        Ok(status) if status.is_guiding => {
            if let Some(trigger_state) = &ctx.trigger_state {
                trigger_state.write().await.set_guiding_enabled(true);
            }
            result
        }
        Ok(_) => append_autofocus_cleanup_failure(
            result,
            "guider accepted resume but did not report guiding".to_string(),
        ),
        Err(error) => append_autofocus_cleanup_failure(
            result,
            format!(
                "could not verify guiding resumed after autofocus: {}",
                error
            ),
        ),
    }
}

pub(crate) fn append_autofocus_cleanup_failure(
    mut result: InstructionResult,
    failure: String,
) -> InstructionResult {
    let prior = result
        .message
        .take()
        .unwrap_or_else(|| "Autofocus did not complete".to_string());
    result.status = NodeStatus::Failure;
    result.message = Some(format!("{}; CRITICAL CLEANUP FAILURE: {}", prior, failure));
    result
}

pub(crate) fn validate_autofocus_config(config: &AutofocusConfig) -> Result<(), String> {
    if !config.exposure_duration.is_finite() || config.exposure_duration <= 0.0 {
        return Err("Autofocus exposure duration must be finite and positive".to_string());
    }
    if !config.max_duration_secs.is_finite() || config.max_duration_secs <= 0.0 {
        return Err("Autofocus maximum duration must be finite and positive".to_string());
    }
    if config.step_size <= 0 {
        return Err("Autofocus step size must be positive".to_string());
    }
    if !(1..=50).contains(&config.steps_out) {
        return Err("Autofocus steps out must be between 1 and 50".to_string());
    }
    if !(1..=10).contains(&config.number_of_attempts) {
        return Err("Autofocus attempt count must be between 1 and 10".to_string());
    }
    if !(1..=20).contains(&config.exposures_per_point) {
        return Err("Autofocus exposures per point must be between 1 and 20".to_string());
    }
    if !config.r_squared_threshold.is_finite() || !(0.0..=1.0).contains(&config.r_squared_threshold)
    {
        return Err("Autofocus R² threshold must be between 0 and 1".to_string());
    }
    if !config.outer_crop_ratio.is_finite()
        || !config.inner_crop_ratio.is_finite()
        || config.outer_crop_ratio <= 0.0
        || config.outer_crop_ratio > 1.0
        || config.inner_crop_ratio < 0.0
        || config.inner_crop_ratio >= config.outer_crop_ratio
    {
        return Err("Autofocus crop ratios must satisfy 0 <= inner < outer <= 1".to_string());
    }
    if config.focuser_settle_time_ms > 10_000 {
        return Err("Autofocus focuser settle time cannot exceed 10000 ms".to_string());
    }
    if config.backlash_compensation < 0 || config.backlash_out_compensation < 0 {
        return Err("Autofocus backlash values cannot be negative".to_string());
    }
    if config.gain.is_some_and(|gain| gain < 0) || config.offset.is_some_and(|offset| offset < 0) {
        return Err("Autofocus gain and offset cannot be negative".to_string());
    }
    for (filter_name, filter_config) in &config.filter_settings {
        if filter_name.trim().is_empty() {
            return Err("Autofocus per-filter settings contain an empty filter name".to_string());
        }
        if filter_config
            .af_exposure_time
            .is_some_and(|exposure| !exposure.is_finite() || exposure <= 0.0)
        {
            return Err(format!(
                "Autofocus exposure override for filter \"{}\" must be finite and positive",
                filter_name
            ));
        }
        if filter_config.gain.is_some_and(|gain| gain < 0)
            || filter_config.offset.is_some_and(|offset| offset < 0)
        {
            return Err(format!(
                "Autofocus gain and offset overrides for filter \"{}\" cannot be negative",
                filter_name
            ));
        }
    }
    Ok(())
}

pub(crate) async fn execute_autofocus_once(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    pause: &crate::node::context::PauseGate,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };
    let focuser_id = match ctx.focuser_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!(
        "Starting autofocus: {:?} method, {} steps, step size {}",
        config.method,
        config.steps_out,
        config.step_size
    );

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(0.0, "Starting autofocus...".to_string());
    }

    // Sweep positions are calculated from the current position outward;
    // failing the read here is fatal because the alternative is to sweep
    // from a guessed origin and land somewhere unrelated to focus.
    tracing::debug!("Getting focuser position for focuser_id: {}", focuser_id);
    let current_position = match ctx.device_ops.focuser_get_position(&focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            tracing::error!("Autofocus failed: Could not get focuser position: {}", e);
            return InstructionResult::failure(format!("Failed to get focuser position: {}", e));
        }
    };

    tracing::info!("Current focuser position: {}", current_position);

    let af_timeout = Duration::from_secs_f64(config.max_duration_secs);
    let af_start_time = tokio::time::Instant::now();
    let autofocus_operation = async {
        let af_config: crate::autofocus::AutofocusConfig = config.into();

        let af_engine = crate::autofocus::VCurveAutofocus::new(af_config.clone());
        let backlash = crate::autofocus::BacklashCompensation::new_directional(
            af_config.backlash_compensation,
            af_config.backlash_out_compensation,
        );

        let positions = af_engine.calculate_positions(current_position);
        let total_points = positions.len();
        let start_position = positions[0];

        let mut focus_data: Vec<crate::autofocus::FocusDataPoint> =
            Vec::with_capacity(total_points);

        if let Some(cb) = progress_callback {
            cb(5.0, format!("Moving to start position: {}", start_position));
        }

        if backlash.is_needed(current_position, start_position) {
            let (intermediate, final_pos) =
                backlash.calculate_approach(current_position, start_position);

            if let Some(overshoot) = intermediate {
                tracing::info!(
                    "Applying backlash compensation: {} -> {} -> {}",
                    current_position,
                    overshoot,
                    final_pos
                );

                if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, overshoot).await {
                    return InstructionResult::failure(format!(
                        "Failed to move focuser (backlash): {}",
                        e
                    ));
                }
                if let Err(e) =
                    wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await
                {
                    return InstructionResult::failure(e);
                }
            }

            if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, final_pos).await {
                return InstructionResult::failure(format!("Failed to move focuser: {}", e));
            }
        } else {
            tracing::info!("Moving to start position: {}", start_position);
            if let Err(e) = ctx
                .device_ops
                .focuser_move_to(&focuser_id, start_position)
                .await
            {
                return InstructionResult::failure(format!("Failed to move focuser: {}", e));
            }
        }

        if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(300)).await {
            return InstructionResult::failure(e);
        }
        if let Some(result) = wait_for_autofocus_settle(config, ctx).await {
            return result;
        }

        let (bin_x, bin_y) = match config.binning {
            Binning::One => (1, 1),
            Binning::Two => (2, 2),
            Binning::Three => (3, 3),
            Binning::Four => (4, 4),
        };

        // The minimum star count is `config.min_star_count` (default 10 from
        // `default_af_min_star_count`), so a user with a fast or dim setup can
        // lower it without patching the binary.
        let min_star_count: u32 = config.min_star_count.max(1);
        // 1.0 px² is the noise floor: a V-curve with smaller HFR variance is
        // indistinguishable from flat noise and the fit would extrapolate to
        // nonsense.
        const MIN_HFR_VARIANCE: f64 = 1.0;
        let mut low_star_count_warnings = 0;
        // Time the operator spent holding the run paused mid-sweep. Excluded
        // from the autofocus deadline below: a Pause is not the focuser being
        // slow, and charging it to the budget would fail a sweep that was
        // healthy right up to the moment the operator stepped away.
        let mut paused_duration = Duration::ZERO;

        for point in 0..total_points {
            // Check timeout
            let working_elapsed = af_start_time.elapsed().saturating_sub(paused_duration);
            if working_elapsed > af_timeout {
                tracing::warn!(
                "Autofocus timed out after {:.0}s (limit: {:.0}s), returning focuser to original position",
                working_elapsed.as_secs_f64(),
                config.max_duration_secs,
            );
                return InstructionResult::failure(format!(
                    "Autofocus timed out after {:.0}s (max duration: {:.0}s)",
                    working_elapsed.as_secs_f64(),
                    config.max_duration_secs,
                ));
            }

            if let Some(result) = ctx.check_cancelled() {
                return result;
            }

            // Honour an operator Pause between sample points. A V-curve sweep
            // is ~15 exposures plus focuser motion inside ONE instruction, so
            // the node-boundary check the tree does never sees a Pause pressed
            // during the sweep.
            if pause.is_paused() {
                let paused_at = tokio::time::Instant::now();
                if !pause.wait_while_paused(&ctx.cancellation_token).await {
                    return InstructionResult::cancelled("Autofocus cancelled while paused");
                }
                paused_duration += paused_at.elapsed();
            }

            let position = positions[point];

            // 10-90% covers the V-curve sample loop; the remaining 10% is the
            // final move + settle + curve fit, which is the noticeable wait the
            // user sees after the last sample is taken.
            // Why: point and total_points are usize bounded by sweep size (<=50 in UI);
            // lossless to f64.
            let point_progress = 10.0 + (point as f64 / total_points as f64 * 80.0);

            tracing::info!(
                "Focus point {}/{} at position {}",
                point + 1,
                total_points,
                position
            );
            if let Some(cb) = progress_callback {
                cb(
                    point_progress,
                    format!("Point {}/{}: pos {}", point + 1, total_points, position),
                );
            }

            if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, position).await {
                return InstructionResult::failure(format!("Failed to move focuser: {}", e));
            }

            if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await
            {
                return InstructionResult::failure(e);
            }
            if let Some(result) = wait_for_autofocus_settle(config, ctx).await {
                return result;
            }

            let mut measurements = Vec::with_capacity(config.exposures_per_point as usize);
            for sample in 0..config.exposures_per_point {
                if let Some(result) = ctx.check_cancelled() {
                    return result;
                }
                let mut abort_guard =
                    CameraExposureAbortGuard::new(ctx.device_ops.clone(), camera_id.clone());
                let exposure_result = ctx
                    .device_ops
                    .camera_start_exposure(
                        &camera_id,
                        config.exposure_duration,
                        config.gain,
                        config.offset,
                        bin_x,
                        bin_y,
                    )
                    .await;
                abort_guard.disarm();
                let image_data = match exposure_result {
                    Ok(data) => {
                        tracing::info!(
                            "[SEQ] Autofocus point {} sample {}/{} completed: {}x{} ({} pixels)",
                            point + 1,
                            sample + 1,
                            config.exposures_per_point,
                            data.width,
                            data.height,
                            data.data.len()
                        );
                        data
                    }
                    Err(e) => {
                        return InstructionResult::failure(format!(
                            "Autofocus exposure failed: {}",
                            e
                        ))
                    }
                };
                measurements.push(calculate_hfr_with_crops(
                    &image_data,
                    config.outer_crop_ratio,
                    config.inner_crop_ratio,
                    config.use_brightest_n_stars,
                ));
            }
            measurements.sort_by(|a, b| a.hfr.total_cmp(&b.hfr));
            let measurement = measurements.swap_remove(measurements.len() / 2);

            tracing::info!(
                "Position {} HFR: {:.2}, Stars: {}",
                position,
                measurement.hfr,
                measurement.star_count
            );

            if measurement.star_count < min_star_count {
                low_star_count_warnings += 1;
                tracing::warn!(
                    "Low star count at position {}: {} stars (minimum: {})",
                    position,
                    measurement.star_count,
                    min_star_count
                );

                // >50% of sweep points failing star detection means seeing /
                // clouds / pointing has degraded so badly that no fit will be
                // meaningful; failing fast saves the user the rest of the sweep
                // and a useless curve-fit error.
                if low_star_count_warnings > total_points / 2 {
                    return InstructionResult::failure(format!(
                    "Autofocus failed: Insufficient stars detected. Only {} stars found (minimum: {}). \
                     This may indicate clouds, poor seeing, or incorrect camera settings.",
                    measurement.star_count, min_star_count
                ));
                }
            }

            focus_data.push(crate::autofocus::FocusDataPoint {
                position,
                hfr: measurement.hfr,
                fwhm: None,
                star_count: measurement.star_count,
            });

            let progress_json = serde_json::json!({
                "type": "autofocus_progress",
                "point": point + 1,
                "total_points": total_points,
                "hfr": measurement.hfr,
                "star_count": measurement.star_count,
                "focus_range": {
                    "min": positions[0],
                    "max": positions[total_points - 1]
                },
                "vcurve_points": focus_data.iter().map(|point| {
                    serde_json::json!({"position": point.position, "hfr": point.hfr})
                }).collect::<Vec<_>>(),
                "star_crops": measurement.star_crops.iter().map(|crop| {
                    serde_json::json!({
                        "pixels_base64": crop.pixels_base64,
                        "width": crop.width,
                        "height": crop.height,
                        "hfr": crop.hfr,
                        "snr": crop.snr
                    })
                }).collect::<Vec<_>>()
            });

            if let Some(cb) = progress_callback {
                cb(point_progress, progress_json.to_string());
            }
        }

        if let Some(cb) = progress_callback {
            cb(92.0, "Validating focus data...".to_string());
        }

        // A flat HFR curve (variance < MIN_HFR_VARIANCE) is not a V-curve to fit
        // — it usually means clouds rolled in, the focuser is far outside the
        // critical zone, or the sensor is misreporting. Fitting anyway would
        // produce a meaningless "best focus" position.
        let hfr_values: Vec<f64> = focus_data.iter().map(|point| point.hfr).collect();
        let min_hfr = hfr_values.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_hfr = hfr_values.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        let hfr_variance = max_hfr - min_hfr;

        tracing::info!(
            "HFR variance: {:.2} (min: {:.2}, max: {:.2})",
            hfr_variance,
            min_hfr,
            max_hfr
        );

        if hfr_variance < MIN_HFR_VARIANCE {
            return InstructionResult::failure(format!(
            "Autofocus failed: No valid V-curve detected. HFR variance is only {:.2} (minimum: {:.1}). \
             The HFR is not changing with focus position, which may indicate: \
             - Clouds or obstructions blocking the sky \
             - Hot pixels being detected instead of real stars \
             - Focus range is too narrow or too far from true focus \
             - Camera is not properly connected or imaging",
            hfr_variance, MIN_HFR_VARIANCE
        ));
        }

        let af_result = match af_engine.find_best_focus(focus_data) {
            Ok(mut result) => {
                result.temperature_celsius = ctx
                    .device_ops
                    .focuser_get_temperature(&focuser_id)
                    .await
                    .ok()
                    .flatten();
                result
            }
            Err(e) => {
                tracing::warn!(
                "Autofocus curve fit failed ({}); shared attempt cleanup will restore position {}",
                e, current_position
            );
                return InstructionResult::failure(format!(
                    "Autofocus curve fitting failed: {}",
                    e
                ));
            }
        };

        // Clamp the fitted best-focus position to the swept range. The parabolic
        // and hyperbolic fits return the analytic vertex, which for a poor-quality
        // (low-R²) curve can land far outside the sampled bracket — an
        // extrapolation that is by definition untrustworthy and, on a permissive
        // driver, would drive the focuser wildly out of position. A vertex outside
        // the bracket means true focus was not bracketed; clamping bounds the move
        // to the sampled window (worst case: a sweep endpoint near where we
        // started) instead of an arbitrary extrapolated step.
        let sweep_lo = positions[0].min(positions[total_points - 1]);
        let sweep_hi = positions[0].max(positions[total_points - 1]);
        let best_position = {
            let raw = af_result.best_position;
            let clamped = raw.clamp(sweep_lo, sweep_hi);
            if clamped != raw {
                tracing::warn!(
                    "Autofocus best-focus vertex {} fell outside the swept range [{}, {}]; \
                 clamping to {}. The curve minimum was an extrapolation (poor fit) — \
                 true focus may lie outside the sweep window.",
                    raw,
                    sweep_lo,
                    sweep_hi,
                    clamped
                );
            }
            clamped
        };
        let best_hfr = af_result.best_hfr;
        let r_squared = af_result.curve_fit_quality;

        // The configured R² value is a real acceptance threshold, not a cosmetic
        // warning. Shared attempt cleanup restores the pre-run position before a
        // retry or terminal failure is returned.
        if r_squared < config.r_squared_threshold {
            tracing::warn!(
                "Low curve fit quality: R²={:.3} (required: {:.3}); returning to original position",
                r_squared,
                config.r_squared_threshold
            );
            return InstructionResult::failure(format!(
                "Autofocus curve fit R² {:.3} is below the configured threshold {:.3}",
                r_squared, config.r_squared_threshold
            ));
        }

        tracing::info!(
            "Best focus at position {}, HFR: {:.2}, R²: {:.3}",
            best_position,
            best_hfr,
            r_squared
        );

        if let Some(cb) = progress_callback {
            cb(95.0, format!("Moving to best focus: {}", best_position));
        }

        let last_position = positions[positions.len() - 1];
        if backlash.is_needed(last_position, best_position) {
            let (intermediate, final_pos) =
                backlash.calculate_approach(last_position, best_position);

            if let Some(overshoot) = intermediate {
                tracing::info!(
                    "Final move with backlash: overshoot to {}, then {}",
                    overshoot,
                    final_pos
                );

                if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, overshoot).await {
                    return InstructionResult::failure(format!(
                        "Failed to move focuser (final backlash): {}",
                        e
                    ));
                }
                if let Err(e) =
                    wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await
                {
                    return InstructionResult::failure(e);
                }
            }

            if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, final_pos).await {
                return InstructionResult::failure(format!("Failed to move to best focus: {}", e));
            }
        } else if let Err(e) = ctx
            .device_ops
            .focuser_move_to(&focuser_id, best_position)
            .await
        {
            return InstructionResult::failure(format!("Failed to move to best focus: {}", e));
        }

        if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await {
            return InstructionResult::failure(format!("Failed to settle at best focus: {}", e));
        }
        if let Some(result) = wait_for_autofocus_settle(config, ctx).await {
            return result;
        }

        if let Some(cb) = progress_callback {
            cb(
                100.0,
                format!(
                    "Complete: pos {}, HFR {:.2}, R² {:.3}",
                    best_position, best_hfr, r_squared
                ),
            );
        }

        InstructionResult {
            status: NodeStatus::Success,
            message: Some(format!(
                "Autofocus complete: position {}, HFR {:.2}, R² {:.3}",
                best_position, best_hfr, r_squared
            )),
            data: serde_json::to_value(&af_result).ok(),
            hfr_values: vec![best_hfr],
        }
    };

    // One deadline encloses every move command, idle poll, mechanical settle,
    // camera exposure, curve fit, and final move. Point-boundary checks alone
    // cannot enforce the advertised limit when any one of those awaits hangs.
    let mut result = match tokio::time::timeout(af_timeout, autofocus_operation).await {
        Ok(result) => result,
        Err(_) => {
            tracing::warn!(
                "Autofocus timed out after {:.0}s (limit: {:.0}s), returning focuser to original position",
                af_start_time.elapsed().as_secs_f64(),
                config.max_duration_secs,
            );
            InstructionResult::failure(format!(
                "Autofocus timed out after {:.0}s (max duration: {:.0}s)",
                af_start_time.elapsed().as_secs_f64(),
                config.max_duration_secs,
            ))
        }
    };

    if matches!(result.status, NodeStatus::Failure | NodeStatus::Cancelled) {
        let restored = restore_autofocus_origin(&focuser_id, ctx, current_position).await;
        if let Err(error) = &restored {
            tracing::error!(
                "Autofocus could not restore original position {}: {}",
                current_position,
                error
            );
            let prior = result
                .message
                .take()
                .unwrap_or_else(|| "Autofocus did not complete".to_string());
            result.message = Some(format!(
                "{}; CRITICAL: failed to restore original focuser position {}: {}",
                prior, current_position, error
            ));
        }
        let mut metadata = match result.data.take() {
            Some(serde_json::Value::Object(object)) => object,
            _ => serde_json::Map::new(),
        };
        metadata.insert(
            "autofocus_origin_restored".to_string(),
            serde_json::Value::Bool(restored.is_ok()),
        );
        result.data = Some(serde_json::Value::Object(metadata));
    }

    result
}

/// Restore the pre-attempt focuser position before returning any failed or
/// cancelled autofocus result. This deliberately ignores the sequence cancel
/// token: cleanup is still hardware work owned by the autofocus Future, and a
/// caller must not be told the run is terminal while the motor is moving.
pub(crate) async fn restore_autofocus_origin(
    focuser_id: &str,
    ctx: &InstructionContext,
    original_position: i32,
) -> Result<(), String> {
    let mut errors = Vec::new();

    if let Err(error) = ctx.device_ops.focuser_halt(focuser_id).await {
        errors.push(format!("halt failed: {}", error));
    }
    if !wait_for_focuser_stop_after_halt(focuser_id, &ctx.device_ops, Duration::from_secs(10)).await
    {
        errors.push("motor did not stop within 10 seconds".to_string());
    }

    match ctx
        .device_ops
        .focuser_move_to(focuser_id, original_position)
        .await
    {
        Ok(()) => {
            if !wait_for_focuser_stop_after_halt(
                focuser_id,
                &ctx.device_ops,
                Duration::from_secs(120),
            )
            .await
            {
                errors.push(format!(
                    "return move to {} did not settle within 120 seconds",
                    original_position
                ));
            }
        }
        Err(error) => errors.push(format!(
            "return move to {} was rejected: {}",
            original_position, error
        )),
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("; "))
    }
}

pub(crate) async fn wait_for_autofocus_settle(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
) -> Option<InstructionResult> {
    let mut remaining = config.focuser_settle_time_ms;
    while remaining > 0 {
        if let Some(result) = ctx.check_cancelled() {
            return Some(result);
        }
        let chunk = remaining.min(100);
        sleep(Duration::from_millis(chunk)).await;
        remaining -= chunk;
    }
    ctx.check_cancelled()
}

/// Enhanced HFR measurement with star crops for UI display
pub(crate) struct HfrMeasurementWithCrops {
    hfr: f64,
    star_count: u32,
    /// Base64-encoded star crops (80x80 grayscale), up to 5 brightest stars
    star_crops: Vec<StarCropInfo>,
}

/// Star crop info for UI display
#[derive(Clone)]
pub(crate) struct StarCropInfo {
    /// Base64-encoded grayscale pixels
    pixels_base64: String,
    width: u32,
    height: u32,
    hfr: f64,
    snr: f64,
}

/// Calculate HFR from image data, honoring the configured central crop and
/// brightest-star cap rather than merely transporting those settings.
pub(crate) fn calculate_hfr_with_crops(
    image: &ImageData,
    outer_crop_ratio: f64,
    inner_crop_ratio: f64,
    use_brightest_n_stars: u32,
) -> HfrMeasurementWithCrops {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
    use nightshade_imaging::{
        detect_stars_with_stats, extract_top_star_crops, StarDetectionConfig,
    };

    // 1 channel = monochrome; raw imager output is treated as mono for HFR
    // regardless of Bayer pattern, because debayering before star detection
    // would smear PSFs and inflate HFR.
    let imaging_data =
        nightshade_imaging::ImageData::from_u16(image.width, image.height, 1, &image.data);

    let config = StarDetectionConfig::default();
    let result = detect_stars_with_stats(&imaging_data, &config);

    let center_x = image.width as f64 / 2.0;
    let center_y = image.height as f64 / 2.0;
    let outer_half_width = image.width as f64 * outer_crop_ratio / 2.0;
    let outer_half_height = image.height as f64 * outer_crop_ratio / 2.0;
    let inner_half_width = image.width as f64 * inner_crop_ratio / 2.0;
    let inner_half_height = image.height as f64 * inner_crop_ratio / 2.0;

    // detect_stars returns brightness-ranked stars. Preserve that order so a
    // non-zero brightest-N setting is deterministic before calculating the
    // median HFR.
    let mut eligible_stars: Vec<_> = result
        .stars
        .into_iter()
        .filter(|star| {
            let dx = (star.x - center_x).abs();
            let dy = (star.y - center_y).abs();
            let inside_outer = dx <= outer_half_width && dy <= outer_half_height;
            let inside_inner =
                inner_crop_ratio > 0.0 && dx < inner_half_width && dy < inner_half_height;
            inside_outer && !inside_inner
        })
        .collect();
    if use_brightest_n_stars > 0 {
        eligible_stars.truncate(use_brightest_n_stars as usize);
    }

    let star_count = eligible_stars.len() as u32;
    let mut hfr_values: Vec<f64> = eligible_stars
        .iter()
        .map(|star| star.hfr)
        .filter(|hfr| hfr.is_finite() && *hfr > 0.0 && *hfr < 20.0)
        .collect();
    hfr_values.sort_by(f64::total_cmp);

    // 20.0 px is the "no valid focus" sentinel: an HFR this high is far
    // beyond any realistic well-focused setup, so the V-curve fit will
    // treat the point as the extreme of the curve (or reject as outlier).
    let hfr = if hfr_values.is_empty() {
        20.0
    } else {
        hfr_values[hfr_values.len() / 2]
    };

    // 5 crops @ 80 px is the upper bound the autofocus UI displays; more
    // would saturate the operator's view and inflate the JSON payload sent
    // over the FRB bridge.
    let crops = extract_top_star_crops(&imaging_data, &eligible_stars, 5, 80);

    let star_crops: Vec<StarCropInfo> = crops
        .into_iter()
        .map(|crop| StarCropInfo {
            pixels_base64: BASE64.encode(&crop.pixels),
            width: crop.width,
            height: crop.height,
            hfr: crop.hfr,
            snr: crop.snr,
        })
        .collect();

    HfrMeasurementWithCrops {
        hfr,
        star_count,
        star_crops,
    }
}
