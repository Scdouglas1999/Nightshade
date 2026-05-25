//! View-frustum cull: HEALPix tiles intersecting the visible sky cap.
//!
//! The frustum is modeled as a spherical cap on the celestial sphere (boresight +
//! projection-aware angular radius). Tile ids use the NESTED scheme at `nside`,
//! matching on-disk catalog tiles.

use crate::catalog::healpix::{bounding_pixels_for_fov, fov_cap_radius_rad, HealpixError};
use crate::types::ViewPose;

/// NESTED HEALPix tile id (opaque `u64`, same as [`crate::catalog::residency::HealpixId`]).
pub type HealpixTileId = u64;

/// HEALPix tiles whose cells intersect the view frustum for `pose`.
///
/// `fov_rad` is the field of view across the shorter screen axis (radians). It may
/// differ from [`ViewPose::fov_rad`] when building a prefetch ring (see
/// [`crate::catalog::residency::TileResidency::sync_visibility`]).
///
/// Returns tile ids sorted in natural nested order. The cap radius includes projection
/// corner inflation and one HEALPix cell margin (see [`fov_cap_radius_rad`]).
pub fn visible_tiles(
    pose: ViewPose,
    fov_rad: f32,
    nside: u32,
) -> Result<Vec<HealpixTileId>, HealpixError> {
    bounding_pixels_for_fov(pose, fov_rad, nside)
}

/// Angular radius (radians) of the sphere cap enclosing the projected viewport.
#[inline]
#[must_use]
pub fn frustum_cap_radius_rad(pose: &ViewPose, fov_rad: f32) -> f64 {
    fov_cap_radius_rad(pose, fov_rad)
}
