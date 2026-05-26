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
        // Why (audit IMG-P2-3): `avg_matched_pairs` and
        // `avg_alignment_residual` are *per-aligned-frame* metrics. The
        // reference frame contributes neither — it is not matched against
        // itself and has zero residual by construction. Dividing by
        // `stacked_frame_count` (which includes the reference) diluted
        // both averages by `(N-1)/N`. We instead average over the count
        // of non-reference frames actually contributing samples.
        //
        // `.saturating_sub(1)` removes the reference's slot;
        // `.max(1)` prevents the impossible-but-cheap divide-by-zero on
        // the very first added frame (where the count just incremented
        // from 1→2, so the contributing count is 1).
        let aligned_count = self.stats.stacked_frame_count.saturating_sub(1).max(1) as f64;
        self.stats.avg_matched_pairs = self.stats.avg_matched_pairs
            * ((aligned_count - 1.0) / aligned_count)
            + matches.len() as f64 / aligned_count;
        self.stats.avg_alignment_residual = self.stats.avg_alignment_residual
            * ((aligned_count - 1.0) / aligned_count)
            + residual / aligned_count;
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

// =============================================================================
// Master Frame Combination (bias / dark / flat)
// =============================================================================
//
// Why this lives next to LiveStacker: both consume a population of frames and
// produce a single combined frame using rejection statistics. LiveStacker is
// the *online* path (one ref + incoming aligned lights); the routines below
// are the *offline* path (a static stack of calibration frames combined in a
// single pass). Sharing the file keeps the pixel-array math in one place.

/// What kind of master frame we are building.
///
/// The kind controls the post-combine behaviour:
/// - `Bias` and `Dark`: take the combined value as-is (no normalisation).
/// - `Flat`: normalise so the *mean* of the master equals 1.0 for `F32`
///   output or `32768` for `U16` output. Normalising is required because
///   the light/flat division step assumes the flat has unit mean; an
///   un-normalised flat would otherwise rescale the light frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MasterFrameKind {
    Bias,
    Dark,
    Flat,
}

impl MasterFrameKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            MasterFrameKind::Bias => "BIAS",
            MasterFrameKind::Dark => "DARK",
            MasterFrameKind::Flat => "FLAT",
        }
    }
}

/// How to combine the input frames pixel-by-pixel.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CombineMethod {
    /// Arithmetic mean of all input values. Lowest noise, but a single
    /// transient (cosmic ray, satellite trail, hot pixel pop) propagates
    /// into the master.
    Mean,
    /// Per-pixel median. Robust to single-frame outliers; the default for
    /// bias and dark masters and the recommended fallback for flats when
    /// the user can't afford the cost of sigma clipping.
    Median,
    /// Iterative sigma clipping. For each pixel, compute mean & stddev,
    /// reject samples outside `kappa * sigma`, repeat for `iterations`,
    /// take the final mean. Preferred for >10 frames; rejects single-frame
    /// transients without the full bias of the median.
    SigmaClip { kappa: f64, iterations: u32 },
}

impl CombineMethod {
    pub fn as_str(&self) -> String {
        match self {
            CombineMethod::Mean => "MEAN".to_string(),
            CombineMethod::Median => "MEDIAN".to_string(),
            CombineMethod::SigmaClip { kappa, iterations } => {
                format!("SIGMA_CLIP({:.2}, {})", kappa, iterations)
            }
        }
    }
}

/// Pixel type preference for the produced master frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MasterOutputType {
    /// 16-bit unsigned integer (legacy calibration pipelines). For flats,
    /// mean is rescaled to 32768 ADU (half-scale) so division still uses
    /// the existing u16 divide path.
    U16,
    /// 32-bit float. Preferred for flats (no quantisation loss when
    /// normalised to mean 1.0) and for sigma-clipped masters.
    F32,
}

/// A combined master calibration frame plus the metadata describing how
/// it was built. Stored so downstream calibration knows which combine
/// method was used and how many frames contributed.
#[derive(Debug, Clone)]
pub struct MasterFrame {
    /// The combined pixel data.
    pub image: ImageData,
    /// What kind of master this represents.
    pub kind: MasterFrameKind,
    /// How many input frames contributed to the combine.
    pub frame_count: u32,
    /// Which combine method produced the master.
    pub method: CombineMethod,
    /// The final output pixel type. Mirrors `image.pixel_type` for
    /// quick inspection without unpacking `image`.
    pub output_type: MasterOutputType,
    /// Mean pixel value of the combined master. For flats this is the
    /// pre-normalisation mean; useful for diagnostics and FITS metadata.
    pub input_mean: f64,
    /// Mean pixel value AFTER normalisation (only meaningful for flats;
    /// equals `input_mean` for bias/dark since they are not normalised).
    pub output_mean: f64,
}

/// Combine a stack of calibration frames into a single master frame.
///
/// Validation: returns `Err` for an empty input, mismatched dimensions /
/// channel counts, or any unsupported pixel type. We deliberately *do not*
/// fall back silently — a calibration master built from heterogeneous
/// frames would silently corrupt every science frame it touches downstream.
///
/// Output pixel type:
/// - `MasterOutputType::U16`: values are clamped to `[0, 65535]` and rounded.
///   For flats this means the *normalised* master has a target mean of 32768
///   (half-scale) so existing u16 calibration code paths still divide
///   correctly.
/// - `MasterOutputType::F32`: values stored without quantisation. For flats
///   the normalised master has a target mean of 1.0.
pub fn combine_master_frames(
    frames: &[ImageData],
    kind: MasterFrameKind,
    method: CombineMethod,
    output_type: MasterOutputType,
) -> Result<MasterFrame, String> {
    // --- validation --------------------------------------------------------
    if frames.is_empty() {
        return Err(format!(
            "combine_master_frames: cannot build {} master from zero frames",
            kind.as_str()
        ));
    }

    let first = &frames[0];
    if first.is_empty() {
        return Err("combine_master_frames: first frame is empty".to_string());
    }

    let width = first.width;
    let height = first.height;
    let channels = first.channels;
    let pixel_type = first.pixel_type;

    if !matches!(pixel_type, PixelType::U16 | PixelType::F32) {
        return Err(format!(
            "combine_master_frames: unsupported input pixel type {:?}; only U16 and F32 are accepted",
            pixel_type
        ));
    }

    for (i, frame) in frames.iter().enumerate() {
        if frame.is_empty() {
            return Err(format!("combine_master_frames: frame {} is empty", i));
        }
        if frame.width != width || frame.height != height {
            return Err(format!(
                "combine_master_frames: frame {} dimensions {}x{} don't match first frame {}x{}",
                i, frame.width, frame.height, width, height
            ));
        }
        if frame.channels != channels {
            return Err(format!(
                "combine_master_frames: frame {} channel count {} doesn't match first frame {}",
                i, frame.channels, channels
            ));
        }
        if frame.pixel_type != pixel_type {
            return Err(format!(
                "combine_master_frames: frame {} pixel type {:?} doesn't match first frame {:?}",
                i, frame.pixel_type, pixel_type
            ));
        }
    }

    if let CombineMethod::SigmaClip { kappa, iterations } = method {
        if !(kappa.is_finite() && kappa > 0.0) {
            return Err(format!(
                "combine_master_frames: invalid sigma-clip kappa {} (must be > 0 and finite)",
                kappa
            ));
        }
        if iterations == 0 {
            return Err(
                "combine_master_frames: sigma-clip iterations must be >= 1".to_string()
            );
        }
    }

    let pixel_count = (width as usize) * (height as usize) * (channels as usize);

    // --- extract pixel data as f64 stacks ----------------------------------
    // We materialise each frame as a Vec<f64> so the per-pixel combine can
    // see across frames. This costs `frames.len() * pixel_count * 8` bytes,
    // which is the same memory the Dart isolate path already pays.
    let frame_stacks: Vec<Vec<f64>> = frames
        .iter()
        .map(|f| match f.pixel_type {
            PixelType::U16 => extract_u16_as_f64(f),
            PixelType::F32 => f
                .data
                .par_chunks_exact(4)
                .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]) as f64)
                .collect(),
            _ => unreachable!("pixel_type validated above"),
        })
        .collect();

    // --- per-pixel combine -------------------------------------------------
    let combined: Vec<f64> = (0..pixel_count)
        .into_par_iter()
        .map(|i| {
            // Gather this pixel across all frames.
            // Small Vec; allocation per pixel is the cost of the offline path.
            let mut samples: Vec<f64> = frame_stacks.iter().map(|s| s[i]).collect();
            combine_pixel(&mut samples, method)
        })
        .collect();

    // --- compute mean BEFORE normalisation --------------------------------
    let input_sum: f64 = combined.par_iter().sum();
    let input_mean = input_sum / combined.len() as f64;

    // --- normalise flats only ---------------------------------------------
    let (final_pixels, output_mean) = match kind {
        MasterFrameKind::Flat => {
            if !input_mean.is_finite() || input_mean <= 0.0 {
                return Err(format!(
                    "combine_master_frames: cannot normalise flat — pre-normalisation mean is {} (must be > 0)",
                    input_mean
                ));
            }
            // For F32 output we target a normalised mean of 1.0.
            // For U16 output we target 32768 so the existing u16 divide-by-flat
            // path (which divides by `flat_pixel / flat_mean`) still operates
            // on values that fit in the [0, 65535] range without saturating.
            let target_mean = match output_type {
                MasterOutputType::F32 => 1.0,
                MasterOutputType::U16 => 32768.0,
            };
            let scale = target_mean / input_mean;
            let scaled: Vec<f64> = combined.par_iter().map(|&v| v * scale).collect();
            (scaled, target_mean)
        }
        MasterFrameKind::Bias | MasterFrameKind::Dark => (combined, input_mean),
    };

    // --- materialise the output ImageData ---------------------------------
    let image = match output_type {
        MasterOutputType::U16 => {
            let u16_data: Vec<u16> = final_pixels
                .par_iter()
                .map(|&v| v.round().clamp(0.0, 65535.0) as u16)
                .collect();
            ImageData::from_u16(width, height, channels, &u16_data)
        }
        MasterOutputType::F32 => {
            let f32_data: Vec<f32> = final_pixels.par_iter().map(|&v| v as f32).collect();
            ImageData::from_f32(width, height, channels, &f32_data)
        }
    };

    Ok(MasterFrame {
        image,
        kind,
        frame_count: frames.len() as u32,
        method,
        output_type,
        input_mean,
        output_mean,
    })
}

/// Reduce a per-pixel sample slice to a single combined value via the
/// requested method. `samples` is mutable so median / sigma-clip can sort
/// in place rather than re-allocating.
fn combine_pixel(samples: &mut [f64], method: CombineMethod) -> f64 {
    // Caller guarantees `samples` is non-empty (combine_master_frames
    // already verified `frames` is non-empty and every frame has the same
    // pixel_count, so every per-pixel sample vec has length `frames.len()`).
    match method {
        CombineMethod::Mean => samples.iter().sum::<f64>() / samples.len() as f64,
        CombineMethod::Median => median_in_place(samples),
        CombineMethod::SigmaClip { kappa, iterations } => {
            sigma_clip_in_place(samples, kappa, iterations)
        }
    }
}

/// Compute the median of `samples`, mutating its order. For even-length
/// inputs, returns the mean of the two centre elements (statistical
/// definition of the median) so that an even cosmic-ray-vs-clean split
/// doesn't bias toward one side.
fn median_in_place(samples: &mut [f64]) -> f64 {
    let n = samples.len();
    // partial sort gets the middle element; for even n we need two.
    samples.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    if n % 2 == 1 {
        samples[n / 2]
    } else {
        (samples[n / 2 - 1] + samples[n / 2]) * 0.5
    }
}

/// Iteratively reject samples outside `kappa * sigma` from the running mean.
/// Returns the mean of the surviving samples. If every sample is rejected
/// (degenerate case — should not happen in practice because the first
/// iteration starts from the full-population mean), falls back to the
/// median so we always emit *something* sensible.
fn sigma_clip_in_place(samples: &mut [f64], kappa: f64, iterations: u32) -> f64 {
    if samples.len() <= 2 {
        // Not enough samples to estimate stddev meaningfully; just average.
        return samples.iter().sum::<f64>() / samples.len() as f64;
    }
    let mut working: Vec<f64> = samples.to_vec();
    for _ in 0..iterations {
        if working.len() < 3 {
            break;
        }
        let n = working.len() as f64;
        let mean: f64 = working.iter().sum::<f64>() / n;
        let var: f64 =
            working.iter().map(|&v| (v - mean) * (v - mean)).sum::<f64>() / (n - 1.0);
        let sigma = var.max(0.0).sqrt();
        if sigma == 0.0 {
            // Population is degenerate (all equal); no clipping possible.
            break;
        }
        let lo = mean - kappa * sigma;
        let hi = mean + kappa * sigma;
        let before = working.len();
        working.retain(|&v| v >= lo && v <= hi);
        if working.len() == before {
            // Converged: no samples rejected this iteration.
            break;
        }
        if working.is_empty() {
            // Total rejection (shouldn't happen on iter 1 with k>=1); bail.
            return median_in_place(samples);
        }
    }
    working.iter().sum::<f64>() / working.len() as f64
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

    // =========================================================================
    // IMG-P2-1: Master frame combination tests
    // =========================================================================

    /// Build a synthetic U16 image filled with a constant value (single channel).
    fn constant_u16_image(width: u32, height: u32, value: u16) -> ImageData {
        let data = vec![value; (width as usize) * (height as usize)];
        ImageData::from_u16(width, height, 1, &data)
    }

    #[test]
    fn master_bias_constant_value_yields_that_constant() {
        // 5 identical bias frames at 1234 ADU. Median (and mean) should
        // produce exactly 1234 — bias is the simplest case and any drift
        // would indicate the combine path is silently corrupting data.
        let frames: Vec<ImageData> = (0..5).map(|_| constant_u16_image(4, 4, 1234)).collect();
        let master = combine_master_frames(
            &frames,
            MasterFrameKind::Bias,
            CombineMethod::Median,
            MasterOutputType::U16,
        )
        .expect("master bias build should succeed");

        assert_eq!(master.kind, MasterFrameKind::Bias);
        assert_eq!(master.frame_count, 5);
        assert_eq!(master.output_type, MasterOutputType::U16);

        let pixels = master.image.as_u16().expect("u16 master should return u16");
        assert_eq!(pixels.len(), 16);
        for &p in &pixels {
            assert_eq!(p, 1234, "every pixel of the bias master should be the constant input value");
        }
        assert!((master.input_mean - 1234.0).abs() < 1e-9);
        assert!((master.output_mean - 1234.0).abs() < 1e-9);
    }

    #[test]
    fn master_dark_median_rejects_single_cosmic_ray_hit() {
        // 3 dark frames, all at ADU=500 except one frame has a cosmic-ray
        // hit at pixel (1,1) saturating to 65535. Median should reject the
        // outlier and return 500 at that pixel; the mean would return ~21845.
        let w = 4;
        let h = 4;
        let mut f1 = vec![500u16; (w * h) as usize];
        let mut f2 = vec![500u16; (w * h) as usize];
        let f3 = vec![500u16; (w * h) as usize];
        // Cosmic ray on f1 at (1,1); also a different hit on f2 at (2,2)
        // to confirm median rejects each independently per-pixel.
        let cr_idx_1 = (w + 1) as usize;
        let cr_idx_2 = (2 * w + 2) as usize;
        f1[cr_idx_1] = 65535;
        f2[cr_idx_2] = 65535;

        let frames = vec![
            ImageData::from_u16(w, h, 1, &f1),
            ImageData::from_u16(w, h, 1, &f2),
            ImageData::from_u16(w, h, 1, &f3),
        ];

        let master = combine_master_frames(
            &frames,
            MasterFrameKind::Dark,
            CombineMethod::Median,
            MasterOutputType::U16,
        )
        .expect("master dark build should succeed");

        let pixels = master.image.as_u16().expect("u16 master");
        for (i, &p) in pixels.iter().enumerate() {
            assert_eq!(
                p, 500,
                "pixel {} should be 500 after median rejection of cosmic ray",
                i
            );
        }
    }

    #[test]
    fn master_flat_is_normalised_to_unit_mean_f32() {
        // 5 flat frames with mean ~10000 ADU. After normalisation to F32,
        // the master mean must be 1.0 (within floating-point tolerance).
        // Use a gradient so the normalised values are visibly non-uniform
        // — this catches the bug where normalisation accidentally maps
        // everything to a single constant.
        let w: u32 = 8;
        let h: u32 = 8;
        let pixel_count = (w * h) as usize;

        // Build a frame whose mean is 10000 ADU but with per-pixel variation
        // (linear ramp 5000..15000). The mean of this ramp is 10000.
        let mut ramp_pixels = Vec::with_capacity(pixel_count);
        for i in 0..pixel_count {
            // Linear from 5000 to 15000 across the image.
            let v = 5000.0 + 10000.0 * (i as f64) / ((pixel_count - 1) as f64);
            ramp_pixels.push(v.round() as u16);
        }
        // Sanity: confirm the test fixture mean really is 10000.
        let raw_mean = ramp_pixels.iter().map(|&p| p as f64).sum::<f64>()
            / ramp_pixels.len() as f64;
        assert!(
            (raw_mean - 10000.0).abs() < 1.0,
            "test fixture ramp mean should be ~10000, got {}",
            raw_mean
        );

        let frames: Vec<ImageData> = (0..5)
            .map(|_| ImageData::from_u16(w, h, 1, &ramp_pixels))
            .collect();

        let master = combine_master_frames(
            &frames,
            MasterFrameKind::Flat,
            CombineMethod::Median,
            MasterOutputType::F32,
        )
        .expect("master flat build should succeed");

        assert_eq!(master.kind, MasterFrameKind::Flat);
        assert_eq!(master.output_type, MasterOutputType::F32);

        let pixels = master.image.as_f32().expect("f32 master should return f32");
        assert_eq!(pixels.len(), pixel_count);
        let out_mean: f64 = pixels.iter().map(|&v| v as f64).sum::<f64>() / pixels.len() as f64;
        assert!(
            (out_mean - 1.0).abs() < 1e-4,
            "normalised flat mean should be 1.0, got {}",
            out_mean
        );
        // Confirm we preserved relative variation — the smallest normalised
        // pixel should be roughly 0.5 (since 5000/10000=0.5).
        let min_pixel = pixels.iter().cloned().fold(f32::INFINITY, f32::min);
        assert!(
            (min_pixel - 0.5).abs() < 0.01,
            "min normalised pixel should be ~0.5, got {}",
            min_pixel
        );
    }

    #[test]
    fn master_flat_u16_normalised_to_half_scale_32768() {
        // Same as the f32 case but request U16 output. The flat's normalised
        // mean should land on 32768 (half-scale) so the legacy u16
        // calibration code can still divide without saturation.
        let w: u32 = 4;
        let h: u32 = 4;
        let frames: Vec<ImageData> = (0..5)
            .map(|_| constant_u16_image(w, h, 10000))
            .collect();

        let master = combine_master_frames(
            &frames,
            MasterFrameKind::Flat,
            CombineMethod::Median,
            MasterOutputType::U16,
        )
        .expect("u16 master flat build should succeed");

        let pixels = master.image.as_u16().expect("u16 master");
        for &p in &pixels {
            assert_eq!(
                p, 32768,
                "constant flat normalised to U16 should be exactly 32768"
            );
        }
        assert!((master.output_mean - 32768.0).abs() < 1e-9);
        assert!((master.input_mean - 10000.0).abs() < 1e-9);
    }

    #[test]
    fn empty_input_returns_err() {
        let frames: Vec<ImageData> = Vec::new();
        let result = combine_master_frames(
            &frames,
            MasterFrameKind::Bias,
            CombineMethod::Median,
            MasterOutputType::U16,
        );
        assert!(result.is_err(), "empty input must return Err, not silently produce a master");
        let err = result.unwrap_err();
        assert!(
            err.contains("zero frames") || err.contains("empty"),
            "error should mention empty/zero frames, got: {}",
            err
        );
    }

    #[test]
    fn mixed_dimensions_returns_err() {
        let f1 = constant_u16_image(4, 4, 1000);
        let f2 = constant_u16_image(8, 4, 1000); // different width
        let result = combine_master_frames(
            &[f1, f2],
            MasterFrameKind::Dark,
            CombineMethod::Median,
            MasterOutputType::U16,
        );
        assert!(result.is_err(), "mixed dimensions must return Err");
        assert!(
            result.unwrap_err().contains("dimensions"),
            "error should mention dimensions"
        );
    }

    #[test]
    fn mixed_pixel_types_returns_err() {
        let f1 = constant_u16_image(4, 4, 1000);
        let f2 = ImageData::from_f32(4, 4, 1, &[1000.0f32; 16]);
        let result = combine_master_frames(
            &[f1, f2],
            MasterFrameKind::Dark,
            CombineMethod::Median,
            MasterOutputType::U16,
        );
        assert!(result.is_err(), "mixed pixel types must return Err");
    }

    #[test]
    fn sigma_clip_rejects_outliers_in_dark_master() {
        // 11 dark frames: 10 at 500 ADU and one outlier at 65000.
        // Sigma clipping at k=2 should reject the outlier; the resulting
        // mean should be ~500, not the mean-with-outlier (~6363).
        let w: u32 = 2;
        let h: u32 = 2;
        let mut frames: Vec<ImageData> = (0..10).map(|_| constant_u16_image(w, h, 500)).collect();
        frames.push(constant_u16_image(w, h, 65000));

        let master = combine_master_frames(
            &frames,
            MasterFrameKind::Dark,
            CombineMethod::SigmaClip {
                kappa: 2.0,
                iterations: 3,
            },
            MasterOutputType::U16,
        )
        .expect("sigma-clip master should succeed");

        let pixels = master.image.as_u16().unwrap();
        for &p in &pixels {
            assert!(
                (p as i32 - 500).abs() < 5,
                "sigma-clipped dark pixel should be ~500, got {}",
                p
            );
        }
    }

    #[test]
    fn invalid_sigma_clip_params_return_err() {
        let frames: Vec<ImageData> = (0..5).map(|_| constant_u16_image(2, 2, 1000)).collect();
        // Zero iterations
        let r1 = combine_master_frames(
            &frames,
            MasterFrameKind::Dark,
            CombineMethod::SigmaClip {
                kappa: 2.0,
                iterations: 0,
            },
            MasterOutputType::U16,
        );
        assert!(r1.is_err(), "sigma-clip iterations=0 must fail");
        // Negative kappa
        let r2 = combine_master_frames(
            &frames,
            MasterFrameKind::Dark,
            CombineMethod::SigmaClip {
                kappa: -1.0,
                iterations: 3,
            },
            MasterOutputType::U16,
        );
        assert!(r2.is_err(), "sigma-clip kappa<=0 must fail");
    }

    // =========================================================================
    // IMG-P2-3: avg_matched_pairs / avg_alignment_residual divisor
    // =========================================================================
    //
    // Verifies that the per-aligned-frame averages divide by the count of
    // *non-reference* frames, not the full stacked_frame_count. The
    // reference frame contributes 0 to both metrics by construction, so the
    // pre-fix divisor of `stacked_frame_count` (which includes it) diluted
    // the averages by (N-1)/N.

    /// Update stats using the same arithmetic the fixed accumulator path uses,
    /// so the test directly exercises the divisor formula introduced for
    /// IMG-P2-3 without spinning up a full LiveStacker (which requires
    /// successful star detection on each frame).
    fn step_stats(stats: &mut StackingStats, matches_len: usize, residual: f64) {
        stats.stacked_frame_count += 1;
        let aligned_count = stats.stacked_frame_count.saturating_sub(1).max(1) as f64;
        stats.avg_matched_pairs =
            stats.avg_matched_pairs * ((aligned_count - 1.0) / aligned_count)
                + matches_len as f64 / aligned_count;
        stats.avg_alignment_residual =
            stats.avg_alignment_residual * ((aligned_count - 1.0) / aligned_count)
                + residual / aligned_count;
    }

    #[test]
    fn avg_metrics_exclude_reference_frame_contribution() {
        // Simulate 5 stacked frames: 1 reference (no metrics), 4 aligned
        // each with matched_pairs=10 and residual=0.5. The post-fix average
        // must be exactly 10.0 and 0.5 — pre-fix this was diluted to 8.0
        // and 0.4 because the reference was counted in the divisor.
        // reference frame initialised but not measured
        let mut stats = StackingStats {
            stacked_frame_count: 1,
            ..Default::default()
        };

        for _ in 0..4 {
            step_stats(&mut stats, 10, 0.5);
        }

        assert_eq!(stats.stacked_frame_count, 5);
        assert!(
            (stats.avg_matched_pairs - 10.0).abs() < 1e-9,
            "avg_matched_pairs should be 10.0 (not diluted by reference), got {}",
            stats.avg_matched_pairs
        );
        assert!(
            (stats.avg_alignment_residual - 0.5).abs() < 1e-9,
            "avg_alignment_residual should be 0.5 (not diluted by reference), got {}",
            stats.avg_alignment_residual
        );
    }

    #[test]
    fn pre_fix_divisor_formula_would_yield_8_and_0_4() {
        // Reference test: prove the bug claim by re-deriving the buggy
        // formula and confirming it produces 8.0 / 0.4 for the same inputs.
        // This locks in WHY the fix is correct: with the old divisor of
        // `stacked_frame_count` (including the reference), the average gets
        // multiplied by (N-1)/N. For 5 frames that's 4/5 = 0.8, so
        // 10 * 0.8 = 8.0 and 0.5 * 0.8 = 0.4.
        let mut buggy_count: u32 = 1;
        let mut buggy_avg_matches = 0.0_f64;
        let mut buggy_avg_residual = 0.0_f64;
        for _ in 0..4 {
            buggy_count += 1;
            let n = buggy_count as f64;
            buggy_avg_matches = buggy_avg_matches * ((n - 1.0) / n) + 10.0 / n;
            buggy_avg_residual = buggy_avg_residual * ((n - 1.0) / n) + 0.5 / n;
        }
        assert!((buggy_avg_matches - 8.0).abs() < 1e-9);
        assert!((buggy_avg_residual - 0.4).abs() < 1e-9);
    }

    #[test]
    fn first_aligned_frame_yields_exact_metrics() {
        // After exactly one aligned frame (so stacked_frame_count=2), the
        // average must equal that frame's metrics — not half of them.
        let mut stats = StackingStats {
            stacked_frame_count: 1,
            ..Default::default()
        };
        step_stats(&mut stats, 17, 0.83);
        assert_eq!(stats.stacked_frame_count, 2);
        assert!(
            (stats.avg_matched_pairs - 17.0).abs() < 1e-9,
            "single aligned frame must report its own match count, got {}",
            stats.avg_matched_pairs
        );
        assert!(
            (stats.avg_alignment_residual - 0.83).abs() < 1e-9,
            "single aligned frame must report its own residual, got {}",
            stats.avg_alignment_residual
        );
    }
}
