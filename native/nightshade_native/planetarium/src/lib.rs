//! Nightshade Planetarium v2 — Rust+wgpu renderer.
//!
//! See docs/plans/2026-05-25-planetarium-v2-design.md for the full architecture.

#![deny(unsafe_op_in_unsafe_fn)]
#![warn(missing_docs)]

/// Crate-wide error type. Per CLAUDE.md, fail loud — no silent fallbacks.
#[derive(Debug, thiserror::Error)]
pub enum PlanetariumError {
    /// A platform surface could not be created for the current platform.
    #[error("platform surface unsupported: {0}")]
    UnsupportedPlatform(&'static str),
}

pub mod bus;
pub mod surface;
pub mod spike;
pub mod types;
