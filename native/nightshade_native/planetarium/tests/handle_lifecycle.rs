//! Planetarium handle lifecycle: create/drop tight loop without panic or leak.
//!
//! Does not call `Resize` / surface allocate — that requires a live Flutter engine
//! (see Task 15 integration tests). Exercises loop + snapshot + command path only.

use std::thread;
use std::time::Duration;

use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::types::ViewPose;
use nightshade_planetarium::{Planetarium, PlanetariumError};

const ITERATIONS: usize = 48;
const WAKE_TIMEOUT: Duration = Duration::from_millis(500);
const POLL: Duration = Duration::from_millis(2);

#[test]
fn create_drop_tight_loop_without_panic() {
    for _ in 0..ITERATIONS {
        let planetarium = Planetarium::new(0).expect("new succeeds without Flutter engine");
        assert_eq!(
            planetarium.texture_id(),
            Err(PlanetariumError::NotAllocated),
            "no fake texture id before resize"
        );
        drop(planetarium);
    }
}

#[test]
fn send_pose_publishes_snapshot_without_surface_allocate() {
    let planetarium = Planetarium::new(0).expect("new");
    assert_eq!(planetarium.texture_id(), Err(PlanetariumError::NotAllocated));

    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose {
            ra_rad: 1.25,
            ..ViewPose::default()
        }))
        .expect("send SetPose");

    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        if planetarium.snapshot().frame_id > 0 {
            break;
        }
        if std::time::Instant::now() >= deadline {
            panic!(
                "timed out waiting for snapshot publish; frame_id={}",
                planetarium.snapshot().frame_id
            );
        }
        thread::sleep(POLL);
    }

    assert_eq!(planetarium.texture_id(), Err(PlanetariumError::NotAllocated));
}
