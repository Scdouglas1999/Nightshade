//! Planetarium handle lifecycle: create/drop tight loop without panic or leak.
//!
//! Does not call `Resize` / surface allocate — that requires a live Flutter engine
//! (see Task 15 integration tests). Exercises loop + snapshot + command path only.

use std::thread;
use std::time::Duration;

use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::types::{AstroTime, Observer, ViewPose};
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

#[test]
fn set_time_and_observer_appear_in_published_snapshot() {
    let planetarium = Planetarium::new(0).expect("new");
    let time = AstroTime::from_jd_utc(2_459_223.5);
    let observer = Observer {
        latitude_rad: 0.5,
        longitude_rad: -1.2,
        elevation_m: 1200.0,
        pressure_hpa: 900.0,
        temperature_c: -5.0,
    };

    planetarium
        .send(PlanetariumCommand::SetTime(time))
        .expect("SetTime");
    planetarium
        .send(PlanetariumCommand::SetObserver(observer))
        .expect("SetObserver");
    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose::default()))
        .expect("SetPose");

    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        let snap = planetarium.snapshot();
        if snap.frame_id > 0 && snap.astro_time == time && snap.observer == observer {
            return;
        }
        if std::time::Instant::now() >= deadline {
            let snap = planetarium.snapshot();
            panic!(
                "timed out; frame_id={} time={:?} observer={:?}",
                snap.frame_id, snap.astro_time, snap.observer
            );
        }
        thread::sleep(POLL);
    }
}

#[test]
fn resize_clears_surface_error_before_retry() {
    let planetarium = Planetarium::new(0).expect("new");
    let resize = |w, h| {
        planetarium
            .send(PlanetariumCommand::Resize {
                width: w,
                height: h,
                dpr: 1.0,
            })
            .expect("send Resize")
    };

    resize(64, 64);
    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        if planetarium.last_surface_error().is_some() {
            break;
        }
        if std::time::Instant::now() >= deadline {
            panic!("timed out waiting for first resize failure");
        }
        thread::sleep(POLL);
    }

    resize(128, 128);
    let mut saw_clear = false;
    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        if planetarium.last_surface_error().is_none() {
            saw_clear = true;
        }
        if saw_clear && planetarium.last_surface_error().is_some() {
            break;
        }
        if std::time::Instant::now() >= deadline {
            panic!(
                "timed out waiting for surface_error clear on retry; saw_clear={saw_clear}"
            );
        }
        thread::sleep(POLL);
    }
    assert!(
        saw_clear,
        "second resize should clear surface_error before surface.resize runs"
    );
}
