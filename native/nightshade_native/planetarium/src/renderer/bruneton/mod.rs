//! Bruneton 2020 precomputed atmospheric scattering LUTs.
//!
//! Port of Eric Bruneton's public implementation (`ebruneton/precomputed_atmospheric_scattering`).

pub mod constants;
pub mod luts;
pub mod params;
pub mod precompute;
pub mod sample;

pub use constants::*;
pub use luts::{readback_texture_2d_rgba_f32, BrunetonLuts, BrunetonPrecomputeError};
pub use params::{luminance_from_radiance_identity, PrecomputeConfig};
pub use precompute::precompute_bruneton_luts;
pub use sample::{sample_transmittance_rgba, transmittance_uv_from_r_mu};
