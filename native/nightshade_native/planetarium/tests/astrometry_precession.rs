//! IAU 2006 P03 precession — ground truth from IAU SOFA `eraPmat06` (ERFA 0.2.1).
//!
//! Fukushima-Williams angles from `eraPfw06`; matrix from `eraFw2m` / `eraPmat06`.
//! Reference values computed with pyerfa (SOFA Issue 2021-01-25).

use glam::{DMat3, DVec3};
use nightshade_planetarium::astrometry::precession::{
    precession_matrix_from_jd_tt, precession_matrix_from_julian_centuries_tt,
};
use nightshade_planetarium::astrometry::time::J2000_JD_TT;

/// Maximum angular separation vs SOFA (0.5″ per Task 21).
const MAX_SEP_ARCSEC: f64 = 0.5;
const ARCSEC_TO_RAD: f64 = std::f64::consts::PI / (180.0 * 3_600.0);

fn angular_separation_rad(a: DVec3, b: DVec3) -> f64 {
    a.normalize()
        .dot(b.normalize())
        .clamp(-1.0, 1.0)
        .acos()
}

/// SOFA `rbp[row][col]` as a glam `DMat3` (`V(date) = matrix * V(GCRS)`).
fn sofa_matrix(rows: [[f64; 3]; 3]) -> DMat3 {
    DMat3::from_cols(
        DVec3::new(rows[0][0], rows[1][0], rows[2][0]),
        DVec3::new(rows[0][1], rows[1][1], rows[2][1]),
        DVec3::new(rows[0][2], rows[1][2], rows[2][2]),
    )
}

/// ICRS unit direction at equatorial coordinates (radians).
fn direction_icrs(ra_rad: f64, dec_rad: f64) -> DVec3 {
    let cos_dec = dec_rad.cos();
    DVec3::new(cos_dec * ra_rad.cos(), cos_dec * ra_rad.sin(), dec_rad.sin())
}

/// SOFA `eraPmat06` at J2000.0 (ERFA; two-part TT = DJ00 + 0).
#[test]
fn precession_matrix_j2000_matches_sofa() {
    const SOFA: [[f64; 3]; 3] = [
        [9.999_999_999_999_941e-01, -7.078_368_960_971_556e-08, 8.056_213_977_613_186e-08],
        [7.078_368_694_637_676e-08, 9.999_999_999_999_969e-01, 3.305_943_735_432_138e-08],
        [-8.056_214_211_620_057e-08, -3.305_943_169_218_395e-08, 9.999_999_999_999_962e-01],
    ];
    let m = precession_matrix_from_jd_tt(J2000_JD_TT, 0.0);
    let expected = sofa_matrix(SOFA);
    for row in 0..3 {
        for col in 0..3 {
            let got = m.col(col)[row];
            let exp = expected.col(col)[row];
            assert!(
                (got - exp).abs() < 1e-14,
                "rbp[{row}][{col}] got {got} expected {exp}"
            );
        }
    }
}

/// SOFA `eraPmat06` at J2050.0 (T = 0.5 Julian centuries TT since J2000.0).
#[test]
fn precession_matrix_j2050_matches_sofa() {
    const SOFA: [[f64; 3]; 3] = [
        [9.999_256_843_098_003e-01, -1.118_167_244_077_447e-02, -4.857_577_483_145_684e-03],
        [1.118_167_289_642_969e-02, 9.999_374_827_751_564e-01, -2.706_512_742_406_408e-05],
        [4.857_576_434_271_398e-03, -2.725_272_642_511_989e-05, 9.999_882_015_346_351e-01],
    ];
    let days = 50.0 * 365.25;
    let m = precession_matrix_from_jd_tt(J2000_JD_TT, days);
    let expected = sofa_matrix(SOFA);
    for row in 0..3 {
        for col in 0..3 {
            let got = m.col(col)[row];
            let exp = expected.col(col)[row];
            assert!(
                (got - exp).abs() < 1e-12,
                "rbp[{row}][{col}] got {got} expected {exp}"
            );
        }
    }
}

/// Precess (RA=0, Dec=0) from J2000 to J2050; compare to SOFA `eraPmat06` × (1,0,0) (<0.5″).
#[test]
fn precess_equinox_j2000_to_j2050_within_half_arcsec() {
    const SOFA: [[f64; 3]; 3] = [
        [9.999_256_843_098_003e-01, -1.118_167_244_077_447e-02, -4.857_577_483_145_684e-03],
        [1.118_167_289_642_969e-02, 9.999_374_827_751_564e-01, -2.706_512_742_406_408e-05],
        [4.857_576_434_271_398e-03, -2.725_272_642_511_989e-05, 9.999_882_015_346_351e-01],
    ];
    let m = precession_matrix_from_julian_centuries_tt(0.5);
    let icrs = direction_icrs(0.0, 0.0);
    let got = (m * icrs).normalize();
    let expected = DVec3::new(SOFA[0][0], SOFA[1][0], SOFA[2][0]).normalize();

    let sep_arcsec = angular_separation_rad(got, expected) / ARCSEC_TO_RAD;
    assert!(
        sep_arcsec < MAX_SEP_ARCSEC,
        "separation {sep_arcsec} arcsec (limit {MAX_SEP_ARCSEC})"
    );
}

/// 2006-01-01 00:00 UTC epoch (same leap-second table as sidereal tests).
#[test]
fn precess_equinox_2006_within_half_arcsec() {
    const SOFA: [[f64; 3]; 3] = [
        [9.999_989_290_282_343e-01, -1.342_330_327_899_070e-03, -5.831_737_951_580_601e-04],
        [1.342_330_351_590_754e-03, 9.999_990_990_741_463e-01, -3.507_807_228_020_354e-07],
        [5.831_737_406_253_134e-04, -4.320_315_382_666_529e-07, 9.999_998_299_540_863e-01],
    ];

    let jd_tt = 2_453_737.5 + 65.184 / 86_400.0;
    let t = (jd_tt - J2000_JD_TT) / 36_525.0;
    let m = precession_matrix_from_julian_centuries_tt(t);
    let icrs = direction_icrs(0.0, 0.0);
    let got = (m * icrs).normalize();
    let expected = DVec3::new(SOFA[0][0], SOFA[1][0], SOFA[2][0]).normalize();

    let sep_arcsec = angular_separation_rad(got, expected) / ARCSEC_TO_RAD;
    assert!(
        sep_arcsec < MAX_SEP_ARCSEC,
        "separation {sep_arcsec} arcsec (limit {MAX_SEP_ARCSEC})"
    );
}
