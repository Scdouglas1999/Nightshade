//! Mount and target tracking integration on the render loop.

use std::thread;
use std::time::{Duration, Instant};

use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC;
use nightshade_planetarium::scene::{MountPosition, PoseLock, TrackingTarget};
use nightshade_planetarium::types::AstroTime;
use nightshade_planetarium::Planetarium;

const WAKE_TIMEOUT: Duration = Duration::from_millis(500);
const POLL: Duration = Duration::from_millis(2);

fn wait_for_frame(planetarium: &Planetarium) -> u64 {
    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        let frame_id = planetarium.snapshot().frame_id;
        if frame_id > 0 {
            return frame_id;
        }
        if Instant::now() >= deadline {
            panic!("timed out waiting for snapshot publish");
        }
        thread::sleep(POLL);
    }
}

fn wake_render_loop(planetarium: &Planetarium) {
    planetarium
        .send(PlanetariumCommand::SetTime(AstroTime::from_jd_utc(
            DEFAULT_ASTRO_TIME_JD_UTC,
        )))
        .expect("wake");
}

fn wait_for_ra_after(planetarium: &Planetarium, expected_ra: f64, after: u64) {
    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        let snap = planetarium.snapshot();
        if snap.frame_id > after && (snap.view_pose.ra_rad - expected_ra).abs() < 1e-8 {
            return;
        }
        if Instant::now() >= deadline {
            panic!(
                "timed out waiting for ra={expected_ra}; last={}",
                snap.view_pose.ra_rad
            );
        }
        thread::sleep(POLL);
    }
}

#[test]
fn mount_lock_follows_set_mount_position() {
    let planetarium = Planetarium::new(0).expect("new");
    planetarium
        .send(PlanetariumCommand::SetPoseLock(PoseLock::LockedToMount))
        .expect("lock");
    planetarium
        .send(PlanetariumCommand::SetMountPosition(Some(MountPosition {
            ra_rad: 1.0,
            dec_rad: 0.4,
        })))
        .expect("mount");
    wake_render_loop(&planetarium);

    wait_for_frame(&planetarium);
    let snap = planetarium.snapshot();
    assert!((snap.view_pose.ra_rad - 1.0).abs() < 1e-8);
    assert!((snap.view_pose.dec_rad - 0.4).abs() < 1e-8);
    let frame = snap.frame_id;

    planetarium
        .send(PlanetariumCommand::SetMountPosition(Some(MountPosition {
            ra_rad: 2.5,
            dec_rad: -0.2,
        })))
        .expect("mount move");
    wake_render_loop(&planetarium);

    wait_for_ra_after(&planetarium, 2.5, frame);
    let moved = planetarium.snapshot();
    assert!((moved.view_pose.dec_rad + 0.2).abs() < 1e-8);
}

#[test]
fn target_lock_follows_set_tracking_target() {
    let target_id = 42_u64;
    let planetarium = Planetarium::new(0).expect("new");
    // Locking is explicit — provide the target THEN switch to LockedToTarget.
    planetarium
        .send(PlanetariumCommand::SetTrackingTarget(Some(
            TrackingTarget {
                id: target_id,
                ra_rad: 3.0,
                dec_rad: 0.1,
            },
        )))
        .expect("target");
    planetarium
        .send(PlanetariumCommand::SetPoseLock(PoseLock::LockedToTarget(
            target_id,
        )))
        .expect("lock");
    wake_render_loop(&planetarium);

    wait_for_frame(&planetarium);
    let snap = planetarium.snapshot();
    assert_eq!(snap.view_pose.ra_rad, 3.0);
    assert!((snap.view_pose.dec_rad - 0.1).abs() < 1e-8);

    planetarium
        .send(PlanetariumCommand::SetTrackingTarget(Some(
            TrackingTarget {
                id: target_id,
                ra_rad: 4.2,
                dec_rad: -0.3,
            },
        )))
        .expect("target move");
    wake_render_loop(&planetarium);

    wait_for_ra_after(&planetarium, 4.2, snap.frame_id);
}

#[test]
fn set_tracking_target_does_not_lock_pose_when_free() {
    // Regression: SetTrackingTarget used to auto-lock to the target, which silently
    // hijacked the user's view. The lock is now strictly governed by SetPoseLock.
    let target_id = 7_u64;
    let planetarium = Planetarium::new(0).expect("new");

    // Capture the free pose BEFORE the target update so we can assert it doesn't move.
    planetarium
        .send(PlanetariumCommand::SetPose(
            nightshade_planetarium::types::ViewPose {
                ra_rad: 1.25,
                dec_rad: 0.0,
                ..nightshade_planetarium::types::ViewPose::default()
            },
        ))
        .expect("seed pose");
    wake_render_loop(&planetarium);
    wait_for_frame(&planetarium);
    let baseline_ra = planetarium.snapshot().view_pose.ra_rad;
    assert!(
        (baseline_ra - 1.25).abs() < 1e-8,
        "baseline RA should be 1.25, got {baseline_ra}"
    );

    planetarium
        .send(PlanetariumCommand::SetTrackingTarget(Some(
            TrackingTarget {
                id: target_id,
                ra_rad: 5.0, // wildly different from baseline
                dec_rad: 0.9,
            },
        )))
        .expect("target");
    wake_render_loop(&planetarium);

    // Give the render loop ample time to (incorrectly) drift toward the target.
    thread::sleep(Duration::from_millis(20));
    let snap = planetarium.snapshot();
    assert!(
        (snap.view_pose.ra_rad - 1.25).abs() < 1e-8,
        "free-pose RA must remain at 1.25 after SetTrackingTarget; got {}",
        snap.view_pose.ra_rad,
    );
    assert!(
        snap.view_pose.dec_rad.abs() < 1e-8,
        "free-pose Dec must remain at 0.0 after SetTrackingTarget; got {}",
        snap.view_pose.dec_rad,
    );
}
