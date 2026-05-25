//! Public [`Planetarium`] handle — surface, render loop, and snapshot slot.
//!
//! Dart/FFI holds this type (via Task 15 registry). Dropping the handle shuts down
//! the render thread and platform surface cleanly.

use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::sync::Arc;

use crossbeam_channel::SendError;
use parking_lot::Mutex;

use crate::animation::AnimationState;
use crate::bus::dirty::DirtyFlags;
use crate::bus::loop_thread::{FrameRenderer, RenderLoop};
use crate::bus::PlanetariumCommand;
use std::path::Path;

use crate::catalog::{open_star_tile_pack, CatalogSet, StarPack};
use crate::gesture::{hit_test_screen, GestureStateMachine, HitTestError};
use crate::scene::{
    build_render_scene, load, new_snapshot_slot, publish_snapshot, BuildSceneInputs,
    SceneSnapshot, SelectedObject, SnapshotInputs, SnapshotSlot,
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
    /// Kept last in the struct so `Drop` shuts down the render thread after `inner` fields go away.
    _render_loop: RenderLoop,
}

struct PlanetariumInner {
    cmd_tx: crossbeam_channel::Sender<PlanetariumCommand>,
    snapshot: SnapshotSlot,
    texture_id: Arc<AtomicI64>,
    surface_error: Arc<Mutex<Option<String>>>,
    /// Incremented at the start of each [`PlanetariumCommand::Resize`] (observable retry).
    resize_generation: Arc<AtomicU64>,
    catalog: Arc<Mutex<CatalogSet>>,
    render_config: Mutex<RenderConfig>,
}

/// Renderer running on the dedicated loop thread; owns the platform surface.
struct PlanetariumRenderer {
    surface: Box<dyn PlatformSurface>,
    snapshot: SnapshotSlot,
    texture_id: Arc<AtomicI64>,
    surface_error: Arc<Mutex<Option<String>>>,
    resize_generation: Arc<AtomicU64>,
    catalog: Arc<Mutex<CatalogSet>>,
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
        let resize_generation = Arc::new(AtomicU64::new(0));
        let catalog = Arc::new(Mutex::new(CatalogSet::new()));

        let renderer = PlanetariumRenderer {
            surface,
            snapshot: Arc::clone(&snapshot),
            texture_id: Arc::clone(&texture_id),
            surface_error: Arc::clone(&surface_error),
            resize_generation: Arc::clone(&resize_generation),
            catalog: Arc::clone(&catalog),
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
                resize_generation,
                catalog,
                render_config: Mutex::new(RenderConfig::default()),
            }),
            _render_loop: render_loop,
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
    pub fn hit_test(&self, x: f32, y: f32) -> Result<Option<SelectedObject>, HitTestError> {
        let pose = self.snapshot().view_pose;
        let mag_limit = self.inner.render_config.lock().magnitude_limit;
        hit_test_screen(&self.inner.catalog.lock(), x, y, pose, mag_limit)
    }

    /// Enqueues a command for the render thread.
    pub fn send(&self, cmd: PlanetariumCommand) -> Result<(), PlanetariumError> {
        if let PlanetariumCommand::SetConfig(cfg) = &cmd {
            *self.inner.render_config.lock() = *cfg;
        }
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

    /// Number of [`PlanetariumCommand::Resize`] commands processed on the render thread.
    pub fn resize_generation(&self) -> u64 {
        self.inner.resize_generation.load(Ordering::Acquire)
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
        let build_inputs = BuildSceneInputs {
            view_pose: self.view_pose,
            render_config: self.render_config,
            observer: self.observer,
            astro_time: self.astro_time,
        };

        let catalog = self.catalog.lock();
        let scene = match build_render_scene(&catalog, build_inputs, anim) {
            Ok(scene) => scene,
            Err(err) => {
                tracing::error!("build_render_scene failed: {err}");
                self.frame_id = self.frame_id.saturating_add(1);
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
                return;
            }
        };
        drop(catalog);

        if self.texture_id.load(Ordering::Acquire) != NO_TEXTURE_ID {
            if let Err(err) = self.surface.render(&scene) {
                tracing::error!("surface render failed: {err}");
            }
            if let Err(err) = self.surface.mark_frame_available() {
                tracing::error!("mark_frame_available failed: {err}");
            }
        }

        self.frame_id = self.frame_id.saturating_add(1);
        let catalog = self.catalog.lock();
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
