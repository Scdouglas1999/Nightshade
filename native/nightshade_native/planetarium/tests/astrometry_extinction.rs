//! Atmospheric extinction LUT — parity with Dart `AtmosphericExtinctionLUT`.
//!
//! Reference values from `packages/nightshade_planetarium/lib/src/rendering/sky_renderer.dart`.

use nightshade_planetarium::astrometry::extinction::{lookup, lut_entry, ExtinctionSample};

const EPS: f64 = 1e-14;

fn assert_sample(actual: ExtinctionSample, brightness: f64, red_shift: f64) {
    assert!(
        (actual.brightness_factor - brightness).abs() < EPS,
        "brightness: got {} expected {}",
        actual.brightness_factor,
        brightness
    );
    assert!(
        (actual.red_shift - red_shift).abs() < EPS,
        "red_shift: got {} expected {}",
        actual.red_shift,
        red_shift
    );
}

/// Integer table entries (Dart `_buildLUT`).
#[test]
fn lut_integer_altitudes_match_dart() {
    assert_sample(lut_entry(0), 0.5, 0.2);
    assert_sample(lut_entry(15), 0.75, 0.1);
    assert_sample(
        lut_entry(29),
        0.983_333_333_333_333_4,
        0.006_666_666_666_666_644,
    );
    assert_sample(lut_entry(30), 1.0, 0.0);
    assert_sample(lut_entry(90), 1.0, 0.0);
}

/// Interpolated lookups (Dart `lookup`).
#[test]
fn lookup_interpolation_matches_dart() {
    assert_sample(lookup(0.0), 0.5, 0.2);
    assert_sample(
        lookup(14.5),
        0.741_666_666_666_666_7,
        0.103_333_333_333_333_33,
    );
    assert_sample(
        lookup(29.5),
        0.991_666_666_666_666_7,
        0.003_333_333_333_333_322,
    );
}

/// Above 30° and below horizon clamps (Dart early returns).
#[test]
fn lookup_clamps_match_dart() {
    assert_sample(lookup(30.0), 1.0, 0.0);
    assert_sample(lookup(45.0), 1.0, 0.0);
    assert_sample(lookup(-5.0), 0.5, 0.2);
    assert_sample(lookup(89.5), 1.0, 0.0);
    assert_sample(lookup(90.0), 1.0, 0.0);
}
