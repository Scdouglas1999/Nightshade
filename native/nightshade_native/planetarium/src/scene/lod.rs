//! Magnitude / zoom LOD selection for HEALPix star tiles.
//!
//! Frame-level limits mirror v1 [`dynamicMagnitudeLimitsProvider`](https://github.com/nightshade):
//! base cap from quality tier plus a logarithmic boost as FOV narrows. Per-tile limits
//! optionally soften at the frustum edge; [`select_lod`] maps a limit onto a tile's
//! [`LodEntry`](crate::catalog::tile::LodEntry) table.

use crate::catalog::hyg_build::HYG_MAG_LIMIT;
use crate::catalog::LodEntry;

/// Reference wide-field FOV (degrees) used for zoom scaling (v1 default 120°).
pub const REF_FOV_DEG: f32 = 120.0;
/// Maximum magnitude boost from zoom alone (v1 caps at 7.0).
pub const FOV_MAG_BOOST_CAP: f32 = 7.0;
/// Faintest stars drawn at any zoom (catalog floor).
pub const STAR_MAG_FLOOR: f32 = 2.0;
/// Default ceiling before catalog-specific clamping (v1 star clamp 12.0).
pub const STAR_MAG_CEILING: f32 = 12.0;

/// Quality tier magnitude caps (`RenderConfig::quality`: 0=low, 1=medium, 2=high).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct QualityConfig {
    /// Tier index (0=low, 1=medium, 2=high).
    pub tier: u32,
    /// Base star magnitude limit for this tier before zoom boost.
    pub base_star_magnitude_limit: f32,
}

impl QualityConfig {
    /// Map a render-quality tier to the v1-equivalent base star limit.
    #[must_use]
    pub fn from_tier(tier: u32) -> Self {
        let base = match tier {
            0 => 6.0,
            1 => 8.0,
            _ => 10.0,
        };
        Self {
            tier,
            base_star_magnitude_limit: base,
        }
    }
}

/// User-adjustable magnitude limit (maps from `RenderConfig::magnitude_limit`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MagLimitConfig {
    /// User star magnitude limit.
    pub star_magnitude_limit: f32,
}

impl MagLimitConfig {
    /// Wrap a user magnitude limit.
    #[must_use]
    pub const fn new(star_magnitude_limit: f32) -> Self {
        Self {
            star_magnitude_limit,
        }
    }
}

/// Result of mapping a magnitude limit onto a tile's LOD table.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LodSelection {
    /// Magnitude limit applied for this tile.
    pub mag_limit: f32,
    /// Highest included LOD band index (inclusive), or `None` when no band qualifies.
    pub lod_level_index: Option<u32>,
    /// Number of stars to draw (sum of included band counts).
    pub draw_count: u32,
}

/// Logarithmic FOV zoom factor: ~+2 mag per halving of FOV (v1 formula).
#[must_use]
pub fn fov_zoom_mag_boost(fov_rad: f32) -> f32 {
    if !fov_rad.is_finite() || fov_rad <= 0.0 {
        return 0.0;
    }
    let fov_deg = fov_rad.to_degrees().clamp(1.0, REF_FOV_DEG);
    let factor = 2.0 * (REF_FOV_DEG / fov_deg).log2();
    factor.clamp(0.0, FOV_MAG_BOOST_CAP)
}

/// Frame-level star magnitude limit from zoom, quality tier, and user cap.
#[must_use]
pub fn frame_star_mag_limit(
    fov_rad: f32,
    quality: QualityConfig,
    mag_limit: MagLimitConfig,
) -> f32 {
    let boosted = quality.base_star_magnitude_limit + fov_zoom_mag_boost(fov_rad);
    let ceiling = STAR_MAG_CEILING
        .min(HYG_MAG_LIMIT)
        .min(mag_limit.star_magnitude_limit);
    boosted.clamp(STAR_MAG_FLOOR, ceiling)
}

/// Per-tile magnitude limit given frame limit and angular distance from boresight.
///
/// `tile_angular_distance_rad` is the separation between the tile center and view
/// boresight; `cap_radius_rad` is the frustum cap radius (see
/// [`super::visibility::frustum_cap_radius_rad`]).
#[must_use]
pub fn tile_star_mag_limit(
    fov_rad: f32,
    quality: QualityConfig,
    mag_limit: MagLimitConfig,
    tile_angular_distance_rad: f64,
    cap_radius_rad: f64,
) -> f32 {
    let frame = frame_star_mag_limit(fov_rad, quality, mag_limit);
    if !cap_radius_rad.is_finite() || cap_radius_rad <= 0.0 {
        return frame;
    }
    let t = (tile_angular_distance_rad / cap_radius_rad).clamp(0.0, 1.0) as f32;
    // Quadratic falloff: up to 1 mag fainter at the cap edge (perf guard for peripheral tiles).
    let edge_penalty = t * t;
    (frame - edge_penalty).max(STAR_MAG_FLOOR)
}

/// Select LOD bands and draw count for `mag_limit` on a sorted ascending-threshold table.
#[must_use]
pub fn select_lod(lod_entries: &[LodEntry], mag_limit: f32) -> LodSelection {
    let mut draw_count = 0u32;
    let mut last_index = None;

    for (index, entry) in lod_entries.iter().enumerate() {
        if entry.mag_threshold <= mag_limit {
            draw_count = draw_count.saturating_add(entry.count);
            last_index = Some(index as u32);
        } else {
            break;
        }
    }

    LodSelection {
        mag_limit,
        lod_level_index: last_index,
        draw_count,
    }
}
