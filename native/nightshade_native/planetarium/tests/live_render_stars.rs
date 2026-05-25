//! Integration: fake in-memory pack produces a non-empty GPU star scene.

use std::borrow::Cow;
use std::collections::HashMap;

use nightshade_planetarium::animation::AnimationState;
use nightshade_planetarium::catalog::{pixel_for_direction, CatalogSet, StarPack, StarRecord};
use nightshade_planetarium::renderer::{Renderer, FRAME_CLEAR};
use nightshade_planetarium::scene::{build_render_scene, BuildSceneInputs};
use nightshade_planetarium::types::{AstroTime, Observer, RenderConfig, SkyProjection, ViewPose};
use nightshade_planetarium::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC;

struct FakePack {
    id: &'static str,
    nside: u32,
    tiles: HashMap<u64, Vec<StarRecord>>,
}

impl FakePack {
    fn vega_cluster() -> Self {
        let nside = 64;
        let vega = (4.872_013, 0.676_757, 0.03_f32, 91262_u32);
        let sirius = (1.767_015, -0.291_808, -1.46_f32, 32349_u32);
        let mut tiles: HashMap<u64, Vec<StarRecord>> = HashMap::new();
        for &(ra, dec, mag, hip) in &[vega, sirius] {
            let pixel = pixel_for_direction(ra, dec, nside).expect("pixel");
            tiles.entry(pixel).or_default().push(StarRecord::from_radec(
                hip,
                ra as f32,
                dec as f32,
                mag,
                f32::NAN,
                0,
            ));
        }
        Self {
            id: "fake-live",
            nside,
            tiles,
        }
    }
}

impl StarPack for FakePack {
    fn pack_id(&self) -> &str {
        self.id
    }

    fn nside(&self) -> u32 {
        self.nside
    }

    fn stars_in_pixel(&self, healpix_id: u64) -> Option<Cow<'_, [StarRecord]>> {
        self.tiles
            .get(&healpix_id)
            .map(|v| Cow::Borrowed(v.as_slice()))
    }

    fn build_hit_index(&self) -> nightshade_planetarium::catalog::HitIndex {
        let mut idx = nightshade_planetarium::catalog::HitIndex::new(self.nside);
        for stars in self.tiles.values() {
            for &star in stars {
                idx.insert_star(star).expect("insert");
            }
        }
        idx
    }
}

#[test]
fn catalog_pack_yields_non_empty_star_scene() {
    let mut catalog = CatalogSet::new();
    catalog.register(Box::new(FakePack::vega_cluster()));

    let pose = ViewPose {
        ra_rad: 4.872_013,
        dec_rad: 0.676_757,
        fov_rad: 0.5,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    let inputs = BuildSceneInputs {
        view_pose: pose,
        render_config: RenderConfig {
            show_stars: true,
            magnitude_limit: 6.0,
            ..Default::default()
        },
        observer: Observer::default(),
        astro_time: AstroTime::from_jd_utc(DEFAULT_ASTRO_TIME_JD_UTC),
    };

    let scene = build_render_scene(&catalog, inputs, &AnimationState::INACTIVE)
        .expect("scene");
    assert!(
        !scene.stars.is_empty(),
        "registered pack must populate Scene.stars"
    );
}

#[test]
fn catalog_stars_render_non_black_pixels_offscreen() {
    let mut catalog = CatalogSet::new();
    catalog.register(Box::new(FakePack::vega_cluster()));

    let pose = ViewPose {
        ra_rad: 4.872_013,
        dec_rad: 0.676_757,
        fov_rad: 0.5,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    let inputs = BuildSceneInputs {
        view_pose: pose,
        render_config: RenderConfig {
            show_stars: true,
            magnitude_limit: 6.0,
            ..Default::default()
        },
        observer: Observer::default(),
        astro_time: AstroTime::from_jd_utc(DEFAULT_ASTRO_TIME_JD_UTC),
    };
    let scene = build_render_scene(&catalog, inputs, &AnimationState::INACTIVE)
        .expect("scene");
    assert!(!scene.stars.is_empty());

    let pixels = pollster::block_on(async {
        let (device, queue) = nightshade_planetarium::renderer::offscreen_device().await;
        let mut renderer = Renderer::new(
            device,
            queue,
            wgpu::TextureFormat::Rgba8UnormSrgb,
            256,
            256,
        );
        renderer.render(&scene);
        renderer.readback_rgba()
    });

    let black = (
        (FRAME_CLEAR.r * 255.0).round() as u8,
        (FRAME_CLEAR.g * 255.0).round() as u8,
        (FRAME_CLEAR.b * 255.0).round() as u8,
    );
    let bright_count = pixels
        .chunks_exact(4)
        .filter(|c| (c[0], c[1], c[2]) != black)
        .count();
    assert!(
        bright_count > 0,
        "GPU render must draw at least one non-black pixel for catalog stars"
    );
}
