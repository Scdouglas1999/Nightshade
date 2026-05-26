//! Scene visibility cull — frustum → HEALPix tile set.

use nightshade_planetarium::catalog::healpix::{
    bounding_pixels_for_fov, pixel_for_direction, HealpixError,
};
use nightshade_planetarium::scene::visibility::{frustum_cap_radius_rad, visible_tiles};
use nightshade_planetarium::types::{SkyProjection, ViewPose};

const NSIDE: u32 = 32;

fn pose_at(ra: f64, dec: f64, fov_rad: f32, projection: SkyProjection) -> ViewPose {
    ViewPose {
        ra_rad: ra,
        dec_rad: dec,
        fov_rad,
        roll_rad: 0.0,
        projection,
    }
}

#[test]
fn visible_tiles_contains_boresight_all_projections() {
    let ra = 1.762_786_157;
    let dec = 0.596_857_796;
    let fov = 0.35f32;
    for projection in [
        SkyProjection::Stereographic,
        SkyProjection::Orthographic,
        SkyProjection::AzimuthalEquidistant,
    ] {
        let pose = pose_at(ra, dec, fov, projection);
        let tiles = visible_tiles(pose, fov, NSIDE).expect("visible_tiles");
        let boresight = pixel_for_direction(ra, dec, NSIDE).expect("boresight");
        assert!(
            tiles.contains(&boresight),
            "frustum must include boresight tile for {projection:?}"
        );
        assert!(!tiles.is_empty());
    }
}

#[test]
fn visible_tiles_matches_healpix_bounding_pixels() {
    let pose = pose_at(0.4, 0.2, 0.2, SkyProjection::Stereographic);
    let from_scene = visible_tiles(pose, pose.fov_rad, NSIDE).expect("scene");
    let from_catalog = bounding_pixels_for_fov(pose, pose.fov_rad, NSIDE).expect("catalog");
    assert_eq!(from_scene, from_catalog);
}

#[test]
fn visible_tiles_sorted_nested_order() {
    let pose = pose_at(2.1, -0.3, 0.5, SkyProjection::Orthographic);
    let tiles = visible_tiles(pose, pose.fov_rad, NSIDE).expect("tiles");
    let mut sorted = tiles.clone();
    sorted.sort_unstable();
    assert_eq!(tiles, sorted, "tile ids must be sorted ascending");
}

#[test]
fn larger_fov_is_superset_of_smaller_fov() {
    let pose = pose_at(0.9, 0.4, 0.15, SkyProjection::AzimuthalEquidistant);
    let small = visible_tiles(pose, 0.15, NSIDE).expect("small");
    let large = visible_tiles(pose, 0.45, NSIDE).expect("large");
    for id in &small {
        assert!(
            large.contains(id),
            "tile {id} visible at 0.15 rad must appear at 0.45 rad"
        );
    }
}

#[test]
fn frustum_cap_radius_positive_and_finite() {
    let pose = pose_at(0.0, 0.5, 0.25, SkyProjection::Stereographic);
    let r = frustum_cap_radius_rad(&pose, pose.fov_rad);
    assert!(r.is_finite() && r > 0.0);
}

#[test]
fn rejects_invalid_nside() {
    let pose = pose_at(0.0, 0.0, 0.2, SkyProjection::Stereographic);
    let err = visible_tiles(pose, pose.fov_rad, 12).unwrap_err();
    assert!(matches!(err, HealpixError::InvalidNside(12)));
}

#[test]
fn rejects_non_positive_fov() {
    let pose = pose_at(0.0, 0.0, 0.2, SkyProjection::Stereographic);
    let err = visible_tiles(pose, 0.0, NSIDE).unwrap_err();
    assert!(matches!(err, HealpixError::InvalidFov(_)));
}
