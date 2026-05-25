//! Kepler solver + minor-body propagation vs MPC-style osculating elements.
//!
//! Reference geocentric positions computed with the v1 Dart `KeplerianPropagator`
//! algorithm (Python cross-check). Elements from `MinorPlanetCatalog` (MPC, 2024).

#[path = "../src/astrometry/kepler.rs"]
mod kepler;

use glam::DVec3;
use kepler::{
    geocentric_equatorial_j2000, heliocentric_ecliptic_j2000, kepler_equation_residual,
    solve_kepler, HeliocentricState, OrbitalElements, NEAR_PARABOLIC_ECCENTRICITY,
    KEPLER_TOLERANCE_RAD,
};

/// 1 Ceres — MPC osculating elements, epoch 2024 Jan 1.0 TT (JD 2460310.5).
fn ceres_elements() -> OrbitalElements {
    OrbitalElements {
        epoch_jd: 2_460_310.5,
        semi_major_axis_au: 2.7670,
        eccentricity: 0.0760,
        inclination_deg: 10.594,
        longitude_ascending_node_deg: 80.394,
        argument_perihelion_deg: 73.597,
        mean_anomaly_deg: 60.070,
    }
}

/// 2P/Encke — high eccentricity comet (exercises Halley solver path).
fn encke_elements() -> OrbitalElements {
    OrbitalElements {
        epoch_jd: 2_460_226.5,
        semi_major_axis_au: 2.2151,
        eccentricity: 0.84833,
        inclination_deg: 11.781,
        longitude_ascending_node_deg: 334.568,
        argument_perihelion_deg: 186.546,
        mean_anomaly_deg: 255.100,
    }
}

struct HelioFixture {
    jd: f64,
    position_au: [f64; 3],
    distance_au: f64,
}

struct GeoFixture {
    jd: f64,
    ra_hours: f64,
    dec_deg: f64,
    distance_au: f64,
    heliocentric_distance_au: f64,
}

const CERES_HELIO: &[HelioFixture] = &[
    HelioFixture {
        jd: 2_460_310.5,
        position_au: [-1.961_099_04, -1.793_035_82, 0.305_691_41],
        distance_au: 2.674_758_71,
    },
    HelioFixture {
        jd: 2_460_340.5,
        position_au: [-1.754_348_65, -2.032_055_22, 0.260_103_67],
        distance_au: 2.697_154_34,
    },
    HelioFixture {
        jd: 2_460_490.5,
        position_au: [-0.437_562_75, -2.779_569_88, -0.006_060_90],
        distance_au: 2.813_806_43,
    },
];

const CERES_GEO: &[GeoFixture] = &[
    GeoFixture {
        jd: 2_460_310.5,
        ra_hours: 13.492_260,
        dec_deg: -1.182_716,
        distance_au: 2.306_968_14,
        heliocentric_distance_au: 2.674_758_71,
    },
    GeoFixture {
        jd: 2_460_340.5,
        ra_hours: 13.876_489,
        dec_deg: -5.720_124,
        distance_au: 2.730_217_13,
        heliocentric_distance_au: 2.697_154_34,
    },
    GeoFixture {
        jd: 2_460_490.5,
        ra_hours: 17.670_522,
        dec_deg: -23.452_973,
        distance_au: 3.798_755_42,
        heliocentric_distance_au: 2.813_806_43,
    },
];

const ENCKE_GEO: &[GeoFixture] = &[
    GeoFixture {
        jd: 2_460_226.5,
        ra_hours: 23.805_556,
        dec_deg: 2.064_926,
        distance_au: 4.543_653_27,
        heliocentric_distance_au: 3.603_776_49,
    },
    GeoFixture {
        jd: 2_460_236.5,
        ra_hours: 23.959_021,
        dec_deg: 3.202_133,
        distance_au: 4.441_694_47,
        heliocentric_distance_au: 3.562_223_39,
    },
    GeoFixture {
        jd: 2_460_276.5,
        ra_hours: 0.536_211,
        dec_deg: 7.736_748,
        distance_au: 3.841_794_16,
        heliocentric_distance_au: 3.376_308_01,
    },
];

const POS_TOLERANCE_AU: f64 = 1.0e-5;
const ANGLE_TOLERANCE_DEG: f64 = 0.01;
const DIST_TOLERANCE_AU: f64 = 1.0e-5;

fn assert_helio_near(actual: HeliocentricState, expected: &HelioFixture) {
    let expected_pos = DVec3::from_array(expected.position_au);
    let pos_err = (actual.position_au - expected_pos).length();
    assert!(
        pos_err < POS_TOLERANCE_AU,
        "heliocentric position error {pos_err} AU at JD {}",
        expected.jd
    );
    assert!(
        (actual.distance_au - expected.distance_au).abs() < DIST_TOLERANCE_AU,
        "heliocentric distance mismatch at JD {}: got {} expected {}",
        expected.jd,
        actual.distance_au,
        expected.distance_au
    );
}

fn assert_geo_near(actual: &kepler::GeocentricEquatorial, expected: &GeoFixture) {
    assert!(
        (actual.ra_hours - expected.ra_hours).abs() < ANGLE_TOLERANCE_DEG / 15.0,
        "RA mismatch at JD {}: got {} h expected {} h",
        expected.jd,
        actual.ra_hours,
        expected.ra_hours
    );
    assert!(
        (actual.dec_deg - expected.dec_deg).abs() < ANGLE_TOLERANCE_DEG,
        "Dec mismatch at JD {}: got {}° expected {}°",
        expected.jd,
        actual.dec_deg,
        expected.dec_deg
    );
    assert!(
        (actual.distance_au - expected.distance_au).abs() < DIST_TOLERANCE_AU,
        "geocentric distance mismatch at JD {}",
        expected.jd
    );
    assert!(
        (actual.heliocentric_distance_au - expected.heliocentric_distance_au).abs()
            < DIST_TOLERANCE_AU,
        "heliocentric distance mismatch at JD {}",
        expected.jd
    );
}

#[test]
fn kepler_equation_converges_for_moderate_eccentricity() {
    let e = 0.076;
    for m_deg in [0.0_f64, 45.0, 90.0, 180.0, 270.0, 359.9] {
        let m = m_deg.to_radians();
        let e_anomaly = solve_kepler(m, e);
        let residual = kepler_equation_residual(e_anomaly, m, e);
        assert!(
            residual.abs() < KEPLER_TOLERANCE_RAD,
            "residual {residual} at M={m_deg}° e={e}"
        );
    }
}

#[test]
fn kepler_equation_uses_halley_for_high_eccentricity() {
    let encke_e = encke_elements().eccentricity;
    assert!(encke_e >= NEAR_PARABOLIC_ECCENTRICITY);

    let m = 255.100_f64.to_radians();
    let e_anomaly = solve_kepler(m, encke_e);
    let residual = kepler_equation_residual(e_anomaly, m, encke_e);
    assert!(
        residual.abs() < KEPLER_TOLERANCE_RAD,
        "Encke residual {residual} with e={encke_e}"
    );
}

#[test]
fn kepler_halley_matches_newton_when_both_converge() {
    // e just below Halley threshold — both methods should agree.
    let e = 0.75_f64;
    let m = 1.234_f64;
    let mut halley_e = m + e * m.sin();
    let mut newton_e = halley_e;

    // Inline Halley (same as module) for cross-check.
    for _ in 0..30 {
        let sin_e = halley_e.sin();
        let cos_e = halley_e.cos();
        let f = halley_e - e * sin_e - m;
        if f.abs() < KEPLER_TOLERANCE_RAD {
            break;
        }
        let fp = 1.0 - e * cos_e;
        let fpp = e * sin_e;
        halley_e -= (2.0 * f * fp) / (2.0 * fp * fp - f * fpp);
    }
    for _ in 0..30 {
        let f = newton_e - e * newton_e.sin() - m;
        if f.abs() < KEPLER_TOLERANCE_RAD {
            break;
        }
        newton_e -= f / (1.0 - e * newton_e.cos());
    }

    let solver_e = solve_kepler(m, e);
    assert!((solver_e - newton_e).abs() < 1.0e-12);
    assert!((solver_e - halley_e).abs() < 1.0e-10);
}

#[test]
fn ceres_mpc_heliocentric_positions() {
    let elements = ceres_elements();
    for fixture in CERES_HELIO {
        let state = heliocentric_ecliptic_j2000(&elements, fixture.jd);
        assert_helio_near(state, fixture);
    }
}

#[test]
fn ceres_mpc_geocentric_ephemeris() {
    let elements = ceres_elements();
    for fixture in CERES_GEO {
        let state = geocentric_equatorial_j2000(&elements, fixture.jd);
        assert_geo_near(&state, fixture);
    }
}

#[test]
fn encke_high_eccentricity_comet_ephemeris() {
    let elements = encke_elements();
    for fixture in ENCKE_GEO {
        let state = geocentric_equatorial_j2000(&elements, fixture.jd);
        assert_geo_near(&state, fixture);
    }
}
