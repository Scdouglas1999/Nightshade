//! Planetarium handle lifecycle: create/drop tight loop without panic or leak.
//!
//! Does not call `Resize` / surface allocate — that requires a live Flutter engine
//! (see Task 15 integration tests). Exercises loop + snapshot + command path only.

use std::thread;
use std::time::{Duration, Instant};

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
fn frame_id_monotonic_across_error_recovery() {
    // Each call to `render_frame` must advance `frame_id` by exactly 1, regardless
    // of whether scene building succeeded. The previous implementation incremented
    // inside the error branch AND inside the happy-path branch — correct only
    // because of an early-return, and fragile against future refactors.
    //
    // We send a sequence of commands that each guarantee at least one render,
    // sample frame_id after each, and assert strict +1 monotonicity.
    let planetarium = Planetarium::new(0).expect("new");

    let mut last = planetarium.snapshot().frame_id;
    for step in 0..8 {
        // Distinct AstroTime per step guarantees the render loop processes a
        // fresh command instead of coalescing into the previous dirty cycle.
        let jd = 2_451_545.0 + (step as f64) * 0.001;
        planetarium
            .send(PlanetariumCommand::SetTime(AstroTime::from_jd_utc(jd)))
            .expect("wake");

        let deadline = Instant::now() + WAKE_TIMEOUT;
        let next = loop {
            let now = planetarium.snapshot().frame_id;
            if now > last {
                break now;
            }
            if Instant::now() >= deadline {
                panic!("timed out waiting for frame after {last} at step {step}");
            }
            thread::sleep(POLL);
        };

        assert_eq!(
            next,
            last + 1,
            "frame_id must advance by exactly 1 each render (step {step}, last={last})",
        );
        last = next;
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

    let gen_after_first = planetarium.resize_generation();
    resize(128, 128);
    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        if planetarium.resize_generation() > gen_after_first
            && planetarium.last_surface_error().is_some()
        {
            return;
        }
        if std::time::Instant::now() >= deadline {
            panic!(
                "timed out waiting for second resize; gen={} (after {gen_after_first}), err={:?}",
                planetarium.resize_generation(),
                planetarium.last_surface_error()
            );
        }
        thread::sleep(POLL);
    }
}
