//! AstroTime conversions — ground truth from IAU SOFA / IERS leap-second history.
//!
//! Leap-second table: IERS Bulletin C via IANA `leap-seconds.list`
//! (https://data.iana.org/time-zones/data/leap-seconds.list).
//! TT − TAI = 32.184 s (IAU 2009 resolution; SOFA `iauTttai`).
//! TT − UTC = (TAI−UTC) + 32.184 s at 2000-01-01 12:00 UTC → 64.184 s (SOFA `iauUtctt`).

use nightshade_planetarium::astrometry::time::*;

#[test]
fn julian_date_2000_jan_1_noon_tt() {
    // J2000.0 noon UTC: JD(UTC) = 2451545.0 (Meeus; SOFA `iauCal2jd` for 2000-01-01 12:00:00).
    let t = AstroTime::from_jd_utc(2_451_545.0);
    // TAI−UTC = 32 s on 2000-01-01 (IERS); TT = TAI + 32.184 s → JD(TT) = JD(UTC) + 64.184/86400.
    let expected_jd_tt = 2_451_545.0 + 64.184 / 86_400.0;
    assert!((t.jd_tt - expected_jd_tt).abs() < 1e-6);
    // J2000.0 is JD 2451545.0 TT; at this UTC noon T = (JD_TT − 2451545)/36525 ≈ 2×10⁻⁸ (SOFA `t`).
    assert!(t.julian_centuries_tt().abs() < 1e-7);
}
