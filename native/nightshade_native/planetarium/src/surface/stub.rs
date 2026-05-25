//! Non-Windows stub surface — compiles on Linux/macOS CI; fails loud on allocate/resize.

use crate::{surface::PlatformSurface, PlanetariumError};

const MSG: &str = "planetarium GPU surface is only supported on Windows (Phase 1)";

/// Placeholder surface so the crate builds on non-Windows targets.
pub struct StubSurface {
    _engine_handle: i64,
}

impl StubSurface {
    /// Creates a stub surface (no Flutter registration).
    pub fn new(engine_handle: i64) -> Self {
        Self {
            _engine_handle: engine_handle,
        }
    }
}

impl PlatformSurface for StubSurface {
    fn allocate(&mut self, _width: u32, _height: u32) -> Result<i64, PlanetariumError> {
        Err(PlanetariumError::UnsupportedPlatform(MSG))
    }

    fn resize(&mut self, _width: u32, _height: u32) -> Result<i64, PlanetariumError> {
        Err(PlanetariumError::UnsupportedPlatform(MSG))
    }

    fn tick(&self) -> Result<(), PlanetariumError> {
        Err(PlanetariumError::UnsupportedPlatform(MSG))
    }

    fn mark_frame_available(&self) -> Result<(), PlanetariumError> {
        Err(PlanetariumError::UnsupportedPlatform(MSG))
    }

    fn shutdown(&mut self) -> Result<(), PlanetariumError> {
        Ok(())
    }
}
