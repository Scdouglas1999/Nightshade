//! Trigger system for the sequencer

use crate::{PierSide, RecoveryAction, TriggerType};
use chrono::{NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Trust-patch §6: hard upper bound on the FocusDrift rolling-window length.
/// The window is user-configurable (`TriggerType::FocusDrift::window_size`,
/// `lib.rs:1115`); enforcing a ceiling here keeps the in-memory footprint
/// bounded and prevents a misconfigured sequence from allocating an
/// unbounded ring buffer per trigger evaluation. 100 samples at the typical
/// 1 Hz monitor tick is 100 s of drift history — well past any reasonable
/// focus-drift detection horizon.
pub const FOCUS_DRIFT_WINDOW_MAX: usize = 100;

/// If `trigger_type` is `FocusDrift` and the configured window exceeds
/// `FOCUS_DRIFT_WINDOW_MAX`, clamp it and log a warning. Used by
/// `Trigger::new` so a stored sequence with an oversized window does not
/// allocate without bounds at runtime.
///
/// Wave 1.5 Pack A: returns `(clamped_type, Option<TriggerClampWarning>)` so
/// `Trigger::new` can capture the clamping diagnostic and the executor can
/// later surface it as a user-visible `ExecutorEvent::Error`. Previously the
/// only signal was a `tracing::warn!` which the user never saw.
fn clamp_focus_drift_window(
    trigger_type: TriggerType,
) -> (TriggerType, Option<TriggerClampWarning>) {
    if let TriggerType::FocusDrift {
        window_size,
        min_increasing_count,
        min_total_increase,
    } = &trigger_type
    {
        if *window_size > FOCUS_DRIFT_WINDOW_MAX {
            tracing::warn!(
                "FocusDrift trigger window_size {} exceeds maximum {}; clamping (trust-patch §6). \
                 Reduce window_size in the trigger configuration to silence this warning.",
                window_size,
                FOCUS_DRIFT_WINDOW_MAX
            );
            let warning = TriggerClampWarning {
                field: "FocusDrift.window_size",
                original: *window_size,
                clamped_to: FOCUS_DRIFT_WINDOW_MAX,
            };
            return (
                TriggerType::FocusDrift {
                    window_size: FOCUS_DRIFT_WINDOW_MAX,
                    min_increasing_count: *min_increasing_count,
                    min_total_increase: *min_total_increase,
                },
                Some(warning),
            );
        }
    }
    (trigger_type, None)
}

fn build_utc_naive_time_or_fallback(
    date: NaiveDate,
    hour: u32,
    minute: u32,
    fallback: (u32, u32, u32),
) -> chrono::NaiveDateTime {
    // Why (audit-rust §4.3): same pattern as instructions.rs equivalent — invalid (h,m,s)
    // tuple falls through to the documented `fallback`; if `fallback` itself is invalid,
    // midnight is the safe last-resort representable time for the same calendar date.
    date.and_hms_opt(hour, minute, 0)
        .or_else(|| date.and_hms_opt(fallback.0, fallback.1, fallback.2))
        .unwrap_or_else(|| date.and_time(chrono::NaiveTime::MIN))
}

fn looks_like_tracking_limit_hit(state: &TriggerState) -> bool {
    if !state.mount_tracking_expected || !state.mount_tracking_lost {
        return false;
    }

    if state.mount_status_query_failed {
        tracing::debug!("Tracking lost but status query failed - not a limit hit");
        return false;
    }

    if !matches!(state.mount_is_tracking, Some(false) | None) {
        tracing::debug!(
            "Tracking lost heuristic rejected because tracking state is {:?}",
            state.mount_is_tracking
        );
        return false;
    }

    let not_slewing = matches!(state.mount_slewing, Some(false) | None);
    let not_parked = matches!(state.mount_parked, Some(false) | None);
    if !not_slewing || !not_parked {
        tracing::debug!(
            "Tracking lost but mount is slewing={:?} parked={:?} - not a limit hit",
            state.mount_slewing,
            state.mount_parked
        );
        return false;
    }

    let now = Utc::now().timestamp();
    if let Some(limit_time) = state.mount_tracking_limit_time {
        if limit_time <= now + 60 {
            return !matches!(state.pier_side, Some(PierSide::East));
        }
    }

    let ha = match state.current_hour_angle {
        Some(ha) if ha > 0.0 => ha,
        _ => {
            tracing::debug!(
                "Tracking lost but HA={:?} - not past meridian, not a limit hit",
                state.current_hour_angle
            );
            return false;
        }
    };

    let on_pre_flip_side = match state.pier_side {
        Some(PierSide::West) => true,
        Some(PierSide::East) => false,
        _ => true,
    };

    if !on_pre_flip_side {
        tracing::debug!("Tracking lost but pier side is East - already flipped");
        return false;
    }

    ha > 0.0
}

/// A trigger that monitors conditions and fires when met
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Trigger {
    pub id: String,
    pub name: String,
    pub trigger_type: TriggerType,
    pub recovery_action: RecoveryAction,
    pub enabled: bool,
    #[serde(skip)]
    pub cooldown_secs: Option<u64>,
    #[serde(skip)]
    pub last_triggered: Option<Instant>,
    /// Counter for consecutive frames exceeding HFR threshold.
    /// Only used by HfrDegraded triggers; reset when condition clears.
    #[serde(skip)]
    pub hfr_bad_frame_count: u32,
    /// P1-9: the `TriggerState::hfr_sample_seq` last consumed by this
    /// HfrDegraded trigger. `check()` runs on the ~1Hz monitor tick; gating on
    /// a change here makes `hfr_bad_frame_count` advance once per FRAME instead
    /// of once per tick (which had turned `consecutive_frames` into seconds).
    #[serde(skip, default)]
    pub last_hfr_seq: Option<u64>,
    /// Rolling window of HFR values for FocusDrift detection.
    /// Stores recent HFR measurements to detect monotonic upward trends.
    /// Trust-patch §6: switched from `Vec<f64>` to `VecDeque<f64>` so the
    /// per-tick trim uses O(1) `pop_front` instead of O(n) `remove(0)`. The
    /// window is bounded by `FOCUS_DRIFT_WINDOW_MAX` (enforced at trigger
    /// creation time) so worst-case allocation is fixed.
    #[serde(skip)]
    pub focus_drift_hfr_window: VecDeque<f64>,
    /// Wave 1.5 Pack A: when `Trigger::new` clamped an oversize FocusDrift
    /// `window_size`, the original user-supplied value is captured here so the
    /// executor can emit a user-visible `ExecutorEvent::Error` on start
    /// instead of leaving the clamp silently in the tracing log. `None` means
    /// no clamping occurred.
    #[serde(skip, default)]
    pub clamp_warning: Option<TriggerClampWarning>,
    /// Wave 5 Agent 4: monotonic timestamp at which the `CloudCoverThreshold`
    /// trigger first observed cover above its `max_percent`. Reset to `None`
    /// whenever a sample drops back below the threshold; reused to implement
    /// the user's `duration_secs` debounce. Per-trigger (not on shared
    /// `TriggerState`) so multiple `CloudCoverThreshold` triggers with
    /// different thresholds debounce independently.
    #[serde(skip, default)]
    pub cloud_cover_above_threshold_since: Option<Instant>,
    /// Wave 7 Science: monotonic timestamp at which a
    /// `TransparencyDropped` trigger first observed transparency at or
    /// below its `below_threshold`. Reset to `None` whenever the sample
    /// recovers above the threshold; used to implement the user's
    /// `duration_secs` debounce. Per-trigger so multiple triggers with
    /// different thresholds debounce independently.
    #[serde(skip, default)]
    pub transparency_below_threshold_since: Option<Instant>,
}

/// Wave 1.5 Pack A: trigger-creation-time clamping diagnostic. Built by
/// `Trigger::new` when the user-supplied configuration was reduced to fit a
/// hard upper bound (currently `FOCUS_DRIFT_WINDOW_MAX`). Consumed by the
/// executor's start path so the user sees the clamp in the UI run dashboard.
#[derive(Debug, Clone)]
pub struct TriggerClampWarning {
    pub field: &'static str,
    pub original: usize,
    pub clamped_to: usize,
}

impl Trigger {
    /// Create a new trigger.
    ///
    /// Trust-patch §6: when `trigger_type` is `FocusDrift`, the configured
    /// `window_size` is silently clamped to `FOCUS_DRIFT_WINDOW_MAX`. A
    /// warning is emitted via `tracing::warn!` so a misconfigured sequence
    /// is loudly visible in the logs (CLAUDE.md "errors are a feature").
    /// Callers that want to reject invalid windows up front should use
    /// [`Trigger::new_focus_drift_checked`] instead, which returns an
    /// `Err(String)` for sizes exceeding the cap.
    pub fn new(
        id: impl Into<String>,
        name: impl Into<String>,
        trigger_type: TriggerType,
        recovery_action: RecoveryAction,
    ) -> Self {
        let (trigger_type, clamp_warning) = clamp_focus_drift_window(trigger_type);
        Self {
            id: id.into(),
            name: name.into(),
            trigger_type,
            recovery_action,
            enabled: true,
            cooldown_secs: None,
            last_triggered: None,
            hfr_bad_frame_count: 0,
            last_hfr_seq: None,
            focus_drift_hfr_window: VecDeque::new(),
            clamp_warning,
            cloud_cover_above_threshold_since: None,
            transparency_below_threshold_since: None,
        }
    }

    /// Construct a `FocusDrift` trigger, rejecting `window_size` values
    /// above `FOCUS_DRIFT_WINDOW_MAX` instead of clamping silently. This is
    /// the preferred entry point when loading a user-provided sequence: a
    /// clear error message lets the UI surface the misconfiguration rather
    /// than silently truncating the user's value (CLAUDE.md "errors are a
    /// feature; silent fallbacks hide bugs for months").
    pub fn new_focus_drift_checked(
        id: impl Into<String>,
        name: impl Into<String>,
        window_size: usize,
        min_increasing_count: usize,
        min_total_increase: f64,
        recovery_action: RecoveryAction,
    ) -> Result<Self, String> {
        if window_size > FOCUS_DRIFT_WINDOW_MAX {
            return Err(format!(
                "FocusDrift window_size {} exceeds maximum {} (trust-patch §6). \
                 Reduce window_size in the trigger configuration.",
                window_size, FOCUS_DRIFT_WINDOW_MAX
            ));
        }
        Ok(Self::new(
            id,
            name,
            TriggerType::FocusDrift {
                window_size,
                min_increasing_count,
                min_total_increase,
            },
            recovery_action,
        ))
    }

    /// Set cooldown duration
    pub fn with_cooldown(mut self, secs: u64) -> Self {
        self.cooldown_secs = Some(secs);
        self
    }

    /// Check if the trigger is in cooldown
    pub fn is_in_cooldown(&self) -> bool {
        if let (Some(cooldown), Some(last)) = (self.cooldown_secs, self.last_triggered) {
            last.elapsed() < Duration::from_secs(cooldown)
        } else {
            false
        }
    }

    /// Check if the trigger condition is met
    pub async fn check(&mut self, state: &TriggerState) -> bool {
        if !self.enabled || self.is_in_cooldown() {
            return false;
        }

        let triggered = match &self.trigger_type {
            TriggerType::HfrDegraded {
                threshold_percent,
                absolute_threshold,
                consecutive_frames,
            } => {
                if state.autofocus_invalidated {
                    tracing::info!(
                        "HFR trigger forcing autofocus because autofocus state was invalidated: {:?}",
                        state.autofocus_invalidation_reason
                    );
                    self.hfr_bad_frame_count = (*consecutive_frames).max(1);
                    true
                } else {
                    let current = match state.current_hfr {
                        Some(v) => v,
                        None => return false,
                    };

                    let required = (*consecutive_frames).max(1);
                    // P1-9: only advance the consecutive-bad-frame counter when
                    // a NEW frame has been graded. check() runs on the ~1Hz
                    // monitor tick, so counting per tick made `consecutive_frames`
                    // mean "seconds" — the trigger fired partway through a SINGLE
                    // bad sub. Gate on the per-frame HFR sample sequence; on a
                    // stale tick return the latched decision unchanged.
                    if self.last_hfr_seq == Some(state.hfr_sample_seq) {
                        return self.hfr_bad_frame_count >= required;
                    }
                    self.last_hfr_seq = Some(state.hfr_sample_seq);

                    // A threshold of 0.0 means "this branch is disabled" — both
                    // modes share the trigger and either alone can fire. Users
                    // typically pick one; the OR below makes the choice
                    // declarative rather than requiring a separate "mode" enum.
                    let exceeds_absolute =
                        *absolute_threshold > 0.0 && current > *absolute_threshold;

                    let exceeds_relative = if *threshold_percent > 0.0 {
                        if let Some(baseline) = state.baseline_hfr {
                            if baseline > 0.0 {
                                let increase = (current - baseline) / baseline * 100.0;
                                increase > *threshold_percent
                            } else {
                                false
                            }
                        } else {
                            false
                        }
                    } else {
                        false
                    };

                    let is_bad = exceeds_absolute || exceeds_relative;

                    // A single bad frame is usually a seeing spike, not a real
                    // focus problem. consecutive_frames is the user's tolerance
                    // for how many bad frames in a row count as a real
                    // degradation worth interrupting the sequence over.
                    if is_bad {
                        self.hfr_bad_frame_count += 1;
                    } else {
                        self.hfr_bad_frame_count = 0;
                    }

                    self.hfr_bad_frame_count >= required
                }
            }
            TriggerType::MeridianFlip { config } => {
                // Audit §1.3 / §1.9: once flipped for a target, the same trigger
                // must not fire again until the target changes. Without this
                // guard, the post-flip pier-side reading could ping-pong and
                // request a second flip in the opposite direction.
                if state.has_flipped_this_target {
                    return false;
                }

                match config.trigger_method {
                    crate::MeridianTriggerMethod::MinutesPastMeridian => {
                        if let Some(ha) = state.current_hour_angle {
                            let minutes_past = ha * 60.0;
                            // Pier-side guards a degenerate post-flip case: once
                            // we are on the post-flip side, HA is still positive
                            // but a second flip would be wrong. Unknown is
                            // permissive (legacy mounts that don't report pier
                            // side); a positive HA there still implies we are
                            // past meridian and should flip.
                            let on_pre_flip_side = match state.pier_side {
                                Some(PierSide::West) => ha > 0.0,
                                Some(PierSide::East) => false,
                                _ => ha > 0.0,
                            };
                            on_pre_flip_side && minutes_past >= config.minutes_past_meridian
                        } else {
                            false
                        }
                    }
                    crate::MeridianTriggerMethod::MinutesBeforeLimit => {
                        // Requires the mount to advertise a real tracking-limit
                        // time. We deliberately do NOT fall back to estimating
                        // from HA: that estimate would be the user's previous
                        // mode (HourAngleThreshold), and silently switching
                        // modes hides misconfiguration.
                        if let Some(limit_time) = state.mount_tracking_limit_time {
                            let now = chrono::Utc::now().timestamp();
                            // Why: i64 timestamp difference -> f64; durations under
                            // ~285k years fit in f64 mantissa.
                            let minutes_to_limit = (limit_time - now) as f64 / 60.0;
                            minutes_to_limit > 0.0
                                && minutes_to_limit <= config.minutes_before_limit
                        } else {
                            false
                        }
                    }
                    crate::MeridianTriggerMethod::HourAngleThreshold => {
                        if let Some(ha) = state.current_hour_angle {
                            let on_pre_flip_side = match state.pier_side {
                                Some(PierSide::West) => ha > 0.0,
                                Some(PierSide::East) => false,
                                _ => ha > 0.0,
                            };
                            on_pre_flip_side && ha >= config.hour_angle_threshold
                        } else {
                            false
                        }
                    }
                    crate::MeridianTriggerMethod::OnTrackingLimitHit => {
                        if !looks_like_tracking_limit_hit(state) {
                            return false;
                        }

                        // The wait period lets users absorb a brief tracking
                        // glitch (e.g. EQ8 self-recovering from a brief stall)
                        // without forcing a flip; zero means "flip immediately".
                        if config.tracking_limit_wait_minutes > 0.0 {
                            if let Some(detected_at) = state.tracking_limit_detected_at {
                                let elapsed_secs = chrono::Utc::now().timestamp() - detected_at;
                                // Why: tracking_limit_wait_minutes is f64 user-config
                                // (UI-bounded, typically 0..30). f64 -> i64 saturates
                                // per Rust 1.45 spec; negatives clamp to 0 which is
                                // the "no wait, flip immediately" semantics.
                                let wait_secs = (config.tracking_limit_wait_minutes * 60.0) as i64;
                                if elapsed_secs < wait_secs {
                                    // Why §1.21: emit "n/a" when HA is unmeasured so the log
                                    // never advertises the 0.0 sentinel as if it were real data.
                                    tracing::trace!(
                                        "Tracking limit hit: waiting {}/{}s before flip (HA={}h)",
                                        elapsed_secs,
                                        wait_secs,
                                        state
                                            .current_hour_angle
                                            .map(|v| format!("{:.2}", v))
                                            // Why (audit-rust §4.3, §1.21): hour-angle is
                                            // Option<f64>; None means the mount has not yet
                                            // reported coordinates. "n/a" is the documented
                                            // diagnostic substitute (never 0.0, which would
                                            // mask missing data).
                                            .unwrap_or_else(|| "n/a".into())
                                    );
                                    return false;
                                }
                                // Why §1.21: see HA formatting note above — preserve "n/a"
                                // distinction at info level too.
                                tracing::info!(
                                    "Tracking limit wait elapsed ({:.1} min), triggering meridian flip (HA={}h)",
                                    config.tracking_limit_wait_minutes,
                                    state
                                        .current_hour_angle
                                        .map(|v| format!("{:.2}", v))
                                        // Why (audit-rust §4.3, §1.21): see equivalent above.
                                        .unwrap_or_else(|| "n/a".into())
                                );
                            } else {
                                // No timestamp yet - wait for executor to record it on next poll
                                return false;
                            }
                        } else {
                            // Why §1.21: HA may be `None` if the mount has not yet reported
                            // coordinates this poll cycle — log "n/a" rather than masking
                            // missing data as 0.0.
                            tracing::info!(
                                "Tracking limit hit detected, triggering immediate meridian flip (HA={}h, pier={:?})",
                                state
                                    .current_hour_angle
                                    .map(|v| format!("{:.2}", v))
                                    // Why (audit-rust §4.3, §1.21): see equivalent above.
                                    .unwrap_or_else(|| "n/a".into()),
                                state.pier_side
                            );
                        }

                        true
                    }
                }
            }
            TriggerType::GuidingFailed {
                rms_threshold,
                duration_secs,
                rms_retention_secs: _,
            } => {
                // Audit §1.21: the configured retention is propagated to
                // the trigger state by `TriggerManager::sync_state_from_config`
                // (called after every config edit and on standard-trigger
                // construction). Reading state here is sufficient — the
                // history has already been trimmed by `update_guiding_rms`
                // using the propagated retention.
                if let Some(rms_history) = &state.guiding_rms_history {
                    // "All samples within `duration_secs` above threshold"
                    // means a sustained guiding failure, not a transient spike
                    // (which `consecutive_frames` handles for HFR). One good
                    // sample inside the window resets the trigger.
                    let recent: Vec<_> = rms_history
                        .iter()
                        .filter(|(time, _)| time.elapsed().as_secs_f64() < *duration_secs)
                        .collect();

                    if recent.is_empty() {
                        false
                    } else {
                        recent.iter().all(|(_, rms)| *rms > *rms_threshold)
                    }
                } else {
                    false
                }
            }
            TriggerType::AltitudeLimit { min_altitude } => {
                if let Some(alt) = state.current_altitude {
                    alt < *min_altitude
                } else {
                    false
                }
            }
            TriggerType::WeatherUnsafe => {
                // Defense-in-depth (full-night audit 2026-06-04): the in-sequencer
                // WeatherUnsafe trigger must abort when EITHER the hardware safety
                // monitor reports unsafe OR the Dart-side weather-safety verdict
                // (configured thresholds + API/cloud sources) computed unsafe. A
                // rig with no hardware safety device leaves `weather_safe` at its
                // `false`-by-default/last-poll value; the verdict is the path that
                // makes the trigger react to non-hardware weather conditions. This
                // is OR-of-unsafe (never less safe than the hardware verdict) — an
                // abstaining verdict (`None`) or a `Some(false)` SAFE verdict never
                // suppresses a hardware-unsafe reading.
                !state.weather_safe || state.weather_verdict_unsafe == Some(true)
            }
            TriggerType::TemperatureShift { degrees } => {
                if let (Some(baseline), Some(current)) =
                    (state.baseline_temperature, state.current_temperature)
                {
                    (current - baseline).abs() > *degrees
                } else {
                    false
                }
            }
            TriggerType::FilterChange => state.filter_changed,
            TriggerType::DawnApproaching { minutes_before } => {
                // `dawn_time` is seeded by the executor when observer location
                // becomes available; absent it we cannot evaluate without
                // forcing a recompute on every poll.
                if let Some(dawn_time) = state.dawn_time {
                    let now = chrono::Utc::now().timestamp();
                    // Why: i64 timestamp difference -> f64 lossless for any
                    // single-night duration.
                    let time_to_dawn = (dawn_time - now) as f64 / 60.0;
                    // Positive `time_to_dawn` excludes the case where dawn has
                    // already passed (negative value); without it the trigger
                    // would fire continuously through the daylight hours.
                    time_to_dawn > 0.0 && time_to_dawn <= *minutes_before
                } else {
                    false
                }
            }
            TriggerType::AutofocusInterval { every_n_frames } => {
                if state.completed_exposures == 0 || *every_n_frames == 0 {
                    false
                } else {
                    let frames_since_af = state
                        .completed_exposures
                        .saturating_sub(state.last_autofocus_frame);
                    frames_since_af >= *every_n_frames
                }
            }
            TriggerType::DitherInterval { every_n_frames } => {
                if state.completed_exposures == 0 || *every_n_frames == 0 {
                    false
                } else {
                    let frames_since_dither = state
                        .completed_exposures
                        .saturating_sub(state.last_dither_frame);
                    frames_since_dither >= *every_n_frames
                }
            }
            TriggerType::MountTrackingLost => {
                if !state.mount_tracking_expected || !state.mount_tracking_lost {
                    return false;
                }

                // Tracking-limit hits also raise mount_tracking_lost, but the
                // user wants those to drive a meridian flip, not a Pause. We
                // suppress MountTrackingLost when the limit-hit heuristic
                // matches so MeridianFlip(OnTrackingLimitHit) wins the dispatch.
                if matches!(
                    state.meridian_trigger_method,
                    Some(crate::MeridianTriggerMethod::OnTrackingLimitHit)
                ) {
                    let looks_like_limit_hit = looks_like_tracking_limit_hit(state);

                    if looks_like_limit_hit {
                        tracing::debug!(
                            "Tracking lost but matches limit-hit heuristic - deferring to MeridianFlip trigger"
                        );
                        return false;
                    }
                }

                true
            }
            TriggerType::DomeShutterNotOpen => {
                state.dome_shutter_open_expected
                    && match state.dome_shutter_status.as_deref() {
                        Some("Open") => false,
                        Some(_) => true,
                        None => true, // Unknown shutter state is treated unsafe (fail-closed).
                    }
            }
            TriggerType::GuideStarLost => {
                // `guiding_enabled` gate prevents the trigger from firing while
                // the guider is idle between sequences (e.g. during slews or
                // before a StartGuiding node has run).
                state.guiding_enabled && state.guide_star_lost
            }
            TriggerType::FocusDrift {
                window_size,
                min_increasing_count,
                min_total_increase,
            } => {
                let current = match state.current_hfr {
                    Some(v) => v,
                    None => return false,
                };

                // Trust-patch §6: O(1) push to the back of the VecDeque
                // (previously O(n) `Vec::remove(0)` for the head-drop in the
                // trim loop below).
                self.focus_drift_hfr_window.push_back(current);

                // `.max(2)` guards against a misconfigured window of 0 or 1 —
                // a single sample cannot show a trend, so the math below would
                // panic on the run-start subtraction. The window is further
                // clamped to FOCUS_DRIFT_WINDOW_MAX at trigger construction
                // time, so the allocation here is bounded.
                let max_size = (*window_size).clamp(2, FOCUS_DRIFT_WINDOW_MAX);
                while self.focus_drift_hfr_window.len() > max_size {
                    // Trust-patch §6: O(1) head-drop replaces the
                    // O(n) `Vec::remove(0)` shift.
                    self.focus_drift_hfr_window.pop_front();
                }

                let min_count = (*min_increasing_count).max(2);
                if self.focus_drift_hfr_window.len() < min_count {
                    return false;
                }

                // Walking from the tail forward captures the *current* trend
                // (focus drift is by definition ongoing, not historical) and
                // ignores earlier wobbles that might otherwise dilute the run.
                let window = &self.focus_drift_hfr_window;
                let mut increasing_run = 1usize;
                for i in (1..window.len()).rev() {
                    if window[i] > window[i - 1] {
                        increasing_run += 1;
                    } else {
                        break;
                    }
                }

                if increasing_run < min_count {
                    return false;
                }

                // The total-rise threshold defends against creeping near-zero
                // increases that satisfy "monotonic" but are within noise:
                // 0.01 px/frame over 5 frames is not a drift, it is jitter.
                let run_start = window.len() - increasing_run;
                // Why (audit-rust §4.3): `back()` returns None only if the
                // deque is empty, but the `len() < min_count` early return
                // above guarantees at least `min_count >= 2` samples are
                // present here. The unwrap documents that invariant.
                let total_increase =
                    window.back().expect("non-empty window invariant") - window[run_start];
                total_increase >= *min_total_increase
            }
            TriggerType::HumidityThreshold { max_percent } => {
                match state.current_humidity {
                    Some(humidity) => humidity > *max_percent,
                    None => false, // No humidity data - can't trigger
                }
            }
            TriggerType::DriftLimit { max_pixels } => {
                // Audit §1.11: fire when accumulated plate-solve drift exceeds
                // the configured pixel budget. The state holds the most recent
                // plate-solve coordinates and pixel scale; absent any of them
                // we cannot evaluate drift and the trigger stays inactive.
                let Some((ra_px, dec_px)) = state.calculate_drift_pixels() else {
                    return false;
                };
                // Combine in quadrature so a small drift on one axis cannot
                // mask a large drift on the other. `calculate_drift_pixels`
                // already returns absolute values.
                let drift = (ra_px * ra_px + dec_px * dec_px).sqrt();
                drift > *max_pixels
            }
            TriggerType::CloudArrivingIn {
                minutes_before,
                coverage_threshold,
            } => {
                // Wave 5 Agent 4: fire when (a) the analyzer says clouds
                // arrive within `minutes_before` minutes AND (b) the
                // predicted coverage exceeds `coverage_threshold`. The two
                // gates together prevent firing for a passing wisp.
                //
                // Coverage threshold reads `current_cloud_coverage_percent`
                // — this is the analyzer's best-known coverage at the
                // (predicted) arrival time. Using a separate "predicted
                // coverage" field would be more accurate but the analyzer
                // does not yet model that; treating the current value as
                // the prediction is the documented behaviour until the
                // analyzer exposes a forecast curve.
                let Some(arrival) = state.predicted_cloud_arrival_minutes else {
                    return false;
                };
                let Some(coverage) = state.current_cloud_coverage_percent else {
                    return false;
                };
                arrival <= *minutes_before && coverage > *coverage_threshold
            }
            TriggerType::CloudOpeningIn {
                minutes_before,
                minimum_duration_secs,
            } => {
                // Wave 5 Agent 4: fire when the analyzer predicts a clear
                // opening within `minutes_before` minutes AND the opening's
                // duration is at least `minimum_duration_secs`. Used by
                // `RecoveryAction::PauseAndWaitForClear` to auto-resume.
                let Some(opening) = state.predicted_cloud_opening_minutes else {
                    return false;
                };
                if opening > *minutes_before {
                    return false;
                }
                // A missing duration is treated as "unknown" rather than
                // "any" — firing on an unknown-length opening would lead
                // the recovery layer to slew into a hole that closes
                // before settle. CLAUDE.md "errors are a feature": no
                // duration => don't fire.
                let Some(duration) = state.predicted_cloud_opening_duration_secs else {
                    return false;
                };
                duration >= *minimum_duration_secs
            }
            TriggerType::CloudCoverThreshold {
                max_percent,
                duration_secs,
            } => {
                // Wave 5 Agent 4: fire when the current cloud cover has been
                // above `max_percent` for at least `duration_secs` consecutive
                // seconds. The debounce is implemented via the per-trigger
                // `cloud_cover_above_threshold_since` timestamp so multiple
                // CloudCoverThreshold triggers with different thresholds
                // (e.g. 50% warn / 80% park) debounce independently.
                let Some(coverage) = state.current_cloud_coverage_percent else {
                    // No data => reset our debounce timer so a stale arming
                    // from a previous reading does not fire.
                    self.cloud_cover_above_threshold_since = None;
                    return false;
                };
                if coverage <= *max_percent {
                    self.cloud_cover_above_threshold_since = None;
                    return false;
                }
                // We are above threshold. Arm the debounce timer on the
                // first crossing and check elapsed on subsequent samples.
                let since = *self
                    .cloud_cover_above_threshold_since
                    .get_or_insert_with(Instant::now);
                since.elapsed().as_secs_f64() >= *duration_secs
            }
            TriggerType::TransparencyDropped {
                below_threshold,
                duration_secs,
            } => {
                // Wave 7 Science: fire when the live transparency reading
                // has been at or below `below_threshold` for at least
                // `duration_secs` consecutive seconds. Same debounce
                // pattern as `CloudCoverThreshold` so multiple triggers
                // (e.g. 0.7 warn / 0.4 swap) debounce independently.
                let Some(transparency) = state.current_transparency else {
                    // No data => reset our debounce timer so a stale
                    // arming from a previous reading does not fire.
                    self.transparency_below_threshold_since = None;
                    return false;
                };
                if transparency > *below_threshold {
                    self.transparency_below_threshold_since = None;
                    return false;
                }
                let since = *self
                    .transparency_below_threshold_since
                    .get_or_insert_with(Instant::now);
                since.elapsed().as_secs_f64() >= *duration_secs
            }
        };

        if triggered {
            self.last_triggered = Some(Instant::now());
        }

        triggered
    }
}

/// Calculate dawn (morning astronomical twilight) time for a given location
/// Returns Unix timestamp of next dawn
pub fn calculate_dawn_time(latitude: f64, longitude: f64) -> i64 {
    use chrono::Datelike;

    let now = Utc::now();
    let today = now.date_naive();

    // Sun altitude threshold for astronomical twilight (18 degrees below horizon)
    let altitude_threshold: f64 = -18.0;

    // Approximate solar declination using Cooper's equation
    // Why: ordinal() returns u32 day-of-year (1..=366); trivially lossless to f64.
    let day_of_year = f64::from(today.ordinal());
    let declination: f64 = 23.45
        * (360.0_f64 * (284.0 + day_of_year) / 365.0)
            .to_radians()
            .sin();
    let dec_rad = declination.to_radians();
    let lat_rad = latitude.to_radians();
    let alt_rad = altitude_threshold.to_radians();

    // Calculate hour angle at astronomical twilight
    let cos_h = (alt_rad.sin() - lat_rad.sin() * dec_rad.sin()) / (lat_rad.cos() * dec_rad.cos());

    // Handle polar day/night explicitly to avoid silently fabricating a time.
    if cos_h > 1.0 {
        // Sun never reaches this altitude threshold today (e.g., polar day).
        // Return a far-future timestamp so dawn trigger remains inactive.
        return i64::MAX;
    }
    if cos_h < -1.0 {
        // Sun is always below this altitude threshold today (e.g., polar night).
        // Dawn is effectively "already reached" for scheduling logic.
        return now.timestamp();
    }

    let hour_angle = cos_h.acos().to_degrees();

    // Solar noon in UTC (approximately 12:00 - longitude/15 hours)
    let solar_noon_utc = 12.0 - longitude / 15.0;

    // Morning twilight occurs before solar noon
    let hours_before_noon = hour_angle / 15.0;
    let dawn_hour_utc = solar_noon_utc - hours_before_noon;

    // Normalize to 0-24 range
    let dawn_hour = dawn_hour_utc.rem_euclid(24.0);
    // Why: dawn_hour is bounded by rem_euclid(24.0) above; .fract()*60.0 is in
    // [0, 60). f64 -> u32 saturates per Rust 1.45 spec.
    let dawn_minutes = (dawn_hour.fract() * 60.0) as u32;
    let dawn_hour = dawn_hour as u32;

    let dawn_datetime = build_utc_naive_time_or_fallback(today, dawn_hour, dawn_minutes, (6, 0, 0));

    let dawn_timestamp =
        chrono::DateTime::<Utc>::from_naive_utc_and_offset(dawn_datetime, Utc).timestamp();

    // If the calculated dawn is in the past, it's tomorrow's dawn
    if dawn_timestamp < now.timestamp() {
        dawn_timestamp + 86400 // Add 24 hours
    } else {
        dawn_timestamp
    }
}

/// State information used by triggers
#[derive(Debug, Clone)]
pub struct TriggerState {
    // HFR tracking
    pub baseline_hfr: Option<f64>,
    pub current_hfr: Option<f64>,
    /// P1-9: monotonically increments each time a NEW frame's HFR is recorded
    /// via `update_hfr`. The HfrDegraded trigger gates its consecutive-bad-frame
    /// counter on a change here so it counts frames, not ~1Hz monitor ticks.
    pub hfr_sample_seq: u64,
    pub autofocus_invalidated: bool,
    pub autofocus_invalidation_reason: Option<String>,

    // Meridian flip - enhanced fields
    /// Current hour angle of the target in hours (negative = east, positive = west of meridian)
    pub current_hour_angle: Option<f64>,
    /// Current pier side of the mount
    pub pier_side: Option<PierSide>,
    /// Unix timestamp when mount will hit its tracking limit (if reported by mount)
    pub mount_tracking_limit_time: Option<i64>,
    /// Whether we've already flipped for the current target (prevents double-flip)
    pub has_flipped_this_target: bool,
    /// Target name for the current meridian flip tracking
    pub current_target_name: Option<String>,
    /// Legacy field - Unix timestamp for flip (deprecated, use current_hour_angle instead)
    pub next_meridian_flip_time: Option<i64>,
    /// Threshold (minutes past meridian) of the active MinutesPastMeridian
    /// flip trigger, propagated by [`TriggerManager::sync_state_from_config`]
    /// on every evaluation tick. The exposure instruction's pre-frame
    /// meridian gate reads this to hold frames that would still be exposing
    /// when the flip fires. None when no MinutesPastMeridian flip trigger
    /// is enabled (other trigger methods are not predictable in advance).
    pub meridian_flip_minutes_past: Option<f64>,

    // Guiding
    pub guiding_rms_history: Option<Vec<(Instant, f64)>>,
    pub guiding_enabled: bool,
    /// Whether the guide star has been lost (guider reports no star / lost lock)
    pub guide_star_lost: bool,
    /// Filter focus offset (steps) currently embodied in the focuser position,
    /// relative to the reference filter. Filter offsets are reference-relative
    /// deltas; a filter change moves the focuser by
    /// `(offset_new - last_applied_filter_offset)` so offsets do not stack and
    /// walk focus off across an LRGB/SHO night. `0` means the focuser is at the
    /// reference-filter focus (the initial state and after selecting the
    /// reference filter).
    pub last_applied_filter_offset: i32,
    /// Audit §1.21: configurable retention window (seconds) for
    /// `guiding_rms_history`. Set by the trigger evaluator from the
    /// `GuidingFailed` trigger configuration so a user-tuned value is
    /// honoured. Defaults to 300s (5 minutes), matching the previous
    /// hardcoded behaviour.
    pub guiding_rms_retention_secs: u64,
    /// Audit §1.9: pier side recorded at the moment a flip was marked
    /// performed, so a subsequent observable return to that side can clear
    /// `has_flipped_this_target`. `None` means no flip has been recorded yet
    /// for the current target.
    pub flip_origin_pier_side: Option<PierSide>,

    // Humidity
    /// Current humidity percentage (0-100)
    pub current_humidity: Option<f64>,

    // Altitude
    pub current_altitude: Option<f64>,

    // Weather
    /// Hardware safety-monitor verdict: `true` when the connected safety/weather
    /// device reports safe (or, under `WarnOnly`, the last good reading). Fed by
    /// the executor's safety poll (`executor/mod.rs` `safety_is_safe`).
    pub weather_safe: bool,
    /// Defense-in-depth: the Dart-side `weatherSafetyProvider` overall verdict,
    /// composed from the user's configured thresholds + API/cloud sources (which
    /// the hardware `weather_safe` poll knows nothing about). `Some(true)` means
    /// the Dart side computed UNSAFE; `Some(false)` means it computed SAFE;
    /// `None` means the Dart side has not reported (e.g. provider disabled / no
    /// data) and this layer abstains. Folded into the `WeatherUnsafe` trigger as
    /// an ADDITIONAL unsafe source — it can only make the rig safer, never less
    /// safe than the hardware verdict (CLAUDE.md "fail closed"). Pushed via
    /// `ExecutorCommand::UpdateWeatherVerdict`.
    pub weather_verdict_unsafe: Option<bool>,
    /// Architecture-unification 2026-06-05 (Subsystem 2 step 3 — stale-verdict
    /// observability): the monotonic timestamp of the most recent
    /// `update_weather_verdict` push. `None` until the Dart side has pushed at
    /// least once.
    ///
    /// A pushed `Some(true)` (UNSAFE) verdict is FAIL-CLOSED: if the Dart feed
    /// then goes silent, the verdict is deliberately NOT auto-cleared — holding
    /// the sequence paused is the correct safe behaviour. But an INDEFINITE hold
    /// must never be SILENT. The safety poll loop uses this timestamp to detect
    /// a stale-AND-unsafe verdict and emit a loud warning event so the operator
    /// knows the hold is being sustained by a dead feed rather than fresh data.
    /// It is NEVER used to resume — staleness only adds observability, never
    /// anti-safety auto-resume.
    pub weather_verdict_last_update: Option<Instant>,

    // Temperature
    pub baseline_temperature: Option<f64>,
    pub current_temperature: Option<f64>,
    pub baseline_focuser_position: Option<i32>,

    // Filter
    pub filter_changed: bool,
    pub current_filter: Option<String>,

    // Dawn (astronomical twilight timestamp)
    pub dawn_time: Option<i64>,
    pub observer_latitude: Option<f64>,
    pub observer_longitude: Option<f64>,

    /// Architecture-unification 2026-06-07 (W1 native daylight gate): the
    /// maximum Sun altitude (degrees above the horizon) at which an on-sky
    /// LIGHT capture is allowed. Seeded by the executor from
    /// `RuntimeConfig::max_sun_altitude_degrees` so the structural native
    /// daylight START gate in `instructions::execute_slew` / `execute_exposure`
    /// can read the configured threshold through the shared trigger state.
    ///
    /// Remediation 2026-06-09 (finding #2): the Dart side now genuinely pushes
    /// its `SchedulerConfig.maxSunAltitudeDegrees` here via
    /// `SequenceExecutor::update_max_sun_altitude`
    /// ([`crate::executor::ExecutorCommand::UpdateMaxSunAltitude`]), so this
    /// value really does mirror the Dart scheduler's threshold. `None` until
    /// seeded; the gate then falls back to
    /// [`crate::instructions::DEFAULT_MAX_SUN_ALTITUDE_DEGREES`] (-12°, the Dart
    /// default), so even an un-pushed gate is no weaker than the Dart W1 gate.
    /// This value is NOT itself a trigger — it carries config to the
    /// instruction-layer gate.
    pub max_sun_altitude_degrees: Option<f64>,

    // Frame counting for periodic triggers
    pub completed_exposures: u32,
    pub last_autofocus_frame: u32,
    pub last_dither_frame: u32,

    // Plate solve tracking for drift detection
    pub last_plate_solve_ra: Option<f64>,  // RA in degrees
    pub last_plate_solve_dec: Option<f64>, // Dec in degrees
    pub last_plate_solve_pixel_scale: Option<f64>, // arcsec per pixel
    pub target_ra: Option<f64>,            // Target RA in degrees
    pub target_dec: Option<f64>,           // Target Dec in degrees

    // Mount tracking
    pub mount_is_tracking: Option<bool>,
    pub mount_tracking_expected: bool,
    pub mount_tracking_lost: bool,
    /// Whether the mount is currently slewing (from status polling)
    pub mount_slewing: Option<bool>,
    /// Whether the mount is currently parked (from status polling)
    pub mount_parked: Option<bool>,
    /// Set to true when the most recent mount status query failed (connection lost / error).
    /// Defaults to false (no failure). The tracking-limit heuristic requires this to be false.
    pub mount_status_query_failed: bool,
    /// Unix timestamp when tracking limit was first detected (for wait-before-flip)
    pub tracking_limit_detected_at: Option<i64>,
    /// The active meridian trigger method (so MountTrackingLost can defer to OnTrackingLimitHit)
    pub meridian_trigger_method: Option<crate::MeridianTriggerMethod>,

    // Dome status
    pub dome_shutter_status: Option<String>,
    pub dome_shutter_open_expected: bool,

    // Grid dither tracking
    /// Current position index in the NxN grid dither pattern (0-based).
    /// Incremented after each dither, wraps around to 0 after grid_size*grid_size.
    pub grid_dither_index: u32,

    // ---------------------------------------------------------------------
    // Wave 5 Agent 4 — Cloud-motion telemetry.
    //
    // Fed by `ExecutorCommand::UpdateCloudMotion` which the Dart side
    // pushes from the live `cloudMotionAnalyzerProvider` (currently every
    // 60 seconds). All fields are `Option` because the analyzer may not
    // yet have enough radar history; an absent field disables the
    // corresponding trigger evaluation rather than firing spuriously.
    // ---------------------------------------------------------------------
    /// Current cloud coverage percentage (0-100). Source: Dart
    /// `cloudCoverPercentageProvider` (Open-Meteo) merged with analyzer.
    pub current_cloud_coverage_percent: Option<f64>,
    /// Predicted minutes until significant clouds reach the user location.
    /// `Some(n)` when the analyzer reports an approaching cloud bank;
    /// `None` when clouds are absent, stationary, or moving away.
    pub predicted_cloud_arrival_minutes: Option<f64>,
    /// Predicted minutes until a clear opening (gap in the cloud field)
    /// reaches the user. `Some(n)` while currently overcast and a hole
    /// is approaching; `None` when no opening is predicted.
    pub predicted_cloud_opening_minutes: Option<f64>,
    /// Predicted opening duration in seconds. Pairs with
    /// `predicted_cloud_opening_minutes`; the `CloudOpeningIn` trigger
    /// rejects openings shorter than the user's `minimum_duration_secs`.
    pub predicted_cloud_opening_duration_secs: Option<f64>,
    /// (alt, az) of a clear-sky direction reported by the analyzer. Used
    /// by `RecoveryAction::SlewToGapAndContinue` to choose where to
    /// re-point. `None` => no usable gap; the recovery action falls
    /// back to `PauseAndWaitForClear`.
    pub predicted_clear_sky_direction: Option<(f64, f64)>,
    /// Most recent timestamp at which we received a cloud-motion update.
    /// Surfaced to the run dashboard so the operator can tell whether the
    /// telemetry is fresh; also used by validation to flag stale data.
    pub cloud_motion_last_update: Option<Instant>,

    // ---------------------------------------------------------------------
    // Wave 7 Science — Sky transparency telemetry.
    //
    // Fed by `ExecutorCommand::UpdateTransparency` which the Dart science
    // pipeline pushes whenever the transparency sampler produces a new
    // reading. `None` until the science pipeline has a first sample;
    // `Some(fraction)` carries the live 0.0..=1.0 transparency reading.
    // ---------------------------------------------------------------------
    /// Live transparency reading (0.0..=1.0; 1.0 = clear). Consumed by
    /// `TransparencyDropped`.
    pub current_transparency: Option<f64>,
    /// Most recent timestamp at which we received a transparency update.
    /// Surfaced to the run dashboard for staleness checks.
    pub transparency_last_update: Option<Instant>,
}

impl Default for TriggerState {
    fn default() -> Self {
        Self {
            baseline_hfr: None,
            current_hfr: None,
            hfr_sample_seq: 0,
            autofocus_invalidated: false,
            autofocus_invalidation_reason: None,
            current_hour_angle: None,
            pier_side: None,
            mount_tracking_limit_time: None,
            has_flipped_this_target: false,
            current_target_name: None,
            next_meridian_flip_time: None,
            meridian_flip_minutes_past: None,
            guiding_rms_history: None,
            guiding_enabled: false,
            guide_star_lost: false,
            last_applied_filter_offset: 0,
            // Audit §1.21: 300s preserves the previous hardcoded retention so
            // un-configured triggers behave exactly as before.
            guiding_rms_retention_secs: 300,
            flip_origin_pier_side: None,
            current_humidity: None,
            current_altitude: None,
            weather_safe: false,
            weather_verdict_unsafe: None,
            weather_verdict_last_update: None,
            baseline_temperature: None,
            current_temperature: None,
            baseline_focuser_position: None,
            filter_changed: false,
            current_filter: None,
            dawn_time: None,
            observer_latitude: None,
            observer_longitude: None,
            // W1 native daylight gate — None until the executor seeds it from
            // RuntimeConfig; the instruction-layer gate falls back to the
            // default constant when unset.
            max_sun_altitude_degrees: None,
            completed_exposures: 0,
            last_autofocus_frame: 0,
            last_dither_frame: 0,
            last_plate_solve_ra: None,
            last_plate_solve_dec: None,
            last_plate_solve_pixel_scale: None,
            target_ra: None,
            target_dec: None,
            mount_is_tracking: None,
            mount_tracking_expected: false,
            mount_tracking_lost: false,
            mount_slewing: None,
            mount_parked: None,
            mount_status_query_failed: false,
            tracking_limit_detected_at: None,
            meridian_trigger_method: None,
            dome_shutter_status: None,
            dome_shutter_open_expected: false,
            grid_dither_index: 0,
            // Wave 5 Agent 4 — cloud-motion telemetry. All None until Dart
            // pushes the first `UpdateCloudMotion`.
            current_cloud_coverage_percent: None,
            predicted_cloud_arrival_minutes: None,
            predicted_cloud_opening_minutes: None,
            predicted_cloud_opening_duration_secs: None,
            predicted_clear_sky_direction: None,
            cloud_motion_last_update: None,
            // Wave 7 Science — transparency telemetry. Both None until the
            // Dart science pipeline pushes the first `UpdateTransparency`.
            current_transparency: None,
            transparency_last_update: None,
        }
    }
}

impl TriggerState {
    pub fn new() -> Self {
        Self {
            weather_safe: false,
            guiding_enabled: false,
            ..Default::default()
        }
    }

    pub fn update_hfr(&mut self, hfr: f64) {
        if self.baseline_hfr.is_none() {
            self.baseline_hfr = Some(hfr);
        }
        self.current_hfr = Some(hfr);
        // P1-9: mark this as a new HFR sample so the HfrDegraded trigger counts
        // it once (per frame) rather than once per ~1Hz evaluation tick.
        self.hfr_sample_seq = self.hfr_sample_seq.wrapping_add(1);
    }

    pub fn reset_baseline_hfr(&mut self) {
        self.baseline_hfr = self.current_hfr;
    }

    pub fn invalidate_autofocus(&mut self, reason: impl Into<String>) {
        let reason = reason.into();
        self.baseline_hfr = None;
        self.autofocus_invalidated = true;
        self.autofocus_invalidation_reason = Some(reason.clone());
        tracing::info!("Autofocus invalidated: {}", reason);
    }

    /// Append a guiding-RMS sample and trim the rolling history to
    /// `self.guiding_rms_retention_secs`. Audit §1.21: the previously hardcoded
    /// 300-second window is now configurable via
    /// `set_guiding_rms_retention_secs` (driven by the GuidingFailed trigger
    /// configuration in the trigger evaluator). Default remains 300s.
    pub fn update_guiding_rms(&mut self, rms: f64) {
        if self.guiding_rms_history.is_none() {
            self.guiding_rms_history = Some(Vec::new());
        }

        let retention = self.guiding_rms_retention_secs.max(1);
        if let Some(history) = &mut self.guiding_rms_history {
            history.push((Instant::now(), rms));
            history.retain(|(time, _)| time.elapsed().as_secs() < retention);
        }
    }

    /// Audit §1.21: set the retention window (seconds) for
    /// `guiding_rms_history`. Driven by the GuidingFailed trigger configuration
    /// so a user-tuned `rms_retention_secs` is honoured at runtime instead of
    /// silently falling back to the previous 300-second hardcode.
    pub fn set_guiding_rms_retention_secs(&mut self, secs: u64) {
        self.guiding_rms_retention_secs = secs.max(1);
    }

    pub fn update_temperature(&mut self, temp: f64) {
        if self.baseline_temperature.is_none() {
            self.baseline_temperature = Some(temp);
        }
        self.current_temperature = Some(temp);
    }

    pub fn reset_baseline_temperature(&mut self) {
        self.baseline_temperature = self.current_temperature;
    }

    pub fn reset_baseline_focuser_position(&mut self, current_position: i32) {
        self.baseline_focuser_position = Some(current_position);
    }

    pub fn set_filter(&mut self, filter: String) {
        let changed = self.current_filter.as_ref() != Some(&filter);
        self.filter_changed = changed;
        if changed {
            self.invalidate_autofocus(format!("filter changed to {}", filter));
        }
        self.current_filter = Some(filter);
    }

    pub fn clear_filter_changed(&mut self) {
        self.filter_changed = false;
    }

    /// Increment completed exposures counter (for periodic triggers)
    pub fn increment_exposure_count(&mut self) {
        self.completed_exposures += 1;
    }

    /// Mark that autofocus was just performed
    pub fn mark_autofocus_performed(&mut self) {
        self.last_autofocus_frame = self.completed_exposures;
        self.autofocus_invalidated = false;
        self.autofocus_invalidation_reason = None;
    }

    /// Mark that dither was just performed
    pub fn mark_dither_performed(&mut self) {
        self.last_dither_frame = self.completed_exposures;
    }

    /// Reset exposure counters (for new sequence)
    pub fn reset_exposure_counters(&mut self) {
        self.completed_exposures = 0;
        self.last_autofocus_frame = 0;
        self.last_dither_frame = 0;
    }

    /// Update plate solve result for drift detection
    pub fn update_plate_solve(&mut self, ra_degrees: f64, dec_degrees: f64, pixel_scale: f64) {
        self.last_plate_solve_ra = Some(ra_degrees);
        self.last_plate_solve_dec = Some(dec_degrees);
        self.last_plate_solve_pixel_scale = Some(pixel_scale);
    }

    /// Set target coordinates for drift detection
    pub fn set_target(&mut self, ra_degrees: f64, dec_degrees: f64) {
        self.target_ra = Some(ra_degrees);
        self.target_dec = Some(dec_degrees);
    }

    /// Calculate drift from target in pixels (RA, Dec)
    /// Returns None if insufficient data available
    pub fn calculate_drift_pixels(&self) -> Option<(f64, f64)> {
        let solve_ra = self.last_plate_solve_ra?;
        let solve_dec = self.last_plate_solve_dec?;
        let target_ra = self.target_ra?;
        let target_dec = self.target_dec?;
        let pixel_scale = self.last_plate_solve_pixel_scale?;

        let ra_diff_deg = solve_ra - target_ra;
        let dec_diff_deg = solve_dec - target_dec;

        // RA must be scaled by cos(dec) — RA "circles" shrink as you approach
        // the poles, so a 1° RA difference at Dec=89° is a tiny on-sky distance
        // compared to a 1° RA difference at the equator. Omitting cos(dec) is
        // the classic high-declination drift bug.
        let dec_rad = target_dec.to_radians();
        let ra_arcsec = ra_diff_deg * 3600.0 * dec_rad.cos();
        let dec_arcsec = dec_diff_deg * 3600.0;

        let ra_pixels = ra_arcsec / pixel_scale;
        let dec_pixels = dec_arcsec / pixel_scale;

        Some((ra_pixels.abs(), dec_pixels.abs()))
    }

    /// Update guide star lost state
    pub fn set_guide_star_lost(&mut self, lost: bool) {
        if lost && !self.guide_star_lost {
            tracing::warn!("Guide star lost detected");
        }
        self.guide_star_lost = lost;
    }

    /// Arm or disarm the `GuideStarLost` trigger.
    ///
    /// `guiding_enabled` gates `GuideStarLost` (see `check`) so the trigger
    /// cannot fire while the guider is idle between sequences. It MUST be set
    /// `true` once guiding is active, otherwise the star-lost safety net is
    /// dead and the sequence silently keeps exposing unguided after a star
    /// loss. It is set `true` explicitly on a successful `StartGuiding` and
    /// latched `true` in the executor poll whenever the guider reports it is
    /// actively guiding; it is cleared on an explicit `StopGuiding` so an
    /// intentional stop does not masquerade as a lost star.
    pub fn set_guiding_enabled(&mut self, enabled: bool) {
        if self.guiding_enabled != enabled {
            tracing::debug!("Guiding-enabled (star-lost trigger arm) -> {}", enabled);
        }
        self.guiding_enabled = enabled;
    }

    /// Record the filter focus offset (steps, reference-relative) now embodied
    /// in the focuser position. Set after a filter-offset move so the next
    /// filter change applies only the delta. See `last_applied_filter_offset`.
    pub fn set_last_applied_filter_offset(&mut self, offset: i32) {
        self.last_applied_filter_offset = offset;
    }

    /// Update current humidity reading
    /// Wave 5 Agent 4 — push the latest cloud-motion analyzer reading into
    /// the trigger state. Called from the executor when a Dart-side
    /// `UpdateCloudMotion` command arrives. Every argument is optional so the
    /// caller can express "analyzer says no arrival predicted" by passing
    /// `predicted_arrival_minutes: None`.
    ///
    /// `current_cover_percent` outside `[0, 100]` is clamped, but the original
    /// out-of-range value is logged at WARN so a buggy data source is loud
    /// (CLAUDE.md "errors are a feature"). NaN / inf flow through `.filter`
    /// — they would have been treated as "fire" by the comparison operators
    /// otherwise, which is exactly the silent-fallback bug we forbid.
    pub fn update_cloud_motion(
        &mut self,
        current_cover_percent: Option<f64>,
        predicted_arrival_minutes: Option<f64>,
        predicted_opening_minutes: Option<f64>,
        predicted_opening_duration_secs: Option<f64>,
        predicted_clear_sky_alt_az: Option<(f64, f64)>,
    ) {
        let sanitize_finite = |v: Option<f64>| v.filter(|x| x.is_finite());

        let cover = sanitize_finite(current_cover_percent).map(|v| {
            if !(0.0..=100.0).contains(&v) {
                tracing::warn!(
                    "update_cloud_motion: cover {:.2}% out of [0,100]; clamping",
                    v
                );
                v.clamp(0.0, 100.0)
            } else {
                v
            }
        });

        // Negative predicted minutes are clamped to 0 ("any second now") because
        // the user's intent for "fire within N minutes" still applies: if the
        // analyzer says "-2 minutes" the cloud is already arriving.
        let arrival = sanitize_finite(predicted_arrival_minutes).map(|v| v.max(0.0));
        let opening = sanitize_finite(predicted_opening_minutes).map(|v| v.max(0.0));
        let duration = sanitize_finite(predicted_opening_duration_secs).map(|v| v.max(0.0));

        self.current_cloud_coverage_percent = cover;
        self.predicted_cloud_arrival_minutes = arrival;
        self.predicted_cloud_opening_minutes = opening;
        self.predicted_cloud_opening_duration_secs = duration;
        self.predicted_clear_sky_direction = predicted_clear_sky_alt_az;
        self.cloud_motion_last_update = Some(Instant::now());
    }

    pub fn update_humidity(&mut self, humidity: f64) {
        self.current_humidity = Some(humidity);
    }

    /// W1 native daylight gate — seed the configured maximum Sun altitude
    /// (degrees) for on-sky LIGHT captures so the instruction-layer gate
    /// (`instructions::execute_slew` / `execute_exposure`) can read it through
    /// the shared trigger state. A non-finite value is rejected (stored as
    /// `None`) so the gate falls back to its default rather than silently
    /// disabling itself on a NaN/inf config push (CLAUDE.md "fail closed").
    pub fn set_max_sun_altitude_degrees(&mut self, degrees: f64) {
        self.max_sun_altitude_degrees = if degrees.is_finite() {
            Some(degrees)
        } else {
            None
        };
    }

    /// Defense-in-depth (full-night audit 2026-06-04): store the Dart-side
    /// weather-safety verdict. `Some(true)` = Dart computed UNSAFE, `Some(false)`
    /// = Dart computed SAFE, `None` = Dart abstains (provider disabled / no data).
    /// Folded into the `WeatherUnsafe` trigger as an additional unsafe source so a
    /// rig without a hardware safety device still aborts when the configured
    /// thresholds / API / cloud sources say unsafe. Never makes the trigger LESS
    /// safe than the hardware `weather_safe` reading (see the evaluator).
    pub fn update_weather_verdict(&mut self, unsafe_override: Option<bool>) {
        self.weather_verdict_unsafe = unsafe_override;
        // Stamp the push time so the safety poll can detect a stale-AND-unsafe
        // verdict (a dead Dart feed holding the sequence paused) and warn loudly
        // without ever auto-clearing the unsafe state. Stamp on EVERY push,
        // including `None` (abstain) and `Some(false)` (safe): freshness is a
        // property of the channel, not of the verdict value, and a fresh
        // abstain/safe is exactly what clears the stale-unsafe condition.
        self.weather_verdict_last_update = Some(Instant::now());
    }

    /// Architecture-unification 2026-06-05 (Subsystem 2 step 3): true when a
    /// `Some(true)` (UNSAFE) verdict has not been refreshed within
    /// `staleness_secs`. Used by the safety poll to emit a loud
    /// "verdict feed stale; holding paused fail-closed" warning.
    ///
    /// Returns false (NOT stale) when:
    ///   * the verdict is not `Some(true)` (a safe / abstaining verdict that
    ///     goes stale is harmless — nothing is being held), or
    ///   * no verdict has ever been pushed (`weather_verdict_last_update` is
    ///     `None`); there is no feed to be stale yet, and the hardware poll is
    ///     the active gate.
    ///
    /// This NEVER mutates state and NEVER clears the unsafe verdict — it is a
    /// pure observability predicate.
    pub fn is_weather_verdict_stale_unsafe(&self, staleness_secs: u64) -> bool {
        if self.weather_verdict_unsafe != Some(true) {
            return false;
        }
        match self.weather_verdict_last_update {
            Some(last) => last.elapsed().as_secs() >= staleness_secs,
            None => false,
        }
    }

    /// Wave 7 Science: store the latest transparency reading. `None`
    /// clears the slot (used when the science pipeline loses lock).
    /// NaN / infinite values are dropped via `is_finite` rather than
    /// silently stored — CLAUDE.md "errors are a feature".
    pub fn update_transparency(&mut self, transparency: Option<f64>) {
        let sanitised = transparency.filter(|v| v.is_finite()).map(|v| {
            if !(0.0..=1.5).contains(&v) {
                tracing::warn!("update_transparency: {:.3} out of [0,1.5]; clamping", v);
                v.clamp(0.0, 1.5)
            } else {
                v
            }
        });
        self.current_transparency = sanitised;
        self.transparency_last_update = Some(Instant::now());
    }

    /// Set mount tracking expected state
    pub fn set_mount_tracking_expected(&mut self, expected: bool) {
        self.mount_tracking_expected = expected;
        self.mount_tracking_lost = false;
    }

    /// Update dome shutter status
    pub fn update_dome_status(&mut self, status: String) {
        self.dome_shutter_status = Some(status);
    }

    /// Set dome shutter open expected state
    pub fn set_dome_shutter_expected(&mut self, expected: bool) {
        self.dome_shutter_open_expected = expected;
    }

    /// Reset mount tracking lost state
    pub fn reset_mount_tracking_state(&mut self) {
        self.mount_tracking_lost = false;
    }

    /// Get the next grid dither offset (in pixels) for an NxN grid pattern.
    /// Returns (ra_offset, dec_offset) centered on (0,0), then advances the index.
    /// The grid walks through positions in row-major order, wrapping after N*N.
    pub fn next_grid_dither_offset(&mut self, grid_size: u32, pixels: f64) -> (f64, f64) {
        let n = grid_size.max(1);
        let total_positions = n * n;
        let idx = self.grid_dither_index % total_positions;

        let row = idx / n;
        let col = idx % n;

        // Grid is centred on the target by translating each index to a
        // signed offset from the grid centre. step = pixels*2/(n-1) so the
        // outermost positions land exactly at ±pixels (matching the user's
        // intended dither radius); n=1 degenerates to a single (0,0) position.
        let (ra_offset, dec_offset) = if n > 1 {
            // Why: n is u32 grid_size (UI-bounded, typically <=10); col and row
            // are derived from idx % n / n. All u32 -> f64 widenings are lossless
            // for any plausible grid size.
            let step = pixels * 2.0 / f64::from(n - 1);
            let center = f64::from(n - 1) / 2.0;
            let ra = (f64::from(col) - center) * step;
            let dec = (f64::from(row) - center) * step;
            (ra, dec)
        } else {
            (0.0, 0.0)
        };

        self.grid_dither_index = (idx + 1) % total_positions;

        (ra_offset, dec_offset)
    }

    /// Reset grid dither position (call when sequence starts or target changes)
    pub fn reset_grid_dither(&mut self) {
        self.grid_dither_index = 0;
    }

    // ========================================================================
    // Meridian Flip State Management
    // ========================================================================

    /// Update the current hour angle (call periodically from mount polling)
    pub fn update_hour_angle(&mut self, hour_angle: f64) {
        self.current_hour_angle = Some(hour_angle);
    }

    /// Update the current pier side and clear `has_flipped_this_target` if
    /// the mount has returned to the side it was on before the recorded flip.
    /// Audit §1.9: a long single-target session that crosses two meridians
    /// (high latitude / pause-resume / mosaic-with-shared-name) used to
    /// silently skip the second flip because the flag was only ever cleared
    /// by a target-name change. Observing the original pier side is
    /// authoritative evidence that the mount is back on the pre-flip side
    /// and a fresh flip is again required.
    pub fn update_pier_side(&mut self, pier_side: PierSide) {
        self.pier_side = Some(pier_side);
        self.on_pier_side_observed(pier_side);
    }

    /// Audit §1.9: invariant check. Called from `update_pier_side` (and any
    /// other code path that observes mount pier-side telemetry); clears
    /// `has_flipped_this_target` when the observed side matches the
    /// pre-flip side recorded by `mark_flip_performed`. Public so external
    /// observers (e.g., bridge layer reading mount state on a different
    /// cadence) can apply the same invariant without going through
    /// `update_pier_side`.
    pub fn on_pier_side_observed(&mut self, side: PierSide) {
        if !self.has_flipped_this_target {
            return;
        }
        let Some(origin) = self.flip_origin_pier_side else {
            // Why: without an origin we cannot reason about a return-to-pre-flip
            // event. Clearing on every observation would re-introduce the
            // double-flip bug §1.3 fixed, so we leave the flag set until the
            // user changes target.
            return;
        };
        // Unknown is non-actionable — wait for a real reading.
        if matches!(side, PierSide::Unknown) {
            return;
        }
        if side == origin {
            tracing::info!(
                "[MERIDIAN] Pier side returned to pre-flip side ({:?}); clearing has_flipped_this_target so a second flip can be triggered for the same target",
                origin
            );
            self.has_flipped_this_target = false;
            self.flip_origin_pier_side = None;
        }
    }

    /// Audit §1.9: explicit reset of the flip-performed bookkeeping. Called
    /// at natural target-boundaries (sequence reset, target group entry)
    /// where a double-flip on the new target is impossible by construction.
    pub fn clear_flipped_state(&mut self) {
        self.has_flipped_this_target = false;
        self.flip_origin_pier_side = None;
    }

    /// Update mount tracking limit time (if mount reports it)
    pub fn update_tracking_limit_time(&mut self, limit_time: i64) {
        self.mount_tracking_limit_time = Some(limit_time);
    }

    /// Set the current target for meridian flip tracking
    /// This also resets the has_flipped flag for the new target
    pub fn set_meridian_target(&mut self, target_name: String) {
        if self.current_target_name.as_ref() != Some(&target_name) {
            let previous = self.current_target_name.clone();
            self.current_target_name = Some(target_name);
            // Audit §1.9: a target change is a natural boundary; reset both
            // the flag and the recorded origin so flip bookkeeping starts
            // fresh.
            self.has_flipped_this_target = false;
            self.flip_origin_pier_side = None;
            if let Some(previous) = previous {
                self.invalidate_autofocus(format!("target changed from {}", previous));
            }
        }
    }

    /// Mark that a meridian flip has been performed for the current target.
    /// Audit §1.9: also records the pier side that was active *before* the
    /// flip (in `flip_origin_pier_side`) so `on_pier_side_observed` can
    /// detect the mount returning to that side and clear the flag, allowing
    /// a second flip on the same long-running target.
    pub fn mark_flip_performed(&mut self) {
        self.has_flipped_this_target = true;
        // The pier side was updated immediately after the flip, so it now
        // reflects the *post-flip* side. The origin (pre-flip) side is the
        // opposite of the current side. East <-> West; Unknown stays Unknown
        // and prevents future return-detection until telemetry recovers.
        self.flip_origin_pier_side = match self.pier_side {
            Some(PierSide::East) => Some(PierSide::West),
            Some(PierSide::West) => Some(PierSide::East),
            // Why: if telemetry is unavailable we cannot compute the origin
            // safely; leaving it None keeps the flag latched until target
            // change (matches §1.9's safe-default policy).
            _ => None,
        };
        tracing::info!(
            "[MERIDIAN] Flip marked as completed for target: {:?} (origin pier side: {:?})",
            self.current_target_name,
            self.flip_origin_pier_side
        );
    }

    /// Clear meridian flip state (call when target changes or sequence resets)
    pub fn clear_meridian_state(&mut self) {
        self.current_hour_angle = None;
        self.pier_side = None;
        self.mount_tracking_limit_time = None;
        self.has_flipped_this_target = false;
        self.flip_origin_pier_side = None; // Audit §1.9.
        self.current_target_name = None;
        self.next_meridian_flip_time = None;
        self.tracking_limit_detected_at = None;
    }

    /// Reset tracking limit detection state (call when tracking resumes or flip completes)
    pub fn reset_tracking_limit_detection(&mut self) {
        self.tracking_limit_detected_at = None;
        self.mount_tracking_lost = false;
    }

    /// Check if a meridian flip might be needed based on current state
    /// Returns (needs_flip, minutes_past_meridian) for diagnostic purposes
    pub fn meridian_flip_status(&self) -> (bool, Option<f64>) {
        if self.has_flipped_this_target {
            return (false, None);
        }

        if let Some(ha) = self.current_hour_angle {
            let minutes_past = ha * 60.0;
            let on_pre_flip_side = match self.pier_side {
                Some(PierSide::West) => ha > 0.0,
                Some(PierSide::East) => false,
                _ => ha > 0.0,
            };
            (on_pre_flip_side && ha > 0.0, Some(minutes_past))
        } else {
            (false, None)
        }
    }
}

/// Manager for all active triggers
pub struct TriggerManager {
    triggers: Vec<Trigger>,
    state: Arc<RwLock<TriggerState>>,
    enabled: bool,
}

impl TriggerManager {
    pub fn new() -> Self {
        Self {
            triggers: Vec::new(),
            state: Arc::new(RwLock::new(TriggerState::new())),
            enabled: true,
        }
    }

    /// Get the trigger state for updates
    pub fn state(&self) -> Arc<RwLock<TriggerState>> {
        self.state.clone()
    }

    /// Add a trigger
    pub fn add_trigger(&mut self, trigger: Trigger) {
        self.triggers.push(trigger);
    }

    /// Remove a trigger by ID
    pub fn remove_trigger(&mut self, id: &str) {
        self.triggers.retain(|t| t.id != id);
    }

    /// Get a trigger by ID
    pub fn get_trigger(&self, id: &str) -> Option<&Trigger> {
        self.triggers.iter().find(|t| t.id == id)
    }

    /// Get mutable trigger by ID
    pub fn get_trigger_mut(&mut self, id: &str) -> Option<&mut Trigger> {
        self.triggers.iter_mut().find(|t| t.id == id)
    }

    /// Enable/disable a trigger
    pub fn set_trigger_enabled(&mut self, id: &str, enabled: bool) {
        if let Some(trigger) = self.triggers.iter_mut().find(|t| t.id == id) {
            trigger.enabled = enabled;
        }
    }

    /// Enable/disable all triggers
    pub fn set_all_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
    }

    /// Get all triggers
    pub fn triggers(&self) -> &[Trigger] {
        &self.triggers
    }

    /// Check all triggers and return any that fired
    pub async fn check_all(&mut self) -> Vec<(String, RecoveryAction)> {
        if !self.enabled {
            return Vec::new();
        }

        // Audit §1.21: propagate per-trigger retention/configuration into the
        // shared trigger state before evaluation so updates to e.g.
        // `GuidingFailed::rms_retention_secs` take effect on the next sample
        // without requiring a sequence reload.
        self.sync_state_from_config().await;

        // Clone the state once before the loop
        let state = self.state.read().await.clone();
        let mut fired = Vec::new();

        for trigger in &mut self.triggers {
            if trigger.check(&state).await {
                tracing::warn!("Trigger fired: {} ({})", trigger.name, trigger.id);
                fired.push((trigger.id.clone(), trigger.recovery_action.clone()));
            }
        }

        fired
    }

    /// Audit §1.21: copy configurable runtime values from each trigger's
    /// config into the shared `TriggerState`. Currently only
    /// `GuidingFailed::rms_retention_secs` requires propagation; new
    /// configurable retention windows added in future audits should be
    /// wired here so the trigger evaluator never needs to mutate state
    /// behind an immutable borrow.
    pub async fn sync_state_from_config(&self) {
        let mut retention: Option<u64> = None;
        let mut meridian_method: Option<crate::MeridianTriggerMethod> = None;
        let mut meridian_minutes: Option<f64> = None;
        for trigger in &self.triggers {
            if !trigger.enabled {
                continue;
            }
            if let TriggerType::GuidingFailed {
                rms_retention_secs, ..
            } = &trigger.trigger_type
            {
                if retention.is_none() {
                    retention = Some(*rms_retention_secs);
                }
            }
            // Stamp the active flip trigger's method + threshold so (a) the
            // MountTrackingLost evaluator's defer-to-OnTrackingLimitHit
            // heuristic actually sees the configured method (it previously
            // stayed None in production and the deferral never engaged) and
            // (b) the exposure instruction's pre-frame meridian gate can
            // predict when the flip will fire.
            if let TriggerType::MeridianFlip { config } = &trigger.trigger_type {
                if meridian_method.is_none() {
                    meridian_method = Some(config.trigger_method);
                    if config.trigger_method == crate::MeridianTriggerMethod::MinutesPastMeridian {
                        meridian_minutes = Some(config.minutes_past_meridian);
                    }
                }
            }
        }
        let retention_changed = if let Some(secs) = retention {
            let state = self.state.read().await;
            state.guiding_rms_retention_secs != secs
        } else {
            false
        };
        {
            let mut state = self.state.write().await;
            if retention_changed {
                if let Some(secs) = retention {
                    state.set_guiding_rms_retention_secs(secs);
                }
            }
            if state.meridian_trigger_method != meridian_method {
                state.meridian_trigger_method = meridian_method;
            }
            if state.meridian_flip_minutes_past != meridian_minutes {
                state.meridian_flip_minutes_past = meridian_minutes;
            }
        }
    }

    /// Create standard triggers
    pub fn create_standard_triggers(&mut self) {
        // HFR degradation trigger
        self.add_trigger(
            Trigger::new(
                "hfr_degraded",
                "HFR Degradation",
                TriggerType::HfrDegraded {
                    threshold_percent: 20.0,
                    absolute_threshold: 0.0,
                    consecutive_frames: 3,
                },
                RecoveryAction::Autofocus,
            )
            // 5 min cooldown: an autofocus run takes 2-4 min on typical rigs,
            // so a shorter cooldown would re-fire before the previous AF could
            // settle the HFR baseline and would loop AF indefinitely.
            .with_cooldown(300),
        );

        // Meridian flip trigger - uses MeridianFlip recovery action
        self.add_trigger(
            Trigger::new(
                "meridian_flip",
                "Meridian Flip",
                TriggerType::MeridianFlip {
                    config: crate::MeridianFlipConfig::default(),
                },
                RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
            )
            // A meridian flip + re-center + refocus takes 5-8 min; 10 min
            // cooldown is the structural guarantee against the double-flip
            // bug audit §1.3 fixed at the state-machine level.
            .with_cooldown(600),
        );

        // Guiding failure trigger
        self.add_trigger(
            Trigger::new(
                "guiding_failed",
                "Guiding Failure",
                TriggerType::GuidingFailed {
                    rms_threshold: 2.0,
                    duration_secs: 30.0,
                    // Audit §1.21: 300s preserves the previous hardcoded
                    // retention; users can change it via UI/profile JSON.
                    rms_retention_secs: crate::default_guiding_rms_retention_secs(),
                },
                RecoveryAction::Retry { max_attempts: 3 },
            )
            .with_cooldown(60),
        );

        // Altitude limit trigger
        self.add_trigger(
            Trigger::new(
                "altitude_limit",
                "Altitude Limit",
                TriggerType::AltitudeLimit { min_altitude: 30.0 },
                RecoveryAction::NextTarget,
            )
            .with_cooldown(60),
        );

        // Weather safety trigger
        self.add_trigger(
            Trigger::new(
                "weather_unsafe",
                "Weather Unsafe",
                TriggerType::WeatherUnsafe,
                RecoveryAction::ParkAndAbort,
            )
            // Weather safety must re-fire every poll while conditions are
            // unsafe — a cooldown could mask a brief moment of clearance
            // followed by re-degradation, letting the sequence resume into
            // worsening conditions.
            .with_cooldown(0),
        );

        // Temperature shift trigger
        self.add_trigger(
            Trigger::new(
                "temperature_shift",
                "Temperature Shift",
                TriggerType::TemperatureShift { degrees: 2.0 },
                RecoveryAction::Autofocus,
            )
            .with_cooldown(600),
        );

        // Filter change trigger (for focus offsets)
        self.add_trigger(
            Trigger::new(
                "filter_change",
                "Filter Change",
                TriggerType::FilterChange,
                RecoveryAction::Continue, // Handle via filter focus offsets
            )
            .with_cooldown(0),
        );

        // Dawn approaching trigger (automatic morning shutdown)
        self.add_trigger(
            Trigger::new(
                "dawn_approaching",
                "Dawn Approaching",
                TriggerType::DawnApproaching {
                    minutes_before: 30.0,
                }, // 30 min before astronomical twilight
                RecoveryAction::ParkAndAbort,
            )
            .with_cooldown(0), // No cooldown for safety
        );

        // Mount tracking lost trigger
        self.add_trigger(
            Trigger::new(
                "mount_tracking_lost",
                "Mount Tracking Lost",
                TriggerType::MountTrackingLost,
                RecoveryAction::Pause,
            )
            .with_cooldown(60), // 60 second cooldown
        );

        // Dome shutter not open trigger
        self.add_trigger(
            Trigger::new(
                "dome_shutter_not_open",
                "Dome Shutter Not Open",
                TriggerType::DomeShutterNotOpen,
                RecoveryAction::ParkAndAbort,
            )
            .with_cooldown(0), // No cooldown for safety
        );

        // Guide star lost trigger
        self.add_trigger(
            Trigger::new(
                "guide_star_lost",
                "Guide Star Lost",
                TriggerType::GuideStarLost,
                RecoveryAction::Pause,
            )
            .with_cooldown(30), // 30 second cooldown
        );

        // Focus drift detection trigger.
        // Audit §1.21: defaults pulled from the shared
        // `default_focus_drift_*` helpers so config loaders and this builder
        // cannot diverge.
        self.add_trigger(
            Trigger::new(
                "focus_drift",
                "Focus Drift",
                TriggerType::FocusDrift {
                    window_size: crate::default_focus_drift_window_size(),
                    min_increasing_count: crate::default_focus_drift_min_increasing_count(),
                    min_total_increase: crate::default_focus_drift_min_total_increase(),
                },
                RecoveryAction::Autofocus,
            )
            .with_cooldown(600), // 10 minute cooldown (same as temperature shift)
        );

        // Humidity threshold:
        //
        // Architecture-unification 2026-06-05 (Subsystem 2 step 2 — duplicate
        // humidity gate reconciliation). The standard humidity trigger USED to
        // be auto-added here with a HARDCODED `max_percent: 85.0`. That created
        // a second, divergent humidity gate: the Dart `WeatherThresholdEvaluator`
        // already evaluates humidity against the operator-configured
        // `WeatherSettings.maxHumidityPercent` and folds the result into the
        // pushed weather verdict, which the `WeatherUnsafe` trigger consumes. The
        // hardcoded 85% standard trigger ignored that setting, so the same
        // humidity reading could be judged differently by the two gates (e.g. an
        // operator who set 70% still got no abort until 85%, or one who set 90%
        // got a spurious abort at 85%).
        //
        // The humidity ceiling now has exactly ONE definition: the Dart
        // `maxHumidityPercent` → `WeatherThresholdEvaluator` → pushed verdict →
        // `WeatherUnsafe` (which already maps to `RecoveryCause::WeatherUnsafe`,
        // the same recovery this standard trigger used). The `HumidityThreshold`
        // trigger TYPE is retained for operators who explicitly add a per-sequence
        // humidity recovery node with their own threshold + recovery action, but
        // it is no longer silently auto-added with a conflicting hardcoded value.
        // See `weather_threshold_evaluator.dart` and the parity test.

        // Audit §1.11: plate-solve drift trigger. Default 30 px is a pragmatic
        // mid-range value: small enough to catch real drift before it becomes
        // image-ruining, large enough to ignore single-pixel jitter from
        // imperfect plate-solve solutions. Recovery is `Recenter`, not Pause,
        // so the sequence keeps imaging.
        self.add_trigger(
            Trigger::new(
                "drift_limit",
                "Plate-Solve Drift Limit",
                TriggerType::DriftLimit { max_pixels: 30.0 },
                RecoveryAction::Recenter,
            )
            .with_cooldown(120), // 2 min cooldown so a single recenter is given time to settle
        );

        // Audit §1.5: standard `DitherInterval` trigger so periodic dithering
        // happens in sequences that don't include an explicit Dither node.
        // Default cadence 5 frames matches typical mosaic guidance. Recovery
        // is `Dither(default config)`; users override via UI/profile JSON.
        self.add_trigger(
            Trigger::new(
                "dither_interval",
                "Dither Interval",
                TriggerType::DitherInterval { every_n_frames: 5 },
                RecoveryAction::Dither(crate::DitherConfig::default()),
            )
            .with_cooldown(0), // Cadence is exposure-count-driven; no time-based cooldown.
        );

        // Trust-patch §3: standard `AutofocusInterval` trigger so periodic
        // refocus happens in sequences that lack an explicit Autofocus node
        // between bursts. Wired symmetrically with `DitherInterval` so
        // disabling either is straightforward.
        //
        // Default cadence `default_autofocus_interval_frames()` (25 frames)
        // matches typical "AF every ~30 min" for 60-90 s subs. Users override
        // via UI/profile JSON. Recovery is `Autofocus` so the trigger-monitor
        // dispatch reaches `execute_autofocus` with the live device IDs.
        //
        // No time-based cooldown — the cadence is already exposure-count
        // driven and a duplicate cooldown would mask the user's setting
        // (CLAUDE.md "errors are a feature").
        self.add_trigger(
            Trigger::new(
                "autofocus_interval",
                "Autofocus Interval",
                TriggerType::AutofocusInterval {
                    every_n_frames: crate::default_autofocus_interval_frames(),
                },
                RecoveryAction::Autofocus,
            )
            .with_cooldown(0),
        );
    }
}

impl Default for TriggerManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn test_hfr_trigger_relative() {
        let mut trigger = Trigger::new(
            "test",
            "Test HFR Relative",
            TriggerType::HfrDegraded {
                threshold_percent: 20.0,
                absolute_threshold: 0.0,
                consecutive_frames: 1,
            },
            RecoveryAction::Autofocus,
        );

        let mut state = TriggerState::new();
        state.baseline_hfr = Some(2.0);

        // No change - should not trigger. update_hfr keeps the pre-set
        // baseline (only sets it when None) and advances the per-frame
        // sequence so the P1-9 frame-gate lets each check count.
        state.update_hfr(2.0);
        assert!(!trigger.check(&state).await);

        // 10% increase - should not trigger
        state.update_hfr(2.2);
        assert!(!trigger.check(&state).await);

        // 25% increase - should trigger (consecutive_frames=1, so immediate)
        state.update_hfr(2.5);
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_guide_star_lost_requires_arming() {
        // Regression: `guiding_enabled` must be settable so the GuideStarLost
        // trigger can fire. Previously it was never set true, making the
        // trigger permanently dead and letting the sequence take unguided
        // subs after a star loss.
        let mut trigger = Trigger::new(
            "guide_star_lost",
            "Guide Star Lost",
            TriggerType::GuideStarLost,
            RecoveryAction::Pause,
        );

        let mut state = TriggerState::new();

        // Star lost but guiding never armed -> must NOT fire (idle guider).
        state.set_guide_star_lost(true);
        assert!(
            !trigger.check(&state).await,
            "GuideStarLost must not fire before guiding is armed"
        );

        // Arm guiding (as StartGuiding success / executor latch does).
        state.set_guiding_enabled(true);
        assert!(
            trigger.check(&state).await,
            "GuideStarLost must fire once armed and the star is lost"
        );

        // Star reacquired -> no longer fires.
        state.set_guide_star_lost(false);
        assert!(!trigger.check(&state).await);

        // Star lost again while still armed -> fires.
        state.set_guide_star_lost(true);
        assert!(trigger.check(&state).await);

        // Explicit StopGuiding disarms -> must not fire even though the
        // guider reports not-guiding (intentional stop, not a lost star).
        state.set_guiding_enabled(false);
        assert!(
            !trigger.check(&state).await,
            "GuideStarLost must not fire after an intentional StopGuiding"
        );
    }

    #[tokio::test]
    async fn test_dawn_approaching_fires_only_within_upcoming_window() {
        // Regression: DawnApproaching must fire when an UPCOMING dawn is within
        // the window, and must NOT fire when dawn_time is unset (the old bug
        // left it None forever) or already in the past (the stale-cache bug).
        let mut trigger = Trigger::new(
            "dawn",
            "Dawn Approaching",
            TriggerType::DawnApproaching {
                minutes_before: 30.0,
            },
            RecoveryAction::ParkAndAbort,
        );
        let mut state = TriggerState::new();

        // No dawn_time seeded -> cannot fire.
        assert!(!trigger.check(&state).await);

        let now = chrono::Utc::now().timestamp();

        // Dawn 60 min out, 30 min window -> not yet.
        state.dawn_time = Some(now + 60 * 60);
        assert!(!trigger.check(&state).await);

        // Dawn 15 min out -> within the 30 min window -> fire.
        state.dawn_time = Some(now + 15 * 60);
        assert!(trigger.check(&state).await);

        // Dawn already passed -> must NOT fire (would otherwise fire all day).
        state.dawn_time = Some(now - 60);
        assert!(!trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_hfr_trigger_absolute() {
        let mut trigger = Trigger::new(
            "test",
            "Test HFR Absolute",
            TriggerType::HfrDegraded {
                threshold_percent: 0.0, // disabled
                absolute_threshold: 3.5,
                consecutive_frames: 1,
            },
            RecoveryAction::Autofocus,
        );

        let mut state = TriggerState::new();

        // Below absolute threshold - should not trigger
        state.update_hfr(3.0);
        assert!(!trigger.check(&state).await);

        // Above absolute threshold - should trigger
        state.update_hfr(4.0);
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_hfr_trigger_consecutive_frames() {
        let mut trigger = Trigger::new(
            "test",
            "Test HFR Consecutive",
            TriggerType::HfrDegraded {
                threshold_percent: 0.0,
                absolute_threshold: 3.0,
                consecutive_frames: 3,
            },
            RecoveryAction::Autofocus,
        );

        let mut state = TriggerState::new();

        // Frame 1: bad - should not trigger yet (need 3)
        state.update_hfr(4.0);
        assert!(!trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 1);

        // P1-9: a re-evaluation of the SAME frame (the ~1Hz monitor tick) must
        // NOT advance the counter — it counts frames, not ticks. Without the
        // fix this would have bumped the count toward firing within one sub.
        assert!(!trigger.check(&state).await);
        assert_eq!(
            trigger.hfr_bad_frame_count, 1,
            "same frame must not re-count"
        );

        // Frame 2: bad - still not enough
        state.update_hfr(4.0);
        assert!(!trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 2);

        // Frame 3: bad - now should trigger
        state.update_hfr(4.0);
        assert!(trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 3);

        // Reset: good frame resets counter
        state.update_hfr(2.0);
        trigger.hfr_bad_frame_count = 0; // Reset after trigger fired
        assert!(!trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 0);

        // One bad frame after reset - not enough
        state.update_hfr(4.0);
        assert!(!trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 1);
    }

    #[tokio::test]
    async fn test_altitude_trigger() {
        let mut trigger = Trigger::new(
            "test",
            "Test Altitude",
            TriggerType::AltitudeLimit { min_altitude: 30.0 },
            RecoveryAction::NextTarget,
        );

        let mut state = TriggerState::new();

        // Above limit - should not trigger
        state.current_altitude = Some(45.0);
        assert!(!trigger.check(&state).await);

        // Below limit - should trigger
        state.current_altitude = Some(25.0);
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_guiding_failed_trigger() {
        let mut trigger = Trigger::new(
            "test",
            "Test Guiding Failed",
            TriggerType::GuidingFailed {
                rms_threshold: 2.0,
                duration_secs: 10.0,
                rms_retention_secs: 300,
            },
            RecoveryAction::Retry { max_attempts: 3 },
        );

        let mut state = TriggerState::new();
        state.guiding_rms_history = Some(Vec::new());

        // Add recent high RMS values
        let now = std::time::Instant::now();
        state.guiding_rms_history.as_mut().unwrap().push((now, 2.5));
        tokio::time::sleep(Duration::from_millis(100)).await;
        state
            .guiding_rms_history
            .as_mut()
            .unwrap()
            .push((std::time::Instant::now(), 2.8));

        // Should trigger - RMS above threshold for duration
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_autofocus_interval_trigger() {
        let mut trigger = Trigger::new(
            "test",
            "Test Autofocus Interval",
            TriggerType::AutofocusInterval { every_n_frames: 10 },
            RecoveryAction::Autofocus,
        );

        let mut state = TriggerState::new();

        // No exposures completed - should not trigger
        assert!(!trigger.check(&state).await);

        // Complete some exposures
        for _ in 0..9 {
            state.increment_exposure_count();
        }

        // 9 exposures, should not trigger yet
        assert!(!trigger.check(&state).await);

        // 10th exposure - should trigger
        state.increment_exposure_count();
        assert!(trigger.check(&state).await);

        // Mark autofocus performed
        state.mark_autofocus_performed();

        // Should not trigger immediately after autofocus
        assert!(!trigger.check(&state).await);

        // Complete another 10 exposures
        for _ in 0..10 {
            state.increment_exposure_count();
        }

        // Should trigger again
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_dither_interval_trigger() {
        let mut trigger = Trigger::new(
            "test",
            "Test Dither Interval",
            TriggerType::DitherInterval { every_n_frames: 5 },
            RecoveryAction::Continue,
        );

        let mut state = TriggerState::new();

        // Complete 5 exposures
        for _ in 0..5 {
            state.increment_exposure_count();
        }

        // Should trigger after 5 exposures
        assert!(trigger.check(&state).await);

        // Mark dither performed
        state.mark_dither_performed();

        // Complete another 5 exposures
        for _ in 0..5 {
            state.increment_exposure_count();
        }

        // Should trigger again
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_autofocus_interval_resume_counter_does_not_underflow() {
        let mut trigger = Trigger::new(
            "test",
            "Test Autofocus Interval Resume",
            TriggerType::AutofocusInterval { every_n_frames: 5 },
            RecoveryAction::Autofocus,
        );

        let mut state = TriggerState::new();
        state.completed_exposures = 3;
        state.last_autofocus_frame = 10;

        assert!(!trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_dither_interval_resume_counter_does_not_underflow() {
        let mut trigger = Trigger::new(
            "test",
            "Test Dither Interval Resume",
            TriggerType::DitherInterval { every_n_frames: 5 },
            RecoveryAction::Continue,
        );

        let mut state = TriggerState::new();
        state.completed_exposures = 2;
        state.last_dither_frame = 8;

        assert!(!trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_weather_unsafe_trigger() {
        let mut trigger = Trigger::new(
            "test",
            "Test Weather",
            TriggerType::WeatherUnsafe,
            RecoveryAction::ParkAndAbort,
        );

        let mut state = TriggerState::new();

        // Safe weather - should not trigger
        state.weather_safe = true;
        assert!(!trigger.check(&state).await);

        // Unsafe weather - should trigger
        state.weather_safe = false;
        assert!(trigger.check(&state).await);
    }

    /// Full-night audit 2026-06-04 (defense-in-depth): the Dart-side weather
    /// verdict is an ADDITIONAL unsafe source. It must be able to abort a rig
    /// whose hardware safety device reports SAFE (or has no device), but it
    /// must never suppress a hardware-unsafe reading.
    #[tokio::test]
    async fn test_weather_unsafe_trigger_honours_dart_verdict() {
        let mut trigger = Trigger::new(
            "test",
            "Test Weather Verdict",
            TriggerType::WeatherUnsafe,
            RecoveryAction::ParkAndAbort,
        );

        let mut state = TriggerState::new();

        // Hardware reports SAFE, verdict abstains (None) -> overall SAFE.
        state.weather_safe = true;
        state.update_weather_verdict(None);
        assert!(
            !trigger.check(&state).await,
            "no unsafe source: should not fire"
        );

        // Hardware reports SAFE, but the Dart verdict computed UNSAFE -> the
        // trigger MUST fire (this is the rig-without-a-safety-device path).
        state.weather_safe = true;
        state.update_weather_verdict(Some(true));
        assert!(
            trigger.check(&state).await,
            "Some(true) verdict must abort even when hardware says safe"
        );

        // Hardware reports SAFE and the Dart verdict explicitly computed SAFE
        // -> overall SAFE (verdict never spuriously fires).
        state.weather_safe = true;
        state.update_weather_verdict(Some(false));
        assert!(
            !trigger.check(&state).await,
            "Some(false) verdict + device-safe must stay safe"
        );

        // Hardware reports UNSAFE and the Dart verdict says SAFE -> the verdict
        // must NOT make the rig less safe than the hardware reading.
        state.weather_safe = false;
        state.update_weather_verdict(Some(false));
        assert!(
            trigger.check(&state).await,
            "Some(false) verdict must never suppress a hardware-unsafe reading"
        );
    }

    /// Architecture-unification 2026-06-05 (Subsystem 2 step 1): the abstain
    /// landmine. A disabled / snoozed / permissive-fail-mode weather toggle on
    /// the Dart side pushes `None` (abstain), NOT `Some(false)`. This test pins
    /// that abstaining MUST NOT suppress a hardware-unsafe abort — even though
    /// the operator "turned weather safety off", a hardware safety device that
    /// reads unsafe still aborts via the OR in `check`. This is the structural
    /// guarantee that makes the disabled-toggle change safe.
    #[tokio::test]
    async fn test_weather_unsafe_abstain_does_not_suppress_hardware_abort() {
        let mut trigger = Trigger::new(
            "test",
            "Test Weather Abstain",
            TriggerType::WeatherUnsafe,
            RecoveryAction::ParkAndAbort,
        );

        let mut state = TriggerState::new();

        // Operator opted out of weather-driven aborts => Dart abstains (None).
        // The hardware safety device nonetheless reads UNSAFE. The trigger MUST
        // still fire: a disabled toggle can never gag a hardware-unsafe device.
        state.weather_safe = false;
        state.update_weather_verdict(None);
        assert!(
            trigger.check(&state).await,
            "abstain (None) must NOT suppress a hardware-unsafe abort"
        );

        // And when the hardware also reads safe under abstain, nothing fires —
        // abstain is genuinely non-asserting, not a stuck-unsafe.
        state.weather_safe = true;
        state.update_weather_verdict(None);
        assert!(
            !trigger.check(&state).await,
            "abstain (None) with safe hardware must not fire"
        );
    }

    /// Architecture-unification 2026-06-05 (Subsystem 2 step 1) — EXHAUSTIVE
    /// gate matrix: Dart verdict {Some(true), Some(false), None} × hardware
    /// {safe, unsafe, unavailable}. "Unavailable" is what the executor's
    /// safety poll resolves through the shared fail-mode truth table
    /// (`safety_fail_mode_no_data_resolution`) BEFORE the gate sees
    /// `weather_safe`, so the unavailable rows are exercised once per fail
    /// mode here exactly the way the poll loop maps them.
    ///
    /// Invariants pinned:
    ///   1. The gate is `!weather_safe || verdict == Some(true)` — a pure OR
    ///      of unsafe sources.
    ///   2. `None` (abstain) NEVER suppresses an unsafe: every row that fires
    ///      with `Some(false)` or `Some(true)` also fires with `None` swapped
    ///      in only if the hardware term alone fires — i.e. None contributes
    ///      nothing in either direction.
    ///   3. The disabled-safety landmine is closed: a Dart side that opted out
    ///      (pushes `None`, never `Some(false)`) cannot make any unsafe row go
    ///      safe — including the unavailable+FailClosed row — even if a future
    ///      refactor made Rust "trust" the verdict, because there is no SAFE
    ///      assertion to trust.
    #[tokio::test]
    async fn weather_unsafe_gate_full_matrix_verdict_x_hardware() {
        use crate::{safety_fail_mode_no_data_resolution, NoDataResolution, SafetyFailMode};

        let mut trigger = Trigger::new(
            "weather_unsafe",
            "Weather Unsafe",
            TriggerType::WeatherUnsafe,
            RecoveryAction::ParkAndAbort,
        );

        // Map the "unavailable" hardware axis through the shared fail-mode
        // truth table exactly as the executor poll loop does. `prior` is the
        // last good reading (the value WarnOnly preserves).
        fn resolve_unavailable(mode: SafetyFailMode, prior: bool) -> bool {
            match safety_fail_mode_no_data_resolution(mode) {
                NoDataResolution::Unsafe => false,
                NoDataResolution::Safe => true,
                NoDataResolution::Preserve => prior,
            }
        }

        let verdicts: [Option<bool>; 3] = [Some(true), Some(false), None];

        for verdict in verdicts {
            // --- Hardware SAFE ---------------------------------------------
            let mut state = TriggerState::new();
            state.weather_safe = true;
            state.update_weather_verdict(verdict);
            assert_eq!(
                trigger.check(&state).await,
                verdict == Some(true),
                "hardware-safe: gate must fire iff verdict is Some(true) (verdict={verdict:?})"
            );

            // --- Hardware UNSAFE -------------------------------------------
            let mut state = TriggerState::new();
            state.weather_safe = false;
            state.update_weather_verdict(verdict);
            assert!(
                trigger.check(&state).await,
                "hardware-unsafe must ALWAYS fire; verdict={verdict:?} must never suppress it"
            );

            // --- Hardware UNAVAILABLE (per fail mode) ----------------------
            for (mode, prior) in [
                (SafetyFailMode::FailClosed, true),
                (SafetyFailMode::FailOpen, false),
                (SafetyFailMode::WarnOnly, true),
                (SafetyFailMode::WarnOnly, false),
            ] {
                let resolved = resolve_unavailable(mode, prior);
                let mut state = TriggerState::new();
                state.weather_safe = resolved;
                state.update_weather_verdict(verdict);
                let expected = !resolved || verdict == Some(true);
                assert_eq!(
                    trigger.check(&state).await,
                    expected,
                    "hardware-unavailable mode={mode:?} prior={prior} verdict={verdict:?}: \
                     gate must be the pure OR of resolved-hardware-unsafe and Some(true)"
                );
            }
        }

        // Landmine regression (disabled safety + a hypothetical verdict-trusting
        // Rust): the Dart opt-out contract is `None`, never `Some(false)`. With
        // `None` pushed there is no SAFE assertion in the channel at all, so no
        // unsafe hardware state — including unavailable under FailClosed — can
        // be declared safe via the verdict.
        let mut state = TriggerState::new();
        state.weather_safe = resolve_unavailable(SafetyFailMode::FailClosed, true);
        state.update_weather_verdict(None);
        assert!(
            trigger.check(&state).await,
            "disabled-safety abstain must not clear a FailClosed unavailable device"
        );
    }

    /// Architecture-unification 2026-06-05 (Subsystem 2 step 3 — stale-verdict
    /// observability). A pushed `Some(true)`=UNSAFE verdict whose Dart feed goes
    /// stale MUST stay unsafe (the `WeatherUnsafe` trigger keeps firing — the
    /// sequence is held paused fail-closed) and the staleness predicate must
    /// report stale so the executor can emit its loud warning. Staleness NEVER
    /// resumes — there is no anti-safety auto-clear here.
    #[tokio::test]
    async fn weather_verdict_stale_unsafe_stays_unsafe_and_is_detected() {
        let mut trigger = Trigger::new(
            "weather_unsafe",
            "Weather Unsafe",
            TriggerType::WeatherUnsafe,
            RecoveryAction::ParkAndAbort,
        );
        let mut state = TriggerState::new();
        // Hardware reads safe; only the Dart verdict asserts UNSAFE (the
        // rig-without-a-safety-device path).
        state.weather_safe = true;
        state.update_weather_verdict(Some(true));

        // Immediately after the push it is fresh: not stale, but still unsafe.
        assert!(
            !state.is_weather_verdict_stale_unsafe(60),
            "a just-pushed unsafe verdict must not be considered stale"
        );
        assert!(
            trigger.check(&state).await,
            "fresh unsafe verdict must fire (hold paused)"
        );

        // Force the push timestamp into the past so the verdict is now stale.
        // We do NOT touch `weather_verdict_unsafe` — staleness must not clear it.
        state.weather_verdict_last_update =
            Some(Instant::now() - std::time::Duration::from_secs(120));

        // Stale-AND-unsafe: predicate true with a 60s window.
        assert!(
            state.is_weather_verdict_stale_unsafe(60),
            "an unsafe verdict 120s old with a 60s window must read stale"
        );
        // CRITICAL: the trigger STILL fires — staleness holds paused, never resumes.
        assert!(
            state.weather_verdict_unsafe == Some(true),
            "staleness must NOT clear the unsafe verdict"
        );
        assert!(
            trigger.check(&state).await,
            "stale unsafe verdict must keep firing — no auto-resume on staleness"
        );

        // A fresh push (even abstain) clears the stale-unsafe condition.
        state.update_weather_verdict(None);
        assert!(
            !state.is_weather_verdict_stale_unsafe(60),
            "a fresh abstain push must clear the stale-unsafe condition"
        );
    }

    /// Subsystem 2 step 3: the staleness predicate is scoped to `Some(true)`
    /// only. A stale SAFE / abstaining verdict is harmless (nothing is held), and
    /// a never-pushed verdict has no feed to be stale — both must read NOT stale.
    #[tokio::test]
    async fn weather_verdict_staleness_only_applies_to_unsafe() {
        let mut state = TriggerState::new();

        // Never pushed -> no feed to be stale.
        assert!(
            !state.is_weather_verdict_stale_unsafe(0),
            "a never-pushed verdict cannot be stale"
        );

        // Stale SAFE verdict -> not stale-unsafe (nothing is being held).
        state.update_weather_verdict(Some(false));
        state.weather_verdict_last_update =
            Some(Instant::now() - std::time::Duration::from_secs(10_000));
        assert!(
            !state.is_weather_verdict_stale_unsafe(60),
            "a stale SAFE verdict must not read as stale-unsafe"
        );

        // Stale abstain -> not stale-unsafe.
        state.update_weather_verdict(None);
        state.weather_verdict_last_update =
            Some(Instant::now() - std::time::Duration::from_secs(10_000));
        assert!(
            !state.is_weather_verdict_stale_unsafe(60),
            "a stale abstain must not read as stale-unsafe"
        );
    }

    #[tokio::test]
    async fn test_temperature_shift_trigger() {
        let mut trigger = Trigger::new(
            "test",
            "Test Temperature Shift",
            TriggerType::TemperatureShift { degrees: 2.0 },
            RecoveryAction::Autofocus,
        );

        let mut state = TriggerState::new();
        state.baseline_temperature = Some(10.0);

        // Small change - should not trigger
        state.current_temperature = Some(11.0);
        assert!(!trigger.check(&state).await);

        // Large change - should trigger
        state.current_temperature = Some(13.0);
        assert!(trigger.check(&state).await);

        // Negative change - should also trigger
        state.current_temperature = Some(7.5);
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_temperature_shift_needs_a_drifting_source() {
        // Regression for the cooled-camera bug: the executor used to feed this
        // trigger from `camera_get_temperature`. A cooled camera is regulated
        // to a fixed setpoint, so its reading never drifts and the trigger
        // could never fire — focus walked soft over the night. The executor now
        // feeds `update_temperature` from the FOCUSER probe instead. This test
        // demonstrates the underlying contract the fix relies on: a constant
        // (regulated) feed never trips, while a drifting (focuser/ambient) feed
        // does once the delta exceeds the configured degrees.
        let mut trigger = Trigger::new(
            "test",
            "Temp Shift Source",
            TriggerType::TemperatureShift { degrees: 2.0 },
            RecoveryAction::Autofocus,
        );

        // Regulated camera sensor: held at -10.0°C all night. update_temperature
        // seeds the baseline from the first reading, then every reading equals
        // it, so the trigger NEVER fires no matter how many ticks elapse.
        let mut regulated = TriggerState::new();
        for _ in 0..100 {
            regulated.update_temperature(-10.0);
            assert!(
                !trigger.check(&regulated).await,
                "a regulated (constant) temperature source must never trip refocus"
            );
        }

        // Focuser/ambient probe: tracks the night cooling down. Baseline seeds
        // at 8.0°C; once the optical train cools past the 2.0° threshold the
        // trigger fires, requesting the refocus the regulated feed could not.
        let mut drifting = TriggerState::new();
        drifting.update_temperature(8.0);
        assert!(!trigger.check(&drifting).await, "delta 0 must not fire");
        drifting.update_temperature(6.5);
        assert!(!trigger.check(&drifting).await, "delta 1.5 below threshold");
        drifting.update_temperature(5.5);
        assert!(
            trigger.check(&drifting).await,
            "delta 2.5 above threshold must fire refocus from a drifting source"
        );
    }

    #[tokio::test]
    async fn test_trigger_cooldown() {
        let mut trigger = Trigger::new(
            "test",
            "Test Cooldown",
            TriggerType::HfrDegraded {
                threshold_percent: 20.0,
                absolute_threshold: 0.0,
                consecutive_frames: 1,
            },
            RecoveryAction::Autofocus,
        )
        .with_cooldown(2); // 2 second cooldown

        let mut state = TriggerState::new();
        state.baseline_hfr = Some(2.0);
        state.current_hfr = Some(2.5);

        // First check - should trigger
        assert!(trigger.check(&state).await);

        // Immediate second check - should not trigger (cooldown)
        assert!(!trigger.check(&state).await);

        // Wait for cooldown to expire
        tokio::time::sleep(Duration::from_secs(3)).await;

        // Should trigger again
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_trigger_manager() {
        let mut manager = TriggerManager::new();

        // Add some triggers
        manager.add_trigger(Trigger::new(
            "hfr",
            "HFR Monitor",
            TriggerType::HfrDegraded {
                threshold_percent: 25.0,
                absolute_threshold: 0.0,
                consecutive_frames: 1,
            },
            RecoveryAction::Autofocus,
        ));

        manager.add_trigger(Trigger::new(
            "altitude",
            "Altitude Limit",
            TriggerType::AltitudeLimit { min_altitude: 30.0 },
            RecoveryAction::NextTarget,
        ));

        // Set up trigger state
        {
            let state_lock = manager.state();
            let mut state = state_lock.write().await;
            state.baseline_hfr = Some(2.0);
            state.current_hfr = Some(2.6); // 30% increase - should trigger
            state.current_altitude = Some(25.0); // Below limit - should trigger
        }

        // Check all triggers
        let fired = manager.check_all().await;

        // Both triggers should have fired
        assert_eq!(fired.len(), 2);
        assert!(fired.iter().any(|(id, _)| id == "hfr"));
        assert!(fired.iter().any(|(id, _)| id == "altitude"));
    }

    #[tokio::test]
    async fn test_exposure_count_tracking() {
        let mut state = TriggerState::new();

        assert_eq!(state.completed_exposures, 0);
        assert_eq!(state.last_autofocus_frame, 0);
        assert_eq!(state.last_dither_frame, 0);

        // Simulate completing 10 exposures
        for _ in 0..10 {
            state.increment_exposure_count();
        }
        assert_eq!(state.completed_exposures, 10);

        // Perform autofocus
        state.mark_autofocus_performed();
        assert_eq!(state.last_autofocus_frame, 10);

        // Complete more exposures
        for _ in 0..5 {
            state.increment_exposure_count();
        }
        assert_eq!(state.completed_exposures, 15);

        // Perform dither
        state.mark_dither_performed();
        assert_eq!(state.last_dither_frame, 15);
    }

    #[tokio::test]
    async fn test_hfr_baseline_reset() {
        let mut state = TriggerState::new();

        // Initial HFR
        state.update_hfr(2.5);
        assert_eq!(state.baseline_hfr, Some(2.5));
        assert_eq!(state.current_hfr, Some(2.5));

        // HFR changes
        state.update_hfr(3.0);
        assert_eq!(state.baseline_hfr, Some(2.5)); // Baseline stays
        assert_eq!(state.current_hfr, Some(3.0));

        // Reset baseline
        state.reset_baseline_hfr();
        assert_eq!(state.baseline_hfr, Some(3.0)); // Baseline updated
        assert_eq!(state.current_hfr, Some(3.0));
    }

    // =========================================================================
    // OnTrackingLimitHit trigger tests
    // =========================================================================

    /// Helper to create a TriggerState simulating a mount that hit its tracking limit
    fn make_limit_hit_state() -> TriggerState {
        let mut state = TriggerState::new();
        state.mount_tracking_expected = true;
        state.mount_tracking_lost = true;
        state.mount_is_tracking = Some(false);
        state.mount_status_query_failed = false;
        state.mount_slewing = Some(false);
        state.mount_parked = Some(false);
        state.current_hour_angle = Some(1.5); // 1.5h past meridian
        state.pier_side = Some(PierSide::West); // Pre-flip side
        state.tracking_limit_detected_at = Some(chrono::Utc::now().timestamp() - 600); // 10 min ago
        state
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_immediate_flip() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 0.0, // Flip immediately
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Limit Hit",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let state = make_limit_hit_state();
        assert!(
            trigger.check(&state).await,
            "Should trigger immediately when wait is 0"
        );
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_with_wait_not_elapsed() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 5.0, // 5 min wait
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Limit Hit Wait",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = make_limit_hit_state();
        // Detected just 1 minute ago - wait hasn't elapsed
        state.tracking_limit_detected_at = Some(chrono::Utc::now().timestamp() - 60);
        assert!(
            !trigger.check(&state).await,
            "Should NOT trigger - wait period not elapsed"
        );
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_with_wait_elapsed() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 5.0, // 5 min wait
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Limit Hit Wait Elapsed",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = make_limit_hit_state();
        // Detected 10 minutes ago - well past the 5 min wait
        state.tracking_limit_detected_at = Some(chrono::Utc::now().timestamp() - 600);
        assert!(
            trigger.check(&state).await,
            "Should trigger - wait period elapsed"
        );
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_not_tracking_lost() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 0.0,
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Not Lost",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = make_limit_hit_state();
        state.mount_tracking_lost = false; // Tracking is fine
        assert!(
            !trigger.check(&state).await,
            "Should NOT trigger - tracking not lost"
        );
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_connection_lost() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 0.0,
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Disconnected",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = make_limit_hit_state();
        state.mount_status_query_failed = true; // Connection lost
        assert!(
            !trigger.check(&state).await,
            "Should NOT trigger - mount disconnected"
        );
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_wrong_pier_side() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 0.0,
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Wrong Pier",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = make_limit_hit_state();
        state.pier_side = Some(PierSide::East); // Already on post-flip side
        assert!(
            !trigger.check(&state).await,
            "Should NOT trigger - already on East side"
        );
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_negative_ha() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 0.0,
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Negative HA",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = make_limit_hit_state();
        state.current_hour_angle = Some(-2.0); // East of meridian
        assert!(
            !trigger.check(&state).await,
            "Should NOT trigger - target east of meridian"
        );
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_mount_slewing() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 0.0,
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Slewing",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = make_limit_hit_state();
        state.mount_slewing = Some(true); // Mount is slewing
        assert!(
            !trigger.check(&state).await,
            "Should NOT trigger - mount is slewing"
        );
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_already_flipped() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 0.0,
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Already Flipped",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = make_limit_hit_state();
        state.has_flipped_this_target = true; // Already flipped
        assert!(
            !trigger.check(&state).await,
            "Should NOT trigger - already flipped for target"
        );
    }

    #[tokio::test]
    async fn test_mount_tracking_lost_defers_to_limit_hit() {
        let mut trigger = Trigger::new(
            "test",
            "Test Tracking Lost Defers",
            TriggerType::MountTrackingLost,
            RecoveryAction::Pause,
        );

        let mut state = make_limit_hit_state();
        // Set OnTrackingLimitHit as the active method
        state.meridian_trigger_method = Some(crate::MeridianTriggerMethod::OnTrackingLimitHit);

        // Heuristic matches limit hit → MountTrackingLost should NOT fire
        assert!(
            !trigger.check(&state).await,
            "MountTrackingLost should defer to MeridianFlip when limit-hit heuristic matches"
        );
    }

    #[tokio::test]
    async fn test_mount_tracking_lost_fires_when_not_limit_hit() {
        let mut trigger = Trigger::new(
            "test",
            "Test Tracking Lost Fires",
            TriggerType::MountTrackingLost,
            RecoveryAction::Pause,
        );

        let mut state = TriggerState::new();
        state.mount_tracking_expected = true;
        state.mount_tracking_lost = true;
        state.meridian_trigger_method = Some(crate::MeridianTriggerMethod::OnTrackingLimitHit);
        // No HA data → heuristic fails → MountTrackingLost should fire
        assert!(
            trigger.check(&state).await,
            "MountTrackingLost should fire when heuristic doesn't match"
        );
    }

    #[tokio::test]
    async fn test_mount_tracking_lost_fires_with_different_trigger_method() {
        let mut trigger = Trigger::new(
            "test",
            "Test Tracking Lost Normal",
            TriggerType::MountTrackingLost,
            RecoveryAction::Pause,
        );

        let mut state = make_limit_hit_state();
        // Not using OnTrackingLimitHit → MountTrackingLost should fire normally
        state.meridian_trigger_method = Some(crate::MeridianTriggerMethod::MinutesPastMeridian);

        assert!(
            trigger.check(&state).await,
            "MountTrackingLost should fire normally when OnTrackingLimitHit is not active"
        );
    }

    #[tokio::test]
    async fn test_hfr_degraded_forces_autofocus_when_invalidated() {
        let mut trigger = Trigger::new(
            "test",
            "HFR Trigger",
            TriggerType::HfrDegraded {
                threshold_percent: 20.0,
                absolute_threshold: 0.0,
                consecutive_frames: 3,
            },
            RecoveryAction::Autofocus,
        );

        let mut state = TriggerState::new();
        state.invalidate_autofocus("binning changed");

        assert!(trigger.check(&state).await);
    }

    #[test]
    fn test_target_change_invalidates_autofocus() {
        let mut state = TriggerState::new();
        state.current_target_name = Some("M31".to_string());
        state.baseline_hfr = Some(2.0);
        state.current_hfr = Some(2.2);

        state.set_meridian_target("M42".to_string());

        assert!(state.autofocus_invalidated);
        assert_eq!(state.baseline_hfr, None);
    }

    #[test]
    fn test_filter_change_invalidates_autofocus() {
        let mut state = TriggerState::new();
        state.current_filter = Some("L".to_string());
        state.baseline_hfr = Some(2.0);
        state.current_hfr = Some(2.1);

        state.set_filter("Ha".to_string());

        assert!(state.filter_changed);
        assert!(state.autofocus_invalidated);
        assert_eq!(state.baseline_hfr, None);
    }

    #[tokio::test]
    async fn test_on_tracking_limit_hit_uses_limit_time_without_hour_angle() {
        let config = crate::MeridianFlipConfig {
            trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
            tracking_limit_wait_minutes: 0.0,
            ..Default::default()
        };
        let mut trigger = Trigger::new(
            "test",
            "Test Limit Time",
            TriggerType::MeridianFlip { config },
            RecoveryAction::MeridianFlip(crate::MeridianFlipConfig::default()),
        );

        let mut state = TriggerState::new();
        state.mount_tracking_expected = true;
        state.mount_tracking_lost = true;
        state.mount_is_tracking = Some(false);
        state.mount_status_query_failed = false;
        state.mount_slewing = Some(false);
        state.mount_parked = Some(false);
        state.mount_tracking_limit_time = Some(Utc::now().timestamp() - 5);

        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn test_tracking_limit_reset_on_tracking_resume() {
        let mut state = make_limit_hit_state();
        assert!(state.tracking_limit_detected_at.is_some());
        assert!(state.mount_tracking_lost);

        state.reset_tracking_limit_detection();
        assert!(state.tracking_limit_detected_at.is_none());
        assert!(!state.mount_tracking_lost);
    }

    /// Audit §1.9: a flip moves the mount from one pier side to the other,
    /// `mark_flip_performed` records the *origin* side, and a subsequent
    /// observed return to the origin side must clear `has_flipped_this_target`
    /// so a second flip is allowed for the same long-running target.
    #[tokio::test]
    async fn audit_1_9_pier_side_return_clears_flipped_flag() {
        let mut state = TriggerState::new();
        state.set_meridian_target("M101".to_string());

        // Pre-flip: mount on West side.
        state.update_pier_side(PierSide::West);
        assert!(!state.has_flipped_this_target);

        // Flip happens — pier side now reads East. The executor publishes
        // pier-side first, then calls mark_flip_performed (this is the live
        // sequence in `meridian_flip_executor::execute`'s success path).
        state.update_pier_side(PierSide::East);
        state.mark_flip_performed();
        assert!(state.has_flipped_this_target);
        assert_eq!(state.flip_origin_pier_side, Some(PierSide::West));

        // Some time later the mount returns to the original (West) side.
        // The §1.9 invariant clears the flag so the trigger can fire again.
        state.update_pier_side(PierSide::West);
        assert!(
            !state.has_flipped_this_target,
            "has_flipped_this_target must clear when the mount returns to the pre-flip side"
        );
        assert_eq!(state.flip_origin_pier_side, None);
    }

    /// Audit §1.9: pier side `Unknown` must NOT clear the flag (it is not
    /// authoritative evidence of a return-to-origin).
    #[tokio::test]
    async fn audit_1_9_unknown_pier_side_does_not_clear_flipped_flag() {
        let mut state = TriggerState::new();
        state.set_meridian_target("NGC 6888".to_string());
        state.update_pier_side(PierSide::West);
        state.update_pier_side(PierSide::East);
        state.mark_flip_performed();
        assert!(state.has_flipped_this_target);

        state.update_pier_side(PierSide::Unknown);
        assert!(
            state.has_flipped_this_target,
            "Unknown pier side must keep the flag latched until a real reading arrives"
        );
    }

    /// Audit §1.11: DriftLimit fires when accumulated plate-solve drift
    /// exceeds the configured pixel budget. With a 30 px budget and a
    /// (40, 30) drift the quadrature sum is 50 px and the trigger must fire.
    #[tokio::test]
    async fn audit_1_11_drift_limit_fires_when_drift_exceeds_threshold() {
        let mut trigger = Trigger::new(
            "test_drift",
            "Test Drift",
            TriggerType::DriftLimit { max_pixels: 30.0 },
            RecoveryAction::Recenter,
        );
        let mut state = TriggerState::new();
        // Target at RA=0deg, Dec=0deg — keeps the cos(dec) factor predictable.
        state.set_target(0.0, 0.0);
        // Pixel scale 1 arcsec/pixel so RA drift in arcsec equals pixels.
        // RA = 40/3600 deg drift, Dec = 30/3600 deg drift -> 40 px / 30 px.
        state.update_plate_solve(40.0 / 3600.0, 30.0 / 3600.0, 1.0);
        let drift = state.calculate_drift_pixels().expect("drift available");
        // Verify the helper math before exercising the trigger.
        assert!((drift.0 - 40.0).abs() < 0.001);
        assert!((drift.1 - 30.0).abs() < 0.001);
        assert!(trigger.check(&state).await, "drift 50 px must exceed 30 px");
    }

    /// Audit §1.11: DriftLimit must NOT fire below the budget (3 px drift
    /// against a 30 px budget — quadrature sum stays well under).
    #[tokio::test]
    async fn audit_1_11_drift_limit_does_not_fire_below_threshold() {
        let mut trigger = Trigger::new(
            "test_drift",
            "Test Drift",
            TriggerType::DriftLimit { max_pixels: 30.0 },
            RecoveryAction::Recenter,
        );
        let mut state = TriggerState::new();
        state.set_target(0.0, 0.0);
        state.update_plate_solve(2.0 / 3600.0, 2.0 / 3600.0, 1.0);
        assert!(!trigger.check(&state).await);
    }

    /// Audit §1.11: with no plate-solve recorded the trigger evaluator
    /// returns false (not error / not silent fire).
    #[tokio::test]
    async fn audit_1_11_drift_limit_inactive_without_plate_solve() {
        let mut trigger = Trigger::new(
            "test_drift",
            "Test Drift",
            TriggerType::DriftLimit { max_pixels: 30.0 },
            RecoveryAction::Recenter,
        );
        let state = TriggerState::new();
        assert!(!trigger.check(&state).await);
    }

    /// Audit §1.5: the standard-trigger builder now creates a
    /// `DitherInterval` trigger so periodic dithering is honoured even when
    /// the sequence does not contain an explicit Dither node. The standard
    /// `DriftLimit` trigger is also registered for §1.11.
    #[tokio::test]
    async fn audit_1_5_and_1_11_standard_triggers_include_new_audit_triggers() {
        let mut manager = TriggerManager::new();
        manager.create_standard_triggers();
        let names: Vec<String> = manager.triggers().iter().map(|t| t.id.clone()).collect();
        assert!(
            names.contains(&"dither_interval".to_string()),
            "DitherInterval standard trigger missing — audit §1.5 regression. ids: {:?}",
            names
        );
        assert!(
            names.contains(&"drift_limit".to_string()),
            "DriftLimit standard trigger missing — audit §1.11 regression. ids: {:?}",
            names
        );
    }

    /// Trust-patch §3: AutofocusInterval is now part of the standard
    /// trigger set so periodic refocus fires in sequences that lack an
    /// explicit Autofocus node. Symmetric with the §1.5 DitherInterval test.
    #[tokio::test]
    async fn trust_patch_3_standard_triggers_include_autofocus_interval() {
        let mut manager = TriggerManager::new();
        manager.create_standard_triggers();
        let names: Vec<String> = manager.triggers().iter().map(|t| t.id.clone()).collect();
        assert!(
            names.contains(&"autofocus_interval".to_string()),
            "AutofocusInterval standard trigger missing — trust-patch §3 regression. ids: {:?}",
            names
        );
    }

    /// Trust-patch §6: HumidityThreshold trigger fires when state.current_humidity
    /// exceeds the configured threshold and stays inactive when below.
    #[tokio::test]
    async fn trust_patch_2_humidity_threshold_fires_above_max_percent() {
        let mut trigger = Trigger::new(
            "humidity",
            "Humidity Threshold",
            TriggerType::HumidityThreshold { max_percent: 85.0 },
            RecoveryAction::Pause,
        );
        let mut state = TriggerState::new();

        // No humidity reading -> trigger stays inactive
        assert!(!trigger.check(&state).await);

        // Below threshold -> inactive
        state.update_humidity(70.0);
        assert!(!trigger.check(&state).await);

        // Above threshold -> fires
        state.update_humidity(90.0);
        assert!(trigger.check(&state).await);
    }

    /// Trust-patch §6: FocusDrift trigger uses VecDeque so trimming is O(1)
    /// and the window stays bounded.
    #[tokio::test]
    async fn trust_patch_6_focus_drift_window_uses_vecdeque_and_is_bounded() {
        let mut trigger = Trigger::new(
            "focus_drift",
            "Focus Drift",
            TriggerType::FocusDrift {
                window_size: 5,
                min_increasing_count: 3,
                min_total_increase: 0.3,
            },
            RecoveryAction::Autofocus,
        );

        let mut state = TriggerState::new();
        // Feed monotonically increasing HFR values to force a trip:
        // window will hold the last 5 of these.
        for hfr in [1.0_f64, 1.2, 1.4, 1.6, 1.9, 2.3, 2.7] {
            state.current_hfr = Some(hfr);
            // No assertion on intermediate state — the trigger may or may
            // not have fired by now; what matters is the window cap.
            let _ = trigger.check(&state).await;
        }

        // Window must not exceed configured size.
        assert!(
            trigger.focus_drift_hfr_window.len() <= 5,
            "FocusDrift window {} exceeded configured size 5",
            trigger.focus_drift_hfr_window.len()
        );
    }

    /// Trust-patch §6: `Trigger::new_focus_drift_checked` rejects oversize
    /// windows up-front (instead of silently clamping the way `new` does
    /// for stored sequences).
    #[test]
    fn trust_patch_6_focus_drift_checked_rejects_oversize_windows() {
        let err = Trigger::new_focus_drift_checked(
            "fd",
            "FD",
            FOCUS_DRIFT_WINDOW_MAX + 1,
            5,
            0.5,
            RecoveryAction::Autofocus,
        )
        .expect_err("oversize window must be rejected");
        assert!(err.contains("exceeds maximum"), "error message: {}", err);
    }

    /// Trust-patch §6: `Trigger::new` clamps oversize windows silently with
    /// a tracing warning so a checkpoint-restored sequence with a stale
    /// window still loads.
    #[test]
    fn trust_patch_6_focus_drift_new_clamps_oversize_windows() {
        let trigger = Trigger::new(
            "fd",
            "FD",
            TriggerType::FocusDrift {
                window_size: FOCUS_DRIFT_WINDOW_MAX * 2,
                min_increasing_count: 5,
                min_total_increase: 0.5,
            },
            RecoveryAction::Autofocus,
        );
        match trigger.trigger_type {
            TriggerType::FocusDrift { window_size, .. } => {
                assert_eq!(
                    window_size, FOCUS_DRIFT_WINDOW_MAX,
                    "Trigger::new must clamp oversize FocusDrift windows to FOCUS_DRIFT_WINDOW_MAX"
                );
            }
            _ => panic!("expected FocusDrift trigger_type after construction"),
        }
        // Wave 1.5 Pack A: clamp must also populate the visible diagnostic so
        // the executor can surface it on start (ExecutorEvent::Error).
        let warning = trigger
            .clamp_warning
            .as_ref()
            .expect("clamp_warning must be populated when window was clamped");
        assert_eq!(warning.field, "FocusDrift.window_size");
        assert_eq!(warning.original, FOCUS_DRIFT_WINDOW_MAX * 2);
        assert_eq!(warning.clamped_to, FOCUS_DRIFT_WINDOW_MAX);
    }

    /// Wave 1.5 Pack A: when no clamping occurs, `clamp_warning` must be None
    /// so the executor doesn't emit spurious clamp errors for healthy
    /// configurations.
    #[test]
    fn wave_1_5_focus_drift_below_cap_has_no_clamp_warning() {
        let trigger = Trigger::new(
            "fd",
            "FD",
            TriggerType::FocusDrift {
                window_size: 5,
                min_increasing_count: 3,
                min_total_increase: 0.5,
            },
            RecoveryAction::Autofocus,
        );
        assert!(
            trigger.clamp_warning.is_none(),
            "clamp_warning must be None for healthy FocusDrift windows"
        );
    }

    /// Audit §1.21: the GuidingFailed standard trigger ships
    /// `rms_retention_secs = default_guiding_rms_retention_secs()` (300s)
    /// and `TriggerManager::sync_state_from_config` propagates that value
    /// into the shared trigger state on every check_all. A user-tuned value
    /// flows through without a sequence reload.
    #[tokio::test]
    async fn audit_1_21_guiding_rms_retention_propagates_via_sync() {
        let mut manager = TriggerManager::new();
        manager.create_standard_triggers();

        // Find the GuidingFailed trigger and bump its retention.
        let trigger = manager
            .get_trigger_mut("guiding_failed")
            .expect("standard guiding_failed trigger registered");
        if let TriggerType::GuidingFailed {
            rms_retention_secs, ..
        } = &mut trigger.trigger_type
        {
            *rms_retention_secs = 600;
        } else {
            panic!("guiding_failed trigger must be GuidingFailed variant");
        }

        // Synchronise — would be called from check_all in production.
        manager.sync_state_from_config().await;
        let state = manager.state();
        let guard = state.read().await;
        assert_eq!(
            guard.guiding_rms_retention_secs, 600,
            "sync_state_from_config must push rms_retention_secs into TriggerState"
        );
    }

    // =========================================================================
    // Wave 5 Agent 4 — cloud-motion-aware trigger tests
    // =========================================================================

    /// CloudArrivingIn fires when both the arrival-time AND coverage gates
    /// are satisfied. Without coverage data the trigger stays quiescent.
    #[tokio::test]
    async fn wave_5_cloud_arriving_in_fires_when_both_gates_satisfied() {
        let mut trigger = Trigger::new(
            "test_cloud_arriving",
            "Test Cloud Arriving",
            TriggerType::CloudArrivingIn {
                minutes_before: 10.0,
                coverage_threshold: 70.0,
            },
            RecoveryAction::PauseAndWaitForClear,
        );
        let mut state = TriggerState::new();

        // No data => no fire.
        assert!(!trigger.check(&state).await);

        // Far away clouds (30 min) but high coverage => no fire (time gate).
        state.update_cloud_motion(Some(80.0), Some(30.0), None, None, None);
        assert!(!trigger.check(&state).await);

        // Reset & close clouds but low coverage => no fire (coverage gate).
        let mut trigger2 = Trigger::new(
            "test_cloud_arriving_2",
            "Test Cloud Arriving 2",
            TriggerType::CloudArrivingIn {
                minutes_before: 10.0,
                coverage_threshold: 70.0,
            },
            RecoveryAction::PauseAndWaitForClear,
        );
        let mut state2 = TriggerState::new();
        state2.update_cloud_motion(Some(50.0), Some(8.0), None, None, None);
        assert!(!trigger2.check(&state2).await);

        // Both gates satisfied => fire.
        let mut trigger3 = Trigger::new(
            "test_cloud_arriving_3",
            "Test Cloud Arriving 3",
            TriggerType::CloudArrivingIn {
                minutes_before: 10.0,
                coverage_threshold: 70.0,
            },
            RecoveryAction::PauseAndWaitForClear,
        );
        let mut state3 = TriggerState::new();
        state3.update_cloud_motion(Some(85.0), Some(8.0), None, None, None);
        assert!(trigger3.check(&state3).await);
    }

    /// CloudOpeningIn requires the opening to be both within the lead time
    /// AND of at-least the configured minimum duration.
    #[tokio::test]
    async fn wave_5_cloud_opening_in_requires_lead_time_and_duration() {
        let mut trigger = Trigger::new(
            "test_cloud_opening",
            "Test Cloud Opening",
            TriggerType::CloudOpeningIn {
                minutes_before: 5.0,
                minimum_duration_secs: 300.0,
            },
            RecoveryAction::Continue,
        );
        let mut state = TriggerState::new();

        // No data => no fire.
        assert!(!trigger.check(&state).await);

        // Opening in 10 min (too far) but 600s duration => no fire.
        state.update_cloud_motion(Some(80.0), None, Some(10.0), Some(600.0), None);
        assert!(!trigger.check(&state).await);

        // Reset & opening in 3 min but 100s duration (too short) => no fire.
        let mut trigger2 = Trigger::new(
            "test_cloud_opening_2",
            "Test Cloud Opening 2",
            TriggerType::CloudOpeningIn {
                minutes_before: 5.0,
                minimum_duration_secs: 300.0,
            },
            RecoveryAction::Continue,
        );
        let mut state2 = TriggerState::new();
        state2.update_cloud_motion(Some(80.0), None, Some(3.0), Some(100.0), None);
        assert!(!trigger2.check(&state2).await);

        // Both gates satisfied => fire.
        let mut trigger3 = Trigger::new(
            "test_cloud_opening_3",
            "Test Cloud Opening 3",
            TriggerType::CloudOpeningIn {
                minutes_before: 5.0,
                minimum_duration_secs: 300.0,
            },
            RecoveryAction::Continue,
        );
        let mut state3 = TriggerState::new();
        state3.update_cloud_motion(Some(80.0), None, Some(3.0), Some(600.0), None);
        assert!(trigger3.check(&state3).await);

        // Duration unknown => refuse to fire (CLAUDE.md silent-fallback rule).
        let mut trigger4 = Trigger::new(
            "test_cloud_opening_4",
            "Test Cloud Opening 4",
            TriggerType::CloudOpeningIn {
                minutes_before: 5.0,
                minimum_duration_secs: 300.0,
            },
            RecoveryAction::Continue,
        );
        let mut state4 = TriggerState::new();
        state4.update_cloud_motion(Some(80.0), None, Some(3.0), None, None);
        assert!(!trigger4.check(&state4).await);
    }

    /// CloudCoverThreshold honours the per-trigger debounce: a single sample
    /// above the threshold does not fire until `duration_secs` has elapsed.
    #[tokio::test]
    async fn wave_5_cloud_cover_threshold_debounces() {
        let mut trigger = Trigger::new(
            "test_cover_threshold",
            "Test Cover Threshold",
            TriggerType::CloudCoverThreshold {
                max_percent: 50.0,
                duration_secs: 60.0,
            },
            RecoveryAction::Pause,
        );
        let mut state = TriggerState::new();

        // Below threshold => no arm.
        state.update_cloud_motion(Some(20.0), None, None, None, None);
        assert!(!trigger.check(&state).await);
        assert!(trigger.cloud_cover_above_threshold_since.is_none());

        // First above-threshold sample arms the debounce timer.
        state.update_cloud_motion(Some(80.0), None, None, None, None);
        assert!(!trigger.check(&state).await);
        assert!(trigger.cloud_cover_above_threshold_since.is_some());

        // duration_secs=0 should fire immediately on the first sample.
        let mut trigger_no_debounce = Trigger::new(
            "test_cover_immediate",
            "Test Cover Immediate",
            TriggerType::CloudCoverThreshold {
                max_percent: 50.0,
                duration_secs: 0.0,
            },
            RecoveryAction::Pause,
        );
        let mut state2 = TriggerState::new();
        state2.update_cloud_motion(Some(80.0), None, None, None, None);
        assert!(trigger_no_debounce.check(&state2).await);
    }

    /// Cover dropping back below the threshold must reset the debounce
    /// timer — otherwise a flapping cover would eventually fire after the
    /// total elapsed time crossed the threshold.
    #[tokio::test]
    async fn wave_5_cloud_cover_threshold_resets_on_drop() {
        let mut trigger = Trigger::new(
            "test_cover_reset",
            "Test Cover Reset",
            TriggerType::CloudCoverThreshold {
                max_percent: 50.0,
                duration_secs: 60.0,
            },
            RecoveryAction::Pause,
        );
        let mut state = TriggerState::new();

        // Above threshold arms.
        state.update_cloud_motion(Some(80.0), None, None, None, None);
        assert!(!trigger.check(&state).await);
        let armed_at = trigger.cloud_cover_above_threshold_since;
        assert!(armed_at.is_some());

        // Drop below threshold clears the arm.
        state.update_cloud_motion(Some(20.0), None, None, None, None);
        assert!(!trigger.check(&state).await);
        assert!(trigger.cloud_cover_above_threshold_since.is_none());
    }

    /// Trigger respects the per-Trigger cooldown after firing.
    #[tokio::test]
    async fn wave_5_cloud_arriving_respects_cooldown() {
        let mut trigger = Trigger::new(
            "test_cooldown",
            "Test Cooldown",
            TriggerType::CloudArrivingIn {
                minutes_before: 10.0,
                coverage_threshold: 70.0,
            },
            RecoveryAction::PauseAndWaitForClear,
        )
        .with_cooldown(60);
        let mut state = TriggerState::new();
        state.update_cloud_motion(Some(85.0), Some(8.0), None, None, None);
        assert!(trigger.check(&state).await);
        // Cooldown should suppress the second fire.
        assert!(!trigger.check(&state).await);
    }

    /// `update_cloud_motion` rejects NaN / Inf and clamps cover to [0,100].
    #[tokio::test]
    async fn wave_5_update_cloud_motion_sanitises_inputs() {
        let mut state = TriggerState::new();
        state.update_cloud_motion(Some(150.0), Some(-5.0), None, None, None);
        assert_eq!(state.current_cloud_coverage_percent, Some(100.0));
        assert_eq!(state.predicted_cloud_arrival_minutes, Some(0.0));

        state.update_cloud_motion(Some(f64::NAN), Some(f64::INFINITY), None, None, None);
        assert_eq!(
            state.current_cloud_coverage_percent, None,
            "NaN cover must produce None"
        );
        assert_eq!(
            state.predicted_cloud_arrival_minutes, None,
            "Inf arrival must produce None"
        );
    }

    /// JSON round-trip for the three new TriggerType variants.
    #[test]
    fn wave_5_cloud_trigger_types_round_trip_through_serde() {
        for original in [
            TriggerType::CloudArrivingIn {
                minutes_before: 12.5,
                coverage_threshold: 65.0,
            },
            TriggerType::CloudOpeningIn {
                minutes_before: 4.0,
                minimum_duration_secs: 420.0,
            },
            TriggerType::CloudCoverThreshold {
                max_percent: 75.0,
                duration_secs: 30.0,
            },
        ] {
            let json = serde_json::to_string(&original).expect("serialize");
            let back: TriggerType = serde_json::from_str(&json).expect("deserialize");
            // We compare via the round-tripped JSON because TriggerType
            // doesn't implement PartialEq.
            let back_json = serde_json::to_string(&back).expect("re-serialize");
            assert_eq!(json, back_json, "trigger type JSON must round-trip");
        }
    }

    /// JSON round-trip for the two new RecoveryAction variants.
    #[test]
    fn wave_5_cloud_recovery_actions_round_trip_through_serde() {
        for original in [
            RecoveryAction::PauseAndWaitForClear,
            RecoveryAction::SlewToGapAndContinue,
        ] {
            let json = serde_json::to_string(&original).expect("serialize");
            let back: RecoveryAction = serde_json::from_str(&json).expect("deserialize");
            let back_json = serde_json::to_string(&back).expect("re-serialize");
            assert_eq!(json, back_json, "recovery action JSON must round-trip");
        }
    }

    // =============================================================
    // Wave 7 Science — TransparencyDropped trigger tests.
    // =============================================================

    #[tokio::test]
    async fn wave_7_transparency_dropped_fires_below_threshold_immediately() {
        let mut trigger = Trigger::new(
            "test_transparency_immediate",
            "Test Transparency Immediate",
            TriggerType::TransparencyDropped {
                below_threshold: 0.7,
                // duration_secs = 0.0 => fire on the first sample below
                // threshold (matches `CloudCoverThreshold` semantics).
                duration_secs: 0.0,
            },
            RecoveryAction::SwitchTargetOrFilter,
        );
        let mut state = TriggerState::new();

        // Above threshold => no fire, no arm.
        state.update_transparency(Some(0.95));
        assert!(!trigger.check(&state).await);
        assert!(trigger.transparency_below_threshold_since.is_none());

        // Below threshold + duration=0 => fires immediately.
        state.update_transparency(Some(0.5));
        assert!(trigger.check(&state).await);
    }

    #[tokio::test]
    async fn wave_7_transparency_dropped_debounces() {
        let mut trigger = Trigger::new(
            "test_transparency_debounce",
            "Test Transparency Debounce",
            TriggerType::TransparencyDropped {
                below_threshold: 0.7,
                duration_secs: 60.0,
            },
            RecoveryAction::SwitchTargetOrFilter,
        );
        let mut state = TriggerState::new();

        // First below-threshold sample arms but does NOT fire.
        state.update_transparency(Some(0.5));
        assert!(!trigger.check(&state).await);
        assert!(trigger.transparency_below_threshold_since.is_some());

        // Drop back above threshold => arm cleared, no fire.
        state.update_transparency(Some(0.9));
        assert!(!trigger.check(&state).await);
        assert!(trigger.transparency_below_threshold_since.is_none());
    }

    #[tokio::test]
    async fn wave_7_transparency_dropped_handles_missing_data() {
        let mut trigger = Trigger::new(
            "test_transparency_no_data",
            "Test Transparency No Data",
            TriggerType::TransparencyDropped {
                below_threshold: 0.7,
                duration_secs: 0.0,
            },
            RecoveryAction::SwitchTargetOrFilter,
        );
        let mut state = TriggerState::new();

        // No transparency telemetry yet — must NOT fire (CLAUDE.md "no
        // silent fallbacks": absent data is not a trigger condition).
        assert!(!trigger.check(&state).await);
        assert!(trigger.transparency_below_threshold_since.is_none());

        // After Dart pushes None (lock lost), still no fire.
        state.update_transparency(None);
        assert!(!trigger.check(&state).await);
    }

    #[test]
    fn wave_7_update_transparency_drops_non_finite() {
        let mut state = TriggerState::new();
        state.update_transparency(Some(f64::NAN));
        assert_eq!(state.current_transparency, None);
        state.update_transparency(Some(f64::INFINITY));
        assert_eq!(state.current_transparency, None);
        // Valid values flow through.
        state.update_transparency(Some(0.6));
        assert_eq!(state.current_transparency, Some(0.6));
    }
}
