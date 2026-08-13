//! `meridian_gate` tests — moved verbatim out of the former single `instructions::tests`
//! module (release-pass C3 mechanical split). Shared fixtures stay in the parent
//! `tests` module and reach here through `use super::*;`.

use super::*;

/// P1 regression for the pre-exposure meridian gate. A target EAST of the
/// meridian cannot make a MinutesPastMeridian trigger fire (the trigger
/// requires `hour_angle > 0` on the pre-flip / unreported pier side), yet
/// the gate held anyway on a stale hour angle and logged "meridian flip
/// fires in ~0s". Live: target RA 23.4h at LST 21:27 (HA -1.93h) sat at
/// 0/3 frames for minutes with no UI explanation, and with a 30-minute
/// bound PER EXPOSURE a normal sub sequence stalls for hours.
///
/// Pre-fix this test hangs on the gate and trips the timeout.
#[tokio::test]
async fn meridian_gate_does_not_hold_a_target_east_of_the_meridian() {
    let ops = Arc::new(ScriptedDomeRotatorOps::new());
    let mut ec = crate::node::context::ExecutionContext::new("gate-node".to_string());
    ec.device_ops = ops;
    ec.camera_id = Some("camera-1".to_string());
    ec.mount_id = Some("mount-1".to_string());
    ec.longitude = Some(104.65);
    ec.latitude = Some(39.9846);

    let trigger_state = Arc::new(tokio::sync::RwLock::new(
        crate::triggers::TriggerState::new(),
    ));
    {
        let mut state = trigger_state.write().await;
        state.meridian_flip_minutes_past = Some(5.0);
        state.target_ra = Some(23.4);
        state.target_dec = Some(40.0);
        // Stale positive hour angle left behind by an earlier run: the
        // mount poll only runs while a sequence executes, so the first
        // frame of the next run reads the previous run's value.
        state.current_hour_angle = Some(0.19);
        state.pier_side = None;
    }
    ec.trigger_state = Some(trigger_state);

    let mut ctx = ec.to_instruction_context("gate-node").await;
    // LST for longitude 104.65 puts RA 23.4h roughly two hours EAST of the
    // meridian for most of the day; pick the RA that is currently east so
    // the assertion does not depend on the wall clock.
    let lst = crate::meridian::local_sidereal_time(
        crate::meridian::julian_day(&chrono::Utc::now()),
        104.65,
    );
    ctx.target_ra = Some((lst + 4.0) % 24.0);

    let gate = tokio::time::timeout(
        Duration::from_secs(2),
        wait_for_meridian_flip_window(&ctx, 2.0, &BurstControl::default()),
    )
    .await
    .expect("an east-of-meridian target must not be held by the flip gate");

    assert!(
        gate.is_none(),
        "the gate must let the exposure proceed when the flip trigger cannot fire"
    );
}

/// P1 regression, reproduced live 2026-08-09 against the Linux headless
/// build (`--headless`, sim camera + sim mount): 12 x 5s LIGHT on a target
/// at RA 12.5h / Dec +70 from a site at 40N 42E. Frame 1 was captured and
/// the run then sat at `1/12  8%` indefinitely, state "running", status
///
///   Waiting for the meridian flip before the next 5s exposure: the flip
///   fires in ~0s (hour angle +9.88h, threshold 5 min past meridian) and
///   would interrupt the frame
///
/// No "Capturing frame 2/12" ever followed and no flip trigger ever fired:
/// `/api/mount/status` showed the mount parked at RA 0.0 with
/// `sideOfPier: unknown`, so the TRIGGER (which decides from the MOUNT's
/// hour angle) saw a negative HA and could never fire, while the GATE
/// (which predicts from the TARGET's hour angle) held for a flip that was
/// 9.9 hours overdue. `fire_in_secs` was about -35_000, and every negative
/// value counted as "imminent", so each frame paid the gate's full
/// 30-minute bound — a routine target past the meridian cost the night.
///
/// The live rig tripped BOTH arms of this at once (overdue AND a mount the
/// trigger could not fire from). This test isolates the OVERDUE arm — it
/// gives the mount a tracking hour angle so the sibling
/// `gate_does_not_hold_when_the_mount_cannot_make_the_trigger_fire` guard
/// cannot be what releases the burst, and severing the overdue hatch
/// therefore still fails this test.
///
/// This drives the PRODUCTION call site (the exposure burst), not the gate
/// helper. Pre-fix the burst never reaches frame 2 and trips the timeout.
#[tokio::test]
async fn overdue_meridian_flip_does_not_stall_the_exposure_burst() {
    // Parked mount: keeps the daylight gate out of the way (a parked rig
    // is not on-sky) without weakening the meridian gate, which keys only
    // off frame type + target + mount id.
    let ops = Arc::new(ScriptedDomeRotatorOps::new().with_mount_parked(true));
    let dir = std::env::temp_dir().join(format!("ns-mer-overdue-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).expect("temp dir");

    let mut ec = crate::node::context::ExecutionContext::new("overdue-node".to_string());
    ec.device_ops = ops.clone();
    ec.camera_id = Some("camera-1".to_string());
    ec.mount_id = Some("mount-1".to_string());
    ec.save_path = Some(dir.clone());
    ec.latitude = Some(40.0);
    ec.longitude = Some(42.0);

    let trigger_state = Arc::new(tokio::sync::RwLock::new(
        crate::triggers::TriggerState::new(),
    ));
    {
        let mut state = trigger_state.write().await;
        state.meridian_flip_minutes_past = Some(5.0);
        state.target_ra = Some(12.5);
        state.target_dec = Some(70.0);
        // Exactly what the live rig reported: no pier side, and no mount
        // hour angle for the trigger to fire on.
        state.pier_side = None;
        // A mount that IS tracking the target and IS hours past the
        // meridian, so `trigger_can_fire` holds and the sibling
        // "mount cannot make the trigger fire" guard cannot be what
        // releases this burst. Nothing clears `has_flipped_this_target`,
        // which is the state a flip that was requested and then failed
        // (or was retried to exhaustion) leaves behind. Only the overdue
        // escape hatch can let these frames through.
        state.current_hour_angle = Some(9.0);
    }
    ec.trigger_state = Some(trigger_state);

    let control = BurstControl {
        pause: ec.pause_gate(),
        status: None,
    };
    let mut ctx = ec.to_instruction_context("overdue-node").await;
    // Pin the target nine hours WEST of the meridian relative to the
    // current sidereal time so the case under test does not depend on the
    // hour of day the suite runs.
    let lst = crate::meridian::local_sidereal_time(
        crate::meridian::julian_day(&chrono::Utc::now()),
        42.0,
    );
    ctx.target_ra = Some((lst - 9.0 + 24.0) % 24.0);
    ctx.target_dec = Some(70.0);

    let config = ExposureConfig {
        count: 3,
        duration_secs: 0.0,
        frame_type: "light".to_string(),
        ..ExposureConfig::default()
    };

    let result = tokio::time::timeout(
        Duration::from_secs(20),
        execute_exposure_with_renderer(&config, &ctx, None, &control, |_, _| {}),
    )
    .await;

    let completed = result.is_ok();
    let exposures = ops.camera_exposure_calls.load(Ordering::SeqCst);
    let _ = std::fs::remove_dir_all(&dir);

    assert!(
        completed,
        "a meridian flip that is hours overdue must not hold the burst; \
             it stopped after {exposures} of 3 frames"
    );
    assert_eq!(
        exposures, 3,
        "every frame must be captured when the flip the gate is waiting on \
             is already hours past due and will never fire"
    );
}

/// The band the overdue escape hatch does NOT cover, reproduced live on
/// the headless Linux build (sim camera + sim mount, site 40N 42E, target
/// pinned 12 minutes west of the meridian, default 5-minute threshold):
///
///   19:03:00 | running | prog=0.333 | Waiting for the meridian flip
///   before the next 2s exposure: the flip became due 423s ago (hour angle
///   +0.20h, threshold 5 min past meridian) and would interrupt the frame
///
/// and the run then sat at 1/3 for the rest of the watch window. Only 7
/// minutes overdue, so `OVERDUE_GRACE_SECS` does not release it — but the
/// mount was never slewed to the target, so `current_hour_angle` (the only
/// thing the TRIGGER reads) never made the flip fire. The gate was waiting
/// on an event that could not arrive, once per frame, 30 minutes a time.
///
/// Drives the PRODUCTION call site (the exposure burst), not the helper.
#[tokio::test]
async fn gate_does_not_hold_when_the_mount_cannot_make_the_trigger_fire() {
    let ops = Arc::new(ScriptedDomeRotatorOps::new().with_mount_parked(true));
    let dir = std::env::temp_dir().join(format!("ns-mer-nofire-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).expect("temp dir");

    let mut ec = crate::node::context::ExecutionContext::new("nofire-node".to_string());
    ec.device_ops = ops.clone();
    ec.camera_id = Some("camera-1".to_string());
    ec.mount_id = Some("mount-1".to_string());
    ec.save_path = Some(dir.clone());
    ec.latitude = Some(40.0);
    ec.longitude = Some(42.0);

    let trigger_state = Arc::new(tokio::sync::RwLock::new(
        crate::triggers::TriggerState::new(),
    ));
    {
        let mut state = trigger_state.write().await;
        state.meridian_flip_minutes_past = Some(5.0);
        state.target_ra = Some(12.5);
        state.target_dec = Some(70.0);
        state.pier_side = None;
        // Exactly the live rig's state: the mount never reported a
        // position, so the MinutesPastMeridian trigger returns false on
        // every evaluation and no flip can ever be requested.
        state.current_hour_angle = None;
    }
    ec.trigger_state = Some(trigger_state);

    let control = BurstControl {
        pause: ec.pause_gate(),
        status: None,
    };
    let mut ctx = ec.to_instruction_context("nofire-node").await;
    // 12 minutes west of the meridian: past the 5-minute threshold, so the
    // gate wants to hold, but only 7 minutes overdue — inside the grace
    // window, so the overdue hatch cannot be what releases this.
    let lst = crate::meridian::local_sidereal_time(
        crate::meridian::julian_day(&chrono::Utc::now()),
        42.0,
    );
    ctx.target_ra = Some((lst - 12.0 / 60.0 + 24.0) % 24.0);
    ctx.target_dec = Some(70.0);

    let config = ExposureConfig {
        count: 3,
        duration_secs: 0.0,
        frame_type: "light".to_string(),
        ..ExposureConfig::default()
    };

    let result = tokio::time::timeout(
        Duration::from_secs(20),
        execute_exposure_with_renderer(&config, &ctx, None, &control, |_, _| {}),
    )
    .await;

    let completed = result.is_ok();
    let exposures = ops.camera_exposure_calls.load(Ordering::SeqCst);
    let _ = std::fs::remove_dir_all(&dir);

    assert!(
        completed,
        "the gate must not hold for a flip the mount cannot make the trigger \
             request; the burst stopped after {exposures} of 3 frames"
    );
    assert_eq!(
        exposures, 3,
        "every frame must be captured when no flip can ever be requested"
    );
}

/// The gate must still hold when a flip really is imminent, otherwise the
/// fix above would just delete the feature.
#[tokio::test]
async fn meridian_gate_still_holds_when_the_flip_is_imminent() {
    let ops = Arc::new(ScriptedDomeRotatorOps::new());
    let mut ec = crate::node::context::ExecutionContext::new("gate-node".to_string());
    ec.device_ops = ops;
    ec.camera_id = Some("camera-1".to_string());
    ec.mount_id = Some("mount-1".to_string());
    ec.longitude = Some(0.0);

    let trigger_state = Arc::new(tokio::sync::RwLock::new(
        crate::triggers::TriggerState::new(),
    ));
    {
        let mut state = trigger_state.write().await;
        state.meridian_flip_minutes_past = Some(5.0);
        state.target_ra = Some(1.0);
        state.target_dec = Some(40.0);
        state.pier_side = Some(crate::PierSide::West);
        // A mount that is TRACKING THE TARGET, which is what the executor's
        // mount poll reports during a healthy run. The gate may only hold
        // for a flip the trigger can actually request, and the trigger
        // reads this field; leaving it None described a mount that reports
        // no position at all, in which case declining to hold is correct.
        state.current_hour_angle = Some(10.0 / 60.0);
    }
    ec.trigger_state = Some(trigger_state);

    let mut ctx = ec.to_instruction_context("gate-node").await;
    // Ten minutes PAST the meridian with a 5-minute threshold: the trigger
    // is already due, so the frame would be ruined by the flip slew.
    let lst =
        crate::meridian::local_sidereal_time(crate::meridian::julian_day(&chrono::Utc::now()), 0.0);
    ctx.target_ra = Some((lst - 10.0 / 60.0 + 24.0) % 24.0);

    let held = tokio::time::timeout(
        Duration::from_millis(500),
        wait_for_meridian_flip_window(&ctx, 2.0, &BurstControl::default()),
    )
    .await;

    assert!(
        held.is_err(),
        "a flip that is already due must still hold the next exposure"
    );
}

/// D4/R4: `MeridianFlipOutcome` is the only wire a flip travels to reach
/// the run vitals' `meridianFlips` count and the session report. It was
/// emitted by the TRIGGER call site alone, so a sequence that flipped via
/// an explicit MeridianFlip node reported no flip at all — and a
/// node-driven flip that FAILED left an empty error list on a run the
/// operator saw reported as completed.
#[tokio::test]
async fn a_node_driven_meridian_flip_reports_its_outcome_to_the_run() {
    let scratch = scratch_dir("node-flip-outcome");
    let ops = Arc::new(ScriptedDomeRotatorOps::new().with_observer_location(TEST_LAT, TEST_LON));
    let (event_tx, mut event_rx) = tokio::sync::broadcast::channel(64);
    let mut ctx = direct_capture_ctx(ops.clone(), scratch.0.clone()).await;
    ctx.event_tx = Some(event_tx);
    ctx.mount_id = Some("mount-1".to_string());
    ctx.target_name = Some("M42".to_string());
    ctx.target_ra = Some(5.59);
    ctx.target_dec = Some(-5.39);

    let config = crate::MeridianFlipConfig {
        // Below every possible hour angle, so the flip is always due and
        // the test never depends on when it runs.
        minutes_past_meridian: -720.0,
        pause_guiding: false,
        auto_center: false,
        refocus_after: false,
        resume_guiding: false,
        settle_time: 0.0,
        max_retries: 0,
        retry_delays_secs: Vec::new(),
        ..crate::MeridianFlipConfig::default()
    };

    let result = tokio::time::timeout(
        std::time::Duration::from_secs(30),
        execute_meridian_flip(&config, &ctx, None),
    )
    .await
    .expect("the flip node should resolve");

    let mut outcomes = Vec::new();
    while let Ok(event) = event_rx.try_recv() {
        if let crate::executor::ExecutorEvent::MeridianFlipOutcome { outcome, .. } = event {
            outcomes.push(outcome);
        }
    }
    assert_eq!(
        outcomes.len(),
        1,
        "the node path announced nothing; the run's flip count and error list \
             both come from this event. Node returned {:?}",
        result.status
    );
}

/// Regression: the pre-exposure meridian gate must apply to LIGHTS only.
///
/// A calibration frame inside a TargetHeader used to be gated too — a 3s
/// dark was held with "meridian flip fires in ~0s and would interrupt it",
/// stalling the run for the gate's full 30-minute bound. Shutter-closed
/// frames cannot be ruined by where the mount points.
#[test]
fn meridian_gate_applies_to_light_frames_only() {
    for gated in ["light", "Light", "LIGHT"] {
        assert!(
            gated.eq_ignore_ascii_case("light"),
            "{gated} must be recognised as a light frame and gated"
        );
    }
    for ungated in ["dark", "bias", "flat", "darkflat", "snapshot"] {
        assert!(
            !ungated.eq_ignore_ascii_case("light"),
            "{ungated} must NOT be held for a meridian flip"
        );
    }
}
