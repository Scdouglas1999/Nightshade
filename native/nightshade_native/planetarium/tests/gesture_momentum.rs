//! Synthetic pan sequences and expected momentum pose trajectories.

use nightshade_planetarium::gesture::{
    decelerate, remaining_weight, GestureEvent, GestureStateMachine, MOMENTUM_DURATION_SECS,
    STEP_FACTOR,
};
use nightshade_planetarium::types::{SkyProjection, ViewPose};

const FRAME_DT: f32 = 1.0 / 60.0;

fn default_pose() -> ViewPose {
    ViewPose {
        ra_rad: 2.0,
        dec_rad: 0.3,
        fov_rad: 1.0,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    }
}

/// Replay v1-style momentum ticks: `delta = v * (1 - decelerate(t)) * 0.02` with time-based progress.
fn simulate_v1_momentum_ticks(vx: f32, vy: f32, pose: &mut ViewPose, max_frames: u32) -> u32 {
    let mut progress = 0.0f32;
    let mut frames = 0u32;
    for _ in 0..max_frames {
        if progress >= 1.0 {
            break;
        }
        progress = (progress + FRAME_DT / MOMENTUM_DURATION_SECS).min(1.0);
        let remaining = remaining_weight(progress);
        let dx = vx * remaining * STEP_FACTOR;
        let dy = vy * remaining * STEP_FACTOR;
        apply_pan_like_gesture(pose, dx, dy);
        frames += 1;
        if progress >= 1.0 - f32::EPSILON {
            break;
        }
    }
    frames
}

fn apply_pan_like_gesture(pose: &mut ViewPose, dx: f32, dy: f32) {
    let pan_scale = f64::from(pose.fov_rad.to_degrees()) / 500.0;
    let d_ra_hours = -(f64::from(dx)) * pan_scale / 15.0;
    let d_dec_deg = f64::from(dy) * pan_scale;
    pose.ra_rad += d_ra_hours * (std::f64::consts::PI / 12.0);
    let dec = pose.dec_rad + d_dec_deg.to_radians();
    pose.dec_rad = dec.clamp(
        -std::f64::consts::FRAC_PI_2,
        std::f64::consts::FRAC_PI_2,
    );
}

#[test]
fn synthetic_pan_sequence_starts_momentum_on_release() {
    let mut sm = GestureStateMachine::new(default_pose());
    assert!(!sm.apply(GestureEvent::PanStart { x: 0.5, y: 0.5 }));
    assert!(sm.apply(GestureEvent::PanUpdate {
        dx: 0.02,
        dy: 0.0,
        vx: 0.8,
        vy: 0.0,
    }));
    assert!(!sm.apply(GestureEvent::PanEnd { vx: 0.8, vy: 0.0 }));
    assert!(sm.momentum_active());
    assert_eq!(sm.active_gesture(), None);
}

#[test]
fn momentum_trajectory_matches_v1_decay_model() {
    let vx = 0.8f32;
    let vy = 0.0f32;

    let mut expected = default_pose();
    let frames = simulate_v1_momentum_ticks(vx, vy, &mut expected, 120);

    let mut sm = GestureStateMachine::new(default_pose());
    assert!(!sm.apply(GestureEvent::PanEnd { vx, vy }));
    for _ in 0..frames {
        let _ = sm.tick_momentum(FRAME_DT);
    }

    let got = sm.pose();
    assert!(
        (got.ra_rad - expected.ra_rad).abs() < 1e-10,
        "ra mismatch: got {} expected {}",
        got.ra_rad,
        expected.ra_rad
    );
    assert!(
        (got.dec_rad - expected.dec_rad).abs() < 1e-10,
        "dec mismatch: got {} expected {}",
        got.dec_rad,
        expected.dec_rad
    );
}

#[test]
fn momentum_deltas_shrink_as_progress_advances() {
    let mut sm = GestureStateMachine::new(default_pose());
    assert!(!sm.apply(GestureEvent::PanEnd { vx: 1.0, vy: 0.0 }));

    let ra0 = sm.pose().ra_rad;
    let _ = sm.tick_momentum(FRAME_DT);
    let ra_early = sm.pose().ra_rad;
    let early_delta = (ra_early - ra0).abs();

    for _ in 0..24 {
        if !sm.momentum_active() {
            break;
        }
        let _ = sm.tick_momentum(FRAME_DT);
    }
    let ra_mid = sm.pose().ra_rad;
    let _ = sm.tick_momentum(FRAME_DT);
    let ra_late = sm.pose().ra_rad;
    let late_delta = (ra_late - ra_mid).abs();

    assert!(early_delta > late_delta, "early={early_delta} late={late_delta}");
}

#[test]
fn decelerate_curve_matches_flutter_decelerate_samples() {
    // Flutter Cubic(0,0,0.2,1): y = 3*(1-t)*t^2 + t^3
    let samples = [(0.0, 0.0), (0.25, 0.15625), (0.5, 0.5), (0.75, 0.84375), (1.0, 1.0)];
    for (t, y) in samples {
        let got = decelerate(t);
        assert!(
            (got - y).abs() < 1e-5,
            "decelerate({t}) = {got}, expected {y}"
        );
    }
}
