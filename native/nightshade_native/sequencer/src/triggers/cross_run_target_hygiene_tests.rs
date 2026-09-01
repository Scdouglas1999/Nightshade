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

/// The mount has to be FOLLOWING the target, not merely named alongside it.
///
/// `current_hour_angle` is the target's, which fixed the flip that armed off a
/// parked mount's home RA. Underneath it sat this: a parked mount whose named
/// target genuinely is past the meridian still armed the flip. That is a
/// calibration block — a TargetHeader with darks under it, mount parked — and
/// the exhausted flip then coerces a run that captured every frame it was asked
/// for into FAILED.
///
/// The Dart countdown banner already refuses to arm on `mount.isParked` or
/// `!mount.isTracking` (`meridian_countdown_provider`), which is how the
/// Imaging screen could say "Meridian flip imminent — handled automatically"
/// while the Sequencer said "attempt 2/4 failed": only one surface asked.
fn parked_calibration_run_state() -> TriggerState {
    let mut state = TriggerState::new();
    // A TargetHeader stamps the target even for a calibration block under it.
    state.set_target(270.0, 60.0);
    // The target really is past the meridian — well beyond the 5-minute gate.
    state.update_hour_angle(1.5);
    state.pier_side = Some(PierSide::West);
    state
}

fn meridian_trigger(config: crate::MeridianFlipConfig) -> Trigger {
    Trigger::new(
        "meridian_flip",
        "Meridian Flip",
        TriggerType::MeridianFlip {
            config: config.clone(),
        },
        RecoveryAction::MeridianFlip(config),
    )
}

#[tokio::test]
async fn meridian_flip_does_not_arm_on_a_parked_mount() {
    let config = crate::MeridianFlipConfig {
        trigger_method: crate::MeridianTriggerMethod::MinutesPastMeridian,
        minutes_past_meridian: 5.0,
        ..Default::default()
    };

    // Control: identical state, mount tracking the target.
    let mut tracking = parked_calibration_run_state();
    tracking.mount_parked = Some(false);
    tracking.mount_is_tracking = Some(true);
    assert!(
        meridian_trigger(config.clone()).check(&tracking).await,
        "a tracked target past the meridian must still fire the flip"
    );

    let mut parked = parked_calibration_run_state();
    parked.mount_parked = Some(true);
    assert!(
        !meridian_trigger(config).check(&parked).await,
        "a parked mount is not following the target; the flip must not arm"
    );
}

#[tokio::test]
async fn meridian_flip_does_not_arm_when_the_mount_is_not_tracking() {
    let config = crate::MeridianFlipConfig {
        trigger_method: crate::MeridianTriggerMethod::MinutesPastMeridian,
        minutes_past_meridian: 5.0,
        ..Default::default()
    };

    let mut idle = parked_calibration_run_state();
    idle.mount_parked = Some(false);
    idle.mount_is_tracking = Some(false);
    assert!(
        !meridian_trigger(config).check(&idle).await,
        "a mount that is not tracking is not following the target; no flip"
    );
}

#[tokio::test]
async fn meridian_flip_hour_angle_threshold_honours_the_same_mount_guards() {
    // The guard has to cover every hour-angle-derived method, or switching the
    // trigger method reopens the hole.
    let config = crate::MeridianFlipConfig {
        trigger_method: crate::MeridianTriggerMethod::HourAngleThreshold,
        hour_angle_threshold: 0.5,
        ..Default::default()
    };

    let mut tracking = parked_calibration_run_state();
    tracking.mount_parked = Some(false);
    tracking.mount_is_tracking = Some(true);
    assert!(
        meridian_trigger(config.clone()).check(&tracking).await,
        "HourAngleThreshold must still fire for a tracked target"
    );

    let mut parked = parked_calibration_run_state();
    parked.mount_parked = Some(true);
    assert!(
        !meridian_trigger(config).check(&parked).await,
        "HourAngleThreshold must not arm on a parked mount either"
    );
}

#[tokio::test]
async fn a_mount_that_never_reports_park_or_tracking_is_unaffected() {
    // Both fields are Option. `None` means the mount never told us, and such a
    // mount must behave exactly as before rather than losing flips entirely.
    let config = crate::MeridianFlipConfig {
        trigger_method: crate::MeridianTriggerMethod::MinutesPastMeridian,
        minutes_past_meridian: 5.0,
        ..Default::default()
    };

    let silent = parked_calibration_run_state();
    assert_eq!(silent.mount_parked, None);
    assert_eq!(silent.mount_is_tracking, None);
    assert!(
        meridian_trigger(config).check(&silent).await,
        "a mount with no park/tracking readings must still be able to flip"
    );
}

#[tokio::test]
async fn on_tracking_limit_hit_is_exempt_from_the_not_tracking_guard() {
    // Tracking having stopped is that method's entire premise; the new guard
    // must not disable it.
    let config = crate::MeridianFlipConfig {
        trigger_method: crate::MeridianTriggerMethod::OnTrackingLimitHit,
        tracking_limit_wait_minutes: 0.0,
        ..Default::default()
    };

    let mut state = parked_calibration_run_state();
    state.mount_tracking_expected = true;
    state.mount_tracking_lost = true;
    state.mount_is_tracking = Some(false);
    state.mount_status_query_failed = false;
    state.mount_slewing = Some(false);
    state.mount_parked = Some(false);
    state.tracking_limit_detected_at = Some(chrono::Utc::now().timestamp() - 600);

    assert!(
        meridian_trigger(config).check(&state).await,
        "OnTrackingLimitHit fires precisely when tracking has stopped"
    );
}
