//! Image statistics and star detection

use crate::ImageData;

/// Statistics for an image
#[derive(Debug, Clone, Default)]
pub struct ImageStats {
    pub min: f64,
    pub max: f64,
    pub mean: f64,
    pub median: f64,
    pub std_dev: f64,
    pub mad: f64,  // Median Absolute Deviation
}

/// Calculate statistics for a 16-bit image
pub fn calculate_stats_u16(image: &ImageData) -> ImageStats {
    if image.data.is_empty() {
        return ImageStats::default();
    }

    let pixels: Vec<u16> = image.data
        .chunks_exact(2)
        .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
        .collect();

    if pixels.is_empty() {
        return ImageStats::default();
    }

    let mut min = u16::MAX;
    let mut max = u16::MIN;
    let mut sum: f64 = 0.0;

    for &pixel in &pixels {
        min = min.min(pixel);
        max = max.max(pixel);
        sum += pixel as f64;
    }

    let count = pixels.len() as f64;
    let mean = sum / count;

    let variance: f64 = pixels.iter()
        .map(|&p| {
            let diff = p as f64 - mean;
            diff * diff
        })
        .sum::<f64>() / count;
    let std_dev = variance.sqrt();

    let mut sorted = pixels.clone();
    sorted.sort_unstable();
    let median = if sorted.len() % 2 == 0 {
        let mid = sorted.len() / 2;
        (sorted[mid - 1] as f64 + sorted[mid] as f64) / 2.0
    } else {
        sorted[sorted.len() / 2] as f64
    };

    let mut deviations: Vec<f64> = sorted.iter()
        .map(|&p| (p as f64 - median).abs())
        .collect();
    deviations.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mad = if deviations.len() % 2 == 0 {
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
}

impl Default for StarDetectionConfig {
    fn default() -> Self {
        Self {
            detection_sigma: 3.0,
            min_area: 5,
            max_area: 10000,
            max_eccentricity: 0.8,
            saturation_limit: 60000,
            hfr_radius: 20,
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

    // Convert to f64 array
    let pixels: Vec<f64> = image.data
        .chunks_exact(2)
        .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]) as f64)
        .collect();

    // Estimate background using sigma-clipped median
    let (background, noise) = estimate_background(&pixels, width, height);
    
    // Detection threshold
    let threshold = background + config.detection_sigma * noise;
    
    // Find candidate pixels above threshold
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
            let is_max = 
                val >= pixels[idx - 1] &&
                val >= pixels[idx + 1] &&
                val >= pixels[idx - width] &&
                val >= pixels[idx + width] &&
                val >= pixels[idx - width - 1] &&
                val >= pixels[idx - width + 1] &&
                val >= pixels[idx + width - 1] &&
                val >= pixels[idx + width + 1];
            
            if !is_max {
                continue;
            }
            
            // Skip saturated stars
            if val > config.saturation_limit as f64 {
                continue;
            }
            
            // Extract star region and measure
            if let Some(star) = measure_star(
                &pixels, 
                width, 
                height, 
                x, 
                y, 
                background, 
                noise,
                config,
                &mut visited
            ) {
                // Filter by area
                let area = star.flux / (star.peak - background);
                if area >= config.min_area as f64 && area <= config.max_area as f64 {
                    stars.push(star);
                }
            }
        }
    }
    
    // Sort by flux (brightest first)
    stars.sort_by(|a, b| b.flux.partial_cmp(&a.flux).unwrap());
    
    stars
}

/// Estimate background level and noise using sigma clipping
fn estimate_background(pixels: &[f64], width: usize, height: usize) -> (f64, f64) {
    // Sample every 4th pixel for speed
    let mut samples: Vec<f64> = pixels.iter()
        .step_by(4)
        .copied()
        .collect();
    
    if samples.is_empty() {
        return (0.0, 1.0);
    }
    
    // Sigma clipping iterations
    for _ in 0..3 {
        samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let median = samples[samples.len() / 2];
        
        let mad: f64 = samples.iter()
            .map(|&v| (v - median).abs())
            .sum::<f64>() / samples.len() as f64;
        let sigma = mad * 1.4826;
        
        let lower = median - 3.0 * sigma;
        let upper = median + 3.0 * sigma;
        
        samples.retain(|&v| v >= lower && v <= upper);
        
        if samples.is_empty() {
            return (median, sigma);
        }
    }
    
    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let background = samples[samples.len() / 2];
    
    // Estimate noise from remaining samples
    let variance: f64 = samples.iter()
        .map(|&v| (v - background).powi(2))
        .sum::<f64>() / samples.len() as f64;
    let noise = variance.sqrt();
    
    (background, noise.max(1.0))
}

/// Measure a star's properties
fn measure_star(
    pixels: &[f64],
    width: usize,
    height: usize,
    cx: usize,
    cy: usize,
    background: f64,
    noise: f64,
    config: &StarDetectionConfig,
    visited: &mut [bool],
) -> Option<DetectedStar> {
    let radius = config.hfr_radius as i32;
    
    // Calculate centroid using intensity-weighted center
    let mut sum_x = 0.0;
    let mut sum_y = 0.0;
    let mut sum_flux = 0.0;
    let mut peak = 0.0_f64;
    
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let x = cx as i32 + dx;
            let y = cy as i32 + dy;
            
            if x < 0 || y < 0 || x >= width as i32 || y >= height as i32 {
                continue;
            }
            
            let idx = y as usize * width + x as usize;
            let val = pixels[idx] - background;
            
            if val > 0.0 {
                sum_x += x as f64 * val;
                sum_y += y as f64 * val;
                sum_flux += val;
                peak = peak.max(pixels[idx]);
                visited[idx] = true;
            }
        }
    }
    
    if sum_flux <= 0.0 {
        return None;
    }
    
    let centroid_x = sum_x / sum_flux;
    let centroid_y = sum_y / sum_flux;
    
    // Calculate HFR (Half Flux Radius)
    let hfr = calculate_hfr_at_point(pixels, width, height, centroid_x, centroid_y, background, radius);
    
    // Calculate FWHM from HFR
    // For Gaussian profile: FWHM = 2 * sqrt(2 * ln(2)) * σ
    // where HFR ≈ σ, giving FWHM ≈ 2.355 * HFR
    const FWHM_TO_HFR_RATIO: f64 = 2.3548200450309493;  // 2 * sqrt(2 * ln(2))
    let fwhm = hfr * FWHM_TO_HFR_RATIO;
    
    // Calculate SNR
    let snr = sum_flux / (noise * (sum_flux / (peak - background)).sqrt());
    
    Some(DetectedStar {
        x: centroid_x,
        y: centroid_y,
        flux: sum_flux,
        hfr,
        fwhm,
        peak,
        background,
        snr,
    })
}

/// Calculate HFR at a specific point
fn calculate_hfr_at_point(
    pixels: &[f64],
    width: usize,
    height: usize,
    cx: f64,
    cy: f64,
    background: f64,
    radius: i32,
) -> f64 {
    let mut total_flux = 0.0;
    let mut weighted_radius_sum = 0.0;
    
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let x = (cx as i32 + dx).max(0).min(width as i32 - 1) as usize;
            let y = (cy as i32 + dy).max(0).min(height as i32 - 1) as usize;
            
            let val = (pixels[y * width + x] - background).max(0.0);
            let dist = ((dx as f64).powi(2) + (dy as f64).powi(2)).sqrt();
            
            total_flux += val;
            weighted_radius_sum += val * dist;
        }
    }
    
    if total_flux > 0.0 {
        weighted_radius_sum / total_flux
    } else {
        0.0
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
    let count = (stars.len() / 2).max(1).min(50);
    let mut hfrs: Vec<f64> = stars.iter()
        .take(count)
        .map(|s| s.hfr)
        .filter(|&h| h > 0.0 && h < 20.0)  // Filter outliers
        .collect();
    
    if hfrs.is_empty() {
        return None;
    }
    
    hfrs.sort_by(|a, b| a.partial_cmp(b).unwrap());
    Some(hfrs[hfrs.len() / 2])
}

/// Calculate histogram for a 16-bit image
pub fn calculate_histogram(image: &ImageData, bins: usize) -> Vec<u32> {
    let mut histogram = vec![0u32; bins];
    let bin_size = 65536 / bins;
    
    for chunk in image.data.chunks_exact(2) {
        let val = u16::from_le_bytes([chunk[0], chunk[1]]) as usize;
        let bin = (val / bin_size).min(bins - 1);
        histogram[bin] += 1;
    }
    
    histogram
}

/// Calculate histogram for display (256 bins, logarithmic scale option)
pub fn calculate_display_histogram(image: &ImageData, logarithmic: bool) -> Vec<f32> {
    let histogram = calculate_histogram(image, 256);
    
    if logarithmic {
        histogram.iter()
            .map(|&count| if count > 0 { (count as f32).ln() } else { 0.0 })
            .collect()
    } else {
        let max_val = *histogram.iter().max().unwrap_or(&1) as f32;
        histogram.iter()
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
pub fn detect_stars_with_stats(image: &ImageData, config: &StarDetectionConfig) -> StarDetectionResult {
    let width = image.width as usize;
    let height = image.height as usize;
    
    // Estimate background first
    let pixels: Vec<f64> = image.data
        .chunks_exact(2)
        .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]) as f64)
        .collect();
    
    let (background, noise) = if !pixels.is_empty() {
        estimate_background(&pixels, width, height)
    } else {
        (0.0, 1.0)
    };
    
    let stars = detect_stars(image, config);
    let star_count = stars.len() as u32;
    
    // Calculate median statistics
    let (median_hfr, median_fwhm, median_snr) = if !stars.is_empty() {
        let count = (stars.len() / 2).max(1).min(50);
        
        let mut hfrs: Vec<f64> = stars.iter().take(count).map(|s| s.hfr).collect();
        let mut fwhms: Vec<f64> = stars.iter().take(count).map(|s| s.fwhm).collect();
        let mut snrs: Vec<f64> = stars.iter().take(count).map(|s| s.snr).collect();
        
        hfrs.sort_by(|a, b| a.partial_cmp(b).unwrap());
        fwhms.sort_by(|a, b| a.partial_cmp(b).unwrap());
        snrs.sort_by(|a, b| a.partial_cmp(b).unwrap());
        
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
