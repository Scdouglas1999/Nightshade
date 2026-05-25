//! Milky Way equirectangular intensity raster (design §8.2).
//!
//! Procedural galactic-band model ported from
//! `packages/nightshade_planetarium/lib/src/astronomy/milky_way_data.dart`.
//! Built offline into `mw-intensity-v1.bin` and sampled on the GPU in pass 2.

use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

use thiserror::Error;
use zerocopy::{AsBytes, FromBytes, FromZeroes};

/// Magic bytes identifying a planetarium MW intensity map (`"NSPLNT05"`).
pub const MILKY_WAY_MAGIC: &[u8; 8] = b"NSPLNT05";

/// Fixed header size (bytes).
pub const MILKY_WAY_HEADER_LEN: usize = 64;

/// Equirectangular width in pixels (RA 0°→360°).
pub const MILKY_WAY_WIDTH: u32 = 1024;

/// Equirectangular height in pixels (Dec +90°→−90°, top→bottom).
pub const MILKY_WAY_HEIGHT: u32 = 512;

/// On-disk format version for `mw-intensity-v1.bin`.
pub const MILKY_WAY_PACK_VERSION: u32 = 1;

/// `header.format` value: single-channel 8-bit intensity (maps to `R8Unorm`).
pub const MILKY_WAY_FORMAT_R8: u32 = 0;

/// Expected payload bytes (`width * height`).
pub const MILKY_WAY_PAYLOAD_LEN: usize =
    (MILKY_WAY_WIDTH as usize) * (MILKY_WAY_HEIGHT as usize);

/// Expected on-disk file size (header + payload).
pub const MILKY_WAY_FILE_LEN: usize = MILKY_WAY_HEADER_LEN + MILKY_WAY_PAYLOAD_LEN;

/// Relative path from repository root to the bundled desktop asset.
pub const MILKY_WAY_ASSET_REL_PATH: &str =
    "apps/desktop/assets/planetarium/mw-intensity-v1.bin";

/// Galactic north pole (J2000 equatorial), degrees.
pub const GALACTIC_NORTH_POLE_RA_DEG: f64 = 192.8595;
pub const GALACTIC_NORTH_POLE_DEC_DEG: f64 = 27.1283;

/// Galactic center (Sagittarius A*), degrees.
pub const GALACTIC_CENTER_RA_DEG: f64 = 266.4168;
pub const GALACTIC_CENTER_DEC_DEG: f64 = -29.0078;

/// Longitude of ascending node of the galactic plane on the celestial equator, degrees.
pub const GALACTIC_ASCENDING_NODE_DEG: f64 = 32.9319;

/// Minimum normalized intensity written to the raster (matches Dart `> 0.05` cutoff).
pub const MILKY_WAY_INTENSITY_FLOOR: f32 = 0.05;

/// Errors while building or parsing the MW intensity blob.
#[derive(Debug, Error)]
pub enum MilkyWayError {
    /// I/O failure.
    #[error("{context}: {source}")]
    Io {
        /// Human-readable stage.
        context: &'static str,
        /// Underlying error.
        #[source]
        source: std::io::Error,
    },
    /// Buffer shorter than the fixed header.
    #[error("Milky Way map truncated: need at least {MILKY_WAY_HEADER_LEN} bytes, got {actual}")]
    TruncatedHeader {
        /// Bytes available.
        actual: usize,
    },
    /// Magic does not match [`MILKY_WAY_MAGIC`].
    #[error("invalid Milky Way map magic (expected NSPLNT05)")]
    BadMagic,
    /// Header dimensions or format are not supported in v1.
    #[error("unsupported Milky Way map: {detail}")]
    UnsupportedHeader {
        /// Detail.
        detail: String,
    },
    /// Total byte length does not match header width/height.
    #[error("Milky Way map size mismatch: expected {expected} bytes, got {actual}")]
    SizeMismatch {
        /// Expected length from header.
        expected: usize,
        /// Actual buffer length.
        actual: usize,
    },
}

impl MilkyWayError {
    fn io(context: &'static str, source: std::io::Error) -> Self {
        Self::Io { context, source }
    }
}

/// 64-byte on-disk header for `mw-intensity-v1.bin`.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, FromZeroes, FromBytes, AsBytes)]
pub struct MilkyWayHeader {
    /// Must equal [`MILKY_WAY_MAGIC`].
    pub magic: [u8; 8],
    /// Pack format version ([`MILKY_WAY_PACK_VERSION`]).
    pub pack_version: u32,
    /// Equirectangular width ([`MILKY_WAY_WIDTH`]).
    pub width: u32,
    /// Equirectangular height ([`MILKY_WAY_HEIGHT`]).
    pub height: u32,
    /// Pixel format ([`MILKY_WAY_FORMAT_R8`]).
    pub format: u32,
    /// Reserved; must be zero in v1.
    pub _reserved: [u32; 10],
}

impl MilkyWayHeader {
    /// Whether [`magic`] matches [`MILKY_WAY_MAGIC`].
    #[must_use]
    pub fn magic_valid(&self) -> bool {
        &self.magic == MILKY_WAY_MAGIC
    }
}

/// Parsed MW intensity map (header + owned R8 payload).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MilkyWayMap {
    /// Validated header.
    pub header: MilkyWayHeader,
    /// Row-major R8 intensities (`height` rows × `width` columns).
    pub pixels: Vec<u8>,
}

impl MilkyWayMap {
    /// Full on-disk byte length for this map.
    #[must_use]
    pub fn byte_len(&self) -> usize {
        MILKY_WAY_HEADER_LEN + self.pixels.len()
    }

    /// Sample normalized intensity at integer pixel coordinates (clamped).
    #[must_use]
    pub fn sample_normalized(&self, x: u32, y: u32) -> f32 {
        let w = self.header.width;
        let h = self.header.height;
        if w == 0 || h == 0 {
            return 0.0;
        }
        let x = x.min(w - 1) as usize;
        let y = y.min(h - 1) as usize;
        f32::from(self.pixels[y * w as usize + x]) / 255.0
    }

    /// Sample at equatorial J2000 coordinates (degrees).
    #[must_use]
    pub fn intensity_at_equatorial_deg(&self, ra_deg: f64, dec_deg: f64) -> f32 {
        let w = self.header.width;
        let h = self.header.height;
        if w == 0 || h == 0 {
            return 0.0;
        }
        let u = ra_deg.rem_euclid(360.0) / 360.0;
        let v = (90.0 - dec_deg.clamp(-90.0, 90.0)) / 180.0;
        let x = (u * f64::from(w - 1)).round() as u32;
        let y = (v * f64::from(h - 1)).round() as u32;
        self.sample_normalized(x, y)
    }
}

/// Resolve the default bundled asset path under a repository root.
#[must_use]
pub fn default_mw_asset_path(repo_root: impl AsRef<Path>) -> PathBuf {
    repo_root.as_ref().join(MILKY_WAY_ASSET_REL_PATH)
}

/// Build the procedural MW map in memory (no I/O).
#[must_use]
pub fn build_milky_way_map() -> MilkyWayMap {
    let mut pixels = vec![0u8; MILKY_WAY_PAYLOAD_LEN];
    for y in 0..MILKY_WAY_HEIGHT {
        let dec_deg = 90.0 - (f64::from(y) + 0.5) * 180.0 / f64::from(MILKY_WAY_HEIGHT);
        for x in 0..MILKY_WAY_WIDTH {
            let ra_deg = (f64::from(x) + 0.5) * 360.0 / f64::from(MILKY_WAY_WIDTH);
            let (l_deg, b_deg) = equatorial_to_galactic_deg(ra_deg, dec_deg);
            let intensity = galactic_intensity(l_deg, b_deg);
            if intensity >= MILKY_WAY_INTENSITY_FLOOR {
                pixels[y as usize * MILKY_WAY_WIDTH as usize + x as usize] =
                    (intensity.clamp(0.0, 1.0) * 255.0).round() as u8;
            }
        }
    }

    MilkyWayMap {
        header: default_header(),
        pixels,
    }
}

/// Encode a [`MilkyWayMap`] to the on-disk blob layout.
#[must_use]
pub fn encode_milky_way_map(map: &MilkyWayMap) -> Vec<u8> {
    let mut out = Vec::with_capacity(map.byte_len());
    out.extend_from_slice(map.header.as_bytes());
    out.extend_from_slice(&map.pixels);
    out
}

/// Parse and validate a MW intensity blob.
pub fn parse_milky_way_map(bytes: &[u8]) -> Result<MilkyWayMap, MilkyWayError> {
    if bytes.len() < MILKY_WAY_HEADER_LEN {
        return Err(MilkyWayError::TruncatedHeader {
            actual: bytes.len(),
        });
    }

    let header = MilkyWayHeader::ref_from_prefix(bytes).ok_or(MilkyWayError::TruncatedHeader {
        actual: bytes.len(),
    })?;

    if !header.magic_valid() {
        return Err(MilkyWayError::BadMagic);
    }
    if header.pack_version != MILKY_WAY_PACK_VERSION {
        return Err(MilkyWayError::UnsupportedHeader {
            detail: format!("pack_version {}", header.pack_version),
        });
    }
    if header.width != MILKY_WAY_WIDTH || header.height != MILKY_WAY_HEIGHT {
        return Err(MilkyWayError::UnsupportedHeader {
            detail: format!("dimensions {}×{}", header.width, header.height),
        });
    }
    if header.format != MILKY_WAY_FORMAT_R8 {
        return Err(MilkyWayError::UnsupportedHeader {
            detail: format!("format {}", header.format),
        });
    }

    let expected = MILKY_WAY_HEADER_LEN + (header.width as usize) * (header.height as usize);
    if bytes.len() != expected {
        return Err(MilkyWayError::SizeMismatch {
            expected,
            actual: bytes.len(),
        });
    }

    let pixels = bytes[MILKY_WAY_HEADER_LEN..].to_vec();
    Ok(MilkyWayMap {
        header: *header,
        pixels,
    })
}

/// Memory-map or read a MW asset file and parse it.
pub fn load_milky_way_map(path: impl AsRef<Path>) -> Result<MilkyWayMap, MilkyWayError> {
    let bytes =
        std::fs::read(path.as_ref()).map_err(|e| MilkyWayError::io("read mw-intensity-v1.bin", e))?;
    parse_milky_way_map(&bytes)
}

/// Build the map and write `mw-intensity-v1.bin` under `output_path`.
pub fn build_milky_way_asset(output_path: impl AsRef<Path>) -> Result<MilkyWayBuildResult, MilkyWayError> {
    let output_path = output_path.as_ref().to_path_buf();
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent).map_err(|e| MilkyWayError::io("create mw asset parent dir", e))?;
    }

    let map = build_milky_way_map();
    let bytes = encode_milky_way_map(&map);
    debug_assert_eq!(bytes.len(), MILKY_WAY_FILE_LEN);

    let mut file = File::create(&output_path).map_err(|e| MilkyWayError::io("create mw asset", e))?;
    file.write_all(&bytes)
        .map_err(|e| MilkyWayError::io("write mw asset", e))?;

    Ok(MilkyWayBuildResult {
        output_path,
        byte_len: bytes.len(),
        nonzero_pixels: map.pixels.iter().filter(|&&b| b > 0).count(),
    })
}

/// Result of [`build_milky_way_asset`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MilkyWayBuildResult {
    /// Path written.
    pub output_path: PathBuf,
    /// Total bytes on disk.
    pub byte_len: usize,
    /// Pixels with intensity above the write floor.
    pub nonzero_pixels: usize,
}

/// Convert equatorial J2000 (degrees) to galactic `(l, b)` degrees.
#[must_use]
pub fn equatorial_to_galactic_deg(ra_deg: f64, dec_deg: f64) -> (f64, f64) {
    let ra = ra_deg.to_radians();
    let dec = dec_deg.to_radians();
    let ra_gnp = GALACTIC_NORTH_POLE_RA_DEG.to_radians();
    let dec_gnp = GALACTIC_NORTH_POLE_DEC_DEG.to_radians();
    let l0 = GALACTIC_ASCENDING_NODE_DEG.to_radians();

    let sin_b = dec_gnp.sin() * dec.sin() + dec_gnp.cos() * dec.cos() * (ra - ra_gnp).cos();
    let b = sin_b.clamp(-1.0, 1.0).asin();

    let y = dec.cos() * (ra - ra_gnp).sin();
    let x = dec_gnp.cos() * dec.sin() - dec_gnp.sin() * dec.cos() * (ra - ra_gnp).cos();
    let mut l = l0 - y.atan2(x);
    l = l.to_degrees().rem_euclid(360.0);

    (l, b.to_degrees())
}

/// Convert galactic `(l, b)` degrees to equatorial J2000 `(ra, dec)` degrees.
#[must_use]
pub fn galactic_to_equatorial_deg(l_deg: f64, b_deg: f64) -> (f64, f64) {
    let l = l_deg.to_radians();
    let b = b_deg.to_radians();
    let l0 = GALACTIC_ASCENDING_NODE_DEG.to_radians();
    let dec_gnp = GALACTIC_NORTH_POLE_DEC_DEG.to_radians();
    let ra_gnp = GALACTIC_NORTH_POLE_RA_DEG.to_radians();

    let sin_dec = dec_gnp.sin() * b.sin() + dec_gnp.cos() * b.cos() * (l0 - l).cos();
    let dec = sin_dec.clamp(-1.0, 1.0).asin();

    let y = b.cos() * (l0 - l).sin();
    let x = dec_gnp.cos() * b.sin() - dec_gnp.sin() * b.cos() * (l0 - l).cos();
    let mut ra = ra_gnp + y.atan2(x);
    ra = ra.to_degrees().rem_euclid(360.0);

    (ra, dec.to_degrees())
}

/// Normalized MW intensity at galactic longitude/latitude (degrees), ported from Dart.
#[must_use]
pub fn galactic_intensity(l_deg: f64, b_deg: f64) -> f32 {
    let abs_b = b_deg.abs();

    if abs_b < 8.0 {
        let mut intensity = 1.0 - (abs_b / 8.0) * 0.3;

        let dist_from_center = angular_distance_on_plane(l_deg, 0.0);
        if dist_from_center < 60.0 {
            intensity *= 1.0 + (1.0 - dist_from_center / 60.0) * 0.5;
        }

        let dist_from_cygnus = angular_distance_on_plane(l_deg, 80.0);
        if dist_from_cygnus < 30.0 {
            intensity *= 1.0 + (1.0 - dist_from_cygnus / 30.0) * 0.2;
        }

        if dist_from_center < 45.0 && abs_b < 3.0 {
            let patch_phase = (l_deg * 0.1).sin() * (b_deg * 0.5).cos();
            intensity *= 0.7 + patch_phase * 0.15;
        }

        return intensity.clamp(0.0, 1.0) as f32;
    }

    if abs_b < 20.0 {
        return ((1.0 - (abs_b - 8.0) / 12.0) * 0.7) as f32;
    }

    if abs_b < 30.0 {
        return ((1.0 - (abs_b - 20.0) / 10.0) * 0.15) as f32;
    }

    0.0
}

fn angular_distance_on_plane(l1: f64, l2: f64) -> f64 {
    let mut diff = (l1 - l2).abs();
    if diff > 180.0 {
        diff = 360.0 - diff;
    }
    diff
}

fn default_header() -> MilkyWayHeader {
    MilkyWayHeader {
        magic: *MILKY_WAY_MAGIC,
        pack_version: MILKY_WAY_PACK_VERSION,
        width: MILKY_WAY_WIDTH,
        height: MILKY_WAY_HEIGHT,
        format: MILKY_WAY_FORMAT_R8,
        _reserved: [0; 10],
    }
}
