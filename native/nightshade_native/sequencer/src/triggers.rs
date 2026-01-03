//! Trigger system for the sequencer

use crate::{RecoveryAction, TriggerType};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

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
            TriggerType::HfrDegraded { threshold_percent } => {
                if let (Some(baseline), Some(current)) = (state.baseline_hfr, state.current_hfr) {
                    let increase = (current - baseline) / baseline * 100.0;
                    increase > *threshold_percent
                } else {
                    false
                }
            }
            TriggerType::MeridianFlip { minutes_before } => {
                if let Some(flip_time) = state.next_meridian_flip_time {
                    let now = chrono::Utc::now().timestamp();
                    let time_to_flip = (flip_time - now) as f64 / 60.0;
                    time_to_flip > 0.0 && time_to_flip <= *minutes_before
                } else {
                    false
                }
            }
            TriggerType::GuidingFailed { rms_threshold, duration_secs } => {
                if let Some(rms_history) = &state.guiding_rms_history {
                    // Check if RMS has been above threshold for duration
                    let recent: Vec<_> = rms_history.iter()
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
                !state.weather_safe
            }
            TriggerType::TemperatureShift { degrees } => {
                if let (Some(baseline), Some(current)) = (state.baseline_temperature, state.current_temperature) {
                    (current - baseline).abs() > *degrees
                } else {
                    false
                }
            }
            TriggerType::FilterChange => {
                state.filter_changed
            }
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
                    let frames_since_af = state.completed_exposures - state.last_autofocus_frame;
                    frames_since_af >= *every_n_frames
                }
            }
            TriggerType::DitherInterval { every_n_frames } => {
                if state.completed_exposures == 0 || *every_n_frames == 0 {
                    false
                } else {
                    let frames_since_dither = state.completed_exposures - state.last_dither_frame;
                    frames_since_dither >= *every_n_frames
                }
            }
            TriggerType::MountTrackingLost => {
                state.mount_tracking_expected && state.mount_tracking_lost
            }
            TriggerType::DomeShutterNotOpen => {
                state.dome_shutter_open_expected &&
                state.dome_shutter_status.as_ref().map(|s| s != "Open").unwrap_or(false)
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
    use chrono::{Datelike, Utc};

    let now = Utc::now();
    let today = now.date_naive();

    // Sun altitude threshold for astronomical twilight (18 degrees below horizon)
    let altitude_threshold: f64 = -18.0;

    // Approximate solar declination using Cooper's equation
    let day_of_year = today.ordinal() as f64;
    let declination: f64 = 23.45 * (360.0_f64 * (284.0 + day_of_year) / 365.0).to_radians().sin();
    let dec_rad = declination.to_radians();
    let lat_rad = latitude.to_radians();
    let alt_rad = altitude_threshold.to_radians();

    // Calculate hour angle at astronomical twilight
    let cos_h = (alt_rad.sin() - lat_rad.sin() * dec_rad.sin()) / (lat_rad.cos() * dec_rad.cos());

    // Handle polar day/night
    let cos_h = cos_h.clamp(-1.0, 1.0);
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

    let dawn_datetime = today
        .and_hms_opt(dawn_hour, dawn_minutes, 0)
        .unwrap_or_else(|| today.and_hms_opt(6, 0, 0).unwrap());

    let dawn_timestamp = chrono::DateTime::<Utc>::from_naive_utc_and_offset(
        dawn_datetime,
        Utc,
    ).timestamp();

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

    // Meridian flip
    pub next_meridian_flip_time: Option<i64>,

    // Guiding
    pub guiding_rms_history: Option<Vec<(Instant, f64)>>,
    pub guiding_enabled: bool,

    // Altitude
    pub current_altitude: Option<f64>,

    // Weather
    pub weather_safe: bool,

    // Temperature
    pub baseline_temperature: Option<f64>,
    pub current_temperature: Option<f64>,

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
    pub target_ra: Option<f64>,  // Target RA in degrees
    pub target_dec: Option<f64>, // Target Dec in degrees

    // Mount tracking
    pub mount_is_tracking: Option<bool>,
    pub mount_tracking_expected: bool,
    pub mount_tracking_lost: bool,

    // Dome status
    pub dome_shutter_status: Option<String>,
    pub dome_shutter_open_expected: bool,
}

impl TriggerState {
    pub fn new() -> Self {
        Self {
            weather_safe: true,
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

    pub fn set_filter(&mut self, filter: String) {
        self.filter_changed = self.current_filter.as_ref() != Some(&filter);
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
                TriggerType::HfrDegraded { threshold_percent: 20.0 },
                RecoveryAction::Autofocus,
            ).with_cooldown(300) // 5 minute cooldown
        );

        // Meridian flip trigger
        self.add_trigger(
            Trigger::new(
                "meridian_flip",
                "Meridian Flip",
                TriggerType::MeridianFlip { minutes_before: 5.0 },
                RecoveryAction::Pause,
            ).with_cooldown(600) // 10 minute cooldown
        );

        // Guiding failure trigger
        self.add_trigger(
            Trigger::new(
                "guiding_failed",
                "Guiding Failure",
                TriggerType::GuidingFailed { rms_threshold: 2.0, duration_secs: 30.0 },
                RecoveryAction::Retry { max_attempts: 3 },
            ).with_cooldown(60)
        );

        // Altitude limit trigger
        self.add_trigger(
            Trigger::new(
                "altitude_limit",
                "Altitude Limit",
                TriggerType::AltitudeLimit { min_altitude: 30.0 },
                RecoveryAction::NextTarget,
            ).with_cooldown(60)
        );

        // Weather safety trigger
        self.add_trigger(
            Trigger::new(
                "weather_unsafe",
                "Weather Unsafe",
                TriggerType::WeatherUnsafe,
                RecoveryAction::ParkAndAbort,
            ).with_cooldown(0) // No cooldown for safety
        );

        // Temperature shift trigger
        self.add_trigger(
            Trigger::new(
                "temperature_shift",
                "Temperature Shift",
                TriggerType::TemperatureShift { degrees: 2.0 },
                RecoveryAction::Autofocus,
            ).with_cooldown(600)
        );

        // Filter change trigger (for focus offsets)
        self.add_trigger(
            Trigger::new(
                "filter_change",
                "Filter Change",
                TriggerType::FilterChange,
                RecoveryAction::Continue, // Handle via filter focus offsets
            ).with_cooldown(0)
        );

        // Dawn approaching trigger (automatic morning shutdown)
        self.add_trigger(
            Trigger::new(
                "dawn_approaching",
                "Dawn Approaching",
                TriggerType::DawnApproaching { minutes_before: 30.0 }, // 30 min before astronomical twilight
                RecoveryAction::ParkAndAbort,
            ).with_cooldown(0) // No cooldown for safety
        );

        // Mount tracking lost trigger
        self.add_trigger(
            Trigger::new(
                "mount_tracking_lost",
                "Mount Tracking Lost",
                TriggerType::MountTrackingLost,
                RecoveryAction::Pause,
            ).with_cooldown(60) // 60 second cooldown
        );

        // Dome shutter not open trigger
        self.add_trigger(
            Trigger::new(
                "dome_shutter_not_open",
                "Dome Shutter Not Open",
                TriggerType::DomeShutterNotOpen,
                RecoveryAction::ParkAndAbort,
            ).with_cooldown(0) // No cooldown for safety
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
    async fn test_hfr_trigger() {
        let mut trigger = Trigger::new(
            "test",
            "Test HFR",
            TriggerType::HfrDegraded { threshold_percent: 20.0 },
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

        // 25% increase - should trigger
        state.current_hfr = Some(2.5);
        assert!(trigger.check(&state).await);
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
        state.guiding_rms_history.as_mut().unwrap().push((std::time::Instant::now(), 2.8));

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
            TriggerType::HfrDegraded { threshold_percent: 20.0 },
            RecoveryAction::Autofocus,
        ).with_cooldown(2); // 2 second cooldown

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
            TriggerType::HfrDegraded { threshold_percent: 25.0 },
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
}
