//! Tile residency LRU: FOV pan simulation with cap 8.

use std::collections::BTreeSet;

use nightshade_planetarium::catalog::healpix::bounding_pixels_for_fov;
use nightshade_planetarium::catalog::TileResidency;
use nightshade_planetarium::types::{SkyProjection, ViewPose};

const CAP: usize = 8;
const NSIDE: u32 = 8;
const WARMUP_SCALE: f32 = 1.5;

fn pan_poses() -> Vec<ViewPose> {
    let dec = 0.55;
    let fov = 0.22_f32;
    (0..24)
        .map(|step| ViewPose {
            ra_rad: step as f64 * 0.18,
            dec_rad: dec,
            fov_rad: fov,
            roll_rad: 0.0,
            projection: SkyProjection::Stereographic,
        })
        .collect()
}

#[test]
fn fov_pan_respects_cap_and_lru_eviction() {
    let mut residency = TileResidency::new(CAP);
    let mut ever_loaded = BTreeSet::new();
    let mut total_evicted = 0usize;

    for pose in pan_poses() {
        let delta = residency
            .sync_visibility(pose, NSIDE, WARMUP_SCALE, |id| id as u32 % 100 + 1)
            .expect("sync_visibility");

        for id in &delta.loaded {
            ever_loaded.insert(*id);
        }
        total_evicted += delta.evicted.len();

        assert!(
            residency.len() <= CAP,
            "resident count {} exceeds cap {CAP}",
            residency.len()
        );
    }

    assert!(
        ever_loaded.len() > CAP,
        "pan simulation must touch more than {CAP} distinct tiles"
    );
    assert!(
        total_evicted > 0,
        "LRU must evict when panning across {CAP}-tile cap"
    );
    assert!(
        residency.eviction_count() > 0,
        "eviction counter must advance"
    );
}

#[test]
fn stale_tiles_evicted_before_warmup_neighbors() {
    let mut residency = TileResidency::new(CAP);

    let anchor = ViewPose {
        ra_rad: 1.2,
        dec_rad: 0.4,
        fov_rad: 0.2,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    let anchor_fov =
        bounding_pixels_for_fov(anchor, anchor.fov_rad, NSIDE).expect("anchor fov");
    let anchor_ring =
        bounding_pixels_for_fov(anchor, anchor.fov_rad * WARMUP_SCALE, NSIDE).expect("anchor ring");

    residency.sync_pixel_sets(&anchor_fov, &anchor_ring, |_| 5);

    let stale_id = 999_999_u64;
    residency.sync_pixel_sets(&[stale_id], &[], |_| 3);
    assert!(residency.get(stale_id).is_some());

    let far = ViewPose {
        ra_rad: anchor.ra_rad + 2.5,
        dec_rad: -0.35,
        fov_rad: anchor.fov_rad,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    let far_fov = bounding_pixels_for_fov(far, far.fov_rad, NSIDE).expect("far fov");
    let far_ring =
        bounding_pixels_for_fov(far, far.fov_rad * WARMUP_SCALE, NSIDE).expect("far ring");

    while residency.len() >= CAP {
        let delta = residency.sync_pixel_sets(&far_fov, &far_ring, |_| 7);
        if delta.evicted.contains(&stale_id) {
            break;
        }
    }

    assert!(
        residency.get(stale_id).is_none(),
        "tile outside warmup must be evicted before ring/FOV tiles when over cap"
    );
}
