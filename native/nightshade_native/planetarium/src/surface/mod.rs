//! Platform texture abstraction.
//!
//! Each platform implements [`PlatformSurface`] to bridge wgpu's render target
//! to a `flutter::Texture` that Dart can display via `Texture(textureId: ...)`.
//!
//! Per CLAUDE.md: failures here surface as `PlanetariumError`, never silently
//! degrade to CPU readback in production builds.

use crate::PlanetariumError;

/// A platform-specific texture target the renderer writes into and Flutter reads from.
pub trait PlatformSurface: Send + Sync {
    /// Allocate the underlying GPU texture and register it with Flutter.
    /// Returns the texture id Flutter's `Texture` widget needs.
    fn allocate(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError>;

    /// Re-allocate at a new size. Texture id may or may not stay the same.
    fn resize(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError>;

    /// Signal Flutter that a new frame is available for the current texture id.
    fn mark_frame_available(&self) -> Result<(), PlanetariumError>;

    /// Tear down the surface.
    fn shutdown(&mut self) -> Result<(), PlanetariumError>;
}

#[cfg(target_os = "windows")]
pub mod windows;

#[cfg(not(any(target_os = "windows")))]
compile_error!("Phase 1 only supports Windows. Phase 10 adds other platforms.");

/// Create the platform surface for the current OS.
pub fn create_surface(
    engine_handle: i64,
) -> Result<Box<dyn PlatformSurface>, PlanetariumError> {
    #[cfg(target_os = "windows")]
    {
        Ok(Box::new(windows::WindowsSurface::new(engine_handle)?))
    }
}
