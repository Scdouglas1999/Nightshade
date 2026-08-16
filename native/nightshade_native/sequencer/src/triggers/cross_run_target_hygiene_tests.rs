use super::*;
use crate::{PierSide, RecoveryAction, TriggerType};

#[test]
fn reset_for_new_run_drops_the_previous_runs_target() {
    let mut state = TriggerState::new();
    state.set_target(270.0, 60.0);
    state.set_meridian_target("B".to_string());
    state.current_altitude = Some(10.5);
    state.current_hour_angle = Some(11.18);
    state.next_meridian_flip_time = Some(1);
    state.tracking_limit_detected_at = Some(1);
    state.update_plate_solve(270.1, 60.1, 1.2);

    state.reset_for_new_run();

    assert_eq!(state.target_ra, None);
    assert_eq!(state.target_dec, None);
    assert_eq!(state.current_target_name, None);
    assert_eq!(state.current_altitude, None);
    assert_eq!(state.current_hour_angle, None);
    assert_eq!(state.next_meridian_flip_time, None);
    assert_eq!(state.tracking_limit_detected_at, None);
    assert_eq!(state.last_plate_solve_ra, None);
    assert_eq!(state.last_plate_solve_dec, None);
    assert_eq!(state.last_plate_solve_pixel_scale, None);
}

#[test]
fn a_resumed_run_keeps_the_target_restored_from_its_checkpoint() {
    let mut state = TriggerState::new();
    state.set_target(270.0, 60.0);
    state.set_meridian_target("B".to_string());
    state.restored_from_checkpoint = true;

    state.reset_for_new_run();

    assert_eq!(state.target_ra, Some(270.0));
    assert_eq!(state.target_dec, Some(60.0));
    assert_eq!(state.current_target_name, Some("B".to_string()));
    assert!(
        !state.restored_from_checkpoint,
        "the resume flag is one-shot: the run after the resume must clear the target"
    );

    state.reset_for_new_run();
    assert_eq!(state.target_ra, None);
}

#[tokio::test]
async fn altitude_limit_does_not_fire_for_a_run_with_no_target() {
    // Per-run target state is cleared between runs: a dark/flat sequence with
    // no TargetHeader that inherits the previous run's altitude skips its
    // whole tree milliseconds after start, reporting `completed` with zero
    // frames.
    let mut state = TriggerState::new();
    state.set_target(270.0, 60.0);
    state.current_altitude = Some(10.5);

    let mut previous_run = Trigger::new(
        "altitude_limit",
        "Altitude Limit",
        TriggerType::AltitudeLimit { min_altitude: 30.0 },
        RecoveryAction::NextTarget,
    );
    assert!(
        previous_run.check(&state).await,
        "a genuinely low target must still fire the altitude limit"
    );

    state.reset_for_new_run();

    let mut next_run = Trigger::new(
        "altitude_limit",
        "Altitude Limit",
        TriggerType::AltitudeLimit { min_altitude: 30.0 },
        RecoveryAction::NextTarget,
    );
    assert!(
        !next_run.check(&state).await,
        "a run with no target has no altitude and must not fire the altitude limit"
    );
}

#[tokio::test]
async fn meridian_flip_does_not_fire_for_a_run_with_no_target() {
    // Hour angle comes from the mount, so it keeps arriving even on a
    // target-less run. Without a target the flip drove a real daylight
    // slew to the previous run's coordinates.
    let config = crate::MeridianFlipConfig {
        trigger_method: crate::MeridianTriggerMethod::MinutesPastMeridian,
        minutes_past_meridian: 5.0,
        ..Default::default()
    };
    let mut state = TriggerState::new();
    state.set_target(270.0, 60.0);
    state.update_hour_angle(11.18);
    state.pier_side = Some(PierSide::West);

    let mut previous_run = Trigger::new(
        "meridian_flip",
        "Meridian Flip",
        TriggerType::MeridianFlip {
            config: config.clone(),
        },
        RecoveryAction::MeridianFlip(config.clone()),
    );
    assert!(
        previous_run.check(&state).await,
        "a tracked target past the meridian must still fire the flip"
    );

    state.reset_for_new_run();
    // The mount keeps reporting; the monitor loop refreshes hour angle and
    // pier side every tick regardless of whether a target is set.
    state.update_hour_angle(11.18);
    state.pier_side = Some(PierSide::West);

    let mut next_run = Trigger::new(
        "meridian_flip",
        "Meridian Flip",
        TriggerType::MeridianFlip {
            config: config.clone(),
        },
        RecoveryAction::MeridianFlip(config),
    );
    assert!(
        !next_run.check(&state).await,
        "a run with no target must not flip"
    );
}
