//! Star twinkle visual smoke (Task 50): GPU frames differ when animation phase advances.

use nightshade_planetarium::renderer::{
    render_scene_rgba, render_three_stars_rgba, star_altitude_rad, three_star_instances,
    three_stars_twinkle_scene, twinkle_altitude_gate, twinkle_brightness_delta, twinkle_enabled,
    THREE_STARS_SIZE,
};
use nightshade_planetarium::types::RenderConfig;

fn max_channel_delta(a: &[u8], b: &[u8]) -> u8 {
    a.chunks_exact(4)
        .zip(b.chunks_exact(4))
        .map(|(ca, cb)| {
            ca.iter()
                .zip(cb.iter())
                .map(|(x, y)| x.abs_diff(*y))
                .max()
                .unwrap_or(0)
        })
        .max()
        .unwrap_or(0)
}

#[test]
fn twinkle_off_matches_static_golden_path() {
    let off = render_three_stars_rgba();
    let mut scene = three_stars_twinkle_scene(0.0);
    scene.config.twinkle = false;
    let disabled = render_scene_rgba(&scene);
    assert_eq!(off.len(), disabled.len());
    assert_eq!(max_channel_delta(&off, &disabled), 0);
}

#[test]
fn twinkle_phase_changes_frame_when_altitude_gate_active() {
    let scene = three_stars_twinkle_scene(0.0);
    let mut any_gate = false;
    for inst in three_star_instances() {
        let alt = star_altitude_rad(&scene, inst.icrs_dir);
        if twinkle_altitude_gate(alt) > 0.0
            && twinkle_brightness_delta(std::f32::consts::FRAC_PI_2, 0.0, inst.mag, alt, 1.0) > 0.05
        {
            any_gate = true;
        }
    }
    if !any_gate {
        eprintln!("skip GPU twinkle diff: golden stars above 30° at default observer");
        return;
    }

    let frame_a = render_scene_rgba(&three_stars_twinkle_scene(0.0));
    let frame_b = render_scene_rgba(&three_stars_twinkle_scene(std::f32::consts::FRAC_PI_2));
    assert_eq!(frame_a.len(), (THREE_STARS_SIZE * THREE_STARS_SIZE * 4) as usize);
    assert!(
        max_channel_delta(&frame_a, &frame_b) >= 2,
        "twinkle phase π/2 should change star brightness"
    );
}

#[test]
fn twinkle_config_gate_zeroes_shader_uniform() {
    let cfg = RenderConfig {
        twinkle: false,
        show_stars: true,
        show_atmosphere: true,
        ..Default::default()
    };
    assert_eq!(twinkle_enabled(&cfg), 0.0);
}
