//! Per-frame snapshot assembly and ArcSwap publish hook.

use crate::catalog::CatalogSet;
use crate::types::{AstroTime, Observer, RenderConfig, ViewPose};

use super::dev_catalog::DEV_STARS;
use super::projection::project_icrs;
use super::{
    publish, LabelCategory, LabelHint, SceneSnapshot, SelectedObject, SmallString, SnapshotSlot,
};

/// Inputs required to build and publish one frame snapshot.
#[derive(Debug, Clone)]
pub struct SnapshotInputs {
    /// Monotonic frame counter for this publish.
    pub frame_id: u64,
    /// Camera pose used for projection.
    pub view_pose: ViewPose,
    /// Astronomical time for this frame.
    pub astro_time: AstroTime,
    /// Observer site for this frame.
    pub observer: Observer,
    /// Layer visibility and magnitude limit.
    pub render_config: RenderConfig,
    /// Active selection, if any (screen position is refreshed each frame).
    pub selected: Option<SelectedObject>,
}

/// Builds a [`SceneSnapshot`] with projected label hints from catalog or dev stars.
pub fn build_snapshot(catalog: &CatalogSet, inputs: SnapshotInputs) -> SceneSnapshot {
    let labels = collect_label_hints(catalog, &inputs.view_pose, &inputs.render_config);
    let selected = inputs
        .selected
        .map(|sel| project_selected(sel, inputs.view_pose));

    SceneSnapshot {
        frame_id: inputs.frame_id,
        view_pose: inputs.view_pose,
        astro_time: inputs.astro_time,
        observer: inputs.observer,
        labels,
        selected,
    }
}

/// Publishes a snapshot into the lock-free slot (called once per rendered frame).
pub fn publish_snapshot(slot: &SnapshotSlot, catalog: &CatalogSet, inputs: SnapshotInputs) {
    publish(slot, build_snapshot(catalog, inputs));
}

fn collect_label_hints(
    catalog: &CatalogSet,
    view_pose: &ViewPose,
    config: &RenderConfig,
) -> Vec<LabelHint> {
    if !config.show_stars {
        return Vec::new();
    }

    if catalog.is_empty() {
        return collect_dev_label_hints(view_pose, config);
    }

    let mut labels = Vec::new();
    let query = catalog
        .query(*view_pose, config.magnitude_limit)
        .expect("catalog visibility query must not fail with registered packs");
    for hit in query {
        let (ra_rad, dec_rad) = radec_from_icrs_dir(hit.star.icrs_dir);
        let Some((screen_x, screen_y)) = project_icrs(ra_rad, dec_rad, *view_pose) else {
            continue;
        };
        labels.push(LabelHint {
            object_id: u64::from(hit.star.hip_id),
            screen_x,
            screen_y,
            apparent_mag: hit.star.mag,
            priority: label_priority(hit.star.mag),
            text: star_display_name(hit.star.hip_id),
            category: LabelCategory::Star,
        });
    }
    labels
}

fn collect_dev_label_hints(view_pose: &ViewPose, config: &RenderConfig) -> Vec<LabelHint> {
    let mut labels = Vec::with_capacity(DEV_STARS.len());
    for star in DEV_STARS {
        if star.mag > config.magnitude_limit {
            continue;
        }
        let Some((screen_x, screen_y)) = project_icrs(star.ra_rad, star.dec_rad, *view_pose)
        else {
            continue;
        };
        labels.push(LabelHint {
            object_id: star.hip,
            screen_x,
            screen_y,
            apparent_mag: star.mag,
            priority: label_priority(star.mag),
            text: SmallString::new(star.name),
            category: LabelCategory::Star,
        });
    }
    labels
}

fn star_display_name(hip_id: u32) -> SmallString {
    DEV_STARS
        .iter()
        .find(|s| s.hip == u64::from(hip_id))
        .map(|s| SmallString::new(s.name))
        .unwrap_or_else(|| SmallString::new(format!("HIP {hip_id}")))
}

fn project_selected(mut sel: SelectedObject, view_pose: ViewPose) -> SelectedObject {
    if let Some((screen_x, screen_y)) = project_icrs(sel.ra_rad, sel.dec_rad, view_pose) {
        sel.screen_x = screen_x;
        sel.screen_y = screen_y;
    }
    sel
}

fn label_priority(apparent_mag: f32) -> u8 {
    (10.0 - apparent_mag).clamp(0.0, 255.0) as u8
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
