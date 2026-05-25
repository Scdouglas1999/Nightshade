//! HEALPix helpers (NESTED scheme) wrapping [`cdshealpix`].
//!
//! Tile packs store [`super::tile::TileHeader::healpix_id`] at a given [`nside`](super::tile::TileHeader::nside);
//! these functions map sky directions and view cones to the same pixel indices.

use cdshealpix::{self, nested};
use cdshealpix::NSIDE_MAX;

use crate::types::{SkyProjection, ViewPose};

/// HEALPix query error.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
pub enum HealpixError {
    /// `nside` must be a power of two in `[1, NSIDE_MAX]`.
    #[error("nside must be a power of 2 in [1, {NSIDE_MAX}], got {0}")]
    InvalidNside(u32),
    /// Cone radius must be finite and non-negative.
    #[error("cone radius must be finite and non-negative, got {0}")]
    InvalidRadius(f64),
    /// Right ascension or declination was non-finite.
    #[error("ra/dec must be finite (ra={0}, dec={1})")]
    InvalidDirection(f64, f64),
    /// Field of view must be finite and positive.
    #[error("fov_rad must be finite and positive, got {0}")]
    InvalidFov(f32),
}

/// NESTED HEALPix pixel index for an ICRS direction at resolution `nside`.
///
/// `ra_rad` and `dec_rad` are J2000 right ascension and declination in radians
/// (same convention as [`cdshealpix::nested::hash`] longitude/latitude).
#[must_use]
pub fn pixel_for_direction(ra_rad: f64, dec_rad: f64, nside: u32) -> Result<u64, HealpixError> {
    validate_direction(ra_rad, dec_rad)?;
    let depth = depth_for_nside(nside)?;
    Ok(nested::hash(depth, ra_rad, dec_rad))
}

/// All NESTED pixels whose centers fall inside a spherical cone.
///
/// Uses [`cdshealpix::nested::cone_coverage_centers`] (exact w.r.t. cell centers).
/// Returns pixel hashes sorted in natural nested order.
pub fn pixels_in_cone(
    center_ra_rad: f64,
    center_dec_rad: f64,
    radius_rad: f64,
    nside: u32,
) -> Result<Vec<u64>, HealpixError> {
    validate_direction(center_ra_rad, center_dec_rad)?;
    validate_radius(radius_rad)?;
    let depth = depth_for_nside(nside)?;
    let bmoc = nested::cone_coverage_centers(depth, center_ra_rad, center_dec_rad, radius_rad);
    Ok(bmoc.into_flat_iter().collect())
}

/// Pixels overlapping the visible field of view for a [`ViewPose`].
///
/// `fov_rad` is the field of view across the shorter screen axis (radians), matching
/// [`ViewPose::fov_rad`]. The bounding cap uses the same projection edge math as
/// [`crate::scene::projection::project_icrs`], inflated for screen corners and one
/// HEALPix cell margin.
pub fn bounding_pixels_for_fov(
    pose: ViewPose,
    fov_rad: f32,
    nside: u32,
) -> Result<Vec<u64>, HealpixError> {
    validate_direction(pose.ra_rad, pose.dec_rad)?;
    validate_fov(fov_rad)?;
    let depth = depth_for_nside(nside)?;
    let radius = fov_cap_radius_rad(&pose, fov_rad)
        + cdshealpix::largest_center_to_vertex_distance(depth, pose.ra_rad, pose.dec_rad);
    pixels_in_cone(pose.ra_rad, pose.dec_rad, radius, nside)
}

/// Map `nside` to HEALPix depth (`log2(nside)`).
#[inline]
pub fn depth_for_nside(nside: u32) -> Result<u8, HealpixError> {
    if cdshealpix::is_nside(nside) {
        Ok(cdshealpix::depth(nside))
    } else {
        Err(HealpixError::InvalidNside(nside))
    }
}

/// Angular radius (radians) of the sphere cap enclosing the projected viewport.
#[must_use]
pub fn fov_cap_radius_rad(pose: &ViewPose, fov_rad: f32) -> f64 {
    let half_fov = f64::from(fov_rad) * 0.5;
    let edge_r = match pose.projection {
        SkyProjection::Stereographic => 2.0 * (half_fov * 0.5).tan(),
        SkyProjection::Orthographic => half_fov.sin(),
        SkyProjection::AzimuthalEquidistant => half_fov,
    };
    let corner_r = edge_r * std::f64::consts::SQRT_2;
    match pose.projection {
        SkyProjection::Stereographic => 2.0 * (corner_r * 0.5).atan(),
        SkyProjection::Orthographic => corner_r.asin().min(std::f64::consts::FRAC_PI_2),
        SkyProjection::AzimuthalEquidistant => corner_r.min(std::f64::consts::PI),
    }
}

#[inline]
fn validate_direction(ra_rad: f64, dec_rad: f64) -> Result<(), HealpixError> {
    if ra_rad.is_finite() && dec_rad.is_finite() {
        Ok(())
    } else {
        Err(HealpixError::InvalidDirection(ra_rad, dec_rad))
    }
}

#[inline]
fn validate_radius(radius_rad: f64) -> Result<(), HealpixError> {
    if radius_rad.is_finite() && radius_rad >= 0.0 {
        Ok(())
    } else {
        Err(HealpixError::InvalidRadius(radius_rad))
    }
}

#[inline]
fn validate_fov(fov_rad: f32) -> Result<(), HealpixError> {
    if fov_rad.is_finite() && fov_rad > 0.0 {
        Ok(())
    } else {
        Err(HealpixError::InvalidFov(fov_rad))
    }
}
