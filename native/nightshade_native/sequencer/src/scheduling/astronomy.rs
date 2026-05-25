//! Astronomy primitives mirrored from `astronomy_calculations.dart`.
//!
//! Only the calls the scheduler needs are ported: `objectAltAz`,
//! `angularSeparation`, `airmass`, `calculateObjectVisibility`. The formulae,
//! constants, and conventions are byte-for-byte copies of the Dart source so
//! the parity test in `scoring::tests` can assert numeric equality.

use chrono::{DateTime, Datelike, Timelike, Utc};

const DEG2RAD: f64 = std::f64::consts::PI / 180.0;
const RAD2DEG: f64 = 180.0 / std::f64::consts::PI;
const EPSILON: f64 = 1e-12;
const J2000: f64 = 2_451_545.0;

/// Julian Date for the given UTC instant.
///
/// Mirrors `AstronomyCalculations.julianDate` from `astronomy_calculations.dart`.
pub fn julian_date(dt: &DateTime<Utc>) -> f64 {
    let y = dt.year() as f64;
    let m = dt.month() as f64;
    let day = dt.day() as f64
        + (dt.hour() as f64) / 24.0
        + (dt.minute() as f64) / 1440.0
        + (dt.second() as f64) / 86_400.0
        + (dt.timestamp_subsec_millis() as f64) / 86_400_000.0;

    let a = ((14.0 - m) / 12.0).floor();
    let y2 = y + 4800.0 - a;
    let m2 = m + 12.0 * a - 3.0;

    day + ((153.0 * m2 + 2.0) / 5.0).floor() + 365.0 * y2 + (y2 / 4.0).floor()
        - (y2 / 100.0).floor()
        + (y2 / 400.0).floor()
        - 32_045.0
        - 0.5
}

/// Greenwich Mean Sidereal Time in decimal hours.
pub fn greenwich_mean_sidereal_time(dt: &DateTime<Utc>) -> f64 {
    let jd = julian_date(dt);
    let t = (jd - J2000) / 36_525.0;
    let mut gmst = 280.460_618_37 + 360.985_647_366_29 * (jd - J2000) + 0.000_387_933 * t * t
        - t * t * t / 38_710_000.0;

    gmst = gmst.rem_euclid(360.0);
    gmst / 15.0
}

/// Local Sidereal Time in decimal hours.
pub fn local_sidereal_time(dt: &DateTime<Utc>, longitude_deg: f64) -> f64 {
    let gmst = greenwich_mean_sidereal_time(dt);
    let lst = gmst + longitude_deg / 15.0;
    lst.rem_euclid(24.0)
}

/// Convert equatorial RA/Dec to horizontal Alt/Az using the given latitude
/// and LST. Returns `(altitude_deg, azimuth_deg)`.
pub fn equatorial_to_horizontal(
    ra_deg: f64,
    dec_deg: f64,
    latitude_deg: f64,
    lst_hours: f64,
) -> (f64, f64) {
    let ha = (lst_hours * 15.0 - ra_deg) * DEG2RAD;
    let dec = dec_deg * DEG2RAD;
    let lat = latitude_deg * DEG2RAD;

    let sin_alt = dec.sin() * lat.sin() + dec.cos() * lat.cos() * ha.cos();
    let alt = sin_alt.clamp(-1.0, 1.0).asin();

    let y = -ha.sin() * dec.cos();
    let x = dec.sin() * lat.cos() - dec.cos() * lat.sin() * ha.cos();
    let mut az = y.atan2(x);
    if az < 0.0 {
        az += 2.0 * std::f64::consts::PI;
    }

    (alt * RAD2DEG, az * RAD2DEG)
}

/// `objectAltAz` — RA in DEGREES (consistent with Dart). Returns
/// `(altitude_deg, azimuth_deg)`.
pub fn object_alt_az(
    ra_deg: f64,
    dec_deg: f64,
    dt: &DateTime<Utc>,
    latitude_deg: f64,
    longitude_deg: f64,
) -> (f64, f64) {
    let lst = local_sidereal_time(dt, longitude_deg);
    equatorial_to_horizontal(ra_deg, dec_deg, latitude_deg, lst)
}

/// Pickering (2002) airmass formula.
///
/// Returns `f64::INFINITY` for `altitude_deg <= 0`, matching the Dart
/// behaviour.
pub fn airmass(altitude_deg: f64) -> f64 {
    if altitude_deg <= 0.0 {
        return f64::INFINITY;
    }
    let h = altitude_deg;
    1.0 / ((h + 244.0 / (165.0 + 47.0 * h.powf(1.1))) * DEG2RAD).sin()
}

/// Angular separation between two sky positions (degrees).
pub fn angular_separation(ra1_deg: f64, dec1_deg: f64, ra2_deg: f64, dec2_deg: f64) -> f64 {
    let ra1 = ra1_deg * DEG2RAD;
    let dec1 = dec1_deg * DEG2RAD;
    let ra2 = ra2_deg * DEG2RAD;
    let dec2 = dec2_deg * DEG2RAD;

    let cos_sep = dec1.sin() * dec2.sin() + dec1.cos() * dec2.cos() * (ra1 - ra2).cos();
    cos_sep.clamp(-1.0, 1.0).acos() * RAD2DEG
}

/// Rise/transit/set times + transit altitude for a target.
///
/// Mirrors `AstronomyCalculations.calculateObjectVisibility`. Returns
/// `None` for fields that don't apply (circumpolar → no rise/set; never-rises
/// → no transit either).
#[derive(Debug, Clone)]
pub struct ObjectVisibility {
    pub rise_time: Option<DateTime<Utc>>,
    pub transit_time: Option<DateTime<Utc>>,
    pub set_time: Option<DateTime<Utc>>,
    pub transit_altitude: f64,
    pub is_circumpolar: bool,
    pub never_rises: bool,
}

pub fn calculate_object_visibility(
    ra_deg: f64,
    dec_deg: f64,
    date: &DateTime<Utc>,
    latitude_deg: f64,
    longitude_deg: f64,
    min_altitude: f64,
) -> ObjectVisibility {
    let local_noon = chrono::NaiveDate::from_ymd_opt(date.year(), date.month(), date.day())
        .and_then(|d| d.and_hms_opt(12, 0, 0))
        .map(|naive| DateTime::<Utc>::from_naive_utc_and_offset(naive, Utc))
        .unwrap_or(*date);

    let cos_dec = (dec_deg * DEG2RAD).cos();
    let sin_dec = (dec_deg * DEG2RAD).sin();
    let cos_lat = (latitude_deg * DEG2RAD).cos();
    let sin_lat = (latitude_deg * DEG2RAD).sin();
    let denominator = cos_dec * cos_lat;

    let transit_altitude = (90.0 - (latitude_deg - dec_deg).abs()).clamp(-90.0, 90.0);

    if denominator.abs() < EPSILON {
        let above_min = transit_altitude >= min_altitude;
        return ObjectVisibility {
            rise_time: None,
            transit_time: None,
            set_time: None,
            transit_altitude,
            is_circumpolar: above_min,
            never_rises: !above_min,
        };
    }

    let cos_h0 = ((min_altitude * DEG2RAD).sin() - sin_dec * sin_lat) / denominator;

    let mut is_circumpolar = false;
    let mut never_rises = false;
    if cos_h0 < -1.0 {
        is_circumpolar = true;
    } else if cos_h0 > 1.0 {
        never_rises = true;
    }

    let lst0 = local_sidereal_time(&local_noon, longitude_deg);
    let mut hours_till_transit = (ra_deg / 15.0) - lst0;
    if hours_till_transit < -12.0 {
        hours_till_transit += 24.0;
    }
    if hours_till_transit > 12.0 {
        hours_till_transit -= 24.0;
    }

    let transit_time =
        local_noon + chrono::Duration::seconds((hours_till_transit * 3600.0).round() as i64);

    let (rise_time, set_time) = if !is_circumpolar && !never_rises {
        let h0 = cos_h0.acos() * RAD2DEG / 15.0; // in hours
        let half = chrono::Duration::seconds((h0 * 3600.0).round() as i64);
        (Some(transit_time - half), Some(transit_time + half))
    } else {
        (None, None)
    };

    ObjectVisibility {
        rise_time,
        transit_time: Some(transit_time),
        set_time,
        transit_altitude,
        is_circumpolar,
        never_rises,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn airmass_zenith_is_one() {
        // Within 0.5% at zenith (formula is empirical, not a pure secant).
        let am = airmass(90.0);
        assert!((am - 1.0).abs() < 0.005, "got {am}");
    }

    #[test]
    fn airmass_below_horizon_is_infinity() {
        assert!(airmass(-1.0).is_infinite());
        assert!(airmass(0.0).is_infinite());
    }

    #[test]
    fn angular_separation_self_is_zero() {
        let sep = angular_separation(15.0, 30.0, 15.0, 30.0);
        assert!(sep < 1e-6);
    }

    #[test]
    fn angular_separation_pole_to_equator_is_ninety() {
        let sep = angular_separation(0.0, 90.0, 0.0, 0.0);
        assert!((sep - 90.0).abs() < 1e-6, "got {sep}");
    }
}
