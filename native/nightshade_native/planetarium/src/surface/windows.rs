//! Windows D3D11/D3D12 texture surface.
//!
//! Renders into a `wgpu::Texture` backed by a D3D12 resource exported as a DXGI
//! shared handle, which `irondash_texture` registers with the Flutter engine so the
//! Dart-side `Texture(textureId: ...)` widget can display it.

use crate::renderer::Renderer;
use crate::renderer::Scene;
use crate::surface::d3d11_shared::{allocate_shared, SharedTexture};
use crate::{surface::PlatformSurface, PlanetariumError};

use crossbeam_channel::bounded;
use irondash_engine_context::EngineContext;
use irondash_texture::{
    BoxedTextureDescriptor, DxgiSharedHandle, PayloadProvider, PixelFormat, SendableTexture,
    Texture, TextureDescriptor, TextureDescriptorProvider,
};
use std::sync::{Arc, Mutex as StdMutex};

/// Payload type returned by [`Texture::new_with_provider`] for D3D12 shared textures.
type DxgiPayload = BoxedTextureDescriptor<DxgiSharedHandle>;
type DxgiFlutterTexture = Arc<SendableTexture<DxgiPayload>>;

/// Windows-specific surface. Owns the engine context handle and the wgpu device.
pub struct WindowsSurface {
    engine_handle: i64,
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    renderer: Option<Renderer>,
    current: Option<Allocated>,
}

struct Allocated {
    width: u32,
    height: u32,
    texture_id: i64,
    shared: Arc<SharedTexture>,
    /// Cached color attachment view of the shared D3D12 texture; recreating it per
    /// frame is wasteful and creates a labelled garbage object every present.
    shared_view: wgpu::TextureView,
    /// `Option` so `Drop` can `take()` the texture and route its drop back to the
    /// Flutter platform thread (see [`Allocated::drop`]).
    flutter_texture: Option<DxgiFlutterTexture>,
}

/// Supplies the DXGI shared handle to Flutter on each raster callback.
struct SharedHandleProvider {
    shared: Arc<SharedTexture>,
    handle: DxgiSharedHandle,
}

// SAFETY: `shared_handle` is an immutable NT handle to a GPU resource that outlives this provider.
unsafe impl Send for SharedHandleProvider {}
unsafe impl Sync for SharedHandleProvider {}

impl SharedHandleProvider {
    fn new(shared: Arc<SharedTexture>) -> Self {
        Self {
            handle: DxgiSharedHandle(shared.shared_handle as *mut _),
            shared,
        }
    }
}

impl TextureDescriptorProvider<DxgiSharedHandle> for SharedHandleProvider {
    fn get(&self) -> TextureDescriptor<'_, DxgiSharedHandle> {
        TextureDescriptor {
            handle: &self.handle,
            width: self.shared.width as i32,
            height: self.shared.height as i32,
            visible_width: self.shared.width as i32,
            visible_height: self.shared.height as i32,
            pixel_format: PixelFormat::BGRA,
        }
    }
}

impl PayloadProvider<BoxedTextureDescriptor<DxgiSharedHandle>> for SharedHandleProvider {
    fn get_payload(&self) -> BoxedTextureDescriptor<DxgiSharedHandle> {
        Box::new(SharedHandleProvider::new(self.shared.clone()))
    }
}

impl WindowsSurface {
    /// Create a DX12-backed surface for the given Flutter engine handle.
    pub fn new(engine_handle: i64) -> Result<Self, PlanetariumError> {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::DX12,
            ..Default::default()
        });
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        }))
        .ok_or(PlanetariumError::UnsupportedPlatform(
            "no DX12 adapter on this Windows host",
        ))?;
        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: Some("nightshade.windows.device"),
                ..Default::default()
            },
            None,
        ))
        .map_err(|_| PlanetariumError::UnsupportedPlatform("wgpu DX12 device request failed"))?;

        let device = Arc::new(device);
        let queue = Arc::new(queue);

        Ok(Self {
            engine_handle,
            device,
            queue,
            renderer: None,
            current: None,
        })
    }

    /// wgpu device used for rendering into the shared target.
    pub fn device(&self) -> Arc<wgpu::Device> {
        self.device.clone()
    }

    /// wgpu queue paired with [`Self::device`].
    pub fn queue(&self) -> Arc<wgpu::Queue> {
        self.queue.clone()
    }

    /// Current offscreen render target, if [`PlatformSurface::allocate`] succeeded.
    pub fn wgpu_texture(&self) -> Option<Arc<wgpu::Texture>> {
        self.current.as_ref().map(|a| a.shared.wgpu.clone())
    }
}

impl PlatformSurface for WindowsSurface {
    fn allocate(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError> {
        if width == 0 || height == 0 {
            return Err(PlanetariumError::UnsupportedPlatform(
                "surface size must be positive",
            ));
        }
        let shared = Arc::new(allocate_shared(&self.device, width, height)?);
        let shared_view = shared.wgpu.create_view(&wgpu::TextureViewDescriptor {
            label: Some("planetarium.windows.shared_view"),
            ..Default::default()
        });
        let provider: Arc<dyn PayloadProvider<DxgiPayload>> =
            Arc::new(SharedHandleProvider::new(shared.clone()));

        // `Texture::new_with_provider` calls `EngineContext::get()`, which
        // returns `Error::InvalidThread` unless invoked on the Flutter
        // platform/main thread. `into_sendable_texture` likewise calls
        // `RunLoop::current()` and binds the inner `Capsule` to its calling
        // thread. We're on the dedicated render-loop thread here, so we
        // dispatch both onto the platform thread via
        // `EngineContext::perform_on_main_thread` and block for the outcome.
        let (texture_id, flutter_texture) =
            create_flutter_texture_on_main_thread(self.engine_handle, provider)?;

        self.renderer = Some(Renderer::new(
            self.device.clone(),
            self.queue.clone(),
            wgpu::TextureFormat::Bgra8Unorm,
            width,
            height,
        ));

        self.current = Some(Allocated {
            width,
            height,
            texture_id,
            shared,
            shared_view,
            flutter_texture: Some(flutter_texture),
        });
        Ok(texture_id)
    }

    fn resize(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError> {
        if let Some(a) = &self.current {
            if a.width == width && a.height == height {
                return Ok(a.texture_id);
            }
        }
        self.shutdown()?;
        self.allocate(width, height)
    }

    fn render(&mut self, scene: &Scene) -> Result<(), PlanetariumError> {
        let Some(a) = &self.current else {
            return Err(PlanetariumError::UnsupportedPlatform(
                "render called before allocate/resize",
            ));
        };
        let Some(renderer) = self.renderer.as_mut() else {
            return Err(PlanetariumError::UnsupportedPlatform(
                "renderer not initialized after allocate",
            ));
        };
        // Non-blocking submit: Flutter present + vsync pace the loop. Using
        // `render_into` would stall on `Maintain::Wait` every frame and cap us
        // at GPU-roundtrip latency.
        renderer.submit_into(&a.shared_view, scene);
        Ok(())
    }

    fn mark_frame_available(&self) -> Result<(), PlanetariumError> {
        let Some(a) = &self.current else {
            return Err(PlanetariumError::UnsupportedPlatform(
                "mark_frame_available called before allocate",
            ));
        };
        let Some(tex) = a.flutter_texture.as_ref() else {
            return Err(PlanetariumError::UnsupportedPlatform(
                "mark_frame_available called after texture drop",
            ));
        };
        // `SendableTexture::mark_frame_available` internally re-dispatches to
        // the platform thread via its RunLoopSender, so it's safe to call
        // from the render thread.
        tex.mark_frame_available();
        Ok(())
    }

    fn shutdown(&mut self) -> Result<(), PlanetariumError> {
        if let Some(a) = self.current.take() {
            drop(a);
        }
        self.renderer = None;
        Ok(())
    }
}

fn map_irondash_err(err: irondash_texture::Error) -> PlanetariumError {
    tracing::error!("irondash_texture error: {err}");
    PlanetariumError::UnsupportedPlatform("irondash_texture registration failed — see log")
}

/// Run [`Texture::new_with_provider`] + [`Texture::into_sendable_texture`] on
/// the Flutter platform thread (both are thread-affine — see
/// `EngineContext::get` and `RunLoop::current` requirements), then return the
/// texture id and the `Send + Sync` sendable wrapper to the caller's thread.
///
/// Blocks the calling thread until the platform thread runs the closure.
/// This is acceptable because resize/allocate is a rare, user-initiated
/// event, not a per-frame operation.
fn create_flutter_texture_on_main_thread(
    engine_handle: i64,
    provider: Arc<dyn PayloadProvider<DxgiPayload>>,
) -> Result<(i64, DxgiFlutterTexture), PlanetariumError> {
    let (tx, rx) = bounded::<Result<(i64, DxgiFlutterTexture), String>>(1);

    EngineContext::perform_on_main_thread(move || {
        let result = (|| -> Result<(i64, DxgiFlutterTexture), irondash_texture::Error> {
            let texture = Texture::new_with_provider(engine_handle, provider)?;
            let id = texture.id();
            let sendable = texture.into_sendable_texture();
            Ok((id, sendable))
        })()
        .map_err(|e| e.to_string());
        // Receiver may already be gone if the caller timed out; ignore the
        // send error and let the produced texture (if any) drop here on the
        // platform thread, which is safe.
        let _ = tx.send(result);
    })
    .map_err(|err| {
        tracing::error!("perform_on_main_thread dispatch failed: {err:?}");
        PlanetariumError::UnsupportedPlatform(
            "irondash_engine_context plugin not loaded — cannot create Flutter texture",
        )
    })?;

    match rx.recv() {
        Ok(Ok(pair)) => Ok(pair),
        Ok(Err(msg)) => {
            tracing::error!("irondash_texture error: {msg}");
            Err(PlanetariumError::UnsupportedPlatform(
                "irondash_texture registration failed — see log",
            ))
        }
        Err(_) => {
            tracing::error!("main-thread texture creation channel closed before reply");
            Err(PlanetariumError::UnsupportedPlatform(
                "irondash_texture creation channel closed unexpectedly",
            ))
        }
    }
}

impl Drop for Allocated {
    fn drop(&mut self) {
        // `SendableTexture`'s inner `Capsule` was created on the Flutter
        // platform thread (see [`create_flutter_texture_on_main_thread`])
        // and panics in its own `Drop` when dropped on any other thread.
        // The render thread is not the platform thread, so route the drop
        // back through `EngineContext::perform_on_main_thread`.
        //
        // The closure captures the texture through a shared slot rather than
        // by direct move: if the dispatch fails (plugin unloaded), the
        // closure is destroyed on the calling thread and would otherwise
        // drop the captured texture here → Capsule panic. Indirection lets
        // us recover the texture and `mem::forget` it as a last resort
        // instead of crashing the render thread.
        let Some(tex) = self.flutter_texture.take() else {
            return;
        };
        let slot = Arc::new(StdMutex::new(Some(tex)));
        let slot_for_closure = Arc::clone(&slot);
        let dispatched = EngineContext::perform_on_main_thread(move || {
            if let Ok(mut guard) = slot_for_closure.lock() {
                if let Some(t) = guard.take() {
                    drop(t);
                }
            }
        });
        if dispatched.is_err() {
            if let Ok(mut guard) = slot.lock() {
                if let Some(t) = guard.take() {
                    // Engine teardown reclaims the texture registration; leaking
                    // the Rust-side wrapper avoids the Capsule wrong-thread panic.
                    std::mem::forget(t);
                }
            }
            tracing::warn!(
                "flutter_texture drop dispatch failed — leaked to avoid wrong-thread Capsule panic"
            );
        }
    }
}
