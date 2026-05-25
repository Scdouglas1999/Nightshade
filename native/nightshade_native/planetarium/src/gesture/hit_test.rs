//! Dev-catalog screen picking until the HEALPix hit index lands (Task 72).

use crate::scene::dev_catalog::DEV_STARS;
use crate::scene::{LabelCategory, SelectedObject, SmallString};
use crate::scene::projection::project_icrs;
use crate::types::ViewPose;

/// Maximum normalized screen distance for a tap hit.
const PICK_RADIUS: f32 = 0.06;

/// Picks the nearest dev-catalog star under `(x, y)` in normalized screen space.
pub fn hit_test_dev_catalog(x: f32, y: f32, pose: ViewPose) -> Option<SelectedObject> {
    let mut best: Option<SelectedObject> = None;
    let mut best_dist = f32::MAX;

    for star in DEV_STARS {
        let Some((sx, sy)) = project_icrs(star.ra_rad, star.dec_rad, pose) else {
            continue;
        };
        let dist = (sx - x).hypot(sy - y);
        if dist <= PICK_RADIUS && dist < best_dist {
            best_dist = dist;
            best = Some(SelectedObject {
                object_id: star.hip,
                screen_x: sx,
                screen_y: sy,
                ra_rad: star.ra_rad,
                dec_rad: star.dec_rad,
                category: LabelCategory::Star,
                display_name: SmallString::new(star.name),
            });
        }
    }

    best
}
