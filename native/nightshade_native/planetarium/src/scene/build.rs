//! Render-thread [`Scene`](crate::renderer::Scene) assembly from catalog + view state.

use crate::animation::AnimationState;
use crate::catalog::healpix::{angular_separation_rad, pixel_center_radec, HealpixError};
use crate::catalog::CatalogSet;
use crate::renderer::{Scene, StarInstance};
use crate::scene::lod::{select_lod, tile_star_mag_limit, MagLimitConfig, QualityConfig};
use crate::scene::projection::project_icrs;
use crate::scene::visibility::{frustum_cap_radius_rad, visible_tiles};
use crate::types::{AstroTime, Observer, RenderConfig, ViewPose};

/// Inputs for building a GPU frame scene.
#[derive(Debug, Clone, Copy)]
pub struct BuildSceneInputs {
    /// Camera pose for this frame.
    pub view_pose: ViewPose,
    /// Layer visibility and magnitude limit.
    pub render_config: RenderConfig,
    /// Observer site (twinkle / extinction).
    pub observer: Observer,
    /// Epoch for the frame chain.
    pub astro_time: AstroTime,
}

/// Collect GPU star instances from registered catalog packs.
pub fn collect_star_instances(
    catalog: &CatalogSet,
    inputs: BuildSceneInputs,
) -> Result<Vec<StarInstance>, HealpixError> {
    if !inputs.render_config.show_stars || catalog.is_empty() {
        return Ok(Vec::new());
    }

    let quality = QualityConfig::from_tier(inputs.render_config.quality);
    let mag_cfg = MagLimitConfig::new(inputs.render_config.magnitude_limit);
    let cap_radius = frustum_cap_radius_rad(&inputs.view_pose, inputs.view_pose.fov_rad);
    let mut stars = Vec::new();

    for pack in catalog.packs() {
        let pixels = visible_tiles(inputs.view_pose, inputs.view_pose.fov_rad, pack.nside())?;
        for &pixel in &pixels {
            let tile_dist = pixel_center_radec(pixel, pack.nside())
                .map(|(ra, dec)| {
                    angular_separation_rad(
                        inputs.view_pose.ra_rad,
                        inputs.view_pose.dec_rad,
                        ra,
                        dec,
                    )
                })
                .unwrap_or(0.0);
            let tile_mag = tile_star_mag_limit(
                inputs.view_pose.fov_rad,
                quality,
                mag_cfg,
                tile_dist,
                cap_radius,
            );
            let Some(star_slice) = pack.stars_in_pixel(pixel) else {
                continue;
            };
            let draw_count = if let Some(lod_entries) = pack.lod_entries_for_pixel(pixel) {
                select_lod(&lod_entries, tile_mag).draw_count as usize
            } else {
                star_slice.len()
            };
            for star in star_slice.iter().take(draw_count) {
                if star.mag > tile_mag {
                    continue;
                }
                let (ra_rad, dec_rad) = radec_from_icrs_dir(star.icrs_dir);
                if project_icrs(ra_rad, dec_rad, inputs.view_pose).is_some() {
                    stars.push(star_instance_from_record(star));
                }
            }
        }
    }

    Ok(stars)
}

/// Build a full [`Scene`] for the production renderer.
pub fn build_render_scene(
    catalog: &CatalogSet,
    inputs: BuildSceneInputs,
    anim: &AnimationState,
) -> Result<Scene, HealpixError> {
    let stars = collect_star_instances(catalog, inputs)?;
    Ok(Scene {
        view_pose: inputs.view_pose,
        config: inputs.render_config,
        stars,
        observer: inputs.observer,
        astro_time: inputs.astro_time,
        twinkle_phase: anim.twinkle_phase,
    })
}

/// Map a catalog [`StarRecord`](crate::catalog::StarRecord) to a GPU instance.
#[must_use]
pub fn star_instance_from_record(star: &crate::catalog::StarRecord) -> StarInstance {
    StarInstance {
        icrs_dir: star.icrs_dir,
        mag: star.mag,
        bv: star.bv,
        flags: star.flags,
    }
}

#[inline]
fn radec_from_icrs_dir(dir: [f32; 3]) -> (f64, f64) {
    let x = f64::from(dir[0]);
    let y = f64::from(dir[1]);
    let z = f64::from(dir[2]);
    let dec_rad = z.clamp(-1.0, 1.0).asin();
    let ra_rad = y.atan2(x);
    (ra_rad, dec_rad)
}
