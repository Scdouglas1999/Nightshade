//! Annual aberration — Polaris at Earth perihelion vs JPL/DE405 (ERFA `epv00`) reference.

use nightshade_planetarium::astrometry::aberration::{
    annual_aberration_offset_arcsec, earth_heliocentric_velocity_equatorial_au_per_day,
    SPEED_OF_LIGHT_AU_PER_DAY,
};
use nightshade_planetarium::astrometry::time::AstroTime;

/// Earth perihelion season: 2000-01-03 00:00 UTC (TT ≈ +64.184 s on that epoch).
const JD_UTC_PERIHELION_2000: f64 = 2_451_559.5;

/// ICRS J2000 Polaris (α UMi / HIP 11767, SIMBAD).
const POLARIS_RA_DEG: f64 = 37.952_936_42;
const POLARIS_DEC_DEG: f64 = 89.264_109_44;

/// ERFA `epv00` (DE405) annual aberration offset at `JD_TT` below (arcseconds).
const JPL_DRA_ARCSEC: f64 = 5.287_555_742_376_241;
const JPL_DDEC_ARCSEC: f64 = 19.797_098_862_511_575;

/// Task 23 acceptance: VSOP87-derived velocity vs JPL/DE405 to < 1″.
const TOL_ARCSEC: f64 = 1.0;

#[test]
fn polaris_aberration_at_perihelion_within_one_arcsec_of_jpl() {
    let time = AstroTime::from_jd_utc(JD_UTC_PERIHELION_2000);
    let ra = POLARIS_RA_DEG.to_radians();
    let dec = POLARIS_DEC_DEG.to_radians();
    let (dra, ddec) = annual_aberration_offset_arcsec(ra, dec, time.jd_tt);

    assert!(
        (dra - JPL_DRA_ARCSEC).abs() < TOL_ARCSEC,
        "ΔRA {dra:.6}″ (JPL {JPL_DRA_ARCSEC:.6}″), |Δ| = {:.6}″",
        (dra - JPL_DRA_ARCSEC).abs()
    );
    assert!(
        (ddec - JPL_DDEC_ARCSEC).abs() < TOL_ARCSEC,
        "ΔDec {ddec:.6}″ (JPL {JPL_DDEC_ARCSEC:.6}″), |Δ| = {:.6}″",
        (ddec - JPL_DDEC_ARCSEC).abs()
    );

    let total = (dra * dra + ddec * ddec).sqrt();
    assert!(
        (total - 20.491).abs() < 0.5,
        "total aberration {total:.3}″ (expected ~20.5″)"
    );
}

#[test]
fn earth_heliocentric_speed_near_perihelion() {
    let time = AstroTime::from_jd_utc(JD_UTC_PERIHELION_2000);
    let v = earth_heliocentric_velocity_equatorial_au_per_day(time.jd_tt);
    let speed = v.length();
    assert!(
        speed > 0.0170 && speed < 0.0180,
        "Earth heliocentric speed {speed} AU/day"
    );
    let beta_arcsec = (speed / SPEED_OF_LIGHT_AU_PER_DAY) * (180.0 * 3_600.0 / std::f64::consts::PI);
    assert!(
        (beta_arcsec - 20.83).abs() < 0.15,
        "β magnitude {beta_arcsec:.3}″"
    );
}
