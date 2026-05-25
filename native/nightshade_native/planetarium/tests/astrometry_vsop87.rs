//! VSOP87D Sun and planets — truncated series vs Task 27 acceptance epoch.

use nightshade_planetarium::astrometry::time::AstroTime;
use nightshade_planetarium::astrometry::vsop87::{
    heliocentric_ecliptic, sun_equatorial_rad, sun_geocentric_ecliptic, VsopBody,
    DAYS_PER_JULIAN_MILLENNIUM, VSOP87_J2000_JD,
};

/// 2000-01-01 00:00:00 UTC (Meeus JD; matches `time::jd_utc_midnight(2000, 1, 1)`).
const JD_UTC_2000_JAN_1: f64 = 2_451_544.5;

/// ~5′ tolerance on RA (minutes of right ascension) and Dec (arcminutes).
const TOL_RA_MIN: f64 = 5.0;
const TOL_DEC_ARCMIN: f64 = 5.0;

/// Task 27 nominal Sun equatorial coordinates on 2000-01-01 (geocentric, J2000 equator).
const EXP_SUN_RA_HOURS: f64 = 18.0 + 45.0 / 60.0;
const EXP_SUN_DEC_DEG: f64 = -23.0;

#[test]
fn sun_2000_jan_01_ra_dec_within_five_arcmin() {
    let time = AstroTime::from_jd_utc(JD_UTC_2000_JAN_1);
    let (ra_rad, dec_rad) = sun_equatorial_rad(time.jd_tt);
    let ra_hours = ra_rad * 12.0 / std::f64::consts::PI;
    let dec_deg = dec_rad.to_degrees();

    let ra_diff_min = (ra_hours - EXP_SUN_RA_HOURS).abs() * 60.0;
    let dec_diff_arcmin = (dec_deg - EXP_SUN_DEC_DEG).abs() * 60.0;

    assert!(
        ra_diff_min < TOL_RA_MIN,
        "RA {ra_hours:.4} h (expected ~{EXP_SUN_RA_HOURS:.4} h), Δ = {ra_diff_min:.2} min (limit {TOL_RA_MIN})"
    );
    assert!(
        dec_diff_arcmin < TOL_DEC_ARCMIN,
        "Dec {dec_deg:.4}° (expected ~{EXP_SUN_DEC_DEG}°), Δ = {dec_diff_arcmin:.2}′ (limit {TOL_DEC_ARCMIN})"
    );
}

#[test]
fn sun_geocentric_distance_near_one_au() {
    let t = (AstroTime::from_jd_utc(JD_UTC_2000_JAN_1).jd_tt - VSOP87_J2000_JD)
        / DAYS_PER_JULIAN_MILLENNIUM;
    let sun = sun_geocentric_ecliptic(t);
    assert!(
        (sun.distance_au - 0.983).abs() < 0.02,
        "Sun distance {au} AU (expected ~0.98 AU near perihelion season)",
        au = sun.distance_au
    );
}

#[test]
fn earth_heliocentric_distance_near_one_au() {
    let t = (AstroTime::from_jd_utc(JD_UTC_2000_JAN_1).jd_tt - VSOP87_J2000_JD)
        / DAYS_PER_JULIAN_MILLENNIUM;
    let earth = heliocentric_ecliptic(VsopBody::Earth, t);
    assert!(
        (earth.distance_au - 0.983).abs() < 0.02,
        "Earth heliocentric r = {} AU",
        earth.distance_au
    );
}

#[test]
fn jupiter_heliocentric_distance_plausible() {
    let t = (AstroTime::from_jd_utc(JD_UTC_2000_JAN_1).jd_tt - VSOP87_J2000_JD)
        / DAYS_PER_JULIAN_MILLENNIUM;
    let jupiter = heliocentric_ecliptic(VsopBody::Jupiter, t);
    assert!(
        jupiter.distance_au > 4.5 && jupiter.distance_au < 6.5,
        "Jupiter heliocentric r = {} AU",
        jupiter.distance_au
    );
}
