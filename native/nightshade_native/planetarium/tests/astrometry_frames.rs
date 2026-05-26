//! Frame chain ICRS → horizontal — celestial pole altitude vs observer latitude.

use glam::DVec3;
use nightshade_planetarium::astrometry::frames::FrameChain;
use nightshade_planetarium::types::{AstroTime, Observer};

fn pole_ra_at_epoch(time: AstroTime) -> f64 {
    let chain = FrameChain::r#for(time, Observer::default());
    let dir_cirs = (chain.precession_nutation * POLE_DIR_ICRS).normalize();
    dir_cirs
        .y
        .atan2(dir_cirs.x)
        .rem_euclid(std::f64::consts::TAU)
}

const POLE_DIR_ICRS: DVec3 = DVec3::new(0.0, 0.0, 1.0);

/// Geometric pole altitude vs latitude (PN leaves dec ≈ 90°; ~10″ budget).
const MAX_ALT_ERROR_RAD: f64 = 5e-5;

fn observer_at(lat_deg: f64, lon_deg: f64) -> Observer {
    Observer {
        latitude_rad: lat_deg.to_radians(),
        longitude_rad: lon_deg.to_radians(),
        elevation_m: 0.0,
        pressure_hpa: 1010.0,
        temperature_c: 10.0,
    }
}

/// Geometric altitude of the ICRS north pole equals observer latitude (any epoch).
#[test]
fn celestial_pole_altitude_matches_latitude_j2000() {
    let time = AstroTime::from_jd_utc(2_451_545.0);
    for lat_deg in [-60.0, -30.0, 0.0, 35.0, 51.5, 89.0] {
        let obs = observer_at(lat_deg, -5.0);
        let chain = FrameChain::r#for(time, obs);
        let h = chain.icrs_to_geometric_horizontal(POLE_DIR_ICRS);
        assert!(
            (h.altitude_rad - obs.latitude_rad).abs() < MAX_ALT_ERROR_RAD,
            "lat {lat_deg}°: alt {} rad vs expected {}",
            h.altitude_rad,
            obs.latitude_rad
        );
    }
}

/// Same at a later epoch (precession + nutation + ERA still preserve pole geometry).
#[test]
fn celestial_pole_altitude_matches_latitude_2020() {
    let time = AstroTime::from_jd_utc(2_459_223.5);
    let obs = observer_at(45.0, 6.0);
    let chain = FrameChain::r#for(time, obs);
    let h = chain.icrs_to_geometric_horizontal(POLE_DIR_ICRS);
    let err = (h.altitude_rad - obs.latitude_rad).abs();
    assert!(
        err < 1e-3,
        "pole alt error {err} rad at JD 2459223.5 (limit 1e-3)"
    );
}

/// When LMST ≈ 0 (pole hour angle 0 at RA=0), azimuth is north.
#[test]
fn celestial_pole_azimuth_north_on_meridian() {
    let time = AstroTime::from_jd_utc(2_451_545.0);
    let ra_pole = pole_ra_at_epoch(time);
    let lon_deg = (ra_pole - time.gmst()).to_degrees();
    let obs = observer_at(40.0, lon_deg);
    let chain = FrameChain::r#for(time, obs);
    let h = chain.icrs_to_geometric_horizontal(POLE_DIR_ICRS);
    assert!(h.azimuth_rad.abs() < 1e-5 || (h.azimuth_rad - std::f64::consts::TAU).abs() < 1e-5);
}

/// Refraction increases apparent altitude above geometric (mid-latitude, above horizon).
#[test]
fn refraction_raises_apparent_pole_slightly() {
    let obs = observer_at(45.0, 0.0);
    let time = AstroTime::from_jd_utc(2_451_545.0);
    let chain = FrameChain::r#for(time, obs);
    let geom = chain.icrs_to_geometric_horizontal(POLE_DIR_ICRS);
    let app = chain
        .icrs_to_apparent_horizontal(POLE_DIR_ICRS)
        .expect("refraction");
    assert!(app.altitude_rad > geom.altitude_rad);
    assert!(app.altitude_rad - geom.altitude_rad < 0.001); // < ~3 arcmin at 45°
}
