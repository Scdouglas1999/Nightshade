//! Defect map / bad-pixel cosmetic correction pipeline.
//!
//! Builds a per-pixel defect bitmap from a stack of dark or bias frames,
//! applies neighbourhood-median replacement at capture time, and persists
//! defect maps to disk in a compact binary format keyed by camera, sensor
//! size and temperature bucket.
//!
//! ## Detection
//!
//! For each pixel `(x, y)` we collect its value across all dark frames in
//! the input stack. The pixel's representative value is the per-pixel
//! median across the stack; this is the consistent dark-current level for
//! that pixel.
//!
//! A pixel is flagged hot if its per-pixel median exceeds
//! `global_median + DEFECT_MAD_K * MAD` of the frame's pixel-medians, and
//! flagged cold if it is below `global_median - DEFECT_MAD_K * MAD`.
//! MAD (median absolute deviation) is used instead of standard deviation
//! because real defects are large outliers that would inflate σ enough to
//! mask themselves.
//!
//! We additionally require a pixel be a frame-local outlier (above/below
//! the threshold) in at least `MIN_CONSISTENCY_FRAMES` of the input darks;
//! single-frame outliers are typically cosmic rays, not defects.
//!
//! ## Correction
//!
//! At capture time, each defective pixel is replaced by the median of its
//! non-defective neighbours in a 3x3 window. If 8 or more of the 9 pixels
//! in the 3x3 are defective, we expand to a 5x5 window. See
//! [`correct_frame_u16`] for details.
//!
//! ## File format (`.ndm`)
//!
//! 16-byte header:
//! - 4-byte magic `NDM1`
//! - u32 width (little-endian)
//! - u32 height (little-endian)
//! - i16 temperature_bucket × 10 (so -27.5°C → -275)
//! - 2 reserved bytes (zero)
//!
//! Then the packed bitmap of `ceil(width * height / 8)` bytes, bit `i`
//! representing pixel `i = y * width + x`. Bit 0 is the LSB of each byte.
//!
//! Trailing footer: u32 defective pixel count for quick stat lookups
//! without scanning the bitmap.

use crate::{ImageData, PixelType};
use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;

const DEFECT_MAD_K: f64 = 5.0;

/// Minimum number of frames in which a pixel must be an outlier before it
/// is classified as a real defect rather than a transient cosmic ray.
pub const MIN_CONSISTENCY_FRAMES: usize = 5;

/// Magic bytes identifying a Nightshade Defect Map v1 file.
pub const NDM_MAGIC: &[u8; 4] = b"NDM1";

/// Size of the header that precedes the packed bitmap.
pub const NDM_HEADER_SIZE: usize = 16;

/// Size of the trailing footer (u32 count).
pub const NDM_FOOTER_SIZE: usize = 4;

/// Errors that can occur in the defect-map pipeline.
#[derive(Debug, Clone)]
pub enum DefectMapError {
    EmptyStack,
    InsufficientFrames {
        provided: usize,
        required: usize,
    },
    DimensionMismatch {
        expected_width: u32,
        expected_height: u32,
        actual_width: u32,
        actual_height: u32,
        frame_index: usize,
    },
    UnsupportedPixelType {
        pixel_type: PixelType,
    },
    BadMagic,
    Truncated {
        expected: usize,
        actual: usize,
    },
    DimensionMismatchOnApply {
        frame_width: u32,
        frame_height: u32,
        map_width: u32,
        map_height: u32,
    },
    Io(String),
}

impl std::fmt::Display for DefectMapError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DefectMapError::EmptyStack => write!(f, "Defect-map dark stack is empty"),
            DefectMapError::InsufficientFrames { provided, required } => write!(
                f,
                "Insufficient dark frames for defect detection: {} provided, {} required",
                provided, required
            ),
            DefectMapError::DimensionMismatch {
                expected_width,
                expected_height,
                actual_width,
                actual_height,
                frame_index,
            } => write!(
                f,
                "Dimension mismatch in dark stack at frame {}: expected {}x{}, got {}x{}",
                frame_index, expected_width, expected_height, actual_width, actual_height
            ),
            DefectMapError::UnsupportedPixelType { pixel_type } => write!(
                f,
                "Defect map only supports U16 pixels, got {:?}",
                pixel_type
            ),
            DefectMapError::BadMagic => {
                write!(f, "Defect map file does not start with NDM1 magic bytes")
            }
            DefectMapError::Truncated { expected, actual } => write!(
                f,
                "Defect map file truncated: expected {} bytes, got {}",
                expected, actual
            ),
            DefectMapError::DimensionMismatchOnApply {
                frame_width,
                frame_height,
                map_width,
                map_height,
            } => write!(
                f,
                "Defect map dimensions {}x{} do not match light frame {}x{}",
                map_width, map_height, frame_width, frame_height
            ),
            DefectMapError::Io(msg) => write!(f, "Defect map I/O error: {}", msg),
        }
    }
}

impl std::error::Error for DefectMapError {}

impl From<std::io::Error> for DefectMapError {
    fn from(err: std::io::Error) -> Self {
        DefectMapError::Io(err.to_string())
    }
}

/// A defect map: width, height, packed bitmap and the temperature bucket
/// that this map was built for.
#[derive(Debug, Clone)]
pub struct DefectMap {
    pub width: u32,
    pub height: u32,
    /// Temperature bucket in deci-degrees Celsius (e.g. -200 = -20.0 °C).
    pub temperature_bucket_decicelsius: i16,
    bitmap: Vec<u8>,
    defective_count: u32,
}

impl DefectMap {
    pub fn empty(width: u32, height: u32, temperature_bucket_decicelsius: i16) -> Self {
        let bytes = ((width as usize) * (height as usize)).div_ceil(8);
        DefectMap {
            width,
            height,
            temperature_bucket_decicelsius,
            bitmap: vec![0u8; bytes],
            defective_count: 0,
        }
    }

    pub fn defective_count(&self) -> u32 {
        self.defective_count
    }

    pub fn pixel_count(&self) -> usize {
        (self.width as usize) * (self.height as usize)
    }

    #[inline]
    pub fn is_defective(&self, x: u32, y: u32) -> bool {
        if x >= self.width || y >= self.height {
            return false;
        }
        let idx = (y as usize) * (self.width as usize) + (x as usize);
        self.bitmap_get(idx)
    }

    pub fn mark_defective(&mut self, x: u32, y: u32) {
        if x >= self.width || y >= self.height {
            return;
        }
        let idx = (y as usize) * (self.width as usize) + (x as usize);
        if !self.bitmap_get(idx) {
            self.bitmap_set(idx);
            self.defective_count += 1;
        }
    }

    /// Raw bitmap byte slice. Mainly for serialisation / Dart-side blob
    /// storage; callers should normally use [`Self::is_defective`].
    pub fn bitmap_bytes(&self) -> &[u8] {
        &self.bitmap
    }

    #[inline]
    fn bitmap_get(&self, idx: usize) -> bool {
        (self.bitmap[idx / 8] >> (idx % 8)) & 1 != 0
    }

    #[inline]
    fn bitmap_set(&mut self, idx: usize) {
        self.bitmap[idx / 8] |= 1u8 << (idx % 8);
    }

    pub fn serialize(&self) -> Vec<u8> {
        let mut out =
            Vec::with_capacity(NDM_HEADER_SIZE + self.bitmap.len() + NDM_FOOTER_SIZE);
        out.extend_from_slice(NDM_MAGIC);
        out.extend_from_slice(&self.width.to_le_bytes());
        out.extend_from_slice(&self.height.to_le_bytes());
        out.extend_from_slice(&self.temperature_bucket_decicelsius.to_le_bytes());
        out.extend_from_slice(&[0u8, 0u8]);
        out.extend_from_slice(&self.bitmap);
        out.extend_from_slice(&self.defective_count.to_le_bytes());
        out
    }

    pub fn deserialize(bytes: &[u8]) -> Result<Self, DefectMapError> {
        if bytes.len() < NDM_HEADER_SIZE + NDM_FOOTER_SIZE {
            return Err(DefectMapError::Truncated {
                expected: NDM_HEADER_SIZE + NDM_FOOTER_SIZE,
                actual: bytes.len(),
            });
        }
        if &bytes[0..4] != NDM_MAGIC {
            return Err(DefectMapError::BadMagic);
        }
        let width = u32::from_le_bytes(bytes[4..8].try_into().expect("4 bytes"));
        let height = u32::from_le_bytes(bytes[8..12].try_into().expect("4 bytes"));
        let temperature_bucket_decicelsius =
            i16::from_le_bytes(bytes[12..14].try_into().expect("2 bytes"));

        let pixel_count = (width as usize) * (height as usize);
        let bitmap_bytes_len = pixel_count.div_ceil(8);
        let expected_total = NDM_HEADER_SIZE + bitmap_bytes_len + NDM_FOOTER_SIZE;
        if bytes.len() != expected_total {
            return Err(DefectMapError::Truncated {
                expected: expected_total,
                actual: bytes.len(),
            });
        }

        let bitmap_start = NDM_HEADER_SIZE;
        let bitmap_end = bitmap_start + bitmap_bytes_len;
        let bitmap = bytes[bitmap_start..bitmap_end].to_vec();
        let defective_count = u32::from_le_bytes(
            bytes[bitmap_end..bitmap_end + 4]
                .try_into()
                .expect("4 bytes"),
        );

        Ok(DefectMap {
            width,
            height,
            temperature_bucket_decicelsius,
            bitmap,
            defective_count,
        })
    }

    pub fn write_to_file(&self, path: &Path) -> Result<(), DefectMapError> {
        let bytes = self.serialize();
        let mut f = File::create(path)?;
        f.write_all(&bytes)?;
        f.sync_all()?;
        Ok(())
    }

    pub fn read_from_file(path: &Path) -> Result<Self, DefectMapError> {
        let mut f = File::open(path)?;
        let mut bytes = Vec::new();
        f.read_to_end(&mut bytes)?;
        DefectMap::deserialize(&bytes)
    }
}

/// Bucket a temperature in °C to the nearest 5°C, returned as
/// deci-degrees-Celsius (i.e. ×10). Example: -22.3 → -200, +27.4 → +250.
pub fn bucket_temperature(celsius: f64) -> i16 {
    let bucketed = (celsius / 5.0).round() * 5.0;
    let clamped = bucketed.clamp(i16::MIN as f64 / 10.0, i16::MAX as f64 / 10.0);
    (clamped * 10.0).round() as i16
}

/// Build a defect map from a stack of dark (or bias) frames.
pub fn build_defect_map(
    darks: &[&ImageData],
    temperature_bucket_decicelsius: i16,
) -> Result<DefectMap, DefectMapError> {
    if darks.is_empty() {
        return Err(DefectMapError::EmptyStack);
    }
    if darks.len() < MIN_CONSISTENCY_FRAMES {
        return Err(DefectMapError::InsufficientFrames {
            provided: darks.len(),
            required: MIN_CONSISTENCY_FRAMES,
        });
    }

    let width = darks[0].width;
    let height = darks[0].height;
    for (i, frame) in darks.iter().enumerate() {
        if frame.pixel_type != PixelType::U16 {
            return Err(DefectMapError::UnsupportedPixelType {
                pixel_type: frame.pixel_type,
            });
        }
        if frame.width != width || frame.height != height {
            return Err(DefectMapError::DimensionMismatch {
                expected_width: width,
                expected_height: height,
                actual_width: frame.width,
                actual_height: frame.height,
                frame_index: i,
            });
        }
    }

    let pixel_count = (width as usize) * (height as usize);
    let n_frames = darks.len();

    let mut frame_pixels: Vec<Vec<u16>> = Vec::with_capacity(n_frames);
    for frame in darks {
        let pixels = frame
            .as_u16()
            .ok_or(DefectMapError::UnsupportedPixelType {
                pixel_type: frame.pixel_type,
            })?;
        if pixels.len() != pixel_count {
            return Err(DefectMapError::DimensionMismatch {
                expected_width: width,
                expected_height: height,
                actual_width: frame.width,
                actual_height: frame.height,
                frame_index: 0,
            });
        }
        frame_pixels.push(pixels);
    }

    let mut per_pixel_medians: Vec<f64> = Vec::with_capacity(pixel_count);
    let mut scratch = vec![0u16; n_frames];
    for i in 0..pixel_count {
        for (f, frame) in frame_pixels.iter().enumerate() {
            scratch[f] = frame[i];
        }
        scratch.sort_unstable();
        let mid = n_frames / 2;
        let median = if n_frames.is_multiple_of(2) {
            (scratch[mid - 1] as f64 + scratch[mid] as f64) / 2.0
        } else {
            scratch[mid] as f64
        };
        per_pixel_medians.push(median);
    }

    let mut sorted = per_pixel_medians.clone();
    sorted.sort_unstable_by(|a, b| a.total_cmp(b));
    let global_median = sample_median_sorted(&sorted);

    let mut deviations: Vec<f64> = per_pixel_medians
        .iter()
        .map(|p| (p - global_median).abs())
        .collect();
    deviations.sort_unstable_by(|a, b| a.total_cmp(b));
    let mad = sample_median_sorted(&deviations).max(1.0e-9);

    let upper_threshold = global_median + DEFECT_MAD_K * mad;
    let lower_threshold = global_median - DEFECT_MAD_K * mad;

    let mut map = DefectMap::empty(width, height, temperature_bucket_decicelsius);

    for i in 0..pixel_count {
        let med = per_pixel_medians[i];
        if med <= upper_threshold && med >= lower_threshold {
            continue;
        }
        let mut outlier_frames = 0usize;
        for frame in &frame_pixels {
            let v = frame[i] as f64;
            if v > upper_threshold || v < lower_threshold {
                outlier_frames += 1;
                if outlier_frames >= MIN_CONSISTENCY_FRAMES {
                    break;
                }
            }
        }
        if outlier_frames >= MIN_CONSISTENCY_FRAMES {
            let x = (i % width as usize) as u32;
            let y = (i / width as usize) as u32;
            map.mark_defective(x, y);
        }
    }

    Ok(map)
}

#[inline]
fn sample_median_sorted(sorted: &[f64]) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let mid = sorted.len() / 2;
    if sorted.len().is_multiple_of(2) {
        (sorted[mid - 1] + sorted[mid]) / 2.0
    } else {
        sorted[mid]
    }
}

/// Apply a defect map to a U16 light frame in place.
///
/// Why neighbour-median replacement: zeroing or NaN-marking defective
/// pixels propagates a hole through downstream debayering, stretching and
/// star detection that creates a visible artefact. The local median
/// preserves frame statistics.
pub fn correct_frame_u16(light: &mut ImageData, map: &DefectMap) -> Result<(), DefectMapError> {
    if light.pixel_type != PixelType::U16 {
        return Err(DefectMapError::UnsupportedPixelType {
            pixel_type: light.pixel_type,
        });
    }
    if light.width != map.width || light.height != map.height {
        return Err(DefectMapError::DimensionMismatchOnApply {
            frame_width: light.width,
            frame_height: light.height,
            map_width: map.width,
            map_height: map.height,
        });
    }
    if map.defective_count == 0 {
        return Ok(());
    }

    let width = light.width as i32;
    let height = light.height as i32;
    let w_usize = light.width as usize;
    let channels = light.channels as usize;

    let pixel_count = (width as usize) * (height as usize) * channels;
    let expected_bytes = pixel_count * 2;
    if light.data.len() != expected_bytes {
        return Err(DefectMapError::DimensionMismatchOnApply {
            frame_width: light.width,
            frame_height: light.height,
            map_width: map.width,
            map_height: map.height,
        });
    }

    let mut neighbour_scratch: Vec<u16> = Vec::with_capacity(25);

    for y in 0..height {
        for x in 0..width {
            if !map.is_defective(x as u32, y as u32) {
                continue;
            }
            for c in 0..channels {
                neighbour_scratch.clear();
                let mut defective_in_3x3 = 0u32;
                for dy in -1..=1 {
                    for dx in -1..=1 {
                        if dx == 0 && dy == 0 {
                            continue;
                        }
                        let nx = x + dx;
                        let ny = y + dy;
                        if nx < 0 || nx >= width || ny < 0 || ny >= height {
                            continue;
                        }
                        if map.is_defective(nx as u32, ny as u32) {
                            defective_in_3x3 += 1;
                            continue;
                        }
                        neighbour_scratch.push(read_u16_pixel(
                            &light.data,
                            nx as usize,
                            ny as usize,
                            c,
                            w_usize,
                            channels,
                        ));
                    }
                }
                // Why fall back to 5x5: if 8 or 9 of the 9 3x3 pixels are
                // defective (a cluster), the 3x3 median is unreliable.
                // The wider window finds healthy pixels just outside.
                if neighbour_scratch.len() <= 1 || defective_in_3x3 >= 8 {
                    neighbour_scratch.clear();
                    for dy in -2..=2 {
                        for dx in -2..=2 {
                            if dx == 0 && dy == 0 {
                                continue;
                            }
                            let nx = x + dx;
                            let ny = y + dy;
                            if nx < 0 || nx >= width || ny < 0 || ny >= height {
                                continue;
                            }
                            if map.is_defective(nx as u32, ny as u32) {
                                continue;
                            }
                            neighbour_scratch.push(read_u16_pixel(
                                &light.data,
                                nx as usize,
                                ny as usize,
                                c,
                                w_usize,
                                channels,
                            ));
                        }
                    }
                }
                if neighbour_scratch.is_empty() {
                    // Why preserve original: zero good neighbours means
                    // the whole local region is defective. Zeroing would
                    // produce a black hole that stretching amplifies into
                    // a visible artefact; leaving the raw value is the
                    // less destructive choice, and the count reported back
                    // to the user makes the issue visible.
                    continue;
                }
                neighbour_scratch.sort_unstable();
                let mid = neighbour_scratch.len() / 2;
                let median = if neighbour_scratch.len().is_multiple_of(2) {
                    ((neighbour_scratch[mid - 1] as u32 + neighbour_scratch[mid] as u32) / 2)
                        as u16
                } else {
                    neighbour_scratch[mid]
                };
                write_u16_pixel(
                    &mut light.data,
                    x as usize,
                    y as usize,
                    c,
                    w_usize,
                    channels,
                    median,
                );
            }
        }
    }

    Ok(())
}

#[inline]
fn read_u16_pixel(
    data: &[u8],
    x: usize,
    y: usize,
    channel: usize,
    width: usize,
    channels: usize,
) -> u16 {
    let pixel_idx = (y * width + x) * channels + channel;
    let byte_idx = pixel_idx * 2;
    u16::from_le_bytes([data[byte_idx], data[byte_idx + 1]])
}

#[inline]
fn write_u16_pixel(
    data: &mut [u8],
    x: usize,
    y: usize,
    channel: usize,
    width: usize,
    channels: usize,
    value: u16,
) {
    let pixel_idx = (y * width + x) * channels + channel;
    let byte_idx = pixel_idx * 2;
    let bytes = value.to_le_bytes();
    data[byte_idx] = bytes[0];
    data[byte_idx + 1] = bytes[1];
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flat_dark(width: u32, height: u32, value: u16) -> ImageData {
        let pixels = vec![value; (width * height) as usize];
        ImageData::from_u16(width, height, 1, &pixels)
    }

    fn with_hot(width: u32, height: u32, base: u16, hot: &[(u32, u32, u16)]) -> ImageData {
        let mut pixels = vec![base; (width * height) as usize];
        for &(x, y, v) in hot {
            pixels[(y * width + x) as usize] = v;
        }
        ImageData::from_u16(width, height, 1, &pixels)
    }

    #[test]
    fn detects_three_hot_pixels_in_10x10_stack() {
        let w = 10u32;
        let h = 10u32;
        let hot = [(1u32, 1u32, 60000u16), (5, 4, 65000), (8, 9, 62000)];
        let frames: Vec<ImageData> = (0..8)
            .map(|i| with_hot(w, h, 1000u16 + (i as u16 % 3), &hot))
            .collect();
        let refs: Vec<&ImageData> = frames.iter().collect();

        let map = build_defect_map(&refs, -200).expect("detection should succeed");
        assert_eq!(map.defective_count(), 3);
        for (x, y, _) in hot {
            assert!(
                map.is_defective(x, y),
                "expected ({}, {}) to be flagged defective",
                x,
                y
            );
        }
        assert!(!map.is_defective(0, 0));
        assert!(!map.is_defective(4, 4));
    }

    #[test]
    fn rejects_single_frame_outlier_as_cosmic_ray() {
        let w = 10u32;
        let h = 10u32;
        // 7 clean frames, 1 frame with a single hot pixel: should NOT be
        // flagged because consistency check requires 5 frames of outlier.
        let mut frames: Vec<ImageData> = (0..7).map(|_| flat_dark(w, h, 1000)).collect();
        let cosmic_pixels = {
            let mut p = vec![1000u16; (w * h) as usize];
            p[2 * w as usize + 2] = 65535;
            p
        };
        frames.push(ImageData::from_u16(w, h, 1, &cosmic_pixels));
        let refs: Vec<&ImageData> = frames.iter().collect();

        let map = build_defect_map(&refs, -150).expect("detection should succeed");
        assert_eq!(map.defective_count(), 0);
        assert!(!map.is_defective(2, 2));
    }

    #[test]
    fn corrects_hot_pixel_with_neighbour_median() {
        let w = 5u32;
        let h = 5u32;
        let mut pixels = vec![1000u16; (w * h) as usize];
        pixels[2 * w as usize + 2] = 65535;
        let mut light = ImageData::from_u16(w, h, 1, &pixels);

        let mut map = DefectMap::empty(w, h, -200);
        map.mark_defective(2, 2);

        correct_frame_u16(&mut light, &map).expect("correction should succeed");
        let corrected = light.as_u16().expect("u16 light");
        assert_eq!(corrected[2 * w as usize + 2], 1000);
    }

    #[test]
    fn correction_falls_back_to_5x5_when_3x3_is_mostly_defective() {
        let w = 7u32;
        let h = 7u32;
        let mut pixels = vec![1000u16; (w * h) as usize];
        for dy in -1i32..=1 {
            for dx in -1i32..=1 {
                let x = (3i32 + dx) as u32;
                let y = (3i32 + dy) as u32;
                pixels[(y * w + x) as usize] = 65535;
            }
        }
        let mut light = ImageData::from_u16(w, h, 1, &pixels);

        let mut map = DefectMap::empty(w, h, -200);
        for dy in -1i32..=1 {
            for dx in -1i32..=1 {
                map.mark_defective((3i32 + dx) as u32, (3i32 + dy) as u32);
            }
        }

        correct_frame_u16(&mut light, &map).expect("correction should succeed");
        let corrected = light.as_u16().expect("u16 light");
        assert_eq!(corrected[3 * w as usize + 3], 1000);
        assert_eq!(corrected[2 * w as usize + 2], 1000);
    }

    #[test]
    fn ndm_round_trip_preserves_map_contents() {
        let mut map = DefectMap::empty(13, 17, -275);
        map.mark_defective(0, 0);
        map.mark_defective(12, 16);
        map.mark_defective(7, 9);
        map.mark_defective(5, 5);

        let bytes = map.serialize();
        assert!(bytes.starts_with(NDM_MAGIC));

        let restored = DefectMap::deserialize(&bytes).expect("round trip should succeed");
        assert_eq!(restored.width, 13);
        assert_eq!(restored.height, 17);
        assert_eq!(restored.temperature_bucket_decicelsius, -275);
        assert_eq!(restored.defective_count(), 4);
        assert!(restored.is_defective(0, 0));
        assert!(restored.is_defective(12, 16));
        assert!(restored.is_defective(7, 9));
        assert!(restored.is_defective(5, 5));
        assert!(!restored.is_defective(1, 1));
    }

    #[test]
    fn ndm_rejects_bad_magic() {
        let mut map = DefectMap::empty(4, 4, 0);
        map.mark_defective(0, 0);
        let mut bytes = map.serialize();
        bytes[0] = b'X';
        assert!(matches!(
            DefectMap::deserialize(&bytes),
            Err(DefectMapError::BadMagic)
        ));
    }

    #[test]
    fn ndm_rejects_truncated() {
        let mut map = DefectMap::empty(4, 4, 0);
        map.mark_defective(0, 0);
        let bytes = map.serialize();
        let truncated = &bytes[..bytes.len() - 1];
        assert!(matches!(
            DefectMap::deserialize(truncated),
            Err(DefectMapError::Truncated { .. })
        ));
    }

    #[test]
    fn temperature_bucketing_rounds_to_nearest_5c() {
        assert_eq!(bucket_temperature(-22.3), -200);
        assert_eq!(bucket_temperature(-22.6), -250);
        assert_eq!(bucket_temperature(0.0), 0);
        assert_eq!(bucket_temperature(7.4), 50);
        assert_eq!(bucket_temperature(7.6), 100);
        assert_eq!(bucket_temperature(27.4), 250);
    }

    #[test]
    fn build_rejects_insufficient_frames() {
        let frames: Vec<ImageData> = (0..3).map(|_| flat_dark(4, 4, 1000)).collect();
        let refs: Vec<&ImageData> = frames.iter().collect();
        assert!(matches!(
            build_defect_map(&refs, 0),
            Err(DefectMapError::InsufficientFrames { .. })
        ));
    }

    #[test]
    fn build_rejects_empty_stack() {
        let refs: Vec<&ImageData> = Vec::new();
        assert!(matches!(
            build_defect_map(&refs, 0),
            Err(DefectMapError::EmptyStack)
        ));
    }

    #[test]
    fn apply_rejects_dimension_mismatch() {
        let mut light = flat_dark(4, 4, 1000);
        let mut map = DefectMap::empty(5, 5, 0);
        map.mark_defective(0, 0);
        assert!(matches!(
            correct_frame_u16(&mut light, &map),
            Err(DefectMapError::DimensionMismatchOnApply { .. })
        ));
    }

    #[test]
    fn file_round_trip() {
        let path = std::env::temp_dir().join(format!(
            "nightshade_defect_map_test_{}.ndm",
            std::process::id()
        ));
        let mut map = DefectMap::empty(8, 8, -200);
        map.mark_defective(3, 3);
        map.mark_defective(0, 7);
        map.write_to_file(&path).expect("write");
        let loaded = DefectMap::read_from_file(&path).expect("read");
        assert_eq!(loaded.width, 8);
        assert_eq!(loaded.height, 8);
        assert_eq!(loaded.temperature_bucket_decicelsius, -200);
        assert_eq!(loaded.defective_count(), 2);
        assert!(loaded.is_defective(3, 3));
        assert!(loaded.is_defective(0, 7));
        let _ = std::fs::remove_file(&path);
    }
}
