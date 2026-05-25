//! Earth Rotation Angle and mean sidereal time (IAU 2000 / 2006).
//!
//! Algorithms match IAU SOFA `eraEra00` and `eraGmst06` (ERFA).

use crate::types::AstroTime;

use super::time::{DAYS_PER_JULIAN_CENTURY, J2000_JD_TT};

/// Julian date of J2000.0 used for two-part UT1/TT splits (SOFA `ERFA_DJ00`).
const J2000_JD: f64 = J2000_JD_TT;

/// ERA scale factor: Earth rotations per UT1 day (IAU 2000; SOFA `eraEra00`).
const ERA_RATE: f64 = 0.002_737_811_911_354_48;

/// ERA at J2000.0 (fraction of turn; SOFA `eraEra00`).
const ERA_J2000: f64 = 0.779_057_273_264_0;

/// Arcseconds to radians (SOFA `ERFA_DAS2R`).
const ARCSEC_TO_RAD: f64 = std::f64::consts::PI / (180.0 * 3_600.0);

/// Normalize an angle to \[0, 2π) (SOFA `eraAnp`).
#[inline]
fn normalize_angle(rad: f64) -> f64 {
    let two_pi = std::f64::consts::TAU;
    let mut a = rad % two_pi;
    if a < 0.0 {
        a += two_pi;
    }
    a
}

/// Fractional part of a Julian Date (SOFA `fmod(d, 1)` for positive dates).
#[inline]
fn jd_fraction(jd: f64) -> f64 {
    jd - jd.trunc()
}

/// Earth rotation angle (radians) from a two-part UT1 Julian Date.
///
/// IAU 2000 model; SOFA `eraEra00` / Capitaine et al. (2000).
pub fn era_from_ut1_parts(uta: f64, utb: f64) -> f64 {
    let (d1, d2) = if uta < utb { (uta, utb) } else { (utb, uta) };
    let days = d1 + (d2 - J2000_JD);
    let frac = jd_fraction(uta) + jd_fraction(utb);
    normalize_angle(std::f64::consts::TAU * (frac + ERA_J2000 + ERA_RATE * days))
}

/// Earth rotation angle (radians) for a UT1 Julian date (J2000.0 split).
#[inline]
pub fn era_from_jd_ut1(jd_ut1: f64) -> f64 {
    era_from_ut1_parts(J2000_JD, jd_ut1 - J2000_JD)
}

/// Greenwich mean sidereal time (radians, IAU 2006).
///
/// Requires UT1 for Earth rotation and TT for the precession-rate polynomial;
/// SOFA `eraGmst06` (Capitaine et al. 2005).
pub fn gmst_from_jd_ut1_tt(jd_ut1: f64, jd_tt: f64) -> f64 {
    let t = (jd_tt - J2000_JD) / DAYS_PER_JULIAN_CENTURY;
    let era = era_from_ut1_parts(J2000_JD, jd_ut1 - J2000_JD);
    let poly_arcsec = 0.014_506
        + t * (4_612.156_534
            + t * (1.391_581_7
                + t * (-0.000_000_44
                    + t * (-0.000_029_956 + t * (-0.000_000_036_8)))));
    normalize_angle(era + poly_arcsec * ARCSEC_TO_RAD)
}

/// Local mean sidereal time (radians): GMST + east longitude, normalized.
#[inline]
pub fn lmst_from_gmst_and_longitude(gmst: f64, longitude_rad: f64) -> f64 {
    normalize_angle(gmst + longitude_rad)
}

impl AstroTime {
    /// Earth Rotation Angle at this epoch (radians, IAU 2000).
    #[inline]
    pub fn era(&self) -> f64 {
        era_from_jd_ut1(self.jd_ut1)
    }

    /// Greenwich Mean Sidereal Time (radians, IAU 2006).
    #[inline]
    pub fn gmst(&self) -> f64 {
        gmst_from_jd_ut1_tt(self.jd_ut1, self.jd_tt)
    }

    /// Local Mean Sidereal Time (radians) for east-positive `longitude_rad`.
    #[inline]
    pub fn lmst(&self, longitude_rad: f64) -> f64 {
        lmst_from_gmst_and_longitude(self.gmst(), longitude_rad)
    }
}
