//! Snapshot publishing pipeline: labels projected from the dev star table.

use std::thread;
use std::time::{Duration, Instant};

use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::scene::{build_snapshot, project_icrs, SnapshotInputs};
use nightshade_planetarium::types::{AstroTime, Observer, RenderConfig, ViewPose};
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

fn wait_for_frame_after(planetarium: &Planetarium, after: u64) -> u64 {
    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        let frame_id = planetarium.snapshot().frame_id;
        if frame_id > after {
            return frame_id;
        }
        if Instant::now() >= deadline {
            panic!("timed out waiting for snapshot frame after {after}");
        }
        thread::sleep(POLL);
    }
}

#[test]
fn build_snapshot_includes_visible_dev_stars_at_pole_view() {
    let snap = build_snapshot(SnapshotInputs {
        frame_id: 1,
        view_pose: ViewPose::default(),
        astro_time: AstroTime::from_jd_utc(2_451_545.0),
        observer: Observer::default(),
        render_config: RenderConfig::default(),
        selected: None,
    });

    assert_eq!(snap.frame_id, 1);
    assert!(
        snap.labels.len() >= 2,
        "expected multiple bright stars at pole view, got {}",
        snap.labels.len()
    );
    assert!(
        snap.labels.iter().any(|l| l.text.as_str() == "Polaris"),
        "Polaris should be visible near the celestial pole"
    );
}

#[test]
fn pose_change_moves_label_screen_positions() {
    let planetarium = Planetarium::new(0).expect("new");
    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose::default()))
        .expect("SetPose");

    wait_for_frame(&planetarium);
    let snap_a = planetarium.snapshot();
    let vega_a = snap_a
        .labels
        .iter()
        .find(|l| l.text.as_str() == "Vega")
        .expect("Vega label");
    let frame_a = snap_a.frame_id;

    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose {
            ra_rad: 1.0,
            dec_rad: std::f64::consts::FRAC_PI_2,
            ..ViewPose::default()
        }))
        .expect("SetPose");

    wait_for_frame_after(&planetarium, frame_a);
    let snap_b = planetarium.snapshot();
    let vega_b = snap_b
        .labels
        .iter()
        .find(|l| l.text.as_str() == "Vega")
        .expect("Vega label");

    assert!(snap_b.frame_id > frame_a);
    let dx = (vega_a.screen_x - vega_b.screen_x).abs();
    let dy = (vega_a.screen_y - vega_b.screen_y).abs();
    assert!(
        dx > 0.01 || dy > 0.01,
        "label position should change with pose (dx={dx}, dy={dy})"
    );
}

#[test]
fn show_stars_disabled_yields_empty_labels_but_increments_frame() {
    let planetarium = Planetarium::new(0).expect("new");
    planetarium
        .send(PlanetariumCommand::SetConfig(RenderConfig {
            show_stars: false,
            ..RenderConfig::default()
        }))
        .expect("SetConfig");
    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose::default()))
        .expect("SetPose");

    wait_for_frame(&planetarium);
    let snap = planetarium.snapshot();
    assert!(snap.frame_id > 0);
    assert!(snap.labels.is_empty());
}

#[test]
fn polaris_near_screen_center_when_view_centered_on_pole() {
    let (x, y) = project_icrs(0.662_062, 1.557_896, ViewPose::default()).expect("project");
    assert!(
        (x - 0.5).abs() < 0.05 && (y - 0.5).abs() < 0.05,
        "Polaris should sit near view center at pole pose, got ({x}, {y})"
    );
}
