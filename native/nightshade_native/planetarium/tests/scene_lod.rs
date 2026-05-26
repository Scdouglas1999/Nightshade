//! LOD selector — zoom / quality / mag limit per tile.

use nightshade_planetarium::catalog::hyg_build::HYG_LOD_MAG_THRESHOLDS;
use nightshade_planetarium::catalog::LodEntry;
use nightshade_planetarium::scene::lod::{
    fov_zoom_mag_boost, frame_star_mag_limit, select_lod, tile_star_mag_limit, LodSelection,
    MagLimitConfig, QualityConfig, FOV_MAG_BOOST_CAP, REF_FOV_DEG, STAR_MAG_CEILING,
    STAR_MAG_FLOOR,
};
use nightshade_planetarium::scene::visibility::frustum_cap_radius_rad;
use nightshade_planetarium::types::{SkyProjection, ViewPose};

fn deg(deg: f32) -> f32 {
    deg.to_radians()
}

fn quality_balanced() -> QualityConfig {
    QualityConfig::from_tier(1)
}

fn mag_user(limit: f32) -> MagLimitConfig {
    MagLimitConfig::new(limit)
}

#[test]
fn fov_zoom_boost_increases_as_fov_narrows() {
    let wide = fov_zoom_mag_boost(deg(120.0));
    let medium = fov_zoom_mag_boost(deg(30.0));
    let narrow = fov_zoom_mag_boost(deg(5.0));
    assert!((wide - 0.0).abs() < 1e-5, "120° FOV should add no boost");
    assert!(medium > wide);
    assert!(narrow > medium);
    assert!(narrow <= FOV_MAG_BOOST_CAP);
}

#[test]
fn frame_mag_limit_scales_with_several_zoom_levels() {
    let quality = QualityConfig::from_tier(0);
    let mag = mag_user(12.0);

    let wide = frame_star_mag_limit(deg(120.0), quality, mag);
    let mid = frame_star_mag_limit(deg(60.0), quality, mag);
    let narrow = frame_star_mag_limit(deg(10.0), quality, mag);
    let deep = frame_star_mag_limit(deg(1.0), quality, mag);

    assert!((wide - 6.0).abs() < 1e-4, "low tier base at wide FOV");
    assert!(mid > wide);
    assert!(narrow > mid);
    assert!(deep >= narrow);
    assert!(deep <= STAR_MAG_CEILING);
    assert!(wide >= STAR_MAG_FLOOR);
}

#[test]
fn user_mag_cap_limits_frame_limit() {
    let quality = QualityConfig::from_tier(2);
    let tight_user = mag_user(7.0);
    let wide = frame_star_mag_limit(deg(120.0), quality, tight_user);
    assert!((wide - 7.0).abs() < 1e-4);
}

#[test]
fn tile_limit_softens_at_frustum_edge() {
    let quality = quality_balanced();
    let mag = mag_user(10.0);
    let fov = deg(20.0);
    let pose = ViewPose {
        ra_rad: 0.5,
        dec_rad: 0.2,
        fov_rad: fov,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    let cap = frustum_cap_radius_rad(&pose, fov);

    let center = tile_star_mag_limit(fov, quality, mag, 0.0, cap);
    let edge = tile_star_mag_limit(fov, quality, mag, cap, cap);
    assert!(edge <= center);
    assert!(center - edge <= 1.0 + 1e-5);
}

#[test]
fn select_lod_includes_bands_up_to_mag_limit() {
    let entries: Vec<LodEntry> = HYG_LOD_MAG_THRESHOLDS
        .iter()
        .enumerate()
        .map(|(i, &threshold)| LodEntry {
            mag_threshold: threshold,
            start_offset: (i * 10) as u32,
            count: 10,
            reserved: 0,
        })
        .collect();

    let at_six: LodSelection = select_lod(&entries, 6.0);
    assert_eq!(at_six.lod_level_index, Some(2)); // 2.5, 4.0, 6.0
    assert_eq!(at_six.draw_count, 30);

    let at_three: LodSelection = select_lod(&entries, 3.0);
    assert_eq!(at_three.lod_level_index, Some(0));
    assert_eq!(at_three.draw_count, 10);

    let beyond_pack: LodSelection = select_lod(&entries, 20.0);
    assert_eq!(
        beyond_pack.lod_level_index,
        Some((entries.len() - 1) as u32)
    );
    assert_eq!(beyond_pack.draw_count, entries.len() as u32 * 10);
}

#[test]
fn select_lod_empty_table() {
    let sel = select_lod(&[], 8.0);
    assert_eq!(sel.lod_level_index, None);
    assert_eq!(sel.draw_count, 0);
}

#[test]
fn reference_fov_constant_matches_v1() {
    assert!((REF_FOV_DEG - 120.0).abs() < f32::EPSILON);
}
