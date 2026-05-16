//! Meridian Flip Calculations
//!
//! This module provides astronomical calculations for determining when a target
//! crosses the meridian and when a meridian flip should be performed.

use chrono::{DateTime, Datelike, Timelike, Utc};

/// Pier side enumeration for German Equatorial Mounts
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PierSide {
    /// Mount is on the east side of the pier (pointing west)
    East,
    /// Mount is on the west side of the pier (pointing east)
    West,
    /// Unknown pier side (mount doesn't support reporting)
    Unknown,
}

/// Calculate when a target crosses the meridian
///
/// # Arguments
/// * `ra_hours` - Target's Right Ascension in hours (0-24)
/// * `longitude` - Observer's longitude in degrees (west is negative)
/// * `current_time` - Current UTC time
///
/// # Returns
/// The UTC DateTime when the target will cross the meridian
pub fn calculate_meridian_crossing(
    ra_hours: f64,
    longitude: f64,
    current_time: DateTime<Utc>,
) -> DateTime<Utc> {
    // Calculate Julian Day for current time
    let jd = julian_day(&current_time);

    // Calculate Local Sidereal Time
    let lst = local_sidereal_time(jd, longitude);

    // Target crosses meridian when LST = RA
    // Calculate time difference
    let mut time_to_crossing = ra_hours - lst;

    // Normalize to 0-24 hour range
    if time_to_crossing < 0.0 {
        time_to_crossing += 24.0;
    }
    if time_to_crossing > 24.0 {
        time_to_crossing -= 24.0;
    }

    // Convert sidereal hours to solar seconds
    // 1 sidereal hour = 0.99726957 solar hours = 3589.77 solar seconds
    let sidereal_to_solar = 0.99726957;
    let solar_hours = time_to_crossing * sidereal_to_solar;
    // Why (audit-rust §1.4): `time_to_crossing` is normalized to [0, 24]
    // hours by the loop above; `solar_hours * 3600` is therefore ≤ ~86400.
    // Rust 1.45+ defines f64 → i64 as saturating-on-overflow / 0-on-NaN,
    // which for a bounded sidereal interval is the desired behavior.
    let seconds = (solar_hours * 3600.0).round() as i64;

    current_time + chrono::Duration::seconds(seconds)
}

/// Calculate the hour angle for a target
///
/// # Arguments
/// * `ra_hours` - Target's Right Ascension in hours
/// * `lst_hours` - Local Sidereal Time in hours
///
/// # Returns
/// Hour angle in hours, normalized to the range -12 to +12
/// Negative values indicate the target is east of the meridian (approaching)
/// Positive values indicate the target is west of the meridian (past meridian)
pub fn hour_angle(ra_hours: f64, lst_hours: f64) -> f64 {
    let mut ha = lst_hours - ra_hours;

    // Normalize to -12 to +12 range
    while ha < -12.0 {
        ha += 24.0;
    }
    while ha > 12.0 {
        ha -= 24.0;
    }

    ha
}

/// Calculate when a meridian flip should occur based on a trigger threshold
///
/// # Arguments
/// * `ra_hours` - Target's Right Ascension in hours
/// * `longitude` - Observer's longitude in degrees
/// * `current_time` - Current UTC time
/// * `minutes_past_meridian` - How many minutes past the meridian to wait before flipping
///
/// # Returns
/// The UTC DateTime when the flip should be triggered
pub fn calculate_flip_time(
    ra_hours: f64,
    longitude: f64,
    current_time: DateTime<Utc>,
    minutes_past_meridian: f64,
) -> DateTime<Utc> {
    let meridian_crossing = calculate_meridian_crossing(ra_hours, longitude, current_time);
    // Why (audit-rust §1.4): `minutes_past_meridian` is a configured
    // threshold in minutes (UI surfaces 0..~30 typically). f64 → i64 uses
    // Rust 1.45+ saturating semantics; for any sane threshold the result
    // is well inside i64 range.
    meridian_crossing + chrono::Duration::seconds((minutes_past_meridian * 60.0) as i64)
}

/// Check if a mount needs to flip based on hour angle and flip threshold
///
/// # Arguments
/// * `ra_hours` - Target's Right Ascension in hours
/// * `longitude` - Observer's longitude in degrees
/// * `current_time` - Current UTC time
/// * `minutes_past_meridian` - Threshold in minutes past meridian to trigger flip
///
/// # Returns
/// `true` if the mount should flip now, `false` otherwise
pub fn should_flip_now(
    ra_hours: f64,
    longitude: f64,
    current_time: DateTime<Utc>,
    minutes_past_meridian: f64,
) -> bool {
    let jd = julian_day(&current_time);
    let lst = local_sidereal_time(jd, longitude);
    let ha = hour_angle(ra_hours, lst);

    // Flip when hour angle exceeds the threshold (in hours)
    let threshold_hours = minutes_past_meridian / 60.0;
    ha >= threshold_hours
}

/// Determine which side of the pier the mount should be on for a given hour angle
///
/// # Arguments
/// * `hour_angle_hours` - Hour angle in hours
///
/// # Returns
/// The expected pier side based on optimal positioning
pub fn expected_pier_side(hour_angle_hours: f64) -> PierSide {
    if hour_angle_hours < 0.0 {
        // Target is east of meridian, mount should be on east side (pointing west)
        PierSide::East
    } else {
        // Target is west of meridian, mount should be on west side (pointing east)
        PierSide::West
    }
}

/// Calculate altitude for a target at a given time
///
/// # Arguments
/// * `ra_hours` - Right Ascension in hours
/// * `dec_degrees` - Declination in degrees
/// * `latitude` - Observer's latitude in degrees
/// * `longitude` - Observer's longitude in degrees
/// * `time` - UTC time
///
/// # Returns
/// Altitude in degrees above the horizon
pub fn calculate_altitude(
    ra_hours: f64,
    dec_degrees: f64,
    latitude: f64,
    longitude: f64,
    time: DateTime<Utc>,
) -> f64 {
    let jd = julian_day(&time);
    let lst = local_sidereal_time(jd, longitude);
    let ha = hour_angle(ra_hours, lst);

    // Convert to radians
    let ha_rad = (ha * 15.0).to_radians(); // Convert hours to degrees, then to radians
    let dec_rad = dec_degrees.to_radians();
    let lat_rad = latitude.to_radians();

    // Calculate altitude using the altitude formula
    let sin_alt = lat_rad.sin() * dec_rad.sin() + lat_rad.cos() * dec_rad.cos() * ha_rad.cos();

    sin_alt.asin().to_degrees()
}

/// Calculate Julian Day from UTC DateTime
pub fn julian_day(dt: &DateTime<Utc>) -> f64 {
    let year = dt.year();
    // Why (audit-rust §1.4): `month()` returns u32 in [1, 12]; u32 → i32
    // is SAFE narrowing (12 << i32::MAX). Subsequent arithmetic uses i32.
    let month = dt.month() as i32;
    // Why (audit-rust §1.4): `day()` returns u32 in [1, 31]; u32 → f64
    // exact widening.
    let day = f64::from(dt.day());
    // Why (audit-rust §1.4): hour/minute/second all u32 in small ranges;
    // u32 → f64 exact widening.
    let hour =
        f64::from(dt.hour()) + f64::from(dt.minute()) / 60.0 + f64::from(dt.second()) / 3600.0;

    let (y, m) = if month <= 2 {
        (year - 1, month + 12)
    } else {
        (year, month)
    };

    // Why (audit-rust §1.4): `y` is i32 calendar year (calendrically bounded
    // by chrono::DateTime to ~[-262_144, 262_143]); i32 → f64 exact.
    let a = (f64::from(y) / 100.0).floor();
    let b = 2.0 - a + (a / 4.0).floor();

    // Why (audit-rust §1.4): same i32 → f64 exact widening as `a` above.
    (365.25 * (f64::from(y) + 4716.0)).floor()
        + (30.6001 * (f64::from(m) + 1.0)).floor()
        + day
        + hour / 24.0
        + b
        - 1524.5
}

/// Calculate Local Sidereal Time in hours
pub fn local_sidereal_time(jd: f64, longitude: f64) -> f64 {
    let t = (jd - 2451545.0) / 36525.0;

    // Greenwich Mean Sidereal Time in degrees
    let gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t
        - t * t * t / 38710000.0;

    // Add longitude to get Local Sidereal Time
    let lst = (gmst + longitude) % 360.0;

    // Convert to hours and normalize

    if lst < 0.0 {
        (lst + 360.0) / 15.0
    } else {
        lst / 15.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn test_hour_angle_calculation() {
        // When LST = 12h and RA = 12h, HA should be 0 (on meridian)
        assert!((hour_angle(12.0, 12.0) - 0.0).abs() < 0.001);

        // When LST = 13h and RA = 12h, HA should be +1h (1h past meridian)
        assert!((hour_angle(12.0, 13.0) - 1.0).abs() < 0.001);

        // When LST = 11h and RA = 12h, HA should be -1h (1h before meridian)
        assert!((hour_angle(12.0, 11.0) + 1.0).abs() < 0.001);

        // Test wraparound: LST = 23h and RA = 1h, HA should be -2h
        assert!((hour_angle(1.0, 23.0) + 2.0).abs() < 0.001);
    }

    #[test]
    fn test_hour_angle_normalization() {
        // Test that hour angle is normalized to -12 to +12 range
        let ha = hour_angle(0.0, 15.0);
        assert!((-12.0..=12.0).contains(&ha));

        let ha2 = hour_angle(20.0, 5.0);
        assert!((-12.0..=12.0).contains(&ha2));
    }

    #[test]
    fn test_expected_pier_side() {
        // Target east of meridian (HA < 0) should be on east side of pier
        assert_eq!(expected_pier_side(-1.0), PierSide::East);
        assert_eq!(expected_pier_side(-5.0), PierSide::East);

        // Target west of meridian (HA > 0) should be on west side of pier
        assert_eq!(expected_pier_side(1.0), PierSide::West);
        assert_eq!(expected_pier_side(5.0), PierSide::West);

        // Exactly on meridian (HA = 0) should be west side (just flipped)
        assert_eq!(expected_pier_side(0.0), PierSide::West);
    }

    #[test]
    fn test_should_flip_now() {
        // Create a test time
        let test_time = Utc.with_ymd_and_hms(2025, 3, 15, 0, 0, 0).unwrap();

        // For a target at RA = 12h, longitude = -75.0 (Eastern US)
        // Calculate LST at this time
        let jd = julian_day(&test_time);
        let lst = local_sidereal_time(jd, -75.0);

        // Set RA slightly behind LST (just past meridian)
        let ra_hours = lst - 0.1; // 6 minutes past meridian (0.1 hours)

        // Should flip if threshold is less than 6 minutes
        assert!(should_flip_now(ra_hours, -75.0, test_time, 5.0));

        // Should not flip if threshold is more than 6 minutes
        assert!(!should_flip_now(ra_hours, -75.0, test_time, 10.0));
    }

    #[test]
    fn test_meridian_crossing_in_future() {
        let test_time = Utc.with_ymd_and_hms(2025, 3, 15, 12, 0, 0).unwrap();

        // For any RA and longitude, crossing time should be within next 24 hours
        let crossing = calculate_meridian_crossing(10.0, -75.0, test_time);
        let duration = crossing.signed_duration_since(test_time);

        // Should be positive (in future) and less than 24 hours
        assert!(duration.num_seconds() > 0);
        assert!(duration.num_seconds() < 86400);
    }

    #[test]
    fn test_flip_time_calculation() {
        let test_time = Utc.with_ymd_and_hms(2025, 3, 15, 12, 0, 0).unwrap();

        // Calculate flip time for 5 minutes past meridian
        let crossing = calculate_meridian_crossing(10.0, -75.0, test_time);
        let flip_time = calculate_flip_time(10.0, -75.0, test_time, 5.0);

        // Flip time should be 5 minutes after crossing
        let diff = flip_time.signed_duration_since(crossing);
        assert_eq!(diff.num_seconds(), 300); // 5 minutes = 300 seconds
    }

    #[test]
    fn test_altitude_calculation() {
        // Test altitude for a known configuration
        // Object at RA=12h, Dec=45°, from latitude 45°N
        let test_time = Utc.with_ymd_and_hms(2025, 3, 21, 12, 0, 0).unwrap(); // Vernal equinox noon

        let alt = calculate_altitude(12.0, 45.0, 45.0, 0.0, test_time);

        // Altitude should be reasonable (between 0 and 90 degrees)
        assert!((0.0..=90.0).contains(&alt));
    }

    #[test]
    fn test_julian_day_epoch() {
        // J2000 epoch: January 1, 2000, 12:00 TT (approximately 11:58:56 UTC)
        let j2000 = Utc.with_ymd_and_hms(2000, 1, 1, 12, 0, 0).unwrap();
        let jd = julian_day(&j2000);

        // Should be very close to 2451545.0
        assert!((jd - 2451545.0).abs() < 0.01);
    }
}
