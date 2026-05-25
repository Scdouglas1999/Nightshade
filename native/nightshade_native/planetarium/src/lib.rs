//! Nightshade Planetarium v2 — Rust+wgpu renderer.
//!
//! See docs/plans/2026-05-25-planetarium-v2-design.md for the full architecture.

#![deny(unsafe_op_in_unsafe_fn)]
#![warn(missing_docs)]

/// Crate-wide error type. Per CLAUDE.md, fail loud — no silent fallbacks.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PlanetariumError {
    /// A platform surface could not be created for the current platform.
    #[error("platform surface unsupported: {0}")]
    UnsupportedPlatform(&'static str),
    /// No Flutter texture has been allocated yet (resize not completed successfully).
    #[error("texture not allocated — send Resize with a valid engine handle first")]
    NotAllocated,
    /// The render-loop command channel is closed (handle dropped or thread exited).
    #[error("command channel closed")]
    ChannelClosed,
    /// Catalog pack manifest, integrity, or tile load failed.
    #[error("catalog pack: {0}")]
    CatalogPack(String),
}

mod handle;

pub use handle::Planetarium;

pub mod astrometry;
pub mod catalog;
pub mod animation;
pub mod bus;
pub mod gesture;
pub mod scene;
pub mod renderer;
pub mod surface;
pub mod types;
