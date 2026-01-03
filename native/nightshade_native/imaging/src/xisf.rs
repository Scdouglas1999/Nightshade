//! XISF (Extensible Image Serialization Format) support
//!
//! XISF is PixInsight's native format. Structure:
//! - XML header with metadata
//! - Binary data block(s)
//! - Optional compression (zlib, lz4, zstd)

use crate::{ImageData, PixelType};
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Write, Seek, SeekFrom};
use std::path::Path;

/// XISF file magic signature
const XISF_MAGIC: &[u8; 8] = b"XISF0100";

/// XISF metadata
#[derive(Debug, Clone, Default)]
pub struct XisfMetadata {
    pub properties: HashMap<String, XisfProperty>,
    pub fits_keywords: HashMap<String, String>,
}

/// XISF property types
#[derive(Debug, Clone)]
pub enum XisfProperty {
    String(String),
    Int8(i8),
    Int16(i16),
    Int32(i32),
    Int64(i64),
    UInt8(u8),
    UInt16(u16),
    UInt32(u32),
    UInt64(u64),
    Float32(f32),
    Float64(f64),
    Boolean(bool),
    TimePoint(String),  // ISO 8601 format
}

impl XisfProperty {
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            XisfProperty::Float64(f) => Some(*f),
            XisfProperty::Float32(f) => Some(*f as f64),
            XisfProperty::Int64(i) => Some(*i as f64),
            XisfProperty::Int32(i) => Some(*i as f64),
            XisfProperty::Int16(i) => Some(*i as f64),
            XisfProperty::Int8(i) => Some(*i as f64),
            XisfProperty::UInt64(u) => Some(*u as f64),
            XisfProperty::UInt32(u) => Some(*u as f64),
            XisfProperty::UInt16(u) => Some(*u as f64),
            XisfProperty::UInt8(u) => Some(*u as f64),
            _ => None,
        }
    }
    
    pub fn as_string(&self) -> Option<&str> {
        match self {
            XisfProperty::String(s) => Some(s),
            XisfProperty::TimePoint(s) => Some(s),
            _ => None,
        }
    }
}

/// XISF error types
#[derive(Debug)]
pub enum XisfError {
    Io(std::io::Error),
    InvalidFormat(String),
    XmlParse(String),
    Compression(String),
    UnsupportedSampleFormat(String),
}

impl std::fmt::Display for XisfError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            XisfError::Io(e) => write!(f, "IO error: {}", e),
            XisfError::InvalidFormat(s) => write!(f, "Invalid XISF format: {}", s),
            XisfError::XmlParse(s) => write!(f, "XML parse error: {}", s),
            XisfError::Compression(s) => write!(f, "Compression error: {}", s),
            XisfError::UnsupportedSampleFormat(s) => write!(f, "Unsupported sample format: {}", s),
        }
    }
}

impl std::error::Error for XisfError {}

impl From<std::io::Error> for XisfError {
    fn from(e: std::io::Error) -> Self {
        XisfError::Io(e)
    }
}

/// Read an XISF file
pub fn read_xisf(path: &Path) -> Result<(ImageData, XisfMetadata), XisfError> {
    let file = File::open(path)?;
    let mut reader = BufReader::new(file);
    
    // Read and verify magic signature
    let mut magic = [0u8; 8];
    reader.read_exact(&mut magic)?;
    
    if &magic != XISF_MAGIC {
        return Err(XisfError::InvalidFormat("Invalid XISF magic signature".to_string()));
    }
    
    // Read header length (little-endian u32)
    let mut header_len_bytes = [0u8; 4];
    reader.read_exact(&mut header_len_bytes)?;
    let header_len = u32::from_le_bytes(header_len_bytes) as usize;
    
    // Skip reserved bytes (4 bytes)
    let mut reserved = [0u8; 4];
    reader.read_exact(&mut reserved)?;
    
    // Read XML header
    let mut xml_bytes = vec![0u8; header_len];
    reader.read_exact(&mut xml_bytes)?;
    let xml_str = String::from_utf8_lossy(&xml_bytes);
    
    // Parse XML header (simplified parser)
    let (width, height, channels, sample_format, data_offset, data_size, _color_space) =
        parse_xisf_header(&xml_str)?;
    
    let metadata = parse_xisf_metadata(&xml_str)?;
    
    // Seek to data block
    reader.seek(SeekFrom::Start(data_offset as u64))?;
    
    // Read pixel data
    let mut data = vec![0u8; data_size];
    reader.read_exact(&mut data)?;
    
    // Determine pixel type
    let pixel_type = match sample_format.as_str() {
        "UInt8" => PixelType::U8,
        "UInt16" => PixelType::U16,
        "UInt32" => PixelType::U32,
        "Float32" => PixelType::F32,
        "Float64" => PixelType::F64,
        other => return Err(XisfError::UnsupportedSampleFormat(other.to_string())),
    };
    
    // XISF stores data in channel-major order (all R, then all G, then all B)
    // We need to keep it as-is for processing
    let image = ImageData {
        width,
        height,
        channels,
        pixel_type,
        data,
    };
    
    Ok((image, metadata))
}

/// Parse XISF XML header for image dimensions and data location
fn parse_xisf_header(xml: &str) -> Result<(u32, u32, u32, String, usize, usize, String), XisfError> {
    // Simple regex-like parsing for key attributes
    // In production, use a proper XML parser
    
    let width = extract_attribute(xml, "geometry", 0)
        .ok_or_else(|| XisfError::XmlParse("Missing width".to_string()))?;
    let height = extract_attribute(xml, "geometry", 1)
        .ok_or_else(|| XisfError::XmlParse("Missing height".to_string()))?;
    let channels = extract_attribute(xml, "geometry", 2).unwrap_or(1);
    
    let sample_format = extract_string_attribute(xml, "sampleFormat")
        .unwrap_or_else(|| "UInt16".to_string());
    
    let color_space = extract_string_attribute(xml, "colorSpace")
        .unwrap_or_else(|| "Gray".to_string());
    
    // Parse attachment location
    let (data_offset, data_size) = parse_attachment_location(xml)?;
    
    Ok((width, height, channels, sample_format, data_offset, data_size, color_space))
}

/// Extract numeric attribute from geometry string "W:H:C"
fn extract_attribute(xml: &str, attr: &str, index: usize) -> Option<u32> {
    let attr_pattern = format!("{}=\"", attr);
    let start = xml.find(&attr_pattern)? + attr_pattern.len();
    let end = xml[start..].find('"')? + start;
    let value = &xml[start..end];
    
    // geometry format is "W:H:C" or "W:H"
    let parts: Vec<&str> = value.split(':').collect();
    parts.get(index)?.parse().ok()
}

/// Extract string attribute value
fn extract_string_attribute(xml: &str, attr: &str) -> Option<String> {
    let attr_pattern = format!("{}=\"", attr);
    let start = xml.find(&attr_pattern)? + attr_pattern.len();
    let end = xml[start..].find('"')? + start;
    Some(xml[start..end].to_string())
}

/// Parse attachment location "attachment:OFFSET:SIZE"
fn parse_attachment_location(xml: &str) -> Result<(usize, usize), XisfError> {
    // Look for location attribute
    let loc_start = xml.find("location=\"attachment:")
        .ok_or_else(|| XisfError::XmlParse("Missing attachment location".to_string()))?;
    
    let loc_start = loc_start + "location=\"attachment:".len();
    let loc_end = xml[loc_start..].find('"')
        .ok_or_else(|| XisfError::XmlParse("Invalid attachment location".to_string()))?
        + loc_start;
    
    let loc_str = &xml[loc_start..loc_end];
    let parts: Vec<&str> = loc_str.split(':').collect();
    
    if parts.len() != 2 {
        return Err(XisfError::XmlParse("Invalid attachment format".to_string()));
    }
    
    let offset: usize = parts[0].parse()
        .map_err(|_| XisfError::XmlParse("Invalid offset".to_string()))?;
    let size: usize = parts[1].parse()
        .map_err(|_| XisfError::XmlParse("Invalid size".to_string()))?;
    
    Ok((offset, size))
}

/// Parse XISF metadata properties
fn parse_xisf_metadata(xml: &str) -> Result<XisfMetadata, XisfError> {
    let mut metadata = XisfMetadata::default();
    
    // Parse Property elements
    let mut search_start = 0;
    while let Some(prop_start) = xml[search_start..].find("<Property ") {
        let abs_start = search_start + prop_start;
        if let Some(prop_end) = xml[abs_start..].find("/>") {
            let prop_xml = &xml[abs_start..abs_start + prop_end + 2];
            
            if let (Some(id), Some(value)) = (
                extract_string_attribute(prop_xml, "id"),
                extract_string_attribute(prop_xml, "value")
            ) {
                let prop_type = extract_string_attribute(prop_xml, "type")
                    .unwrap_or_else(|| "String".to_string());
                
                let property = parse_property_value(&value, &prop_type);
                metadata.properties.insert(id, property);
            }
            
            search_start = abs_start + prop_end + 2;
        } else {
            break;
        }
    }
    
    // Parse FITSKeyword elements
    search_start = 0;
    while let Some(kw_start) = xml[search_start..].find("<FITSKeyword ") {
        let abs_start = search_start + kw_start;
        if let Some(kw_end) = xml[abs_start..].find("/>") {
            let kw_xml = &xml[abs_start..abs_start + kw_end + 2];
            
            if let (Some(name), Some(value)) = (
                extract_string_attribute(kw_xml, "name"),
                extract_string_attribute(kw_xml, "value")
            ) {
                metadata.fits_keywords.insert(name, value);
            }
            
            search_start = abs_start + kw_end + 2;
        } else {
            break;
        }
    }
    
    Ok(metadata)
}

/// Parse property value based on type
fn parse_property_value(value: &str, prop_type: &str) -> XisfProperty {
    match prop_type {
        "Int8" => value.parse().map(XisfProperty::Int8).unwrap_or(XisfProperty::String(value.to_string())),
        "Int16" => value.parse().map(XisfProperty::Int16).unwrap_or(XisfProperty::String(value.to_string())),
        "Int32" => value.parse().map(XisfProperty::Int32).unwrap_or(XisfProperty::String(value.to_string())),
        "Int64" => value.parse().map(XisfProperty::Int64).unwrap_or(XisfProperty::String(value.to_string())),
        "UInt8" => value.parse().map(XisfProperty::UInt8).unwrap_or(XisfProperty::String(value.to_string())),
        "UInt16" => value.parse().map(XisfProperty::UInt16).unwrap_or(XisfProperty::String(value.to_string())),
        "UInt32" => value.parse().map(XisfProperty::UInt32).unwrap_or(XisfProperty::String(value.to_string())),
        "UInt64" => value.parse().map(XisfProperty::UInt64).unwrap_or(XisfProperty::String(value.to_string())),
        "Float32" => value.parse().map(XisfProperty::Float32).unwrap_or(XisfProperty::String(value.to_string())),
        "Float64" => value.parse().map(XisfProperty::Float64).unwrap_or(XisfProperty::String(value.to_string())),
        "Boolean" => XisfProperty::Boolean(value == "true" || value == "1"),
        "TimePoint" => XisfProperty::TimePoint(value.to_string()),
        _ => XisfProperty::String(value.to_string()),
    }
}

/// Write an XISF file
pub fn write_xisf(path: &Path, image: &ImageData, metadata: &XisfMetadata) -> Result<(), XisfError> {
    let file = File::create(path)?;
    let mut writer = BufWriter::new(file);

    let data_size = image.data.len();

    // XISF format:
    // - 8 bytes: magic signature "XISF0100"
    // - 4 bytes: header length (little-endian u32)
    // - 4 bytes: reserved (zeros)
    // - N bytes: XML header
    // - padding to align data
    // - image data

    // We need to calculate the data offset, but the offset depends on the XML length,
    // which depends on the offset (circular dependency).
    // Solution: Use a fixed alignment and iterate if needed.

    // First pass: estimate XML size with placeholder offset
    let placeholder_offset = 16 + 4096;  // Conservative estimate
    let xml_v1 = build_xisf_xml_with_location(image, metadata, placeholder_offset, data_size);

    // Calculate required padding to align data to 16-byte boundary (XISF spec recommendation)
    let xml_len_v1 = xml_v1.len();
    let header_with_magic = 16 + xml_len_v1;  // magic(8) + length(4) + reserved(4) + xml
    let aligned_offset = (header_with_magic + 15) & !15;  // Align to 16 bytes

    // Second pass: rebuild XML with correct offset
    let xml_final = build_xisf_xml_with_location(image, metadata, aligned_offset, data_size);
    let xml_bytes = xml_final.as_bytes();

    // Verify offset didn't change significantly (different digit count could change length)
    let final_header = 16 + xml_bytes.len();
    let final_aligned = (final_header + 15) & !15;

    // If the offset changed, recalculate one more time
    let (xml_bytes, data_offset) = if final_aligned != aligned_offset {
        let xml_final2 = build_xisf_xml_with_location(image, metadata, final_aligned, data_size);
        let bytes = xml_final2.into_bytes();
        let offset = (16 + bytes.len() + 15) & !15;
        (bytes, offset)
    } else {
        (xml_bytes.to_vec(), aligned_offset)
    };

    // Write magic signature
    writer.write_all(XISF_MAGIC)?;

    // Write header length (actual XML size, not padded - per XISF spec)
    writer.write_all(&(xml_bytes.len() as u32).to_le_bytes())?;

    // Write reserved (4 bytes)
    writer.write_all(&[0u8; 4])?;

    // Write XML header
    writer.write_all(&xml_bytes)?;

    // Pad to data offset
    let current_pos = 16 + xml_bytes.len();
    let padding = data_offset - current_pos;
    if padding > 0 {
        writer.write_all(&vec![0u8; padding])?;
    }

    // Write image data
    writer.write_all(&image.data)?;

    writer.flush()?;

    tracing::debug!(
        "XISF written: {}x{}, {} bytes data at offset {}",
        image.width, image.height, data_size, data_offset
    );

    Ok(())
}

/// Build XISF XML header
fn build_xisf_xml(image: &ImageData, metadata: &XisfMetadata) -> String {
    build_xisf_xml_with_location(image, metadata, 0, image.data.len())
}

/// Build XISF XML header with data location
fn build_xisf_xml_with_location(
    image: &ImageData,
    metadata: &XisfMetadata,
    data_offset: usize,
    data_size: usize
) -> String {
    let sample_format = match image.pixel_type {
        PixelType::U8 => "UInt8",
        PixelType::U16 => "UInt16",
        PixelType::U32 => "UInt32",
        PixelType::F32 => "Float32",
        PixelType::F64 => "Float64",
    };

    // Bounds attribute - tells PixInsight the valid data range
    let bounds = match image.pixel_type {
        PixelType::U8 => "0:255",
        PixelType::U16 => "0:65535",
        PixelType::U32 => "0:4294967295",
        PixelType::F32 | PixelType::F64 => "0:1",  // Normalized
    };

    let color_space = if image.channels == 1 { "Gray" } else { "RGB" };
    let geometry = if image.channels == 1 {
        format!("{}:{}", image.width, image.height)
    } else {
        format!("{}:{}:{}", image.width, image.height, image.channels)
    };

    let mut xml = String::new();
    xml.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    xml.push_str("<xisf version=\"1.0\" xmlns=\"http://www.pixinsight.com/xisf\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.pixinsight.com/xisf http://pixinsight.com/xisf/xisf-1.0.xsd\">\n");

    // Image element with all required attributes
    xml.push_str(&format!(
        "  <Image geometry=\"{}\" sampleFormat=\"{}\" bounds=\"{}\" colorSpace=\"{}\" location=\"attachment:{}:{}\">\n",
        geometry, sample_format, bounds, color_space, data_offset, data_size
    ));

    // Add XISF creator property
    xml.push_str("    <Property id=\"XISF:CreatorApplication\" type=\"String\" value=\"Nightshade 2.0\"/>\n");
    xml.push_str(&format!(
        "    <Property id=\"XISF:CreationTime\" type=\"TimePoint\" value=\"{}\"/>\n",
        chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ")
    ));

    // Add user-provided properties
    for (id, prop) in &metadata.properties {
        let (type_str, value_str) = property_to_strings(prop);
        xml.push_str(&format!(
            "    <Property id=\"{}\" type=\"{}\" value=\"{}\"/>\n",
            escape_xml(id), type_str, escape_xml(&value_str)
        ));
    }

    // Add FITS keywords for interoperability
    for (name, value) in &metadata.fits_keywords {
        // FITS keywords need proper formatting
        xml.push_str(&format!(
            "    <FITSKeyword name=\"{}\" value=\"{}\" comment=\"\"/>\n",
            escape_xml(name), escape_xml(value)
        ));
    }

    xml.push_str("  </Image>\n");
    xml.push_str("</xisf>\n");

    xml
}

/// Convert property to type and value strings
fn property_to_strings(prop: &XisfProperty) -> (&'static str, String) {
    match prop {
        XisfProperty::String(s) => ("String", s.clone()),
        XisfProperty::Int8(v) => ("Int8", v.to_string()),
        XisfProperty::Int16(v) => ("Int16", v.to_string()),
        XisfProperty::Int32(v) => ("Int32", v.to_string()),
        XisfProperty::Int64(v) => ("Int64", v.to_string()),
        XisfProperty::UInt8(v) => ("UInt8", v.to_string()),
        XisfProperty::UInt16(v) => ("UInt16", v.to_string()),
        XisfProperty::UInt32(v) => ("UInt32", v.to_string()),
        XisfProperty::UInt64(v) => ("UInt64", v.to_string()),
        XisfProperty::Float32(v) => ("Float32", v.to_string()),
        XisfProperty::Float64(v) => ("Float64", v.to_string()),
        XisfProperty::Boolean(v) => ("Boolean", if *v { "true" } else { "false" }.to_string()),
        XisfProperty::TimePoint(s) => ("TimePoint", s.clone()),
    }
}

/// Escape XML special characters
fn escape_xml(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}





