//! HEALPix wrappers — cross-check against `cdshealpix` direct calls.

use cdshealpix::nested;
use nightshade_planetarium::catalog::healpix::{
    bounding_pixels_for_fov, depth_for_nside, pixel_for_direction, pixels_in_cone, HealpixError,
};
use nightshade_planetarium::types::{SkyProjection, ViewPose};

const NSIDE: u32 = 64;

fn depth() -> u8 {
    depth_for_nside(NSIDE).expect("test nside")
}

#[test]
fn pixel_for_direction_matches_nested_hash() {
    let cases: &[(f64, f64)] = &[
        (0.0, std::f64::consts::FRAC_PI_2),
        (1.762_786_157, 0.596_857_796),
        (1.895_652_880, -0.515_785_559),
    ];
    for &(ra, dec) in cases {
        let wrapped = pixel_for_direction(ra, dec, NSIDE).expect("pixel");
        let direct = nested::hash(depth(), ra, dec);
        assert_eq!(wrapped, direct, "ra={ra} dec={dec}");
    }
}

#[test]
fn pixels_in_cone_matches_centers_coverage() {
    let ra = 1.762_786_157;
    let dec = 0.596_857_796;
    let radius = 0.05;
    let wrapped = pixels_in_cone(ra, dec, radius, NSIDE).expect("cone");
    let direct: Vec<u64> = nested::cone_coverage_centers(depth(), ra, dec, radius)
        .into_flat_iter()
        .collect();
    assert_eq!(wrapped, direct);
    let center = pixel_for_direction(ra, dec, NSIDE).expect("center pixel");
    assert!(wrapped.contains(&center), "cone must include center pixel");
}

#[test]
fn bounding_pixels_for_fov_contains_boresight() {
    let pose = ViewPose {
        ra_rad: 1.762_786_157,
        dec_rad: 0.596_857_796,
        fov_rad: 0.35,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    let pixels = bounding_pixels_for_fov(pose, pose.fov_rad, NSIDE).expect("fov");
    let boresight = pixel_for_direction(pose.ra_rad, pose.dec_rad, NSIDE).expect("boresight");
    assert!(pixels.contains(&boresight));
    assert!(!pixels.is_empty());
}

#[test]
fn rejects_invalid_nside() {
    let err = pixel_for_direction(0.0, 0.0, 12).unwrap_err();
    assert!(matches!(err, HealpixError::InvalidNside(n) if n == 12));
}

#[test]
fn rejects_negative_cone_radius() {
    let err = pixels_in_cone(0.0, 0.0, -0.1, NSIDE).unwrap_err();
    assert!(matches!(err, HealpixError::InvalidRadius(_)));
}
