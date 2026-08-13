//! `filter.rs` — moved verbatim out of the former single-file `instructions.rs`
//! (release-pass C3 mechanical split). No logic changed; private items were
//! widened to `pub(crate)` so the sibling modules and the tests module still
//! see them, and `super::*` supplies the imports the original file had.

use super::*;

// =============================================================================
// FILTER CHANGE INSTRUCTION
// =============================================================================

/// Default timeout for filter wheel change operations (in seconds)
pub(crate) const DEFAULT_FILTER_WHEEL_TIMEOUT_SECS: u64 = 120;

/// Execute filter change
pub async fn execute_filter_change(
    config: &FilterConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let fw_id = match ctx.filterwheel_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Per-filter timeout overrides the global default to accommodate slow
    // wheels (motorized covers, many-position wheels) that legitimately
    // need longer than 120 s; configuring None preserves the safe default.
    // Why: `timeout_secs: Option<u32>` is the explicit
    // user-override slot — None means "use the documented default".
    let timeout = Duration::from_secs(
        config
            .timeout_secs
            // Why: u32 -> u64 widening is lossless.
            .map(u64::from)
            .unwrap_or(DEFAULT_FILTER_WHEEL_TIMEOUT_SECS),
    );

    tracing::info!(
        "Changing filter to: {} (timeout: {:?})",
        config.filter_name,
        timeout
    );

    if let Some(cb) = progress_callback {
        cb(0.0, format!("Changing to {}", config.filter_name));
    }

    // Index path is preferred over name (see execute_exposure rationale).
    if let Some(index) = config.filter_index {
        match ctx.device_ops.filterwheel_set_position(&fw_id, index).await {
            Ok(_) => {
                if let Some(cb) = progress_callback {
                    cb(30.0, format!("Moving to position {}", index));
                }
                if let Err(e) = wait_for_filterwheel_idle(&fw_id, index, ctx, timeout).await {
                    return InstructionResult::failure(e);
                }
                // Filter-specific focus offsets compensate for the differing
                // optical path length of each filter glass; applying them
                // here keeps the focus point usable for the next exposure
                // without forcing the user to run autofocus after every
                // filter change.
                if let Err(e) =
                    apply_filter_focus_offset(&config.filter_name, ctx, progress_callback).await
                {
                    return InstructionResult::failure(format!(
                        "Focus offset failed for filter \"{}\": {}",
                        config.filter_name, e
                    ));
                }
                if let Some(cb) = progress_callback {
                    cb(100.0, format!("Filter {}", index));
                }
                return InstructionResult::success_with_message(format!(
                    "Changed to filter position: {}",
                    index
                ));
            }
            Err(e) => return InstructionResult::failure(format!("Filter change failed: {}", e)),
        }
    }

    match ctx
        .device_ops
        .filterwheel_set_filter_by_name(&fw_id, &config.filter_name)
        .await
    {
        Ok(pos) => {
            if let Some(cb) = progress_callback {
                cb(30.0, format!("Moving to {}", config.filter_name));
            }
            if let Err(e) = wait_for_filterwheel_idle(&fw_id, pos, ctx, timeout).await {
                return InstructionResult::failure(e);
            }
            if let Err(e) =
                apply_filter_focus_offset(&config.filter_name, ctx, progress_callback).await
            {
                return InstructionResult::failure(format!(
                    "Focus offset failed for filter \"{}\": {}",
                    config.filter_name, e
                ));
            }
            if let Some(cb) = progress_callback {
                cb(100.0, format!("Filter: {}", config.filter_name));
            }
            InstructionResult::success_with_message(format!(
                "Changed to filter: {} (pos {})",
                config.filter_name, pos
            ))
        }
        Err(e) => InstructionResult::failure(format!("Filter change failed: {}", e)),
    }
}

/// Apply the focus offset configured for a given filter after a filter change.
///
/// Looks up the offset in `ctx.filter_focus_offsets` and moves the focuser
/// by that amount relative to its current position. If the offset is zero,
/// no focuser is connected, or no offset is configured, this is a no-op.
/// Errors are logged but do not fail the filter change.
pub(crate) async fn apply_filter_focus_offset(
    filter_name: &str,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> Result<(), String> {
    let focuser_id = match ctx.focuser_id.as_deref() {
        Some(id) if !id.is_empty() => id,
        _ => return Ok(()),
    };

    // Filter focus offsets are stored RELATIVE to the reference filter
    // (offset = optimal_focus[filter] - optimal_focus[reference]); the
    // reference filter and any unconfigured filter have offset 0.
    let offset_new = ctx
        .filter_focus_offsets
        .get(filter_name)
        .copied()
        .unwrap_or(0);

    // The focuser already carries the offset applied for the PREVIOUS filter.
    // Applying `offset_new` as an absolute shift from the current position
    // would stack offsets and walk focus off across an LRGB/SHO night
    // (e.g. L->R = +30, then R->G would land at reference+40 instead of
    // reference+10, and re-selecting a filter would re-add its offset every
    // time). Move by the DELTA between the new offset and the one currently
    // embodied so the focuser always lands at reference_focus + offset_new.
    let last_applied = match &ctx.trigger_state {
        Some(ts) => ts.read().await.last_applied_filter_offset,
        None => 0,
    };
    let delta = offset_new - last_applied;

    if delta == 0 {
        // Already at the correct offset for this filter (re-selecting the same
        // filter, or selecting the reference filter when nothing is applied).
        tracing::debug!(
            "Filter \"{}\": focus offset {} already embodied; no focuser move needed",
            filter_name,
            offset_new
        );
        return Ok(());
    }

    tracing::info!(
        "Applying focus offset for filter \"{}\": embodied {} -> {} ({:+} step delta)",
        filter_name,
        last_applied,
        offset_new,
        delta
    );

    if let Some(cb) = progress_callback {
        cb(60.0, format!("Applying focus offset: {:+} steps", delta));
    }

    let current_pos = match ctx.device_ops.focuser_get_position(focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            return Err(format!("failed to read focuser position: {}", e));
        }
    };

    let target_pos = current_pos + delta;
    tracing::info!(
        "Focus offset: {} + {} = {} (current + delta = target; filter offset {})",
        current_pos,
        delta,
        target_pos,
        offset_new
    );

    if let Err(e) = ctx.device_ops.focuser_move_to(focuser_id, target_pos).await {
        return Err(format!("failed to move focuser: {}", e));
    }

    // 60 polls × 500 ms = 30 s — enough for typical filter-offset moves
    // (which are tens of steps), but short enough that a stuck focuser does
    // not block the next exposure. Real verification of `final_pos ==
    // target_pos` happens after the wait so we catch slow-but-completing
    // moves as well as outright failures.
    let mut reached_target = false;
    for _ in 0..60 {
        sleep(Duration::from_millis(500)).await;
        match ctx.device_ops.focuser_is_moving(focuser_id).await {
            Ok(false) => {
                reached_target = true;
                break;
            }
            Ok(true) => continue,
            Err(e) => {
                return Err(format!("failed while checking focuser movement: {}", e));
            }
        }
    }

    if !reached_target {
        return Err("focuser did not report completion before the timeout window".to_string());
    }

    let final_pos = match ctx.device_ops.focuser_get_position(focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            return Err(format!("failed to verify final focuser position: {}", e));
        }
    };

    if final_pos != target_pos {
        return Err(format!(
            "target focuser position {} but actual position is {}",
            target_pos, final_pos
        ));
    }

    // Record the offset now embodied in the focuser position so the NEXT
    // filter change moves only by the delta (and re-selecting this filter is a
    // no-op). Without this the offsets accumulate across the night.
    if let Some(ts) = &ctx.trigger_state {
        ts.write().await.set_last_applied_filter_offset(offset_new);
    }

    if let Some(cb) = progress_callback {
        cb(
            80.0,
            format!(
                "Focus offset applied: {} -> {} ({:+} steps)",
                current_pos, final_pos, delta
            ),
        );
    }

    tracing::info!(
        "Focus offset for filter \"{}\" applied: {} -> {} (embodied offset now {})",
        filter_name,
        current_pos,
        final_pos,
        offset_new
    );
    Ok(())
}
