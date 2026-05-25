//! Per-frame snapshot assembly and ArcSwap publish hook.

use crate::types::{RenderConfig, ViewPose};

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
    /// Layer visibility and magnitude limit.
    pub render_config: RenderConfig,
    /// Active selection, if any (screen position is refreshed each frame).
    pub selected: Option<SelectedObject>,
}

/// Builds a [`SceneSnapshot`] with projected label hints from the dev star table.
pub fn build_snapshot(inputs: SnapshotInputs) -> SceneSnapshot {
    let labels = collect_label_hints(&inputs.view_pose, &inputs.render_config);
    let selected = inputs
        .selected
        .map(|sel| project_selected(sel, inputs.view_pose));

    SceneSnapshot {
        frame_id: inputs.frame_id,
        view_pose: inputs.view_pose,
        labels,
        selected,
    }
}

/// Publishes a snapshot into the lock-free slot (called once per rendered frame).
pub fn publish_snapshot(slot: &SnapshotSlot, inputs: SnapshotInputs) {
    publish(slot, build_snapshot(inputs));
}

fn collect_label_hints(view_pose: &ViewPose, config: &RenderConfig) -> Vec<LabelHint> {
    if !config.show_stars {
        return Vec::new();
    }

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
