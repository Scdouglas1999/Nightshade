//! Body phase angles vs JPL Horizons-style reference epochs (VSOP87 + ELP).
//!
//! `body_lighting` is path-included until the integrator adds `pub mod body_lighting` to
//! `astrometry/mod.rs`.

#[path = "../src/astrometry/body_lighting.rs"]
mod body_lighting;
#[path = "../src/astrometry/moon.rs"]
mod moon;
#[path = "../src/astrometry/vsop87.rs"]
mod vsop87;

use body_lighting::{
    body_lighting, illuminated_fraction_from_phase_angle, moon_lighting, planet_lighting,
    BodyLighting, LitBody,
};
use vsop87::VsopBody;

/// Visual-grade tolerance for truncated VSOP87D + ELP-50.
const TOL_PHASE_DEG: f64 = 5.0;
const TOL_ELONG_DEG: f64 = 5.0;
const TOL_ILLUM: f64 = 0.05;

struct HorizonsLightingRef {
    jd_tt: f64,
    phase_deg: f64,
    illum: f64,
    elong_deg: f64,
}

/// Moon: equatorial elongation + phase ≈ π − elongation; VSOP87D+ELP-50 nominal rows.
const MOON_HORIZONS: &[HorizonsLightingRef] = &[
    HorizonsLightingRef {
        jd_tt: 2_451_545.0,
        phase_deg: 123.0,
        illum: 0.23,
        elong_deg: 57.0,
    },
    HorizonsLightingRef {
        jd_tt: 2_451_562.0,
        phase_deg: 38.0,
        illum: 0.93,
        elong_deg: 142.0,
    },
    HorizonsLightingRef {
        jd_tt: 2_451_546.92,
        phase_deg: 144.0,
        illum: 0.09,
        elong_deg: 36.0,
    },
];

const VENUS_HORIZONS: &[HorizonsLightingRef] = &[
    HorizonsLightingRef {
        jd_tt: 2_457_835.5,
        phase_deg: 167.0,
        illum: 0.01,
        elong_deg: 8.0,
    },
    HorizonsLightingRef {
        jd_tt: 2_458_849.5,
        phase_deg: 50.0,
        illum: 0.82,
        elong_deg: 34.5,
    },
];

fn assert_near(actual: f64, expected: f64, tol: f64, label: &str) {
    assert!(
        (actual - expected).abs() <= tol,
        "{label}: got {actual}, expected {expected} (±{tol})"
    );
}

fn assert_lighting_near(got: BodyLighting, exp: &HorizonsLightingRef) {
    assert_near(
        got.phase_angle_rad.to_degrees(),
        exp.phase_deg,
        TOL_PHASE_DEG,
        "phase angle (deg)",
    );
    assert_near(
        got.illuminated_fraction,
        exp.illum,
        TOL_ILLUM,
        "illuminated fraction",
    );
    assert_near(
        got.elongation_rad.to_degrees(),
        exp.elong_deg,
        TOL_ELONG_DEG,
        "elongation (deg)",
    );
}

#[test]
fn illuminated_fraction_matches_lambert() {
    for phase_deg in [0.0_f64, 45.0, 90.0, 135.0, 180.0] {
        let phase = phase_deg.to_radians();
        let frac = illuminated_fraction_from_phase_angle(phase);
        let expected = (1.0 + phase.cos()) / 2.0;
        assert!((frac - expected).abs() < 1e-12);
    }
}

#[test]
fn moon_phase_angle_is_pi_minus_elongation() {
    let lit = moon_lighting(2_451_545.0);
    let expected = std::f64::consts::PI - lit.elongation_rad;
    assert!(
        (lit.phase_angle_rad - expected).abs() < 1e-9,
        "phase {} vs π − elong {}",
        lit.phase_angle_rad,
        expected
    );
}

#[test]
fn planet_phase_angle_matches_heliocentric_vectors() {
    let lit = planet_lighting(VsopBody::Mars, 2_451_545.0);
    let dot = lit.sun_from_body[0] * lit.observer_from_body[0]
        + lit.sun_from_body[1] * lit.observer_from_body[1]
        + lit.sun_from_body[2] * lit.observer_from_body[2];
    let from_vectors = dot.clamp(-1.0, 1.0).acos();
    assert!(
        (from_vectors - lit.phase_angle_rad).abs() < 1e-9,
        "vector angle {from_vectors} vs phase {angle}",
        angle = lit.phase_angle_rad
    );
}

#[test]
fn moon_phase_within_horizons_tolerance() {
    for r in MOON_HORIZONS {
        let got = moon_lighting(r.jd_tt);
        assert_lighting_near(got, r);
        assert!(
            (got.illuminated_fraction - illuminated_fraction_from_phase_angle(got.phase_angle_rad))
                .abs()
                < 1e-12
        );
    }
}

#[test]
fn venus_inferior_planet_phase_within_horizons_tolerance() {
    for r in VENUS_HORIZONS {
        let got = planet_lighting(VsopBody::Venus, r.jd_tt);
        assert_lighting_near(got, r);
    }
}

#[test]
fn body_lighting_dispatches_moon_and_planet() {
    let moon = body_lighting(LitBody::Moon, 2_451_546.92);
    let direct = moon_lighting(2_451_546.92);
    assert_eq!(moon.phase_angle_rad, direct.phase_angle_rad);
    assert_eq!(moon.illuminated_fraction, direct.illuminated_fraction);

    let venus = body_lighting(LitBody::Planet(VsopBody::Venus), 2_457_835.5);
    let direct_v = planet_lighting(VsopBody::Venus, 2_457_835.5);
    assert_eq!(venus.phase_angle_rad, direct_v.phase_angle_rad);
}

#[test]
fn sun_body_and_observer_vectors_are_unit_length() {
    let lit = planet_lighting(VsopBody::Mars, 2_451_545.0);
    let sun_len = (lit.sun_from_body[0].powi(2)
        + lit.sun_from_body[1].powi(2)
        + lit.sun_from_body[2].powi(2))
    .sqrt();
    let obs_len = (lit.observer_from_body[0].powi(2)
        + lit.observer_from_body[1].powi(2)
        + lit.observer_from_body[2].powi(2))
    .sqrt();
    assert!((sun_len - 1.0).abs() < 1e-12);
    assert!((obs_len - 1.0).abs() < 1e-12);
}
