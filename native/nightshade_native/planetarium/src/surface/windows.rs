//! Windows D3D11/D3D12 texture surface.
//!
//! Renders into a `wgpu::Texture` backed by a D3D12 resource exported as a DXGI
//! shared handle, which `irondash_texture` registers with the Flutter engine so the
//! Dart-side `Texture(textureId: ...)` widget can display it.

use crate::renderer::Renderer;
use crate::renderer::Scene;
use crate::surface::d3d11_shared::{allocate_shared, SharedTexture};
use crate::{surface::PlatformSurface, PlanetariumError};

use irondash_texture::{
    BoxedTextureDescriptor, DxgiSharedHandle, PayloadProvider, PixelFormat, SendableTexture,
    Texture, TextureDescriptor, TextureDescriptorProvider,
};
use std::sync::Arc;

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
    flutter_texture: Arc<SendableTexture<BoxedTextureDescriptor<DxgiSharedHandle>>>,
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
    fn get(&self) -> TextureDescriptor<DxgiSharedHandle> {
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
        let provider: Arc<dyn PayloadProvider<BoxedTextureDescriptor<DxgiSharedHandle>>> =
            Arc::new(SharedHandleProvider::new(shared.clone()));
        let texture =
            Texture::new_with_provider(self.engine_handle, provider).map_err(map_irondash_err)?;
        let texture_id = texture.id();
        let flutter_texture = texture.into_sendable_texture();

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
            flutter_texture,
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
        let view = a
            .shared
            .wgpu
            .create_view(&wgpu::TextureViewDescriptor::default());
        renderer.render_into(&view, scene);
        Ok(())
    }

    fn mark_frame_available(&self) -> Result<(), PlanetariumError> {
        let Some(a) = &self.current else {
            return Err(PlanetariumError::UnsupportedPlatform(
                "mark_frame_available called before allocate",
            ));
        };
        a.flutter_texture.mark_frame_available();
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
