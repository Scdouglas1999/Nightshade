//! Trigger system for the sequencer

use crate::{PierSide, RecoveryAction, TriggerType};
use chrono::{NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

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
    /// Rolling window of HFR values for FocusDrift detection.
    /// Stores recent HFR measurements to detect monotonic upward trends.
    #[serde(skip)]
    pub focus_drift_hfr_window: Vec<f64>,
}

impl Trigger {
    /// Create a new trigger
    pub fn new(
        id: impl Into<String>,
        name: impl Into<String>,
        trigger_type: TriggerType,
        recovery_action: RecoveryAction,
    ) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            trigger_type,
            recovery_action,
            enabled: true,
            cooldown_secs: None,
            last_triggered: None,
            hfr_bad_frame_count: 0,
            focus_drift_hfr_window: Vec::new(),
        }
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

                    let required = (*consecutive_frames).max(1);
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
            TriggerType::WeatherUnsafe => !state.weather_safe,
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

                self.focus_drift_hfr_window.push(current);

                // `.max(2)` guards against a misconfigured window of 0 or 1 —
                // a single sample cannot show a trend, so the math below would
                // panic on the run-start subtraction.
                let max_size = (*window_size).max(2);
                while self.focus_drift_hfr_window.len() > max_size {
                    self.focus_drift_hfr_window.remove(0);
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
                let total_increase = window.last().unwrap() - window[run_start];
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

    // Guiding
    pub guiding_rms_history: Option<Vec<(Instant, f64)>>,
    pub guiding_enabled: bool,
    /// Whether the guide star has been lost (guider reports no star / lost lock)
    pub guide_star_lost: bool,
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
    pub weather_safe: bool,

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
}

impl Default for TriggerState {
    fn default() -> Self {
        Self {
            baseline_hfr: None,
            current_hfr: None,
            autofocus_invalidated: false,
            autofocus_invalidation_reason: None,
            current_hour_angle: None,
            pier_side: None,
            mount_tracking_limit_time: None,
            has_flipped_this_target: false,
            current_target_name: None,
            next_meridian_flip_time: None,
            guiding_rms_history: None,
            guiding_enabled: false,
            guide_star_lost: false,
            // Audit §1.21: 300s preserves the previous hardcoded retention so
            // un-configured triggers behave exactly as before.
            guiding_rms_retention_secs: 300,
            flip_origin_pier_side: None,
            current_humidity: None,
            current_altitude: None,
            weather_safe: false,
            baseline_temperature: None,
            current_temperature: None,
            baseline_focuser_position: None,
            filter_changed: false,
            current_filter: None,
            dawn_time: None,
            observer_latitude: None,
            observer_longitude: None,
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

    /// Update current humidity reading
    pub fn update_humidity(&mut self, humidity: f64) {
        self.current_humidity = Some(humidity);
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
        for trigger in &self.triggers {
            if !trigger.enabled {
                continue;
            }
            if let TriggerType::GuidingFailed {
                rms_retention_secs, ..
            } = &trigger.trigger_type
            {
                retention = Some(*rms_retention_secs);
                break;
            }
        }
        if let Some(secs) = retention {
            let mut state = self.state.write().await;
            if state.guiding_rms_retention_secs != secs {
                state.set_guiding_rms_retention_secs(secs);
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

        // Humidity threshold trigger
        self.add_trigger(
            Trigger::new(
                "humidity_threshold",
                "Humidity Threshold",
                TriggerType::HumidityThreshold { max_percent: 85.0 },
                RecoveryAction::Pause, // Pause (not abort) - humidity may drop again
            )
            .with_cooldown(60), // 60 second cooldown
        );

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

        // No change - should not trigger
        state.current_hfr = Some(2.0);
        assert!(!trigger.check(&state).await);

        // 10% increase - should not trigger
        state.current_hfr = Some(2.2);
        assert!(!trigger.check(&state).await);

        // 25% increase - should trigger (consecutive_frames=1, so immediate)
        state.current_hfr = Some(2.5);
        assert!(trigger.check(&state).await);
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
        state.current_hfr = Some(3.0);
        assert!(!trigger.check(&state).await);

        // Above absolute threshold - should trigger
        state.current_hfr = Some(4.0);
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
        state.current_hfr = Some(4.0);
        assert!(!trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 1);

        // Frame 2: bad - still not enough
        assert!(!trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 2);

        // Frame 3: bad - now should trigger
        assert!(trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 3);

        // Reset: good frame resets counter
        state.current_hfr = Some(2.0);
        trigger.hfr_bad_frame_count = 0; // Reset after trigger fired
        assert!(!trigger.check(&state).await);
        assert_eq!(trigger.hfr_bad_frame_count, 0);

        // One bad frame after reset - not enough
        state.current_hfr = Some(4.0);
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
}
