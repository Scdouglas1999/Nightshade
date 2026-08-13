//! `cooling` tests — moved verbatim out of the former single `instructions::tests`
//! module (release-pass C3 mechanical split). Shared fixtures stay in the parent
//! `tests` module and reach here through `use super::*;`.

use super::*;

/// A WarmCamera whose final "switch the cooler off" fails must not report
/// success. On the reference rig (2026-08-09, L19) that call failed for
/// every request — the instruction ran its whole ramp, discarded the
/// error, and reported "Camera warmed to ambient" with the TEC still
/// powered.
#[tokio::test(start_paused = true)]
async fn warm_camera_reports_failure_when_the_cooler_will_not_switch_off() {
    let ops =
        Arc::new(ScriptedDomeRotatorOps::new().with_failing_cooler_off(
            "Failed to set cooler: Failed to set property SetCCDTemperature",
        ));
    let ctx = ctx_with_ops(ops.clone()).await;

    let result = execute_warm_camera(
        &WarmConfig {
            rate_per_min: 60.0,
            target_temp: Some(20.0),
        },
        &ctx,
        None,
    )
    .await;

    assert_eq!(
        result.status,
        NodeStatus::Failure,
        "a warm-up that could not switch the cooler off must not report success: {:?}",
        result.message
    );
    let message = result.message.unwrap_or_default();
    assert!(
        message.contains("could not switch the cooler off"),
        "the failure must name what actually went wrong, got: {message}"
    );
    assert!(
        ops.cooler_commands
            .lock()
            .unwrap()
            .iter()
            .any(|(enabled, _)| !*enabled),
        "the instruction must still have attempted the cooler-off"
    );
}
