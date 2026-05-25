//! IAU 2000B nutation — ground truth from IAU SOFA `eraNut00b` (ERFA 0.2.1).
//!
//! Reference values computed with pyerfa (SOFA Issue 2021-01-25).

use nightshade_planetarium::astrometry::nutation::{
    nutation_from_jd_tt, nutation_from_julian_centuries_tt,
};
use nightshade_planetarium::astrometry::time::J2000_JD_TT;

/// Match SOFA nutation components to ~1 nanoradian (well below 1 mas).
const TIGHT: f64 = 1e-9;

fn assert_nutation_matches_sofa(dpsi: f64, deps: f64, sofa_dpsi: f64, sofa_deps: f64, label: &str) {
    assert!(
        (dpsi - sofa_dpsi).abs() < TIGHT,
        "{label} dpsi: got {dpsi} expected {sofa_dpsi}"
    );
    assert!(
        (deps - sofa_deps).abs() < TIGHT,
        "{label} deps: got {deps} expected {sofa_deps}"
    );
}

/// SOFA `eraNut00b` at J2000.0 TT (two-part date = DJ00 + 0).
#[test]
fn nutation_j2000_matches_sofa() {
    const DPSI: f64 = -6.754_261_253_992_235e-05;
    const DEPS: f64 = -2.797_092_331_098_565e-05;
    let (dpsi, deps) = nutation_from_jd_tt(J2000_JD_TT, 0.0);
    assert_nutation_matches_sofa(dpsi, deps, DPSI, DEPS, "J2000");
}

/// SOFA `eraNut00b` at J2050.0 (T = 0.5 Julian centuries TT since J2000.0).
#[test]
fn nutation_j2050_matches_sofa() {
    const DPSI: f64 = 7.355_290_795_194_448e-05;
    const DEPS: f64 = -2.584_110_526_212_885e-05;
    let days = 50.0 * 365.25;
    let (dpsi, deps) = nutation_from_jd_tt(J2000_JD_TT, days);
    assert_nutation_matches_sofa(dpsi, deps, DPSI, DEPS, "J2050");
    let (dpsi_t, deps_t) = nutation_from_julian_centuries_tt(0.5);
    assert_nutation_matches_sofa(dpsi_t, deps_t, DPSI, DEPS, "J2050 via t");
}

/// SOFA at 2006-01-01 00:00 UTC (TT offset 65.184 s on that leap-second epoch).
#[test]
fn nutation_2006_jan_1_matches_sofa() {
    const DPSI: f64 = -8.853_909_584_596_934e-06;
    const DEPS: f64 = 4.094_234_224_333_117e-05;
    let jd_tt = 2_453_737.5 + 65.184 / 86_400.0;
    let t = (jd_tt - J2000_JD_TT) / 36_525.0;
    let (dpsi, deps) = nutation_from_julian_centuries_tt(t);
    assert_nutation_matches_sofa(dpsi, deps, DPSI, DEPS, "2006-01-01");
}

/// SOFA at J2000.0 18:00 UTC (JD TT fraction +0.5 day from noon anchor).
#[test]
fn nutation_j2000_18h_utc_matches_sofa() {
    const DPSI: f64 = -6.750_553_532_840_426e-05;
    const DEPS: f64 = -2.802_164_727_981_113e-05;
    let (dpsi, deps) = nutation_from_jd_tt(2_451_545.5, 0.0);
    assert_nutation_matches_sofa(dpsi, deps, DPSI, DEPS, "J2000 18h UTC");
}
