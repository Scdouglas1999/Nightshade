//! Windows D3D11 texture surface.
//!
//! Renders into a `wgpu::Texture` backed by a D3D11 shared texture handle,
//! which `irondash_texture` registers with the Flutter engine so the Dart-side
//! `Texture(textureId: ...)` widget can display it.

use crate::{surface::PlatformSurface, PlanetariumError};
use std::sync::Arc;

/// Windows-specific surface. Owns the engine context handle and the wgpu device.
pub struct WindowsSurface {
    engine_handle: i64,
    current: Option<Allocated>,
}

struct Allocated {
    width: u32,
    height: u32,
    texture_id: i64,
}

impl WindowsSurface {
    pub fn new(engine_handle: i64) -> Result<Self, PlanetariumError> {
        Ok(Self { engine_handle, current: None })
    }
}

impl PlatformSurface for WindowsSurface {
    fn allocate(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError> {
        // Task 5 wires this to irondash_texture + wgpu. For now, fail loudly
        // so callers can't depend on this returning a fake id.
        Err(PlanetariumError::UnsupportedPlatform(
            "WindowsSurface::allocate not yet implemented — Task 5 wires it",
        ))
    }

    fn resize(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError> {
        self.allocate(width, height)
    }

    fn mark_frame_available(&self) -> Result<(), PlanetariumError> {
        Err(PlanetariumError::UnsupportedPlatform(
            "WindowsSurface::mark_frame_available not yet implemented — Task 5",
        ))
    }

    fn shutdown(&mut self) -> Result<(), PlanetariumError> {
        self.current = None;
        Ok(())
    }
}
