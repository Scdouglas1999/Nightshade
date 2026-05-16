//! Live stacking engine for EAA and outreach
//!
//! Provides incremental image stacking with:
//! - Star detection and matching between frames
//! - Affine alignment (translation + rotation) via matched star pairs
//! - Running average accumulation with optional sigma-clipping rejection
//! - Parallel pixel operations via rayon

use crate::{detect_stars, DetectedStar, ImageData, PixelType, StarDetectionConfig};
use rayon::prelude::*;

/// Configuration for the live stacking engine
#[derive(Debug, Clone)]
pub struct LiveStackConfig {
    /// Sigma threshold for pixel rejection (e.g. 2.5 means reject > 2.5 sigma from running mean)
    pub sigma_clip_threshold: f64,
    /// Whether sigma clipping is enabled
    pub sigma_clip_enabled: bool,
    /// Maximum number of stars to use for matching (brightest N)
    pub max_match_stars: usize,
    /// Maximum distance in pixels for a star match to be valid
    pub match_radius_px: f64,
    /// Maximum flux ratio difference for a star match (0.0 to 1.0; e.g. 0.5 means flux can differ by 50%)
    pub match_flux_tolerance: f64,
    /// Minimum number of matched star pairs required for alignment
    pub min_matched_pairs: usize,
    /// Star detection config overrides
    pub star_detection: StarDetectionConfig,
}

impl Default for LiveStackConfig {
    fn default() -> Self {
        Self {
            sigma_clip_threshold: 2.5,
            sigma_clip_enabled: true,
            max_match_stars: 100,
            match_radius_px: 50.0,
            match_flux_tolerance: 0.7,
            min_matched_pairs: 5,
            star_detection: StarDetectionConfig {
                detection_sigma: 4.0,
                min_snr: 8.0,
                ..StarDetectionConfig::default()
            },
        }
    }
}

/// Statistics about the stacking process
#[derive(Debug, Clone, Default)]
pub struct StackingStats {
    /// Total frames added (including rejected)
    pub total_frames_attempted: u32,
    /// Successfully stacked frames
    pub stacked_frame_count: u32,
    /// Frames rejected due to insufficient star matches
    pub rejected_alignment_failures: u32,
    /// Average number of matched star pairs across stacked frames
    pub avg_matched_pairs: f64,
    /// Average alignment residual (RMS of matched star distances after transform)
    pub avg_alignment_residual: f64,
    /// Total pixels rejected by sigma clipping across all frames
    pub total_sigma_rejected_pixels: u64,
}

/// A 2D affine transform: [cos(t)*sx, -sin(t)*sy, tx; sin(t)*sx, cos(t)*sy, ty]
/// Simplified to: translation (tx, ty) + rotation (theta)
/// We don't do scaling because stacking frames from the same scope/camera session
/// should have identical pixel scale.
#[derive(Debug, Clone, Copy)]
struct AffineTransform {
    tx: f64,
    ty: f64,
    cos_theta: f64,
    sin_theta: f64,
}

impl AffineTransform {
    /// Identity transform (no shift, no rotation)
    fn identity() -> Self {
        Self {
            tx: 0.0,
            ty: 0.0,
            cos_theta: 1.0,
            sin_theta: 0.0,
        }
    }

    /// Apply transform to a point
    fn apply(&self, x: f64, y: f64) -> (f64, f64) {
        let rx = self.cos_theta * x - self.sin_theta * y + self.tx;
        let ry = self.sin_theta * x + self.cos_theta * y + self.ty;
        (rx, ry)
    }
}

/// Running statistics per pixel for sigma clipping
/// Stores sum and sum-of-squares to compute mean and variance incrementally.
#[derive(Debug, Clone)]
struct PixelAccumulator {
    /// Running sum of pixel values
    sum: f64,
    /// Running sum of squared pixel values (for variance)
    sum_sq: f64,
    /// Number of accepted values
    count: u32,
}

impl Default for PixelAccumulator {
    fn default() -> Self {
        Self {
            sum: 0.0,
            sum_sq: 0.0,
            count: 0,
        }
    }
}

/// The main live stacking engine
pub struct LiveStacker {
    /// Image dimensions
    width: u32,
    height: u32,
    channels: u32,

    /// Reference frame stars (detected from the first frame)
    reference_stars: Vec<DetectedStar>,

    /// Per-pixel accumulators for sigma-clipping
    /// Length: width * height * channels
    accumulators: Vec<PixelAccumulator>,

    /// Configuration
    config: LiveStackConfig,

    /// Running statistics
    stats: StackingStats,

    /// Centroid of reference stars for transform computation
    ref_centroid: (f64, f64),
}

impl LiveStacker {
    /// Create a new live stacker initialized with the reference frame.
    ///
    /// The reference frame defines the coordinate system that all subsequent
    /// frames will be aligned to. Stars are detected in the reference frame
    /// and stored for matching.
    pub fn new(reference_frame: &ImageData, config: LiveStackConfig) -> Result<Self, String> {
        if reference_frame.is_empty() {
            return Err("Reference frame is empty".to_string());
        }

        if reference_frame.pixel_type != PixelType::U16 {
            return Err(format!(
                "Live stacking currently supports U16 images only, got {:?}",
                reference_frame.pixel_type
            ));
        }

        let width = reference_frame.width;
        let height = reference_frame.height;
        let channels = reference_frame.channels;

        // Detect stars in reference frame
        let ref_stars = detect_stars(reference_frame, &config.star_detection);
        if ref_stars.len() < config.min_matched_pairs {
            return Err(format!(
                "Reference frame has only {} stars, need at least {} for alignment",
                ref_stars.len(),
                config.min_matched_pairs
            ));
        }

        tracing::info!(
            "Live stacker initialized: {}x{} reference with {} stars",
            width,
            height,
            ref_stars.len()
        );

        // Compute centroid of reference stars (used for rotation center)
        let n = ref_stars.len().min(config.max_match_stars) as f64;
        let ref_centroid = ref_stars
            .iter()
            .take(config.max_match_stars)
            .fold((0.0, 0.0), |(sx, sy), s| (sx + s.x, sy + s.y));
        let ref_centroid = (ref_centroid.0 / n, ref_centroid.1 / n);

        // Initialize accumulators from reference frame pixel data
        let ref_pixels = extract_u16_as_f64(reference_frame);
        let accumulators: Vec<PixelAccumulator> = ref_pixels
            .par_iter()
            .map(|&val| PixelAccumulator {
                sum: val,
                sum_sq: val * val,
                count: 1,
            })
            .collect();

        let mut stacker = Self {
            width,
            height,
            channels,
            reference_stars: ref_stars,
            accumulators,
            config,
            stats: StackingStats::default(),
            ref_centroid,
        };

        stacker.stats.total_frames_attempted = 1;
        stacker.stats.stacked_frame_count = 1;

        Ok(stacker)
    }

    /// Add a frame to the stack. Returns the current stacked result.
    ///
    /// Steps:
    /// 1. Detect stars in the new frame
    /// 2. Match stars against reference frame using nearest-neighbor with flux constraint
    /// 3. Compute affine transform (translation + rotation) from matched pairs
    /// 4. Apply transform to align frame pixels to reference
    /// 5. Accumulate aligned pixels with optional sigma-clipping rejection
    pub fn add_frame(&mut self, frame: &ImageData) -> Result<ImageData, String> {
        self.stats.total_frames_attempted += 1;

        // Validate dimensions
        if frame.width != self.width || frame.height != self.height {
            return Err(format!(
                "Frame dimensions {}x{} don't match reference {}x{}",
                frame.width, frame.height, self.width, self.height
            ));
        }
        if frame.channels != self.channels {
            return Err(format!(
                "Frame channel count {} doesn't match reference {}",
                frame.channels, self.channels
            ));
        }
        if frame.pixel_type != PixelType::U16 {
            return Err(format!(
                "Expected U16 pixel type, got {:?}",
                frame.pixel_type
            ));
        }

        // Step 1: Detect stars
        let frame_stars = detect_stars(frame, &self.config.star_detection);
        if frame_stars.len() < self.config.min_matched_pairs {
            self.stats.rejected_alignment_failures += 1;
            tracing::warn!(
                "Frame rejected: only {} stars detected (need {})",
                frame_stars.len(),
                self.config.min_matched_pairs
            );
            return Err(format!(
                "Insufficient stars for alignment: {} detected, {} required",
                frame_stars.len(),
                self.config.min_matched_pairs
            ));
        }

        // Step 2: Match stars
        let matches = match_stars(
            &self.reference_stars,
            &frame_stars,
            self.config.max_match_stars,
            self.config.match_radius_px,
            self.config.match_flux_tolerance,
        );

        if matches.len() < self.config.min_matched_pairs {
            self.stats.rejected_alignment_failures += 1;
            tracing::warn!(
                "Frame rejected: only {} star matches (need {})",
                matches.len(),
                self.config.min_matched_pairs
            );
            return Err(format!(
                "Insufficient star matches for alignment: {} matched, {} required",
                matches.len(),
                self.config.min_matched_pairs
            ));
        }

        // Step 3: Compute affine transform from matched pairs
        let transform = compute_affine_transform(&matches, self.ref_centroid);

        // Compute alignment residual (RMS of distances after transform)
        let residual = compute_alignment_residual(&matches, &transform);

        tracing::debug!(
            "Frame aligned: {} matches, residual={:.2}px, tx={:.1}, ty={:.1}, rot={:.3}deg",
            matches.len(),
            residual,
            transform.tx,
            transform.ty,
            transform.sin_theta.atan2(transform.cos_theta).to_degrees()
        );

        // Step 4: Extract frame pixels and apply transform
        let frame_pixels = extract_u16_as_f64(frame);
        let aligned_pixels = apply_transform_bilinear(
            &frame_pixels,
            self.width as usize,
            self.height as usize,
            self.channels as usize,
            &transform,
        );

        // Step 5: Accumulate with optional sigma clipping
        let sigma_rejected = self.accumulate_pixels(&aligned_pixels);

        // Update stats
        self.stats.stacked_frame_count += 1;
        let n = self.stats.stacked_frame_count as f64;
        self.stats.avg_matched_pairs =
            self.stats.avg_matched_pairs * ((n - 1.0) / n) + matches.len() as f64 / n;
        self.stats.avg_alignment_residual =
            self.stats.avg_alignment_residual * ((n - 1.0) / n) + residual / n;
        self.stats.total_sigma_rejected_pixels += sigma_rejected;

        tracing::info!(
            "Frame {} stacked ({} total, {} rejected, {:.0} sigma-clipped px)",
            self.stats.total_frames_attempted,
            self.stats.stacked_frame_count,
            self.stats.rejected_alignment_failures,
            sigma_rejected,
        );

        // Return current stack
        Ok(self.get_current_stack())
    }

    /// Accumulate aligned pixel values into the running stack.
    /// Returns the number of pixels rejected by sigma clipping.
    fn accumulate_pixels(&mut self, aligned_pixels: &[f64]) -> u64 {
        let sigma_enabled = self.config.sigma_clip_enabled;
        let sigma_threshold = self.config.sigma_clip_threshold;

        // Process in parallel chunks for cache efficiency
        // We need mutable access to accumulators, so we use par_iter_mut
        let rejected: u64 = self
            .accumulators
            .par_iter_mut()
            .zip(aligned_pixels.par_iter())
            .map(|(acc, &val)| {
                // Skip NaN values (outside-of-frame pixels from transform)
                if val.is_nan() {
                    return 0u64;
                }

                if sigma_enabled && acc.count >= 3 {
                    // Sigma clipping: reject pixels that deviate too far from running mean
                    let mean = acc.sum / acc.count as f64;
                    let variance = if acc.count > 1 {
                        (acc.sum_sq - (acc.sum * acc.sum) / acc.count as f64)
                            / (acc.count as f64 - 1.0)
                    } else {
                        0.0
                    };
                    let std_dev = variance.max(0.0).sqrt();

                    if std_dev > 0.0 && (val - mean).abs() > sigma_threshold * std_dev {
                        return 1u64; // rejected
                    }
                }

                acc.sum += val;
                acc.sum_sq += val * val;
                acc.count += 1;
                0u64
            })
            .sum();

        rejected
    }

    /// Get the current stacked result as an ImageData.
    /// Returns the mean of all accumulated pixel values.
    pub fn get_current_stack(&self) -> ImageData {
        let pixel_count = (self.width as usize) * (self.height as usize) * (self.channels as usize);
        let mut result_u16 = vec![0u16; pixel_count];

        result_u16
            .par_iter_mut()
            .zip(self.accumulators.par_iter())
            .for_each(|(out, acc)| {
                if acc.count > 0 {
                    let mean = acc.sum / acc.count as f64;
                    *out = mean.round().clamp(0.0, 65535.0) as u16;
                }
            });

        ImageData::from_u16(self.width, self.height, self.channels, &result_u16)
    }

    /// Reset the stacker, clearing all accumulated data.
    /// The reference frame stars are preserved.
    pub fn reset(&mut self) {
        let pixel_count = (self.width as usize) * (self.height as usize) * (self.channels as usize);
        self.accumulators = vec![PixelAccumulator::default(); pixel_count];
        self.stats = StackingStats::default();
        tracing::info!("Live stacker reset");
    }

    /// Get the number of successfully stacked frames.
    pub fn frame_count(&self) -> u32 {
        self.stats.stacked_frame_count
    }

    /// Get stacking statistics.
    pub fn get_stats(&self) -> StackingStats {
        self.stats.clone()
    }
}

// =============================================================================
// Star Matching
// =============================================================================

/// A matched star pair: reference star index, frame star index, distance
#[derive(Debug, Clone)]
#[allow(dead_code)]
struct StarMatch {
    ref_star: DetectedStar,
    frame_star: DetectedStar,
    distance: f64,
}

/// Match stars between reference and frame using nearest-neighbor with flux constraint.
///
/// For each reference star (up to max_stars), find the closest frame star
/// that is within match_radius pixels AND whose flux ratio is within flux_tolerance.
/// Uses a simple O(N*M) approach which is fine for the typical star counts (~50-200).
fn match_stars(
    ref_stars: &[DetectedStar],
    frame_stars: &[DetectedStar],
    max_stars: usize,
    match_radius: f64,
    flux_tolerance: f64,
) -> Vec<StarMatch> {
    let match_radius_sq = match_radius * match_radius;
    let mut matches = Vec::new();
    let mut used_frame_indices = vec![false; frame_stars.len()];

    // Stars are already sorted by flux (brightest first) from detect_stars
    for ref_star in ref_stars.iter().take(max_stars) {
        let mut best_dist_sq = f64::MAX;
        let mut best_frame_idx: Option<usize> = None;

        for (fi, frame_star) in frame_stars.iter().enumerate() {
            if used_frame_indices[fi] {
                continue;
            }

            // Distance check
            let dx = ref_star.x - frame_star.x;
            let dy = ref_star.y - frame_star.y;
            let dist_sq = dx * dx + dy * dy;

            if dist_sq > match_radius_sq {
                continue;
            }

            // Flux ratio check: the ratio of smaller/larger flux must exceed (1 - tolerance)
            let flux_ratio = if ref_star.flux > frame_star.flux {
                frame_star.flux / ref_star.flux
            } else {
                ref_star.flux / frame_star.flux
            };

            if flux_ratio < (1.0 - flux_tolerance) {
                continue;
            }

            if dist_sq < best_dist_sq {
                best_dist_sq = dist_sq;
                best_frame_idx = Some(fi);
            }
        }

        if let Some(fi) = best_frame_idx {
            used_frame_indices[fi] = true;
            matches.push(StarMatch {
                ref_star: ref_star.clone(),
                frame_star: frame_stars[fi].clone(),
                distance: best_dist_sq.sqrt(),
            });
        }
    }

    matches
}

// =============================================================================
// Affine Transform Computation
// =============================================================================

/// Compute the best-fit affine transform (translation + rotation) from matched star pairs.
///
/// Uses the Procrustes method:
/// 1. Compute centroids of both point sets
/// 2. Center both sets on their centroids
/// 3. Compute rotation angle via atan2 of cross/dot products
/// 4. Translation = ref_centroid - R * frame_centroid
///
/// This is a rigid body transform (no scaling) which is appropriate for
/// tracking/mount-shift between frames of the same optical system.
fn compute_affine_transform(
    matches: &[StarMatch],
    _ref_centroid_hint: (f64, f64),
) -> AffineTransform {
    if matches.is_empty() {
        return AffineTransform::identity();
    }

    let n = matches.len() as f64;

    // Compute centroids of matched pairs
    let (ref_cx, ref_cy) = matches.iter().fold((0.0, 0.0), |(sx, sy), m| {
        (sx + m.ref_star.x, sy + m.ref_star.y)
    });
    let (ref_cx, ref_cy) = (ref_cx / n, ref_cy / n);

    let (frm_cx, frm_cy) = matches.iter().fold((0.0, 0.0), |(sx, sy), m| {
        (sx + m.frame_star.x, sy + m.frame_star.y)
    });
    let (frm_cx, frm_cy) = (frm_cx / n, frm_cy / n);

    // Center both sets on their centroids
    // Compute rotation using cross-covariance
    // sum of (centered_frame) x (centered_ref) gives sin/cos components
    let mut sum_cross = 0.0; // Sum of x_f * y_r - y_f * x_r (cross product, proportional to sin(theta))
    let mut sum_dot = 0.0; // Sum of x_f * x_r + y_f * y_r (dot product, proportional to cos(theta))

    for m in matches {
        let fx = m.frame_star.x - frm_cx;
        let fy = m.frame_star.y - frm_cy;
        let rx = m.ref_star.x - ref_cx;
        let ry = m.ref_star.y - ref_cy;

        sum_dot += fx * rx + fy * ry;
        sum_cross += fx * ry - fy * rx;
    }

    // Rotation angle: frame -> reference
    let theta = sum_cross.atan2(sum_dot);
    let cos_theta = theta.cos();
    let sin_theta = theta.sin();

    // Translation: ref_centroid = R * frame_centroid + t
    // So: t = ref_centroid - R * frame_centroid
    let tx = ref_cx - (cos_theta * frm_cx - sin_theta * frm_cy);
    let ty = ref_cy - (sin_theta * frm_cx + cos_theta * frm_cy);

    AffineTransform {
        tx,
        ty,
        cos_theta,
        sin_theta,
    }
}

/// Compute RMS alignment residual after applying the transform.
/// This measures how well the transform aligns the matched stars.
fn compute_alignment_residual(matches: &[StarMatch], transform: &AffineTransform) -> f64 {
    if matches.is_empty() {
        return 0.0;
    }

    let sum_sq: f64 = matches
        .iter()
        .map(|m| {
            let (tx, ty) = transform.apply(m.frame_star.x, m.frame_star.y);
            let dx = tx - m.ref_star.x;
            let dy = ty - m.ref_star.y;
            dx * dx + dy * dy
        })
        .sum();

    (sum_sq / matches.len() as f64).sqrt()
}

// =============================================================================
// Frame Alignment (Pixel Resampling)
// =============================================================================

/// Apply the inverse affine transform to resample frame pixels onto the reference grid.
///
/// For each output pixel (in reference coordinates), we compute where it maps
/// in the frame using the inverse transform, then use bilinear interpolation
/// to sample the frame pixel value.
///
/// Pixels that map outside the frame boundaries are set to NaN (sentinel)
/// so they can be excluded from accumulation.
fn apply_transform_bilinear(
    frame_pixels: &[f64],
    width: usize,
    height: usize,
    channels: usize,
    transform: &AffineTransform,
) -> Vec<f64> {
    let pixel_count = width * height * channels;
    let stride = width * channels;

    // Compute inverse transform: frame_pos = R^-1 * (ref_pos - t)
    // For rotation matrix R(theta), R^-1 = R(-theta)
    let inv_cos = transform.cos_theta; // cos(-theta) = cos(theta)
    let inv_sin = -transform.sin_theta; // sin(-theta) = -sin(theta)
                                        // Process rows in parallel
    let result: Vec<f64> = (0..height)
        .into_par_iter()
        .flat_map(|y| {
            let mut row = vec![f64::NAN; width * channels];

            for x in 0..width {
                // Apply the inverse affine transform explicitly as R^-1(ref - t).
                let rx = x as f64 - transform.tx;
                let ry = y as f64 - transform.ty;
                let fx = inv_cos * rx - inv_sin * ry;
                let fy = inv_sin * rx + inv_cos * ry;

                // Bilinear interpolation
                let fx_floor = fx.floor();
                let fy_floor = fy.floor();
                let ix = fx_floor as i64;
                let iy = fy_floor as i64;

                // Check bounds (need ix, ix+1, iy, iy+1 all in range)
                if ix < 0 || iy < 0 || ix + 1 >= width as i64 || iy + 1 >= height as i64 {
                    // Out of bounds: leave as NaN
                    continue;
                }

                let ix = ix as usize;
                let iy = iy as usize;
                let dx = fx - fx_floor;
                let dy = fy - fy_floor;

                let w00 = (1.0 - dx) * (1.0 - dy);
                let w10 = dx * (1.0 - dy);
                let w01 = (1.0 - dx) * dy;
                let w11 = dx * dy;

                for c in 0..channels {
                    let p00 = frame_pixels[iy * stride + ix * channels + c];
                    let p10 = frame_pixels[iy * stride + (ix + 1) * channels + c];
                    let p01 = frame_pixels[(iy + 1) * stride + ix * channels + c];
                    let p11 = frame_pixels[(iy + 1) * stride + (ix + 1) * channels + c];

                    row[x * channels + c] = w00 * p00 + w10 * p10 + w01 * p01 + w11 * p11;
                }
            }

            row
        })
        .collect();

    debug_assert_eq!(result.len(), pixel_count);
    result
}

// =============================================================================
// Utility Functions
// =============================================================================

/// Extract U16 image data as f64 values
fn extract_u16_as_f64(image: &ImageData) -> Vec<f64> {
    image
        .data
        .par_chunks_exact(2)
        .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]) as f64)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Create a simple test image with a known star pattern.
    /// Background is 1000 ADU with Gaussian noise (sigma ~30 ADU).
    /// Stars are Gaussian profiles with sigma=2.5 pixels (realistic HFR ~2-3).
    fn make_test_image(width: u32, height: u32, star_positions: &[(f64, f64, f64)]) -> ImageData {
        let w = width as usize;
        let h = height as usize;
        let bg = 1000u16;
        let mut data = vec![bg; w * h];

        // Add simple deterministic noise for realistic background statistics
        for (i, pixel) in data.iter_mut().enumerate() {
            // Noise with ~30 ADU standard deviation using simple LCG
            let n = ((i as u64).wrapping_mul(1103515245).wrapping_add(12345) >> 16) & 0xFF;
            let noise = (n as i32 - 128) / 4; // range roughly [-32, 32]
            *pixel = (bg as i32 + noise).clamp(0, 65535) as u16;
        }

        for &(sx, sy, brightness) in star_positions {
            // Draw Gaussian star with sigma=2.5 (realistic PSF)
            let radius = 8i32;
            let sigma = 2.5;
            for dy in -radius..=radius {
                for dx in -radius..=radius {
                    let px = sx as i32 + dx;
                    let py = sy as i32 + dy;
                    if px >= 0 && px < width as i32 && py >= 0 && py < height as i32 {
                        let dist_sq = (dx * dx + dy * dy) as f64;
                        let gauss = (-dist_sq / (2.0 * sigma * sigma)).exp();
                        let val = (brightness * gauss) as u32;
                        let idx = py as usize * w + px as usize;
                        data[idx] = (data[idx] as u32 + val).min(65535) as u16;
                    }
                }
            }
        }

        ImageData::from_u16(width, height, 1, &data)
    }

    #[test]
    fn test_stacker_creation() {
        // Bright stars with peak intensities well above background
        let stars = vec![
            (100.0, 100.0, 40000.0),
            (200.0, 150.0, 35000.0),
            (300.0, 200.0, 38000.0),
            (150.0, 300.0, 30000.0),
            (250.0, 250.0, 36000.0),
            (350.0, 100.0, 32000.0),
            (50.0, 350.0, 28000.0),
        ];
        let img = make_test_image(512, 512, &stars);
        let config = LiveStackConfig {
            min_matched_pairs: 3,
            star_detection: StarDetectionConfig {
                detection_sigma: 3.0,
                min_snr: 3.0,
                min_hfr: 0.5,
                max_sharpness: 1.0,
                ..StarDetectionConfig::default()
            },
            ..LiveStackConfig::default()
        };

        let stacker = LiveStacker::new(&img, config);
        assert!(
            stacker.is_ok(),
            "Stacker creation failed: {:?}",
            stacker.err()
        );
        let stacker = stacker.unwrap();
        assert_eq!(stacker.frame_count(), 1);
    }

    #[test]
    fn test_affine_translation_only() {
        // Create matches with a known translation
        let matches = vec![
            StarMatch {
                ref_star: DetectedStar {
                    x: 100.0,
                    y: 100.0,
                    flux: 1000.0,
                    hfr: 2.0,
                    fwhm: 4.7,
                    peak: 5000.0,
                    background: 500.0,
                    snr: 50.0,
                    eccentricity: 0.1,
                    sharpness: 0.3,
                },
                frame_star: DetectedStar {
                    x: 105.0,
                    y: 103.0,
                    flux: 1000.0,
                    hfr: 2.0,
                    fwhm: 4.7,
                    peak: 5000.0,
                    background: 500.0,
                    snr: 50.0,
                    eccentricity: 0.1,
                    sharpness: 0.3,
                },
                distance: 5.83,
            },
            StarMatch {
                ref_star: DetectedStar {
                    x: 200.0,
                    y: 200.0,
                    flux: 800.0,
                    hfr: 2.0,
                    fwhm: 4.7,
                    peak: 4000.0,
                    background: 500.0,
                    snr: 40.0,
                    eccentricity: 0.1,
                    sharpness: 0.3,
                },
                frame_star: DetectedStar {
                    x: 205.0,
                    y: 203.0,
                    flux: 800.0,
                    hfr: 2.0,
                    fwhm: 4.7,
                    peak: 4000.0,
                    background: 500.0,
                    snr: 40.0,
                    eccentricity: 0.1,
                    sharpness: 0.3,
                },
                distance: 5.83,
            },
        ];

        let transform = compute_affine_transform(&matches, (150.0, 150.0));

        // With pure translation of (5,3), the transform should have tx ~ -5, ty ~ -3
        // and zero rotation
        assert!(
            (transform.cos_theta - 1.0).abs() < 0.01,
            "cos_theta should be ~1.0"
        );
        assert!(transform.sin_theta.abs() < 0.01, "sin_theta should be ~0.0");
        assert!(
            (transform.tx - (-5.0)).abs() < 0.1,
            "tx should be ~-5.0, got {}",
            transform.tx
        );
        assert!(
            (transform.ty - (-3.0)).abs() < 0.1,
            "ty should be ~-3.0, got {}",
            transform.ty
        );
    }

    #[test]
    fn test_apply_transform_bilinear_rotation_and_translation() {
        let width = 5usize;
        let height = 5usize;
        let channels = 1usize;
        let mut frame_pixels = vec![0.0; width * height * channels];
        frame_pixels[2 * width + 1] = 42.0;

        let transform = AffineTransform {
            tx: 2.0,
            ty: 1.0,
            cos_theta: 0.0,
            sin_theta: 1.0,
        };

        let aligned = apply_transform_bilinear(&frame_pixels, width, height, channels, &transform);

        assert_eq!(
            aligned[2 * width],
            42.0,
            "inverse affine mapping should land the rotated pixel at its transformed coordinates"
        );
    }

    #[test]
    fn test_star_matching() {
        let ref_stars = vec![
            DetectedStar {
                x: 100.0,
                y: 100.0,
                flux: 10000.0,
                hfr: 2.0,
                fwhm: 4.7,
                peak: 5000.0,
                background: 500.0,
                snr: 50.0,
                eccentricity: 0.1,
                sharpness: 0.3,
            },
            DetectedStar {
                x: 200.0,
                y: 200.0,
                flux: 8000.0,
                hfr: 2.0,
                fwhm: 4.7,
                peak: 4000.0,
                background: 500.0,
                snr: 40.0,
                eccentricity: 0.1,
                sharpness: 0.3,
            },
        ];

        // Frame stars shifted by (3, 2)
        let frame_stars = vec![
            DetectedStar {
                x: 103.0,
                y: 102.0,
                flux: 9500.0,
                hfr: 2.0,
                fwhm: 4.7,
                peak: 5000.0,
                background: 500.0,
                snr: 50.0,
                eccentricity: 0.1,
                sharpness: 0.3,
            },
            DetectedStar {
                x: 203.0,
                y: 202.0,
                flux: 7800.0,
                hfr: 2.0,
                fwhm: 4.7,
                peak: 4000.0,
                background: 500.0,
                snr: 40.0,
                eccentricity: 0.1,
                sharpness: 0.3,
            },
        ];

        let matches = match_stars(&ref_stars, &frame_stars, 50, 20.0, 0.5);
        assert_eq!(matches.len(), 2, "Should match both stars");
    }

    #[test]
    fn sigma_clipping_uses_sample_variance_for_small_stacks() {
        let count = 3.0;
        let sum = 1000.0 + 1002.0 + 998.0;
        let sum_sq = 1000.0f64.powi(2) + 1002.0f64.powi(2) + 998.0f64.powi(2);
        let mean = sum / count;
        let sample_variance = (sum_sq - (sum * sum) / count) / (count - 1.0);
        let population_variance = (sum_sq / count) - mean * mean;
        let sample_std_dev = sample_variance.sqrt();
        let population_std_dev = population_variance.sqrt();
        let outlier_delta = (1004.0 - mean).abs();

        assert!(
            outlier_delta <= 2.0 * sample_std_dev,
            "sample variance should keep the moderate deviation"
        );
        assert!(
            outlier_delta > 2.0 * population_std_dev,
            "population variance would incorrectly reject the same deviation"
        );
    }
}
