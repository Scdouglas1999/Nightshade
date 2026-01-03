//! Image stretching algorithms for display

use crate::ImageData;

/// Stretch parameters
#[derive(Debug, Clone)]
pub struct StretchParams {
    pub shadows: f64,      // Black point (0-1)
    pub highlights: f64,   // White point (0-1)
    pub midtones: f64,     // Midtone balance (0-1)
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
pub fn auto_stretch_stf(image: &ImageData) -> StretchParams {
    // STF (Screen Transfer Function) algorithm
    // Similar to PixInsight's auto stretch
    
    if image.data.is_empty() {
        return StretchParams::default();
    }

    // Convert to f64 normalized values
    let pixels: Vec<f64> = image.data
        .chunks_exact(2)
        .map(|chunk| {
            let val = u16::from_le_bytes([chunk[0], chunk[1]]);
            val as f64 / 65535.0
        })
        .collect();

    if pixels.is_empty() {
        return StretchParams::default();
    }

    // Calculate median and MAD
    let mut sorted = pixels.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    
    let median = sorted[sorted.len() / 2];
    
    let mut deviations: Vec<f64> = sorted.iter()
        .map(|&p| (p - median).abs())
        .collect();
    deviations.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mad = deviations[deviations.len() / 2] * 1.4826; // Scale factor for normal distribution

    // STF parameters
    let c0 = median.max(0.0);
    let c1 = 1.0_f64.min(median + 2.8 * mad);
    
    // Calculate shadows clip
    let shadows = (median - 2.8 * mad).max(0.0);
    
    // Calculate midtone balance
    let m = if c1 > c0 {
        mtf((median - c0) / (c1 - c0), 0.25)
    } else {
        0.5
    };

    StretchParams {
        shadows,
        highlights: c1,
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
        num / den
    }
}

/// Apply stretch to an image, returning 8-bit output for display
pub fn apply_stretch(image: &ImageData, params: &StretchParams) -> Vec<u8> {
    let range = params.highlights - params.shadows;
    if range <= 0.0 {
        return vec![0u8; image.width as usize * image.height as usize];
    }

    image.data
        .chunks_exact(2)
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
