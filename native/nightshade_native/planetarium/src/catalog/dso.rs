//! OpenNGC DSO catalog — single mmap-friendly binary blob (design exception §6).
//!
//! Layout:
//! ```text
//! [DsoCatalogHeader — 64 B][DsoRecord × record_count — 48 B each]
//! ```
//!
//! Records are sorted brightest-first (unknown magnitude last). Field layout matches
//! design §5.4 `DsoInstance` (GPU DSO pipeline).

use std::fs::File;
use std::path::Path;

use memmap2::Mmap;
use thiserror::Error;
use zerocopy::{AsBytes, FromBytes, FromZeroes};

/// Magic bytes identifying a planetarium DSO catalog (`"NSPLNT02"`).
pub const DSO_CATALOG_MAGIC: &[u8; 8] = b"NSPLNT02";

/// Fixed header size (bytes).
pub const DSO_HEADER_LEN: usize = 64;

/// Packed on-disk record size (bytes).
pub const DSO_RECORD_LEN: usize = 48;

/// Pack-local catalog identifier for OpenNGC (`core` pack DSO table).
pub const OPENNGC_CATALOG_ID: u32 = 2;

/// On-disk format version for `dso-opengnc-v1.bin`.
pub const OPENNGC_PACK_VERSION: u32 = 1;

/// `DsoRecord::flags` — apparent magnitude is finite (not unknown).
pub const DSO_FLAG_HAS_MAG: u32 = 1 << 0;

/// `DsoRecord::flags` — object has a valid Messier number (1–110).
pub const DSO_FLAG_MESSIER: u32 = 1 << 1;

/// Errors while parsing or mapping a DSO catalog blob.
#[derive(Debug, Error)]
pub enum DsoParseError {
    /// Buffer shorter than the fixed header.
    #[error("DSO catalog truncated: need at least {DSO_HEADER_LEN} bytes, got {actual}")]
    TruncatedHeader {
        /// Bytes available.
        actual: usize,
    },
    /// Magic does not match [`DSO_CATALOG_MAGIC`].
    #[error("invalid DSO catalog magic (expected NSPLNT02)")]
    BadMagic,
    /// Total byte length does not match header `record_count`.
    #[error("DSO catalog size mismatch: expected {expected} bytes, got {actual}")]
    SizeMismatch {
        /// Expected length from header.
        expected: usize,
        /// Actual buffer length.
        actual: usize,
    },
    /// `record_count` does not match the number of records in the buffer.
    #[error("record_count {declared} does not match {actual} DSO records in blob")]
    RecordCountMismatch {
        /// Value in header.
        declared: u32,
        /// Records parsed from tail.
        actual: usize,
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

impl DsoParseError {
    fn io(context: &'static str, source: std::io::Error) -> Self {
        Self::Io { context, source }
    }
}

/// 64-byte catalog header (single-file OpenNGC pack).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, FromZeroes, FromBytes, AsBytes)]
pub struct DsoCatalogHeader {
    /// Must equal [`DSO_CATALOG_MAGIC`].
    pub magic: [u8; 8],
    /// Pack-local catalog identifier ([`OPENNGC_CATALOG_ID`]).
    pub catalog_id: u32,
    /// Pack format version ([`OPENNGC_PACK_VERSION`]).
    pub pack_version: u32,
    /// Number of [`DsoRecord`] entries following this header.
    pub record_count: u32,
    /// Faintest apparent magnitude included when the blob was built.
    pub mag_limit: f32,
    /// Padding (keeps header exactly 64 B).
    _pad: u32,
    /// Reserved; must be zero in v1 catalogs.
    pub reserved: [u8; 36],
}

impl DsoCatalogHeader {
    /// Build a header with magic and reserved fields zeroed.
    #[must_use]
    pub fn new(catalog_id: u32, pack_version: u32, record_count: u32, mag_limit: f32) -> Self {
        Self {
            magic: *DSO_CATALOG_MAGIC,
            catalog_id,
            pack_version,
            record_count,
            mag_limit,
            _pad: 0,
            reserved: [0; 36],
        }
    }

    /// Returns `true` when `magic` matches [`DSO_CATALOG_MAGIC`].
    #[must_use]
    pub fn magic_valid(&self) -> bool {
        &self.magic == DSO_CATALOG_MAGIC
    }
}

/// Packed on-disk DSO record (design §5.4 `DsoInstance` + catalog ids).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, FromZeroes, FromBytes, AsBytes)]
pub struct DsoRecord {
    /// Unit direction in ICRS (J2000).
    pub icrs_dir: [f32; 3],
    /// Major and minor axis size in arcminutes (`0` when unknown).
    pub size_arcmin: [f32; 2],
    /// Position angle in degrees (`NaN` when unknown).
    pub pa_deg: f32,
    /// Apparent magnitude used for culling (V preferred, else B; `NaN` if unknown).
    pub surface_mag: f32,
    /// Renderer type id ([`dso_type`] constants).
    pub type_id: u32,
    /// [`DSO_FLAG_HAS_MAG`] | [`DSO_FLAG_MESSIER`], …
    pub flags: u32,
    /// NGC catalog number (`0` when not an NGC id).
    pub ngc_id: u32,
    /// IC catalog number (`0` when not an IC id).
    pub ic_id: u32,
    /// Messier number 1–110 (`0` when none).
    pub messier_num: u32,
}

impl DsoRecord {
    /// Construct a record from equatorial coordinates (radians) and catalog fields.
    #[must_use]
    pub fn from_radec(
        ra_rad: f32,
        dec_rad: f32,
        size_major_arcmin: f32,
        size_minor_arcmin: f32,
        pa_deg: f32,
        surface_mag: f32,
        type_id: u32,
        flags: u32,
        ngc_id: u32,
        ic_id: u32,
        messier_num: u32,
    ) -> Self {
        let (sin_dec, cos_dec) = dec_rad.sin_cos();
        let (sin_ra, cos_ra) = ra_rad.sin_cos();
        Self {
            icrs_dir: [cos_dec * cos_ra, cos_dec * sin_ra, sin_dec],
            size_arcmin: [size_major_arcmin, size_minor_arcmin],
            pa_deg,
            surface_mag,
            type_id,
            flags,
            ngc_id,
            ic_id,
            messier_num,
        }
    }
}

/// OpenNGC type code → renderer `type_id` (design §5.4).
pub mod dso_type {
    /// Galaxy (incl. pairs/groups mapped to galaxy procedural).
    pub const GALAXY: u32 = 0;
    /// Open cluster.
    pub const OPEN_CLUSTER: u32 = 1;
    /// Globular cluster.
    pub const GLOBULAR_CLUSTER: u32 = 2;
    /// Generic / emission / reflection / HII / dark nebula.
    pub const NEBULA: u32 = 3;
    /// Planetary nebula.
    pub const PLANETARY_NEBULA: u32 = 4;
    /// Supernova remnant.
    pub const SUPERNOVA_REMNANT: u32 = 5;
    /// Stellar (misclassified DSO, double, association, …).
    pub const STELLAR: u32 = 6;
    /// Cluster with nebulosity.
    pub const CLUSTER_NEBULA: u32 = 7;
    /// Nova.
    pub const NOVA: u32 = 8;
    /// Asterism / star cloud / other.
    pub const OTHER: u32 = 9;
}

/// Map an OpenNGC `Type` column value to [`dso_type`] id.
#[must_use]
pub fn type_id_from_opengnc(type_code: &str) -> u32 {
    match type_code {
        "OCl" => dso_type::OPEN_CLUSTER,
        "GCl" => dso_type::GLOBULAR_CLUSTER,
        "Cl+N" => dso_type::CLUSTER_NEBULA,
        "G" | "GPair" | "GTrpl" | "GGroup" => dso_type::GALAXY,
        "PN" => dso_type::PLANETARY_NEBULA,
        "HII" | "DrkN" | "EmN" | "Neb" | "RfN" => dso_type::NEBULA,
        "SNR" => dso_type::SUPERNOVA_REMNANT,
        "Nova" => dso_type::NOVA,
        "*" | "**" | "*Ass" => dso_type::STELLAR,
        _ => dso_type::OTHER,
    }
}

/// Borrowed view of a validated DSO catalog blob.
#[derive(Debug, Clone, Copy)]
pub struct ParsedDsoCatalog<'a> {
    /// Catalog header (first 64 bytes).
    pub header: &'a DsoCatalogHeader,
    /// DSO records (brightest-first).
    pub records: &'a [DsoRecord],
}

/// Total on-disk size for a catalog with the given record count.
#[must_use]
pub fn catalog_byte_len(record_count: usize) -> usize {
    DSO_HEADER_LEN + record_count * DSO_RECORD_LEN
}

/// Serialize header and records into a single little-endian blob.
#[must_use]
pub fn encode_catalog(header: &DsoCatalogHeader, records: &[DsoRecord]) -> Vec<u8> {
    assert_eq!(
        header.record_count as usize,
        records.len(),
        "record_count must match records.len()"
    );

    let mut out = Vec::with_capacity(catalog_byte_len(records.len()));
    out.extend_from_slice(header.as_bytes());
    for record in records {
        out.extend_from_slice(record.as_bytes());
    }
    out
}

/// Parse and validate a DSO catalog from an in-memory byte slice.
pub fn parse_catalog(bytes: &[u8]) -> Result<ParsedDsoCatalog<'_>, DsoParseError> {
    if bytes.len() < DSO_HEADER_LEN {
        return Err(DsoParseError::TruncatedHeader {
            actual: bytes.len(),
        });
    }

    let header =
        DsoCatalogHeader::ref_from_prefix(bytes).ok_or(DsoParseError::TruncatedHeader {
            actual: bytes.len(),
        })?;
    if !header.magic_valid() {
        return Err(DsoParseError::BadMagic);
    }

    let record_count = header.record_count as usize;
    let expected = catalog_byte_len(record_count);
    if bytes.len() != expected {
        return Err(DsoParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        });
    }

    let records = DsoRecord::slice_from_prefix(&bytes[DSO_HEADER_LEN..], record_count)
        .map(|(s, _)| s)
        .ok_or(DsoParseError::SizeMismatch {
            expected,
            actual: bytes.len(),
        })?;

    if records.len() != record_count {
        return Err(DsoParseError::RecordCountMismatch {
            declared: header.record_count,
            actual: records.len(),
        });
    }

    Ok(ParsedDsoCatalog { header, records })
}

/// Memory-mapped OpenNGC binary catalog (read-only).
pub struct MappedDsoCatalog {
    mmap: Mmap,
}

impl MappedDsoCatalog {
    /// Open and validate `path`, then mmap the file.
    pub fn open(path: &Path) -> Result<Self, DsoParseError> {
        let file = File::open(path).map_err(|e| DsoParseError::io("open DSO catalog", e))?;
        let mmap =
            unsafe { Mmap::map(&file) }.map_err(|e| DsoParseError::io("mmap DSO catalog", e))?;
        parse_catalog(&mmap)?;
        Ok(Self { mmap })
    }

    /// Validated borrowed view of the mapped bytes.
    pub fn parsed(&self) -> Result<ParsedDsoCatalog<'_>, DsoParseError> {
        parse_catalog(&self.mmap)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn struct_sizes_match_spec() {
        assert_eq!(core::mem::size_of::<DsoCatalogHeader>(), DSO_HEADER_LEN);
        assert_eq!(core::mem::size_of::<DsoRecord>(), DSO_RECORD_LEN);
    }

    #[test]
    fn round_trip_encode_parse() {
        let records = vec![DsoRecord::from_radec(
            0.1,
            0.2,
            10.0,
            5.0,
            35.0,
            3.4,
            dso_type::GALAXY,
            DSO_FLAG_HAS_MAG,
            224,
            0,
            31,
        )];
        let header = DsoCatalogHeader::new(
            OPENNGC_CATALOG_ID,
            OPENNGC_PACK_VERSION,
            records.len() as u32,
            20.0,
        );
        let bytes = encode_catalog(&header, &records);
        let parsed = parse_catalog(&bytes).expect("parse");
        assert_eq!(parsed.header.catalog_id, OPENNGC_CATALOG_ID);
        assert_eq!(parsed.records.len(), 1);
        assert_eq!(parsed.records[0].ngc_id, 224);
        assert_eq!(parsed.records[0].messier_num, 31);
    }
}
