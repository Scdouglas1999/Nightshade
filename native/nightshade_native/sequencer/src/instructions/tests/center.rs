//! `center` tests — moved verbatim out of the former single `instructions::tests`
//! module (release-pass C3 mechanical split). Shared fixtures stay in the parent
//! `tests` module and reach here through `use super::*;`.

use super::*;

#[tokio::test(start_paused = true)]
async fn centering_waits_for_slew_startup_before_accepting_idle() {
    let ops = Arc::new(
        ScriptedDomeRotatorOps::new()
            .with_mount_slewing_states(vec![false, false, true, true, false]),
    );
    let mut ctx = ctx_with_ops(ops.clone()).await;
    ctx.mount_id = Some("mount-1".to_string());

    wait_for_centering_correction_slew("mount-1", &ctx)
        .await
        .expect("slew should start after the driver's delayed status update and then finish");

    assert_eq!(
        ops.mount_slew_state_calls.load(Ordering::SeqCst),
        5,
        "the initial idle polls must not be mistaken for slew completion"
    );
}
