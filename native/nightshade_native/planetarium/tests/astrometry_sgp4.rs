//! SGP4 propagation vs canonical Spacetrack verification vectors.
//!
//! Vectors are from the Vallado / AFSPC test suite (also shipped as `test_cases.toml`
//! in the `sgp4` crate). TEME example satellite NORAD 00005 and ISS sample TLE.

use glam::DVec3;
use nightshade_planetarium::astrometry::sgp4_prop::{
    position_error_km, propagate_tle_minutes_since_epoch, SatellitePropagator,
    VERIFICATION_POSITION_TOLERANCE_KM, VERIFICATION_VELOCITY_TOLERANCE_KM_S,
};

/// NORAD 00005 (Vanguard 1) — first case in the canonical `sgp4` verification set.
const VANGUARD_LINE1: &str =
    "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753";
const VANGUARD_LINE2: &str =
    "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667";

struct VerifState {
    minutes_since_epoch: f64,
    position_km: [f64; 3],
    velocity_km_s: [f64; 3],
}

const VANGUARD_STATES: &[VerifState] = &[
    VerifState {
        minutes_since_epoch: 0.0,
        position_km: [7022.46529266, -1400.08296755, 0.03995155],
        velocity_km_s: [1.893841015, 6.405893759, 4.534807250],
    },
    VerifState {
        minutes_since_epoch: 360.0,
        position_km: [-7154.03120202, -3783.17682504, -3536.19412294],
        velocity_km_s: [4.741887409, -4.151817765, -2.093935425],
    },
    VerifState {
        minutes_since_epoch: 720.0,
        position_km: [-7134.59340119, 6531.68641334, 3260.27186483],
        velocity_km_s: [-4.113793027, -2.911922039, -2.557327851],
    },
    VerifState {
        minutes_since_epoch: 1440.0,
        position_km: [-938.55923943, -6268.18748831, -4294.02924751],
        velocity_km_s: [7.536105209, -0.427127707, 0.989878080],
    },
];

/// ISS (ZARYA) — CelesTrak example TLE (public domain GP data).
const ISS_LINE1: &str = "1 25544U 98067A   20194.88612269 -.00002218  00000-0 -31515-4 0  9992";
const ISS_LINE2: &str = "2 25544  51.6461 221.2784 0001413  89.1723 280.4612 15.49507896236008";

fn assert_state_near(
    actual_pos: DVec3,
    actual_vel: DVec3,
    expected_pos: [f64; 3],
    expected_vel: [f64; 3],
) {
    let expected_pos = DVec3::from_array(expected_pos);
    let expected_vel = DVec3::from_array(expected_vel);
    let pos_err = position_error_km(actual_pos, expected_pos);
    assert!(
        pos_err < VERIFICATION_POSITION_TOLERANCE_KM,
        "position error {pos_err} km exceeds {} km",
        VERIFICATION_POSITION_TOLERANCE_KM
    );
    let vel_err = (actual_vel - expected_vel).length();
    assert!(
        vel_err < VERIFICATION_VELOCITY_TOLERANCE_KM_S,
        "velocity error {vel_err} km/s exceeds {} km/s",
        VERIFICATION_VELOCITY_TOLERANCE_KM_S
    );
}

#[test]
fn vanguard_canonical_verification_states() {
    let sat =
        SatellitePropagator::from_tle(Some("VANGUARD 1".into()), VANGUARD_LINE1, VANGUARD_LINE2)
            .expect("Vanguard TLE must parse");

    for case in VANGUARD_STATES {
        let state = sat
            .propagate_minutes_since_epoch(case.minutes_since_epoch)
            .unwrap_or_else(|e| {
                panic!(
                    "propagation at t={} min failed: {e}",
                    case.minutes_since_epoch
                )
            });
        assert_state_near(
            state.position_km,
            state.velocity_km_s,
            case.position_km,
            case.velocity_km_s,
        );
    }
}

#[test]
fn iss_tle_propagates_in_leo() {
    let state =
        propagate_tle_minutes_since_epoch(Some("ISS (ZARYA)".into()), ISS_LINE1, ISS_LINE2, 0.0)
            .expect("ISS TLE must propagate at epoch");
    let radius_km = state.position_km.length();
    assert!(
        (6_500.0..7_500.0).contains(&radius_km),
        "LEO radius {radius_km} km out of expected range"
    );
    assert!(state.velocity_km_s.length() > 6.0 && state.velocity_km_s.length() < 9.0);
}

#[test]
fn propagator_reuse_matches_one_shot() {
    let sat = SatellitePropagator::from_tle(None, VANGUARD_LINE1, VANGUARD_LINE2).unwrap();
    let reused = sat.propagate_minutes_since_epoch(720.0).unwrap();
    let once =
        propagate_tle_minutes_since_epoch(None, VANGUARD_LINE1, VANGUARD_LINE2, 720.0).unwrap();
    assert!(
        position_error_km(reused.position_km, once.position_km) < 1.0e-9,
        "reused propagator position mismatch"
    );
}
