//! Render-loop integration tests: idle, wake on SetPose, animation wake, clean shutdown.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use nightshade_planetarium::animation::{AnimationSet, AnimationState};
use nightshade_planetarium::bus::dirty::DirtyFlags;
use nightshade_planetarium::bus::loop_thread::{FrameRenderer, RenderLoop};
use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::scene::{LabelCategory, SelectedObject, SmallString};
use nightshade_planetarium::types::{RenderConfig, ViewPose};

/// Test double that increments a shared frame counter every render.
///
/// Kept here in the test crate instead of production `bus::loop_thread`
/// because it has zero callers outside this file.
#[derive(Debug)]
struct CountingRenderer {
    frames: Arc<AtomicU64>,
}

impl CountingRenderer {
    fn new() -> Self {
        Self {
            frames: Arc::new(AtomicU64::new(0)),
        }
    }

    fn counter(&self) -> Arc<AtomicU64> {
        Arc::clone(&self.frames)
    }
}

impl FrameRenderer for CountingRenderer {
    fn render_frame(&mut self, _dirty: DirtyFlags, _anim: &AnimationState) {
        self.frames.fetch_add(1, Ordering::Relaxed);
    }
}

const IDLE_WAIT: Duration = Duration::from_millis(50);

const WAKE_POLL: Duration = Duration::from_millis(1);

const WAKE_TIMEOUT: Duration = Duration::from_millis(200);

fn idle_config() -> RenderConfig {
    RenderConfig {
        twinkle: false,

        show_atmosphere: false,

        ..RenderConfig::default()
    }
}

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

    let loop_handle = RenderLoop::spawn_with_animations(renderer, AnimationSet::new(idle_config()));

    thread::sleep(IDLE_WAIT);

    assert_eq!(counter.load(Ordering::Relaxed), 0);

    loop_handle.shutdown().expect("shutdown joins cleanly");
}

#[test]

fn set_pose_wakes_one_frame() {
    let renderer = CountingRenderer::new();

    let counter = renderer.counter();

    let loop_handle = RenderLoop::spawn_with_animations(renderer, AnimationSet::new(idle_config()));

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

    loop_handle.shutdown().expect("shutdown joins cleanly");
}

#[test]

fn twinkle_wakes_without_commands() {
    let renderer = CountingRenderer::new();

    let counter = renderer.counter();

    let loop_handle = RenderLoop::spawn_with_animations(
        renderer,
        AnimationSet::new(RenderConfig {
            twinkle: true,

            show_atmosphere: true,

            show_stars: true,

            ..RenderConfig::default()
        }),
    );

    wait_for_frames(&counter, 2);

    loop_handle.shutdown().expect("shutdown joins cleanly");
}

#[test]

fn set_config_mag_limit_triggers_pop_in_frames() {
    let renderer = CountingRenderer::new();

    let counter = renderer.counter();

    let loop_handle = RenderLoop::spawn_with_animations(renderer, AnimationSet::new(idle_config()));

    loop_handle
        .send(PlanetariumCommand::SetConfig(RenderConfig {
            magnitude_limit: 9.0,

            ..idle_config()
        }))
        .expect("send SetConfig");

    wait_for_frames(&counter, 1);

    loop_handle.shutdown().expect("shutdown joins cleanly");
}

#[test]

fn set_selection_wakes_pulse_frames() {
    let renderer = CountingRenderer::new();

    let counter = renderer.counter();

    let loop_handle = RenderLoop::spawn_with_animations(renderer, AnimationSet::new(idle_config()));

    loop_handle
        .send(PlanetariumCommand::SetSelection(Some(SelectedObject {
            object_id: 1,

            screen_x: 0.5,

            screen_y: 0.5,

            ra_rad: 0.0,

            dec_rad: 0.0,

            category: LabelCategory::Star,

            display_name: SmallString::new("Sirius"),
        })))
        .expect("send SetSelection");

    wait_for_frames(&counter, 1);

    loop_handle.shutdown().expect("shutdown joins cleanly");
}

#[test]

fn shutdown_exits_cleanly() {
    let renderer = CountingRenderer::new();

    let loop_handle = RenderLoop::spawn_with_animations(renderer, AnimationSet::new(idle_config()));

    loop_handle
        .shutdown()
        .expect("render thread joined without panic");
}

/// FrameRenderer that panics on its first render — used to verify the
/// render-loop Drop swallows the panic without aborting the process.
struct PanickingRenderer;

impl FrameRenderer for PanickingRenderer {
    fn render_frame(&mut self, _dirty: DirtyFlags, _anim: &AnimationState) {
        panic!("intentional panic for test");
    }
}

#[test]
fn drop_with_panicked_render_thread_does_not_double_panic() {
    // Prior implementation: `let _ = self.join_thread()` silently swallowed
    // a thread panic during Drop. Now Drop logs the error via tracing
    // before continuing — Drop itself must not panic (double-panic aborts).
    let loop_handle =
        RenderLoop::spawn_with_animations(PanickingRenderer, AnimationSet::new(idle_config()));

    // Send a command that causes a render → render thread panics.
    loop_handle
        .send(PlanetariumCommand::SetPose(ViewPose::default()))
        .expect("send before panic");
    // Give the render thread time to wake, panic, and unwind.
    thread::sleep(Duration::from_millis(50));

    // Drop runs here at end of scope; must not double-panic. If it does,
    // the test process aborts and reports as a hard fail (not a regular
    // test failure) — distinct enough to be obvious in CI.
    drop(loop_handle);
}
