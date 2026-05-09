//! Image stretching algorithms for display

use crate::ImageData;
use rayon::prelude::*;

/// Stretch parameters
#[derive(Debug, Clone)]
pub struct StretchParams {
    pub shadows: f64,    // Black point (0-1)
    pub highlights: f64, // White point (0-1)
    pub midtones: f64,   // Midtone balance (0-1)
}

impl Default for StretchParams {
    fn default() -> Self {
        Self {
            shadows: 0.0,
            highlights: 1.0,
            midtones: 0.5,
        }
    }
}

/// Auto stretch method
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutoStretchMethod {
    /// Screen Transfer Function (similar to PixInsight STF)
    Stf,
    /// Histogram based stretch
    Histogram,
    /// Asinh stretch (preserves star colors)
    Asinh,
}

/// Calculate auto stretch parameters using STF method
/// Modified for raw astronomical data - uses percentile-based clipping
pub fn auto_stretch_stf(image: &ImageData) -> StretchParams {
    // STF (Screen Transfer Function) algorithm
    // Modified for raw astronomical images with dark backgrounds

    if image.data.is_empty() {
        return StretchParams::default();
    }

    // Convert to f64 normalized values in parallel
    let pixels: Vec<f64> = image
        .data
        .par_chunks_exact(2)
        .map(|chunk| {
            let val = u16::from_le_bytes([chunk[0], chunk[1]]);
            val as f64 / 65535.0
        })
        .collect();

    if pixels.is_empty() {
        return StretchParams::default();
    }

    // Calculate percentiles and median
    let mut sorted = pixels.clone();
    // Use unstable parallel sort for speed
    sorted.par_sort_unstable_by(|a, b| a.total_cmp(b));

    let len = sorted.len();
    let median = sorted[len / 2];

    // Use percentile-based clipping for raw astronomical data
    // This is more robust than MAD-based for images with bright stars
    let shadow_percentile = 0.001; // 0.1% - clip very dark pixels
    let highlight_percentile = 0.999; // 99.9% - preserve bright stars

    let shadow_idx = ((len as f64) * shadow_percentile) as usize;
    let highlight_idx = ((len as f64) * highlight_percentile).min((len - 1) as f64) as usize;

    let shadows = sorted[shadow_idx];
    let highlights = sorted[highlight_idx];

    // Ensure valid range
    let (shadows, highlights) = if highlights <= shadows {
        // Fallback: use full range
        (0.0, 1.0)
    } else {
        (shadows, highlights)
    };

    // Calculate midtone balance based on median position in the range
    let range = highlights - shadows;
    let median_pos = if range > 0.0 {
        ((median - shadows) / range).clamp(0.0, 1.0)
    } else {
        0.5
    };

    // Apply MTF to get a balanced midtone (target 0.25 for typical astro images)
    let m = if median_pos > 0.0 && median_pos < 1.0 {
        mtf(median_pos, 0.25)
    } else {
        0.5
    };

    StretchParams {
        shadows,
        highlights,
        midtones: m,
    }
}

/// Midtone Transfer Function
fn mtf(x: f64, m: f64) -> f64 {
    if x <= 0.0 {
        0.0
    } else if x >= 1.0 {
        1.0
    } else if x == m {
        0.5
    } else {
        let num = (m - 1.0) * x;
        let den = (2.0 * m - 1.0) * x - m;
        if den.abs() < f64::EPSILON {
            return 0.5;
        }
        num / den
    }
}

/// Apply stretch to an image, returning 8-bit output for display
pub fn apply_stretch(image: &ImageData, params: &StretchParams) -> Vec<u8> {
    let range = params.highlights - params.shadows;
    if range <= 0.0 {
        return vec![0u8; image.width as usize * image.height as usize];
    }

    // Parallel processing for applying stretch
    image
        .data
        .par_chunks_exact(2)
        .map(|chunk| {
            let val = u16::from_le_bytes([chunk[0], chunk[1]]);
            let normalized = val as f64 / 65535.0;

            // Apply shadows/highlights
            let stretched = ((normalized - params.shadows) / range).clamp(0.0, 1.0);

            // Apply midtone curve
            let curved = mtf(stretched, params.midtones);

            // Convert to 8-bit
            (curved * 255.0) as u8
        })
        .collect()
}

/// Apply stretch to RGB image (3 channels), returning 8-bit RGB output for display
/// Input: RGB16 data (width * height * 3 u16 values)
/// Output: RGB8 data (width * height * 3 u8 values)
pub fn apply_stretch_rgb(
    rgb_data: &[u16],
    width: u32,
    height: u32,
    params: &StretchParams,
) -> Vec<u8> {
    let range = params.highlights - params.shadows;
    if range <= 0.0 {
        return vec![0u8; (width * height * 3) as usize];
    }

    // Process RGB channels in parallel
    rgb_data
        .par_iter()
        .map(|&val| {
            let normalized = val as f64 / 65535.0;

            // Apply shadows/highlights
            let stretched = ((normalized - params.shadows) / range).clamp(0.0, 1.0);

            // Apply midtone curve
            let curved = mtf(stretched, params.midtones);

            // Convert to 8-bit
            (curved * 255.0) as u8
        })
        .collect()
}

/// Calculate auto stretch parameters for RGB image (per-channel)
/// Returns (R params, G params, B params)
pub fn auto_stretch_rgb(
    rgb_data: &[u16],
    width: u32,
    height: u32,
) -> (StretchParams, StretchParams, StretchParams) {
    let pixel_count = (width * height) as usize;

    if rgb_data.len() != pixel_count * 3 {
        return (
            StretchParams::default(),
            StretchParams::default(),
            StretchParams::default(),
        );
    }

    // Separate RGB channels
    let mut r_channel = Vec::with_capacity(pixel_count);
    let mut g_channel = Vec::with_capacity(pixel_count);
    let mut b_channel = Vec::with_capacity(pixel_count);

    for i in 0..pixel_count {
        r_channel.push(rgb_data[i * 3]);
        g_channel.push(rgb_data[i * 3 + 1]);
        b_channel.push(rgb_data[i * 3 + 2]);
    }

    // Calculate stretch params for each channel
    let r_params = auto_stretch_channel(&r_channel);
    let g_params = auto_stretch_channel(&g_channel);
    let b_params = auto_stretch_channel(&b_channel);

    (r_params, g_params, b_params)
}

/// Calculate auto stretch for a single channel
/// Modified for raw astronomical data - uses percentile-based clipping
fn auto_stretch_channel(channel_data: &[u16]) -> StretchParams {
    if channel_data.is_empty() {
        return StretchParams::default();
    }

    // Convert to f64 normalized values
    let pixels: Vec<f64> = channel_data
        .par_iter()
        .map(|&val| val as f64 / 65535.0)
        .collect();

    // Calculate percentiles and median
    let mut sorted = pixels.clone();
    sorted.par_sort_unstable_by(|a, b| a.total_cmp(b));

    let len = sorted.len();
    let median = sorted[len / 2];

    // Use percentile-based clipping for raw astronomical data
    let shadow_percentile = 0.001; // 0.1%
    let highlight_percentile = 0.999; // 99.9%

    let shadow_idx = ((len as f64) * shadow_percentile) as usize;
    let highlight_idx = ((len as f64) * highlight_percentile).min((len - 1) as f64) as usize;

    let shadows = sorted[shadow_idx];
    let highlights = sorted[highlight_idx];

    // Ensure valid range
    let (shadows, highlights) = if highlights <= shadows {
        (0.0, 1.0)
    } else {
        (shadows, highlights)
    };

    // Calculate midtone balance
    let range = highlights - shadows;
    let median_pos = if range > 0.0 {
        ((median - shadows) / range).clamp(0.0, 1.0)
    } else {
        0.5
    };

    let m = if median_pos > 0.0 && median_pos < 1.0 {
        mtf(median_pos, 0.25)
    } else {
        0.5
    };

    StretchParams {
        shadows,
        highlights,
        midtones: m,
    }
}
