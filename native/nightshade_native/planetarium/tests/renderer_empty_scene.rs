//! Golden test: empty scene renders pure black at 64×64.

use nightshade_planetarium::renderer::{render_empty_scene_rgba, FRAME_CLEAR};

const GOLDEN_SIZE: u32 = 64;

#[test]
fn empty_scene_is_pure_black_64x64() {
    let pixels = render_empty_scene_rgba(GOLDEN_SIZE, GOLDEN_SIZE);
    assert_eq!(
        pixels.len(),
        (GOLDEN_SIZE * GOLDEN_SIZE * 4) as usize,
        "readback size mismatch"
    );

    let expected_r = (FRAME_CLEAR.r * 255.0).round() as u8;
    let expected_g = (FRAME_CLEAR.g * 255.0).round() as u8;
    let expected_b = (FRAME_CLEAR.b * 255.0).round() as u8;
    let expected_a = (FRAME_CLEAR.a * 255.0).round() as u8;

    for (i, chunk) in pixels.chunks_exact(4).enumerate() {
        let (r, g, b, a) = (chunk[0], chunk[1], chunk[2], chunk[3]);
        assert_eq!(
            (r, g, b, a),
            (expected_r, expected_g, expected_b, expected_a),
            "pixel {i} not black: ({r},{g},{b},{a})"
        );
    }
}
