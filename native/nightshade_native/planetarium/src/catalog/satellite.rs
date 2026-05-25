//! Satellite TLE catalog — mmap-friendly binary pack + SGP4 loader.
//!
//! Layout:
//! ```text
//! [SatelliteTleHeader — 64 B][SatelliteTleRecord × record_count — 160 B each]
//! ```
//!
//! Each record stores a NORAD two-line element set (69 + 69 bytes) and a short name.
//! Propagation delegates to [`crate::astrometry::sgp4_prop`].

use std::fs::File;
use std::path::Path;

use memmap2::Mmap;
use thiserror::Error;
use zerocopy::{AsBytes, FromBytes, FromZeroes};

use crate::astrometry::time::sgp4_prop::{
    SatellitePropagator, Sgp4PropError, TemeState,
};

/// Magic bytes identifying a planetarium TLE catalog (`"NSPLNT04"`).
pub const SATELLITE_TLE_CATALOG_MAGIC: &[u8; 8] = b"NSPLNT04";

/// Fixed header size (bytes).
pub const SATELLITE_TLE_HEADER_LEN: usize = 64;

/// Packed on-disk record size (bytes).
pub const SATELLITE_TLE_RECORD_LEN: usize = 160;

/// Pack-local catalog identifier for `satellites-tle`.
pub const SATELLITE_TLE_CATALOG_ID: u32 = 4;

/// On-disk format version for `satellites-tle-v1.bin`.
pub const SATELLITE_TLE_PACK_VERSION: u32 = 1;

/// NORAD TLE line width (characters).
pub const TLE_LINE_WIDTH: usize = 69;

/// Errors while parsing or mapping a satellite TLE catalog blob.
#[derive(Debug, Error)]
pub enum SatelliteTleParseError {
    /// Buffer shorter than the fixed header.
    #[error("satellite TLE catalog truncated: need at least {SATELLITE_TLE_HEADER_LEN} bytes, got {actual}")]
    TruncatedHeader {
        /// Bytes available.
        actual: usize,
    },
    /// Magic does not match [`SATELLITE_TLE_CATALOG_MAGIC`].
    #[error("invalid satellite TLE catalog magic (expected NSPLNT04)")]
    BadMagic,
    /// Total byte length does not match header `record_count`.
    #[error("satellite TLE catalog size mismatch: expected {expected} bytes, got {actual}")]
    SizeMismatch {
        /// Expected length from header.
        expected: usize,
        /// Actual buffer length.
        actual: usize,
    },
    /// `record_count` does not match records in the buffer.
    #[error("record_count {declared} does not match {actual} TLE records in blob")]
    RecordCountMismatch {
        /// Value in header.
        declared: u32,
        /// Records parsed from tail.
        actual: usize,
    },
    /// A stored TLE line is not valid UTF-8 or not exactly 69 characters when trimmed.
    #[error("invalid TLE line in record {index}: {detail}")]
    InvalidTleLine {
        /// Record index.
        index: usize,
        /// Detail.
        detail: String,
    },
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

impl SatelliteTleParseError {
    fn io(context: &'static str, source: std::io::Error) -> Self {
        Self::Io { context, source }
    }
}

/// Errors while parsing CelesTrak-style TLE text.
#[derive(Debug, Error)]
pub enum TleTextParseError {
    /// No valid element sets were found.
    #[error("no valid TLE element sets in text")]
    Empty,
    /// A line failed SGP4 parsing during ingest.
    #[error("TLE parse error for {name}: {detail}")]
    Element {
        /// Object name or catalog id.
        name: String,
        /// Underlying error.
        detail: String,
    },
}

/// 64-byte catalog header (`satellites-tle` pack).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, FromZeroes, FromBytes, AsBytes)]
pub struct SatelliteTleHeader {
    /// Must equal [`SATELLITE_TLE_CATALOG_MAGIC`].
    pub magic: [u8; 8],
    /// Pack-local catalog identifier ([`SATELLITE_TLE_CATALOG_ID`]).
    pub catalog_id: u32,
    /// Pack format version ([`SATELLITE_TLE_PACK_VERSION`]).
    pub pack_version: u32,
    /// Number of [`SatelliteTleRecord`] entries following this header.
    pub record_count: u32,
    /// Reserved; must be zero in v1 catalogs.
    pub reserved: [u8; 44],
}

impl SatelliteTleHeader {
    /// Build a header with magic and reserved fields zeroed.
    #[must_use]
    pub fn new(record_count: u32) -> Self {
        Self {
            magic: *SATELLITE_TLE_CATALOG_MAGIC,
            catalog_id: SATELLITE_TLE_CATALOG_ID,
            pack_version: SATELLITE_TLE_PACK_VERSION,
            record_count,
            reserved: [0; 44],
        }
    }

    /// Returns `true` when `magic` matches [`SATELLITE_TLE_CATALOG_MAGIC`].
    #[must_use]
    pub fn magic_valid(&self) -> bool {
        &self.magic == SATELLITE_TLE_CATALOG_MAGIC
    }
}

/// Packed on-disk TLE record (fixed-width lines for mmap).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, FromZeroes, FromBytes, AsBytes)]
pub struct SatelliteTleRecord {
    /// Line 1 (space-padded to 69 bytes).
    pub line1: [u8; TLE_LINE_WIDTH],
    /// Line 2 (space-padded to 69 bytes).
    pub line2: [u8; TLE_LINE_WIDTH],
    /// Short object name (UTF-8, zero-padded, max 14 bytes).
    pub name: [u8; 14],
    /// NORAD catalog number.
    pub norad_id: u32,
    /// Length of `name` in bytes.
    pub name_len: u8,
    /// Reserved (keeps record exactly 160 B).
    pub reserved: [u8; 3],
}

impl SatelliteTleRecord {
    /// Build a record from parsed TLE lines (lines are normalized to 69 characters).
    pub fn from_tle_lines(
        name: &str,
        line1: &str,
        line2: &str,
        norad_id: u32,
    ) -> Result<Self, SatelliteTleParseError> {
        Ok(Self {
            line1: pad_tle_line(line1, 0)?,
            line2: pad_tle_line(line2, 1)?,
            name: pad_name(name)?,
            norad_id,
            name_len: u8::try_from(name.len()).map_err(|_| SatelliteTleParseError::InvalidTleLine {
                index: 0,
                detail: "name longer than 14 bytes".into(),
            })?,
            reserved: [0; 3],
        })
    }

    /// Object name as UTF-8.
    pub fn object_name(&self) -> Result<&str, SatelliteTleParseError> {
        let len = self.name_len as usize;
        std::str::from_utf8(&self.name[..len])
            .map_err(|_| SatelliteTleParseError::InvalidTleLine {
                index: 0,
                detail: "invalid UTF-8 name".into(),
            })
    }

    /// TLE line 1 (trimmed, for SGP4).
    pub fn tle_line1(&self) -> Result<String, SatelliteTleParseError> {
        tle_line_to_string(&self.line1)
    }

    /// TLE line 2 (trimmed, for SGP4).
    pub fn tle_line2(&self) -> Result<String, SatelliteTleParseError> {
        tle_line_to_string(&self.line2)
    }

    /// Build an SGP4 propagator for this record.
    pub fn propagator(&self) -> Result<SatellitePropagator, Sgp4PropError> {
        let name = self.object_name().ok().map(str::to_string);
        SatellitePropagator::from_tle(
            name,
            &self.tle_line1().map_err(sgp4_line_err)?,
            &self.tle_line2().map_err(sgp4_line_err)?,
        )
    }

    /// Propagate to `minutes_since_epoch` from the TLE epoch.
    pub fn propagate_minutes_since_epoch(
        &self,
        minutes_since_epoch: f64,
    ) -> Result<TemeState, Sgp4PropError> {
        self.propagator()?.propagate_minutes_since_epoch(minutes_since_epoch)
    }
}

fn sgp4_line_err(err: SatelliteTleParseError) -> Sgp4PropError {
    Sgp4PropError::TleParse(err.to_string())
}

/// One parsed TLE element set from text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TleEntry {
    /// Object name (line 0 when present).
    pub name: String,
    /// NORAD catalog number (from line 1).
    pub norad_id: u32,
    /// TLE line 1.
    pub line1: String,
    /// TLE line 2.
    pub line2: String,
}

/// Borrowed view of a validated satellite TLE catalog blob.
#[derive(Debug, Clone, Copy)]
pub struct ParsedSatelliteTleCatalog<'a> {
    /// Catalog header (first 64 bytes).
    pub header: &'a SatelliteTleHeader,
    /// TLE records.
    pub records: &'a [SatelliteTleRecord],
}

/// Loaded TLE catalog with pre-built SGP4 propagators.
pub struct SatelliteTleCatalog {
    records: Vec<SatelliteTleRecord>,
    propagators: Vec<SatellitePropagator>,
}

impl SatelliteTleCatalog {
    /// Parse CelesTrak-style TLE text and build propagators (fails if any element is invalid).
    pub fn from_tle_text(text: &str) -> Result<Self, TleTextParseError> {
        let entries = parse_tle_text(text)?;
        let mut records = Vec::with_capacity(entries.len());
        let mut propagators = Vec::with_capacity(entries.len());
        for (index, entry) in entries.into_iter().enumerate() {
            let record = SatelliteTleRecord::from_tle_lines(
                &entry.name,
                &entry.line1,
                &entry.line2,
                entry.norad_id,
            )
            .map_err(|e| TleTextParseError::Element {
                name: entry.name.clone(),
                detail: e.to_string(),
            })?;
            let propagator = record.propagator().map_err(|e| TleTextParseError::Element {
                name: entry.name,
                detail: e.to_string(),
            })?;
            records.push(record);
            propagators.push(propagator);
            let _ = index;
        }
        Ok(Self {
            records,
            propagators,
        })
    }

    /// Load from a validated on-disk catalog blob.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, SatelliteTleParseError> {
        let parsed = parse_catalog(bytes)?;
        let mut propagators = Vec::with_capacity(parsed.records.len());
        for (index, record) in parsed.records.iter().enumerate() {
            propagators.push(record.propagator().map_err(|e| {
                SatelliteTleParseError::InvalidTleLine {
                    index,
                    detail: e.to_string(),
                }
            })?);
        }
        Ok(Self {
            records: parsed.records.to_vec(),
            propagators,
        })
    }

    /// Open a mmap catalog file under `path`.
    pub fn open(path: &Path) -> Result<Self, SatelliteTleParseError> {
        let mapped = MappedSatelliteTleCatalog::open(path)?;
        Self::from_bytes(&mapped.mmap)
    }

    /// Number of satellites in the catalog.
    #[must_use]
    pub fn len(&self) -> usize {
        self.records.len()
    }

    /// Returns `true` when the catalog has no entries.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    /// TLE records (on-disk layout).
    #[must_use]
    pub fn records(&self) -> &[SatelliteTleRecord] {
        &self.records
    }

    /// Propagate satellite `index` to `minutes_since_epoch`.
    pub fn propagate(
        &self,
        index: usize,
        minutes_since_epoch: f64,
    ) -> Result<TemeState, Sgp4PropError> {
        self.propagators
            .get(index)
            .ok_or_else(|| Sgp4PropError::Propagate(format!("satellite index {index} out of range")))?
            .propagate_minutes_since_epoch(minutes_since_epoch)
    }
}

/// Total on-disk size for a catalog with the given record count.
#[must_use]
pub fn catalog_byte_len(record_count: usize) -> usize {
    SATELLITE_TLE_HEADER_LEN + record_count * SATELLITE_TLE_RECORD_LEN
}

/// Serialize header and records into a single little-endian blob.
#[must_use]
pub fn encode_catalog(records: &[SatelliteTleRecord]) -> Vec<u8> {
    let header = SatelliteTleHeader::new(records.len() as u32);
    let mut out = Vec::with_capacity(catalog_byte_len(records.len()));
    out.extend_from_slice(header.as_bytes());
    for record in records {
        out.extend_from_slice(record.as_bytes());
    }
    out
}

/// Parse and validate a satellite TLE catalog from an in-memory byte slice.
pub fn parse_catalog(bytes: &[u8]) -> Result<ParsedSatelliteTleCatalog<'_>, SatelliteTleParseError> {
    if bytes.len() < SATELLITE_TLE_HEADER_LEN {
        return Err(SatelliteTleParseError::TruncatedHeader {
            actual: bytes.len(),
        });
    }

    let header = SatelliteTleHeader::ref_from_prefix(bytes).ok_or(
        SatelliteTleParseError::TruncatedHeader {
            actual: bytes.len(),
        },
    )?;
    if !header.magic_valid() {
        return Err(SatelliteTleParseError::BadMagic);
    }

    let record_count = header.record_count as usize;
    let expected = catalog_byte_len(record_count);
    if bytes.len() != expected {
        return Err(SatelliteTleParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        });
    }

    let records = SatelliteTleRecord::slice_from_prefix(
        &bytes[SATELLITE_TLE_HEADER_LEN..],
        record_count,
    )
    .map(|(s, _)| s)
    .ok_or(SatelliteTleParseError::SizeMismatch {
        expected,
        actual: bytes.len(),
    })?;

    if records.len() != record_count {
        return Err(SatelliteTleParseError::RecordCountMismatch {
            declared: header.record_count,
            actual: records.len(),
        });
    }

    for (index, record) in records.iter().enumerate() {
        record.tle_line1().map_err(|e| SatelliteTleParseError::InvalidTleLine {
            index,
            detail: e.to_string(),
        })?;
        record.tle_line2().map_err(|e| SatelliteTleParseError::InvalidTleLine {
            index,
            detail: e.to_string(),
        })?;
    }

    Ok(ParsedSatelliteTleCatalog { header, records })
}

/// Memory-mapped satellite TLE catalog (read-only).
pub struct MappedSatelliteTleCatalog {
    /// Mapped file bytes.
    pub mmap: Mmap,
}

impl MappedSatelliteTleCatalog {
    /// Open and validate `path`, then mmap the file.
    pub fn open(path: &Path) -> Result<Self, SatelliteTleParseError> {
        let file =
            File::open(path).map_err(|e| SatelliteTleParseError::io("open satellite TLE catalog", e))?;
        let mmap = unsafe { Mmap::map(&file) }
            .map_err(|e| SatelliteTleParseError::io("mmap satellite TLE catalog", e))?;
        parse_catalog(&mmap)?;
        Ok(Self { mmap })
    }

    /// Validated borrowed view of the mapped bytes.
    pub fn parsed(&self) -> Result<ParsedSatelliteTleCatalog<'_>, SatelliteTleParseError> {
        parse_catalog(&self.mmap)
    }
}

/// Parse CelesTrak-style TLE text (3-line or 2-line element sets).
pub fn parse_tle_text(text: &str) -> Result<Vec<TleEntry>, TleTextParseError> {
    let lines: Vec<&str> = text
        .lines()
        .map(str::trim_end)
        .filter(|l| !l.is_empty())
        .collect();

    let mut entries = Vec::new();
    let mut i = 0;
    while i < lines.len() {
        if i + 2 < lines.len() && is_tle_line1(lines[i + 1]) && is_tle_line2(lines[i + 2]) {
            let name = lines[i].trim().to_string();
            let line1 = normalize_tle_line(lines[i + 1])?;
            let line2 = normalize_tle_line(lines[i + 2])?;
            let norad_id = norad_id_from_line1(&line1)?;
            entries.push(TleEntry {
                name,
                norad_id,
                line1,
                line2,
            });
            i += 3;
        } else if i + 1 < lines.len() && is_tle_line1(lines[i]) && is_tle_line2(lines[i + 1]) {
            let line1 = normalize_tle_line(lines[i])?;
            let line2 = normalize_tle_line(lines[i + 1])?;
            let norad_id = norad_id_from_line1(&line1)?;
            entries.push(TleEntry {
                name: format!("SAT {norad_id}"),
                norad_id,
                line1,
                line2,
            });
            i += 2;
        } else {
            i += 1;
        }
    }

    if entries.is_empty() {
        return Err(TleTextParseError::Empty);
    }
    Ok(entries)
}

/// Build a catalog blob from TLE text (validates each element via SGP4).
pub fn encode_catalog_from_text(text: &str) -> Result<Vec<u8>, TleTextParseError> {
    let catalog = SatelliteTleCatalog::from_tle_text(text)?;
    Ok(encode_catalog(catalog.records()))
}

fn is_tle_line1(line: &str) -> bool {
    line.len() >= TLE_LINE_WIDTH && line.starts_with("1 ")
}

fn is_tle_line2(line: &str) -> bool {
    line.len() >= TLE_LINE_WIDTH && line.starts_with("2 ")
}

fn norad_id_from_line1(line1: &str) -> Result<u32, TleTextParseError> {
    let id_str = line1[2..7].trim();
    id_str
        .parse()
        .map_err(|e| TleTextParseError::Element {
            name: line1.to_string(),
            detail: format!("NORAD id: {e}"),
        })
}

fn normalize_tle_line(line: &str) -> Result<String, TleTextParseError> {
    if line.len() < TLE_LINE_WIDTH {
        return Err(TleTextParseError::Element {
            name: line.to_string(),
            detail: format!("line shorter than {TLE_LINE_WIDTH} characters"),
        });
    }
    Ok(line[..TLE_LINE_WIDTH].to_string())
}

fn pad_tle_line(line: &str, index: usize) -> Result<[u8; TLE_LINE_WIDTH], SatelliteTleParseError> {
    let normalized = normalize_tle_line(line).map_err(|e| SatelliteTleParseError::InvalidTleLine {
        index,
        detail: e.to_string(),
    })?;
    let mut buf = [b' '; TLE_LINE_WIDTH];
    buf[..normalized.len()].copy_from_slice(normalized.as_bytes());
    Ok(buf)
}

fn pad_name(name: &str) -> Result<[u8; 14], SatelliteTleParseError> {
    if name.len() > 14 {
        return Err(SatelliteTleParseError::InvalidTleLine {
            index: 0,
            detail: format!("name longer than 14 bytes: {name}"),
        });
    }
    let mut buf = [0u8; 14];
    buf[..name.len()].copy_from_slice(name.as_bytes());
    Ok(buf)
}

fn tle_line_to_string(line: &[u8; TLE_LINE_WIDTH]) -> Result<String, SatelliteTleParseError> {
    let trimmed = std::str::from_utf8(line)
        .map_err(|e| SatelliteTleParseError::InvalidTleLine {
            index: 0,
            detail: e.to_string(),
        })?
        .trim_end();
    if trimmed.len() < TLE_LINE_WIDTH - 1 {
        return Err(SatelliteTleParseError::InvalidTleLine {
            index: 0,
            detail: "TLE line too short after trim".into(),
        });
    }
    Ok(trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::astrometry::time::sgp4_prop::VERIFICATION_POSITION_TOLERANCE_KM;

    const VANGUARD_NAME: &str = "VANGUARD 1";
    const VANGUARD_LINE1: &str =
        "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753";
    const VANGUARD_LINE2: &str =
        "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667";

    fn vanguard_text() -> String {
        format!("{VANGUARD_NAME}\n{VANGUARD_LINE1}\n{VANGUARD_LINE2}\n")
    }

    #[test]
    fn struct_sizes_match_spec() {
        assert_eq!(
            core::mem::size_of::<SatelliteTleHeader>(),
            SATELLITE_TLE_HEADER_LEN
        );
        assert_eq!(core::mem::size_of::<SatelliteTleRecord>(), SATELLITE_TLE_RECORD_LEN);
    }

    #[test]
    fn parse_three_line_tle_text() {
        let entries = parse_tle_text(&vanguard_text()).expect("parse");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].name, VANGUARD_NAME);
        assert_eq!(entries[0].norad_id, 5);
    }

    #[test]
    fn round_trip_encode_parse_and_propagate() {
        let catalog = SatelliteTleCatalog::from_tle_text(&vanguard_text()).expect("catalog");
        let bytes = encode_catalog(catalog.records());
        let loaded = SatelliteTleCatalog::from_bytes(&bytes).expect("load bytes");
        let state = loaded.propagate(0, 0.0).expect("epoch");
        let radius = state.position_km.length();
        assert!((6_500.0..7_500.0).contains(&radius));
        let parsed = parse_catalog(&bytes).expect("parse");
        assert_eq!(parsed.header.catalog_id, SATELLITE_TLE_CATALOG_ID);
    }

    #[test]
    fn vanguard_matches_canonical_verification_position() {
        let catalog = SatelliteTleCatalog::from_tle_text(&vanguard_text()).unwrap();
        let state = catalog.propagate(0, 0.0).unwrap();
        let expected = [7022.46529266, -1400.08296755, 0.03995155];
        let err = (state.position_km - glam::DVec3::from_array(expected)).length();
        assert!(
            err < VERIFICATION_POSITION_TOLERANCE_KM,
            "position error {err} km"
        );
    }
}
