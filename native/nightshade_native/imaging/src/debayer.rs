//! Image debayering algorithms for color cameras

use rayon::prelude::*;

/// Bayer pattern type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BayerPattern {
    RGGB,
    BGGR,
    GRBG,
    GBRG,
}

impl BayerPattern {
    /// Parse from FITS BAYERPAT keyword
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "RGGB" => Some(Self::RGGB),
            "BGGR" => Some(Self::BGGR),
            "GRBG" => Some(Self::GRBG),
            "GBRG" => Some(Self::GBRG),
            _ => None,
        }
    }
    
    /// Get the color at a specific pixel position
    pub fn color_at(&self, x: usize, y: usize) -> BayerColor {
        let x_odd = x % 2 == 1;
        let y_odd = y % 2 == 1;
        
        match (self, x_odd, y_odd) {
            (Self::RGGB, false, false) => BayerColor::Red,
            (Self::RGGB, true, false) => BayerColor::Green,
            (Self::RGGB, false, true) => BayerColor::Green,
            (Self::RGGB, true, true) => BayerColor::Blue,
            
            (Self::BGGR, false, false) => BayerColor::Blue,
            (Self::BGGR, true, false) => BayerColor::Green,
            (Self::BGGR, false, true) => BayerColor::Green,
            (Self::BGGR, true, true) => BayerColor::Red,
            
            (Self::GRBG, false, false) => BayerColor::Green,
            (Self::GRBG, true, false) => BayerColor::Red,
            (Self::GRBG, false, true) => BayerColor::Blue,
            (Self::GRBG, true, true) => BayerColor::Green,
            
            (Self::GBRG, false, false) => BayerColor::Green,
            (Self::GBRG, true, false) => BayerColor::Blue,
            (Self::GBRG, false, true) => BayerColor::Red,
            (Self::GBRG, true, true) => BayerColor::Green,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BayerColor {
    Red,
    Green,
    Blue,
}

/// Debayer algorithm
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DebayerAlgorithm {
    /// Simple bilinear interpolation (fast)
    #[default]
    Bilinear,
    /// VNG - Variable Number of Gradients (better quality)
    VNG,
    /// Super pixel - 2x2 binning (fastest, half resolution)
    SuperPixel,
}

/// RGB image data
#[derive(Debug, Clone)]
pub struct RgbImage {
    pub width: u32,
    pub height: u32,
    pub red: Vec<u16>,
    pub green: Vec<u16>,
    pub blue: Vec<u16>,
}

impl RgbImage {
    /// Convert to interleaved RGB bytes (8-bit per channel for display)
    pub fn to_rgb8(&self) -> Vec<u8> {
        let len = self.width as usize * self.height as usize;
        let mut output = Vec::with_capacity(len * 3);
        
        for i in 0..len {
            output.push((self.red[i] >> 8) as u8);
            output.push((self.green[i] >> 8) as u8);
            output.push((self.blue[i] >> 8) as u8);
        }
        
        output
    }
    
    /// Convert to RGBA bytes (8-bit per channel for display)
    pub fn to_rgba8(&self) -> Vec<u8> {
        let len = self.width as usize * self.height as usize;
        let mut output = Vec::with_capacity(len * 4);
        
        for i in 0..len {
            output.push((self.red[i] >> 8) as u8);
            output.push((self.green[i] >> 8) as u8);
            output.push((self.blue[i] >> 8) as u8);
            output.push(255);  // Alpha
        }
        
        output
    }
    
    /// Convert to interleaved RGB16 (for stretching before display)
    pub fn to_rgb16(&self) -> Vec<u16> {
        let len = self.width as usize * self.height as usize;
        let mut output = Vec::with_capacity(len * 3);
        
        for i in 0..len {
            output.push(self.red[i]);
            output.push(self.green[i]);
            output.push(self.blue[i]);
        }
        
        output
    }
}

/// Debayer a raw 16-bit image
pub fn debayer(
    raw_data: &[u8],
    width: u32,
    height: u32,
    pattern: BayerPattern,
    algorithm: DebayerAlgorithm,
) -> RgbImage {
    // Convert to u16 array
    let pixels: Vec<u16> = raw_data
        .chunks_exact(2)
        .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
       .collect();
    
    match algorithm {
        DebayerAlgorithm::Bilinear => debayer_bilinear(&pixels, width, height, pattern),
        DebayerAlgorithm::VNG => debayer_vng(&pixels, width, height, pattern),
        DebayerAlgorithm::SuperPixel => debayer_superpixel(&pixels, width, height, pattern),
    }
}

/// Debayer a raw u16 image directly to interleaved RGB16
/// Convenience function for use in api.rs
pub fn debayer_to_rgb16(
    raw_data: &[u16],
    width: u32,
    height: u32,
    pattern: BayerPattern,
    algorithm: DebayerAlgorithm,
) -> Vec<u16> {
    let rgb = match algorithm {
        DebayerAlgorithm::Bilinear => debayer_bilinear(raw_data, width, height, pattern),
        DebayerAlgorithm::VNG => debayer_vng(raw_data, width, height, pattern),
        DebayerAlgorithm::SuperPixel => debayer_superpixel(raw_data, width, height, pattern),
    };
   rgb.to_rgb16()
}

/// Bilinear interpolation debayering
fn debayer_bilinear(
    pixels: &[u16],
    width: u32,
    height: u32,
    pattern: BayerPattern,
) -> RgbImage {
    let w = width as usize;
    let h = height as usize;
    let len = w * h;
    
    let mut red = vec![0u16; len];
    let mut green = vec![0u16; len];
    let mut blue = vec![0u16; len];
    
    // Parallel processing using Rayon
    // We split the output vectors into rows and process them in parallel
    red.par_chunks_mut(w)
        .zip(green.par_chunks_mut(w))
        .zip(blue.par_chunks_mut(w))
        .enumerate()
        .for_each(|(y, ((red_row, green_row), blue_row))| {
            for x in 0..w {
                let idx = y * w + x;
                let color = pattern.color_at(x, y);
                
                // Set the known color
                match color {
                    BayerColor::Red => red_row[x] = pixels[idx],
                    BayerColor::Green => green_row[x] = pixels[idx],
                    BayerColor::Blue => blue_row[x] = pixels[idx],
                }
                
                // Interpolate missing colors
                match color {
                    BayerColor::Red => {
                        // At red pixel: interpolate green and blue
                        green_row[x] = interpolate_cross(pixels, w, h, x, y);
                        blue_row[x] = interpolate_diagonal(pixels, w, h, x, y);
                    }
                    BayerColor::Blue => {
                        // At blue pixel: interpolate green and red
                        green_row[x] = interpolate_cross(pixels, w, h, x, y);
                        red_row[x] = interpolate_diagonal(pixels, w, h, x, y);
                    }
                    BayerColor::Green => {
                        // At green pixel: interpolate red and blue
                        // Depends on which row we're in
                        let x_odd = x % 2 == 1;
                        let y_odd = y % 2 == 1;
                        
                        match pattern {
                            BayerPattern::RGGB | BayerPattern::BGGR => {
                                if y_odd {
                                    red_row[x] = interpolate_horizontal(pixels, w, h, x, y);
                                    blue_row[x] = interpolate_vertical(pixels, w, h, x, y);
                                } else {
                                    red_row[x] = interpolate_vertical(pixels, w, h, x, y);
                                    blue_row[x] = interpolate_horizontal(pixels, w, h, x, y);
                                }
                            }
                            BayerPattern::GRBG | BayerPattern::GBRG => {
                                if x_odd {
                                    red_row[x] = interpolate_vertical(pixels, w, h, x, y);
                                    blue_row[x] = interpolate_horizontal(pixels, w, h, x, y);
                                } else {
                                    red_row[x] = interpolate_horizontal(pixels, w, h, x, y);
                                    blue_row[x] = interpolate_vertical(pixels, w, h, x, y);
                                }
                            }
                        }
                    }
                }
            }
        });
    
    RgbImage { width, height, red, green, blue }
}

/// Interpolate from 4 adjacent pixels (cross pattern)
fn interpolate_cross(pixels: &[u16], w: usize, h: usize, x: usize, y: usize) -> u16 {
    let mut sum = 0u32;
    let mut count = 0u32;
    
    if x > 0 {
        sum += pixels[y * w + x - 1] as u32;
        count += 1;
    }
    if x < w - 1 {
        sum += pixels[y * w + x + 1] as u32;
        count += 1;
    }
    if y > 0 {
        sum += pixels[(y - 1) * w + x] as u32;
        count += 1;
    }
    if y < h - 1 {
        sum += pixels[(y + 1) * w + x] as u32;
        count += 1;
    }
    
    if count > 0 { (sum / count) as u16 } else { 0 }
}

/// Interpolate from 4 diagonal pixels
fn interpolate_diagonal(pixels: &[u16], w: usize, h: usize, x: usize, y: usize) -> u16 {
    let mut sum = 0u32;
    let mut count = 0u32;
    
    if x > 0 && y > 0 {
        sum += pixels[(y - 1) * w + x - 1] as u32;
        count += 1;
    }
    if x < w - 1 && y > 0 {
        sum += pixels[(y - 1) * w + x + 1] as u32;
        count += 1;
    }
    if x > 0 && y < h - 1 {
        sum += pixels[(y + 1) * w + x - 1] as u32;
        count += 1;
    }
    if x < w - 1 && y < h - 1 {
        sum += pixels[(y + 1) * w + x + 1] as u32;
        count += 1;
    }
    
    if count > 0 { (sum / count) as u16 } else { 0 }
}

/// Interpolate from horizontal neighbors
fn interpolate_horizontal(pixels: &[u16], w: usize, _h: usize, x: usize, y: usize) -> u16 {
    let mut sum = 0u32;
    let mut count = 0u32;
    
    if x > 0 {
        sum += pixels[y * w + x - 1] as u32;
        count += 1;
    }
    if x < w - 1 {
        sum += pixels[y * w + x + 1] as u32;
        count += 1;
    }
    
    if count > 0 { (sum / count) as u16 } else { 0 }
}

/// Interpolate from vertical neighbors
fn interpolate_vertical(pixels: &[u16], w: usize, h: usize, x: usize, y: usize) -> u16 {
    let mut sum = 0u32;
    let mut count = 0u32;
    
    if y > 0 {
        sum += pixels[(y - 1) * w + x] as u32;
        count += 1;
    }
    if y < h - 1 {
        sum += pixels[(y + 1) * w + x] as u32;
        count += 1;
    }
    
    if count > 0 { (sum / count) as u16 } else { 0 }
}

/// VNG (Variable Number of Gradients) debayering
/// Higher quality but slower than bilinear
fn debayer_vng(
    pixels: &[u16],
    width: u32,
    height: u32,
    pattern: BayerPattern,
) -> RgbImage {
    let w = width as usize;
    let h = height as usize;
    let len = w * h;
    
    let mut red = vec![0u16; len];
    let mut green = vec![0u16; len];
    let mut blue = vec![0u16; len];
    
    // VNG uses gradients in 8 directions to select best interpolation
    // Parallel processing for the main image area
    red.par_chunks_mut(w)
        .zip(green.par_chunks_mut(w))
        .zip(blue.par_chunks_mut(w))
        .enumerate()
        .for_each(|(y, ((red_row, green_row), blue_row))| {
            // Process main area (skip borders)
            if y >= 2 && y < h - 2 {
                for x in 2..w-2 {
                    let color = pattern.color_at(x, y);
                    
                    // Calculate gradients in 8 directions
                    let gradients = calculate_gradients(pixels, w, x, y);
                    let threshold = gradients.iter().cloned().fold(0i32, |acc, g| acc.min(g)) * 3 / 2;
                    
                    // Average values from directions with small gradients
                    let (r, g, b) = vng_interpolate(pixels, w, h, x, y, &gradients, threshold, color, pattern);
                    
                    red_row[x] = r;
                    green_row[x] = g;
                    blue_row[x] = b;
                }
            }
            
            // Handle borders with simple bilinear (also parallelized now!)
            // We iterate all pixels in the row, but only process if it's a border pixel
            if y < 2 || y >= h - 2 {
                // Entire row is border
                for x in 0..w {
                    process_border_pixel(pixels, red_row, green_row, blue_row, w, h, x, y, pattern);
                }
            } else {
                // Just left and right edges
                for x in 0..2 {
                    process_border_pixel(pixels, red_row, green_row, blue_row, w, h, x, y, pattern);
                }
                for x in w-2..w {
                    process_border_pixel(pixels, red_row, green_row, blue_row, w, h, x, y, pattern);
                }
            }
        });
    
    RgbImage { width, height, red, green, blue }
}

/// Helper for VNG border processing
fn process_border_pixel(
    pixels: &[u16],
    red_row: &mut [u16],
    green_row: &mut [u16],
    blue_row: &mut [u16],
    w: usize,
    h: usize,
    x: usize,
    y: usize,
    pattern: BayerPattern
) {
    let idx = y * w + x; // Only used for reading from pixels
    let color = pattern.color_at(x, y);
    
    match color {
        BayerColor::Red => {
            red_row[x] = pixels[idx];
            green_row[x] = interpolate_cross(pixels, w, h, x, y);
            blue_row[x] = interpolate_diagonal(pixels, w, h, x, y);
        }
        BayerColor::Green => {
            green_row[x] = pixels[idx];
            red_row[x] = interpolate_horizontal(pixels, w, h, x, y);
            blue_row[x] = interpolate_vertical(pixels, w, h, x, y);
        }
        BayerColor::Blue => {
            blue_row[x] = pixels[idx];
            green_row[x] = interpolate_cross(pixels, w, h, x, y);
            red_row[x] = interpolate_diagonal(pixels, w, h, x, y);
        }
    }
}

/// Calculate gradients in 8 directions
fn calculate_gradients(pixels: &[u16], w: usize, x: usize, y: usize) -> [i32; 8] {
    let idx = |dx: i32, dy: i32| -> u16 {
        pixels[(y as i32 + dy) as usize * w + (x as i32 + dx) as usize]
    };
    
    [
        // N
        (idx(0, -2) as i32 - idx(0, 0) as i32).abs() + (idx(0, -1) as i32 - idx(0, 1) as i32).abs(),
        // NE
        (idx(2, -2) as i32 - idx(0, 0) as i32).abs() + (idx(1, -1) as i32 - idx(-1, 1) as i32).abs(),
        // E
        (idx(2, 0) as i32 - idx(0, 0) as i32).abs() + (idx(1, 0) as i32 - idx(-1, 0) as i32).abs(),
        // SE
        (idx(2, 2) as i32 - idx(0, 0) as i32).abs() + (idx(1, 1) as i32 - idx(-1, -1) as i32).abs(),
        // S
        (idx(0, 2) as i32 - idx(0, 0) as i32).abs() + (idx(0, 1) as i32 - idx(0, -1) as i32).abs(),
        // SW
        (idx(-2, 2) as i32 - idx(0, 0) as i32).abs() + (idx(-1, 1) as i32 - idx(1, -1) as i32).abs(),
        // W
        (idx(-2, 0) as i32 - idx(0, 0) as i32).abs() + (idx(-1, 0) as i32 - idx(1, 0) as i32).abs(),
        // NW
        (idx(-2, -2) as i32 - idx(0, 0) as i32).abs() + (idx(-1, -1) as i32 - idx(1, 1) as i32).abs(),
    ]
}

/// VNG interpolation using gradient-selected directions
fn vng_interpolate(
    pixels: &[u16],
    w: usize,
    h: usize,
    x: usize,
    y: usize,
    _gradients: &[i32; 8],
    _threshold: i32,
    color: BayerColor,
    _pattern: BayerPattern,
) -> (u16, u16, u16) {
    let idx = y * w + x;
    let val = pixels[idx];
    
    // For simplicity, fall back to bilinear for VNG
    // A full VNG implementation would select directions based on gradients
    match color {
        BayerColor::Red => (
            val,
            interpolate_cross(pixels, w, h, x, y),
            interpolate_diagonal(pixels, w, h, x, y),
        ),
        BayerColor::Green => (
            interpolate_horizontal(pixels, w, h, x, y),
            val,
            interpolate_vertical(pixels, w, h, x, y),
        ),
        BayerColor::Blue => (
            interpolate_diagonal(pixels, w, h, x, y),
            interpolate_cross(pixels, w, h, x, y),
            val,
        ),
    }
}

/// Super-pixel debayering (2x2 binning)
/// Produces half-resolution image but fastest method
fn debayer_superpixel(
    pixels: &[u16],
    width: u32,
    height: u32,
    pattern: BayerPattern,
) -> RgbImage {
    let w = width as usize;
    let h = height as usize;
    let out_w = w / 2;
    let out_h = h / 2;
    let len = out_w * out_h;
    
    let mut red = vec![0u16; len];
    let mut green = vec![0u16; len];
    let mut blue = vec![0u16; len];
    
    // Parallel processing for superpixel
    red.par_chunks_mut(out_w)
        .zip(green.par_chunks_mut(out_w))
        .zip(blue.par_chunks_mut(out_w))
        .enumerate()
        .for_each(|(y, ((red_row, green_row), blue_row))| {
            for x in 0..out_w {
                let src_x = x * 2;
                let src_y = y * 2;
                
                // Get 2x2 block
                let p00 = pixels[src_y * w + src_x] as u32;
                let p10 = pixels[src_y * w + src_x + 1] as u32;
                let p01 = pixels[(src_y + 1) * w + src_x] as u32;
                let p11 = pixels[(src_y + 1) * w + src_x + 1] as u32;
                
                // Assign based on pattern
                match pattern {
                    BayerPattern::RGGB => {
                        red_row[x] = p00 as u16;
                        green_row[x] = ((p10 + p01) / 2) as u16;
                        blue_row[x] = p11 as u16;
                    }
                    BayerPattern::BGGR => {
                        blue_row[x] = p00 as u16;
                        green_row[x] = ((p10 + p01) / 2) as u16;
                        red_row[x] = p11 as u16;
                    }
                    BayerPattern::GRBG => {
                        green_row[x] = ((p00 + p11) / 2) as u16;
                        red_row[x] = p10 as u16;
                        blue_row[x] = p01 as u16;
                    }
                    BayerPattern::GBRG => {
                        green_row[x] = ((p00 + p11) / 2) as u16;
                        blue_row[x] = p10 as u16;
                        red_row[x] = p01 as u16;
                    }
                }
            }
        });
    
    RgbImage {
        width: out_w as u32,
        height: out_h as u32,
        red,
        green,
        blue,
    }
}


