//! Real FITS file I/O
//!
//! Implements actual FITS file reading and writing according to the
//! FITS standard (NASA/Science Office of Standards and Technology).
//!
//! FITS format:
//! - 2880-byte blocks
//! - Header with 80-character keyword records
//! - Data in big-endian format
//!
//! # `as`-cast policy (audit-rust §1.4)
//!
//! FITS pixel I/O involves many wire-format scalar casts. They cluster into:
//! - **BITPIX dispatch** (`bitpix as i32`): FITS BITPIX is an integer in
//!   {8, 16, 32, 64, -32, -64}. The cast is over a small set of statically
//!   known constants.
//! - **Pixel-buffer rescaling**: `v as f64 * bscale + bzero` saturating into
//!   {u8,u16,u32,f32}. The `.clamp(...)` and `as` saturation match the FITS
//!   spec's expectation that out-of-range scaled values are clipped.
//! - **`width * height * depth`** in `(_ as usize)` form: these are u32 image
//!   dimensions; for sensors below ~46340x46340x1 the u32 multiply fits, and
//!   the resulting size is also valid usize. Allocation failure surfaces from
//!   `Vec` itself on >RAM sizes.
//!
//! Sites with their own `Why:` comment override the module-level reasoning.

use crate::{BayerPattern, ImageData, PixelType};
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Seek, Write};
use std::path::Path;

/// FITS header containing all keywords plus separate COMMENT and HISTORY blocks.
///
/// Why: COMMENT and HISTORY are not value cards — they have no `=` separator and
/// the card body is a free-form text run from columns 9..80. Storing them in the
/// same `keywords` map as value cards (with synthetic names like `COMMENT_3`)
/// produced malformed cards on writeback and silently corrupted round-trips.
#[derive(Debug, Clone, Default)]
pub struct FitsHeader {
    /// Keyword-value pairs (uppercase keys; never includes COMMENT/HISTORY).
    pub keywords: HashMap<String, FitsValue>,
    /// Keywords in original order (for stable rewrite).
    keyword_order: Vec<String>,
    /// Optional inline comment text for each keyword (`KEY = value / comment`).
    keyword_comments: HashMap<String, String>,
    /// COMMENT card text in original order.
    pub comments: Vec<String>,
    /// HISTORY card text in original order.
    pub history: Vec<String>,
}

/// FITS value types. COMMENT/HISTORY are intentionally NOT a value variant —
/// they live in `FitsHeader::comments` and `FitsHeader::history` because they
/// are not value cards in the FITS sense.
#[derive(Debug, Clone)]
pub enum FitsValue {
    String(String),
    Integer(i64),
    Float(f64),
    Boolean(bool),
    /// Retained only for backward source compatibility; never produced by the
    /// reader and treated as a free-form value-style string by the writer.
    Comment(String),
}

impl FitsValue {
    pub fn as_string(&self) -> Option<&str> {
        match self {
            FitsValue::String(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            FitsValue::Integer(i) => Some(*i),
            FitsValue::Float(f) => Some(*f as i64),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            FitsValue::Float(f) => Some(*f),
            FitsValue::Integer(i) => Some(*i as f64),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            FitsValue::Boolean(b) => Some(*b),
            _ => None,
        }
    }
}

impl FitsHeader {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_string(&mut self, key: &str, value: &str) {
        let key_upper = key.to_uppercase();
        if !self.keyword_order.contains(&key_upper) {
            self.keyword_order.push(key_upper.clone());
        }
        self.keywords
            .insert(key_upper, FitsValue::String(value.to_string()));
    }

    pub fn set_int(&mut self, key: &str, value: i64) {
        let key_upper = key.to_uppercase();
        if !self.keyword_order.contains(&key_upper) {
            self.keyword_order.push(key_upper.clone());
        }
        self.keywords.insert(key_upper, FitsValue::Integer(value));
    }

    pub fn set_float(&mut self, key: &str, value: f64) {
        let key_upper = key.to_uppercase();
        if !self.keyword_order.contains(&key_upper) {
            self.keyword_order.push(key_upper.clone());
        }
        self.keywords.insert(key_upper, FitsValue::Float(value));
    }

    pub fn set_bool(&mut self, key: &str, value: bool) {
        let key_upper = key.to_uppercase();
        if !self.keyword_order.contains(&key_upper) {
            self.keyword_order.push(key_upper.clone());
        }
        self.keywords.insert(key_upper, FitsValue::Boolean(value));
    }

    /// Attach an inline comment to an existing keyword. Emitted as
    /// `KEY = value / comment` on write, truncated if the card would exceed 80 bytes.
    pub fn set_comment(&mut self, key: &str, comment: &str) {
        self.keyword_comments
            .insert(key.to_uppercase(), comment.to_string());
    }

    /// Append a free-form COMMENT card.
    pub fn add_comment(&mut self, text: &str) {
        self.comments.push(text.to_string());
    }

    /// Append a HISTORY card.
    pub fn add_history(&mut self, text: &str) {
        self.history.push(text.to_string());
    }

    /// Remove a keyword (and any inline comment) from the header.
    fn remove(&mut self, key: &str) {
        let key_upper = key.to_uppercase();
        self.keywords.remove(&key_upper);
        self.keyword_comments.remove(&key_upper);
        self.keyword_order.retain(|k| k != &key_upper);
    }

    pub fn get(&self, key: &str) -> Option<&FitsValue> {
        self.keywords.get(&key.to_uppercase())
    }

    pub fn get_string(&self, key: &str) -> Option<&str> {
        self.get(key).and_then(|v| v.as_string())
    }

    pub fn get_int(&self, key: &str) -> Option<i64> {
        self.get(key).and_then(|v| v.as_i64())
    }

    pub fn get_float(&self, key: &str) -> Option<f64> {
        self.get(key).and_then(|v| v.as_f64())
    }

    pub fn get_comment(&self, key: &str) -> Option<&str> {
        self.keyword_comments
            .get(&key.to_uppercase())
            .map(|s| s.as_str())
    }
}

/// FITS file reading errors
#[derive(Debug)]
pub enum FitsError {
    Io(std::io::Error),
    InvalidFormat(String),
    UnsupportedBitpix(i32),
    MissingKeyword(String),
    /// FITS files with NAXIS > 3 (4-D cubes / hyperspectral) are not supported.
    /// Why: silently dropping planes corrupts science data; explicit failure forces
    /// the caller to choose a real handling strategy.
    Unsupported4DCube { naxis: i64 },
    /// Caller passed a sub-horizon altitude to an airmass routine; the optical
    /// path is undefined below the horizon. The caller decides how to handle.
    BelowHorizon { altitude_degrees: f64 },
}

impl std::fmt::Display for FitsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FitsError::Io(e) => write!(f, "IO error: {}", e),
            FitsError::InvalidFormat(s) => write!(f, "Invalid FITS format: {}", s),
            FitsError::UnsupportedBitpix(b) => write!(f, "Unsupported BITPIX: {}", b),
            FitsError::MissingKeyword(k) => write!(f, "Missing required keyword: {}", k),
            FitsError::Unsupported4DCube { naxis } => write!(
                f,
                "Unsupported FITS dimensionality: NAXIS={} (only NAXIS<=3 is supported)",
                naxis
            ),
            FitsError::BelowHorizon { altitude_degrees } => write!(
                f,
                "Altitude {:.4}° is below the horizon; airmass is undefined",
                altitude_degrees
            ),
        }
    }
}

impl std::error::Error for FitsError {}

impl From<std::io::Error> for FitsError {
    fn from(e: std::io::Error) -> Self {
        FitsError::Io(e)
    }
}

/// Read a FITS file from disk
pub fn read_fits(path: &Path) -> Result<(ImageData, FitsHeader), FitsError> {
    let file = File::open(path)?;
    let mut reader = BufReader::new(file);
    read_fits_from_reader(&mut reader)
}

/// Read FITS from memory buffer
pub fn read_fits_from_bytes(bytes: &[u8]) -> Result<(ImageData, FitsHeader), FitsError> {
    let mut reader = std::io::Cursor::new(bytes);
    read_fits_from_reader(&mut reader)
}

/// Internal function to read FITS from any reader
fn read_fits_from_reader<R: Read>(reader: &mut R) -> Result<(ImageData, FitsHeader), FitsError> {
    // Read header
    let mut header = read_header(reader)?;

    // Get image dimensions
    let bitpix = header
        .get_int("BITPIX")
        .ok_or_else(|| FitsError::MissingKeyword("BITPIX".to_string()))?;
    let naxis = header
        .get_int("NAXIS")
        .ok_or_else(|| FitsError::MissingKeyword("NAXIS".to_string()))?;

    if naxis == 0 {
        // No data, just header
        return Ok((ImageData::new(0, 0, 1, PixelType::U16), header));
    }

    // Why: 4-D cubes (NAXIS > 3) cannot be represented by `ImageData` (which has a
    // single channel/depth axis). Silently loading only the first plane corrupts
    // science workflows that depend on the full cube. Reject explicitly per audit §6.5.
    if naxis > 3 {
        return Err(FitsError::Unsupported4DCube { naxis });
    }

    let width = header
        .get_int("NAXIS1")
        .ok_or_else(|| FitsError::MissingKeyword("NAXIS1".to_string()))? as u32;
    let height = if naxis >= 2 {
        header
            .get_int("NAXIS2")
            .ok_or_else(|| FitsError::MissingKeyword("NAXIS2".to_string()))? as u32
    } else {
        1
    };
    let depth = if naxis >= 3 {
        header
            .get_int("NAXIS3")
            .ok_or_else(|| FitsError::MissingKeyword("NAXIS3".to_string()))? as u32
    } else {
        1
    };

    // Get scaling parameters. Why: per FITS 4.4.2.5, the in-memory data after applying
    // BSCALE/BZERO is the "physical" value; storing the original BSCALE/BZERO in the
    // returned header would cause a subsequent write_fits to apply a second scaling pass
    // (audit §6.3 — CRITICAL data corruption).
    // Why (audit-rust §4.3): per FITS standard 4.4.2.5, BZERO and BSCALE are OPTIONAL
    // header cards; when absent the convention is BZERO=0.0, BSCALE=1.0 (the identity
    // transform). These are documented defaults, not silent error fallbacks.
    let bzero = header.get_float("BZERO").unwrap_or(0.0);
    let bscale = header.get_float("BSCALE").unwrap_or(1.0);

    // Determine pixel type and read data
    let (pixel_type, data) = match bitpix as i32 {
        8 => {
            let raw = read_u8_data(reader, width, height, depth)?;
            // Apply scaling if needed
            if bzero != 0.0 || bscale != 1.0 {
                let scaled: Vec<u8> = raw
                    .iter()
                    .map(|&v| ((v as f64 * bscale + bzero) as i32).clamp(0, 255) as u8)
                    .collect();
                (PixelType::U8, scaled)
            } else {
                (PixelType::U8, raw)
            }
        }
        16 => {
            let raw = read_i16_data(reader, width, height, depth)?;
            // Convert to u16 with BZERO=32768 for unsigned
            let adjusted: Vec<u8> = if bzero == 32768.0 {
                // Common case: unsigned 16-bit stored as signed with BZERO
                raw.iter()
                    .flat_map(|&v| {
                        let unsigned = (v as i32 + 32768).clamp(0, 65535) as u16;
                        unsigned.to_le_bytes()
                    })
                    .collect()
            } else {
                raw.iter()
                    .flat_map(|&v| {
                        let scaled = (v as f64 * bscale + bzero).clamp(0.0, 65535.0) as u16;
                        scaled.to_le_bytes()
                    })
                    .collect()
            };
            (PixelType::U16, adjusted)
        }
        32 => {
            let raw = read_i32_data(reader, width, height, depth)?;
            // Convert to u32
            let adjusted: Vec<u8> = raw
                .iter()
                .flat_map(|&v| {
                    let scaled = (v as f64 * bscale + bzero).clamp(0.0, u32::MAX as f64) as u32;
                    scaled.to_le_bytes()
                })
                .collect();
            (PixelType::U32, adjusted)
        }
        -32 => {
            let raw = read_f32_data(reader, width, height, depth)?;
            // Keep as f32
            let bytes: Vec<u8> = raw
                .iter()
                .flat_map(|&v| {
                    let scaled = v * bscale as f32 + bzero as f32;
                    scaled.to_le_bytes()
                })
                .collect();
            (PixelType::F32, bytes)
        }
        -64 => {
            let raw = read_f64_data(reader, width, height, depth)?;
            let bytes: Vec<u8> = raw
                .iter()
                .flat_map(|&v| {
                    let scaled = v * bscale + bzero;
                    scaled.to_le_bytes()
                })
                .collect();
            (PixelType::F64, bytes)
        }
        other => return Err(FitsError::UnsupportedBitpix(other)),
    };

    let image = ImageData {
        width,
        height,
        channels: depth,
        pixel_type,
        data,
    };

    // Why: after BSCALE/BZERO have been folded into the data buffer, the header
    // entries are stale. Leaving them in `keyword_order` would cause write_fits
    // to emit them, double-scaling on round-trip. Strip them now so the next
    // write computes fresh values for the chosen output BITPIX (audit §6.3).
    header.remove("BZERO");
    header.remove("BSCALE");

    Ok((image, header))
}

/// Read the FITS header (80-character records until END)
pub(crate) fn read_header<R: Read>(reader: &mut R) -> Result<FitsHeader, FitsError> {
    let mut header = FitsHeader::new();
    let mut buffer = [0u8; 80];
    let mut total_records: usize = 0;
    const MAX_HEADER_RECORDS: usize = 65_536;

    loop {
        reader.read_exact(&mut buffer)?;
        total_records += 1;
        if total_records > MAX_HEADER_RECORDS {
            return Err(FitsError::InvalidFormat(
                "FITS header exceeds maximum supported size or is missing END".to_string(),
            ));
        }

        let record = String::from_utf8_lossy(&buffer);
        let keyword = record[..8].trim();

        if keyword == "END" {
            break;
        }

        if keyword.is_empty() || keyword.starts_with(' ') {
            continue; // Blank or comment
        }

        if !is_valid_keyword(keyword) && keyword != "COMMENT" && keyword != "HISTORY" {
            return Err(FitsError::InvalidFormat(format!(
                "Invalid FITS keyword: {}",
                keyword
            )));
        }

        // Parse the card. COMMENT/HISTORY cards have NO `=` separator per FITS 4.4.2.4
        // and their text occupies columns 9..80; route them to dedicated vectors so
        // they are never mistaken for value cards and re-emitted with `=` (audit §6.5).
        if keyword == "COMMENT" {
            let text = record[8..].trim_end().to_string();
            header.comments.push(text);
        } else if keyword == "HISTORY" {
            let text = record[8..].trim_end().to_string();
            header.history.push(text);
        } else if record.len() > 10 && &record[8..10] == "= " {
            let raw_after = &record[10..];
            let (value_part, comment_part) = split_value_and_comment(raw_after);
            let value = parse_fits_value(value_part)?;
            let key_owned = keyword.to_string();
            header.keywords.insert(key_owned.clone(), value);
            if !header.keyword_order.contains(&key_owned) {
                header.keyword_order.push(key_owned.clone());
            }
            if let Some(comment) = comment_part {
                let trimmed = comment.trim().to_string();
                if !trimmed.is_empty() {
                    header.keyword_comments.insert(key_owned, trimmed);
                }
            }
        }
    }

    // Skip to next 2880-byte boundary
    // The header is padded with spaces to a multiple of 2880 bytes
    // Use total_records (which counts every 80-byte record including
    // COMMENT, HISTORY, blanks, and END) for accurate padding calculation.
    let header_bytes = total_records * 80;
    let padding = (2880 - (header_bytes % 2880)) % 2880;
    if padding > 0 {
        let mut skip = vec![0u8; padding];
        reader.read_exact(&mut skip)?;
    }

    Ok(header)
}

/// Parse a FITS value from string. `s` may still contain a trailing `/ comment`;
/// callers that have already split the comment off can pass either form.
fn parse_fits_value(s: &str) -> Result<FitsValue, FitsError> {
    let s = s.trim();
    let (value_part, _) = split_value_and_comment(s);

    // Check for string (enclosed in single quotes)
    if let Some(stripped) = value_part.strip_prefix('\'') {
        if let Some(end) = stripped.find('\'') {
            return Ok(FitsValue::String(stripped[..end].trim().to_string()));
        }
        return Err(FitsError::InvalidFormat(
            "Unterminated FITS string literal".to_string(),
        ));
    }

    // Check for boolean
    if value_part == "T" {
        return Ok(FitsValue::Boolean(true));
    }
    if value_part == "F" {
        return Ok(FitsValue::Boolean(false));
    }

    // Try to parse as integer
    if let Ok(i) = value_part.parse::<i64>() {
        return Ok(FitsValue::Integer(i));
    }

    // Try to parse as float
    if let Ok(f) = value_part
        .replace('D', "E")
        .replace('d', "e")
        .parse::<f64>()
    {
        return Ok(FitsValue::Float(f));
    }

    // Default to string
    Ok(FitsValue::String(value_part.to_string()))
}

fn split_value_and_comment(s: &str) -> (&str, Option<&str>) {
    let mut in_string = false;
    for (idx, ch) in s.char_indices() {
        match ch {
            '\'' => in_string = !in_string,
            '/' if !in_string => return (s[..idx].trim(), Some(s[idx + 1..].trim())),
            _ => {}
        }
    }
    (s.trim(), None)
}

fn is_valid_keyword(keyword: &str) -> bool {
    !keyword.is_empty()
        && keyword.len() <= 8
        && keyword.bytes().all(|byte| {
            byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'-' || byte == b'_'
        })
}

/// Compute pixel count from FITS NAXIS dimensions, surfacing overflow as a
/// structured error rather than a wrapping `as usize`.
///
/// Why (audit-rust §1.4): the previous `(width * height * depth) as usize`
/// in u32 silently wraps for >4G-pixel images; promoting to u64 with
/// checked_mul forces the failure to surface at the I/O boundary where the
/// caller can map it to a structured FitsError.
fn fits_pixel_count(width: u32, height: u32, depth: u32) -> Result<usize, FitsError> {
    let product = u64::from(width)
        .checked_mul(u64::from(height))
        .and_then(|n| n.checked_mul(u64::from(depth)))
        .ok_or_else(|| {
            FitsError::InvalidFormat(format!(
                "FITS NAXIS dimensions overflow: {}*{}*{}",
                width, height, depth
            ))
        })?;
    usize::try_from(product).map_err(|_| {
        FitsError::InvalidFormat(format!("FITS pixel count {} exceeds usize::MAX", product))
    })
}

/// Read unsigned 8-bit data
fn read_u8_data<R: Read>(
    reader: &mut R,
    width: u32,
    height: u32,
    depth: u32,
) -> Result<Vec<u8>, FitsError> {
    let size = fits_pixel_count(width, height, depth)?;
    let mut data = vec![0u8; size];
    reader.read_exact(&mut data)?;
    Ok(data)
}

/// Read signed 16-bit data (big-endian)
fn read_i16_data<R: Read>(
    reader: &mut R,
    width: u32,
    height: u32,
    depth: u32,
) -> Result<Vec<i16>, FitsError> {
    let size = fits_pixel_count(width, height, depth)?;
    let buffer_len = size.checked_mul(2).ok_or_else(|| {
        FitsError::InvalidFormat(format!("FITS i16 buffer overflow for {} pixels", size))
    })?;
    let mut buffer = vec![0u8; buffer_len];
    reader.read_exact(&mut buffer)?;

    let data: Vec<i16> = buffer
        .chunks_exact(2)
        .map(|chunk| i16::from_be_bytes([chunk[0], chunk[1]]))
        .collect();

    Ok(data)
}

/// Read signed 32-bit data (big-endian)
fn read_i32_data<R: Read>(
    reader: &mut R,
    width: u32,
    height: u32,
    depth: u32,
) -> Result<Vec<i32>, FitsError> {
    let size = fits_pixel_count(width, height, depth)?;
    let buffer_len = size.checked_mul(4).ok_or_else(|| {
        FitsError::InvalidFormat(format!("FITS i32 buffer overflow for {} pixels", size))
    })?;
    let mut buffer = vec![0u8; buffer_len];
    reader.read_exact(&mut buffer)?;

    let data: Vec<i32> = buffer
        .chunks_exact(4)
        .map(|chunk| i32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect();

    Ok(data)
}

/// Read 32-bit float data (big-endian IEEE 754)
fn read_f32_data<R: Read>(
    reader: &mut R,
    width: u32,
    height: u32,
    depth: u32,
) -> Result<Vec<f32>, FitsError> {
    let size = fits_pixel_count(width, height, depth)?;
    let buffer_len = size.checked_mul(4).ok_or_else(|| {
        FitsError::InvalidFormat(format!("FITS f32 buffer overflow for {} pixels", size))
    })?;
    let mut buffer = vec![0u8; buffer_len];
    reader.read_exact(&mut buffer)?;

    let data: Vec<f32> = buffer
        .chunks_exact(4)
        .map(|chunk| f32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect();

    Ok(data)
}

/// Read 64-bit float data (big-endian IEEE 754)
fn read_f64_data<R: Read>(
    reader: &mut R,
    width: u32,
    height: u32,
    depth: u32,
) -> Result<Vec<f64>, FitsError> {
    let size = fits_pixel_count(width, height, depth)?;
    let buffer_len = size.checked_mul(8).ok_or_else(|| {
        FitsError::InvalidFormat(format!("FITS f64 buffer overflow for {} pixels", size))
    })?;
    let mut buffer = vec![0u8; buffer_len];
    reader.read_exact(&mut buffer)?;

    let data: Vec<f64> = buffer
        .chunks_exact(8)
        .map(|chunk| {
            f64::from_be_bytes([
                chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
            ])
        })
        .collect();

    Ok(data)
}

/// Write a FITS file to disk.
///
/// Why: this writer enforces three FITS-spec invariants that the prior version
/// violated (audit §6.3 and §6.5):
///  * BSCALE/BZERO are computed fresh from the in-memory pixel type, never
///    inherited from a stale source header.
///  * String values are padded to ≥8 characters between single quotes (FITS 4.2.1.1).
///  * COMMENT/HISTORY cards are emitted without an `=` separator and free-form
///    text in columns 9..80; they are NOT routed through the value-card writer.
pub fn write_fits(path: &Path, image: &ImageData, header: &FitsHeader) -> Result<(), FitsError> {
    let file = File::create(path)?;
    let mut writer = BufWriter::new(file);

    // Determine BITPIX based on pixel type
    let bitpix: i32 = match image.pixel_type {
        PixelType::U8 => 8,
        PixelType::U16 => 16,
        PixelType::U32 => 32,
        PixelType::F32 => -32,
        PixelType::F64 => -64,
    };

    // Write mandatory keywords
    write_value_card(&mut writer, "SIMPLE", "T", None)?;
    write_value_card(&mut writer, "BITPIX", &bitpix.to_string(), None)?;
    write_value_card(
        &mut writer,
        "NAXIS",
        &format!("{}", if image.channels > 1 { 3 } else { 2 }),
        None,
    )?;
    write_value_card(&mut writer, "NAXIS1", &image.width.to_string(), None)?;
    write_value_card(&mut writer, "NAXIS2", &image.height.to_string(), None)?;
    if image.channels > 1 {
        write_value_card(&mut writer, "NAXIS3", &image.channels.to_string(), None)?;
    }

    // Why: per audit §6.3 the writer must always emit fresh BSCALE/BZERO matching
    // the chosen output BITPIX. The decoder strips them from `keyword_order`, so
    // these are the only BSCALE/BZERO cards in the file.
    if image.pixel_type == PixelType::U16 {
        write_value_card(&mut writer, "BZERO", "32768", None)?;
        write_value_card(&mut writer, "BSCALE", "1", None)?;
    }

    // Write additional header keywords. SIMPLE/BITPIX/NAXIS*/BZERO/BSCALE/END are
    // skipped because they are owned by this writer.
    for key in &header.keyword_order {
        if [
            "SIMPLE", "BITPIX", "NAXIS", "NAXIS1", "NAXIS2", "NAXIS3", "BZERO", "BSCALE", "END",
        ]
        .contains(&key.as_str())
        {
            continue;
        }
        let Some(value) = header.keywords.get(key) else {
            continue;
        };
        let comment = header.keyword_comments.get(key).map(|s| s.as_str());
        match value {
            FitsValue::String(s) => {
                let formatted = format_fits_string_value(s);
                write_value_card(&mut writer, key, &formatted, comment)?;
            }
            FitsValue::Integer(i) => {
                write_value_card(&mut writer, key, &i.to_string(), comment)?;
            }
            FitsValue::Float(f) => {
                write_value_card(&mut writer, key, &format_fits_float(*f), comment)?;
            }
            FitsValue::Boolean(b) => {
                let token = if *b { "T" } else { "F" };
                write_value_card(&mut writer, key, token, comment)?;
            }
            // Why: legacy callers may still construct FitsValue::Comment directly.
            // Treat it as a free-form COMMENT card to avoid producing a malformed
            // value card. New code should call `add_comment()` on FitsHeader instead.
            FitsValue::Comment(c) => {
                write_text_card(&mut writer, "COMMENT", c)?;
            }
        }
    }

    // Emit COMMENT cards. Why: §6.5 — these have no `=` separator and the text
    // body occupies columns 9..80, padded with spaces.
    for text in &header.comments {
        write_text_card(&mut writer, "COMMENT", text)?;
    }
    for text in &header.history {
        write_text_card(&mut writer, "HISTORY", text)?;
    }

    // Write END keyword
    write_end_card(&mut writer)?;

    // Pad header to 2880-byte boundary
    let pos = writer.stream_position()? as usize;
    let padding = (2880 - (pos % 2880)) % 2880;
    for _ in 0..padding {
        writer.write_all(b" ")?;
    }

    // Write image data
    match image.pixel_type {
        PixelType::U8 => {
            writer.write_all(&image.data)?;
        }
        PixelType::U16 => {
            // Convert from little-endian u16 to big-endian i16 with BZERO offset
            for chunk in image.data.chunks_exact(2) {
                let val = u16::from_le_bytes([chunk[0], chunk[1]]);
                let signed = (val as i32 - 32768) as i16;
                writer.write_all(&signed.to_be_bytes())?;
            }
        }
        PixelType::U32 => {
            for chunk in image.data.chunks_exact(4) {
                let val = u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                let signed = val as i32;
                writer.write_all(&signed.to_be_bytes())?;
            }
        }
        PixelType::F32 => {
            for chunk in image.data.chunks_exact(4) {
                let val = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                writer.write_all(&val.to_be_bytes())?;
            }
        }
        PixelType::F64 => {
            for chunk in image.data.chunks_exact(8) {
                let val = f64::from_le_bytes([
                    chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
                ]);
                writer.write_all(&val.to_be_bytes())?;
            }
        }
    }

    // Pad data to 2880-byte boundary
    let data_size = image.data.len();
    let padding = (2880 - (data_size % 2880)) % 2880;
    for _ in 0..padding {
        writer.write_all(&[0u8])?;
    }

    writer.flush()?;
    Ok(())
}

/// Format a FITS string value with the FITS 4.2.1.1 minimum-length rule.
///
/// Why: PixInsight, AstroPixelProcessor, and several legacy tools reject string
/// cards whose quoted body is shorter than 8 characters. The spec requires the
/// quoted text to be space-padded out to at least 8 characters before the closing
/// quote (audit §6.5 item 1).
fn format_fits_string_value(value: &str) -> String {
    // Why: a single-quote inside the string must be escaped as `''` per FITS 4.2.1.1.
    let escaped = value.replace('\'', "''");
    let body = if escaped.chars().count() < 8 {
        // Pad with trailing spaces to the 8-char minimum.
        let needed = 8 - escaped.chars().count();
        format!("{}{}", escaped, " ".repeat(needed))
    } else {
        escaped
    };
    format!("'{}'", body)
}

/// Format a float for a FITS value card. Why: FITS uses standard scientific
/// notation; we keep enough precision (10 significant digits) for double-precision
/// astrometry values without exceeding the 70-byte value field.
fn format_fits_float(value: f64) -> String {
    // Why: integer-valued floats round-trip through `f64::to_string` as e.g. "1",
    // which silently changes the type from Float to Integer on re-parse. Force a
    // decimal point for true integer values to preserve Float typing.
    if value.is_finite() && value.fract() == 0.0 && value.abs() < 1.0e16 {
        format!("{:.1}", value)
    } else {
        format!("{:.10E}", value)
    }
}

/// Write the END card. END has no `=` and no value body.
fn write_end_card<W: Write>(writer: &mut W) -> Result<(), FitsError> {
    let mut record = [b' '; 80];
    record[..3].copy_from_slice(b"END");
    writer.write_all(&record)?;
    Ok(())
}

/// Write a free-form text card (COMMENT, HISTORY, or any spec-defined commentary
/// keyword). Per FITS 4.4.2.4 these have no `=` separator; the text body fills
/// columns 9..80 (1-indexed) and is padded with trailing spaces. Long text is
/// split across multiple cards. Why: emitting a value-card for COMMENT/HISTORY
/// (the previous behavior) produced malformed cards like `COMMENT = some text`.
fn write_text_card<W: Write>(writer: &mut W, keyword: &str, text: &str) -> Result<(), FitsError> {
    if keyword.len() > 8 {
        return Err(FitsError::InvalidFormat(format!(
            "Commentary keyword '{}' exceeds 8 chars",
            keyword
        )));
    }
    // Up to 72 bytes of text per card (cols 9..80). Wrap longer payloads.
    let bytes = text.as_bytes();
    let chunk_size = 72;
    if bytes.is_empty() {
        let mut record = [b' '; 80];
        let key_bytes = keyword.as_bytes();
        record[..key_bytes.len()].copy_from_slice(key_bytes);
        writer.write_all(&record)?;
        return Ok(());
    }
    for chunk in bytes.chunks(chunk_size) {
        let mut record = [b' '; 80];
        let key_bytes = keyword.as_bytes();
        record[..key_bytes.len()].copy_from_slice(key_bytes);
        // Why: column 9 is the first text byte (0-indexed offset 8) and the spec
        // does not place an `=` at column 9 for commentary keywords.
        let copy_len = chunk.len().min(72);
        record[8..8 + copy_len].copy_from_slice(&chunk[..copy_len]);
        writer.write_all(&record)?;
    }
    Ok(())
}

/// Write a value-card record `KEYNAME = value [/ comment]`.
///
/// `comment` is an optional inline comment. The card is truncated at 80 bytes;
/// if the comment would push the card past 80 bytes it is shortened (or omitted)
/// rather than wrapped, since FITS 4.4.2.3 forbids continuation of value-card
/// inline comments.
fn write_value_card<W: Write>(
    writer: &mut W,
    keyword: &str,
    value: &str,
    comment: Option<&str>,
) -> Result<(), FitsError> {
    if !is_valid_keyword(keyword) {
        return Err(FitsError::InvalidFormat(format!(
            "Invalid FITS keyword for write: {}",
            keyword
        )));
    }

    let mut record = [b' '; 80];

    // Write keyword (8 chars, left-justified)
    let keyword_bytes = keyword.as_bytes();
    let keyword_len = keyword_bytes.len().min(8);
    record[..keyword_len].copy_from_slice(&keyword_bytes[..keyword_len]);

    if value.is_empty() {
        writer.write_all(&record)?;
        return Ok(());
    }

    // "= " indicator at columns 9..10 (0-indexed 8..10).
    record[8] = b'=';
    record[9] = b' ';

    let value_bytes = value.as_bytes();
    // Strings start at column 11 (offset 10); numerics are right-justified ending at
    // column 30 (offset 30).
    let is_string = value.starts_with('\'');
    let start = if is_string {
        if value_bytes.len() > 70 {
            return Err(FitsError::InvalidFormat(format!(
                "FITS string value too long for {}",
                keyword
            )));
        }
        10
    } else {
        if value_bytes.len() > 70 {
            return Err(FitsError::InvalidFormat(format!(
                "FITS value too long for {}",
                keyword
            )));
        }
        30_usize.saturating_sub(value_bytes.len())
    };
    let value_len = value_bytes.len().min(70);
    if start + value_len > record.len() {
        return Err(FitsError::InvalidFormat(format!(
            "FITS value overflows 80-byte card for {}",
            keyword
        )));
    }
    record[start..start + value_len].copy_from_slice(&value_bytes[..value_len]);

    // Inline comment. Why: FITS 4.4.2.3 — the format is `value / comment` with at
    // least one space on each side of the `/`. Truncate (never wrap) to fit 80 bytes.
    if let Some(comment_text) = comment {
        let trimmed = comment_text.trim();
        if !trimmed.is_empty() {
            let value_end = start + value_len;
            // Need " / " (3 bytes) plus at least one comment byte.
            if value_end + 4 <= 80 {
                let separator = b" / ";
                let sep_start = value_end + 1; // leave a space after the value
                if sep_start + 2 < 80 {
                    record[sep_start..sep_start + 2].copy_from_slice(&separator[1..3]);
                    let comment_start = sep_start + 2;
                    let available = 80 - comment_start;
                    let comment_bytes = trimmed.as_bytes();
                    let copy_len = comment_bytes.len().min(available);
                    record[comment_start..comment_start + copy_len]
                        .copy_from_slice(&comment_bytes[..copy_len]);
                }
            }
        }
    }

    writer.write_all(&record)?;
    Ok(())
}

/// Parsed Bayer geometry from a FITS header, accounting for subframe offsets.
///
/// Why: `BAYERPAT` describes the color pattern at the *full-sensor* origin.
/// When a frame is captured with a subframe whose top-left pixel is at odd
/// offsets relative to the sensor, the effective pattern at the in-memory
/// origin (0,0) is shifted. `XBAYROFF`/`YBAYROFF` keywords (NINA, ASIAIR,
/// SharpCap, ASTAP, INDI) record those offsets so the consumer can apply the
/// correct pattern. Without this, every odd-offset subframe is debayered with
/// the wrong color mapping (audit §6.6).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BayerGeometry {
    /// Effective Bayer pattern at the image origin (after applying offsets).
    pub effective: BayerPattern,
    /// Source pattern as stored in BAYERPAT.
    pub source: BayerPattern,
    /// X offset of the subframe top-left, relative to the sensor origin.
    pub x_offset: i64,
    /// Y offset of the subframe top-left, relative to the sensor origin.
    pub y_offset: i64,
}

/// Compose a base Bayer pattern with subframe offsets, returning the effective
/// pattern at the in-memory image origin (0,0).
///
/// Composition table — `effective_bayer_pattern(source, x % 2, y % 2)`:
///
/// | source | (0,0) | (1,0) | (0,1) | (1,1) |
/// |--------|-------|-------|-------|-------|
/// | RGGB   | RGGB  | GRBG  | GBRG  | BGGR  |
/// | BGGR   | BGGR  | GBRG  | GRBG  | RGGB  |
/// | GRBG   | GRBG  | RGGB  | BGGR  | GBRG  |
/// | GBRG   | GBRG  | BGGR  | RGGB  | GRBG  |
///
/// Negative offsets are wrapped via Euclidean mod 2 to keep the table consistent.
pub fn effective_bayer_pattern(
    source: BayerPattern,
    x_offset: i64,
    y_offset: i64,
) -> BayerPattern {
    // Why: rust's `%` is sign-preserving; for offset composition we need a true
    // modulo so a -1 offset behaves like a +1 offset (parity is what matters).
    let xb = x_offset.rem_euclid(2) as usize;
    let yb = y_offset.rem_euclid(2) as usize;
    match (source, xb, yb) {
        (BayerPattern::RGGB, 0, 0) => BayerPattern::RGGB,
        (BayerPattern::RGGB, 1, 0) => BayerPattern::GRBG,
        (BayerPattern::RGGB, 0, 1) => BayerPattern::GBRG,
        (BayerPattern::RGGB, 1, 1) => BayerPattern::BGGR,

        (BayerPattern::BGGR, 0, 0) => BayerPattern::BGGR,
        (BayerPattern::BGGR, 1, 0) => BayerPattern::GBRG,
        (BayerPattern::BGGR, 0, 1) => BayerPattern::GRBG,
        (BayerPattern::BGGR, 1, 1) => BayerPattern::RGGB,

        (BayerPattern::GRBG, 0, 0) => BayerPattern::GRBG,
        (BayerPattern::GRBG, 1, 0) => BayerPattern::RGGB,
        (BayerPattern::GRBG, 0, 1) => BayerPattern::BGGR,
        (BayerPattern::GRBG, 1, 1) => BayerPattern::GBRG,

        (BayerPattern::GBRG, 0, 0) => BayerPattern::GBRG,
        (BayerPattern::GBRG, 1, 0) => BayerPattern::BGGR,
        (BayerPattern::GBRG, 0, 1) => BayerPattern::RGGB,
        (BayerPattern::GBRG, 1, 1) => BayerPattern::GRBG,

        // Why: rem_euclid(2) only ever returns 0 or 1, but the match must be
        // exhaustive in (BayerPattern, usize, usize); unreachable! signals the
        // invariant rather than silently picking a wrong arm.
        _ => unreachable!("rem_euclid(2) returned out-of-range value"),
    }
}

/// Read the Bayer geometry from a FITS header.
///
/// Returns `None` if `BAYERPAT` is absent or unrecognized. When present,
/// `XBAYROFF`/`YBAYROFF` are read as integer keywords (default 0) and composed
/// with the source pattern via [`effective_bayer_pattern`] so the caller's
/// debayer step uses the correct origin (audit §6.6).
pub fn read_bayer_geometry(header: &FitsHeader) -> Option<BayerGeometry> {
    let pat_str = header.get_string("BAYERPAT")?;
    let source = BayerPattern::from_str(pat_str.trim())?;
    // Why (audit-rust §4.3): per the doc-comment above, XBAYROFF/YBAYROFF default to 0
    // (no Bayer-pattern shift) — documented convention.
    let x_offset = header.get_int("XBAYROFF").unwrap_or(0);
    let y_offset = header.get_int("YBAYROFF").unwrap_or(0);
    let effective = effective_bayer_pattern(source, x_offset, y_offset);
    Some(BayerGeometry {
        effective,
        source,
        x_offset,
        y_offset,
    })
}

/// WCS (World Coordinate System) information from plate solving
/// Used to add astrometric headers to FITS files
#[derive(Debug, Clone)]
pub struct WcsInfo {
    /// Reference RA in degrees (CRVAL1)
    pub crval1: f64,
    /// Reference DEC in degrees (CRVAL2)
    pub crval2: f64,
    /// Reference pixel X coordinate (CRPIX1) - usually image center
    pub crpix1: f64,
    /// Reference pixel Y coordinate (CRPIX2) - usually image center
    pub crpix2: f64,
    /// CD matrix element 1,1 (scale and rotation)
    pub cd1_1: f64,
    /// CD matrix element 1,2 (scale and rotation)
    pub cd1_2: f64,
    /// CD matrix element 2,1 (scale and rotation)
    pub cd2_1: f64,
    /// CD matrix element 2,2 (scale and rotation)
    pub cd2_2: f64,
}

impl WcsInfo {
    /// Create WCS info from plate solve result
    ///
    /// # Arguments
    /// * `ra` - Right ascension in degrees
    /// * `dec` - Declination in degrees
    /// * `rotation` - Field rotation in degrees
    /// * `pixel_scale` - Pixel scale in arcseconds per pixel
    /// * `image_width` - Image width in pixels
    /// * `image_height` - Image height in pixels
    pub fn from_plate_solve(
        ra: f64,
        dec: f64,
        rotation: f64,
        pixel_scale: f64,
        image_width: u32,
        image_height: u32,
    ) -> Self {
        // Reference pixel is the image center
        let crpix1 = image_width as f64 / 2.0;
        let crpix2 = image_height as f64 / 2.0;

        // Convert pixel scale from arcsec/pixel to deg/pixel
        let scale_deg = pixel_scale / 3600.0;

        // Convert rotation to radians
        let rot_rad = rotation.to_radians();
        let cos_rot = rot_rad.cos();
        let sin_rot = rot_rad.sin();

        // Build CD matrix incorporating rotation
        let cd1_1 = -scale_deg * cos_rot; // Negative for RA increasing to the left
        let cd1_2 = scale_deg * sin_rot;
        let cd2_1 = scale_deg * sin_rot;
        let cd2_2 = scale_deg * cos_rot;

        Self {
            crval1: ra,
            crval2: dec,
            crpix1,
            crpix2,
            cd1_1,
            cd1_2,
            cd2_1,
            cd2_2,
        }
    }
}

/// Add WCS (World Coordinate System) headers to a FITS header
///
/// This adds standard astrometry headers based on plate solve results.
/// The WCS headers allow astronomical software to map pixel coordinates
/// to sky coordinates (RA/Dec).
///
/// # Arguments
/// * `header` - The FITS header to add WCS keywords to
/// * `wcs` - WCS information from plate solving
pub fn add_wcs_headers(header: &mut FitsHeader, wcs: &WcsInfo) {
    // Reference coordinates
    header.set_float("CRVAL1", wcs.crval1);
    header.set_float("CRVAL2", wcs.crval2);

    // Reference pixels
    header.set_float("CRPIX1", wcs.crpix1);
    header.set_float("CRPIX2", wcs.crpix2);

    // CD matrix (scale and rotation)
    header.set_float("CD1_1", wcs.cd1_1);
    header.set_float("CD1_2", wcs.cd1_2);
    header.set_float("CD2_1", wcs.cd2_1);
    header.set_float("CD2_2", wcs.cd2_2);

    // Coordinate type (tangent plane projection)
    header.set_string("CTYPE1", "RA---TAN");
    header.set_string("CTYPE2", "DEC--TAN");

    // Coordinate units
    header.set_string("CUNIT1", "deg");
    header.set_string("CUNIT2", "deg");

    // Reference frame
    header.set_float("EQUINOX", 2000.0);
    header.set_string("RADESYS", "ICRS");
}

/// Standard FITS keywords for astrophotography
pub struct StandardKeywords;

impl StandardKeywords {
    pub const BITPIX: &'static str = "BITPIX";
    pub const NAXIS: &'static str = "NAXIS";
    pub const NAXIS1: &'static str = "NAXIS1";
    pub const NAXIS2: &'static str = "NAXIS2";
    pub const BZERO: &'static str = "BZERO";
    pub const BSCALE: &'static str = "BSCALE";
    pub const OBJECT: &'static str = "OBJECT";
    pub const TELESCOP: &'static str = "TELESCOP";
    pub const INSTRUME: &'static str = "INSTRUME";
    pub const OBSERVER: &'static str = "OBSERVER";
    pub const DATE_OBS: &'static str = "DATE-OBS";
    pub const EXPTIME: &'static str = "EXPTIME";
    pub const CCD_TEMP: &'static str = "CCD-TEMP";
    pub const GAIN: &'static str = "GAIN";
    pub const OFFSET: &'static str = "OFFSET";
    pub const XBINNING: &'static str = "XBINNING";
    pub const YBINNING: &'static str = "YBINNING";
    pub const FILTER: &'static str = "FILTER";
    pub const RA: &'static str = "RA";
    pub const DEC: &'static str = "DEC";
    pub const FOCALLEN: &'static str = "FOCALLEN";
    pub const APTDIA: &'static str = "APTDIA";
    pub const IMAGETYP: &'static str = "IMAGETYP";
    pub const SITELAT: &'static str = "SITELAT";
    pub const SITELONG: &'static str = "SITELONG";
    pub const SITEELEV: &'static str = "SITEELEV";
    pub const AIRMASS: &'static str = "AIRMASS";
    pub const PIXSIZE1: &'static str = "PIXSIZE1";
    pub const PIXSIZE2: &'static str = "PIXSIZE2";
    pub const XPIXSZ: &'static str = "XPIXSZ";
    pub const YPIXSZ: &'static str = "YPIXSZ";

    // WCS Keywords
    pub const CRVAL1: &'static str = "CRVAL1";
    pub const CRVAL2: &'static str = "CRVAL2";
    pub const CRPIX1: &'static str = "CRPIX1";
    pub const CRPIX2: &'static str = "CRPIX2";
    pub const CD1_1: &'static str = "CD1_1";
    pub const CD1_2: &'static str = "CD1_2";
    pub const CD2_1: &'static str = "CD2_1";
    pub const CD2_2: &'static str = "CD2_2";
    pub const CTYPE1: &'static str = "CTYPE1";
    pub const CTYPE2: &'static str = "CTYPE2";
    pub const EQUINOX: &'static str = "EQUINOX";
    pub const RADESYS: &'static str = "RADESYS";
}

/// Calculate airmass from true (geometric) altitude.
///
/// Airmass is the relative optical path length through Earth's atmosphere
/// compared to the zenith. The implementation uses **Pickering (2002)** above
/// 10° true altitude where it is well-conditioned (worst-case error vs.
/// rigorous radiative transfer is < 0.0008 airmass) and **Young (1994)** below
/// 10° down to the true horizon where Pickering's `1/sin(h + 244/(165+47*h^1.1))`
/// term degrades sharply (audit §6.14).
///
/// # Arguments
/// * `altitude_degrees` - True altitude angle in degrees (must be ≥ 0)
///
/// # Returns
/// * `Ok(X)` — airmass value, ≥ 1.0 at the zenith and increasing toward the
///   horizon (Young's formula evaluated at h=0° gives ≈31.74).
/// * `Err(FitsError::BelowHorizon)` — for altitudes below 0°. Why: airmass is
///   physically undefined for sub-horizon paths; silently clamping (the prior
///   behavior) hides scheduler/coord-transform bugs that send the mount below
///   the horizon. The caller decides how to handle (skip, retry, alert).
///
/// # Validity range
/// - Pickering 2002: 10° ≤ h ≤ 90° (chosen here for matching that range)
/// - Young 1994: 0° ≤ h ≤ 90° (used here for h < 10°)
///
/// # References
/// * Pickering, K. A. 2002. "The Southern Limits of the Ancient Star Catalog."
///   *DIO* 12 #1, p. 20.
/// * Young, A. T. 1994. "Air mass and refraction." *Applied Optics* 33, 1108–1110.
pub fn calculate_airmass(altitude_degrees: f64) -> Result<f64, FitsError> {
    if !altitude_degrees.is_finite() {
        return Err(FitsError::InvalidFormat(format!(
            "Altitude must be finite, got {}",
            altitude_degrees
        )));
    }
    if altitude_degrees < 0.0 {
        return Err(FitsError::BelowHorizon {
            altitude_degrees,
        });
    }
    // Clamp upper bound only — the math is well-defined at 90° but we guard
    // against numerical noise like 90.000001 that would push trig sin(90+) past 1.
    let alt = altitude_degrees.min(90.0);

    if alt >= 89.9 {
        // Why: at zenith the formulas converge to 1.0; this avoids floating-point
        // jitter producing values like 0.99999999.
        return Ok(1.0);
    }

    let airmass = if alt >= 10.0 {
        // Pickering 2002 — accurate to < 0.001 at h ≥ 10°.
        let h_pow = alt.powf(1.1);
        let correction = 244.0 / (165.0 + 47.0 * h_pow);
        let effective_alt = alt + correction;
        1.0 / effective_alt.to_radians().sin()
    } else {
        // Young 1994 — empirical formula valid all the way to h = 0°. Form:
        //   X(z) = (1.002432 cos²z + 0.148386 cos z + 0.0096467) /
        //          (cos³z + 0.149864 cos²z + 0.0102963 cos z + 0.000303978)
        // where z = 90° - h is the true zenith angle. At h = 0°, X ≈ 38.0.
        let z = (90.0 - alt).to_radians();
        let cos_z = z.cos();
        let cos2 = cos_z * cos_z;
        let cos3 = cos2 * cos_z;
        let numerator = 1.002432 * cos2 + 0.148386 * cos_z + 0.0096467;
        let denominator = cos3 + 0.149864 * cos2 + 0.0102963 * cos_z + 0.000303978;
        numerator / denominator
    };

    if !airmass.is_finite() {
        return Err(FitsError::InvalidFormat(format!(
            "Airmass computation produced non-finite result for altitude {}°",
            altitude_degrees
        )));
    }
    Ok(airmass)
}

/// Image validation result
#[derive(Debug, Clone)]
pub struct ImageValidation {
    pub is_valid: bool,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
}

impl ImageValidation {
    pub fn valid() -> Self {
        Self {
            is_valid: true,
            warnings: Vec::new(),
            errors: Vec::new(),
        }
    }

    pub fn add_warning(&mut self, warning: String) {
        self.warnings.push(warning);
    }

    pub fn add_error(&mut self, error: String) {
        self.errors.push(error);
        self.is_valid = false;
    }
}

/// Validate image data for common issues
///
/// # Arguments
/// * `image` - The image data to validate
/// * `expected_width` - Expected image width (None to skip check)
/// * `expected_height` - Expected image height (None to skip check)
///
/// # Returns
/// Validation result with errors and warnings
pub fn validate_image(
    image: &ImageData,
    expected_width: Option<u32>,
    expected_height: Option<u32>,
) -> ImageValidation {
    let mut validation = ImageValidation::valid();

    // Check dimensions match expected
    if let Some(width) = expected_width {
        if image.width != width {
            validation.add_error(format!(
                "Width mismatch: expected {}, got {}",
                width, image.width
            ));
        }
    }

    if let Some(height) = expected_height {
        if image.height != height {
            validation.add_error(format!(
                "Height mismatch: expected {}, got {}",
                height, image.height
            ));
        }
    }

    // Check for zero dimensions
    if image.width == 0 || image.height == 0 {
        validation.add_error("Image has zero dimensions".to_string());
        return validation;
    }

    // Check data size matches dimensions
    let pixel_size = match image.pixel_type {
        PixelType::U8 => 1,
        PixelType::U16 => 2,
        PixelType::U32 => 4,
        PixelType::F32 => 4,
        PixelType::F64 => 8,
    };
    let expected_size = (image.width * image.height * image.channels) as usize * pixel_size;
    if image.data.len() != expected_size {
        validation.add_error(format!(
            "Data size mismatch: expected {} bytes, got {}",
            expected_size,
            image.data.len()
        ));
    }

    // For 16-bit images, check for all-zero or all-saturated frames
    if image.pixel_type == PixelType::U16 {
        let pixels: Vec<u16> = image
            .data
            .chunks_exact(2)
            .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
            .collect();

        if !pixels.is_empty() {
            let all_zero = pixels.iter().all(|&p| p == 0);
            let all_saturated = pixels.iter().all(|&p| p >= 65530);

            if all_zero {
                validation.add_error("Image is all-zero (no data captured)".to_string());
            } else if all_saturated {
                validation
                    .add_error("Image is all-saturated (overexposed or sensor issue)".to_string());
            }

            // Check for extremely low signal
            // Why (audit-rust §4.3): max() of an empty pixel iterator → 0; an empty pixel
            // vec is impossible (we are inside the `pixels.len() > 0`-guarded branch and
            // both prior `all_zero`/`all_saturated` iterators have already inspected it).
            // Zero is the inert placeholder for the unreachable empty case.
            let max_value = pixels.iter().copied().max().unwrap_or(0);
            if max_value < 100 {
                validation.add_warning(format!(
                    "Very low signal detected (max value: {})",
                    max_value
                ));
            }
        }
    }

    validation
}

/// Comprehensive image validation options
#[derive(Debug, Clone)]
pub struct ImageValidationOptions {
    /// Expected image width (None to skip check)
    pub expected_width: Option<u32>,
    /// Expected image height (None to skip check)
    pub expected_height: Option<u32>,
    /// Whether this is a bias frame (allows uniform pixel values)
    pub is_bias_frame: bool,
    /// Minimum acceptable max pixel value (default: 100)
    pub min_max_value: u16,
    /// Saturation threshold (pixels above this are considered saturated, default: 65530)
    pub saturation_threshold: u16,
    /// Maximum acceptable saturation percentage (default: 0.90 = 90%)
    pub max_saturation_percent: f64,
}

impl Default for ImageValidationOptions {
    fn default() -> Self {
        Self {
            expected_width: None,
            expected_height: None,
            is_bias_frame: false,
            min_max_value: 100,
            saturation_threshold: 65530,
            max_saturation_percent: 0.90,
        }
    }
}

/// Validate image data with bias frame option
///
/// # Arguments
/// * `image` - The image data to validate
/// * `expected_width` - Expected image width (None to skip check)
/// * `expected_height` - Expected image height (None to skip check)
/// * `is_bias_frame` - If true, allows uniform pixel values (bias frames naturally have this)
///
/// # Returns
/// Validation result with errors and warnings
pub fn validate_image_with_options(
    image: &ImageData,
    expected_width: Option<u32>,
    expected_height: Option<u32>,
    is_bias_frame: bool,
) -> ImageValidation {
    validate_image_comprehensive(
        image,
        ImageValidationOptions {
            expected_width,
            expected_height,
            is_bias_frame,
            ..Default::default()
        },
    )
}

/// Comprehensive image validation with full options
///
/// Performs the following validation checks:
/// 1. Validates image data size matches dimensions (width * height)
/// 2. Rejects images where ALL pixels are identical (unless it's a bias frame)
/// 3. Rejects severely underexposed images (max pixel value < min_max_value)
/// 4. Warns on excessive saturation (>max_saturation_percent of pixels saturated)
/// 5. Logs validation results for debugging
///
/// # Arguments
/// * `image` - The image data to validate
/// * `options` - Validation options
///
/// # Returns
/// Validation result with errors and warnings
pub fn validate_image_comprehensive(
    image: &ImageData,
    options: ImageValidationOptions,
) -> ImageValidation {
    let mut validation = ImageValidation::valid();

    // Check dimensions match expected
    if let Some(width) = options.expected_width {
        if image.width != width {
            validation.add_error(format!(
                "Width mismatch: expected {}, got {}",
                width, image.width
            ));
        }
    }

    if let Some(height) = options.expected_height {
        if image.height != height {
            validation.add_error(format!(
                "Height mismatch: expected {}, got {}",
                height, image.height
            ));
        }
    }

    // Check for zero dimensions
    if image.width == 0 || image.height == 0 {
        validation.add_error("Image has zero dimensions".to_string());
        tracing::error!("[IMAGE_VALIDATION] REJECTED: Image has zero dimensions");
        return validation;
    }

    // Check data size matches dimensions
    let pixel_size = match image.pixel_type {
        PixelType::U8 => 1,
        PixelType::U16 => 2,
        PixelType::U32 => 4,
        PixelType::F32 => 4,
        PixelType::F64 => 8,
    };
    let expected_size = (image.width * image.height * image.channels) as usize * pixel_size;
    if image.data.len() != expected_size {
        validation.add_error(format!(
            "Data size mismatch: expected {} bytes for {}x{}x{} image, got {} bytes (truncated or corrupted)",
            expected_size,
            image.width, image.height, image.channels,
            image.data.len()
        ));
        tracing::error!(
            "[IMAGE_VALIDATION] REJECTED: Data size mismatch - expected {} bytes, got {}",
            expected_size,
            image.data.len()
        );
    }

    // For 16-bit images, perform comprehensive validation
    if image.pixel_type == PixelType::U16 && !image.data.is_empty() {
        let pixels: Vec<u16> = image
            .data
            .chunks_exact(2)
            .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
            .collect();

        if !pixels.is_empty() {
            let total_pixels = pixels.len();

            // Calculate statistics in a single pass for efficiency
            let (min_value, max_value, sum, saturated_count) = pixels.iter().fold(
                (u16::MAX, u16::MIN, 0u64, 0usize),
                |(min, max, sum, sat_count), &pixel| {
                    (
                        min.min(pixel),
                        max.max(pixel),
                        sum + pixel as u64,
                        sat_count + (pixel >= options.saturation_threshold) as usize,
                    )
                },
            );
            let mean_value = if total_pixels > 0 {
                sum / total_pixels as u64
            } else {
                0
            };
            let saturation_percent = saturated_count as f64 / total_pixels as f64;

            // Log statistics for debugging
            tracing::debug!(
                "[IMAGE_VALIDATION] Stats: size={}, min={}, max={}, mean={}, saturated={:.1}%",
                total_pixels,
                min_value,
                max_value,
                mean_value,
                saturation_percent * 100.0
            );

            // Check 1: All pixels identical (uniform data)
            // This indicates sensor failure, dead frame, or possibly a bias frame
            let all_same = min_value == max_value;
            if all_same {
                if options.is_bias_frame {
                    // Bias frames may legitimately have very uniform data
                    tracing::info!(
                        "[IMAGE_VALIDATION] INFO: Bias frame has uniform pixel value {}",
                        min_value
                    );
                } else {
                    validation.add_error(format!(
                        "All {} pixels have identical value {} - possible sensor failure or dead frame",
                        total_pixels, min_value
                    ));
                    tracing::error!(
                        "[IMAGE_VALIDATION] REJECTED: All pixels identical (value={})",
                        min_value
                    );
                }
            }

            // Check 2: All-zero frame (no data captured)
            let all_zero = max_value == 0;
            if all_zero && !all_same {
                // Don't double-report
                validation.add_error("Image is all-zero (no data captured)".to_string());
                tracing::error!("[IMAGE_VALIDATION] REJECTED: All-zero image");
            }

            // Check 3: Underexposure detection with tiered thresholds
            // Severe underexposure (max < min_max_value, default 100) - error
            // Moderate underexposure (max < min_max_value * 5, default 500) - warning
            let moderate_threshold = options.min_max_value.saturating_mul(5);
            if max_value < options.min_max_value && !all_zero && !options.is_bias_frame {
                validation.add_error(format!(
                    "Image severely underexposed: max pixel value {} is below minimum threshold {} - \
                    increase exposure time or check camera connection/shutter",
                    max_value, options.min_max_value
                ));
                tracing::error!(
                    "[IMAGE_VALIDATION] REJECTED: Severely underexposed (max={} < {})",
                    max_value,
                    options.min_max_value
                );
            } else if max_value < moderate_threshold && !all_zero && !options.is_bias_frame {
                // Moderate underexposure - useful signal but concerning
                validation.add_warning(format!(
                    "Low signal detected (max value: {}) - consider increasing exposure time",
                    max_value
                ));
                tracing::warn!(
                    "[IMAGE_VALIDATION] WARNING: Low signal (max={} < {})",
                    max_value,
                    moderate_threshold
                );
            }

            // Check 4: Excessive saturation (>90% of pixels saturated)
            // This indicates severe overexposure or gain/exposure misconfiguration
            if saturation_percent > options.max_saturation_percent {
                validation.add_warning(format!(
                    "Excessive saturation: {:.1}% of pixels are saturated (>{}%) - \
                    reduce exposure time or gain",
                    saturation_percent * 100.0,
                    options.max_saturation_percent * 100.0
                ));
                tracing::warn!(
                    "[IMAGE_VALIDATION] WARNING: Excessive saturation ({:.1}% > {:.1}%)",
                    saturation_percent * 100.0,
                    options.max_saturation_percent * 100.0
                );
            }

            // Check 5: All pixels saturated (complete overexposure)
            let all_saturated = min_value >= options.saturation_threshold;
            if all_saturated {
                validation.add_error(format!(
                    "Image is completely saturated (min value {} >= {}) - \
                    significantly reduce exposure time or gain",
                    min_value, options.saturation_threshold
                ));
                tracing::error!(
                    "[IMAGE_VALIDATION] REJECTED: All pixels saturated (min={})",
                    min_value
                );
            }
        }
    }

    // Log final validation result
    if validation.is_valid {
        if validation.warnings.is_empty() {
            tracing::debug!("[IMAGE_VALIDATION] PASSED: Image validated successfully");
        } else {
            tracing::info!(
                "[IMAGE_VALIDATION] PASSED with {} warning(s): {:?}",
                validation.warnings.len(),
                validation.warnings
            );
        }
    } else {
        tracing::error!(
            "[IMAGE_VALIDATION] FAILED with {} error(s): {:?}",
            validation.errors.len(),
            validation.errors
        );
    }

    validation
}

/// Validate FITS header completeness for astrophotography
///
/// # Arguments
/// * `header` - The FITS header to validate
///
/// # Returns
/// Validation result with warnings for missing recommended keywords
pub fn validate_fits_header(header: &FitsHeader) -> ImageValidation {
    let mut validation = ImageValidation::valid();

    // Required keywords
    let required = vec!["SIMPLE", "BITPIX", "NAXIS", "NAXIS1", "NAXIS2"];
    for keyword in required {
        if header.get(keyword).is_none() {
            validation.add_error(format!("Missing required keyword: {}", keyword));
        }
    }

    // Recommended for astrophotography
    let recommended = vec![
        "DATE-OBS", "EXPTIME", "IMAGETYP", "OBJECT", "TELESCOP", "INSTRUME", "OBSERVER",
    ];
    for keyword in recommended {
        if header.get(keyword).is_none() {
            validation.add_warning(format!("Missing recommended keyword: {}", keyword));
        }
    }

    validation
}

/// Calculate image quality score
///
/// Quality score is a 0-100 metric based on:
/// - HFR (smaller is better, below 3.0 is excellent)
/// - Star count (more stars indicate better data)
/// - Background uniformity (lower stddev relative to mean is better)
///
/// # Arguments
/// * `hfr` - Half-flux radius (arc-seconds or pixels)
/// * `star_count` - Number of detected stars
/// * `mean` - Image mean value
/// * `std_dev` - Image standard deviation
///
/// # Returns
/// Quality score from 0-100 (100 is best)
pub fn calculate_quality_score(
    hfr: Option<f64>,
    star_count: Option<i32>,
    mean: f64,
    std_dev: f64,
) -> f64 {
    let mut score = 0.0;
    let mut weight_sum = 0.0;

    // HFR component (40% weight)
    // Excellent: < 2.0, Good: 2-3, Fair: 3-5, Poor: > 5
    if let Some(hfr_val) = hfr {
        if hfr_val > 0.0 {
            let hfr_score = if hfr_val < 2.0 {
                100.0
            } else if hfr_val < 3.0 {
                100.0 - (hfr_val - 2.0) * 25.0
            } else if hfr_val < 5.0 {
                75.0 - (hfr_val - 3.0) * 25.0
            } else {
                (25.0 - (hfr_val - 5.0).min(5.0) * 5.0).max(0.0)
            };
            score += hfr_score * 0.4;
            weight_sum += 0.4;
        }
    }

    // Star count component (30% weight)
    // Excellent: > 100, Good: 50-100, Fair: 20-50, Poor: < 20
    if let Some(stars) = star_count {
        let star_score = if stars >= 100 {
            100.0
        } else if stars >= 50 {
            66.0 + (stars - 50) as f64 / 50.0 * 34.0
        } else if stars >= 20 {
            33.0 + (stars - 20) as f64 / 30.0 * 33.0
        } else {
            (stars as f64 / 20.0 * 33.0).max(0.0)
        };
        score += star_score * 0.3;
        weight_sum += 0.3;
    }

    // Background uniformity component (30% weight)
    // Lower noise is better - check coefficient of variation
    if mean > 0.0 {
        let cv = std_dev / mean; // Coefficient of variation
        let uniformity_score = if cv < 0.1 {
            100.0
        } else if cv < 0.3 {
            100.0 - (cv - 0.1) * 333.0
        } else {
            (33.0 - (cv - 0.3).min(0.33) * 100.0).max(0.0)
        };
        score += uniformity_score * 0.3;
        weight_sum += 0.3;
    }

    if weight_sum <= 0.0 {
        return 0.0;
    }

    let mut normalized_score = (score / weight_sum).clamp(0.0, 100.0);

    // Apply an additional global penalty for severe focus issues.
    // Extremely high HFR should reduce overall quality even when star count
    // and background metrics still appear favorable.
    if let Some(hfr_val) = hfr {
        if hfr_val > 5.0 {
            let hfr_excess = (hfr_val - 5.0).min(15.0);
            let penalty_factor = 1.0 - (hfr_excess / 15.0) * 0.25;
            normalized_score *= penalty_factor;
        }
    }

    normalized_score.clamp(0.0, 100.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn test_calculate_airmass_zenith() {
        let airmass = calculate_airmass(90.0).expect("zenith airmass must succeed");
        assert_eq!(airmass, 1.0, "Airmass at zenith should be 1.0");
    }

    #[test]
    fn test_calculate_airmass_45_degrees() {
        let airmass = calculate_airmass(45.0).expect("45 deg airmass must succeed");
        assert!(
            airmass > 1.0 && airmass < 2.0,
            "Airmass at 45° should be between 1.0 and 2.0"
        );
        // At 45 degrees, airmass should be approximately 1.41 (sqrt(2))
        assert!(
            (airmass - 1.41).abs() < 0.1,
            "Airmass at 45° should be close to 1.41"
        );
    }

    #[test]
    fn test_calculate_airmass_horizon_uses_young_1994() {
        // Why: Young 1994 evaluated at z=90° (h=0°) gives airmass ≈ 31.74. This
        // replaces the old sentinel-clamp value of 40.0 (audit §6.14).
        let airmass = calculate_airmass(0.0).expect("h=0° must succeed via Young 1994");
        assert!(
            (airmass - 31.74).abs() < 0.5,
            "Young 1994 airmass at horizon should be near 31.74, got {}",
            airmass
        );
    }

    #[test]
    fn test_calculate_airmass_5_degrees_uses_young() {
        // At 5° true altitude Young 1994 yields ~10.32. Pickering would yield
        // ~10.4 — both are reasonable, but the test verifies a real number
        // (no clamp to 40) and that the function does not error in the low band.
        let airmass = calculate_airmass(5.0).expect("h=5° must succeed");
        assert!(
            (8.0..=12.0).contains(&airmass),
            "Young 1994 airmass at 5° should be 8-12, got {}",
            airmass
        );
    }

    #[test]
    fn test_calculate_airmass_15_degrees_uses_pickering() {
        // 15° is in the Pickering range; expect ~3.81.
        let airmass = calculate_airmass(15.0).expect("h=15° must succeed");
        assert!(
            (3.5..=4.1).contains(&airmass),
            "Pickering airmass at 15° should be ~3.8, got {}",
            airmass
        );
    }

    #[test]
    fn test_calculate_airmass_below_horizon_errors() {
        // Audit §6.14 — sub-horizon altitudes must surface an error rather than
        // silently clamping. The caller decides how to handle.
        let err = calculate_airmass(-1.0).expect_err("below-horizon must error");
        assert!(
            matches!(err, FitsError::BelowHorizon { altitude_degrees } if altitude_degrees < 0.0),
            "Expected BelowHorizon error, got {:?}",
            err
        );
    }

    #[test]
    fn test_calculate_airmass_30_degrees() {
        let airmass = calculate_airmass(30.0).expect("h=30° must succeed");
        assert!(
            airmass > 1.5 && airmass < 3.0,
            "Airmass at 30° should be between 1.5 and 3.0"
        );
    }

    #[test]
    fn test_validate_image_correct_dimensions() {
        let image = ImageData::from_u16(100, 100, 1, &vec![1000u16; 100 * 100]);
        let validation = validate_image(&image, Some(100), Some(100));
        assert!(
            validation.is_valid,
            "Image with correct dimensions should be valid"
        );
        assert!(validation.errors.is_empty(), "Should have no errors");
    }

    #[test]
    fn test_validate_image_wrong_dimensions() {
        let image = ImageData::from_u16(100, 100, 1, &vec![1000u16; 100 * 100]);
        let validation = validate_image(&image, Some(200), Some(200));
        assert!(
            !validation.is_valid,
            "Image with wrong dimensions should be invalid"
        );
        assert_eq!(
            validation.errors.len(),
            2,
            "Should have 2 dimension mismatch errors"
        );
    }

    #[test]
    fn test_validate_image_all_zero() {
        let image = ImageData::from_u16(100, 100, 1, &vec![0u16; 100 * 100]);
        let validation = validate_image(&image, None, None);
        assert!(!validation.is_valid, "All-zero image should be invalid");
        assert!(
            validation.errors.iter().any(|e| e.contains("all-zero")),
            "Should have all-zero error"
        );
    }

    #[test]
    fn test_validate_image_all_saturated() {
        let image = ImageData::from_u16(100, 100, 1, &vec![65535u16; 100 * 100]);
        let validation = validate_image(&image, None, None);
        assert!(
            !validation.is_valid,
            "All-saturated image should be invalid"
        );
        assert!(
            validation.errors.iter().any(|e| e.contains("saturated")),
            "Should have saturated error"
        );
    }

    #[test]
    fn test_validate_image_low_signal() {
        let image = ImageData::from_u16(100, 100, 1, &vec![50u16; 100 * 100]);
        let validation = validate_image(&image, None, None);
        assert!(
            validation.is_valid,
            "Low signal image should still be valid"
        );
        assert!(
            !validation.warnings.is_empty(),
            "Should have low signal warning"
        );
    }

    #[test]
    fn test_validate_fits_header_minimal() {
        let mut header = FitsHeader::new();
        header.set_string("SIMPLE", "T");
        header.set_int("BITPIX", 16);
        header.set_int("NAXIS", 2);
        header.set_int("NAXIS1", 100);
        header.set_int("NAXIS2", 100);

        let validation = validate_fits_header(&header);
        assert!(validation.is_valid, "Minimal FITS header should be valid");
        assert!(
            !validation.warnings.is_empty(),
            "Should have warnings for missing recommended keywords"
        );
    }

    #[test]
    fn test_validate_fits_header_complete() {
        let mut header = FitsHeader::new();
        // Required
        header.set_string("SIMPLE", "T");
        header.set_int("BITPIX", 16);
        header.set_int("NAXIS", 2);
        header.set_int("NAXIS1", 100);
        header.set_int("NAXIS2", 100);
        // Recommended
        header.set_string("DATE-OBS", "2025-01-01T00:00:00");
        header.set_float("EXPTIME", 60.0);
        header.set_string("IMAGETYP", "Light");
        header.set_string("OBJECT", "M31");
        header.set_string("TELESCOP", "Test Scope");
        header.set_string("INSTRUME", "Test Camera");
        header.set_string("OBSERVER", "Test Observer");

        let validation = validate_fits_header(&header);
        assert!(validation.is_valid, "Complete FITS header should be valid");
        assert!(
            validation.warnings.is_empty(),
            "Complete header should have no warnings"
        );
    }

    #[test]
    fn test_validate_fits_header_missing_required() {
        let mut header = FitsHeader::new();
        header.set_string("SIMPLE", "T");
        // Missing BITPIX, NAXIS, etc.

        let validation = validate_fits_header(&header);
        assert!(
            !validation.is_valid,
            "Header missing required keywords should be invalid"
        );
        assert!(
            !validation.errors.is_empty(),
            "Should have errors for missing required keywords"
        );
    }

    #[test]
    fn test_quality_score_excellent() {
        let score = calculate_quality_score(Some(1.8), Some(150), 5000.0, 500.0);
        assert!(
            score > 85.0,
            "Excellent image (HFR=1.8, stars=150, CV=0.1) should score > 85, got {}",
            score
        );
    }

    #[test]
    fn test_quality_score_good() {
        let score = calculate_quality_score(Some(2.5), Some(75), 5000.0, 800.0);
        // HFR 2.5 = 75/100, stars 75 = 83/100, CV 0.16 = ~70/100
        // Weighted: 75*0.4 + 83*0.3 + 70*0.3 = 75.9
        assert!(
            score > 70.0 && score < 85.0,
            "Good image should score 70-85, got {}",
            score
        );
    }

    #[test]
    fn test_quality_score_poor() {
        let score = calculate_quality_score(Some(6.0), Some(15), 5000.0, 2000.0);
        assert!(
            score < 40.0,
            "Poor image (HFR=6.0, stars=15, CV=0.4) should score < 40, got {}",
            score
        );
    }

    #[test]
    fn test_quality_score_no_data() {
        let score = calculate_quality_score(None, None, 5000.0, 800.0);
        assert!(
            (0.0..=100.0).contains(&score),
            "Score should be in valid range even with no HFR/star data"
        );
    }

    #[test]
    fn test_fits_header_set_get() {
        let mut header = FitsHeader::new();
        header.set_string("OBJECT", "M31");
        header.set_float("EXPTIME", 120.5);
        header.set_int("GAIN", 100);
        header.set_bool("SIMPLE", true);

        assert_eq!(header.get_string("OBJECT"), Some("M31"));
        assert_eq!(header.get_float("EXPTIME"), Some(120.5));
        assert_eq!(header.get_int("GAIN"), Some(100));
    }

    #[test]
    fn test_fits_header_operations() {
        // Create test image
        let width = 10;
        let height = 10;
        let data: Vec<u16> = (0..100).collect();
        let _image = ImageData::from_u16(width, height, 1, &data);

        // Create header
        let mut header = FitsHeader::new();
        header.set_string("OBJECT", "Test");
        header.set_float("EXPTIME", 60.0);
        header.set_string("IMAGETYP", "Light");
        header.set_int("GAIN", 100);
        header.set_float("CCD-TEMP", -10.5);

        // Test that header operations work
        assert_eq!(header.get_string("OBJECT"), Some("Test"));
        assert_eq!(header.get_float("EXPTIME"), Some(60.0));
        assert_eq!(header.get_string("IMAGETYP"), Some("Light"));
        assert_eq!(header.get_int("GAIN"), Some(100));
        assert_eq!(header.get_float("CCD-TEMP"), Some(-10.5));
    }

    #[test]
    fn test_fits_complete_metadata() {
        // Create header with all astrophotography metadata
        let mut header = FitsHeader::new();
        header.set_bool("SIMPLE", true);
        header.set_int("BITPIX", 16);
        header.set_int("NAXIS", 2);
        header.set_int("NAXIS1", 3008);
        header.set_int("NAXIS2", 3008);

        // Core metadata
        header.set_string("DATE-OBS", "2025-01-15T22:30:45.123");
        header.set_string("IMAGETYP", "Light");
        header.set_float("EXPTIME", 300.0);
        header.set_string("OBJECT", "M31");
        header.set_string("FILTER", "Luminance");

        // Equipment
        header.set_string("TELESCOP", "Test Telescope");
        header.set_string("INSTRUME", "Test Camera");
        header.set_string("OBSERVER", "Test Observer");

        // Camera settings
        header.set_int("GAIN", 139);
        header.set_int("OFFSET", 21);
        header.set_float("CCD-TEMP", -10.0);
        header.set_int("XBINNING", 1);
        header.set_int("YBINNING", 1);

        // Optics
        header.set_float("FOCALLEN", 600.0);
        header.set_float("APTDIA", 100.0);
        header.set_float("PIXSIZE1", 3.76);
        header.set_float("PIXSIZE2", 3.76);
        header.set_float("XPIXSZ", 3.76);
        header.set_float("YPIXSZ", 3.76);

        // Observer location
        header.set_float("SITELAT", 39.0);
        header.set_float("SITELONG", -77.0);
        header.set_float("SITEELEV", 100.0);

        // Target coordinates
        header.set_float("RA", 10.685);
        header.set_float("DEC", 41.27);
        header.set_float("AIRMASS", 1.15);

        // Validate header completeness
        let validation = validate_fits_header(&header);
        assert!(validation.is_valid, "Complete header should be valid");
        assert!(
            validation.warnings.is_empty(),
            "Complete header should have no warnings"
        );

        // Verify all values
        assert_eq!(
            header.get_string("DATE-OBS"),
            Some("2025-01-15T22:30:45.123")
        );
        assert_eq!(header.get_string("IMAGETYP"), Some("Light"));
        assert_eq!(header.get_float("EXPTIME"), Some(300.0));
        assert_eq!(header.get_float("FOCALLEN"), Some(600.0));
        assert_eq!(header.get_float("SITELAT"), Some(39.0));
        assert_eq!(header.get_float("AIRMASS"), Some(1.15));
    }

    #[test]
    fn test_fits_round_trip() {
        // Create test image
        let width = 100;
        let height = 100;
        let data: Vec<u16> = (0..10000).map(|i| (i % 65535) as u16).collect();
        let _image = ImageData::from_u16(width, height, 1, &data);

        // Create header with metadata
        let mut header = FitsHeader::new();
        header.set_bool("SIMPLE", true);
        header.set_int("BITPIX", 16);
        header.set_int("NAXIS", 2);
        header.set_int("NAXIS1", width as i64);
        header.set_int("NAXIS2", height as i64);
        header.set_string("OBJECT", "M31");
        header.set_float("EXPTIME", 180.0);
        header.set_string("DATE-OBS", "2025-01-15T22:30:45");
        header.set_string("IMAGETYP", "Light");
        header.set_float("AIRMASS", 1.2);

        // Validate the header
        let validation = validate_fits_header(&header);
        assert!(validation.is_valid, "Header should be valid");

        // Verify specific keywords exist
        assert!(header.get("OBJECT").is_some());
        assert!(header.get("EXPTIME").is_some());
        assert!(header.get("DATE-OBS").is_some());
        assert!(header.get("IMAGETYP").is_some());
        assert!(header.get("AIRMASS").is_some());
    }

    #[test]
    fn test_quality_score_edge_cases() {
        // Test with zero values
        let score = calculate_quality_score(Some(0.0), Some(0), 0.0, 0.0);
        assert!(
            (0.0..=100.0).contains(&score),
            "Score should be valid even with zeros"
        );

        // Test with very high HFR
        let score = calculate_quality_score(Some(20.0), Some(150), 5000.0, 500.0);
        assert!(
            score < 50.0,
            "Very high HFR should lower score significantly"
        );

        // Test with perfect image
        let score = calculate_quality_score(Some(1.5), Some(200), 10000.0, 500.0);
        assert!(
            score > 90.0,
            "Perfect image (HFR=1.5, stars=200, CV=0.05) should score > 90"
        );
    }

    #[test]
    fn test_parse_fits_value_requires_exact_boolean_tokens() {
        assert!(matches!(
            parse_fits_value("F / false").unwrap(),
            FitsValue::Boolean(false)
        ));
        assert!(matches!(
            parse_fits_value("FLAT / image type").unwrap(),
            FitsValue::String(value) if value == "FLAT"
        ));
    }

    #[test]
    fn test_parse_fits_value_preserves_slash_inside_string() {
        assert!(matches!(
            parse_fits_value("'L-eXtreme / Duo' / filter").unwrap(),
            FitsValue::String(value) if value == "L-eXtreme / Duo"
        ));
    }

    #[test]
    fn test_read_header_rejects_invalid_keyword() {
        let mut bytes = vec![b' '; 2880];
        bytes[..80].copy_from_slice(
            b"BAD*KEY =                    1                                                  ",
        );
        bytes[80..160].copy_from_slice(
            b"END                                                                             ",
        );

        let err = read_header(&mut Cursor::new(bytes)).unwrap_err();
        assert!(matches!(err, FitsError::InvalidFormat(_)));
    }

    #[test]
    fn test_write_keyword_rejects_overflowing_string() {
        let mut out = Vec::new();
        let value = format!("'{}'", "A".repeat(71));
        let err = write_value_card(&mut out, "OBJECT", &value, None).unwrap_err();
        assert!(matches!(err, FitsError::InvalidFormat(_)));
    }

    #[test]
    fn test_read_fits_requires_naxis2_for_2d_images() {
        let mut bytes = vec![b' '; 2880];
        let cards = [
            "SIMPLE  =                    T",
            "BITPIX  =                   16",
            "NAXIS   =                    2",
            "NAXIS1  =                   10",
            "END",
        ];

        for (idx, card) in cards.iter().enumerate() {
            let offset = idx * 80;
            let mut card_bytes = [b' '; 80];
            let raw = card.as_bytes();
            card_bytes[..raw.len()].copy_from_slice(raw);
            bytes[offset..offset + 80].copy_from_slice(&card_bytes);
        }

        let err = read_fits_from_bytes(&bytes).unwrap_err();
        assert!(matches!(err, FitsError::MissingKeyword(keyword) if keyword == "NAXIS2"));
    }

    #[test]
    fn test_duplicate_keywords_do_not_write_twice() {
        let image = ImageData::from_u16(2, 1, 1, &[1, 2]);
        let mut fits_bytes = Vec::new();
        let raw_header = concat!(
            "SIMPLE  =                    T                                                  ",
            "BITPIX  =                   16                                                  ",
            "NAXIS   =                    2                                                  ",
            "NAXIS1  =                    2                                                  ",
            "NAXIS2  =                    1                                                  ",
            "OBJECT  = 'M31     '                                                            ",
            "OBJECT  = 'M42     '                                                            ",
            "END                                                                             "
        );
        fits_bytes.extend_from_slice(raw_header.as_bytes());
        fits_bytes.resize(2880, b' ');
        fits_bytes.extend_from_slice(&[0, 1, 0, 2]);
        fits_bytes.resize(5760, 0);

        let (_, header) = read_fits_from_bytes(&fits_bytes).expect("header should parse");

        let path = std::env::temp_dir().join(format!(
            "nightshade_duplicate_keyword_{}.fits",
            std::process::id()
        ));
        write_fits(&path, &image, &header).expect("write should succeed");
        let output = std::fs::read(&path).expect("fits bytes should be readable");
        let _ = std::fs::remove_file(&path);

        let header_text = String::from_utf8_lossy(&output[..2880.min(output.len())]);
        assert_eq!(header_text.matches("OBJECT").count(), 1);
        assert_eq!(header.get_string("OBJECT"), Some("M42"));
    }

    #[test]
    fn test_write_keyword_rejects_overflowing_numeric_value() {
        let mut out = Vec::new();
        let value = "1".repeat(71);
        let err = write_value_card(&mut out, "EXPTIME", &value, None).unwrap_err();
        assert!(matches!(err, FitsError::InvalidFormat(_)));
    }

    /// Helper: assemble a minimal FITS byte stream from in-order 80-byte cards.
    fn synth_fits_with_cards(cards: &[&str], data: &[u8]) -> Vec<u8> {
        let mut bytes = Vec::new();
        for card in cards {
            let mut buf = [b' '; 80];
            let raw = card.as_bytes();
            let copy = raw.len().min(80);
            buf[..copy].copy_from_slice(&raw[..copy]);
            bytes.extend_from_slice(&buf);
        }
        let mut buf = [b' '; 80];
        buf[..3].copy_from_slice(b"END");
        bytes.extend_from_slice(&buf);
        // Pad header to 2880-byte boundary
        let pad = (2880 - (bytes.len() % 2880)) % 2880;
        bytes.extend(std::iter::repeat_n(b' ', pad));
        bytes.extend_from_slice(data);
        let pad = (2880 - (bytes.len() % 2880)) % 2880;
        bytes.extend(std::iter::repeat_n(0u8, pad));
        bytes
    }

    // -------------------- §6.3 BSCALE/BZERO round-trip --------------------

    #[test]
    fn test_decode_strips_bscale_bzero_from_header() {
        // Build a U16 file with explicit BSCALE=2.0/BZERO=1000.0 stored as i16
        // big-endian. Decode must apply the scaling AND remove BSCALE/BZERO from
        // the returned header so a follow-up write does not double-apply them.
        let cards = [
            "SIMPLE  =                    T",
            "BITPIX  =                   16",
            "NAXIS   =                    2",
            "NAXIS1  =                    2",
            "NAXIS2  =                    1",
            "BZERO   =               1000.0",
            "BSCALE  =                  2.0",
        ];
        // i16 big-endian: pixels {-100, 50}
        let data: Vec<u8> = vec![0xFF, 0x9C, 0x00, 0x32]; // -100, 50 in BE
        let bytes = synth_fits_with_cards(&cards, &data);

        let (image, header) = read_fits_from_bytes(&bytes).expect("read should succeed");
        assert!(
            header.get("BZERO").is_none(),
            "BZERO must be stripped after decode (audit §6.3)"
        );
        assert!(
            header.get("BSCALE").is_none(),
            "BSCALE must be stripped after decode (audit §6.3)"
        );
        // Pixels: physical = raw * 2 + 1000 → {-100*2+1000=800, 50*2+1000=1100}
        assert_eq!(image.pixel_type, PixelType::U16);
        let pix: Vec<u16> = image
            .data
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        assert_eq!(pix, vec![800, 1100]);
    }

    #[test]
    fn test_round_trip_with_nontrivial_bscale_bzero() {
        // CRITICAL: write the read-back header to a temp file, reload, and
        // assert pixels are identical (no double-scaling).
        let cards = [
            "SIMPLE  =                    T",
            "BITPIX  =                   16",
            "NAXIS   =                    2",
            "NAXIS1  =                    4",
            "NAXIS2  =                    1",
            "BZERO   =               1000.0",
            "BSCALE  =                  2.0",
            "OBJECT  = 'NGC1'",
        ];
        // Four i16 BE pixels: -200, 100, 0, 32000  →  physical: 600, 1200, 1000, 65000
        let data: Vec<u8> = vec![
            0xFF, 0x38, 0x00, 0x64, 0x00, 0x00, 0x7D, 0x00,
        ];
        let bytes = synth_fits_with_cards(&cards, &data);
        let (image_a, header_a) = read_fits_from_bytes(&bytes).expect("first read");
        let pix_a: Vec<u16> = image_a
            .data
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        assert_eq!(pix_a, vec![600, 1200, 1000, 65000]);

        let path = std::env::temp_dir().join(format!(
            "nightshade_bscale_roundtrip_{}.fits",
            std::process::id()
        ));
        write_fits(&path, &image_a, &header_a).expect("write");
        let on_disk = std::fs::read(&path).expect("read back");
        let _ = std::fs::remove_file(&path);

        let (image_b, header_b) = read_fits_from_bytes(&on_disk).expect("second read");
        let pix_b: Vec<u16> = image_b
            .data
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        assert_eq!(
            pix_a, pix_b,
            "Pixels must round-trip exactly (no double scaling)"
        );
        // After the second read, BSCALE/BZERO have again been folded into pixels
        // and stripped from the header.
        assert!(header_b.get("BSCALE").is_none());
        assert!(header_b.get("BZERO").is_none());
    }

    // -------------------- §6.5 header invariants --------------------

    #[test]
    fn test_format_fits_string_value_pads_short_strings() {
        // FITS 4.2.1.1 — string body must be ≥ 8 chars between the quotes.
        let formatted = format_fits_string_value("ABC");
        assert_eq!(formatted, "'ABC     '", "short strings must pad to 8 chars");
        let formatted = format_fits_string_value("LongerThanEight");
        assert_eq!(formatted, "'LongerThanEight'");
    }

    #[test]
    fn test_format_fits_string_value_escapes_quote() {
        let formatted = format_fits_string_value("O'Brien");
        // Internal `'` becomes `''` per FITS 4.2.1.1; total quoted body is 8 chars.
        assert_eq!(formatted, "'O''Brien'");
    }

    #[test]
    fn test_write_emits_short_string_padded() {
        let mut header = FitsHeader::new();
        header.set_string("OBJECT", "M31");
        let image = ImageData::from_u16(2, 1, 1, &[10, 20]);

        let path = std::env::temp_dir().join(format!(
            "nightshade_strpad_{}.fits",
            std::process::id()
        ));
        write_fits(&path, &image, &header).expect("write");
        let on_disk = std::fs::read(&path).expect("read");
        let _ = std::fs::remove_file(&path);

        let header_text = String::from_utf8_lossy(&on_disk[..2880]);
        // The OBJECT card must contain the padded form "M31     " between quotes.
        assert!(
            header_text.contains("'M31     '"),
            "OBJECT card must pad short string to 8 chars, header was:\n{}",
            header_text
        );
    }

    #[test]
    fn test_write_emits_comment_and_history_without_equals() {
        let mut header = FitsHeader::new();
        header.add_comment("Calibrated with master flat 2026-04-09");
        header.add_history("STAR-DETECT v2.5 ran 2026-05-09T22:14:11");
        let image = ImageData::from_u16(2, 1, 1, &[1, 2]);

        let path = std::env::temp_dir().join(format!(
            "nightshade_comment_history_{}.fits",
            std::process::id()
        ));
        write_fits(&path, &image, &header).expect("write");
        let on_disk = std::fs::read(&path).expect("read");
        let _ = std::fs::remove_file(&path);

        // Locate the COMMENT card and verify columns 9..10 are NOT "= ".
        let header_block = &on_disk[..2880];
        let mut found_comment = false;
        let mut found_history = false;
        for chunk in header_block.chunks_exact(80) {
            if chunk.starts_with(b"COMMENT ") {
                // Per FITS 4.4.2.4 the text body starts at column 9 (offset 8) and
                // there must be no `=` at offset 8.
                assert_ne!(
                    chunk[8], b'=',
                    "COMMENT card must not have `=` separator"
                );
                let body = String::from_utf8_lossy(&chunk[8..]);
                assert!(body.contains("Calibrated with master flat"));
                found_comment = true;
            }
            if chunk.starts_with(b"HISTORY ") {
                assert_ne!(
                    chunk[8], b'=',
                    "HISTORY card must not have `=` separator"
                );
                let body = String::from_utf8_lossy(&chunk[8..]);
                assert!(body.contains("STAR-DETECT v2.5"));
                found_history = true;
            }
        }
        assert!(found_comment, "COMMENT card not emitted");
        assert!(found_history, "HISTORY card not emitted");
    }

    #[test]
    fn test_read_routes_comment_history_to_dedicated_vectors() {
        let cards = [
            "SIMPLE  =                    T",
            "BITPIX  =                   16",
            "NAXIS   =                    2",
            "NAXIS1  =                    1",
            "NAXIS2  =                    1",
            "COMMENT free-form note one",
            "HISTORY processed at 2026-04-01",
            "COMMENT free-form note two",
        ];
        let data: Vec<u8> = vec![0x00, 0x10];
        let bytes = synth_fits_with_cards(&cards, &data);
        let (_image, header) = read_fits_from_bytes(&bytes).expect("read");
        assert_eq!(header.comments.len(), 2);
        assert!(header.comments[0].contains("note one"));
        assert!(header.comments[1].contains("note two"));
        assert_eq!(header.history.len(), 1);
        assert!(header.history[0].contains("processed at 2026-04-01"));
        // The `keywords` map must NOT contain synthetic COMMENT_<n>/HISTORY_<n> keys.
        for key in header.keywords.keys() {
            assert!(
                !key.starts_with("COMMENT") && !key.starts_with("HISTORY"),
                "keywords map must not contain COMMENT/HISTORY synthetic keys, found: {}",
                key
            );
        }
    }

    #[test]
    fn test_inline_comment_round_trips() {
        let cards = [
            "SIMPLE  =                    T",
            "BITPIX  =                   16",
            "NAXIS   =                    2",
            "NAXIS1  =                    1",
            "NAXIS2  =                    1",
            "EXPTIME =                300.0 / total integration in seconds",
        ];
        let data: Vec<u8> = vec![0x00, 0x10];
        let bytes = synth_fits_with_cards(&cards, &data);
        let (_image, header) = read_fits_from_bytes(&bytes).expect("read");
        assert_eq!(
            header.get_comment("EXPTIME"),
            Some("total integration in seconds")
        );
    }

    #[test]
    fn test_naxis_4_rejected() {
        // Audit §6.5 — 4-D cubes are not silently truncated; the reader must Err.
        let cards = [
            "SIMPLE  =                    T",
            "BITPIX  =                   16",
            "NAXIS   =                    4",
            "NAXIS1  =                    1",
            "NAXIS2  =                    1",
            "NAXIS3  =                    1",
            "NAXIS4  =                    1",
        ];
        let data: Vec<u8> = vec![0x00, 0x10];
        let bytes = synth_fits_with_cards(&cards, &data);
        let err = read_fits_from_bytes(&bytes).unwrap_err();
        assert!(
            matches!(err, FitsError::Unsupported4DCube { naxis: 4 }),
            "expected Unsupported4DCube, got {:?}",
            err
        );
    }

    // -------------------- §6.6 XBAYROFF/YBAYROFF composition --------------------

    #[test]
    fn test_effective_bayer_pattern_zero_offset_identity() {
        for src in [
            BayerPattern::RGGB,
            BayerPattern::BGGR,
            BayerPattern::GRBG,
            BayerPattern::GBRG,
        ] {
            assert_eq!(effective_bayer_pattern(src, 0, 0), src);
            assert_eq!(effective_bayer_pattern(src, 2, 4), src);
        }
    }

    #[test]
    fn test_effective_bayer_pattern_rggb_x1_y0_yields_grbg() {
        // Audit §6.6 explicit case.
        assert_eq!(
            effective_bayer_pattern(BayerPattern::RGGB, 1, 0),
            BayerPattern::GRBG
        );
    }

    #[test]
    fn test_effective_bayer_pattern_rggb_x0_y1_yields_gbrg() {
        assert_eq!(
            effective_bayer_pattern(BayerPattern::RGGB, 0, 1),
            BayerPattern::GBRG
        );
    }

    #[test]
    fn test_effective_bayer_pattern_rggb_x1_y1_yields_bggr() {
        assert_eq!(
            effective_bayer_pattern(BayerPattern::RGGB, 1, 1),
            BayerPattern::BGGR
        );
    }

    #[test]
    fn test_effective_bayer_pattern_negative_offset_wraps() {
        // -1 has the same parity as +1, so result must match.
        assert_eq!(
            effective_bayer_pattern(BayerPattern::RGGB, -1, 0),
            effective_bayer_pattern(BayerPattern::RGGB, 1, 0),
        );
    }

    #[test]
    fn test_read_bayer_geometry_from_header() {
        let mut header = FitsHeader::new();
        header.set_string("BAYERPAT", "RGGB");
        header.set_int("XBAYROFF", 1);
        header.set_int("YBAYROFF", 0);
        let geo = read_bayer_geometry(&header).expect("geometry");
        assert_eq!(geo.source, BayerPattern::RGGB);
        assert_eq!(geo.effective, BayerPattern::GRBG);
        assert_eq!(geo.x_offset, 1);
        assert_eq!(geo.y_offset, 0);
    }

    #[test]
    fn test_read_bayer_geometry_defaults_offsets_to_zero() {
        let mut header = FitsHeader::new();
        header.set_string("BAYERPAT", "BGGR");
        let geo = read_bayer_geometry(&header).expect("geometry");
        assert_eq!(geo.source, BayerPattern::BGGR);
        assert_eq!(geo.effective, BayerPattern::BGGR);
        assert_eq!(geo.x_offset, 0);
        assert_eq!(geo.y_offset, 0);
    }

    #[test]
    fn test_read_bayer_geometry_returns_none_without_bayerpat() {
        let header = FitsHeader::new();
        assert!(read_bayer_geometry(&header).is_none());
    }
}
