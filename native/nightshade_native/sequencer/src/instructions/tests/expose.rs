//! `expose` tests — moved verbatim out of the former single `instructions::tests`
//! module (release-pass C3 mechanical split). Shared fixtures stay in the parent
//! `tests` module and reach here through `use super::*;`.

use super::*;

/// Pause must stop a burst mid-flight. The node tree only checks `is_paused`
/// between instructions and a burst is N frames inside ONE instruction, so
/// without an in-burst check a Pause pressed during frame 2 of a 3x8s Take
/// Exposures shows a PAUSED badge and "Paused 33%" while the log goes
/// `Pausing sequence execution` -> `Capturing frame 3/3 (8.0s)` and the run
/// records `status=completed, framesCaptured=3` with Resume never pressed.
#[tokio::test]
async fn pause_stops_the_burst_before_the_next_frame_starts() {
    let paused = Arc::new(AtomicBool::new(false));
    let ops = Arc::new(ScriptedDomeRotatorOps::new().pausing_after_first_exposure(paused.clone()));
    let dir = std::env::temp_dir().join(format!("ns-pause-burst-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).expect("temp dir");

    let mut ec = crate::node::context::ExecutionContext::new_for_test("pause-node".to_string());
    ec.device_ops = ops.clone();
    ec.camera_id = Some("camera-1".to_string());
    ec.save_path = Some(dir.clone());
    ec.is_paused = paused.clone();
    let ctx = ec.to_instruction_context("pause-node").await;
    let control = BurstControl {
        pause: ec.pause_gate(),
        status: None,
    };
    // Calibration frames so the burst is not daylight-gated or graded.
    let config = ExposureConfig {
        count: 3,
        duration_secs: 0.0,
        frame_type: "dark".to_string(),
        ..ExposureConfig::default()
    };

    let burst = std::pin::pin!(execute_exposure_with_renderer(
        &config,
        &ctx,
        None,
        &control,
        |_, _, _| {}
    ));
    let mut burst = burst;

    let held = tokio::time::timeout(Duration::from_millis(400), &mut burst).await;
    assert!(
        held.is_err(),
        "the burst must still be holding while the operator has it paused"
    );
    assert_eq!(
        ops.camera_exposure_calls.load(Ordering::SeqCst),
        1,
        "no NEW exposure may start while paused — the operator pauses to \
             stand in front of the telescope"
    );

    paused.store(false, Ordering::SeqCst);
    let result = tokio::time::timeout(Duration::from_secs(10), burst)
        .await
        .expect("resume must let the burst finish");

    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(result.status, NodeStatus::Success);
    assert_eq!(
        ops.camera_exposure_calls.load(Ordering::SeqCst),
        3,
        "Resume must complete the remaining frames"
    );
}

#[tokio::test]
async fn dropped_exposure_instruction_aborts_camera() {
    let ops = Arc::new(ScriptedDomeRotatorOps::new().with_hanging_camera());
    let ctx = ctx_with_ops(ops.clone()).await;
    let config = ExposureConfig {
        duration_secs: 60.0,
        count: 1,
        ..ExposureConfig::default()
    };

    let task = tokio::spawn(async move { execute_exposure(&config, &ctx, |_, _, _| {}).await });
    while ops.camera_exposure_calls.load(Ordering::SeqCst) == 0 {
        tokio::task::yield_now().await;
    }
    task.abort();
    let _ = task.await;
    for _ in 0..20 {
        if ops.camera_abort_calls.load(Ordering::SeqCst) > 0 {
            break;
        }
        tokio::task::yield_now().await;
    }

    assert_eq!(
        ops.camera_abort_calls.load(Ordering::SeqCst),
        1,
        "dropping the instruction future must abort the physical exposure"
    );
}

#[tokio::test]
async fn requested_filter_without_wheel_fails_before_capture() {
    let ops = Arc::new(ScriptedDomeRotatorOps::new());
    let mut ctx = ctx_with_ops(ops.clone()).await;
    ctx.filterwheel_id = None;
    let config = ExposureConfig {
        duration_secs: 0.01,
        count: 1,
        filter: Some("Ha".to_string()),
        ..ExposureConfig::default()
    };

    let result = execute_exposure(&config, &ctx, |_, _, _| {}).await;

    assert_eq!(result.status, NodeStatus::Failure);
    assert!(
        result
            .message
            .as_deref()
            .is_some_and(|message| message.contains("no filter wheel")),
        "missing hardware must be surfaced instead of capturing mislabeled data"
    );
    assert_eq!(
        ops.camera_exposure_calls.load(Ordering::SeqCst),
        0,
        "capture must not start when its requested filter cannot be applied"
    );
}
