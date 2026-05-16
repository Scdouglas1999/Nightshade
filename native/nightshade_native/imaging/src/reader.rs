//! Memory-mapped image reader for large files
//!
//! This module provides efficient reading of large image files without
//! loading the entire file into memory. Useful for:
//! - Preview generation from 60MP+ images
//! - Region-of-interest extraction
//! - Streaming operations
//!
//! # `unwrap_or` policy (audit-rust §4.3)
//!
//! Three FITS-standard fallbacks appear in this reader:
//!
//! * `NAXIS3.unwrap_or(1)` — `NAXIS3` (channel count) is only present for
//!   3D FITS cubes; absent for 2D mono frames where the FITS spec defines
//!   the implicit channel count as 1.
//! * `BZERO.unwrap_or(0.0)`, `BSCALE.unwrap_or(1.0)` — these are the
//!   FITS 4.0 spec defaults for the linear pixel-value transform when the
//!   keywords are absent: `physical_value = BZERO + BSCALE * stored_value`
//!   degenerates to identity at `(0.0, 1.0)`.
//! * `extension().unwrap_or("")` — no extension on the file path; empty
//!   string flows through to the format-detection arm that fails with a
//!   real error if no magic-bytes match.

use crate::{FitsError, FitsHeader, ImageData, PixelType};
use image::GenericImageView;
use memmap2::Mmap;
use std::fs::File;
use std::path::Path;

/// Memory-mapped image reader for large FITS files
pub struct MappedFitsReader {
    mmap: Mmap,
    width: u32,
    height: u32,
    channels: u32,
    pixel_type: PixelType,
    data_offset: usize,
    header: FitsHeader,
}

impl MappedFitsReader {
    /// Open a FITS file with memory mapping
    pub fn open(path: &Path) -> Result<Self, FitsError> {
        let file = File::open(path)?;
        // SAFETY: `Mmap::map` is `unsafe` because callers must ensure the mapped file is
        // not concurrently modified by another process (which could violate the
        // immutable-byte-slice invariant the `Mmap` exposes). FITS captures we open here
        // are produced and finalized by the capture path before being read, and this
        // reader takes a `&Path` for read-only access — no writer holds the file. The
        // returned `Mmap` is owned by `Self` and stays alive for the reader's lifetime.
        let mmap = unsafe { Mmap::map(&file)? };

        // Parse header to get dimensions
        let mut cursor = std::io::Cursor::new(&mmap[..]);
        let header = crate::fits::read_header(&mut cursor)?;

        // Get image dimensions from header
        let bitpix = header
            .get_int("BITPIX")
            .ok_or_else(|| FitsError::MissingKeyword("BITPIX".to_string()))?;
        let naxis = header
            .get_int("NAXIS")
            .ok_or_else(|| FitsError::MissingKeyword("NAXIS".to_string()))?;

        if naxis == 0 {
            return Err(FitsError::InvalidFormat(
                "No image data in FITS file".to_string(),
            ));
        }

        let width = header
            .get_int("NAXIS1")
            .ok_or_else(|| FitsError::MissingKeyword("NAXIS1".to_string()))?
            as u32;
        let height = if naxis >= 2 {
            header
                .get_int("NAXIS2")
                .ok_or_else(|| FitsError::MissingKeyword("NAXIS2".to_string()))? as u32
        } else {
            1
        };
        let channels = if naxis >= 3 {
            header.get_int("NAXIS3").unwrap_or(1) as u32
        } else {
            1
        };

        let pixel_type = match bitpix as i32 {
            8 => PixelType::U8,
            16 => PixelType::U16,
            32 => PixelType::U32,
            -32 => PixelType::F32,
            -64 => PixelType::F64,
            other => return Err(FitsError::UnsupportedBitpix(other)),
        };

        // `read_header` already consumes the full FITS header and skips the
        // required padding, so the cursor now points at the exact data start.
        let data_offset = usize::try_from(cursor.position()).map_err(|_| {
            FitsError::InvalidFormat("FITS data offset exceeds platform limits".to_string())
        })?;

        tracing::info!(
            "Opened memory-mapped FITS: {}x{}x{}, type {:?}, data offset: {}",
            width,
            height,
            channels,
            pixel_type,
            data_offset
        );

        Ok(Self {
            mmap,
            width,
            height,
            channels,
            pixel_type,
            data_offset,
            header,
        })
    }

    /// Get image dimensions
    pub fn dimensions(&self) -> (u32, u32, u32) {
        (self.width, self.height, self.channels)
    }

    /// Get pixel type
    pub fn pixel_type(&self) -> PixelType {
        self.pixel_type
    }

    /// Get header
    pub fn header(&self) -> &FitsHeader {
        &self.header
    }

    /// Read a specific region without loading the full image
    ///
    /// This is much more memory-efficient than loading the entire image
    /// when you only need a small region (e.g., for preview or ROI analysis)
    pub fn read_region(
        &self,
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    ) -> Result<ImageData, FitsError> {
        // Validate bounds
        if x + width > self.width || y + height > self.height {
            return Err(FitsError::InvalidFormat(format!(
                "Region {}x{} at ({},{}) exceeds image bounds {}x{}",
                width, height, x, y, self.width, self.height
            )));
        }

        let bytes_per_pixel = self.pixel_type.byte_size();
        let channels = self.channels as usize;
        let stride = (self.width as usize) * bytes_per_pixel * channels;

        let region_size = (width as usize) * (height as usize) * bytes_per_pixel * channels;
        let mut region_data = Vec::with_capacity(region_size);

        // Read row by row from memory-mapped file
        for row in y..(y + height) {
            let row_offset = self.data_offset + (row as usize) * stride;
            let col_offset = (x as usize) * bytes_per_pixel * channels;
            let offset = row_offset + col_offset;
            let length = (width as usize) * bytes_per_pixel * channels;

            if offset + length <= self.mmap.len() {
                // Convert from big-endian (FITS standard) to little-endian
                let row_data = &self.mmap[offset..offset + length];
                region_data.extend_from_slice(row_data);
            } else {
                return Err(FitsError::InvalidFormat(
                    "Region read out of bounds".to_string(),
                ));
            }
        }

        // Convert from FITS big-endian to system little-endian
        let converted_data = self.convert_endianness(&region_data)?;

        Ok(ImageData {
            width,
            height,
            channels: self.channels,
            pixel_type: self.pixel_type,
            data: converted_data,
        })
    }

    /// Convert from FITS big-endian to little-endian
    fn convert_endianness(&self, data: &[u8]) -> Result<Vec<u8>, FitsError> {
        let bzero = self.header.get_float("BZERO").unwrap_or(0.0);
        let bscale = self.header.get_float("BSCALE").unwrap_or(1.0);

        match self.pixel_type {
            PixelType::U8 => {
                // U8 doesn't need endian conversion
                Ok(data.to_vec())
            }
            PixelType::U16 => {
                // Convert i16 big-endian to u16 little-endian
                let converted: Vec<u8> = data
                    .chunks_exact(2)
                    .flat_map(|chunk| {
                        let val = i16::from_be_bytes([chunk[0], chunk[1]]);
                        let adjusted = if bzero == 32768.0 {
                            (val as i32 + 32768).clamp(0, 65535) as u16
                        } else {
                            ((val as f64 * bscale + bzero).clamp(0.0, 65535.0)) as u16
                        };
                        adjusted.to_le_bytes()
                    })
                    .collect();
                Ok(converted)
            }
            PixelType::F32 => {
                // Convert f32 big-endian to little-endian
                let converted: Vec<u8> = data
                    .chunks_exact(4)
                    .flat_map(|chunk| {
                        let val = f32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                        let adjusted = val * bscale as f32 + bzero as f32;
                        adjusted.to_le_bytes()
                    })
                    .collect();
                Ok(converted)
            }
            _ => Ok(data.to_vec()),
        }
    }

    /// Read downsampled version of the full image
    ///
    /// Reads every Nth pixel to create a smaller version, useful for thumbnails.
    /// This is much faster than reading the full image and then downsampling.
    pub fn read_downsampled(&self, downsample_factor: u32) -> Result<ImageData, FitsError> {
        if downsample_factor == 0 {
            return Err(FitsError::InvalidFormat(
                "Downsample factor must be > 0".to_string(),
            ));
        }

        let out_width = self.width.div_ceil(downsample_factor);
        let out_height = self.height.div_ceil(downsample_factor);

        let bytes_per_pixel = self.pixel_type.byte_size();
        let channels = self.channels as usize;
        let stride = (self.width as usize) * bytes_per_pixel * channels;

        let output_size = (out_width as usize) * (out_height as usize) * bytes_per_pixel * channels;
        let mut output_data = Vec::with_capacity(output_size);

        // Sample every Nth row and column
        for out_y in 0..out_height {
            let src_y = (out_y * downsample_factor) as usize;
            let row_offset = self.data_offset + src_y * stride;

            for out_x in 0..out_width {
                let src_x = (out_x * downsample_factor) as usize;
                let pixel_offset = row_offset + src_x * bytes_per_pixel * channels;

                if pixel_offset + bytes_per_pixel * channels > self.mmap.len() {
                    return Err(FitsError::InvalidFormat(
                        "Downsampled FITS read exceeded mapped image bounds".to_string(),
                    ));
                }

                let pixel_data =
                    &self.mmap[pixel_offset..pixel_offset + bytes_per_pixel * channels];
                output_data.extend_from_slice(pixel_data);
            }
        }

        if output_data.len() != output_size {
            return Err(FitsError::InvalidFormat(format!(
                "Downsampled FITS read produced {} bytes, expected {}",
                output_data.len(),
                output_size
            )));
        }

        // Convert endianness
        let converted_data = self.convert_endianness(&output_data)?;

        tracing::info!(
            "Downsampled {}x{} to {}x{} (factor {})",
            self.width,
            self.height,
            out_width,
            out_height,
            downsample_factor
        );

        Ok(ImageData {
            width: out_width,
            height: out_height,
            channels: self.channels,
            pixel_type: self.pixel_type,
            data: converted_data,
        })
    }

    /// Get total file size
    pub fn file_size(&self) -> usize {
        self.mmap.len()
    }
}

/// Generate a preview thumbnail without loading the full image
///
/// This function intelligently selects the best method:
/// - For RAW files: extract embedded JPEG preview
/// - For FITS: use memory-mapped downsampling
/// - For TIFF/PNG: use image library with subsampling
pub fn generate_thumbnail(path: &Path, max_dimension: u32) -> Result<ImageData, String> {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");

    match ext.to_lowercase().as_str() {
        // RAW formats - use LibRaw embedded preview
        "cr2" | "cr3" | "nef" | "arw" | "raf" | "pef" | "orf" | "rw2" => {
            tracing::info!("Extracting RAW thumbnail from {}", path.display());
            crate::raw::extract_thumbnail(path).map_err(|e| e.to_string())
        }

        // FITS - use memory-mapped downsampling
        "fits" | "fit" | "fts" => {
            tracing::info!("Generating FITS thumbnail from {}", path.display());
            let reader = MappedFitsReader::open(path).map_err(|e| e.to_string())?;

            let (width, height, _) = reader.dimensions();
            let max_dim = width.max(height);
            let downsample = max_dim.div_ceil(max_dimension);

            if downsample <= 1 {
                // Image is already small, read full
                reader
                    .read_region(0, 0, width, height)
                    .map_err(|e| e.to_string())
            } else {
                reader
                    .read_downsampled(downsample)
                    .map_err(|e| e.to_string())
            }
        }

        // Other formats - use image crate
        _ => {
            tracing::info!("Loading thumbnail with image crate from {}", path.display());
            let img = image::open(path).map_err(|e| format!("Failed to open image: {}", e))?;

            let (width, height) = img.dimensions();
            let scale = (width.max(height) as f32) / (max_dimension as f32);

            if scale <= 1.0 {
                // Already small enough
                let rgba = img.to_rgba8();
                Ok(ImageData {
                    width,
                    height,
                    channels: 4,
                    pixel_type: PixelType::U8,
                    data: rgba.into_raw(),
                })
            } else {
                let new_width = (width as f32 / scale) as u32;
                let new_height = (height as f32 / scale) as u32;

                let thumbnail = img.thumbnail(new_width, new_height);
                let rgba = thumbnail.to_rgba8();

                Ok(ImageData {
                    width: new_width,
                    height: new_height,
                    channels: 4,
                    pixel_type: PixelType::U8,
                    data: rgba.into_raw(),
                })
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::MappedFitsReader;
    use crate::{write_fits, FitsError, FitsHeader, ImageData, PixelType};
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_path(name: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock before epoch")
            .as_nanos();
        std::env::temp_dir().join(format!("nightshade_reader_{name}_{unique}.fits"))
    }

    #[test]
    fn test_thumbnail_max_dimension() {
        // Test would require actual image files
        // This path exists for integration tests
    }

    #[test]
    fn mapped_reader_open_rejects_header_without_end() {
        let path = temp_path("missing_end");
        let invalid_header = vec![b' '; 2880];
        fs::write(&path, invalid_header).expect("failed to write malformed FITS");

        let result = MappedFitsReader::open(&path);
        let _ = fs::remove_file(&path);

        assert!(result.is_err(), "missing END keyword should be rejected");
    }

    #[test]
    fn mapped_reader_reads_valid_fits_written_by_writer() {
        let path = temp_path("valid");
        let image = ImageData {
            width: 2,
            height: 2,
            channels: 1,
            pixel_type: PixelType::U8,
            data: vec![1, 2, 3, 4],
        };
        let header = FitsHeader::new();
        write_fits(&path, &image, &header).expect("failed to write FITS");

        let reader = MappedFitsReader::open(&path).expect("reader should open valid FITS");
        let region = reader
            .read_region(0, 0, 2, 2)
            .expect("reader should return the stored pixels");
        let _ = fs::remove_file(&path);

        assert_eq!(region.data, image.data);
    }

    #[test]
    fn mapped_reader_requires_naxis2_for_2d_images() {
        let path = temp_path("missing_naxis2");
        let mut bytes = vec![b' '; 2880];
        let cards = [
            "SIMPLE  =                    T",
            "BITPIX  =                    8",
            "NAXIS   =                    2",
            "NAXIS1  =                    2",
            "END",
        ];

        for (idx, card) in cards.iter().enumerate() {
            let offset = idx * 80;
            let mut card_bytes = [b' '; 80];
            let raw = card.as_bytes();
            card_bytes[..raw.len()].copy_from_slice(raw);
            bytes[offset..offset + 80].copy_from_slice(&card_bytes);
        }

        fs::write(&path, bytes).expect("failed to write malformed FITS");
        let result = MappedFitsReader::open(&path);
        let _ = fs::remove_file(&path);

        assert!(matches!(result, Err(FitsError::MissingKeyword(keyword)) if keyword == "NAXIS2"));
    }
}
