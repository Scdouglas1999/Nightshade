//! Render-loop integration tests: idle, wake on SetPose, clean shutdown.

use std::sync::atomic::Ordering;
use std::thread;
use std::time::Duration;

use nightshade_planetarium::bus::loop_thread::{CountingRenderer, RenderLoop};
use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::types::ViewPose;

const IDLE_WAIT: Duration = Duration::from_millis(50);
const WAKE_POLL: Duration = Duration::from_millis(1);
const WAKE_TIMEOUT: Duration = Duration::from_millis(200);

fn wait_for_frames(counter: &std::sync::Arc<std::sync::atomic::AtomicU64>, expected: u64) {
    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    while std::time::Instant::now() < deadline {
        if counter.load(Ordering::Relaxed) >= expected {
            return;
        }
        thread::sleep(WAKE_POLL);
    }
    panic!(
        "timed out waiting for {expected} frame(s); got {}",
        counter.load(Ordering::Relaxed)
    );
}

#[test]
fn idle_produces_no_frames() {
    let renderer = CountingRenderer::new();
    let counter = renderer.counter();
    let loop_handle = RenderLoop::spawn(renderer);

    thread::sleep(IDLE_WAIT);
    assert_eq!(counter.load(Ordering::Relaxed), 0);

    loop_handle
        .shutdown()
        .expect("shutdown joins cleanly");
}

#[test]
fn set_pose_wakes_one_frame() {
    let renderer = CountingRenderer::new();
    let counter = renderer.counter();
    let loop_handle = RenderLoop::spawn(renderer);

    loop_handle
        .send(PlanetariumCommand::SetPose(ViewPose::default()))
        .expect("send SetPose");

    wait_for_frames(&counter, 1);
    thread::sleep(IDLE_WAIT);
    assert_eq!(
        counter.load(Ordering::Relaxed),
        1,
        "coalesced idle should not render extra frames"
    );

    loop_handle
        .shutdown()
        .expect("shutdown joins cleanly");
}

#[test]
fn shutdown_exits_cleanly() {
    let renderer = CountingRenderer::new();
    let loop_handle = RenderLoop::spawn(renderer);

    loop_handle
        .shutdown()
        .expect("render thread joined without panic");
}
