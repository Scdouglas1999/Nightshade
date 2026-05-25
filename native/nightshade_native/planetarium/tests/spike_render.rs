//! Verifies wgpu can produce a non-empty triangle on the host running tests.
//!
//! Skipped automatically if no GPU adapter is available (CI without GPU).

use nightshade_planetarium::spike::{render_triangle, SPIKE_SIZE};

#[test]
fn triangle_has_red_pixel_near_top() {
    let pixels = render_triangle();
    assert_eq!(pixels.len(), (SPIKE_SIZE * SPIKE_SIZE * 4) as usize);

    // Sample a pixel inside the red corner of the triangle.
    let x = SPIKE_SIZE / 2;
    let y = SPIKE_SIZE / 6;
    let idx = ((y * SPIKE_SIZE + x) * 4) as usize;
    let (r, g, b) = (pixels[idx], pixels[idx + 1], pixels[idx + 2]);
    assert!(r > 180 && g < 40 && b < 40, "expected reddish pixel, got ({r},{g},{b})");
}
