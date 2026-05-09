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

                    // Check absolute threshold (if configured > 0)
                    let exceeds_absolute =
                        *absolute_threshold > 0.0 && current > *absolute_threshold;

                    // Check relative threshold (percentage above baseline)
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

                    // HFR is "bad" if either threshold is exceeded
                    let is_bad = exceeds_absolute || exceeds_relative;

                    // Track consecutive bad frames
                    if is_bad {
                        self.hfr_bad_frame_count += 1;
                    } else {
                        self.hfr_bad_frame_count = 0;
                    }

                    // Only trigger after required consecutive bad frames
                    let required = (*consecutive_frames).max(1);
                    self.hfr_bad_frame_count >= required
                }
            }
            TriggerType::MeridianFlip { config } => {
                // Don't trigger if we've already flipped for this target
                if state.has_flipped_this_target {
                    return false;
                }

                // Need to know the current hour angle for the primary trigger methods
                match config.trigger_method {
                    crate::MeridianTriggerMethod::MinutesPastMeridian => {
                        // Trigger when target is past meridian by specified minutes
                        // Hour angle > 0 means west of meridian (past meridian for northern hemisphere)
                        if let Some(ha) = state.current_hour_angle {
                            // Convert hour angle to minutes (1h = 60min)
                            let minutes_past = ha * 60.0;
                            // Trigger when positive HA exceeds threshold (target past meridian)
                            // and we're on the pre-flip pier side (typically West when target is East)
                            let on_pre_flip_side = match state.pier_side {
                                Some(PierSide::West) => ha > 0.0, // Target has crossed
                                Some(PierSide::East) => false,    // Already flipped
                                _ => ha > 0.0,                    // Unknown - use HA sign
                            };
                            on_pre_flip_side && minutes_past >= config.minutes_past_meridian
                        } else {
                            false
                        }
                    }
                    crate::MeridianTriggerMethod::MinutesBeforeLimit => {
                        // Trigger based on time until mount hits its tracking limit
                        // This requires the mount to report its limit time.
                        // Do not estimate from hour-angle heuristics.
                        if let Some(limit_time) = state.mount_tracking_limit_time {
                            let now = chrono::Utc::now().timestamp();
                            let minutes_to_limit = (limit_time - now) as f64 / 60.0;
                            // Trigger when we're within the threshold of hitting the limit
                            minutes_to_limit > 0.0
                                && minutes_to_limit <= config.minutes_before_limit
                        } else {
                            false
                        }
                    }
                    crate::MeridianTriggerMethod::HourAngleThreshold => {
                        // Trigger when absolute hour angle exceeds threshold
                        if let Some(ha) = state.current_hour_angle {
                            // Use the threshold directly (configured in hours)
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

                        // Heuristic passed: this looks like a tracking limit hit.
                        // Check if a wait period is configured.
                        if config.tracking_limit_wait_minutes > 0.0 {
                            if let Some(detected_at) = state.tracking_limit_detected_at {
                                let elapsed_secs = chrono::Utc::now().timestamp() - detected_at;
                                let wait_secs = (config.tracking_limit_wait_minutes * 60.0) as i64;
                                if elapsed_secs < wait_secs {
                                    tracing::trace!(
                                        "Tracking limit hit: waiting {}/{}s before flip (HA={:.2}h)",
                                        elapsed_secs,
                                        wait_secs,
                                        state.current_hour_angle.unwrap_or_default()
                                    );
                                    return false;
                                }
                                tracing::info!(
                                    "Tracking limit wait elapsed ({:.1} min), triggering meridian flip (HA={:.2}h)",
                                    config.tracking_limit_wait_minutes,
                                    state.current_hour_angle.unwrap_or_default()
                                );
                            } else {
                                // No timestamp yet - wait for executor to record it on next poll
                                return false;
                            }
                        } else {
                            tracing::info!(
                                "Tracking limit hit detected, triggering immediate meridian flip (HA={:.2}h, pier={:?})",
                                state.current_hour_angle.unwrap_or_default(),
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
            } => {
                if let Some(rms_history) = &state.guiding_rms_history {
                    // Check if RMS has been above threshold for duration
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
                // Dawn time should be pre-calculated when observer location is set
                if let Some(dawn_time) = state.dawn_time {
                    let now = chrono::Utc::now().timestamp();
                    let time_to_dawn = (dawn_time - now) as f64 / 60.0;
                    // Trigger if dawn is within minutes_before (positive means dawn hasn't happened)
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

                // If OnTrackingLimitHit is the active meridian trigger method, check whether
                // this tracking loss looks like a limit hit. If so, defer to the MeridianFlip
                // trigger instead of pausing the sequence.
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

                // Genuine tracking loss (error condition)
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
                // Fire when guiding is enabled/expected but the guider reports no star
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

                // Add new sample to the rolling window
                self.focus_drift_hfr_window.push(current);

                // Trim window to configured size
                let max_size = (*window_size).max(2);
                while self.focus_drift_hfr_window.len() > max_size {
                    self.focus_drift_hfr_window.remove(0);
                }

                // Need at least min_increasing_count samples to detect a trend
                let min_count = (*min_increasing_count).max(2);
                if self.focus_drift_hfr_window.len() < min_count {
                    return false;
                }

                // Check for monotonically increasing run at the end of the window.
                // Walk backwards from the end to find the longest increasing suffix.
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

                // Check that the total increase is above the threshold
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
    let day_of_year = today.ordinal() as f64;
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
#[derive(Debug, Clone, Default)]
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

    pub fn update_guiding_rms(&mut self, rms: f64) {
        if self.guiding_rms_history.is_none() {
            self.guiding_rms_history = Some(Vec::new());
        }

        if let Some(history) = &mut self.guiding_rms_history {
            history.push((Instant::now(), rms));

            // Keep only last 5 minutes of history
            history.retain(|(time, _)| time.elapsed().as_secs() < 300);
        }
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

        // Calculate angular separation in arcseconds
        let ra_diff_deg = solve_ra - target_ra;
        let dec_diff_deg = solve_dec - target_dec;

        // Convert to arcseconds
        // For RA, account for declination (RA coordinates get closer at poles)
        let dec_rad = target_dec.to_radians();
        let ra_arcsec = ra_diff_deg * 3600.0 * dec_rad.cos();
        let dec_arcsec = dec_diff_deg * 3600.0;

        // Convert arcseconds to pixels
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

        // Center the grid around (0,0): offset = (position - center) * step_size
        // Step size = pixels / (n-1) if n>1, otherwise 0
        let (ra_offset, dec_offset) = if n > 1 {
            let step = pixels * 2.0 / (n - 1) as f64;
            let center = (n - 1) as f64 / 2.0;
            let ra = (col as f64 - center) * step;
            let dec = (row as f64 - center) * step;
            (ra, dec)
        } else {
            (0.0, 0.0)
        };

        // Advance to next position
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

    /// Update the current pier side
    pub fn update_pier_side(&mut self, pier_side: PierSide) {
        self.pier_side = Some(pier_side);
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
            self.has_flipped_this_target = false;
            if let Some(previous) = previous {
                self.invalidate_autofocus(format!("target changed from {}", previous));
            }
        }
    }

    /// Mark that a meridian flip has been performed for the current target
    pub fn mark_flip_performed(&mut self) {
        self.has_flipped_this_target = true;
        tracing::info!(
            "[MERIDIAN] Flip marked as completed for target: {:?}",
            self.current_target_name
        );
    }

    /// Clear meridian flip state (call when target changes or sequence resets)
    pub fn clear_meridian_state(&mut self) {
        self.current_hour_angle = None;
        self.pier_side = None;
        self.mount_tracking_limit_time = None;
        self.has_flipped_this_target = false;
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

    /// Create standard triggers
    pub fn create_standard_triggers(&mut self) {
        // HFR degradation trigger
        self.add_trigger(
            Trigger::new(
                "hfr_degraded",
                "HFR Degradation",
                TriggerType::HfrDegraded {
                    threshold_percent: 20.0,
                    absolute_threshold: 0.0, // disabled by default; users set from UI
                    consecutive_frames: 3,   // require 3 bad frames to avoid seeing spikes
                },
                RecoveryAction::Autofocus,
            )
            .with_cooldown(300), // 5 minute cooldown
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
            .with_cooldown(600), // 10 minute cooldown to prevent double-flip
        );

        // Guiding failure trigger
        self.add_trigger(
            Trigger::new(
                "guiding_failed",
                "Guiding Failure",
                TriggerType::GuidingFailed {
                    rms_threshold: 2.0,
                    duration_secs: 30.0,
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
            .with_cooldown(0), // No cooldown for safety
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

        // Focus drift detection trigger
        self.add_trigger(
            Trigger::new(
                "focus_drift",
                "Focus Drift",
                TriggerType::FocusDrift {
                    window_size: 10,
                    min_increasing_count: 5,
                    min_total_increase: 0.5, // 0.5 pixel/arcsec total increase over the run
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
}
