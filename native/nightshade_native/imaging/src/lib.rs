//! Nightshade Imaging Library
//!
//! Provides real image I/O, processing, and analysis functionality:
//! - FITS file reading and writing
//! - XISF file support (PixInsight format)
//! - Image debayering for color cameras
//! - Image statistics and star detection
//! - Auto-stretch algorithms
//! - File naming patterns
//! - Camera control abstraction
//! - Plate solving via ASTAP
//! - PHD2 guiding integration
//! - Buffer pooling for efficient image capture

pub mod buffer_pool;
pub mod calibration;
pub mod defect_map;

mod camera;
mod debayer;
mod fits;
mod naming;
mod phd2;
mod platesolve;
mod processing; // NEW: Tiled image processing
mod raw; // NEW: RAW file support
mod reader; // NEW: Memory-mapped readers
pub mod stacking;
mod stats;
mod stretch;
mod xisf;

pub use buffer_pool::*;
pub use calibration::*;
pub use camera::*;
pub use debayer::*;
pub use fits::*;
pub use naming::*;
pub use phd2::*;
pub use platesolve::*;
pub use processing::*; // NEW: Export processing types
pub use raw::*; // NEW: Export RAW types
pub use reader::*; // NEW: Export reader types
pub use stats::*;
pub use stretch::*;
pub use xisf::*;

use rayon::prelude::*;

/// Image format supported by Nightshade
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ImageFormat {
    #[default]
    Fits,
    Xisf,
    Tiff,
    Png,
    Jpeg,
    // RAW formats
    CanonCR2,
    CanonCR3,
    NikonNEF,
    SonyARW,
    FujifilmRAF,
    PentaxPEF,
    OlympusORF,
    PanasonicRW2,
    GenericRAW,
}

impl ImageFormat {
    /// Get the file extension for this format
    pub fn extension(&self) -> &'static str {
        match self {
            ImageFormat::Fits => "fits",
            ImageFormat::Xisf => "xisf",
            ImageFormat::Tiff => "tiff",
            ImageFormat::Png => "png",
            ImageFormat::Jpeg => "jpg",
            ImageFormat::CanonCR2 => "cr2",
            ImageFormat::CanonCR3 => "cr3",
            ImageFormat::NikonNEF => "nef",
            ImageFormat::SonyARW => "arw",
            ImageFormat::FujifilmRAF => "raf",
            ImageFormat::PentaxPEF => "pef",
            ImageFormat::OlympusORF => "orf",
            ImageFormat::PanasonicRW2 => "rw2",
            ImageFormat::GenericRAW => "raw",
        }
    }

    /// Parse from file extension
    pub fn from_extension(ext: &str) -> Option<Self> {
        match ext.to_lowercase().as_str() {
            "fits" | "fit" | "fts" => Some(ImageFormat::Fits),
            "xisf" => Some(ImageFormat::Xisf),
            "tiff" | "tif" => Some(ImageFormat::Tiff),
            "png" => Some(ImageFormat::Png),
            "jpg" | "jpeg" => Some(ImageFormat::Jpeg),
            // RAW formats
            "cr2" => Some(ImageFormat::CanonCR2),
            "cr3" => Some(ImageFormat::CanonCR3),
            "nef" | "nrw" => Some(ImageFormat::NikonNEF),
            "arw" | "srf" | "sr2" => Some(ImageFormat::SonyARW),
            "raf" => Some(ImageFormat::FujifilmRAF),
            "pef" | "dng" => Some(ImageFormat::PentaxPEF),
            "orf" => Some(ImageFormat::OlympusORF),
            "rw2" => Some(ImageFormat::PanasonicRW2),
            "raw" | "crw" | "mrw" | "erf" | "3fr" => Some(ImageFormat::GenericRAW),
            _ => None,
        }
    }

    /// Detect image format from magic bytes (file signature)
    /// Returns None if format cannot be determined
    pub fn from_magic_bytes(data: &[u8]) -> Option<Self> {
        if data.len() < 16 {
            return None;
        }

        // FITS: "SIMPLE  ="
        if data.starts_with(b"SIMPLE  =") {
            return Some(ImageFormat::Fits);
        }

        // XISF: "XISF0100"
        if data.starts_with(b"XISF0100") {
            return Some(ImageFormat::Xisf);
        }

        // TIFF: "II" (little-endian) or "MM" (big-endian) followed by 42 (0x2A)
        if (data[0..2] == [0x49, 0x49] || data[0..2] == [0x4D, 0x4D])
            && (data[2] == 0x2A || data[3] == 0x2A)
        {
            // Could be TIFF or various RAW formats that use TIFF container
            // Check for specific RAW signatures

            // Canon CR2: TIFF header + "CR" at offset 8-9
            if data.len() > 10 && &data[8..10] == b"CR" {
                return Some(ImageFormat::CanonCR2);
            }

            // Nikon NEF: Check for "NIKON" in first 1024 bytes
            if data.len() > 1024 && data[..1024].windows(5).any(|w| w == b"NIKON") {
                return Some(ImageFormat::NikonNEF);
            }

            // Sony ARW: Check for "SONY" signature
            if data.len() > 1024 && data[..1024].windows(4).any(|w| w == b"SONY") {
                return Some(ImageFormat::SonyARW);
            }

            // Olympus ORF: Check for "OLYMP" signature
            if data.len() > 1024 && data[..1024].windows(5).any(|w| w == b"OLYMP") {
                return Some(ImageFormat::OlympusORF);
            }

            // Pentax PEF: Check for "PENTAX" signature
            if data.len() > 1024 && data[..1024].windows(6).any(|w| w == b"PENTAX") {
                return Some(ImageFormat::PentaxPEF);
            }

            // Panasonic RW2: Check for "Panasonic"
            if data.len() > 1024 && data[..1024].windows(9).any(|w| w == b"Panasonic") {
                return Some(ImageFormat::PanasonicRW2);
            }

            // Generic TIFF if no RAW signature found
            return Some(ImageFormat::Tiff);
        }

        // Canon CR3: ISO Base Media File Format (ftyp box)
        if data.len() > 12
            && &data[4..8] == b"ftyp"
            && (&data[8..12] == b"crx " || data[8..11] == *b"cr3")
        {
            return Some(ImageFormat::CanonCR3);
        }

        // Fujifilm RAF: "FUJIFILMCCD-RAW"
        if data.starts_with(b"FUJIFILMCCD-RAW") {
            return Some(ImageFormat::FujifilmRAF);
        }

        // PNG: 0x89 "PNG" 0x0D 0x0A 0x1A 0x0A
        if data.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return Some(ImageFormat::Png);
        }

        // JPEG: 0xFF 0xD8 0xFF
        if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
            return Some(ImageFormat::Jpeg);
        }

        None
    }

    /// Check if this format is a RAW camera format
    pub fn is_raw(&self) -> bool {
        matches!(
            self,
            ImageFormat::CanonCR2
                | ImageFormat::CanonCR3
                | ImageFormat::NikonNEF
                | ImageFormat::SonyARW
                | ImageFormat::FujifilmRAF
                | ImageFormat::PentaxPEF
                | ImageFormat::OlympusORF
                | ImageFormat::PanasonicRW2
                | ImageFormat::GenericRAW
        )
    }

    /// Check if this format can be processed by LibRaw
    pub fn is_libraw_supported(&self) -> bool {
        self.is_raw()
    }
}

/// Pixel data types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PixelType {
    U8,
    #[default]
    U16,
    U32,
    F32,
    F64,
}

impl PixelType {
    /// Get the number of bytes per pixel
    pub fn byte_size(&self) -> usize {
        match self {
            PixelType::U8 => 1,
            PixelType::U16 => 2,
            PixelType::U32 | PixelType::F32 => 4,
            PixelType::F64 => 8,
        }
    }

    /// Get the bit depth
    pub fn bit_depth(&self) -> u32 {
        match self {
            PixelType::U8 => 8,
            PixelType::U16 => 16,
            PixelType::U32 | PixelType::F32 => 32,
            PixelType::F64 => 64,
        }
    }
}

/// Image data container
#[derive(Debug, Clone)]
pub struct ImageData {
    pub width: u32,
    pub height: u32,
    pub channels: u32,
    pub pixel_type: PixelType,
    pub data: Vec<u8>,
}

impl Default for ImageData {
    fn default() -> Self {
        Self::new(0, 0, 1, PixelType::U16)
    }
}

impl ImageData {
    /// Create a new image with the given dimensions
    pub fn new(width: u32, height: u32, channels: u32, pixel_type: PixelType) -> Self {
        let bytes_per_pixel = pixel_type.byte_size();
        let size = (width as usize) * (height as usize) * (channels as usize) * bytes_per_pixel;

        Self {
            width,
            height,
            channels,
            pixel_type,
            data: vec![0u8; size],
        }
    }

    /// Get the number of bytes per pixel
    pub fn bytes_per_pixel(&self) -> usize {
        self.pixel_type.byte_size()
    }

    /// Get the total size in bytes
    pub fn size_bytes(&self) -> usize {
        self.data.len()
    }

    /// Get total pixel count
    pub fn pixel_count(&self) -> usize {
        (self.width as usize) * (self.height as usize) * (self.channels as usize)
    }

    /// Check if image has data
    pub fn is_empty(&self) -> bool {
        self.width == 0 || self.height == 0 || self.data.is_empty()
    }

    /// Get image data as u16 slice (for 16-bit images)
    pub fn as_u16(&self) -> Option<Vec<u16>> {
        if self.pixel_type != PixelType::U16 {
            return None;
        }

        Some(
            self.data
                .chunks_exact(2)
                .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                .collect(),
        )
    }

    /// Get image data as f32 slice
    pub fn as_f32(&self) -> Option<Vec<f32>> {
        if self.pixel_type != PixelType::F32 {
            return None;
        }

        Some(
            self.data
                .chunks_exact(4)
                .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
                .collect(),
        )
    }

    /// Create from u16 data
    pub fn from_u16(width: u32, height: u32, channels: u32, data: &[u16]) -> Self {
        let bytes: Vec<u8> = data.iter().flat_map(|&v| v.to_le_bytes()).collect();

        Self {
            width,
            height,
            channels,
            pixel_type: PixelType::U16,
            data: bytes,
        }
    }

    /// Create from f32 data
    pub fn from_f32(width: u32, height: u32, channels: u32, data: &[f32]) -> Self {
        let bytes: Vec<u8> = data.iter().flat_map(|&v| v.to_le_bytes()).collect();

        Self {
            width,
            height,
            channels,
            pixel_type: PixelType::F32,
            data: bytes,
        }
    }

    /// Convert to 8-bit for display (auto-stretched)
    pub fn to_display_u8(&self) -> Vec<u8> {
        if self.pixel_type == PixelType::U16 {
            if self.channels == 3 {
                if let Some(rgb_data) = self.as_u16() {
                    let (r_params, g_params, b_params) =
                        auto_stretch_rgb(&rgb_data, self.width, self.height);
                    let pixel_count = (self.width * self.height) as usize;
                    let mut stretched = vec![0u8; pixel_count * 3];
                    let channel_params = [&r_params, &g_params, &b_params];

                    for idx in 0..pixel_count {
                        for (channel, params) in channel_params.iter().enumerate() {
                            let normalized = rgb_data[idx * 3 + channel] as f64 / 65535.0;
                            let range = params.highlights - params.shadows;
                            let value = if range <= 0.0 {
                                0.0
                            } else {
                                let stretched_value =
                                    ((normalized - params.shadows) / range).clamp(0.0, 1.0);
                                display_mtf(stretched_value, params.midtones)
                            };
                            stretched[idx * 3 + channel] = (value.clamp(0.0, 1.0) * 255.0) as u8;
                        }
                    }

                    stretched
                } else {
                    vec![0u8; self.pixel_count()]
                }
            } else {
                let params = auto_stretch_stf(self);
                apply_stretch(self, &params)
            }
        } else {
            // For other types, simple linear conversion
            match self.pixel_type {
                PixelType::U8 => self.data.clone(),
                PixelType::F32 => {
                    // Parallel conversion for F32
                    self.data
                        .par_chunks_exact(4)
                        .map(|chunk| {
                            let val = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                            (val.clamp(0.0, 1.0) * 255.0) as u8
                        })
                        .collect()
                }
                _ => vec![128u8; self.pixel_count()],
            }
        }
    }

    /// Convert to RGBA for Flutter display
    /// Handles flexible channel counts: 1 (mono), 3 (RGB), 4 (RGBA)
    /// This solves the Fujifilm display issue where NINA couldn't handle 3-channel RGB
    pub fn to_rgba(&self) -> Vec<u8> {
        let grayscale = self.to_display_u8();

        match self.channels {
            // Mono camera FITS or grayscale images
            1 => {
                // Convert grayscale to RGBA by replicating to R=G=B
                // Parallel processing for large images
                grayscale
                    .par_iter()
                    .flat_map(|&v| [v, v, v, 255u8])
                    .collect()
            }

            // Fujifilm X-Trans RGB or Bayer demosaiced RGB
            // This is the critical fix - NINA couldn't handle this case!
            3 => {
                // Add alpha channel to RGB data
                // Parallel processing
                grayscale
                    .par_chunks_exact(3)
                    .flat_map(|chunk| [chunk[0], chunk[1], chunk[2], 255u8])
                    .collect()
            }

            // Already RGBA (some TIFFs, PNGs)
            4 => grayscale,

            // Unsupported channel count
            _ => {
                tracing::warn!(
                    "Unsupported channel count: {}, defaulting to grayscale",
                    self.channels
                );
                // Fallback: treat as grayscale
                vec![128u8; self.width as usize * self.height as usize * 4]
            }
        }
    }
}

fn display_mtf(x: f64, m: f64) -> f64 {
    if x <= 0.0 {
        0.0
    } else if x >= 1.0 {
        1.0
    } else if (x - m).abs() < f64::EPSILON {
        0.5
    } else {
        let numerator = (m - 1.0) * x;
        let denominator = (2.0 * m - 1.0) * x - m;
        if denominator.abs() < f64::EPSILON {
            0.5
        } else {
            numerator / denominator
        }
    }
}

/// Generate a simulated star field image for testing
pub fn generate_simulated_image(
    width: u32,
    height: u32,
    exposure_time: f64,
    gain: i32,
) -> ImageData {
    let mut data = vec![0u16; (width * height) as usize];
    let w = width as usize;
    let h = height as usize;

    // Base background level (sky glow)
    let background = (1000.0 + exposure_time * 50.0 + gain as f64 * 5.0) as u16;

    // Add background noise
    let noise_level = ((exposure_time.sqrt() * 10.0 + gain as f64) as u16).max(10);

    // Fill with background
    for pixel in &mut data {
        let noise = ((simple_random() - 0.5) * noise_level as f64 * 2.0) as i32;
        *pixel = (background as i32 + noise).clamp(0, 65535) as u16;
    }

    // Generate random stars
    let num_stars = (width * height / 5000).clamp(20, 500);
    let star_intensity_base = exposure_time * 1000.0 + gain as f64 * 100.0;

    for i in 0..num_stars {
        let seed = i as f64 * std::f64::consts::E; // Euler's number for pseudo-random distribution

        let x = ((seed * 12345.6789).sin().abs() * width as f64) as usize;
        let y = ((seed * 98765.4321).cos().abs() * height as f64) as usize;

        if x >= w || y >= h {
            continue;
        }

        // Random star brightness
        let brightness = (seed * 11111.1).sin().abs();
        let intensity = (star_intensity_base * brightness * 5.0) as u16;

        // Star size (larger for brighter stars)
        let radius = (brightness * 4.0 + 1.0) as i32;
        let sigma = radius as f64 / 2.5;

        // Draw Gaussian star profile
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                let px = x as i32 + dx;
                let py = y as i32 + dy;

                if px >= 0 && px < w as i32 && py >= 0 && py < h as i32 {
                    let dist_sq = (dx * dx + dy * dy) as f64;
                    let gauss = (-dist_sq / (2.0 * sigma * sigma)).exp();
                    let star_val = (intensity as f64 * gauss) as u32;

                    let idx = py as usize * w + px as usize;
                    data[idx] = (data[idx] as u32 + star_val).min(65535) as u16;
                }
            }
        }
    }

    // Add a few hot pixels
    for i in 0..5 {
        let seed = i as f64 * std::f64::consts::E;
        let x = ((seed * 54321.0).sin().abs() * width as f64) as usize;
        let y = ((seed * 12345.0).cos().abs() * height as f64) as usize;
        if x < w && y < h {
            data[y * w + x] = 65535;
        }
    }

    ImageData::from_u16(width, height, 1, &data)
}

/// Per-thread pseudo-random for simulation noise.
///
/// Why per-thread (audit §6.17): the previous implementation used a single
/// `static AtomicU64` with separate load/store steps. Concurrent calls from
/// multiple threads interleave the load-multiply-store, breaking determinism
/// AND silently dropping LCG steps. Threading-induced non-determinism made
/// the prior comment ("deterministic") false.
///
/// Each thread now holds its own `Cell<u64>` LCG state, seeded with `12345`.
/// Determinism therefore holds *within* a single thread sequence — which is
/// exactly how `generate_simulated_image` uses it (single thread, sequential
/// loops). Across threads, every thread starts from the same seed and steps
/// independently, so per-thread output is deterministic; thread interleaving
/// at the call site is irrelevant because there is no shared state.
fn simple_random() -> f64 {
    use std::cell::Cell;

    thread_local! {
        static SEED: Cell<u64> = const { Cell::new(12345) };
    }

    SEED.with(|cell| {
        let new = cell.get().wrapping_mul(1103515245).wrapping_add(12345);
        cell.set(new);
        new as f64 / u64::MAX as f64
    })
}

/// Image read result
#[derive(Debug)]
pub struct ImageReadResult {
    pub image: ImageData,
    pub format: ImageFormat,
    pub header: std::collections::HashMap<String, String>,
}

// ============================================================================
// IMAGE WRITING FUNCTIONS
// ============================================================================

/// Write an image to TIFF format (16-bit if possible, otherwise 8-bit)
pub fn write_tiff(path: &std::path::Path, image: &ImageData) -> Result<(), String> {
    use image::{GrayImage, ImageBuffer, RgbImage};
    use std::fs::File;
    use std::io::BufWriter;

    let file = File::create(path).map_err(|e| format!("Failed to create TIFF file: {}", e))?;
    let writer = BufWriter::new(file);

    match (image.channels, image.pixel_type) {
        // 16-bit mono - use raw encoder
        (1, PixelType::U16) => {
            use image::ImageEncoder;
            let pixels: Vec<u16> = image
                .data
                .chunks_exact(2)
                .map(|c| u16::from_le_bytes([c[0], c[1]]))
                .collect();

            let encoder = image::codecs::tiff::TiffEncoder::new(writer);
            encoder
                .write_image(
                    bytemuck::cast_slice(&pixels),
                    image.width,
                    image.height,
                    image::ColorType::L16,
                )
                .map_err(|e| format!("Failed to encode TIFF: {}", e))?;
        }
        // 8-bit mono
        (1, PixelType::U8) => {
            let img: GrayImage =
                ImageBuffer::from_raw(image.width, image.height, image.data.clone())
                    .ok_or_else(|| "Failed to create grayscale image buffer".to_string())?;
            img.save(path)
                .map_err(|e| format!("Failed to save TIFF: {}", e))?;
        }
        // 16-bit RGB
        (3, PixelType::U16) => {
            use image::ImageEncoder;
            let pixels: Vec<u16> = image
                .data
                .chunks_exact(2)
                .map(|c| u16::from_le_bytes([c[0], c[1]]))
                .collect();

            let encoder = image::codecs::tiff::TiffEncoder::new(writer);
            encoder
                .write_image(
                    bytemuck::cast_slice(&pixels),
                    image.width,
                    image.height,
                    image::ColorType::Rgb16,
                )
                .map_err(|e| format!("Failed to encode TIFF: {}", e))?;
        }
        // 8-bit RGB
        (3, PixelType::U8) => {
            let img: RgbImage =
                ImageBuffer::from_raw(image.width, image.height, image.data.clone())
                    .ok_or_else(|| "Failed to create RGB image buffer".to_string())?;
            img.save(path)
                .map_err(|e| format!("Failed to save TIFF: {}", e))?;
        }
        // Other formats: convert to 8-bit first
        _ => {
            let display_data = image.to_display_u8();
            if image.channels == 1 {
                let img: GrayImage = ImageBuffer::from_raw(image.width, image.height, display_data)
                    .ok_or_else(|| "Failed to create grayscale image buffer".to_string())?;
                img.save(path)
                    .map_err(|e| format!("Failed to save TIFF: {}", e))?;
            } else if image.channels >= 3 {
                // Multi-channel: display_data contains interleaved channel bytes.
                // Extract the first 3 channels as RGB.
                let pixel_count = (image.width as usize) * (image.height as usize);
                let rgb_data = if image.channels == 3 {
                    display_data
                } else {
                    let mut rgb = Vec::with_capacity(pixel_count * 3);
                    for chunk in display_data.chunks_exact(image.channels as usize) {
                        rgb.push(chunk[0]);
                        rgb.push(chunk[1]);
                        rgb.push(chunk[2]);
                    }
                    rgb
                };
                let img: RgbImage = ImageBuffer::from_raw(image.width, image.height, rgb_data)
                    .ok_or_else(|| "Failed to create RGB image buffer".to_string())?;
                img.save(path)
                    .map_err(|e| format!("Failed to save TIFF: {}", e))?;
            } else {
                return Err(format!(
                    "Unsupported channel count {} for TIFF encoding",
                    image.channels
                ));
            }
        }
    }

    Ok(())
}

/// Write an image to PNG format (8-bit or 16-bit)
pub fn write_png(path: &std::path::Path, image: &ImageData) -> Result<(), String> {
    use image::{GrayImage, ImageBuffer, ImageEncoder, RgbImage};
    use std::fs::File;
    use std::io::BufWriter;

    let file = File::create(path).map_err(|e| format!("Failed to create PNG file: {}", e))?;
    let writer = BufWriter::new(file);

    match (image.channels, image.pixel_type) {
        // 16-bit mono
        (1, PixelType::U16) => {
            let pixels: Vec<u16> = image
                .data
                .chunks_exact(2)
                .map(|c| u16::from_le_bytes([c[0], c[1]]))
                .collect();

            let encoder = image::codecs::png::PngEncoder::new(writer);
            encoder
                .write_image(
                    bytemuck::cast_slice(&pixels),
                    image.width,
                    image.height,
                    image::ColorType::L16,
                )
                .map_err(|e| format!("Failed to encode PNG: {}", e))?;
        }
        // 8-bit mono
        (1, PixelType::U8) => {
            let img: GrayImage =
                ImageBuffer::from_raw(image.width, image.height, image.data.clone())
                    .ok_or_else(|| "Failed to create grayscale image buffer".to_string())?;
            img.save(path)
                .map_err(|e| format!("Failed to save PNG: {}", e))?;
        }
        // 16-bit RGB
        (3, PixelType::U16) => {
            let pixels: Vec<u16> = image
                .data
                .chunks_exact(2)
                .map(|c| u16::from_le_bytes([c[0], c[1]]))
                .collect();

            let encoder = image::codecs::png::PngEncoder::new(writer);
            encoder
                .write_image(
                    bytemuck::cast_slice(&pixels),
                    image.width,
                    image.height,
                    image::ColorType::Rgb16,
                )
                .map_err(|e| format!("Failed to encode PNG: {}", e))?;
        }
        // 8-bit RGB
        (3, PixelType::U8) => {
            let img: RgbImage =
                ImageBuffer::from_raw(image.width, image.height, image.data.clone())
                    .ok_or_else(|| "Failed to create RGB image buffer".to_string())?;
            img.save(path)
                .map_err(|e| format!("Failed to save PNG: {}", e))?;
        }
        // Other formats: convert to 8-bit
        _ => {
            let display_data = image.to_display_u8();
            if image.channels == 1 {
                let img: GrayImage = ImageBuffer::from_raw(image.width, image.height, display_data)
                    .ok_or_else(|| "Failed to create grayscale image buffer".to_string())?;
                img.save(path)
                    .map_err(|e| format!("Failed to save PNG: {}", e))?;
            } else if image.channels >= 3 {
                // Multi-channel: display_data contains interleaved channel bytes.
                // Extract the first 3 channels as RGB.
                let pixel_count = (image.width as usize) * (image.height as usize);
                let rgb_data = if image.channels == 3 {
                    display_data
                } else {
                    let mut rgb = Vec::with_capacity(pixel_count * 3);
                    for chunk in display_data.chunks_exact(image.channels as usize) {
                        rgb.push(chunk[0]);
                        rgb.push(chunk[1]);
                        rgb.push(chunk[2]);
                    }
                    rgb
                };
                let img: RgbImage = ImageBuffer::from_raw(image.width, image.height, rgb_data)
                    .ok_or_else(|| "Failed to create RGB image buffer".to_string())?;
                img.save(path)
                    .map_err(|e| format!("Failed to save PNG: {}", e))?;
            } else {
                return Err(format!(
                    "Unsupported channel count {} for PNG encoding",
                    image.channels
                ));
            }
        }
    }

    Ok(())
}

/// Write an image to JPEG format (always 8-bit, with quality setting)
pub fn write_jpeg(path: &std::path::Path, image: &ImageData, quality: u8) -> Result<(), String> {
    use image::ImageEncoder;
    use std::fs::File;
    use std::io::BufWriter;

    let file = File::create(path).map_err(|e| format!("Failed to create JPEG file: {}", e))?;
    let writer = BufWriter::new(file);

    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(writer, quality);

    // JPEG only supports 8-bit, so always convert to display format
    let display_data = image.to_display_u8();

    if image.channels == 1 {
        // Grayscale JPEG
        encoder
            .write_image(
                &display_data,
                image.width,
                image.height,
                image::ColorType::L8,
            )
            .map_err(|e| format!("Failed to encode JPEG: {}", e))?;
    } else if image.channels >= 3 {
        // RGB JPEG - display_data for multi-channel images contains interleaved
        // RGB bytes (channels * width * height). Extract 3 channels as RGB8.
        let pixel_count = (image.width as usize) * (image.height as usize);
        let rgb_data =
            if display_data.len() == pixel_count * image.channels as usize && image.channels >= 3 {
                // display_data has interleaved channel data; take the first 3 channels
                if image.channels == 3 {
                    display_data
                } else {
                    // channels > 3 (e.g. RGBA): strip extra channels, keep RGB
                    let mut rgb = Vec::with_capacity(pixel_count * 3);
                    for chunk in display_data.chunks_exact(image.channels as usize) {
                        rgb.push(chunk[0]);
                        rgb.push(chunk[1]);
                        rgb.push(chunk[2]);
                    }
                    rgb
                }
            } else {
                // Fallback: replicate mono data to RGB if display_data is single-channel
                let mut rgb = Vec::with_capacity(pixel_count * 3);
                for &v in &display_data[..pixel_count.min(display_data.len())] {
                    rgb.push(v);
                    rgb.push(v);
                    rgb.push(v);
                }
                rgb
            };

        encoder
            .write_image(&rgb_data, image.width, image.height, image::ColorType::Rgb8)
            .map_err(|e| format!("Failed to encode JPEG: {}", e))?;
    } else {
        return Err(format!(
            "Unsupported channel count {} for JPEG encoding",
            image.channels
        ));
    }

    Ok(())
}

/// Read an image file (auto-detect format)
pub fn read_image(path: &std::path::Path) -> Result<ImageReadResult, String> {
    // Why (audit-rust §4.3): path with no extension OR with a non-UTF-8 extension
    // returns empty string; `ImageFormat::from_extension("")` returns None and the
    // ?-propagating ok_or_else fails CLOSED with "Unsupported file extension:" on the
    // next line. Silent fallback to empty is the correct funneling into the error
    // path.
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");

    let format = ImageFormat::from_extension(ext)
        .ok_or_else(|| format!("Unsupported file extension: {}", ext))?;

    match format {
        ImageFormat::Fits => {
            let (image, fits_header) = read_fits(path).map_err(|e| e.to_string())?;

            let header: std::collections::HashMap<String, String> = fits_header
                .keywords
                .into_iter()
                .map(|(k, v)| (k, format!("{:?}", v)))
                .collect();

            Ok(ImageReadResult {
                image,
                format,
                header,
            })
        }
        ImageFormat::Xisf => {
            let (image, xisf_metadata) = read_xisf(path).map_err(|e| e.to_string())?;

            let mut header: std::collections::HashMap<String, String> = xisf_metadata.fits_keywords;
            for (k, v) in xisf_metadata.properties {
                header.insert(k, format!("{:?}", v));
            }

            Ok(ImageReadResult {
                image,
                format,
                header,
            })
        }
        // Handle all RAW formats
        ImageFormat::CanonCR2
        | ImageFormat::CanonCR3
        | ImageFormat::NikonNEF
        | ImageFormat::SonyARW
        | ImageFormat::FujifilmRAF
        | ImageFormat::PentaxPEF
        | ImageFormat::OlympusORF
        | ImageFormat::PanasonicRW2
        | ImageFormat::GenericRAW => {
            let (image, raw_metadata) = read_raw(path, None).map_err(|e| e.to_string())?;

            // Convert raw metadata to hashmap
            let mut header = std::collections::HashMap::new();
            header.insert("MAKE".to_string(), raw_metadata.camera_make);
            header.insert("MODEL".to_string(), raw_metadata.camera_model);

            if let Some(iso) = raw_metadata.iso_speed {
                header.insert("ISO".to_string(), iso.to_string());
            }
            if let Some(shutter) = raw_metadata.shutter_speed {
                header.insert("EXPTIME".to_string(), shutter.to_string());
            }
            if let Some(aperture) = raw_metadata.aperture {
                header.insert("APERTURE".to_string(), aperture.to_string());
            }
            if let Some(focal) = raw_metadata.focal_length {
                header.insert("FOCALLEN".to_string(), focal.to_string());
            }
            if let Some(ts) = raw_metadata.timestamp {
                if let Some(dt) = chrono::DateTime::<chrono::Utc>::from_timestamp(ts, 0) {
                    header.insert("DATETIME".to_string(), dt.to_rfc3339());
                } else {
                    header.insert("DATETIME".to_string(), ts.to_string());
                }
            }

            Ok(ImageReadResult {
                image,
                format,
                header,
            })
        }
        _ => Err(format!(
            "Reading {:?} is not supported by the current image reader pipeline",
            format
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn to_display_u8_preserves_rgb_channel_differences_for_u16_images() {
        let image = ImageData::from_u16(1, 2, 3, &[65535, 0, 0, 0, 32768, 65535]);
        let display = image.to_display_u8();

        assert_eq!(display.len(), 6);
        assert!(display[0] > display[1]);
        assert!(display[0] > display[2]);
        assert!(display[5] >= display[4]);
    }
}
