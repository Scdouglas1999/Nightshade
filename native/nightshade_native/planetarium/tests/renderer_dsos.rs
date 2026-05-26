//! DSO sprite pipeline: OpenNGC fixture catalog + headless render smoke.

use std::path::PathBuf;

use nightshade_planetarium::catalog::{build_opengnc_catalog, parse_catalog};
use nightshade_planetarium::renderer::Scene;
use nightshade_planetarium::renderer::{
    collect_dso_instances_from_records, dso_surface_brightness, DsoInstance, Renderer,
};
use nightshade_planetarium::scene::build::BuildSceneInputs;
use nightshade_planetarium::types::{AstroTime, Observer, RenderConfig, SkyProjection, ViewPose};

const RENDER_SIZE: u32 = 256;

#[test]
fn m31_fixture_collects_and_renders_non_black_pixel() {
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/ngc_mini.csv");
    let out = std::env::temp_dir().join("nightshade_dsos_render_fixture.bin");
    if out.exists() {
        std::fs::remove_file(&out).expect("clean temp");
    }
    build_opengnc_catalog(&fixture, &out).expect("build fixture");

    let bytes = std::fs::read(&out).expect("read catalog");
    let parsed = parse_catalog(&bytes).expect("parse");
    let dso = &parsed.records[0];
    assert_eq!(dso.messier_num, 31);

    let sb = dso_surface_brightness(dso.size_arcmin[0], dso.size_arcmin[1], dso.surface_mag);
    assert!(sb.is_some());

    let pose = ViewPose {
        ra_rad: f64::from(dso.icrs_dir[1].atan2(dso.icrs_dir[0])),
        dec_rad: f64::from(dso.icrs_dir[2].clamp(-1.0, 1.0).asin()),
        fov_rad: 8.0_f32.to_radians(),
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    let inputs = BuildSceneInputs {
        view_pose: pose,
        render_config: RenderConfig {
            show_stars: false,
            show_dsos: true,
            show_milky_way: false,
            show_atmosphere: false,
            magnitude_limit: 12.0,
            ..RenderConfig::default()
        },
        observer: Observer::default(),
        astro_time: AstroTime::from_jd_utc(
            nightshade_planetarium::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC,
        ),
    };
    let instances = collect_dso_instances_from_records(parsed.records, inputs);
    assert_eq!(instances.len(), 1);

    let rgba = pollster::block_on(render_m31_scene(instances, pose));
    let mut max_luma = 0u8;
    for chunk in rgba.chunks_exact(4) {
        let luma = chunk[0].max(chunk[1]).max(chunk[2]);
        max_luma = max_luma.max(luma);
    }
    assert!(
        max_luma > 8,
        "expected visible DSO sprite pixels, max luma {max_luma}"
    );

    let _ = std::fs::remove_file(&out);
}

async fn render_m31_scene(dsos: Vec<DsoInstance>, pose: ViewPose) -> Vec<u8> {
    let (device, queue) = nightshade_planetarium::renderer::offscreen_device().await;
    let mut renderer = Renderer::new(
        device,
        queue,
        wgpu::TextureFormat::Rgba8UnormSrgb,
        RENDER_SIZE,
        RENDER_SIZE,
    );
    renderer.render(&Scene {
        view_pose: pose,
        config: RenderConfig {
            show_stars: false,
            show_dsos: true,
            show_milky_way: false,
            show_atmosphere: false,
            magnitude_limit: 12.0,
            ..RenderConfig::default()
        },
        dsos,
        ..Scene::default()
    });
    renderer.readback_rgba()
}
