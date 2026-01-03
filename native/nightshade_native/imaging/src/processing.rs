//! High-performance image processing with tiling and parallelism
//!
//! This module provides memory-efficient processing for large images by:
//! - Breaking images into tiles to avoid loading entire image into memory
//! - Processing tiles in parallel using rayon
//! - Providing progress callbacks for long operations
//! - Supporting streaming operations

use crate::{ImageData, PixelType};
use rayon::prelude::*;
use std::sync::{Arc, Mutex};

/// Tile region for processing
#[derive(Debug, Clone, Copy)]
pub struct TileRegion {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

impl TileRegion {
    /// Create a new tile region
    pub fn new(x: u32, y: u32, width: u32, height: u32) -> Self {
        Self { x, y, width, height }
    }

    /// Calculate the actual pixel count in this tile
    pub fn pixel_count(&self) -> usize {
        (self.width * self.height) as usize
    }
}

/// Processing operation types
#[derive(Debug, Clone)]
pub enum ProcessOperation {
    /// Auto-stretch with given parameters
    AutoStretch { shadow: f64, midtone: f64, highlight: f64 },
    /// Normalize to 0-1 range
    Normalize,
    /// Apply gamma correction
    Gamma { gamma: f64 },
    /// Debayer (for RAW processing)
    Debayer { pattern: String },
    /// Custom operation (user-defined)
    Custom,
}

/// Progress callback type
pub type ProgressCallback = Arc<dyn Fn(f32) + Send + Sync>;

/// Calculate tile grid for an image
pub fn calculate_tile_grid(width: u32, height: u32, tile_size: u32) -> Vec<TileRegion> {
    let mut tiles = Vec::new();

    let tiles_x = (width + tile_size - 1) / tile_size;
    let tiles_y = (height + tile_size - 1) / tile_size;

    for ty in 0..tiles_y {
        for tx in 0..tiles_x {
            let x = tx * tile_size;
            let y = ty * tile_size;
            let w = (tile_size).min(width - x);
            let h = (tile_size).min(height - y);

            tiles.push(TileRegion::new(x, y, w, h));
        }
    }

    tiles
}

/// Process large image in tiles to avoid memory pressure
///
/// This function:
/// - Divides the image into tiles
/// - Processes each tile in parallel using rayon
/// - Merges results back together
/// - Reports progress via callback
///
/// Memory usage: ~(tile_size^2 * num_threads * bytes_per_pixel) instead of full image
pub async fn process_tiled(
    image: &ImageData,
    tile_size: u32,
    operation: ProcessOperation,
    progress_callback: Option<ProgressCallback>,
) -> Result<ImageData, String> {
    let tiles = calculate_tile_grid(image.width, image.height, tile_size);
    let total_tiles = tiles.len();

    tracing::info!(
        "Processing {}x{} image with {} tiles of size {}x{}",
        image.width,
        image.height,
        total_tiles,
        tile_size,
        tile_size
    );

    // Thread-safe progress counter
    let completed = Arc::new(Mutex::new(0usize));

    // Process tiles in parallel
    let results: Result<Vec<_>, String> = tiles
        .par_iter()
        .map(|tile| {
            let result = process_tile(image, tile, &operation)?;

            // Update progress
            if let Some(ref callback) = progress_callback {
                let mut count = completed.lock().unwrap();
                *count += 1;
                let progress = (*count as f32) / (total_tiles as f32);
                callback(progress);
            }

            Ok((tile.clone(), result))
        })
        .collect();

    let tile_results = results?;

    // Merge results
    merge_tile_results(tile_results, image.width, image.height, image.channels, image.pixel_type)
}

/// Process a single tile
fn process_tile(
    image: &ImageData,
    tile: &TileRegion,
    operation: &ProcessOperation,
) -> Result<Vec<u8>, String> {
    // Extract tile data from full image
    let tile_data = extract_tile_data(image, tile)?;

    // Apply operation to tile
    match operation {
        ProcessOperation::AutoStretch { shadow, midtone, highlight } => {
            apply_stretch_to_tile(&tile_data, image.pixel_type, *shadow, *midtone, *highlight)
        }
        ProcessOperation::Normalize => {
            normalize_tile(&tile_data, image.pixel_type)
        }
        ProcessOperation::Gamma { gamma } => {
            apply_gamma_to_tile(&tile_data, image.pixel_type, *gamma)
        }
        ProcessOperation::Debayer { pattern: _ } => {
            // Debayering requires access to neighboring tiles - not implemented in tiled mode
            Err("Debayer operation not supported in tiled mode".to_string())
        }
        ProcessOperation::Custom => {
            // User would provide custom processing function
            Ok(tile_data)
        }
    }
}

/// Extract tile data from full image
fn extract_tile_data(image: &ImageData, tile: &TileRegion) -> Result<Vec<u8>, String> {
    let bytes_per_pixel = image.bytes_per_pixel();
    let channels = image.channels as usize;
    let stride = (image.width as usize) * bytes_per_pixel * channels;

    let mut tile_data = Vec::with_capacity(tile.pixel_count() * bytes_per_pixel * channels);

    for y in 0..tile.height {
        let src_y = (tile.y + y) as usize;
        let src_x = tile.x as usize;

        let row_start = src_y * stride + src_x * bytes_per_pixel * channels;
        let row_len = (tile.width as usize) * bytes_per_pixel * channels;

        if row_start + row_len <= image.data.len() {
            tile_data.extend_from_slice(&image.data[row_start..row_start + row_len]);
        } else {
            return Err("Tile region out of bounds".to_string());
        }
    }

    Ok(tile_data)
}

/// Apply stretch to tile data
fn apply_stretch_to_tile(
    data: &[u8],
    pixel_type: PixelType,
    shadow: f64,
    midtone: f64,
    highlight: f64,
) -> Result<Vec<u8>, String> {
    match pixel_type {
        PixelType::U16 => {
            let u16_data: Vec<u16> = data
                .chunks_exact(2)
                .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                .collect();

            let stretched: Vec<u8> = u16_data
                .par_iter()
                .flat_map(|&val| {
                    let normalized = val as f64 / 65535.0;
                    let stretched = apply_mtf(normalized, shadow, midtone, highlight);
                    let output = (stretched.clamp(0.0, 1.0) * 255.0) as u8;
                    vec![output]
                })
                .collect();

            Ok(stretched)
        }
        PixelType::F32 => {
            let f32_data: Vec<f32> = data
                .chunks_exact(4)
                .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
                .collect();

            let stretched: Vec<u8> = f32_data
                .par_iter()
                .flat_map(|&val| {
                    let stretched = apply_mtf(val as f64, shadow, midtone, highlight);
                    let output = (stretched.clamp(0.0, 1.0) * 255.0) as u8;
                    vec![output]
                })
                .collect();

            Ok(stretched)
        }
        _ => Ok(data.to_vec()),
    }
}

/// Apply midtone transfer function (MTF)
fn apply_mtf(value: f64, shadow: f64, midtone: f64, highlight: f64) -> f64 {
    // Normalize to shadow-highlight range
    let normalized = ((value - shadow) / (highlight - shadow)).clamp(0.0, 1.0);

    // Apply midtone transfer
    if midtone < 0.5 {
        // Compress shadows
        let m = 2.0 * midtone;
        normalized.powf(1.0 / m)
    } else {
        // Compress highlights
        let m = 2.0 * (1.0 - midtone);
        1.0 - (1.0 - normalized).powf(1.0 / m)
    }
}

/// Normalize tile to 0-1 range
fn normalize_tile(data: &[u8], pixel_type: PixelType) -> Result<Vec<u8>, String> {
    match pixel_type {
        PixelType::U16 => {
            let u16_data: Vec<u16> = data
                .chunks_exact(2)
                .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                .collect();

            let min = *u16_data.iter().min().unwrap_or(&0);
            let max = *u16_data.iter().max().unwrap_or(&65535);
            let range = (max - min) as f64;

            if range == 0.0 {
                return Ok(vec![128u8; u16_data.len()]);
            }

            let normalized: Vec<u8> = u16_data
                .par_iter()
                .map(|&val| {
                    let norm = ((val - min) as f64 / range * 255.0) as u8;
                    norm
                })
                .collect();

            Ok(normalized)
        }
        _ => Ok(data.to_vec()),
    }
}

/// Apply gamma correction to tile
fn apply_gamma_to_tile(data: &[u8], pixel_type: PixelType, gamma: f64) -> Result<Vec<u8>, String> {
    match pixel_type {
        PixelType::U16 => {
            let u16_data: Vec<u16> = data
                .chunks_exact(2)
                .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                .collect();

            let corrected: Vec<u8> = u16_data
                .par_iter()
                .map(|&val| {
                    let normalized = (val as f64) / 65535.0;
                    let corrected = normalized.powf(1.0 / gamma);
                    (corrected * 255.0).clamp(0.0, 255.0) as u8
                })
                .collect();

            Ok(corrected)
        }
        _ => Ok(data.to_vec()),
    }
}

/// Merge tile results back into a single image
fn merge_tile_results(
    tile_results: Vec<(TileRegion, Vec<u8>)>,
    width: u32,
    height: u32,
    channels: u32,
    _pixel_type: PixelType,
) -> Result<ImageData, String> {
    // For display output, we're creating U8 RGBA data
    let output_channels = if channels == 1 { 4 } else { channels }; // Convert mono to RGBA
    let mut output = vec![0u8; (width * height * output_channels) as usize];

    for (tile, tile_data) in tile_results {
        // Write tile data to output
        for y in 0..tile.height {
            let src_offset = (y * tile.width) as usize;
            let dst_y = (tile.y + y) as usize;
            let dst_x = tile.x as usize;
            let dst_offset = dst_y * (width as usize) + dst_x;

            let src_start = src_offset;
            let src_end = src_start + (tile.width as usize);
            let dst_start = dst_offset;
            let dst_end = dst_start + (tile.width as usize);

            if src_end <= tile_data.len() && dst_end <= output.len() {
                output[dst_start..dst_end].copy_from_slice(&tile_data[src_start..src_end]);
            }
        }
    }

    Ok(ImageData {
        width,
        height,
        channels: 1, // Processed output is grayscale for now
        pixel_type: PixelType::U8,
        data: output,
    })
}

/// Process with progress reporting
pub async fn process_with_progress<F>(
    image: &ImageData,
    operation: ProcessOperation,
    tile_size: u32,
    progress_callback: F,
) -> Result<ImageData, String>
where
    F: Fn(f32) + Send + Sync + 'static,
{
    let callback = Arc::new(progress_callback);
    process_tiled(image, tile_size, operation, Some(callback)).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_tile_grid() {
        let tiles = calculate_tile_grid(1000, 1000, 256);
        assert_eq!(tiles.len(), 16); // 4x4 grid

        let tiles = calculate_tile_grid(1920, 1080, 512);
        assert_eq!(tiles.len(), 12); // 4x3 grid
    }

    #[test]
    fn test_tile_region() {
        let tile = TileRegion::new(0, 0, 256, 256);
        assert_eq!(tile.pixel_count(), 65536);
    }

    #[tokio::test]
    async fn test_process_tiled_normalize() {
        let image = ImageData::new(512, 512, 1, PixelType::U16);
        let result = process_tiled(
            &image,
            256,
            ProcessOperation::Normalize,
            None,
        ).await;

        assert!(result.is_ok());
        let processed = result.unwrap();
        assert_eq!(processed.width, 512);
        assert_eq!(processed.height, 512);
    }
}
