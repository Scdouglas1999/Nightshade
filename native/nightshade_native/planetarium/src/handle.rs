//! Public [`Planetarium`] handle — surface, render loop, and snapshot slot.
//!
//! Dart/FFI holds this type (via Task 15 registry). Dropping the handle shuts down
//! the render thread and platform surface cleanly.

use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::sync::Arc;

use arc_swap::ArcSwap;
use crossbeam_channel::SendError;
use parking_lot::{Condvar, Mutex};
use std::time::Duration;

use crate::animation::AnimationState;
use crate::bus::dirty::DirtyFlags;
use crate::bus::loop_thread::{FrameRenderer, RenderLoop};
use crate::bus::PlanetariumCommand;
use std::path::Path;

use crate::catalog::{open_star_tile_pack, CatalogSet, StarPack};
use crate::gesture::{hit_test_screen, GestureStateMachine, HitTestError};
use crate::scene::{
    build_render_scene, load, new_snapshot_slot, publish_snapshot, BuildSceneInputs,
    MountPosition, PoseController, PoseInputs, PoseLock, SceneSnapshot, SelectedObject,
    SnapshotInputs, SnapshotSlot, TrackingTarget,
};
use crate::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC;
use crate::surface::{create_surface, PlatformSurface};
use crate::types::{AstroTime, Observer, RenderConfig, ViewPose};
use crate::PlanetariumError;

/// Sentinel: no Flutter texture registered yet. Never returned from [`Planetarium::texture_id`].
const NO_TEXTURE_ID: i64 = 0;

/// Logical layout size → physical texture pixels (Flutter logical size × device pixel ratio).
fn physical_texture_dimensions(width: u32, height: u32, dpr: f32) -> (u32, u32) {
    let dpr = if dpr.is_finite() && dpr > 0.0 { dpr } else { 1.0 };
    let w = (width as f32 * dpr).round().max(1.0) as u32;
    let h = (height as f32 * dpr).round().max(1.0) as u32;
    (w, h)
}

/// Opaque handle combining platform surface, event-driven render loop, and snapshot publishing.
pub struct Planetarium {
    inner: Arc<PlanetariumInner>,
    /// Never read — held solely so its `Drop` runs at end-of-handle-lifetime.
    ///
    /// MUST be declared AFTER `inner` so `Drop` runs `render_loop` first — joining
    /// the render thread before the shared state in `inner` (snapshot slot, atomics,
    /// catalog mutex, ArcSwap pose/config slots) goes away. Swapping the field
    /// order would let `inner` drop first, leaving an in-flight render frame
    /// with dangling `Arc`s — a use-after-free.
    ///
    /// (The previous underscore-prefix name suggested "unused" to readers; it is
    /// load-bearing. Encoding the invariant in a wrapper type would be sturdier —
    /// see the follow-up note in the cleanup punch list.)
    #[allow(dead_code)]
    render_loop: RenderLoop,
}

struct PlanetariumInner {
    cmd_tx: crossbeam_channel::Sender<PlanetariumCommand>,
    snapshot: SnapshotSlot,
    /// Lock-free, render-thread-published view pose, refreshed on every command
    /// that mutates pose (not just on render). [`Planetarium::hit_test`] reads
    /// this instead of the published [`SceneSnapshot::view_pose`] which lags by
    /// up to one full render cycle.
    live_pose: Arc<ArcSwap<ViewPose>>,
    /// Lock-free, render-thread-published render config. Single source of truth:
    /// the previous FFI-thread mirror would drift from the render thread's copy
    /// because [`Planetarium::send`] applied SetConfig synchronously before the
    /// command was processed, while the render thread ignored that mirror.
    live_render_config: Arc<ArcSwap<RenderConfig>>,
    texture_id: Arc<AtomicI64>,
    surface_error: Arc<Mutex<Option<String>>>,
    /// Incremented at the start of each [`PlanetariumCommand::Resize`] (observable retry).
    resize_generation: Arc<AtomicU64>,
    /// Mutex+Condvar pair the render thread notifies after EVERY resize attempt,
    /// success or failure. [`Planetarium::wait_for_texture_id`] blocks on it so
    /// FFI callers don't busy-poll. The bool is incremented (mod 2 — boolean
    /// semantics don't matter, only the wakeup) to satisfy spurious-wake checks.
    texture_signal: Arc<(Mutex<u64>, Condvar)>,
    catalog: Arc<Mutex<CatalogSet>>,
}

/// Renderer running on the dedicated loop thread; owns the platform surface.
struct PlanetariumRenderer {
    surface: Box<dyn PlatformSurface>,
    snapshot: SnapshotSlot,
    /// Mirror of [`PlanetariumInner::live_pose`] held by the render thread; the
    /// only writer of the inner ArcSwap. See [`Self::refresh_view_pose`].
    live_pose: Arc<ArcSwap<ViewPose>>,
    /// Mirror of [`PlanetariumInner::live_render_config`]; the only writer.
    live_render_config: Arc<ArcSwap<RenderConfig>>,
    texture_id: Arc<AtomicI64>,
    surface_error: Arc<Mutex<Option<String>>>,
    resize_generation: Arc<AtomicU64>,
    texture_signal: Arc<(Mutex<u64>, Condvar)>,
    catalog: Arc<Mutex<CatalogSet>>,
    frame_id: u64,
    view_pose: ViewPose,
    pose_ctrl: PoseController,
    mount: Option<MountPosition>,
    tracking_target: Option<TrackingTarget>,
    astro_time: AstroTime,
    observer: Observer,
    render_config: RenderConfig,
    selected: Option<SelectedObject>,
    gestures: GestureStateMachine,
    last_anim: AnimationState,
}

impl PlanetariumRenderer {
    fn pose_inputs(&self) -> PoseInputs {
        PoseInputs {
            time: self.astro_time,
            mount: self.mount,
            target: self.tracking_target,
        }
    }

    fn refresh_view_pose(&mut self) {
        let inputs = self.pose_inputs();
        match self.pose_ctrl.derived_pose(&inputs) {
            Ok(pose) => {
                self.view_pose = pose;
                // Publish to the lock-free slot so cross-thread readers (FFI
                // `hit_test`, etc.) see the pose as soon as the render thread
                // observes it, not on the next frame boundary.
                self.live_pose.store(Arc::new(pose));
            }
            Err(err) => tracing::error!("derived view pose failed: {err}"),
        }
    }

    fn sync_gestures_to_pose_ctrl(&mut self) {
        let inputs = self.pose_inputs();
        if let Err(err) = self
            .pose_ctrl
            .apply_user_pose(&inputs, self.gestures.pose())
        {
            tracing::error!("apply gesture pose failed: {err}");
        }
        self.refresh_view_pose();
    }
}

impl Planetarium {
    /// Creates a planetarium for the given Flutter engine handle.
    ///
    /// Succeeds without a live Flutter engine (e.g. `engine_handle: 0` in unit tests).
    /// [`PlatformSurface::allocate`] / resize run when a [`PlanetariumCommand::Resize`]
    /// is processed on the render thread and require a valid engine handle.
    pub fn new(engine_handle: i64) -> Result<Self, PlanetariumError> {
        let surface = create_surface(engine_handle)?;
        let snapshot = new_snapshot_slot();
        let live_pose = Arc::new(ArcSwap::from_pointee(ViewPose::default()));
        let live_render_config = Arc::new(ArcSwap::from_pointee(RenderConfig::default()));
        let texture_id = Arc::new(AtomicI64::new(NO_TEXTURE_ID));
        let surface_error = Arc::new(Mutex::new(None));
        let resize_generation = Arc::new(AtomicU64::new(0));
        let texture_signal = Arc::new((Mutex::new(0_u64), Condvar::new()));
        let catalog = Arc::new(Mutex::new(CatalogSet::new()));

        let renderer = PlanetariumRenderer {
            surface,
            snapshot: Arc::clone(&snapshot),
            live_pose: Arc::clone(&live_pose),
            live_render_config: Arc::clone(&live_render_config),
            texture_id: Arc::clone(&texture_id),
            surface_error: Arc::clone(&surface_error),
            resize_generation: Arc::clone(&resize_generation),
            texture_signal: Arc::clone(&texture_signal),
            catalog: Arc::clone(&catalog),
            frame_id: 0,
            view_pose: ViewPose::default(),
            pose_ctrl: PoseController::new(ViewPose::default()),
            mount: None,
            tracking_target: None,
            astro_time: AstroTime::from_jd_utc(DEFAULT_ASTRO_TIME_JD_UTC),
            observer: Observer::default(),
            render_config: RenderConfig::default(),
            selected: None,
            gestures: GestureStateMachine::new(ViewPose::default()),
            last_anim: AnimationState::INACTIVE,
        };

        let render_loop = RenderLoop::spawn(renderer);
        let cmd_tx = render_loop.sender().clone();

        Ok(Self {
            inner: Arc::new(PlanetariumInner {
                cmd_tx,
                snapshot,
                live_pose,
                live_render_config,
                texture_id,
                surface_error,
                resize_generation,
                texture_signal,
                catalog,
            }),
            render_loop,
        })
    }

    /// Registers a star catalog pack for rendering queries and screen hit testing.
    pub fn register_pack(&self, pack: Box<dyn StarPack>) {
        self.inner.catalog.lock().register(pack);
    }

    /// Load a verified star-tile pack from disk and register it on this handle.
    pub fn load_pack(&self, pack_dir: &Path) -> Result<(), PlanetariumError> {
        let pack = open_star_tile_pack(pack_dir).map_err(|e| PlanetariumError::CatalogPack(e.to_string()))?;
        self.register_pack(pack);
        Ok(())
    }

    /// Screen pick at normalized coordinates using registered catalog hit indexes.
    ///
    /// Uses the render-thread's most recently derived pose
    /// ([`PlanetariumInner::live_pose`]) rather than the published snapshot,
    /// which lags by up to a full render cycle. Critical for hit tests issued
    /// immediately after a `SetPose` / mount tracking update.
    pub fn hit_test(&self, x: f32, y: f32) -> Result<Option<SelectedObject>, HitTestError> {
        let pose = self.live_pose();
        let mag_limit = self.live_render_config().magnitude_limit;
        hit_test_screen(&self.inner.catalog.lock(), x, y, pose, mag_limit)
    }

    /// Enqueues a command for the render thread.
    ///
    /// All state mutation is deferred to the render thread; `send` is
    /// fire-and-forget aside from the channel-closed error. Previous versions
    /// also wrote a local-cache mirror of [`PlanetariumCommand::SetConfig`] —
    /// removed in favor of [`Self::live_render_config`] published by the
    /// render thread, so FFI readers can never see a state that no rendered
    /// frame ever saw.
    pub fn send(&self, cmd: PlanetariumCommand) -> Result<(), PlanetariumError> {
        self.inner
            .cmd_tx
            .send(cmd)
            .map_err(|_: SendError<PlanetariumCommand>| PlanetariumError::ChannelClosed)
    }

    /// Returns the latest published scene snapshot (lock-free read).
    pub fn snapshot(&self) -> Arc<SceneSnapshot> {
        load(&self.inner.snapshot)
    }

    /// Flutter `Texture` widget id after a successful resize/allocate on the render thread.
    ///
    /// Returns [`PlanetariumError::NotAllocated`] until the first successful
    /// [`PlanetariumCommand::Resize`]. Never invents a placeholder id.
    pub fn texture_id(&self) -> Result<i64, PlanetariumError> {
        let id = self.inner.texture_id.load(Ordering::Acquire);
        if id == NO_TEXTURE_ID {
            Err(PlanetariumError::NotAllocated)
        } else {
            Ok(id)
        }
    }

    /// Block until the render thread reports a texture allocation outcome from
    /// a resize attempt newer than `since_resize_gen`, or `timeout` elapses.
    ///
    /// Use [`Self::resize_generation`] to capture `since_resize_gen` BEFORE
    /// sending the [`PlanetariumCommand::Resize`] command — that way the
    /// waiter correctly detects an outcome from a resize that completed
    /// before the waiter began waiting. (If you call `wait_for_texture_id`
    /// without first snapshotting the generation, you may miss the notify
    /// that fired before you started listening.)
    ///
    /// Returns `Ok(id)` when the surface allocates successfully. Returns
    /// `Err(NotAllocated)` either when `timeout` elapses or when the render
    /// thread completes a resize attempt that produced an error (use
    /// [`Self::last_surface_error`] to distinguish). Signal-driven —
    /// the render thread notifies the underlying condvar after every resize
    /// attempt (success OR failure), so the FFI caller unblocks the moment a
    /// definitive outcome exists, without busy-polling.
    pub fn wait_for_texture_id(
        &self,
        since_resize_gen: u64,
        timeout: Duration,
    ) -> Result<i64, PlanetariumError> {
        // Fast path: already allocated. No mutex acquisition.
        if let Ok(id) = self.texture_id() {
            return Ok(id);
        }
        // Fast path: a resize newer than `since_resize_gen` has already
        // completed and produced a definitive failure outcome.
        if self.resize_generation() > since_resize_gen
            && self.inner.surface_error.lock().is_some()
        {
            return Err(PlanetariumError::NotAllocated);
        }

        let (lock, cond) = &*self.inner.texture_signal;
        let mut guard = lock.lock();
        let deadline = std::time::Instant::now() + timeout;
        loop {
            // Re-check on every wake — handles spurious wakes and notifies
            // that fired between the fast-path check and the lock acquisition.
            if let Ok(id) = self.texture_id() {
                return Ok(id);
            }
            if self.resize_generation() > since_resize_gen
                && self.inner.surface_error.lock().is_some()
            {
                return Err(PlanetariumError::NotAllocated);
            }
            let now = std::time::Instant::now();
            if now >= deadline {
                return Err(PlanetariumError::NotAllocated);
            }
            let _ = cond.wait_for(&mut guard, deadline - now);
        }
    }

    /// Last surface allocate/resize failure from the render thread, if any.
    pub fn last_surface_error(&self) -> Option<String> {
        self.inner.surface_error.lock().clone()
    }

    /// Number of [`PlanetariumCommand::Resize`] commands processed on the render thread.
    pub fn resize_generation(&self) -> u64 {
        self.inner.resize_generation.load(Ordering::Acquire)
    }

    /// Render-thread-published current pose, updated by every command that
    /// changes the derived pose. Refreshed at command-processing time — not
    /// at frame-render time — so it leads [`Self::snapshot`]`.view_pose` by up
    /// to one full render cycle. Used by [`Self::hit_test`].
    pub fn live_pose(&self) -> ViewPose {
        **self.inner.live_pose.load()
    }

    /// Render-thread-published render config, single source of truth. Updated
    /// inside the [`PlanetariumCommand::SetConfig`] handler. Reads are lock-free.
    pub fn live_render_config(&self) -> RenderConfig {
        **self.inner.live_render_config.load()
    }
}

impl FrameRenderer for PlanetariumRenderer {
    fn on_command(&mut self, cmd: &PlanetariumCommand, dirty: &mut DirtyFlags) {
        match cmd {
            PlanetariumCommand::Resize {
                width,
                height,
                dpr,
            } => {
                *dirty |= DirtyFlags::RESIZE;
                self.resize_generation.fetch_add(1, Ordering::Release);
                *self.surface_error.lock() = None;
                let (width, height) = physical_texture_dimensions(*width, *height, *dpr);
                match self.surface.resize(width, height) {
                    Ok(id) => {
                        *self.surface_error.lock() = None;
                        self.texture_id.store(id, Ordering::Release);
                    }
                    Err(err) => {
                        *self.surface_error.lock() = Some(err.to_string());
                        self.texture_id.store(NO_TEXTURE_ID, Ordering::Release);
                        tracing::error!("surface resize failed: {err}");
                    }
                }
                // Wake any FFI thread blocked in `wait_for_texture_id` regardless
                // of success/failure — both outcomes are observable on the slot.
                let (lock, cond) = &*self.texture_signal;
                *lock.lock() += 1;
                cond.notify_all();
            }
            PlanetariumCommand::SetTime(time) => {
                self.astro_time = *time;
                *dirty |= DirtyFlags::TIME;
                if !matches!(self.pose_ctrl.lock(), PoseLock::Free) {
                    self.refresh_view_pose();
                }
            }
            PlanetariumCommand::SetObserver(observer) => {
                self.observer = *observer;
                *dirty |= DirtyFlags::OBSERVER;
            }
            PlanetariumCommand::SetPose(pose) => {
                if let Err(err) = self.pose_ctrl.apply_user_pose(&self.pose_inputs(), *pose) {
                    tracing::error!("SetPose apply_user_pose failed: {err}");
                }
                self.refresh_view_pose();
                // Re-anchor the gesture machine on the new pose WITHOUT cancelling
                // any in-flight pan momentum or active gesture phase: a programmatic
                // pose update (Dart following a target, etc.) should not silently
                // kill the user's release-fling. Cancellation is what
                // GestureEvent::Cancel is for.
                self.gestures.set_pose_anchor(self.view_pose);
                *dirty |= DirtyFlags::POSE;
            }
            PlanetariumCommand::SetMountPosition(mount) => {
                self.mount = *mount;
                self.refresh_view_pose();
            }
            PlanetariumCommand::SetTrackingTarget(target) => {
                // Setting the tracking target only updates the stored coordinates;
                // it does NOT change the pose lock. Locking is the explicit job of
                // `SetPoseLock(LockedToTarget(id))`. Conflating the two silently
                // hijacks the user's view when they're just preparing a target.
                self.tracking_target = target.clone();
                self.refresh_view_pose();
            }
            PlanetariumCommand::SetPoseLock(lock) => {
                self.pose_ctrl.set_lock(*lock);
                self.refresh_view_pose();
            }
            PlanetariumCommand::PushGesture(evt) => {
                if self.gestures.apply(*evt) {
                    self.sync_gestures_to_pose_ctrl();
                    *dirty |= DirtyFlags::POSE;
                }
            }
            PlanetariumCommand::SetConfig(cfg) => {
                self.render_config = *cfg;
                self.live_render_config.store(Arc::new(*cfg));
                *dirty |= DirtyFlags::CONFIG;
            }
            PlanetariumCommand::SetSelection(sel) => {
                self.selected = sel.clone();
                *dirty |= DirtyFlags::SELECTION;
            }
            other => other.apply_dirty(dirty),
        }
    }

    fn render_frame(&mut self, _dirty: DirtyFlags, anim: &AnimationState) {
        self.last_anim = *anim;
        self.refresh_view_pose();

        // Each call advances the frame counter exactly once, regardless of which
        // sub-step (scene build / GPU draw / present) fails. Dart polls the
        // snapshot frame_id to detect liveness; a stalled counter would be read
        // as "render loop hung" — far worse than publishing a snapshot whose
        // view_pose is fresh but whose texture wasn't redrawn this frame.
        self.frame_id = self.frame_id.saturating_add(1);

        let build_inputs = BuildSceneInputs {
            view_pose: self.view_pose,
            render_config: self.render_config,
            observer: self.observer,
            astro_time: self.astro_time,
        };

        let catalog = self.catalog.lock();
        match build_render_scene(&catalog, build_inputs, anim, None) {
            Ok(scene) => {
                if self.texture_id.load(Ordering::Acquire) != NO_TEXTURE_ID {
                    if let Err(err) = self.surface.render(&scene) {
                        tracing::error!("surface render failed: {err}");
                    }
                    if let Err(err) = self.surface.mark_frame_available() {
                        tracing::error!("mark_frame_available failed: {err}");
                    }
                }
            }
            Err(err) => {
                tracing::error!("build_render_scene failed: {err}");
            }
        }

        // Publish exactly once per frame so frame_id advances monotonically by 1
        // across error/success transitions. The snapshot always reflects current
        // pose/time/observer so Dart overlay layers (labels, FOV ring) stay
        // consistent with whatever the GPU drew (or, on a build failure, with
        // what was attempted).
        publish_snapshot(
            &self.snapshot,
            &catalog,
            SnapshotInputs {
                frame_id: self.frame_id,
                view_pose: self.view_pose,
                astro_time: self.astro_time,
                observer: self.observer,
                render_config: self.render_config,
                selected: self.selected.clone(),
            },
        );
    }
}

#[cfg(test)]
mod resize_tests {
    use super::physical_texture_dimensions;

    #[test]
    fn physical_texture_dimensions_scales_by_dpr() {
        assert_eq!(physical_texture_dimensions(100, 200, 2.0), (200, 400));
        assert_eq!(physical_texture_dimensions(100, 200, 1.0), (100, 200));
    }

    #[test]
    fn physical_texture_dimensions_clamps_invalid_dpr_to_one() {
        assert_eq!(physical_texture_dimensions(64, 48, 0.0), (64, 48));
        assert_eq!(physical_texture_dimensions(64, 48, f32::NAN), (64, 48));
    }

    #[test]
    fn physical_texture_dimensions_minimum_one_pixel() {
        assert_eq!(physical_texture_dimensions(1, 1, 0.5), (1, 1));
    }
}
