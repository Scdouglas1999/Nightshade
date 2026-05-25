//! Sun–body–observer lighting vectors and phase angles for solar-system bodies.
//!
//! Uses VSOP87D heliocentric positions (Sun at origin) and ELP2000-82B geocentric
//! Moon; phase angle is the Sun–target–observer angle at the body (JPL Horizons
//! convention). Illuminated fraction follows Lambert: `(1 + cos i) / 2`.
//!

use crate::astrometry::moon::{
    angular_separation_rad, moon_ecliptic_j2000_from_jd_tt, moon_equatorial_j2000_from_jd_tt,
};
use crate::astrometry::vsop87::{
    heliocentric_ecliptic, julian_millennia_tt, sun_equatorial_rad, VsopBody, VSOP87_J2000_JD,
    DAYS_PER_JULIAN_MILLENNIUM,
};

/// Kilometres per astronomical unit (IAU 2012).
pub const KM_PER_AU: f64 = 149_597_870.7;

/// Solar-system body for lighting / phase queries.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LitBody {
    /// Earth's Moon (ELP geocentric + VSOP Earth).
    Moon,
    /// Major planet (VSOP87D).
    Planet(VsopBody),
}

/// Sun–body–observer geometry for procedural body shading.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BodyLighting {
    /// Phase angle at the body (radians, 0 = full, π = new).
    pub phase_angle_rad: f64,
    /// Illuminated disc fraction, `(1 + cos(phase_angle)) / 2`.
    pub illuminated_fraction: f64,
    /// Solar elongation as seen from the observer (radians).
    pub elongation_rad: f64,
    /// Unit vector from body toward Sun (heliocentric ecliptic J2000).
    pub sun_from_body: [f64; 3],
    /// Unit vector from body toward observer/Earth (heliocentric ecliptic J2000).
    pub observer_from_body: [f64; 3],
}

/// Lighting for the Moon at TT Julian date `jd_tt`.
pub fn moon_lighting(jd_tt: f64) -> BodyLighting {
    let t = julian_millennia_tt(jd_tt);
    let earth = heliocentric_ecliptic(VsopBody::Earth, t);
    let earth_au = ecliptic_rectangular_au(
        earth.longitude_rad,
        earth.latitude_rad,
        earth.distance_au,
    );
    let moon_ecl = moon_ecliptic_j2000_from_jd_tt(jd_tt);
    let moon_geo_au = ecliptic_rectangular_au(
        moon_ecl.longitude_deg.to_radians(),
        moon_ecl.latitude_deg.to_radians(),
        moon_ecl.distance_km / KM_PER_AU,
    );
    let moon_helio = [
        earth_au[0] + moon_geo_au[0],
        earth_au[1] + moon_geo_au[1],
        earth_au[2] + moon_geo_au[2],
    ];
    let mut lit = lighting_from_heliocentric(moon_helio, earth_au);
    let moon_eq = moon_equatorial_j2000_from_jd_tt(jd_tt);
    let (sun_ra, sun_dec) = sun_equatorial_rad(jd_tt);
    lit.elongation_rad =
        angular_separation_rad(moon_eq.ra_rad, moon_eq.dec_rad, sun_ra, sun_dec);
    // Visual-grade Moon phase: Sun at infinity ⇒ i ≈ π − elongation (matches v1 Dart / almanac).
    lit.phase_angle_rad = (std::f64::consts::PI - lit.elongation_rad).clamp(0.0, std::f64::consts::PI);
    lit.illuminated_fraction = illuminated_fraction_from_phase_angle(lit.phase_angle_rad);
    lit
}

/// Lighting for a VSOP87 major planet at TT Julian date `jd_tt`.
pub fn planet_lighting(body: VsopBody, jd_tt: f64) -> BodyLighting {
    let t = julian_millennia_tt(jd_tt);
    let earth = heliocentric_ecliptic(VsopBody::Earth, t);
    let earth_au = ecliptic_rectangular_au(
        earth.longitude_rad,
        earth.latitude_rad,
        earth.distance_au,
    );
    let planet = heliocentric_ecliptic(body, t);
    let body_au = ecliptic_rectangular_au(
        planet.longitude_rad,
        planet.latitude_rad,
        planet.distance_au,
    );
    lighting_from_heliocentric(body_au, earth_au)
}

/// Lighting for a solar-system body at TT Julian date `jd_tt`.
pub fn body_lighting(body: LitBody, jd_tt: f64) -> BodyLighting {
    match body {
        LitBody::Moon => moon_lighting(jd_tt),
        LitBody::Planet(p) => planet_lighting(p, jd_tt),
    }
}

/// Phase angle (radians) from heliocentric body and Earth positions (Sun at origin).
///
/// Uses the law of cosines on the Sun–body–Earth triangle: sides `r` (Sun–body),
/// `δ` (body–Earth geocentric), and `R` (Sun–Earth).
#[inline]
pub fn phase_angle_rad_from_heliocentric(body_au: [f64; 3], earth_au: [f64; 3]) -> f64 {
    let r = vector_norm(body_au);
    let geo = [
        body_au[0] - earth_au[0],
        body_au[1] - earth_au[1],
        body_au[2] - earth_au[2],
    ];
    let delta = vector_norm(geo);
    let r_earth = vector_norm(earth_au);
    if r <= 0.0 || delta <= 0.0 {
        return 0.0;
    }
    let cos_i = (r * r + delta * delta - r_earth * r_earth) / (2.0 * r * delta);
    cos_i.clamp(-1.0, 1.0).acos()
}

/// Illuminated fraction from phase angle (Lambert hemisphere).
#[inline]
pub fn illuminated_fraction_from_phase_angle(phase_angle_rad: f64) -> f64 {
    (1.0 + phase_angle_rad.cos()) / 2.0
}

/// Solar elongation (radians) of `body_au` as seen from geocentric Earth.
#[inline]
pub fn elongation_rad_from_heliocentric(body_au: [f64; 3], earth_au: [f64; 3]) -> f64 {
    let geo = [
        body_au[0] - earth_au[0],
        body_au[1] - earth_au[1],
        body_au[2] - earth_au[2],
    ];
    let sun_from_earth = normalize([-earth_au[0], -earth_au[1], -earth_au[2]]);
    let toward_body = normalize(geo);
    angle_between_rad(sun_from_earth, toward_body)
}

fn lighting_from_heliocentric(body_au: [f64; 3], earth_au: [f64; 3]) -> BodyLighting {
    let sun_from_body = normalize([-body_au[0], -body_au[1], -body_au[2]]);
    let observer_from_body = normalize([
        earth_au[0] - body_au[0],
        earth_au[1] - body_au[1],
        earth_au[2] - body_au[2],
    ]);
    let phase_angle_rad = phase_angle_rad_from_heliocentric(body_au, earth_au);
    let illuminated_fraction = illuminated_fraction_from_phase_angle(phase_angle_rad);
    let elongation_rad = elongation_rad_from_heliocentric(body_au, earth_au);
    BodyLighting {
        phase_angle_rad,
        illuminated_fraction,
        elongation_rad,
        sun_from_body,
        observer_from_body,
    }
}

#[inline]
fn ecliptic_rectangular_au(lon_rad: f64, lat_rad: f64, r_au: f64) -> [f64; 3] {
    let (sl, cl) = lon_rad.sin_cos();
    let (sb, cb) = lat_rad.sin_cos();
    [r_au * cb * cl, r_au * cb * sl, r_au * sb]
}

#[inline]
fn vector_norm(v: [f64; 3]) -> f64 {
    (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt()
}

#[inline]
fn normalize(v: [f64; 3]) -> [f64; 3] {
    let n = vector_norm(v);
    if n <= 0.0 {
        return [0.0, 0.0, 0.0];
    }
    [v[0] / n, v[1] / n, v[2] / n]
}

#[inline]
fn angle_between_rad(a: [f64; 3], b: [f64; 3]) -> f64 {
    let dot = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).clamp(-1.0, 1.0);
    dot.acos()
}

/// Julian millennia from UTC Julian date (convenience for tests).
#[inline]
pub fn julian_millennia_from_jd_utc(jd_utc: f64) -> f64 {
    (jd_utc - VSOP87_J2000_JD) / DAYS_PER_JULIAN_MILLENNIUM
}
