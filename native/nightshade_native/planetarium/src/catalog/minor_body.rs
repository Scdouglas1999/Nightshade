//! MPC minor-body catalog — mmap-friendly binary blob + MPCORB orbit loader.
//!
//! Layout:
//! ```text
//! [MinorBodyCatalogHeader — 64 B][MinorBodyRecord × record_count — 96 B each][UTF-8 string table]
//! ```
//!
//! Orbital elements follow MPC export format (heliocentric, J2000). Propagation uses
//! [`crate::astrometry::kepler`].

use std::fs::File;
use std::path::Path;

use memmap2::Mmap;
use thiserror::Error;
use zerocopy::{AsBytes, FromBytes, FromZeroes};

use crate::astrometry::kepler::{GeocentricEquatorial, OrbitalElements};

/// Magic bytes identifying a planetarium minor-body catalog (`"NSPLNT03"`).
pub const MINOR_BODY_CATALOG_MAGIC: &[u8; 8] = b"NSPLNT03";

/// Fixed header size (bytes).
pub const MINOR_BODY_HEADER_LEN: usize = 64;

/// Packed on-disk record size (bytes).
pub const MINOR_BODY_RECORD_LEN: usize = 96;

/// Pack-local catalog identifier for `solar-system-mpc`.
pub const MPC_CATALOG_ID: u32 = 3;

/// On-disk format version for `mpc-minor-bodies-v1.bin`.
pub const MPC_PACK_VERSION: u32 = 1;

/// `MinorBodyRecord::flags` — readable name present in the string table.
pub const MINOR_BODY_FLAG_HAS_NAME: u32 = 1 << 0;

/// Minor-body classification stored in [`MinorBodyRecord::kind`].
#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MinorBodyKind {
    /// Main-belt or near-Earth asteroid.
    Asteroid = 0,
    /// Comet (periodic or long-period).
    Comet = 1,
}

impl MinorBodyKind {
    /// Infer kind from MPC packed designation / readable name.
    #[must_use]
    pub fn from_designation(designation: &str) -> Self {
        let d = designation.trim();
        if d.contains('/')
            || d.starts_with('C')
            || d.starts_with('P')
            || d.starts_with("C/")
            || d.starts_with("P/")
        {
            Self::Comet
        } else {
            Self::Asteroid
        }
    }
}

/// Errors while parsing or mapping a minor-body catalog blob.
#[derive(Debug, Error)]
pub enum MinorBodyParseError {
    /// Buffer shorter than the fixed header.
    #[error("minor-body catalog truncated: need at least {MINOR_BODY_HEADER_LEN} bytes, got {actual}")]
    TruncatedHeader {
        /// Bytes available.
        actual: usize,
    },
    /// Magic does not match [`MINOR_BODY_CATALOG_MAGIC`].
    #[error("invalid minor-body catalog magic (expected NSPLNT03)")]
    BadMagic,
    /// Total byte length does not match header fields.
    #[error("minor-body catalog size mismatch: expected {expected} bytes, got {actual}")]
    SizeMismatch {
        /// Expected length from header.
        expected: usize,
        /// Actual buffer length.
        actual: usize,
    },
    /// `record_count` does not match records in the buffer.
    #[error("record_count {declared} does not match {actual} minor-body records in blob")]
    RecordCountMismatch {
        /// Value in header.
        declared: u32,
        /// Records parsed from tail.
        actual: usize,
    },
    /// String table offset/length is out of range.
    #[error("invalid string table: offset {offset}, len {len}, blob len {blob_len}")]
    StringTableRange {
        /// Table start offset.
        offset: u32,
        /// Table length.
        len: u32,
        /// Total blob length.
        blob_len: usize,
    },
    /// A record references bytes outside the string table.
    #[error("minor-body record string reference out of range")]
    StringRefOutOfRange,
    /// Memory-map or file I/O failed.
    #[error("{context}: {source}")]
    Io {
        /// Human-readable stage.
        context: &'static str,
        /// Underlying OS error.
        #[source]
        source: std::io::Error,
    },
}

impl MinorBodyParseError {
    fn io(context: &'static str, source: std::io::Error) -> Self {
        Self::Io { context, source }
    }
}

/// Errors while parsing MPC orbit export lines.
#[derive(Debug, Error)]
pub enum MpcParseError {
    /// Line too short for the MPC export format.
    #[error("MPC orbit line too short ({len} chars, need at least {min})")]
    LineTooShort {
        /// Actual length.
        len: usize,
        /// Minimum required length.
        min: usize,
    },
    /// A numeric field failed to parse.
    #[error("invalid MPC field {field}: {detail}")]
    InvalidField {
        /// Column description.
        field: &'static str,
        /// Parse detail.
        detail: String,
    },
    /// Packed epoch could not be decoded.
    #[error("invalid MPC packed epoch: {0}")]
    PackedEpoch(String),
}

/// Minimum MPC export line length (semi-major axis ends at column 103).
pub const MPC_ORBIT_LINE_MIN_LEN: usize = 103;

/// 64-byte catalog header (`solar-system-mpc` pack).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, FromZeroes, FromBytes, AsBytes)]
pub struct MinorBodyCatalogHeader {
    /// Must equal [`MINOR_BODY_CATALOG_MAGIC`].
    pub magic: [u8; 8],
    /// Pack-local catalog identifier ([`MPC_CATALOG_ID`]).
    pub catalog_id: u32,
    /// Pack format version ([`MPC_PACK_VERSION`]).
    pub pack_version: u32,
    /// Number of [`MinorBodyRecord`] entries following this header.
    pub record_count: u32,
    /// Byte offset of the UTF-8 string table from the start of the file.
    pub string_table_offset: u32,
    /// Length of the UTF-8 string table in bytes.
    pub string_table_len: u32,
    /// Padding (keeps header exactly 64 B).
    _pad: u32,
    /// Reserved; must be zero in v1 catalogs.
    pub reserved: [u8; 32],
}

impl MinorBodyCatalogHeader {
    /// Build a header with magic and reserved fields zeroed.
    #[must_use]
    pub fn new(record_count: u32, string_table_offset: u32, string_table_len: u32) -> Self {
        Self {
            magic: *MINOR_BODY_CATALOG_MAGIC,
            catalog_id: MPC_CATALOG_ID,
            pack_version: MPC_PACK_VERSION,
            record_count,
            string_table_offset,
            string_table_len,
            _pad: 0,
            reserved: [0; 32],
        }
    }

    /// Returns `true` when `magic` matches [`MINOR_BODY_CATALOG_MAGIC`].
    #[must_use]
    pub fn magic_valid(&self) -> bool {
        &self.magic == MINOR_BODY_CATALOG_MAGIC
    }
}

/// Packed on-disk minor-body record (MPC osculating elements + photometry).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, FromZeroes, FromBytes, AsBytes)]
pub struct MinorBodyRecord {
    /// Epoch of osculation (Julian date, TT).
    pub epoch_jd: f64,
    /// Semi-major axis (AU).
    pub semi_major_axis_au: f64,
    /// Orbital eccentricity.
    pub eccentricity: f64,
    /// Inclination (degrees, J2000 ecliptic).
    pub inclination_deg: f64,
    /// Longitude of ascending node Ω (degrees).
    pub longitude_ascending_node_deg: f64,
    /// Argument of perihelion ω (degrees).
    pub argument_perihelion_deg: f64,
    /// Mean anomaly at epoch M₀ (degrees).
    pub mean_anomaly_deg: f64,
    /// Absolute magnitude H.
    pub absolute_mag: f32,
    /// Slope parameter G.
    pub slope_param: f32,
    /// Byte offset into the string table for the packed designation (cols 1–7).
    pub designation_offset: u32,
    /// Byte offset into the string table for the readable name (optional).
    pub name_offset: u32,
    /// [`MinorBodyKind`] as `u32`.
    pub kind: u32,
    /// [`MINOR_BODY_FLAG_HAS_NAME`], …
    pub flags: u32,
    /// Length of the designation string in bytes.
    pub designation_len: u16,
    /// Length of the readable name in bytes (`0` when absent).
    pub name_len: u16,
    /// Reserved (keeps record exactly 96 B).
    pub reserved: [u8; 12],
}

impl MinorBodyRecord {
    /// Convert to [`OrbitalElements`] for Kepler propagation.
    #[must_use]
    pub fn orbital_elements(&self) -> OrbitalElements {
        OrbitalElements {
            epoch_jd: self.epoch_jd,
            semi_major_axis_au: self.semi_major_axis_au,
            eccentricity: self.eccentricity,
            inclination_deg: self.inclination_deg,
            longitude_ascending_node_deg: self.longitude_ascending_node_deg,
            argument_perihelion_deg: self.argument_perihelion_deg,
            mean_anomaly_deg: self.mean_anomaly_deg,
        }
    }

    /// Geocentric equatorial J2000 position at Julian date `jd_tt`.
    #[must_use]
    pub fn geocentric_at(&self, jd_tt: f64) -> GeocentricEquatorial {
        crate::astrometry::kepler::geocentric_equatorial_j2000(&self.orbital_elements(), jd_tt)
    }

    /// Classification.
    #[must_use]
    pub fn body_kind(&self) -> MinorBodyKind {
        match self.kind {
            1 => MinorBodyKind::Comet,
            _ => MinorBodyKind::Asteroid,
        }
    }
}

/// One parsed MPC orbit export line (before binary encoding).
#[derive(Debug, Clone, PartialEq)]
pub struct MpcOrbitEntry {
    /// Packed designation (cols 1–7) or readable designation when present.
    pub designation: String,
    /// Readable name from cols 167–194 when the line is long enough.
    pub name: Option<String>,
    /// Asteroid vs comet.
    pub kind: MinorBodyKind,
    /// Absolute magnitude H.
    pub absolute_mag: f32,
    /// Slope parameter G.
    pub slope_param: f32,
    /// Keplerian elements at epoch.
    pub elements: OrbitalElements,
}

/// Borrowed view of a validated minor-body catalog blob.
#[derive(Debug, Clone, Copy)]
pub struct ParsedMinorBodyCatalog<'a> {
    /// Catalog header (first 64 bytes).
    pub header: &'a MinorBodyCatalogHeader,
    /// Minor-body records.
    pub records: &'a [MinorBodyRecord],
    /// Concatenated designation + name strings.
    pub strings: &'a [u8],
}

impl<'a> ParsedMinorBodyCatalog<'a> {
    /// Designation bytes for `record`.
    pub fn designation(&self, record: &MinorBodyRecord) -> Result<&'a str, MinorBodyParseError> {
        string_at(
            self.strings,
            record.designation_offset,
            record.designation_len,
        )
    }

    /// Readable name when present.
    pub fn name(&self, record: &MinorBodyRecord) -> Result<Option<&'a str>, MinorBodyParseError> {
        if record.name_len == 0 {
            return Ok(None);
        }
        Ok(Some(string_at(
            self.strings,
            record.name_offset,
            record.name_len,
        )?))
    }
}

/// Total on-disk size for a catalog with the given record and string table sizes.
#[must_use]
pub fn catalog_byte_len(record_count: usize, string_table_len: usize) -> usize {
    MINOR_BODY_HEADER_LEN + record_count * MINOR_BODY_RECORD_LEN + string_table_len
}

/// Build a catalog blob from MPC orbit entries.
#[must_use]
pub fn encode_catalog(entries: &[MpcOrbitEntry]) -> Vec<u8> {
    let mut strings = Vec::new();
    let mut records = Vec::with_capacity(entries.len());

    for entry in entries {
        let designation_offset = u32::try_from(strings.len()).expect("string table fits u32");
        strings.extend_from_slice(entry.designation.as_bytes());
        let designation_len = u16::try_from(entry.designation.len()).expect("designation fits u16");

        let (name_offset, name_len, flags) = if let Some(name) = &entry.name {
            let name_offset = u32::try_from(strings.len()).expect("string table fits u32");
            strings.extend_from_slice(name.as_bytes());
            let name_len = u16::try_from(name.len()).expect("name fits u16");
            (name_offset, name_len, MINOR_BODY_FLAG_HAS_NAME)
        } else {
            (0, 0, 0)
        };

        records.push(MinorBodyRecord {
            epoch_jd: entry.elements.epoch_jd,
            semi_major_axis_au: entry.elements.semi_major_axis_au,
            eccentricity: entry.elements.eccentricity,
            inclination_deg: entry.elements.inclination_deg,
            longitude_ascending_node_deg: entry.elements.longitude_ascending_node_deg,
            argument_perihelion_deg: entry.elements.argument_perihelion_deg,
            mean_anomaly_deg: entry.elements.mean_anomaly_deg,
            absolute_mag: entry.absolute_mag,
            slope_param: entry.slope_param,
            designation_offset,
            name_offset,
            kind: entry.kind as u32,
            flags,
            designation_len,
            name_len,
            reserved: [0; 12],
        });
    }

    let string_table_offset =
        u32::try_from(MINOR_BODY_HEADER_LEN + records.len() * MINOR_BODY_RECORD_LEN)
            .expect("catalog offset fits u32");
    let string_table_len = u32::try_from(strings.len()).expect("string table len fits u32");
    let header = MinorBodyCatalogHeader::new(
        records.len() as u32,
        string_table_offset,
        string_table_len,
    );

    let mut out = Vec::with_capacity(catalog_byte_len(records.len(), strings.len()));
    out.extend_from_slice(header.as_bytes());
    for record in &records {
        out.extend_from_slice(record.as_bytes());
    }
    out.extend_from_slice(&strings);
    out
}

/// Parse and validate a minor-body catalog from an in-memory byte slice.
pub fn parse_catalog(bytes: &[u8]) -> Result<ParsedMinorBodyCatalog<'_>, MinorBodyParseError> {
    if bytes.len() < MINOR_BODY_HEADER_LEN {
        return Err(MinorBodyParseError::TruncatedHeader {
            actual: bytes.len(),
        });
    }

    let header = MinorBodyCatalogHeader::ref_from_prefix(bytes).ok_or(
        MinorBodyParseError::TruncatedHeader {
            actual: bytes.len(),
        },
    )?;
    if !header.magic_valid() {
        return Err(MinorBodyParseError::BadMagic);
    }

    let record_count = header.record_count as usize;
    let records_end = MINOR_BODY_HEADER_LEN + record_count * MINOR_BODY_RECORD_LEN;
    let expected = records_end + header.string_table_len as usize;
    if bytes.len() != expected {
        return Err(MinorBodyParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        });
    }

    let records = MinorBodyRecord::slice_from_prefix(&bytes[MINOR_BODY_HEADER_LEN..records_end], record_count)
        .map(|(s, _)| s)
        .ok_or(MinorBodyParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        })?;
    if records.len() != record_count {
        return Err(MinorBodyParseError::RecordCountMismatch {
            declared: header.record_count,
            actual: records.len(),
        });
    }

    let st_off = header.string_table_offset as usize;
    let st_len = header.string_table_len as usize;
    if st_off + st_len != bytes.len() {
        return Err(MinorBodyParseError::StringTableRange {
            offset: header.string_table_offset,
            len: header.string_table_len,
            blob_len: bytes.len(),
        });
    }
    let strings = &bytes[st_off..st_off + st_len];

    for record in records {
        string_at(strings, record.designation_offset, record.designation_len)?;
        if record.name_len > 0 {
            string_at(strings, record.name_offset, record.name_len)?;
        }
    }

    Ok(ParsedMinorBodyCatalog {
        header,
        records,
        strings,
    })
}

/// Memory-mapped minor-body catalog (read-only).
pub struct MappedMinorBodyCatalog {
    mmap: Mmap,
}

impl MappedMinorBodyCatalog {
    /// Open and validate `path`, then mmap the file.
    pub fn open(path: &Path) -> Result<Self, MinorBodyParseError> {
        let file = File::open(path).map_err(|e| MinorBodyParseError::io("open minor-body catalog", e))?;
        let mmap =
            unsafe { Mmap::map(&file) }.map_err(|e| MinorBodyParseError::io("mmap minor-body catalog", e))?;
        parse_catalog(&mmap)?;
        Ok(Self { mmap })
    }

    /// Validated borrowed view of the mapped bytes.
    pub fn parsed(&self) -> Result<ParsedMinorBodyCatalog<'_>, MinorBodyParseError> {
        parse_catalog(&self.mmap)
    }
}

/// Parse one MPC orbit export line (≥ [`MPC_ORBIT_LINE_MIN_LEN`] characters).
///
/// Column positions follow <https://minorplanetcenter.net/iau/info/MPOrbitFormat.html>.
pub fn parse_mpc_orbit_line(line: &str) -> Result<MpcOrbitEntry, MpcParseError> {
    if line.len() < MPC_ORBIT_LINE_MIN_LEN {
        return Err(MpcParseError::LineTooShort {
            len: line.len(),
            min: MPC_ORBIT_LINE_MIN_LEN,
        });
    }

    let packed_desig = line[0..7].trim().to_string();
    // Column ranges are 1-based inclusive per MPC export format → Rust `[start - 1 .. end)`.
    let absolute_mag = parse_field_f32(line, 7, 13, "H")?;
    let slope_param = parse_field_f32(line, 13, 19, "G")?;
    let epoch_jd = unpack_packed_epoch(extract_epoch_token(line)?)?;
    let mean_anomaly_deg = parse_field_f64(line, 26, 35, "M")?;
    let argument_perihelion_deg = parse_field_f64(line, 37, 46, "perihelion")?;
    let longitude_ascending_node_deg = parse_field_f64(line, 48, 57, "node")?;
    let inclination_deg = parse_field_f64(line, 59, 68, "inclination")?;
    let eccentricity = parse_field_f64(line, 69, 79, "eccentricity")?;
    let semi_major_axis_au = parse_field_f64(line, 91, 103, "semi-major axis")?;

    let name = if line.len() >= 194 {
        let readable = line[165..194].trim();
        if readable.is_empty() {
            None
        } else {
            Some(readable.to_string())
        }
    } else {
        None
    };

    let kind = MinorBodyKind::from_designation(name.as_deref().unwrap_or(&packed_desig));

    Ok(MpcOrbitEntry {
        designation: packed_desig,
        name,
        kind,
        absolute_mag,
        slope_param,
        elements: OrbitalElements {
            epoch_jd,
            semi_major_axis_au,
            eccentricity,
            inclination_deg,
            longitude_ascending_node_deg,
            argument_perihelion_deg,
            mean_anomaly_deg,
        },
    })
}

/// Parse MPCORB-style text (one orbit per line; `#` comments and blanks skipped).
pub fn parse_mpcorb_dat(text: &str) -> Vec<Result<MpcOrbitEntry, MpcParseError>> {
    text.lines()
        .filter(|line| {
            let trimmed = line.trim_start();
            !trimmed.is_empty() && !trimmed.starts_with('#')
        })
        .map(parse_mpc_orbit_line)
        .collect()
}

/// Decode MPC packed epoch field (cols 21–25, optional fractional day suffix).
pub fn unpack_packed_epoch(field: &str) -> Result<f64, MpcParseError> {
    let field = field.trim();
    if field.len() < 5 {
        return Err(MpcParseError::PackedEpoch(field.to_string()));
    }

    let (packed5, frac_str) = field.split_once('.').unwrap_or((&field[..5], ""));
    let packed = packed5.as_bytes();
    let century = match packed[0] {
        b'I' => 1800,
        b'J' => 1900,
        b'K' => 2000,
        b'L' => 2100,
        c => {
            return Err(MpcParseError::PackedEpoch(format!(
                "unknown century code '{c}'"
            )));
        }
    };
    let yy: u32 = packed5[1..3]
        .parse()
        .map_err(|e| MpcParseError::PackedEpoch(format!("year: {e}")))?;
    let year = century + yy;
    let month = packed_month(packed[3])?;
    let day = packed_day(packed[4])?;

    let mut jd = julian_date_utc(year, month, day);
    if !frac_str.is_empty() {
        let frac: f64 = frac_str
            .parse()
            .map_err(|e| MpcParseError::PackedEpoch(format!("fraction: {e}")))?;
        jd += frac;
    }
    Ok(jd)
}

fn packed_month(c: u8) -> Result<u32, MpcParseError> {
    let month = match c {
        b'1'..=b'9' => c - b'0',
        b'A' => 10,
        b'B' => 11,
        b'C' => 12,
        _ => {
            return Err(MpcParseError::PackedEpoch(format!(
                "invalid month code '{c}'"
            )));
        }
    };
    Ok(u32::from(month))
}

fn packed_day(c: u8) -> Result<u32, MpcParseError> {
    let day = match c {
        b'1'..=b'9' => u32::from(c - b'0'),
        b'A' => 10,
        b'B' => 11,
        b'C' => 12,
        b'D' => 13,
        b'E' => 14,
        b'F' => 15,
        b'G' => 16,
        b'H' => 17,
        b'I' => 18,
        b'J' => 19,
        b'K' => 20,
        b'L' => 21,
        b'M' => 22,
        b'N' => 23,
        b'O' => 24,
        b'P' => 25,
        b'Q' => 26,
        b'R' => 27,
        b'S' => 28,
        b'T' => 29,
        b'U' => 30,
        b'V' => 31,
        _ => {
            return Err(MpcParseError::PackedEpoch(format!(
                "invalid day code '{c}'"
            )));
        }
    };
    Ok(day)
}

/// Gregorian calendar date at 00:00 UTC → Julian Date (matches v1 `_julianDate` at midnight).
fn julian_date_utc(year: u32, month: u32, day: u32) -> f64 {
    let month_i = i32::try_from(month).unwrap_or(1);
    let year_i = i32::try_from(year).unwrap_or(2000);
    let day_i = i32::try_from(day).unwrap_or(1);
    let a = (14 - month_i) / 12;
    let y = year_i + 4800 - a;
    let m = month_i + 12 * a - 3;
    f64::from(day_i)
        + ((153 * m + 2) / 5) as f64
        + 365.0 * f64::from(y)
        + (y / 4) as f64
        - (y / 100) as f64
        + (y / 400) as f64
        - 32_045.0
        - 0.5
}

fn extract_epoch_token(line: &str) -> Result<&str, MpcParseError> {
    let tail = line.get(20..).unwrap_or("").trim_start();
    let end = tail
        .find(|c: char| c.is_ascii_whitespace())
        .unwrap_or(tail.len());
    let token = tail.get(..end).unwrap_or("").trim();
    if token.len() < 5 {
        return Err(MpcParseError::PackedEpoch(token.to_string()));
    }
    Ok(token)
}

fn parse_field_f32(
    line: &str,
    start: usize,
    end: usize,
    field: &'static str,
) -> Result<f32, MpcParseError> {
    let slice = line.get(start..end).unwrap_or("").trim();
    slice
        .parse::<f32>()
        .map_err(|e| MpcParseError::InvalidField {
            field,
            detail: e.to_string(),
        })
}

fn parse_field_f64(
    line: &str,
    start: usize,
    end: usize,
    field: &'static str,
) -> Result<f64, MpcParseError> {
    let slice = line.get(start..end).unwrap_or("").trim();
    slice
        .parse::<f64>()
        .map_err(|e| MpcParseError::InvalidField {
            field,
            detail: e.to_string(),
        })
}

fn string_at<'a>(
    table: &'a [u8],
    offset: u32,
    len: u16,
) -> Result<&'a str, MinorBodyParseError> {
    let start = offset as usize;
    let end = start + len as usize;
    if end > table.len() {
        return Err(MinorBodyParseError::StringRefOutOfRange);
    }
    std::str::from_utf8(&table[start..end]).map_err(|_| MinorBodyParseError::StringRefOutOfRange)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::astrometry::kepler::geocentric_equatorial_j2000;

    fn write_mpc_field(buf: &mut [u8], start_col: usize, end_col: usize, value: &str) {
        let start = start_col - 1;
        let width = end_col - start_col + 1;
        let bytes = value.as_bytes();
        let len = bytes.len().min(width);
        let offset = start + width.saturating_sub(len);
        buf[offset..offset + len].copy_from_slice(&bytes[bytes.len() - len..]);
    }

    fn ceres_mpc_line() -> String {
        let mut buf = vec![b' '; MPC_ORBIT_LINE_MIN_LEN];
        write_mpc_field(&mut buf, 1, 7, "    1");
        write_mpc_field(&mut buf, 9, 13, " 3.34");
        write_mpc_field(&mut buf, 15, 19, " 0.12");
        write_mpc_field(&mut buf, 21, 25, "K2411");
        write_mpc_field(&mut buf, 27, 35, "60.07000");
        write_mpc_field(&mut buf, 38, 46, " 73.59700");
        write_mpc_field(&mut buf, 49, 57, " 80.39400");
        write_mpc_field(&mut buf, 60, 68, " 10.59400");
        write_mpc_field(&mut buf, 71, 79, " 0.0760000");
        write_mpc_field(&mut buf, 81, 91, "  0.21458947");
        write_mpc_field(&mut buf, 93, 103, "  2.7670000");
        String::from_utf8(buf).expect("ascii line")
    }

    #[test]
    fn struct_sizes_match_spec() {
        assert_eq!(
            core::mem::size_of::<MinorBodyCatalogHeader>(),
            MINOR_BODY_HEADER_LEN
        );
        assert_eq!(core::mem::size_of::<MinorBodyRecord>(), MINOR_BODY_RECORD_LEN);
    }

    #[test]
    fn unpack_packed_epoch_jan_2024() {
        let jd = unpack_packed_epoch("K2411.0").expect("epoch");
        assert!((jd - 2_460_310.5).abs() < 1e-6);
    }

    #[test]
    fn parse_ceres_mpc_line() {
        let entry = parse_mpc_orbit_line(&ceres_mpc_line()).expect("ceres line");
        assert_eq!(entry.designation, "1");
        assert_eq!(entry.kind, MinorBodyKind::Asteroid);
        assert!((entry.absolute_mag - 3.34).abs() < 0.01);
        assert!((entry.elements.semi_major_axis_au - 2.767).abs() < 1e-3);
        assert!((entry.elements.epoch_jd - 2_460_310.5).abs() < 1e-6);
    }

    #[test]
    fn round_trip_encode_parse() {
        let entry = parse_mpc_orbit_line(&ceres_mpc_line()).unwrap();
        let bytes = encode_catalog(&[entry]);
        let parsed = parse_catalog(&bytes).expect("parse");
        assert_eq!(parsed.header.catalog_id, MPC_CATALOG_ID);
        assert_eq!(parsed.records.len(), 1);
        let rec = &parsed.records[0];
        assert!((rec.semi_major_axis_au - 2.767).abs() < 1e-3);
        assert_eq!(parsed.designation(rec).unwrap(), "1");
    }

    #[test]
    fn ceres_geocentric_matches_kepler_fixture() {
        let entry = parse_mpc_orbit_line(&ceres_mpc_line()).unwrap();
        let rec = encode_catalog(&[entry]);
        let parsed = parse_catalog(&rec).unwrap();
        let geo = parsed.records[0].geocentric_at(2_460_310.5);
        let expected = geocentric_equatorial_j2000(
            &OrbitalElements {
                epoch_jd: 2_460_310.5,
                semi_major_axis_au: 2.7670,
                eccentricity: 0.0760,
                inclination_deg: 10.594,
                longitude_ascending_node_deg: 80.394,
                argument_perihelion_deg: 73.597,
                mean_anomaly_deg: 60.070,
            },
            2_460_310.5,
        );
        assert!((geo.ra_hours - expected.ra_hours).abs() < 1e-4);
        assert!((geo.dec_deg - expected.dec_deg).abs() < 1e-3);
    }
}
