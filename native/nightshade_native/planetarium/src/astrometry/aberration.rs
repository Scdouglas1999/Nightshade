//! Annual aberration (first-order v/c) from Earth's heliocentric velocity (VSOP87D Earth).
//!
//! Earth's velocity is obtained by symmetric numerical differentiation of the truncated
//! VSOP87D Earth heliocentric series (same coefficients as `vsop87`). Diurnal
//! aberration is omitted (visual planetarium scope).
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
    DVec3::new(v.x, v.y * cos_eps - v.z * sin_eps, v.y * sin_eps + v.z * cos_eps)
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

/// Apply first-order annual aberration to an ICRS direction (ERFA/SOFA `iauAb` style).
///
/// `direction` and returned vector are unit vectors in the ICRS equatorial frame.
pub fn apply_annual_aberration_direction(direction: DVec3, velocity_au_per_day: DVec3) -> DVec3 {
    let s = direction.normalize();
    let beta = velocity_au_per_day / SPEED_OF_LIGHT_AU_PER_DAY;
    let dot = s.dot(beta);
    (s + beta - dot * s).normalize()
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
