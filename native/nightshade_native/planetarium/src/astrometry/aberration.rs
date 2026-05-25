//! Annual aberration via the SOFA `iauAb` special-relativistic formulation
//! from Earth's heliocentric velocity (VSOP87D Earth).
//!
//! Earth's velocity is obtained by symmetric numerical differentiation of the truncated
//! VSOP87D Earth heliocentric series (same coefficients as `vsop87`). The
//! Lorentz form ([`apply_annual_aberration_direction`]) is used instead of the
//! classical v/c addition: the difference at Earth's orbital speed is O(|v/c|²)
//! ≈ 2 µas, but the SOFA-matching form is the published reference and lets the
//! aberration regression tests target sub-millarcsecond agreement with `iauAb`.
//!
//! Diurnal aberration is omitted (visual planetarium scope).
//!

use glam::DVec3;

use crate::astrometry::vsop87::{
    heliocentric_ecliptic, julian_millennia_tt, VsopBody, DAYS_PER_JULIAN_MILLENNIUM,
    MEAN_OBLIQUITY_J2000_DEG, VSOP87_J2000_JD,
};

/// Speed of light (AU per day); IAU 2012 AU + exact c.
pub const SPEED_OF_LIGHT_AU_PER_DAY: f64 = 86_400.0 * 299_792_458.0 / 149_597_870_700.0;

/// Symmetric difference step for heliocentric velocity (days).
const VELOCITY_DT_DAYS: f64 = 1.0;

/// ICRS equatorial unit vector from right ascension and declination (radians).
#[inline]
pub fn direction_from_radec_rad(ra_rad: f64, dec_rad: f64) -> DVec3 {
    let (sin_dec, cos_dec) = dec_rad.sin_cos();
    let (sin_ra, cos_ra) = ra_rad.sin_cos();
    DVec3::new(cos_dec * cos_ra, cos_dec * sin_ra, sin_dec)
}

/// Right ascension and declination (radians) from an equatorial unit vector.
#[inline]
pub fn radec_from_direction(direction: DVec3) -> (f64, f64) {
    let d = direction.normalize();
    let dec = d.z.clamp(-1.0, 1.0).asin();
    let ra = d.y.atan2(d.x).rem_euclid(std::f64::consts::TAU);
    (ra, dec)
}

/// Mean obliquity of the ecliptic (radians) at `jd_tt`.
///
/// Linear IAU 2006 P03 approximation (Hilton/Capitaine 2006). See
/// `vsop87::mean_obliquity_deg` for the trade-off rationale; the full polynomial lives
/// in `astrometry::precession::mean_obliquity_from_julian_centuries_tt`.
#[inline]
fn mean_obliquity_rad(jd_tt: f64) -> f64 {
    let t = (jd_tt - VSOP87_J2000_JD) / 36_525.0;
    (MEAN_OBLIQUITY_J2000_DEG - 0.013_004_2 * t).to_radians()
}

#[inline]
fn ecliptic_rectangular(lon: f64, lat: f64, r: f64) -> DVec3 {
    let (sin_lon, cos_lon) = lon.sin_cos();
    let (sin_lat, cos_lat) = lat.sin_cos();
    DVec3::new(r * cos_lat * cos_lon, r * cos_lat * sin_lon, r * sin_lat)
}

#[inline]
fn ecliptic_vector_to_equatorial(v: DVec3, obliquity_rad: f64) -> DVec3 {
    let (sin_eps, cos_eps) = obliquity_rad.sin_cos();
    DVec3::new(
        v.x,
        v.y * cos_eps - v.z * sin_eps,
        v.y * sin_eps + v.z * cos_eps,
    )
}

/// Earth's heliocentric velocity in the J2000 ecliptic frame (AU/day).
pub fn earth_heliocentric_velocity_ecliptic_au_per_day(jd_tt: f64) -> DVec3 {
    let t = julian_millennia_tt(jd_tt);
    let dt_mill = VELOCITY_DT_DAYS / DAYS_PER_JULIAN_MILLENNIUM;
    let e_minus = heliocentric_ecliptic(VsopBody::Earth, t - dt_mill);
    let e_plus = heliocentric_ecliptic(VsopBody::Earth, t + dt_mill);
    let p_minus = ecliptic_rectangular(
        e_minus.longitude_rad,
        e_minus.latitude_rad,
        e_minus.distance_au,
    );
    let p_plus = ecliptic_rectangular(
        e_plus.longitude_rad,
        e_plus.latitude_rad,
        e_plus.distance_au,
    );
    (p_plus - p_minus) / (2.0 * VELOCITY_DT_DAYS)
}

/// Earth's heliocentric velocity in the J2000 equatorial frame (AU/day).
#[inline]
pub fn earth_heliocentric_velocity_equatorial_au_per_day(jd_tt: f64) -> DVec3 {
    let v_ecl = earth_heliocentric_velocity_ecliptic_au_per_day(jd_tt);
    ecliptic_vector_to_equatorial(v_ecl, mean_obliquity_rad(jd_tt))
}

/// Apply annual aberration to an ICRS direction using the special-relativistic
/// (Lorentz) formulation matching SOFA `iauAb`.
///
/// Inputs:
/// * `direction` — natural (geometric) unit direction to the source in ICRS.
/// * `velocity_au_per_day` — observer velocity relative to the SSB, in AU/day,
///   ICRS equatorial frame.
///
/// Returned vector is the proper (apparent) ICRS direction after aberration,
/// renormalised to unit length.
///
/// Algorithm — direct port of SOFA `iauAb`
/// (Software for Fundamental Astronomy, Wallace & Capitaine 2006; see
/// "SOFA Tools for Earth Attitude" §2.4.5 "Stellar aberration"):
///
/// ```text
/// V    = v / c                          (units of c)
/// bm1  = sqrt(1 − |V|²)                 (Lorentz reciprocal γ⁻¹)
/// s1   = 1 + p · V                      (Doppler factor)
/// w    = 1 + (p · V) / (1 + bm1)
/// p′   = (bm1 · p + w · V) / s1
/// p″   = p′ / |p′|
/// ```
///
/// The previous implementation used `p + V − (p·V)·p` which is the
/// **classical (Newtonian) v/c addition**. At Earth's orbital speed
/// (|V| ≈ 10⁻⁴) the Lorentz correction is O(|V|²) ≈ 10⁻⁸ rad ≈ 2 µas, well
/// below catalog noise — but the Lorentz form is the published reference
/// implementation, costs only a few extra adds, and makes regression tests
/// against SOFA `iauAb` reference vectors meaningful to 1 mas and tighter.
pub fn apply_annual_aberration_direction(direction: DVec3, velocity_au_per_day: DVec3) -> DVec3 {
    let p = direction.normalize();
    let v_over_c = velocity_au_per_day / SPEED_OF_LIGHT_AU_PER_DAY;

    let v_dot_v = v_over_c.dot(v_over_c);
    // bm1 = sqrt(1 − |V|²). Clamp the inside of the sqrt to ≥ 0 so a
    // pathological |V| ≥ c (which would indicate an upstream ephemeris bug)
    // does not yield NaN — debug builds trap, release builds degrade to the
    // |V|=c limit (bm1 = 0).
    debug_assert!(
        v_dot_v < 1.0,
        "observer speed ≥ c (|v/c|² = {v_dot_v}); ephemeris velocity is wrong"
    );
    let bm1 = (1.0 - v_dot_v).max(0.0).sqrt();

    let p_dot_v = p.dot(v_over_c);
    let s1 = 1.0 + p_dot_v;
    let w = 1.0 + p_dot_v / (1.0 + bm1);

    let p_prime = (bm1 * p + w * v_over_c) / s1;
    p_prime.normalize()
}

/// Apparent ICRS direction after annual aberration at TT Julian date.
pub fn apparent_direction_icrs_rad(ra_rad: f64, dec_rad: f64, jd_tt: f64) -> (f64, f64) {
    let s = direction_from_radec_rad(ra_rad, dec_rad);
    let v = earth_heliocentric_velocity_equatorial_au_per_day(jd_tt);
    radec_from_direction(apply_annual_aberration_direction(s, v))
}

/// Aberration offset (apparent − geometric) in arcseconds: (ΔRA cos δ, ΔDec).
pub fn annual_aberration_offset_arcsec(ra_rad: f64, dec_rad: f64, jd_tt: f64) -> (f64, f64) {
    let (ra_app, dec_app) = apparent_direction_icrs_rad(ra_rad, dec_rad, jd_tt);
    let d_ra_rad = (ra_app - ra_rad).rem_euclid(std::f64::consts::TAU);
    let d_ra_rad = if d_ra_rad > std::f64::consts::PI {
        d_ra_rad - std::f64::consts::TAU
    } else {
        d_ra_rad
    };
    let arcsec_per_rad = 180.0 * 3_600.0 / std::f64::consts::PI;
    (
        d_ra_rad * dec_rad.cos() * arcsec_per_rad,
        (dec_app - dec_rad) * arcsec_per_rad,
    )
}
