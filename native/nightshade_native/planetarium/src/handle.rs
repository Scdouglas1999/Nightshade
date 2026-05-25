//! Public [`Planetarium`] handle — surface, render loop, and snapshot slot.
//!
//! Dart/FFI holds this type (via Task 15 registry). Dropping the handle shuts down
//! the render thread and platform surface cleanly.

use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;

use crossbeam_channel::SendError;
use parking_lot::Mutex;

use crate::animation::AnimationState;
use crate::bus::dirty::DirtyFlags;
use crate::gesture::GestureStateMachine;
use crate::bus::loop_thread::{FrameRenderer, RenderLoop};
use crate::bus::PlanetariumCommand;
use crate::scene::{
    load, new_snapshot_slot, publish_snapshot, SceneSnapshot, SelectedObject, SnapshotInputs,
    SnapshotSlot,
};
use crate::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC;
use crate::surface::{create_surface, PlatformSurface};
use crate::types::{AstroTime, Observer, RenderConfig, ViewPose};
use crate::PlanetariumError;

/// Sentinel: no Flutter texture registered yet. Never returned from [`Planetarium::texture_id`].
const NO_TEXTURE_ID: i64 = 0;

/// Opaque handle combining platform surface, event-driven render loop, and snapshot publishing.
pub struct Planetarium {
    inner: Arc<PlanetariumInner>,
    /// Kept last in the struct so `Drop` shuts down the render thread after `inner` fields go away.
    _render_loop: RenderLoop,
}

struct PlanetariumInner {
    cmd_tx: crossbeam_channel::Sender<PlanetariumCommand>,
    snapshot: SnapshotSlot,
    texture_id: Arc<AtomicI64>,
    surface_error: Arc<Mutex<Option<String>>>,
}

/// Renderer running on the dedicated loop thread; owns the platform surface.
struct PlanetariumRenderer {
    surface: Box<dyn PlatformSurface>,
    snapshot: SnapshotSlot,
    texture_id: Arc<AtomicI64>,
    surface_error: Arc<Mutex<Option<String>>>,
    frame_id: u64,
    view_pose: ViewPose,
    astro_time: AstroTime,
    observer: Observer,
    render_config: RenderConfig,
    selected: Option<SelectedObject>,
    gestures: GestureStateMachine,
    last_anim: AnimationState,
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
        let texture_id = Arc::new(AtomicI64::new(NO_TEXTURE_ID));
        let surface_error = Arc::new(Mutex::new(None));

        let renderer = PlanetariumRenderer {
            surface,
            snapshot: Arc::clone(&snapshot),
            texture_id: Arc::clone(&texture_id),
            surface_error: Arc::clone(&surface_error),
            frame_id: 0,
            view_pose: ViewPose::default(),
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
                texture_id,
                surface_error,
            }),
            _render_loop: render_loop,
        })
    }

    /// Enqueues a command for the render thread.
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

    /// Last surface allocate/resize failure from the render thread, if any.
    pub fn last_surface_error(&self) -> Option<String> {
        self.inner.surface_error.lock().clone()
    }
}

impl FrameRenderer for PlanetariumRenderer {
    fn on_command(&mut self, cmd: &PlanetariumCommand, dirty: &mut DirtyFlags) {
        match cmd {
            PlanetariumCommand::Resize {
                width,
                height,
                dpr: _,
            } => {
                *dirty |= DirtyFlags::RESIZE;
                *self.surface_error.lock() = None;
                match self.surface.resize(*width, *height) {
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
            }
            PlanetariumCommand::SetTime(time) => {
                self.astro_time = *time;
                *dirty |= DirtyFlags::TIME;
            }
            PlanetariumCommand::SetObserver(observer) => {
                self.observer = *observer;
                *dirty |= DirtyFlags::OBSERVER;
            }
            PlanetariumCommand::SetPose(pose) => {
                self.view_pose = *pose;
                self.gestures = GestureStateMachine::new(*pose);
                *dirty |= DirtyFlags::POSE;
            }
            PlanetariumCommand::PushGesture(evt) => {
                if self.gestures.apply(*evt) {
                    self.view_pose = self.gestures.pose();
                    *dirty |= DirtyFlags::POSE;
                }
            }
            PlanetariumCommand::SetConfig(cfg) => {
                self.render_config = *cfg;
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
        if self.texture_id.load(Ordering::Acquire) != NO_TEXTURE_ID {
            if let Err(err) = self.surface.tick() {
                tracing::error!("surface tick failed: {err}");
            }
            if let Err(err) = self.surface.mark_frame_available() {
                tracing::error!("mark_frame_available failed: {err}");
            }
        }

        self.frame_id = self.frame_id.saturating_add(1);
        publish_snapshot(
            &self.snapshot,
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
