//! IAU 2006 P03 precession (bias + precession): GCRS → mean equator/equinox of date.
//!
//! Algorithms match IAU SOFA `eraPfw06`, `eraObl06`, and `eraFw2m` (ERFA).
//! Reference: Capitaine et al. (2003); Hilton et al. (2006).

use glam::{DMat3, DVec3};

use super::time::{DAYS_PER_JULIAN_CENTURY, J2000_JD_TT};

/// Arcseconds to radians (SOFA `ERFA_DAS2R`).
const ARCSEC_TO_RAD: f64 = std::f64::consts::PI / (180.0 * 3_600.0);

/// Julian centuries since J2000.0 TT from a two-part Julian Date (SOFA `t`).
#[inline]
fn julian_centuries_tt(date1: f64, date2: f64) -> f64 {
    ((date1 - J2000_JD_TT) + date2) / DAYS_PER_JULIAN_CENTURY
}

/// Mean obliquity of the ecliptic (radians); SOFA `eraObl06`.
pub fn mean_obliquity_from_julian_centuries_tt(t: f64) -> f64 {
    mean_obliquity_rad(t)
}

/// Mean obliquity of the ecliptic (radians); SOFA `eraObl06`.
fn mean_obliquity_rad(t: f64) -> f64 {
    let arcsec = 84_381.406
        + t * (-46.836_769
            + t * (-0.000_183_1
                + t * (0.002_003_40 + t * (-0.000_000_576 + t * (-0.000_000_043_4)))));
    arcsec * ARCSEC_TO_RAD
}

/// Fukushima-Williams bias-precession angles (radians); SOFA `eraPfw06`.
fn fukushima_williams_angles_rad(t: f64) -> (f64, f64, f64, f64) {
    let gamb = (-0.052_928
        + t * (10.556_378
            + t * (0.493_204_4
                + t * (-0.000_312_38 + t * (-0.000_002_788 + t * 0.000_000_026_0)))))
        * ARCSEC_TO_RAD;
    let phib = (84_381.412_819
        + t * (-46.811_016
            + t * (0.051_126_8
                + t * (0.000_532_89 + t * (-0.000_000_440 + t * (-0.000_000_017_6))))))
        * ARCSEC_TO_RAD;
    let psib = (-0.041_775
        + t * (5_038.481_484
            + t * (1.558_417_5
                + t * (-0.000_185_22 + t * (-0.000_026_452 + t * (-0.000_000_014_8))))))
        * ARCSEC_TO_RAD;
    let epsa = mean_obliquity_rad(t);
    (gamb, phib, psib, epsa)
}

/// Post-multiply `r` by an x-rotation (SOFA `eraRx` / `eraRz` convention).
fn postrotate_x(r: &mut [[f64; 3]; 3], angle: f64) {
    let (s, c) = angle.sin_cos();
    for j in 0..3 {
        let a10 = c * r[1][j] + s * r[2][j];
        let a20 = -s * r[1][j] + c * r[2][j];
        r[1][j] = a10;
        r[2][j] = a20;
    }
}

/// Post-multiply `r` by a z-rotation (SOFA `eraRz`).
fn postrotate_z(r: &mut [[f64; 3]; 3], angle: f64) {
    let (s, c) = angle.sin_cos();
    for j in 0..3 {
        let a00 = c * r[0][j] + s * r[1][j];
        let a10 = -s * r[0][j] + c * r[1][j];
        r[0][j] = a00;
        r[1][j] = a10;
    }
}

/// Rotation matrix from Fukushima-Williams angles; SOFA `eraFw2m`.
///
/// `V(date) = matrix * V(GCRS)` for column vectors.
fn matrix_from_fw_angles(gamb: f64, phib: f64, psib: f64, epsa: f64) -> DMat3 {
    let mut r = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]];
    postrotate_z(&mut r, gamb);
    postrotate_x(&mut r, phib);
    postrotate_z(&mut r, -psib);
    postrotate_x(&mut r, -epsa);
    DMat3::from_cols(
        DVec3::new(r[0][0], r[1][0], r[2][0]),
        DVec3::new(r[0][1], r[1][1], r[2][1]),
        DVec3::new(r[0][2], r[1][2], r[2][2]),
    )
}

/// Bias-precession matrix from Julian centuries TT since J2000.0; SOFA `eraPmat06`.
pub fn precession_matrix_from_julian_centuries_tt(t: f64) -> DMat3 {
    let (gamb, phib, psib, epsa) = fukushima_williams_angles_rad(t);
    matrix_from_fw_angles(gamb, phib, psib, epsa)
}

/// Bias-precession matrix from a two-part TT Julian Date; SOFA `eraPmat06`.
#[inline]
pub fn precession_matrix_from_jd_tt(date1: f64, date2: f64) -> DMat3 {
    precession_matrix_from_julian_centuries_tt(julian_centuries_tt(date1, date2))
}

/// Apply precession to an ICRS direction (unit vector in, unit vector out).
#[inline]
pub fn precess_direction_icrs(direction: DVec3, matrix: DMat3) -> DVec3 {
    (matrix * direction).normalize()
}
