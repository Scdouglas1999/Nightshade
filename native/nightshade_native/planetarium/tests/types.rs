use nightshade_planetarium::types::{SkyProjection, ViewPose};

#[test]
fn view_pose_default_is_zenith() {
    let p = ViewPose::default();
    assert_eq!(p.fov_rad, std::f32::consts::FRAC_PI_2);
    assert!(matches!(p.projection, SkyProjection::Stereographic));
}
