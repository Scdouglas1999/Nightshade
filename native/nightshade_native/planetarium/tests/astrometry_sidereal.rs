//! ERA, GMST, and LMST — ground truth from IAU SOFA `eraEra00` / `eraGmst06`.
//!
//! Reference values computed with ERFA 0.2.1 (SOFA Issue 2021-01-25).

use nightshade_planetarium::astrometry::earth_rotation::{
    era_from_jd_ut1, gmst_from_jd_ut1_tt, lmst_from_gmst_and_longitude,
};
use nightshade_planetarium::types::AstroTime;

const TIGHT: f64 = 1e-12;

/// SOFA `eraEra00` / `eraGmst06` at J2000.0 noon UTC (UT1 ≈ UTC, ΔUT1 = 0).
#[test]
fn era_gmst_j2000_noon_utc() {
    let t = AstroTime::from_jd_utc(2_451_545.0);
    // ERFA: era00(2451545,0), gmst06(2451545,0,2451545,64.184/86400)
    const ERA: f64 = 4.894_961_212_823_756;
    const GMST: f64 = 4.894_961_283_605_610;
    assert!((t.era() - ERA).abs() < TIGHT, "era {}", t.era());
    assert!((t.gmst() - GMST).abs() < TIGHT, "gmst {}", t.gmst());
    assert!((era_from_jd_ut1(t.jd_ut1) - ERA).abs() < TIGHT);
    assert!((gmst_from_jd_ut1_tt(t.jd_ut1, t.jd_tt) - GMST).abs() < TIGHT);
}

/// SOFA at 2000-01-01 18:00 UTC (JD UTC fraction 0.5).
#[test]
fn era_gmst_j2000_18h_utc() {
    let t = AstroTime::from_jd_utc(2_451_545.5);
    const ERA: f64 = 1.761_969_649_021_585;
    const GMST: f64 = 1.761_970_025_900_166;
    assert!((t.era() - ERA).abs() < TIGHT);
    assert!((t.gmst() - GMST).abs() < TIGHT);
}

/// SOFA at 2006-01-01 00:00 UTC (TAI−UTC = 33 s on that date).
#[test]
fn era_gmst_2006_jan_1() {
    // 2006-01-01 00:00 UTC (SOFA `iauCal2jd`; IERS leap-second epoch JD).
    let t = AstroTime::from_jd_utc(2_453_737.5);
    const ERA: f64 = 1.770_035_434_878_316;
    const GMST: f64 = 1.771_377_764_122_836;
    assert!((t.era() - ERA).abs() < TIGHT);
    assert!((t.gmst() - GMST).abs() < TIGHT);
}

/// LMST = GMST + east longitude (radians), normalized.
#[test]
fn lmst_equals_gmst_plus_longitude() {
    let t = AstroTime::from_jd_utc(2_451_545.0);
    let gmst = t.gmst();
    assert!((t.lmst(0.0) - gmst).abs() < TIGHT);
    let lon = std::f64::consts::FRAC_PI_4;
    let expected = lmst_from_gmst_and_longitude(gmst, lon);
    assert!((t.lmst(lon) - expected).abs() < TIGHT);
    assert!(t.lmst(lon) >= 0.0 && t.lmst(lon) < std::f64::consts::TAU);
}
