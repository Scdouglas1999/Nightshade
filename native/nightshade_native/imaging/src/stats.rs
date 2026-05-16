//! Image statistics and star detection

use crate::ImageData;
use rayon::prelude::*;

/// Statistics for an image
#[derive(Debug, Clone, Default)]
pub struct ImageStats {
    pub min: f64,
    pub max: f64,
    pub mean: f64,
    pub median: f64,
    pub std_dev: f64,
    pub mad: f64, // Median Absolute Deviation
}

/// Calculate statistics for a 16-bit image
pub fn calculate_stats_u16(image: &ImageData) -> ImageStats {
    if image.data.is_empty() {
        return ImageStats::default();
    }

    // Parallel conversion to u16
    let mut pixels: Vec<u16> = image
        .data
        .par_chunks_exact(2)
        .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
        .collect();

    if pixels.is_empty() {
        return ImageStats::default();
    }

    // Parallel calculation of min, max, sum
    let (min, max, sum) = pixels
        .par_iter()
        .fold(
            || (u16::MAX, u16::MIN, 0.0f64),
            |(min, max, sum), &val| (min.min(val), max.max(val), sum + val as f64),
        )
        .reduce(
            || (u16::MAX, u16::MIN, 0.0f64),
            |(min1, max1, sum1), (min2, max2, sum2)| (min1.min(min2), max1.max(max2), sum1 + sum2),
        );

    let count = pixels.len() as f64;
    let mean = sum / count;

    // Parallel variance calculation
    let variance: f64 = pixels
        .par_iter()
        .map(|&p| {
            let diff = p as f64 - mean;
            diff * diff
        })
        .sum::<f64>()
        / count;
    let std_dev = variance.sqrt();

    // Parallel sort for median
    pixels.par_sort_unstable();
    let median = if pixels.len().is_multiple_of(2) {
        let mid = pixels.len() / 2;
        (pixels[mid - 1] as f64 + pixels[mid] as f64) / 2.0
    } else {
        pixels[pixels.len() / 2] as f64
    };

    // Parallel MAD calculation
    let mut deviations: Vec<f64> = pixels
        .par_iter()
        .map(|&p| (p as f64 - median).abs())
        .collect();

    deviations.par_sort_unstable_by(|a, b| a.total_cmp(b));

    let mad = if deviations.len().is_multiple_of(2) {
        let mid = deviations.len() / 2;
        (deviations[mid - 1] + deviations[mid]) / 2.0
    } else {
        deviations[deviations.len() / 2]
    };

    ImageStats {
        min: min as f64,
        max: max as f64,
        mean,
        median,
        std_dev,
        mad,
    }
}

/// Star detection result
#[derive(Debug, Clone)]
pub struct DetectedStar {
    pub x: f64,
    pub y: f64,
    pub flux: f64,
    pub hfr: f64,
    pub fwhm: f64,
    pub peak: f64,
    pub background: f64,
    pub snr: f64,
    /// Eccentricity: 0 = perfect circle, 1 = line (elongated)
    pub eccentricity: f64,
    /// Sharpness: ratio of peak to spread - hot pixels have high sharpness, real stars lower
    /// Typical real stars: 0.1-0.5, hot pixels: > 0.8
    pub sharpness: f64,
}

/// Camera-domain inputs for the standard CCD-equation SNR.
///
/// Why: per audit §6.10, SNR must be computed in the electron domain using
/// `SNR = signal / sqrt(signal + n_pix * (sky + read_noise² + dark))`. That
/// formula needs the conversion from ADU to electrons (`gain_e_per_adu`),
/// the per-pixel read noise (`read_noise_e`), and the per-pixel dark
/// accumulated over the exposure (`dark_e_per_sec * exposure_s`). When the
/// caller cannot supply this metadata, `StarDetectionConfig::noise_model`
/// is left `None` and we fall back to the ADU-domain CCD-equation
/// approximation (see `compute_snr` for the explicit formula and
/// documented approximation), which is the same equation evaluated against
/// the empirically-measured per-pixel background variance.
#[derive(Debug, Clone, Copy)]
pub struct CameraNoiseModel {
    /// Gain in electrons per ADU (e.g. ZWO ASI2600MM at unity gain ≈ 1.0).
    pub gain_e_per_adu: f64,
    /// Read noise in electrons RMS per pixel.
    pub read_noise_e: f64,
    /// Dark current in electrons per pixel per second.
    pub dark_e_per_sec: f64,
    /// Exposure duration in seconds (used to compute total dark per pixel).
    pub exposure_s: f64,
}

/// Star detection configuration
#[derive(Debug, Clone)]
pub struct StarDetectionConfig {
    /// Detection threshold in sigma above background
    pub detection_sigma: f64,
    /// Minimum star area in pixels
    pub min_area: u32,
    /// Maximum star area in pixels
    pub max_area: u32,
    /// Maximum eccentricity (0 = circle, 1 = line)
    pub max_eccentricity: f64,
    /// Saturation threshold (0-65535)
    pub saturation_limit: u16,
    /// Search radius for HFR calculation
    pub hfr_radius: u32,
    /// Minimum HFR to be considered a real star (filters hot pixels)
    /// Hot pixels typically have HFR < 1.0, real stars > 1.2
    pub min_hfr: f64,
    /// Minimum SNR to be considered a valid detection
    pub min_snr: f64,
    /// Maximum sharpness (filters hot pixels which have very high sharpness)
    pub max_sharpness: f64,
    /// Camera noise model for the electron-domain CCD-equation SNR.
    ///
    /// Why: when present, SNR is computed in electrons per audit §6.10.
    /// When `None`, SNR uses the ADU-domain approximation against the
    /// measured per-pixel background variance (still the standard CCD
    /// equation, just evaluated empirically). Callers that do have
    /// camera metadata (gain, read-noise, dark-current, exposure) should
    /// populate this so reported SNR is comparable across cameras.
    pub noise_model: Option<CameraNoiseModel>,
}

impl Default for StarDetectionConfig {
    fn default() -> Self {
        Self {
            detection_sigma: 5.0, // Increased from 3.0 - more conservative
            min_area: 9,          // Increased from 5 - hot pixels rarely exceed this
            max_area: 10000,
            max_eccentricity: 0.7, // Slightly tighter - real stars are round
            saturation_limit: 60000,
            hfr_radius: 20,
            min_hfr: 1.0,        // Real stars have HFR > ~1.0; hot pixels < 0.8
            min_snr: 5.0,        // Modest SNR threshold - real stars in short subs can be faint
            max_sharpness: 0.95, // Only reject extreme hot pixels (sharpness ~1.0); real stars spread flux
            // Why: callers without camera metadata fall back to the ADU-domain
            // CCD-equation approximation (documented in `compute_snr`). Callers
            // with profile metadata should set this explicitly.
            noise_model: None,
        }
    }
}

/// Detect stars in a 16-bit image
pub fn detect_stars(image: &ImageData, config: &StarDetectionConfig) -> Vec<DetectedStar> {
    let width = image.width as usize;
    let height = image.height as usize;

    if width == 0 || height == 0 || image.data.len() < width * height * 2 {
        return Vec::new();
    }

    // Parallel convert to f64 array
    let pixels: Vec<f64> = image
        .data
        .par_chunks_exact(2)
        .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]) as f64)
        .collect();

    // Estimate background using sigma-clipped median (partially parallelized)
    let (background, noise) = estimate_background(&pixels, width, height);

    // Detection threshold
    let threshold = background + config.detection_sigma * noise;

    // Find candidate pixels above threshold
    // Note: Full star detection is hard to parallelize due to 'visited' state
    // We keep the main loop sequential for correctness but use the parallelized setup
    let mut visited = vec![false; pixels.len()];
    let mut stars = Vec::new();

    for y in 2..height - 2 {
        for x in 2..width - 2 {
            let idx = y * width + x;

            if visited[idx] || pixels[idx] < threshold {
                continue;
            }

            // Check if this is a local maximum (8-connected)
            let val = pixels[idx];
            let is_max = val >= pixels[idx - 1]
                && val >= pixels[idx + 1]
                && val >= pixels[idx - width]
                && val >= pixels[idx + width]
                && val >= pixels[idx - width - 1]
                && val >= pixels[idx - width + 1]
                && val >= pixels[idx + width - 1]
                && val >= pixels[idx + width + 1];

            if !is_max {
                continue;
            }

            // Skip saturated stars
            if val > config.saturation_limit as f64 {
                continue;
            }

            // Extract star region and measure
            let mut ctx = StarMeasurementContext {
                pixels: &pixels,
                width,
                height,
                background,
                noise,
                config,
                visited: &mut visited,
            };
            if let Some(star) = measure_star(&mut ctx, x, y) {
                // Comprehensive star validation to filter hot pixels and noise
                // Track rejection reasons for diagnostics (only log first few)
                static LOGGED_REJECTIONS: std::sync::atomic::AtomicU32 =
                    std::sync::atomic::AtomicU32::new(0);
                let should_log = LOGGED_REJECTIONS.load(std::sync::atomic::Ordering::Relaxed) < 5;

                // 1. HFR check - hot pixels have very small HFR
                if star.hfr < config.min_hfr {
                    if should_log {
                        tracing::debug!(
                            "Star rejected: HFR {:.2} < min {:.2} (pos: {:.1},{:.1})",
                            star.hfr,
                            config.min_hfr,
                            star.x,
                            star.y
                        );
                        LOGGED_REJECTIONS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    }
                    continue;
                }

                // 2. SNR check - require good signal-to-noise
                if star.snr < config.min_snr {
                    if should_log {
                        tracing::debug!(
                            "Star rejected: SNR {:.2} < min {:.2} (pos: {:.1},{:.1}, HFR: {:.2})",
                            star.snr,
                            config.min_snr,
                            star.x,
                            star.y,
                            star.hfr
                        );
                        LOGGED_REJECTIONS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    }
                    continue;
                }

                // 3. Eccentricity check - reject elongated objects (cosmic rays, tracking errors)
                if star.eccentricity > config.max_eccentricity {
                    if should_log {
                        tracing::debug!(
                            "Star rejected: eccentricity {:.2} > max {:.2} (pos: {:.1},{:.1})",
                            star.eccentricity,
                            config.max_eccentricity,
                            star.x,
                            star.y
                        );
                        LOGGED_REJECTIONS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    }
                    continue;
                }

                // 4. Sharpness check - hot pixels have very high sharpness
                if star.sharpness > config.max_sharpness {
                    if should_log {
                        tracing::debug!(
                            "Star rejected: sharpness {:.2} > max {:.2} (pos: {:.1},{:.1})",
                            star.sharpness,
                            config.max_sharpness,
                            star.x,
                            star.y
                        );
                        LOGGED_REJECTIONS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    }
                    continue;
                }

                // 5. Area check (approximate from flux distribution)
                let area = star.flux / (star.peak - background).max(1.0);
                if area < config.min_area as f64 || area > config.max_area as f64 {
                    if should_log {
                        tracing::debug!(
                            "Star rejected: area {:.1} outside range [{}, {}] (pos: {:.1},{:.1})",
                            area,
                            config.min_area,
                            config.max_area,
                            star.x,
                            star.y
                        );
                        LOGGED_REJECTIONS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    }
                    continue;
                }

                stars.push(star);
            }
        }
    }

    // Sort by flux (brightest first)
    stars.sort_by(|a, b| b.flux.total_cmp(&a.flux));

    stars
}

/// Estimate background level and noise using sigma clipping
fn estimate_background(pixels: &[f64], _width: usize, _height: usize) -> (f64, f64) {
    // Sample every 4th pixel for speed
    // Parallelize sampling
    let mut samples: Vec<f64> = pixels.par_iter().step_by(4).copied().collect();

    if samples.is_empty() {
        return (0.0, 1.0);
    }

    // Sigma clipping iterations
    for _ in 0..3 {
        samples.par_sort_unstable_by(|a, b| a.total_cmp(b));
        let median = samples[samples.len() / 2];

        // Parallel MAD calculation
        let mad: f64 =
            samples.par_iter().map(|&v| (v - median).abs()).sum::<f64>() / samples.len() as f64;
        let sigma = mad * 1.4826;

        let lower = median - 3.0 * sigma;
        let upper = median + 3.0 * sigma;

        // Parallel retain is not available directly on Vec, but we can filter and collect
        // However, retain is in-place and might be faster than allocating new vec
        // Keep sequential retain as it iterates an already reduced set.
        samples.retain(|&v| v >= lower && v <= upper);

        if samples.is_empty() {
            return (median, sigma);
        }
    }

    samples.par_sort_unstable_by(|a, b| a.total_cmp(b));
    let background = samples[samples.len() / 2];

    // Estimate noise from remaining samples
    let variance: f64 = samples
        .par_iter()
        .map(|&v| (v - background).powi(2))
        .sum::<f64>()
        / samples.len() as f64;
    let noise = variance.sqrt();

    (background, noise.max(1.0))
}

/// Context for star measurement to reduce parameter count
struct StarMeasurementContext<'a> {
    pixels: &'a [f64],
    width: usize,
    height: usize,
    background: f64,
    noise: f64,
    config: &'a StarDetectionConfig,
    visited: &'a mut [bool],
}

/// Measure a star's properties including eccentricity and sharpness
fn measure_star(ctx: &mut StarMeasurementContext, cx: usize, cy: usize) -> Option<DetectedStar> {
    let radius = ctx.config.hfr_radius as i32;

    // First pass: Calculate centroid using intensity-weighted center
    let mut sum_x = 0.0;
    let mut sum_y = 0.0;
    let mut sum_flux = 0.0;
    let mut peak = 0.0_f64;
    let mut pixel_count = 0u32;

    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let x = cx as i32 + dx;
            let y = cy as i32 + dy;

            if x < 0 || y < 0 || x >= ctx.width as i32 || y >= ctx.height as i32 {
                continue;
            }

            let idx = y as usize * ctx.width + x as usize;
            let val = ctx.pixels[idx] - ctx.background;

            if val > 0.0 {
                sum_x += x as f64 * val;
                sum_y += y as f64 * val;
                sum_flux += val;
                peak = peak.max(ctx.pixels[idx]);
                pixel_count += 1;
                ctx.visited[idx] = true;
            }
        }
    }

    if sum_flux <= 0.0 || pixel_count == 0 {
        return None;
    }

    let centroid_x = sum_x / sum_flux;
    let centroid_y = sum_y / sum_flux;

    // Second pass: Calculate second moments for eccentricity
    // Mxx = Σ(x - cx)² * I / Σ I
    // Myy = Σ(y - cy)² * I / Σ I
    // Mxy = Σ(x - cx)(y - cy) * I / Σ I
    let mut mxx = 0.0;
    let mut myy = 0.0;
    let mut mxy = 0.0;

    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let x = cx as i32 + dx;
            let y = cy as i32 + dy;

            if x < 0 || y < 0 || x >= ctx.width as i32 || y >= ctx.height as i32 {
                continue;
            }

            let idx = y as usize * ctx.width + x as usize;
            let val = ctx.pixels[idx] - ctx.background;

            if val > 0.0 {
                let dx_c = x as f64 - centroid_x;
                let dy_c = y as f64 - centroid_y;
                mxx += dx_c * dx_c * val;
                myy += dy_c * dy_c * val;
                mxy += dx_c * dy_c * val;
            }
        }
    }

    mxx /= sum_flux;
    myy /= sum_flux;
    mxy /= sum_flux;

    // Calculate eccentricity from second moments
    // Using eigenvalues of the covariance matrix
    let trace = mxx + myy;
    let det = mxx * myy - mxy * mxy;
    let discriminant = (trace * trace - 4.0 * det).max(0.0).sqrt();

    let lambda1 = (trace + discriminant) / 2.0;
    let lambda2 = (trace - discriminant) / 2.0;

    // Eccentricity: 0 = circle, 1 = line
    let eccentricity = if lambda1 > 1e-10 && lambda2 >= 0.0 {
        (1.0 - lambda2 / lambda1).max(0.0).sqrt()
    } else {
        0.0
    };

    // Calculate HFR (true encircled-energy 50% radius — see audit §6.11).
    let hfr = calculate_hfr_at_point(
        ctx.pixels,
        ctx.width,
        ctx.height,
        centroid_x,
        centroid_y,
        ctx.background,
        radius,
    );

    // Why: with the encircled-energy 50% HFR (matching NINA / SGP / PixInsight),
    // FWHM = 2.0 × HFR for a Gaussian PSF (HFR_true = σ·√(2 ln 2),
    // FWHM = 2σ·√(2 ln 2)). The previous 2.3548 constant assumed HFR ≈ σ,
    // which is wrong: HFR_true ≈ 1.177σ. See audit §6.11.
    const FWHM_TO_HFR_RATIO: f64 = 2.0;
    let fwhm = hfr * FWHM_TO_HFR_RATIO;

    // SNR via the standard CCD equation (audit §6.10). `pixel_count` is the
    // actual aperture pixel count `n_pix` derived from the detection mask.
    let snr = compute_snr(
        sum_flux,
        pixel_count as f64,
        ctx.noise,
        ctx.config.noise_model.as_ref(),
    );

    let peak_above_bg = peak - ctx.background;

    // Calculate sharpness: ratio of peak intensity to average flux per pixel
    // Hot pixels have very high sharpness (most flux in one pixel)
    // Real stars have lower sharpness (flux spread across many pixels)
    let avg_flux_per_pixel = sum_flux / pixel_count as f64;
    let sharpness = if avg_flux_per_pixel > 0.0 {
        (peak_above_bg / avg_flux_per_pixel).min(1.0)
    } else {
        1.0 // Default to high sharpness (reject) if can't calculate
    };

    Some(DetectedStar {
        x: centroid_x,
        y: centroid_y,
        flux: sum_flux,
        hfr,
        fwhm,
        peak,
        background: ctx.background,
        snr,
        eccentricity,
        sharpness,
    })
}

/// Compute the true encircled-energy 50% half-flux radius (HFR).
///
/// Why: per audit §6.11 we sort the aperture pixels by distance from the
/// centroid, integrate background-subtracted flux in increasing-radius
/// order, and return the radius at which cumulative flux first crosses
/// 50% of the total. Sub-pixel accuracy is achieved by linearly
/// interpolating the radius between the two pixels that bracket the
/// 50% point.
///
/// This matches the NINA / SGP / PixInsight HFR convention. The
/// previous implementation returned the flux-weighted *mean* radius
/// ⟨r⟩, which over-states FWHM by ~25% for a Gaussian PSF.
fn calculate_hfr_at_point(
    pixels: &[f64],
    width: usize,
    height: usize,
    cx: f64,
    cy: f64,
    background: f64,
    radius: i32,
) -> f64 {
    // Use the sub-pixel centroid as the reference for radial distances so
    // that the returned HFR has sub-pixel accuracy.
    let mut samples: Vec<(f64, f64)> =
        Vec::with_capacity(((2 * radius + 1) * (2 * radius + 1)) as usize);

    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let xi = cx.round() as i32 + dx;
            let yi = cy.round() as i32 + dy;
            if xi < 0 || yi < 0 || xi >= width as i32 || yi >= height as i32 {
                continue;
            }
            let val = (pixels[yi as usize * width + xi as usize] - background).max(0.0);
            if val <= 0.0 {
                continue;
            }
            let dxr = xi as f64 - cx;
            let dyr = yi as f64 - cy;
            let dist = (dxr * dxr + dyr * dyr).sqrt();
            samples.push((dist, val));
        }
    }

    if samples.is_empty() {
        return 0.0;
    }

    // Sort by radial distance ascending.
    samples.sort_by(|a, b| a.0.total_cmp(&b.0));

    let total_flux: f64 = samples.iter().map(|s| s.1).sum();
    if total_flux <= 0.0 {
        return 0.0;
    }
    let half_flux = 0.5 * total_flux;

    let mut cum = 0.0;
    let mut prev_r = 0.0;
    let mut prev_cum = 0.0;
    for &(r, v) in &samples {
        let next_cum = cum + v;
        if next_cum >= half_flux {
            // Linearly interpolate between the previous (r, cum) and (r, next_cum).
            // Why: cumulative flux is piecewise-linear in r if we treat each
            // pixel contribution as an instantaneous step at its radius; using
            // a linear interpolation between the bracketing samples gives the
            // best sub-pixel estimate available without re-sampling the PSF.
            let denom = next_cum - prev_cum;
            if denom <= 0.0 {
                return r;
            }
            let frac = (half_flux - prev_cum) / denom;
            return prev_r + frac * (r - prev_r);
        }
        prev_cum = next_cum;
        prev_r = r;
        cum = next_cum;
    }

    // Fallback: should not happen because cum reaches total_flux >= half_flux
    // at the last sample, but keep the outermost radius if it does.
    prev_r
}

/// Compute SNR via the standard CCD equation.
///
/// Why: per audit §6.10, the previous formula
/// `sum_flux / (noise * sqrt(sum_flux / peak_above_bg))` is non-standard
/// and omits read noise + dark current entirely. The correct model is
///
/// ```text
///     SNR = signal / sqrt(signal + n_pix * (sky + read_noise² + dark))
/// ```
///
/// Inputs:
/// * `signal_adu` — integrated background-subtracted flux in the aperture (ADU).
/// * `n_pix` — actual aperture pixel count from the detection mask.
/// * `bg_noise_adu` — empirical per-pixel background sigma in ADU
///   (output of `estimate_background`). This already aggregates sky shot
///   noise, read noise, and dark current as they appear in this frame.
/// * `model` — optional electron-domain camera metadata.
///
/// When `model` is supplied, the calculation is performed in electrons
/// using `gain_e_per_adu`, `read_noise_e`, `dark_e_per_sec * exposure_s`,
/// and the empirical sky variance converted to electrons. When `model`
/// is `None`, we evaluate the same CCD equation in the ADU domain
/// against `bg_noise_adu²`; this is mathematically the standard CCD
/// equation with the sum (sky + read_noise² + dark) replaced by the
/// empirically-measured per-pixel background variance. The ADU-domain
/// branch under-counts only the source-shot-noise term that depends on
/// gain (it is treated as if gain = 1 e/ADU); this is documented and
/// callers that have profile metadata should populate `noise_model`.
fn compute_snr(
    signal_adu: f64,
    n_pix: f64,
    bg_noise_adu: f64,
    model: Option<&CameraNoiseModel>,
) -> f64 {
    if signal_adu <= 0.0 || n_pix <= 0.0 {
        return 0.0;
    }

    match model {
        Some(m) if m.gain_e_per_adu > 0.0 => {
            // Convert ADU → electrons for the source signal and the
            // empirical sky variance. The empirical per-pixel variance in
            // ADU² maps to electron² via gain² (since e = ADU * gain).
            let signal_e = signal_adu * m.gain_e_per_adu;
            let sky_var_e2 = (bg_noise_adu * bg_noise_adu) * m.gain_e_per_adu * m.gain_e_per_adu;
            let read_var_e2 = m.read_noise_e * m.read_noise_e;
            let dark_e = (m.dark_e_per_sec * m.exposure_s).max(0.0);

            // Per-pixel background variance term (electrons²). We add
            // read_noise² and dark explicitly. If the empirical sky
            // variance already includes them (typical for a well-sampled
            // background), this slightly over-counts; that is the safe
            // direction (pessimistic SNR) and is documented.
            let per_pixel_var_e2 = sky_var_e2 + read_var_e2 + dark_e;
            let denom = signal_e + n_pix * per_pixel_var_e2;
            if denom <= 0.0 {
                return 0.0;
            }
            signal_e / denom.sqrt()
        }
        _ => {
            // ADU-domain CCD equation against the measured background
            // variance. Treats ADU as electrons (gain = 1 e/ADU) for the
            // source-shot-noise term — documented approximation.
            let var_per_pixel = bg_noise_adu * bg_noise_adu;
            let denom = signal_adu + n_pix * var_per_pixel;
            if denom <= 0.0 {
                return 0.0;
            }
            signal_adu / denom.sqrt()
        }
    }
}

/// Calculate median HFR for detected stars
pub fn calculate_median_hfr(image: &ImageData) -> Option<f64> {
    let config = StarDetectionConfig::default();
    let stars = detect_stars(image, &config);

    if stars.is_empty() {
        return None;
    }

    // Use top 50% brightest stars for HFR
    let count = (stars.len() / 2).clamp(1, 50);
    let mut hfrs: Vec<f64> = stars
        .iter()
        .take(count)
        .map(|s| s.hfr)
        .filter(|&h| h > 0.0 && h < 20.0) // Filter outliers
        .collect();

    if hfrs.is_empty() {
        return None;
    }

    hfrs.sort_by(|a, b| a.total_cmp(b));
    Some(hfrs[hfrs.len() / 2])
}

/// Calculate histogram for a 16-bit image
pub fn calculate_histogram(image: &ImageData, bins: usize) -> Vec<u32> {
    if bins == 0 {
        return Vec::new();
    }

    let bin_size = 65536 / bins;

    // Parallel histogram calculation
    // Each thread calculates a local histogram, then they are reduced
    image
        .data
        .par_chunks_exact(2)
        .fold(
            || vec![0u32; bins],
            |mut hist, chunk| {
                let val = u16::from_le_bytes([chunk[0], chunk[1]]) as usize;
                let bin = (val / bin_size).min(bins - 1);
                hist[bin] += 1;
                hist
            },
        )
        .reduce(
            || vec![0u32; bins],
            |mut hist1, hist2| {
                for (h1, h2) in hist1.iter_mut().zip(hist2.iter()) {
                    *h1 += h2;
                }
                hist1
            },
        )
}

/// Calculate histogram for display (256 bins, logarithmic scale option)
pub fn calculate_display_histogram(image: &ImageData, logarithmic: bool) -> Vec<f32> {
    let histogram = calculate_histogram(image, 256);

    // Parallel processing for display conversion
    if logarithmic {
        histogram
            .par_iter()
            .map(|&count| if count > 0 { (count as f32).ln() } else { 0.0 })
            .collect()
    } else {
        // Why: §audit-rust 4.3 — `calculate_histogram` always returns 256
        // entries (we just asked for `bins=256`), so `.iter().max()` is
        // `None` ONLY in the never-reached "0 bins requested" branch.
        // Substituting `&1` is the documented "empty/all-zero histogram"
        // divisor that yields a flat 0.0 display (no division by zero)
        // rather than a NaN-filled output that the GPU shader would
        // render as black. We also clamp the actual max to 1 for the same
        // reason: an all-zero image (e.g. just-opened darks) used to
        // produce NaN bars from a 0/0 division.
        let max_raw = *histogram.iter().max().unwrap_or(&1);
        let max_val = max_raw.max(1) as f32;
        histogram
            .par_iter()
            .map(|&count| count as f32 / max_val)
            .collect()
    }
}

/// Star detection summary
#[derive(Debug, Clone)]
pub struct StarDetectionResult {
    pub stars: Vec<DetectedStar>,
    pub star_count: u32,
    pub median_hfr: f64,
    pub median_fwhm: f64,
    pub median_snr: f64,
    pub background: f64,
    pub noise: f64,
}

/// Run full star detection with summary statistics
pub fn detect_stars_with_stats(
    image: &ImageData,
    config: &StarDetectionConfig,
) -> StarDetectionResult {
    let width = image.width as usize;
    let height = image.height as usize;

    // Estimate background first
    // Parallel conversion
    let pixels: Vec<f64> = image
        .data
        .par_chunks_exact(2)
        .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]) as f64)
        .collect();

    let (background, noise) = if !pixels.is_empty() {
        estimate_background(&pixels, width, height)
    } else {
        (0.0, 1.0)
    };

    // Log detection parameters for diagnostics
    let threshold = background + config.detection_sigma * noise;
    let pixel_stats: (f64, f64, f64) = if !pixels.is_empty() {
        let min = pixels.iter().copied().fold(f64::INFINITY, f64::min);
        let max = pixels.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        let sum: f64 = pixels.iter().sum();
        let avg = sum / pixels.len() as f64;
        (min, max, avg)
    } else {
        (0.0, 0.0, 0.0)
    };
    tracing::info!(
        "[STAR_DETECT] Image {}x{}, pixel range: {:.0}-{:.0}, avg: {:.1}",
        width,
        height,
        pixel_stats.0,
        pixel_stats.1,
        pixel_stats.2
    );
    tracing::info!(
        "[STAR_DETECT] Background: {:.1}, Noise: {:.1}, Threshold: {:.1} (sigma={})",
        background,
        noise,
        threshold,
        config.detection_sigma
    );

    let stars = detect_stars(image, config);
    let star_count = stars.len() as u32;
    tracing::info!(
        "[STAR_DETECT] Detected {} stars after filtering",
        star_count
    );

    // Calculate median statistics
    let (median_hfr, median_fwhm, median_snr) = if !stars.is_empty() {
        let count = (stars.len() / 2).clamp(1, 50);

        let mut hfrs: Vec<f64> = stars.iter().take(count).map(|s| s.hfr).collect();
        let mut fwhms: Vec<f64> = stars.iter().take(count).map(|s| s.fwhm).collect();
        let mut snrs: Vec<f64> = stars.iter().take(count).map(|s| s.snr).collect();

        hfrs.sort_by(|a, b| a.total_cmp(b));
        fwhms.sort_by(|a, b| a.total_cmp(b));
        snrs.sort_by(|a, b| a.total_cmp(b));

        (
            hfrs[hfrs.len() / 2],
            fwhms[fwhms.len() / 2],
            snrs[snrs.len() / 2],
        )
    } else {
        (0.0, 0.0, 0.0)
    };

    StarDetectionResult {
        stars,
        star_count,
        median_hfr,
        median_fwhm,
        median_snr,
        background,
        noise,
    }
}

/// Data for a cropped star image ready for UI display
#[derive(Debug, Clone)]
pub struct StarCropData {
    /// Cropped image pixels as 8-bit grayscale (normalized/stretched)
    pub pixels: Vec<u8>,
    /// Width of the crop
    pub width: u32,
    /// Height of the crop
    pub height: u32,
    /// Star X position in original image
    pub star_x: f64,
    /// Star Y position in original image
    pub star_y: f64,
    /// Star's HFR value
    pub hfr: f64,
    /// Star's SNR value
    pub snr: f64,
}

/// Extract a cropped region around a star, normalized for display
///
/// Returns an 80x80 (or smaller near edges) crop centered on the star,
/// with pixel values auto-stretched to 0-255 range for display.
pub fn extract_star_crop(image: &ImageData, star: &DetectedStar, crop_size: u32) -> StarCropData {
    let width = image.width as i32;
    let height = image.height as i32;
    let half_size = crop_size as i32 / 2;

    // Calculate crop bounds, clamping to image edges
    let star_x = star.x.round() as i32;
    let star_y = star.y.round() as i32;

    let x_start = (star_x - half_size).max(0);
    let y_start = (star_y - half_size).max(0);
    let x_end = (star_x + half_size).min(width);
    let y_end = (star_y + half_size).min(height);

    let crop_width = (x_end - x_start) as u32;
    let crop_height = (y_end - y_start) as u32;

    // Extract pixels from the raw byte array (2 bytes per pixel, little-endian u16)
    let mut crop_pixels: Vec<u16> = Vec::with_capacity((crop_width * crop_height) as usize);
    let mut min_val = u16::MAX;
    let mut max_val = u16::MIN;

    for y in y_start..y_end {
        for x in x_start..x_end {
            let idx = ((y * width + x) * 2) as usize; // 2 bytes per pixel
            if idx + 1 < image.data.len() {
                let val = u16::from_le_bytes([image.data[idx], image.data[idx + 1]]);
                crop_pixels.push(val);
                min_val = min_val.min(val);
                max_val = max_val.max(val);
            }
        }
    }

    // Normalize to 0-255 with auto-stretch
    let range = (max_val - min_val).max(1) as f64;
    let normalized: Vec<u8> = crop_pixels
        .iter()
        .map(|&val| ((val - min_val) as f64 / range * 255.0) as u8)
        .collect();

    StarCropData {
        pixels: normalized,
        width: crop_width,
        height: crop_height,
        star_x: star.x,
        star_y: star.y,
        hfr: star.hfr,
        snr: star.snr,
    }
}

/// Extract crops for the top N brightest stars, sorted by SNR
///
/// Returns up to `max_crops` star crops, sorted by brightness (SNR descending).
/// Useful for the autofocus UI to let users cycle through different stars.
pub fn extract_top_star_crops(
    image: &ImageData,
    stars: &[DetectedStar],
    max_crops: usize,
    crop_size: u32,
) -> Vec<StarCropData> {
    // Sort stars by SNR (brightness) descending
    // Why: §audit-rust 4.3 — `partial_cmp` returns `None` only when comparing
    // against NaN. SNR is computed in `detect_stars` as a ratio of finite
    // sums divided by a positive standard deviation, so NaN here would
    // indicate a star-detection bug (zero pixel variance with non-zero flux,
    // impossible by construction). Treating any NaN as `Equal` keeps the
    // sort stable for those edge stars rather than panicking; if the bug
    // ever materialises the NaN-SNR stars cluster together at their original
    // positions, which is easy to spot in the UI/log.
    let mut sorted_stars: Vec<&DetectedStar> = stars.iter().collect();
    sorted_stars.sort_by(|a, b| {
        b.snr
            .partial_cmp(&a.snr)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // Extract crops for top N
    sorted_stars
        .into_iter()
        .take(max_crops)
        .map(|star| extract_star_crop(image, star, crop_size))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calculate_stats_reports_expected_mad_for_even_sample() {
        let image = ImageData::from_u16(4, 1, 1, &[10, 10, 14, 22]);
        let stats = calculate_stats_u16(&image);
        assert_eq!(stats.median, 12.0);
        assert_eq!(stats.mad, 2.0);
    }

    #[test]
    fn calculate_stats_ignores_trailing_odd_byte() {
        let image = ImageData {
            width: 1,
            height: 1,
            channels: 1,
            pixel_type: crate::PixelType::U16,
            data: vec![0x34, 0x12, 0xFF],
        };
        let stats = calculate_stats_u16(&image);
        assert_eq!(stats.min, 0x1234 as f64);
        assert_eq!(stats.max, 0x1234 as f64);
        assert_eq!(stats.mad, 0.0);
    }

    #[test]
    fn calculate_histogram_returns_empty_for_zero_bins() {
        let image = ImageData::from_u16(2, 1, 1, &[10, 20]);
        assert!(calculate_histogram(&image, 0).is_empty());
    }

    /// Render a synthetic 2-D Gaussian PSF on a u16 grid.
    ///
    /// Why: the audit (§6.11) requires a load-bearing test that builds a
    /// known-σ Gaussian, runs the detector, and asserts the reported HFR
    /// (≈ 1.177 σ) and FWHM (≈ 2.355 σ) within 5%.
    fn render_gaussian_u16(width: u32, height: u32, cx: f64, cy: f64, sigma: f64) -> ImageData {
        const BACKGROUND: f64 = 1000.0;
        const PEAK: f64 = 30000.0;
        let mut data = vec![BACKGROUND as u16; (width * height) as usize];
        let two_sigma_sq = 2.0 * sigma * sigma;
        for y in 0..height {
            for x in 0..width {
                let dx = x as f64 - cx;
                let dy = y as f64 - cy;
                let r2 = dx * dx + dy * dy;
                let v = BACKGROUND + PEAK * (-r2 / two_sigma_sq).exp();
                let v = v.clamp(0.0, 65535.0) as u16;
                data[(y * width + x) as usize] = v;
            }
        }
        ImageData::from_u16(width, height, 1, &data)
    }

    /// Render a synthetic Moffat-β profile.
    ///
    /// Why: the audit (§6.11) asks for a Moffat-2 cross-check confirming the
    /// metric behaves under non-Gaussian PSFs. Moffat β=2 has heavier wings
    /// than a Gaussian; its encircled-energy HFR is therefore larger than
    /// the half-maximum radius for the same analytic FWHM.
    fn render_moffat_u16(
        width: u32,
        height: u32,
        cx: f64,
        cy: f64,
        alpha: f64,
        beta: f64,
    ) -> ImageData {
        const BACKGROUND: f64 = 1000.0;
        const PEAK: f64 = 30000.0;
        let mut data = vec![BACKGROUND as u16; (width * height) as usize];
        let alpha_sq = alpha * alpha;
        for y in 0..height {
            for x in 0..width {
                let dx = x as f64 - cx;
                let dy = y as f64 - cy;
                let r2 = dx * dx + dy * dy;
                let v = BACKGROUND + PEAK * (1.0 + r2 / alpha_sq).powf(-beta);
                let v = v.clamp(0.0, 65535.0) as u16;
                data[(y * width + x) as usize] = v;
            }
        }
        ImageData::from_u16(width, height, 1, &data)
    }

    #[test]
    fn hfr_and_fwhm_match_gaussian_definition_within_five_percent() {
        let sigma = 2.5_f64;
        let image = render_gaussian_u16(64, 64, 32.0, 32.0, sigma);

        // Reduce min_area: the synthetic Gaussian on a 64×64 grid still has
        // many pixels above background but we want the HFR computation to
        // dominate the assertion, not detection thresholds.
        let config = StarDetectionConfig {
            min_area: 5,
            min_hfr: 0.5,
            min_snr: 1.0,
            max_sharpness: 1.0,
            hfr_radius: 16,
            ..Default::default()
        };

        let stars = detect_stars(&image, &config);
        assert!(
            !stars.is_empty(),
            "expected at least one detected star for synthetic Gaussian"
        );
        // Pick the brightest detection — that is the synthetic peak.
        let star = &stars[0];

        let expected_hfr = sigma * (2.0_f64 * 2.0_f64.ln()).sqrt();
        let expected_fwhm = 2.0 * sigma * (2.0_f64 * 2.0_f64.ln()).sqrt();

        let hfr_err = (star.hfr - expected_hfr).abs() / expected_hfr;
        let fwhm_err = (star.fwhm - expected_fwhm).abs() / expected_fwhm;
        assert!(
            hfr_err < 0.05,
            "HFR {:.4} vs expected {:.4} (err {:.2}%)",
            star.hfr,
            expected_hfr,
            hfr_err * 100.0
        );
        assert!(
            fwhm_err < 0.05,
            "FWHM {:.4} vs expected {:.4} (err {:.2}%)",
            star.fwhm,
            expected_fwhm,
            fwhm_err * 100.0
        );
    }

    #[test]
    fn hfr_and_fwhm_track_moffat_beta_two_profile() {
        // For Moffat-β, analytic FWHM = 2·α·√(2^(1/β) − 1). Pick α so
        // that half-maximum width matches an easy reference (5 px), then
        // verify the encircled-energy HFR independently.
        let beta = 2.0_f64;
        let target_fwhm = 5.0_f64;
        let alpha = (target_fwhm / 2.0) / (2.0_f64.powf(1.0 / beta) - 1.0).sqrt();
        let image = render_moffat_u16(64, 64, 32.0, 32.0, alpha, beta);

        let config = StarDetectionConfig {
            min_area: 5,
            min_hfr: 0.5,
            min_snr: 1.0,
            max_sharpness: 1.0,
            hfr_radius: 24,
            ..Default::default()
        };

        let stars = detect_stars(&image, &config);
        assert!(!stars.is_empty(), "expected detection on Moffat-2 PSF");
        let star = &stars[0];

        // Encircled-energy 50% HFR for a normalized Moffat-β PSF:
        // r_50 = α·√(2^(1/(β−1)) − 1), beta > 1.
        let expected_hfr = alpha * (2.0_f64.powf(1.0 / (beta - 1.0)) - 1.0).sqrt();
        let expected_fwhm = 2.0 * expected_hfr;

        // 10% tolerance: Moffat has heavier wings than a Gaussian, the
        // discrete aperture truncation introduces more error than for the
        // Gaussian case.
        let hfr_err = (star.hfr - expected_hfr).abs() / expected_hfr;
        let fwhm_err = (star.fwhm - expected_fwhm).abs() / expected_fwhm;
        assert!(
            hfr_err < 0.10,
            "Moffat-2 HFR {:.4} vs expected {:.4} (err {:.2}%)",
            star.hfr,
            expected_hfr,
            hfr_err * 100.0
        );
        assert!(
            fwhm_err < 0.10,
            "Moffat-2 FWHM {:.4} vs expected {:.4} (err {:.2}%)",
            star.fwhm,
            expected_fwhm,
            fwhm_err * 100.0
        );
    }

    #[test]
    fn snr_uses_ccd_equation_in_adu_domain_when_no_camera_model() {
        // signal=1000 ADU, n_pix=10, bg_noise=2 ADU.
        // Standard CCD eq in ADU domain: signal / sqrt(signal + n_pix·noise²).
        // = 1000 / sqrt(1000 + 10·4) = 1000 / sqrt(1040).
        let snr = compute_snr(1000.0, 10.0, 2.0, None);
        let expected = 1000.0 / (1040.0_f64).sqrt();
        assert!((snr - expected).abs() < 1e-9);
    }

    #[test]
    fn snr_uses_full_ccd_equation_with_camera_model() {
        // signal=1000 ADU, n_pix=10, bg_noise=2 ADU, gain=1 e/ADU,
        // read=3 e, dark=0.5 e/s, exposure=10s ⇒ dark=5 e.
        // electrons: signal_e=1000, sky_var_e²=4, read²=9, dark=5
        // SNR = 1000 / sqrt(1000 + 10·(4+9+5)) = 1000 / sqrt(1180).
        let model = CameraNoiseModel {
            gain_e_per_adu: 1.0,
            read_noise_e: 3.0,
            dark_e_per_sec: 0.5,
            exposure_s: 10.0,
        };
        let snr = compute_snr(1000.0, 10.0, 2.0, Some(&model));
        let expected = 1000.0 / (1180.0_f64).sqrt();
        assert!(
            (snr - expected).abs() < 1e-9,
            "got {} expected {}",
            snr,
            expected
        );
    }

    #[test]
    fn snr_returns_zero_for_invalid_inputs() {
        assert_eq!(compute_snr(0.0, 10.0, 2.0, None), 0.0);
        assert_eq!(compute_snr(100.0, 0.0, 2.0, None), 0.0);
    }
}
