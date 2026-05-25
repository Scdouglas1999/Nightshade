//! Visual-grade astrometry (time, frames, precession, refraction, extinction, SGP4).
//!
//! See `docs/plans/2026-05-25-planetarium-v2-design.md` §7.

pub mod aberration;
pub mod body_lighting;
pub mod earth_rotation;
pub mod extinction;
pub mod frames;
pub mod kepler;
pub mod moon;
pub mod nutation;
pub mod precession;
pub mod refraction;
pub mod sgp4_prop;
pub mod time;
pub mod vsop87;
