//! Saemundsson refraction — published-formula table at standard atmosphere.
//!
//! Table values: Sæmundsson inverse formula (Wikipedia; P = 1010 hPa, T = 10 °C).

use nightshade_planetarium::astrometry::refraction::{
    apparent_to_true_altitude, refraction_arcmin, refraction_arcmin_standard, refraction_deg,
    refraction_scale, true_to_apparent_altitude, RefractionError, STANDARD_PRESSURE_HPA,
    STANDARD_TEMPERATURE_C,
};

const TIGHT_ARCMIN: f64 = 1e-4;
const TIGHT_DEG: f64 = 1e-5;

/// Published Sæmundsson table (arcminutes) at standard P/T; h = true altitude (°).
const PUBLISHED_ARCMIN: &[(f64, f64)] = &[
    (90.0, 0.0),
    (45.0, 1.012_7),
    (30.0, 1.746_0),
    (20.0, 2.741_2),
    (10.0, 5.407_7),
    (5.0, 9.674_1),
    (2.0, 16.925_7),
    (1.0, 21.743_9),
    (0.0, 28.981_9),
];

#[test]
fn published_table_standard_atmosphere() {
    for &(h, expected_arcmin) in PUBLISHED_ARCMIN {
        let got = refraction_arcmin_standard(h).expect("valid altitude");
        assert!(
            (got - expected_arcmin).abs() < TIGHT_ARCMIN,
            "h={h}° expected {expected_arcmin}′ got {got}′"
        );
    }
}

#[test]
fn degrees_match_arcminutes_over_sixty() {
    for &(h, expected_arcmin) in PUBLISHED_ARCMIN {
        let deg = refraction_deg(h, STANDARD_PRESSURE_HPA, STANDARD_TEMPERATURE_C).unwrap();
        assert!((deg * 60.0 - expected_arcmin).abs() < TIGHT_ARCMIN, "h={h}");
    }
}

#[test]
fn pressure_temperature_scale_factors() {
    let h = 10.0;
    let base = refraction_arcmin(h, STANDARD_PRESSURE_HPA, STANDARD_TEMPERATURE_C).unwrap();
    let high_p = refraction_arcmin(h, 1040.0, STANDARD_TEMPERATURE_C).unwrap();
    let hot = refraction_arcmin(h, STANDARD_PRESSURE_HPA, 30.0).unwrap();
    assert!(high_p > base);
    assert!(hot < base);
    let scale = refraction_scale(1040.0, STANDARD_TEMPERATURE_C)
        / refraction_scale(STANDARD_PRESSURE_HPA, STANDARD_TEMPERATURE_C);
    assert!((high_p / base - scale).abs() < TIGHT_ARCMIN);
}

#[test]
fn below_cutoff_returns_zero() {
    assert_eq!(refraction_arcmin_standard(-5.0).unwrap(), 0.0);
    // Dart uses strict `< -2.0`; at exactly -2° the formula still applies.
    assert!(refraction_arcmin_standard(-2.0).unwrap() > 0.0);
}

#[test]
fn invalid_altitude_errors() {
    assert!(matches!(
        refraction_arcmin_standard(f64::NAN),
        Err(RefractionError::InvalidAltitude(_))
    ));
    assert!(matches!(
        refraction_arcmin_standard(91.0),
        Err(RefractionError::InvalidAltitude(91.0))
    ));
}

#[test]
fn true_apparent_roundtrip_standard() {
    for &h in &[15.0, 10.0, 5.0, 1.0, 0.5] {
        let apparent =
            true_to_apparent_altitude(h, STANDARD_PRESSURE_HPA, STANDARD_TEMPERATURE_C).unwrap();
        let back =
            apparent_to_true_altitude(apparent, STANDARD_PRESSURE_HPA, STANDARD_TEMPERATURE_C)
                .unwrap();
        assert!((back - h).abs() < TIGHT_DEG, "h={h} apparent={apparent} back={back}");
    }
}

#[test]
fn matches_dart_bennett_coefficients_at_10_deg() {
    // `astronomy_calculations.dart` uses the same 1.02 / tan(h + 10.3/(h+5.11)) on true altitude.
    let h: f64 = 10.0;
    let r_arcmin = 1.02 / ((h + 10.3 / (h + 5.11)).to_radians().tan());
    let r_deg = r_arcmin / 60.0;
    let got = refraction_deg(h, STANDARD_PRESSURE_HPA, STANDARD_TEMPERATURE_C).unwrap();
    assert!((got - r_deg).abs() < TIGHT_DEG);
}
