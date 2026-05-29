//! Event-driven render loop running on a dedicated thread.
//!
//! The loop blocks on the command channel when nothing is dirty and no animation
//! needs periodic wakeups (zero frame work). Incoming commands set [`DirtyFlags`];
//! continuous animations (twinkle) and timed effects (selection pulse, pop-in)
//! wake the loop via [`recv_timeout`](crossbeam_channel::Receiver::recv_timeout) even
//! without new commands. [`PlanetariumCommand::Shutdown`] ends the thread cleanly.

use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crossbeam_channel::{Receiver, RecvError, RecvTimeoutError, SendError, Sender};

use crate::animation::{AnimationSet, AnimationState};

use super::dirty::DirtyFlags;
use super::PlanetariumCommand;

/// Renders one frame when the loop has pending dirty state or animation tick.
pub trait FrameRenderer: Send {
    /// Apply side effects for an incoming command and update dirty flags.
    ///
    /// Default implementation only updates [`DirtyFlags`]; production renderers may
    /// also drive platform surface resize, snapshot state, etc.
    fn on_command(&mut self, cmd: &PlanetariumCommand, dirty: &mut DirtyFlags) {
        cmd.apply_dirty(dirty);
    }

    /// Draw (or simulate drawing) for the given dirty subsystem flags and animation sample.
    fn render_frame(&mut self, dirty: DirtyFlags, anim: &AnimationState);

    /// Whether the renderer needs the loop to keep waking even with no commands
    /// queued and no [`AnimationSet`] animation active.
    ///
    /// Used for renderer-owned continuous state — most importantly, pan
    /// **momentum** after a release-fling. The gesture state machine coasts
    /// for ~1 s after release; without this hook the loop would block in
    /// [`Receiver::recv`] the instant the user lifted their finger and the
    /// view would freeze mid-fling. Default `false`.
    fn needs_continuous_tick(&self) -> bool {
        false
    }
}

/// Handle to a running render-loop thread.
pub struct RenderLoop {
    cmd_tx: Sender<PlanetariumCommand>,
    thread: Option<JoinHandle<()>>,
}

impl RenderLoop {
    /// Spawns the render loop with default [`AnimationSet`] (twinkle on per [`RenderConfig::default`]).
    pub fn spawn<R: FrameRenderer + 'static>(renderer: R) -> Self {
        Self::spawn_with_animations(renderer, AnimationSet::default())
    }

    /// Spawns the render loop with a custom animation configuration (used in tests).
    pub fn spawn_with_animations<R: FrameRenderer + 'static>(
        renderer: R,
        animations: AnimationSet,
    ) -> Self {
        let (cmd_tx, cmd_rx) = crossbeam_channel::unbounded();
        let thread = thread::spawn(move || run(cmd_rx, renderer, animations));
        Self {
            cmd_tx,
            thread: Some(thread),
        }
    }

    /// Command sender used by the FFI / planetarium handle (wired in Task 14).
    pub fn sender(&self) -> &Sender<PlanetariumCommand> {
        &self.cmd_tx
    }

    /// Enqueues a command for the render thread.
    pub fn send(&self, cmd: PlanetariumCommand) -> Result<(), SendError<PlanetariumCommand>> {
        self.cmd_tx.send(cmd)
    }

    /// Sends [`PlanetariumCommand::Shutdown`] and waits for the render thread to exit.
    pub fn shutdown(mut self) -> Result<(), LoopJoinError> {
        let _ = self.cmd_tx.send(PlanetariumCommand::Shutdown);
        self.join_thread()
    }

    fn join_thread(&mut self) -> Result<(), LoopJoinError> {
        if let Some(handle) = self.thread.take() {
            handle.join().map_err(|_| LoopJoinError::Panicked)?;
        }
        Ok(())
    }
}

impl Drop for RenderLoop {
    fn drop(&mut self) {
        // Best-effort shutdown send: if the thread has already exited (panic or
        // clean), the channel is closed and the send errors silently — that's
        // fine, the join below tells us what actually happened.
        let _ = self.cmd_tx.send(PlanetariumCommand::Shutdown);
        if let Err(err) = self.join_thread() {
            // A render-thread panic during Drop is a real bug — preserving it
            // through `let _ = ...` would hide it for months. We can't surface
            // it via the Drop signature, but we can make it loud in the log
            // (fail-loud per CLAUDE.md). Tests assert via tracing-test.
            tracing::error!(?err, "render loop thread panicked during shutdown");
        }
    }
}

/// Error while joining the render-loop thread.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoopJoinError {
    /// The render thread panicked.
    Panicked,
}

fn run<R: FrameRenderer>(
    cmd_rx: Receiver<PlanetariumCommand>,
    mut renderer: R,
    mut animations: AnimationSet,
) {
    let mut dirty = DirtyFlags::empty();

    // Continuous-tick wake interval (~60 Hz). Used for renderer-owned animated
    // state like pan momentum that isn't driven by [`AnimationSet`].
    const CONTINUOUS_TICK: Duration = Duration::from_millis(16);

    loop {
        let renderer_wants_tick = renderer.needs_continuous_tick();
        if dirty.any() || animations.needs_wake() || renderer_wants_tick {
            // Dirty work renders immediately; animation-only waits use `next_wakeup`,
            // or a fixed ~60 Hz tick when only the renderer needs continuous waking.
            let timeout = if dirty.any() {
                Duration::ZERO
            } else if animations.needs_wake() {
                animations.next_wakeup().min(CONTINUOUS_TICK)
            } else {
                CONTINUOUS_TICK
            };
            match cmd_rx.recv_timeout(timeout) {
                Ok(PlanetariumCommand::Shutdown) => return,
                Ok(cmd) => apply_command(&mut renderer, &mut dirty, &mut animations, cmd),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return,
            }

            while let Ok(cmd) = cmd_rx.try_recv() {
                match cmd {
                    PlanetariumCommand::Shutdown => return,
                    other => apply_command(&mut renderer, &mut dirty, &mut animations, other),
                }
            }

            let now = Instant::now();
            let anim_tick = animations.advance(now);
            if dirty.any() || anim_tick || renderer.needs_continuous_tick() {
                let state = animations.state(now);
                renderer.render_frame(dirty, &state);
                dirty = DirtyFlags::empty();
            }
        } else {
            match cmd_rx.recv() {
                Ok(PlanetariumCommand::Shutdown) => return,
                Ok(cmd) => apply_command(&mut renderer, &mut dirty, &mut animations, cmd),
                Err(RecvError) => return,
            }
        }
    }
}

fn apply_command<R: FrameRenderer>(
    renderer: &mut R,
    dirty: &mut DirtyFlags,
    animations: &mut AnimationSet,
    cmd: PlanetariumCommand,
) {
    let now = Instant::now();
    animations.on_command(&cmd, now);
    renderer.on_command(&cmd, dirty);
}

trait DirtyExt {
    fn any(self) -> bool;
}

impl DirtyExt for DirtyFlags {
    fn any(self) -> bool {
        !self.is_empty()
    }
}
