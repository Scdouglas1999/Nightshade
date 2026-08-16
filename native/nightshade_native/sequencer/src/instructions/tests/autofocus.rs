//! `autofocus` tests — moved verbatim out of the former single `instructions::tests`
//! module (release-pass C3 mechanical split). Shared fixtures stay in the parent
//! `tests` module and reach here through `use super::*;`.

use super::*;

#[test]
fn autofocus_admission_is_atomic_and_released_by_guard() {
    let _serial = AF_GATE_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let first = try_admit_autofocus_run().expect("first run must admit");
    assert!(
        try_admit_autofocus_run().is_none(),
        "a concurrent autofocus run must be rejected"
    );
    drop(first);
    let next = try_admit_autofocus_run().expect("guard drop must release admission");
    drop(next);
}

// Single-threaded (current-thread) tokio runtime, so holding the sync gate
// lock across awaits cannot deadlock; the lock only serializes vs other
// gate tests running on separate threads.
#[tokio::test(start_paused = true)]
#[allow(clippy::await_holding_lock)]
async fn node_admission_waits_for_inflight_run_then_times_out_on_stuck_gate() {
    let _serial = AF_GATE_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());

    // Scenario 1: a trigger-fired run holds the gate; the node waiter must
    // block while it is held rather than fail the run.
    let inflight = try_admit_autofocus_run().expect("first run must admit");
    let waiter =
        tokio::spawn(async { admit_autofocus_run_waiting(Duration::from_secs(600)).await });
    tokio::time::sleep(Duration::from_secs(5)).await;
    assert!(
        !waiter.is_finished(),
        "the node waiter must keep waiting while an autofocus is in flight, \
             not fail immediately"
    );
    // Once the in-flight run releases, the waiter admits.
    drop(inflight);
    let guard = waiter
        .await
        .expect("waiter task panicked")
        .expect("waiter must admit once the gate frees");
    drop(guard);

    // Scenario 2: a gate that never releases must time out (not hang).
    let _stuck = try_admit_autofocus_run().expect("hold the gate");
    let result = admit_autofocus_run_waiting(Duration::from_secs(600)).await;
    assert!(
        result.is_none(),
        "a gate that never releases must time out, not hang forever"
    );
}

#[test]
fn autofocus_config_validation_rejects_decorative_or_dangerous_values() {
    let valid = AutofocusConfig::default();
    assert!(validate_autofocus_config(&valid).is_ok());

    let mut invalid = valid.clone();
    invalid.exposures_per_point = 0;
    assert!(validate_autofocus_config(&invalid).is_err());

    let mut invalid = valid.clone();
    invalid.inner_crop_ratio = invalid.outer_crop_ratio;
    assert!(validate_autofocus_config(&invalid).is_err());

    let mut invalid = valid.clone();
    invalid.number_of_attempts = 11;
    assert!(validate_autofocus_config(&invalid).is_err());

    let mut invalid = valid.clone();
    invalid.gain = Some(-1);
    assert!(validate_autofocus_config(&invalid).is_err());

    let mut invalid = valid;
    invalid.max_duration_secs = 0.0;
    assert!(validate_autofocus_config(&invalid).is_err());
}

#[tokio::test]
async fn autofocus_cleanup_restores_and_verifies_original_position() {
    let ops = Arc::new(ScriptedDomeRotatorOps::new());
    let ctx = ctx_with_ops(ops.clone()).await;

    restore_autofocus_origin("focuser-1", &ctx, 12_345)
        .await
        .expect("cleanup should restore the original position");

    assert_eq!(ops.focuser_halt_calls.load(Ordering::SeqCst), 1);
    assert_eq!(*ops.focuser_moves.lock().unwrap(), vec![12_345]);
}

#[tokio::test]
#[allow(clippy::await_holding_lock)]
async fn autofocus_restores_designated_filter_and_guiding_on_cancel() {
    let _serial = AF_GATE_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let ops = Arc::new(ScriptedDomeRotatorOps::new().with_guiding(true));
    let ctx = ctx_with_ops(ops.clone()).await;
    ctx.cancellation_token.store(true, Ordering::SeqCst);
    let mut config = AutofocusConfig {
        filter: Some("L".to_string()),
        disable_guiding_during_af: true,
        ..AutofocusConfig::default()
    };
    config.filter_settings.insert(
        "R".to_string(),
        crate::AutofocusFilterConfig {
            af_filter_name: Some("L".to_string()),
            gain: Some(120),
            offset: Some(15),
            ..crate::AutofocusFilterConfig::default()
        },
    );

    let guard = try_admit_autofocus_run().expect("test autofocus must admit");
    let result = execute_autofocus_admitted(&config, &ctx, None, guard).await;

    assert_eq!(result.status, NodeStatus::Cancelled);
    assert_eq!(*ops.filter_moves.lock().unwrap(), vec![0, 1]);
    assert_eq!(ops.guider_stop_calls.load(Ordering::SeqCst), 1);
    assert_eq!(ops.guider_start_calls.load(Ordering::SeqCst), 1);
    assert!(ops.guiding.load(Ordering::SeqCst));
}

#[tokio::test(start_paused = true)]
async fn autofocus_timeout_bounds_hung_camera_exposure() {
    let ops = Arc::new(ScriptedDomeRotatorOps::new().with_hanging_camera());
    let ctx = ctx_with_ops(ops.clone()).await;
    let config = AutofocusConfig {
        steps_out: 1,
        max_duration_secs: 1.0,
        focuser_settle_time_ms: 0,
        ..AutofocusConfig::default()
    };

    let result = execute_autofocus_once(
        &config,
        &ctx,
        None,
        &crate::node::context::PauseGate::default(),
    )
    .await;

    assert_eq!(result.status, NodeStatus::Failure);
    assert!(
        result
            .message
            .as_deref()
            .is_some_and(|message| message.contains("timed out")),
        "hung sub-operation must fail at the autofocus deadline: {:?}",
        result.message
    );
    tokio::task::yield_now().await;
    assert_eq!(
        ops.camera_abort_calls.load(Ordering::SeqCst),
        1,
        "timing out a camera exposure must also abort it"
    );
}
