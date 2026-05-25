//! Star draw smoke / perf (Task 49): large instance counts complete without panic.

use std::time::Instant;

use nightshade_planetarium::renderer::{three_star_instances, Renderer, Scene, StarInstance};
use nightshade_planetarium::types::{RenderConfig, SkyProjection, ViewPose};

const SMOKE_INSTANCES: usize = 50_000;
const TARGET_5M: usize = 5_000_000;
/// Budget for 5M instanced quads at 256×256 (draw + readback, not a strict 60 fps gate).
const BUDGET_5M_MS: u128 = 500;

fn smoke_view_pose() -> ViewPose {
    ViewPose {
        ra_rad: 0.0,
        dec_rad: 0.5,
        fov_rad: 60.0_f32.to_radians(),
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    }
}

/// Many instances clustered around the golden three-star directions (known in-FOV).
fn synthetic_instances(count: usize) -> Vec<StarInstance> {
    let seeds = three_star_instances();
    let mut stars = Vec::with_capacity(count);
    for i in 0..count {
        let seed = seeds[i % seeds.len()];
        let jitter = (i as f32 * 1e-4) % 0.02;
        stars.push(StarInstance {
            icrs_dir: [
                seed.icrs_dir[0] + jitter,
                seed.icrs_dir[1],
                seed.icrs_dir[2],
            ],
            mag: seed.mag,
            bv: seed.bv,
            flags: 0,
        });
    }
    stars
}

fn smoke_scene(stars: Vec<StarInstance>) -> Scene {
    Scene {
        view_pose: smoke_view_pose(),
        config: RenderConfig {
            show_stars: true,
            magnitude_limit: 12.0,
            ..Default::default()
        },
        stars,
        ..Scene::default()
    }
}

#[test]
fn stars_smoke_50k_instances_complete() {
    pollster::block_on(async {
        let (device, queue) = nightshade_planetarium::renderer::offscreen_device().await;
        let mut renderer = Renderer::new(
            device,
            queue,
            wgpu::TextureFormat::Rgba8UnormSrgb,
            256,
            256,
        );
        renderer.render(&smoke_scene(synthetic_instances(SMOKE_INSTANCES)));
    });
}

/// Run locally: `cargo test -p nightshade_planetarium stars_5m_draw_within_budget -- --ignored --nocapture`
#[test]
#[ignore = "GPU perf smoke: 5M instanced stars (Task 49 budget check)"]
fn stars_5m_draw_within_budget() {
    let scene = smoke_scene(synthetic_instances(TARGET_5M));
    let elapsed = pollster::block_on(async {
        let (device, queue) = nightshade_planetarium::renderer::offscreen_device().await;
        let mut renderer = Renderer::new(
            device,
            queue,
            wgpu::TextureFormat::Rgba8UnormSrgb,
            256,
            256,
        );
        let start = Instant::now();
        renderer.render(&scene);
        let _ = renderer.readback_rgba();
        start.elapsed()
    });

    eprintln!(
        "5M stars render+readback: {:.1} ms (budget {BUDGET_5M_MS} ms)",
        elapsed.as_secs_f64() * 1000.0
    );
    assert!(
        elapsed.as_millis() <= BUDGET_5M_MS,
        "5M star draw exceeded {BUDGET_5M_MS} ms — profile on reference desktop"
    );
}
