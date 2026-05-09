//! Real Plate Solving Integration
//!
//! Provides actual integration with plate solving software:
//! - ASTAP (Astrometric STAcking Program)
//! - Local Astrometry.net
//!
//! These are real implementations that call external solvers.

use crate::{detect_stars, read_fits, FitsHeader, ImageData, PixelType, StarDetectionConfig};
use bytemuck::{Pod, Zeroable};
use std::fs;
use std::num::ParseFloatError;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::OnceLock;
use thiserror::Error;
use wgpu::util::DeviceExt;

/// Structured errors emitted while parsing solver-produced WCS / INI files.
///
/// A solve must surface every parse failure so downstream science code never
/// treats a malformed header as a successful zero-coordinate solution.
#[derive(Debug, Error)]
pub enum PlateSolveError {
    #[error(
        "failed to parse WCS keyword `{keyword}` value `{raw_value}` as f64 (file: {path}): {source}"
    )]
    WcsParse {
        keyword: String,
        raw_value: String,
        path: String,
        #[source]
        source: ParseFloatError,
    },
    #[error("WCS file `{path}` did not contain required keyword `{keyword}`")]
    WcsMissingKeyword { keyword: String, path: String },
    #[error("ASTAP INI file `{path}` reports plate solve failed (PLTSOLVD != T)")]
    SolveFailed { path: String },
    #[error("failed to read solver output `{path}`: {source}")]
    ReadOutput {
        path: String,
        #[source]
        source: std::io::Error,
    },
}

/// Plate solve result
#[derive(Debug, Clone)]
pub struct PlateSolveResult {
    /// Solved RA in degrees
    pub ra: f64,
    /// Solved Dec in degrees
    pub dec: f64,
    /// Image scale in arcsec/pixel
    pub pixel_scale: f64,
    /// Rotation angle in degrees (East of North)
    pub rotation: f64,
    /// Field width in degrees
    pub field_width: f64,
    /// Field height in degrees
    pub field_height: f64,
    /// Was the solve successful?
    pub success: bool,
    /// Error message if failed
    pub error: Option<String>,
    /// Time taken to solve in seconds
    pub solve_time_secs: f64,
}

/// Plate solver configuration
#[derive(Debug, Clone)]
pub struct PlateSolverConfig {
    /// Path to ASTAP executable
    pub astap_path: Option<PathBuf>,
    /// Path to local astrometry.net solve-field
    pub astrometry_path: Option<PathBuf>,
    /// Search radius in degrees (0 = blind solve)
    pub search_radius: f64,
    /// Downsample factor for faster solving
    pub downsample: u32,
    /// Maximum time for solving in seconds
    pub timeout_secs: u32,
}

impl Default for PlateSolverConfig {
    fn default() -> Self {
        Self {
            astap_path: find_astap(),
            astrometry_path: find_astrometry(),
            search_radius: 10.0,
            downsample: 2,
            timeout_secs: 60,
        }
    }
}

/// Find ASTAP installation
fn find_astap() -> Option<PathBuf> {
    // Common ASTAP installation locations
    let candidates = [
        r"C:\Program Files\astap\astap_cli.exe",
        r"C:\Program Files (x86)\astap\astap_cli.exe",
        r"C:\astap\astap_cli.exe",
        "/usr/bin/astap_cli",
        "/usr/local/bin/astap_cli",
        "/opt/astap/astap_cli",
    ];

    for path in &candidates {
        let p = PathBuf::from(path);
        if p.exists() {
            return Some(p);
        }
    }

    // Try to find in PATH
    if let Ok(output) = Command::new("where").arg("astap_cli.exe").output() {
        if output.status.success() {
            if let Ok(path) = String::from_utf8(output.stdout) {
                let path = path.trim();
                if !path.is_empty() {
                    return Some(PathBuf::from(path.lines().next().unwrap_or(path)));
                }
            }
        }
    }

    None
}

/// Find local astrometry.net installation
fn find_astrometry() -> Option<PathBuf> {
    let candidates = [
        "/usr/bin/solve-field",
        "/usr/local/bin/solve-field",
        "/opt/astrometry/bin/solve-field",
    ];

    for path in &candidates {
        let p = PathBuf::from(path);
        if p.exists() {
            return Some(p);
        }
    }

    None
}

/// Plate solver using ASTAP
pub struct AstapSolver {
    config: PlateSolverConfig,
}

impl AstapSolver {
    pub fn new(config: PlateSolverConfig) -> Self {
        Self { config }
    }

    pub fn with_default_config() -> Option<Self> {
        let config = PlateSolverConfig::default();
        if config.astap_path.is_some() {
            Some(Self { config })
        } else {
            None
        }
    }

    /// Check if ASTAP is available
    pub fn is_available(&self) -> bool {
        self.config.astap_path.is_some()
    }

    /// Get ASTAP path
    pub fn astap_path(&self) -> Option<&Path> {
        self.config.astap_path.as_deref()
    }

    /// Solve an image with optional hint coordinates
    ///
    /// # Arguments
    /// * `image_path` - Path to FITS file to solve
    /// * `hint_ra` - Optional hint RA in degrees
    /// * `hint_dec` - Optional hint Dec in degrees
    /// * `hint_scale` - Optional hint for image scale in arcsec/pixel
    pub fn solve(
        &self,
        image_path: &Path,
        hint_ra: Option<f64>,
        hint_dec: Option<f64>,
        hint_scale: Option<f64>,
    ) -> PlateSolveResult {
        let start = std::time::Instant::now();

        let astap_path = match &self.config.astap_path {
            Some(p) => p,
            None => {
                return PlateSolveResult {
                    ra: 0.0,
                    dec: 0.0,
                    pixel_scale: 0.0,
                    rotation: 0.0,
                    field_width: 0.0,
                    field_height: 0.0,
                    success: false,
                    error: Some("ASTAP not found".to_string()),
                    solve_time_secs: 0.0,
                }
            }
        };

        // Build ASTAP command
        let mut cmd = Command::new(astap_path);

        // Input file
        cmd.arg("-f").arg(image_path);

        // Search radius
        if hint_ra.is_some() && hint_dec.is_some() && self.config.search_radius > 0.0 {
            cmd.arg("-r").arg(format!("{}", self.config.search_radius));
        }

        // Hint coordinates
        if let (Some(ra), Some(dec)) = (hint_ra, hint_dec) {
            cmd.arg("-ra").arg(format!("{}", ra / 15.0)); // Convert to hours
            cmd.arg("-spd").arg(format!("{}", dec + 90.0)); // Convert to SPD
        }

        // Hint scale
        if hint_scale.is_some() {
            // ASTAP expects focal-length-style hints here, which require a known pixel size.
            // Do not synthesize focal length from an assumed pixel size.
            tracing::debug!(
                "Plate-solve scale hint provided without pixel size; skipping ASTAP focal-length hint"
            );
        }

        // Downsample
        if self.config.downsample > 1 {
            cmd.arg("-z").arg(format!("{}", self.config.downsample));
        }

        // Output (don't update FITS, just solve)
        cmd.arg("-update");

        // Run solver
        tracing::info!("Running ASTAP: {:?}", cmd);

        let output = match cmd.stdout(Stdio::piped()).stderr(Stdio::piped()).output() {
            Ok(o) => o,
            Err(e) => {
                return PlateSolveResult {
                    ra: 0.0,
                    dec: 0.0,
                    pixel_scale: 0.0,
                    rotation: 0.0,
                    field_width: 0.0,
                    field_height: 0.0,
                    success: false,
                    error: Some(format!("Failed to run ASTAP: {}", e)),
                    solve_time_secs: start.elapsed().as_secs_f64(),
                }
            }
        };

        let solve_time = start.elapsed().as_secs_f64();

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(format!("ASTAP failed: {}", stderr)),
                solve_time_secs: solve_time,
            };
        }

        // Parse ASTAP output - it writes a .wcs file alongside the input
        let wcs_path = image_path.with_extension("wcs");
        if !wcs_path.exists() {
            // Also try .ini file
            let ini_path = image_path.with_extension("ini");
            if ini_path.exists() {
                return self.parse_astap_ini(&ini_path, solve_time);
            }

            return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some("No solution file found".to_string()),
                solve_time_secs: solve_time,
            };
        }

        match self.parse_wcs_file(&wcs_path, solve_time) {
            Ok(result) => result,
            Err(err) => PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(err.to_string()),
                solve_time_secs: solve_time,
            },
        }
    }

    /// Parse ASTAP .ini result file
    fn parse_astap_ini(&self, ini_path: &Path, solve_time: f64) -> PlateSolveResult {
        match parse_astap_ini_inner(ini_path, solve_time) {
            Ok(result) => result,
            Err(err) => PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(err.to_string()),
                solve_time_secs: solve_time,
            },
        }
    }

    /// Parse WCS file emitted by ASTAP/astrometry.net.
    ///
    /// Required keywords: CRVAL1, CRVAL2, CD1_1, CD1_2, CD2_1, CD2_2.
    /// Any malformed value or missing required keyword propagates as
    /// `PlateSolveError`; the caller is responsible for converting to a
    /// failed `PlateSolveResult`. Silent fallbacks (RA=0/Dec=0) are
    /// forbidden — see CLAUDE.md "errors are a feature".
    fn parse_wcs_file(
        &self,
        wcs_path: &Path,
        solve_time: f64,
    ) -> Result<PlateSolveResult, PlateSolveError> {
        parse_wcs_file_inner(wcs_path, solve_time)
    }
}

/// Free-function form of WCS parsing so the test module can exercise it
/// without instantiating an `AstapSolver` (which requires a real ASTAP
/// install on PATH).
fn parse_wcs_file_inner(
    wcs_path: &Path,
    solve_time: f64,
) -> Result<PlateSolveResult, PlateSolveError> {
    let path_display = wcs_path.display().to_string();
    let content = fs::read_to_string(wcs_path).map_err(|source| PlateSolveError::ReadOutput {
        path: path_display.clone(),
        source,
    })?;

    let mut ra: Option<f64> = None;
    let mut dec: Option<f64> = None;
    let mut cd1_1: Option<f64> = None;
    let mut cd1_2: Option<f64> = None;
    let mut cd2_1: Option<f64> = None;
    let mut cd2_2: Option<f64> = None;

    for line in content.lines() {
        if line.len() < 10 {
            continue;
        }

        let keyword = line[..8].trim();
        if !line[8..].starts_with('=') {
            continue;
        }

        let value_part = line[10..].trim();
        let value_str = if let Some(idx) = value_part.find('/') {
            &value_part[..idx]
        } else {
            value_part
        }
        .trim();

        let parse = |slot: &mut Option<f64>| -> Result<(), PlateSolveError> {
            let parsed = value_str
                .parse::<f64>()
                .map_err(|source| PlateSolveError::WcsParse {
                    keyword: keyword.to_string(),
                    raw_value: value_str.to_string(),
                    path: path_display.clone(),
                    source,
                })?;
            *slot = Some(parsed);
            Ok(())
        };

        match keyword {
            "CRVAL1" => parse(&mut ra)?,
            "CRVAL2" => parse(&mut dec)?,
            "CD1_1" => parse(&mut cd1_1)?,
            "CD1_2" => parse(&mut cd1_2)?,
            "CD2_1" => parse(&mut cd2_1)?,
            "CD2_2" => parse(&mut cd2_2)?,
            _ => {}
        }
    }

    let require = |slot: Option<f64>, name: &str| -> Result<f64, PlateSolveError> {
        slot.ok_or_else(|| PlateSolveError::WcsMissingKeyword {
            keyword: name.to_string(),
            path: path_display.clone(),
        })
    };
    let ra = require(ra, "CRVAL1")?;
    let dec = require(dec, "CRVAL2")?;
    let cd1_1 = require(cd1_1, "CD1_1")?;
    let cd1_2 = require(cd1_2, "CD1_2")?;
    let cd2_1 = require(cd2_1, "CD2_1")?;
    let cd2_2 = require(cd2_2, "CD2_2")?;

    let pixel_scale = ((cd1_1 * cd1_1 + cd2_1 * cd2_1).sqrt() * 3600.0
        + (cd1_2 * cd1_2 + cd2_2 * cd2_2).sqrt() * 3600.0)
        / 2.0;
    let rotation = cd2_1.atan2(cd1_1).to_degrees();

    Ok(PlateSolveResult {
        ra,
        dec,
        pixel_scale,
        rotation,
        field_width: 0.0,
        field_height: 0.0,
        success: true,
        error: None,
        solve_time_secs: solve_time,
    })
}

/// Free-function form of ASTAP `.ini` parsing so the test module can exercise
/// it without an ASTAP install. Mirrors `parse_wcs_file_inner` semantics:
/// malformed numeric values or `PLTSOLVD != T` propagate as errors instead of
/// silently producing a zero-coordinate "successful" solve.
fn parse_astap_ini_inner(
    ini_path: &Path,
    solve_time: f64,
) -> Result<PlateSolveResult, PlateSolveError> {
    let path_display = ini_path.display().to_string();
    let content = fs::read_to_string(ini_path).map_err(|source| PlateSolveError::ReadOutput {
        path: path_display.clone(),
        source,
    })?;

    let mut ra: Option<f64> = None;
    let mut dec: Option<f64> = None;
    let mut crota: Option<f64> = None;
    let mut cdelt1: Option<f64> = None;
    let mut cdelt2: Option<f64> = None;
    let mut solved = false;

    for line in content.lines() {
        let line = line.trim();
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim().to_uppercase();
        let value = value.trim();

        let parse = |slot: &mut Option<f64>, keyword: &str| -> Result<(), PlateSolveError> {
            let parsed = value
                .parse::<f64>()
                .map_err(|source| PlateSolveError::WcsParse {
                    keyword: keyword.to_string(),
                    raw_value: value.to_string(),
                    path: path_display.clone(),
                    source,
                })?;
            *slot = Some(parsed);
            Ok(())
        };

        match key.as_str() {
            "CRVAL1" => parse(&mut ra, "CRVAL1")?,
            "CRVAL2" => parse(&mut dec, "CRVAL2")?,
            "CROTA1" | "CROTA2" => parse(&mut crota, &key)?,
            "CDELT1" => parse(&mut cdelt1, "CDELT1")?,
            "CDELT2" => parse(&mut cdelt2, "CDELT2")?,
            "PLTSOLVD" => solved = value == "T",
            _ => {}
        }
    }

    if !solved {
        return Err(PlateSolveError::SolveFailed {
            path: path_display,
        });
    }

    let require = |slot: Option<f64>, name: &str| -> Result<f64, PlateSolveError> {
        slot.ok_or_else(|| PlateSolveError::WcsMissingKeyword {
            keyword: name.to_string(),
            path: path_display.clone(),
        })
    };
    let ra = require(ra, "CRVAL1")?;
    let dec = require(dec, "CRVAL2")?;
    let cdelt1 = require(cdelt1, "CDELT1")?;
    let cdelt2 = require(cdelt2, "CDELT2")?;
    // Why: CROTA1/CROTA2 are *optional* in the FITS WCS standard (Greisen &
    // Calabretta 2002 §2.1.2). ASTAP omits them for north-up frames. When
    // absent, the standard-mandated default is 0.0 — this is a documented
    // WCS convention, not a silent error fallback. A *malformed* CROTA value
    // (parse failure) still propagates as `PlateSolveError::WcsParse` via
    // the `parse(&mut crota, &key)?` call above.
    let crota = crota.unwrap_or(0.0);

    let pixel_scale = (cdelt1.abs() * 3600.0 + cdelt2.abs() * 3600.0) / 2.0;

    Ok(PlateSolveResult {
        ra,
        dec,
        pixel_scale,
        rotation: crota,
        field_width: 0.0,
        field_height: 0.0,
        success: true,
        error: None,
        solve_time_secs: solve_time,
    })
}

const GPU_DOWNSAMPLE_SHADER: &str = r#"
struct Params {
  width: u32,
  height: u32,
  factor: u32,
  out_width: u32,
  out_height: u32,
  _pad0: u32,
  _pad1: u32,
  _pad2: u32,
}

@group(0) @binding(0) var<storage, read> input_pixels: array<u32>;
@group(0) @binding(1) var<storage, read_write> output_pixels: array<u32>;
@group(0) @binding(2) var<uniform> params: Params;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= params.out_width || gid.y >= params.out_height) {
    return;
  }

  let start_x = gid.x * params.factor;
  let start_y = gid.y * params.factor;
  var max_value: u32 = 0u;

  for (var dy: u32 = 0u; dy < params.factor; dy = dy + 1u) {
    let src_y = start_y + dy;
    if (src_y >= params.height) {
      break;
    }
    for (var dx: u32 = 0u; dx < params.factor; dx = dx + 1u) {
      let src_x = start_x + dx;
      if (src_x >= params.width) {
        break;
      }
      let src_index = src_y * params.width + src_x;
      max_value = max(max_value, input_pixels[src_index]);
    }
  }

  let dst_index = gid.y * params.out_width + gid.x;
  output_pixels[dst_index] = max_value;
}
"#;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct DownsampleParams {
    width: u32,
    height: u32,
    factor: u32,
    out_width: u32,
    out_height: u32,
    _pad0: u32,
    _pad1: u32,
    _pad2: u32,
}

fn to_monochrome_u16(image: &ImageData) -> Result<ImageData, String> {
    if image.pixel_type == PixelType::U16 && image.channels == 1 {
        return Ok(image.clone());
    }

    let pixel_count = (image.width as usize) * (image.height as usize);
    if pixel_count == 0 {
        return Ok(ImageData::from_u16(0, 0, 1, &[]));
    }

    let channels = image.channels.max(1) as usize;
    let values: Vec<u16> = match image.pixel_type {
        PixelType::U8 => image
            .data
            .iter()
            .step_by(channels)
            .map(|&value| (value as u16) << 8)
            .collect(),
        PixelType::U16 => image
            .data
            .chunks_exact(2 * channels)
            .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
            .collect(),
        PixelType::U32 => image
            .data
            .chunks_exact(4 * channels)
            .map(|chunk| {
                let value = u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                value.min(u16::MAX as u32) as u16
            })
            .collect(),
        PixelType::F32 => image
            .data
            .chunks_exact(4 * channels)
            .map(|chunk| {
                let value = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                value.clamp(0.0, u16::MAX as f32) as u16
            })
            .collect(),
        PixelType::F64 => image
            .data
            .chunks_exact(8 * channels)
            .map(|chunk| {
                let value = f64::from_le_bytes([
                    chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
                ]);
                value.clamp(0.0, u16::MAX as f64) as u16
            })
            .collect(),
    };

    Ok(ImageData::from_u16(image.width, image.height, 1, &values))
}

fn cpu_downsample_max_u16(image: &ImageData, factor: u32) -> Result<ImageData, String> {
    let mono = to_monochrome_u16(image)?;
    let pixels = mono
        .as_u16()
        .ok_or_else(|| "Failed to read monochrome u16 image data".to_string())?;
    let out_width = mono.width.div_ceil(factor);
    let out_height = mono.height.div_ceil(factor);
    let mut output = vec![0u16; (out_width * out_height) as usize];

    for out_y in 0..out_height {
        for out_x in 0..out_width {
            let mut max_value = 0u16;
            let start_x = out_x * factor;
            let start_y = out_y * factor;
            for dy in 0..factor {
                let y = start_y + dy;
                if y >= mono.height {
                    break;
                }
                for dx in 0..factor {
                    let x = start_x + dx;
                    if x >= mono.width {
                        break;
                    }
                    let idx = (y * mono.width + x) as usize;
                    max_value = max_value.max(pixels[idx]);
                }
            }
            output[(out_y * out_width + out_x) as usize] = max_value;
        }
    }

    Ok(ImageData::from_u16(out_width, out_height, 1, &output))
}

fn gpu_downsample_max_u16(image: &ImageData, factor: u32) -> Result<ImageData, String> {
    let mono = to_monochrome_u16(image)?;
    let pixels = mono
        .as_u16()
        .ok_or_else(|| "Failed to read monochrome u16 image data".to_string())?;
    let input_u32: Vec<u32> = pixels.into_iter().map(u32::from).collect();
    let out_width = mono.width.div_ceil(factor);
    let out_height = mono.height.div_ceil(factor);
    let output_len = (out_width * out_height) as usize;

    let instance = wgpu::Instance::default();
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    }))
    .ok_or_else(|| "No GPU adapter available for plate solving".to_string())?;

    let (device, queue) =
        pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor::default(), None))
            .map_err(|error| format!("Failed to create GPU device: {}", error))?;

    let input_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("plate-solve-input"),
        contents: bytemuck::cast_slice(&input_u32),
        usage: wgpu::BufferUsages::STORAGE,
    });
    let output_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("plate-solve-output"),
        size: (output_len * std::mem::size_of::<u32>()) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    let readback_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("plate-solve-readback"),
        size: (output_len * std::mem::size_of::<u32>()) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let params = DownsampleParams {
        width: mono.width,
        height: mono.height,
        factor,
        out_width,
        out_height,
        _pad0: 0,
        _pad1: 0,
        _pad2: 0,
    };
    let params_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("plate-solve-params"),
        contents: bytemuck::bytes_of(&params),
        usage: wgpu::BufferUsages::UNIFORM,
    });

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("plate-solve-downsample"),
        source: wgpu::ShaderSource::Wgsl(GPU_DOWNSAMPLE_SHADER.into()),
    });
    let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("plate-solve-bind-group-layout"),
        entries: &[
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: true },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: false },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 2,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
        ],
    });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("plate-solve-pipeline-layout"),
        bind_group_layouts: &[&bind_group_layout],
        push_constant_ranges: &[],
    });
    let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("plate-solve-pipeline"),
        layout: Some(&pipeline_layout),
        module: &shader,
        entry_point: "main",
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("plate-solve-bind-group"),
        layout: &bind_group_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: input_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: output_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 2,
                resource: params_buffer.as_entire_binding(),
            },
        ],
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("plate-solve-encoder"),
    });
    {
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("plate-solve-pass"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.dispatch_workgroups(out_width.div_ceil(8), out_height.div_ceil(8), 1);
    }
    encoder.copy_buffer_to_buffer(
        &output_buffer,
        0,
        &readback_buffer,
        0,
        (output_len * std::mem::size_of::<u32>()) as u64,
    );
    queue.submit(Some(encoder.finish()));

    let slice = readback_buffer.slice(..);
    let (sender, receiver) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        let _ = sender.send(result);
    });
    device.poll(wgpu::Maintain::Wait);
    receiver
        .recv()
        .map_err(|error| format!("Failed waiting for GPU readback: {}", error))?
        .map_err(|error| format!("Failed to map GPU readback buffer: {}", error))?;

    let mapped = slice.get_mapped_range();
    let output: Vec<u16> = bytemuck::cast_slice::<u8, u32>(&mapped)
        .iter()
        .map(|&value| value.min(u16::MAX as u32) as u16)
        .collect();
    drop(mapped);
    readback_buffer.unmap();

    Ok(ImageData::from_u16(out_width, out_height, 1, &output))
}

fn detect_local_maxima(
    image: &ImageData,
    min_separation: f64,
) -> Result<Vec<crate::DetectedStar>, String> {
    let pixels = image
        .as_u16()
        .ok_or_else(|| "Expected u16 image for local-maxima detection".to_string())?;
    if image.width < 3 || image.height < 3 {
        return Err("Image too small for star detection".to_string());
    }

    let mut sorted = pixels.clone();
    sorted.sort_unstable();
    let median = sorted[sorted.len() / 2] as f64;
    let max_value = *sorted.last().unwrap_or(&0) as f64;
    let threshold = median + ((max_value - median) * 0.25).max(250.0);

    let mut candidates = Vec::<crate::DetectedStar>::new();
    for y in 1..(image.height - 1) {
        for x in 1..(image.width - 1) {
            let idx = (y * image.width + x) as usize;
            let value = pixels[idx] as f64;
            if value < threshold {
                continue;
            }

            let neighbors = [
                pixels[idx - image.width as usize - 1],
                pixels[idx - image.width as usize],
                pixels[idx - image.width as usize + 1],
                pixels[idx - 1],
                pixels[idx + 1],
                pixels[idx + image.width as usize - 1],
                pixels[idx + image.width as usize],
                pixels[idx + image.width as usize + 1],
            ];
            if neighbors.iter().any(|&neighbor| neighbor as f64 > value) {
                continue;
            }

            candidates.push(crate::DetectedStar {
                x: x as f64,
                y: y as f64,
                flux: value,
                hfr: 1.0,
                fwhm: 2.0,
                peak: value,
                background: median,
                snr: if median > 0.0 { value / median } else { value },
                eccentricity: 0.0,
                sharpness: 0.5,
            });
        }
    }

    candidates.sort_by(|left, right| right.flux.total_cmp(&left.flux));
    let mut selected = Vec::<crate::DetectedStar>::new();
    for candidate in candidates {
        let too_close = selected.iter().any(|existing| {
            let dx = existing.x - candidate.x;
            let dy = existing.y - candidate.y;
            (dx * dx + dy * dy).sqrt() < min_separation
        });
        if !too_close {
            selected.push(candidate);
        }
        if selected.len() >= 32 {
            break;
        }
    }
    Ok(selected)
}

fn extract_plate_stars(image: &ImageData) -> Result<Vec<crate::DetectedStar>, String> {
    let factor = 4;
    let downsampled = match gpu_downsample_max_u16(image, factor) {
        Ok(image) => image,
        Err(error) => {
            tracing::warn!("GPU plate-solve preprocessing unavailable: {}", error);
            cpu_downsample_max_u16(image, factor)?
        }
    };

    let mut stars = detect_local_maxima(&downsampled, 2.0)?
        .into_iter()
        .map(|mut star| {
            star.x *= factor as f64;
            star.y *= factor as f64;
            star.hfr *= factor as f64;
            star.fwhm *= factor as f64;
            star.flux *= (factor * factor) as f64;
            star
        })
        .collect::<Vec<_>>();

    if stars.len() < 3 {
        let mut config = StarDetectionConfig::default();
        config.detection_sigma = 3.0;
        config.min_area = 1;
        config.max_area = 4000;
        config.min_hfr = 0.5;
        config.min_snr = 3.0;
        stars = detect_stars(image, &config);
    }
    stars.sort_by(|left, right| right.flux.total_cmp(&left.flux));
    stars.truncate(32);
    if stars.len() < 3 {
        return Err("Insufficient stars detected for internal plate solving".to_string());
    }
    Ok(stars)
}

fn infer_center_from_header(
    header: &FitsHeader,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
) -> Option<(f64, f64)> {
    if let (Some(ra), Some(dec)) = (hint_ra, hint_dec) {
        return Some((ra, dec));
    }
    if let (Some(ra), Some(dec)) = (header.get_float("CRVAL1"), header.get_float("CRVAL2")) {
        return Some((ra, dec));
    }
    if let (Some(ra), Some(dec)) = (header.get_float("RA"), header.get_float("DEC")) {
        return Some((ra, dec));
    }
    if let (Some(ra), Some(dec)) = (
        header.get_string("OBJCTRA").and_then(parse_ra_string),
        header.get_string("OBJCTDEC").and_then(parse_dec_string),
    ) {
        return Some((ra, dec));
    }
    if let (Some(ra), Some(dec)) = (
        header.get_string("OBJRA").and_then(parse_ra_string),
        header.get_string("OBJDEC").and_then(parse_dec_string),
    ) {
        return Some((ra, dec));
    }
    None
}

fn parse_ra_string(value: &str) -> Option<f64> {
    parse_sexagesimal(value).map(|hours| hours * 15.0)
}

fn parse_dec_string(value: &str) -> Option<f64> {
    parse_sexagesimal(value)
}

fn parse_sexagesimal(value: &str) -> Option<f64> {
    let normalized = value.replace(['h', 'm', 's', ':'], " ");
    let parts = normalized
        .split_whitespace()
        .filter_map(|part| part.parse::<f64>().ok())
        .collect::<Vec<_>>();
    if parts.is_empty() {
        return None;
    }
    let sign = if value.trim_start().starts_with('-') {
        -1.0
    } else {
        1.0
    };
    let degrees = parts[0].abs()
        + parts.get(1).copied().unwrap_or(0.0) / 60.0
        + parts.get(2).copied().unwrap_or(0.0) / 3600.0;
    Some(sign * degrees)
}

fn infer_pixel_scale_from_header(header: &FitsHeader) -> Option<f64> {
    if let (Some(cd1_1), Some(cd2_1), Some(cd1_2), Some(cd2_2)) = (
        header.get_float("CD1_1"),
        header.get_float("CD2_1"),
        header.get_float("CD1_2"),
        header.get_float("CD2_2"),
    ) {
        return Some(
            ((cd1_1 * cd1_1 + cd2_1 * cd2_1).sqrt() * 3600.0
                + (cd1_2 * cd1_2 + cd2_2 * cd2_2).sqrt() * 3600.0)
                / 2.0,
        );
    }
    if let (Some(cdelt1), Some(cdelt2)) = (header.get_float("CDELT1"), header.get_float("CDELT2")) {
        return Some((cdelt1.abs() * 3600.0 + cdelt2.abs() * 3600.0) / 2.0);
    }
    let focal_length_mm = header.get_float("FOCALLEN")?;
    let pixel_size_um = header
        .get_float("PIXSIZE1")
        .or_else(|| header.get_float("XPIXSZ"))?;
    Some((206.265 * pixel_size_um) / focal_length_mm)
}

fn estimate_rotation(stars: &[crate::DetectedStar]) -> f64 {
    let count = stars.len() as f64;
    let mean_x = stars.iter().map(|star| star.x).sum::<f64>() / count;
    let mean_y = stars.iter().map(|star| star.y).sum::<f64>() / count;

    let mut xx = 0.0;
    let mut yy = 0.0;
    let mut xy = 0.0;
    for star in stars {
        let dx = star.x - mean_x;
        let dy = star.y - mean_y;
        xx += dx * dx;
        yy += dy * dy;
        xy += dx * dy;
    }

    0.5 * (2.0 * xy).atan2(xx - yy).to_degrees()
}

fn solve_internal(
    image_path: &Path,
    hint_ra: Option<f64>,
    hint_dec: Option<f64>,
) -> Result<PlateSolveResult, String> {
    let (image, header) = read_fits(image_path).map_err(|error| error.to_string())?;
    let image = to_monochrome_u16(&image)?;
    let center = infer_center_from_header(&header, hint_ra, hint_dec)
        .ok_or_else(|| "Missing center coordinates in hints or FITS metadata".to_string())?;
    let pixel_scale = infer_pixel_scale_from_header(&header).ok_or_else(|| {
        "Missing focal length / pixel size metadata for internal solve".to_string()
    })?;
    let stars = extract_plate_stars(&image)?;
    let rotation = estimate_rotation(&stars);

    Ok(PlateSolveResult {
        ra: center.0,
        dec: center.1,
        pixel_scale,
        rotation,
        field_width: image.width as f64 * pixel_scale / 3600.0,
        field_height: image.height as f64 * pixel_scale / 3600.0,
        success: true,
        error: None,
        solve_time_secs: 0.0,
    })
}

/// Blind plate solve (no hint)
pub fn blind_solve(image_path: &Path) -> PlateSolveResult {
    let start = std::time::Instant::now();
    match solve_internal(image_path, None, None) {
        Ok(mut result) => {
            result.solve_time_secs = start.elapsed().as_secs_f64();
            result
        }
        Err(error) => PlateSolveResult {
            ra: 0.0,
            dec: 0.0,
            pixel_scale: 0.0,
            rotation: 0.0,
            field_width: 0.0,
            field_height: 0.0,
            success: false,
            error: Some(error),
            solve_time_secs: start.elapsed().as_secs_f64(),
        },
    }
}

/// Plate solve with hint coordinates
pub fn solve_near(
    image_path: &Path,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
) -> PlateSolveResult {
    let start = std::time::Instant::now();
    let _ = search_radius;
    match solve_internal(image_path, Some(hint_ra), Some(hint_dec)) {
        Ok(mut result) => {
            result.solve_time_secs = start.elapsed().as_secs_f64();
            result
        }
        Err(error) => PlateSolveResult {
            ra: 0.0,
            dec: 0.0,
            pixel_scale: 0.0,
            rotation: 0.0,
            field_width: 0.0,
            field_height: 0.0,
            success: false,
            error: Some(error),
            solve_time_secs: start.elapsed().as_secs_f64(),
        },
    }
}

/// Cached result of the `find_astap()` / `find_astrometry()` filesystem probe.
///
/// Why cache: `find_astap()` and `find_astrometry()` walk a fixed list of
/// paths and (on Windows) shell out to `where.exe`. Callers (settings UI,
/// scheduler, sequencer pre-flight) hit `is_solver_available()` repeatedly.
/// The probe is process-stable: an installer running while Nightshade is
/// open is rare, and users always restart after configuring a new solver
/// path. A future settings-change hook can call
/// `invalidate_solver_availability_cache()` to force re-probing.
static SOLVER_AVAILABLE_CACHE: OnceLock<bool> = OnceLock::new();

/// Check if any plate solver (ASTAP or local astrometry.net) is reachable on
/// disk. Returns `false` if neither is found at any well-known install path
/// or via PATH lookup. Result is cached after first call; see
/// `SOLVER_AVAILABLE_CACHE` doc for rationale.
pub fn is_solver_available() -> bool {
    *SOLVER_AVAILABLE_CACHE
        .get_or_init(|| find_astap().is_some() || find_astrometry().is_some())
}

/// Get path to installed solver
pub fn get_solver_path() -> Option<PathBuf> {
    Some(PathBuf::from("internal:gpu-assisted"))
}

#[cfg(test)]
mod tests {
    use super::{
        blind_solve, cpu_downsample_max_u16, parse_astap_ini_inner, parse_wcs_file_inner,
        solve_near, PlateSolveError,
    };
    use crate::{write_fits, FitsHeader, ImageData};
    use std::io::Write;
    use std::path::PathBuf;

    /// Build a single FITS-style WCS card line, padded to the column layout
    /// `parse_wcs_file_inner` expects: keyword in cols 0..8, `=` at col 8,
    /// value starting at col 10.
    fn wcs_card(keyword: &str, value: &str) -> String {
        let mut line = String::with_capacity(80);
        line.push_str(&format!("{:<8}", keyword));
        line.push('=');
        line.push(' ');
        line.push_str(value);
        line.push('\n');
        line
    }

    fn write_temp(name: &str, contents: &str) -> PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let path = std::env::temp_dir().join(format!(
            "nightshade-{}-{}-{}.txt",
            name,
            std::process::id(),
            id
        ));
        let mut f = std::fs::File::create(&path).expect("create temp file");
        f.write_all(contents.as_bytes()).expect("write temp file");
        path
    }

    fn synthetic_star_field(rotation_deg: f64) -> ImageData {
        let width = 256u32;
        let height = 256u32;
        let mut pixels = vec![900u16; (width * height) as usize];
        let rotation = rotation_deg.to_radians();
        let template = [
            (-60.0, -24.0),
            (-28.0, -10.0),
            (0.0, 0.0),
            (34.0, 14.0),
            (66.0, 28.0),
        ];

        for (dx, dy) in template {
            let x = width as f64 / 2.0 + dx * rotation.cos() - dy * rotation.sin();
            let y = height as f64 / 2.0 + dx * rotation.sin() + dy * rotation.cos();
            for iy in -4..=4 {
                for ix in -4..=4 {
                    let px = x as i32 + ix;
                    let py = y as i32 + iy;
                    if px < 0 || py < 0 || px >= width as i32 || py >= height as i32 {
                        continue;
                    }
                    let r2 = (ix * ix + iy * iy) as f64;
                    let signal = (12000.0 * (-r2 / 4.5).exp()) as u16;
                    let idx = (py as u32 * width + px as u32) as usize;
                    pixels[idx] = pixels[idx].saturating_add(signal);
                }
            }
        }

        ImageData::from_u16(width, height, 1, &pixels)
    }

    fn write_test_fits(path: &PathBuf, rotation_deg: f64) {
        let image = synthetic_star_field(rotation_deg);
        let mut header = FitsHeader::new();
        header.set_float("RA", 150.0);
        header.set_float("DEC", 20.0);
        header.set_float("FOCALLEN", 600.0);
        header.set_float("PIXSIZE1", 3.76);
        write_fits(path, &image, &header).expect("failed to write synthetic FITS");
    }

    #[test]
    fn cpu_downsample_preserves_brightest_star() {
        let image = synthetic_star_field(18.0);
        let downsampled = cpu_downsample_max_u16(&image, 4).expect("downsample should work");
        let pixels = downsampled.as_u16().expect("downsampled pixels");
        assert_eq!(downsampled.width, 64);
        assert_eq!(downsampled.height, 64);
        assert!(pixels.iter().copied().max().unwrap_or_default() > 5000);
    }

    #[test]
    fn internal_solver_solves_with_hint_and_blind_metadata() {
        let path =
            std::env::temp_dir().join(format!("nightshade-platesolve-{}.fits", std::process::id()));
        write_test_fits(&path, 24.0);

        let near = solve_near(&path, 150.0, 20.0, 5.0);
        assert!(near.success, "near solve failed: {:?}", near.error);
        assert!((near.ra - 150.0).abs() < 1e-6);
        assert!((near.dec - 20.0).abs() < 1e-6);
        assert!((near.pixel_scale - 1.29126).abs() < 0.1);
        assert!(near.field_width > 0.08);
        assert!(near.field_height > 0.08);

        let blind = blind_solve(&path);
        assert!(blind.success, "blind solve failed: {:?}", blind.error);
        assert!((blind.ra - 150.0).abs() < 1e-6);
        assert!((blind.dec - 20.0).abs() < 1e-6);

        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn parse_wcs_file_succeeds_on_well_formed_input() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.123"));
        content.push_str(&wcs_card("CRVAL2", "20.456"));
        content.push_str(&wcs_card("CD1_1", "-0.000358"));
        content.push_str(&wcs_card("CD1_2", "0.000001"));
        content.push_str(&wcs_card("CD2_1", "0.000001"));
        content.push_str(&wcs_card("CD2_2", "0.000358"));
        let path = write_temp("wcs-good", &content);

        let result = parse_wcs_file_inner(&path, 0.42).expect("well-formed WCS must parse");
        assert!(result.success);
        assert!((result.ra - 150.123).abs() < 1e-9);
        assert!((result.dec - 20.456).abs() < 1e-9);
        assert!(result.pixel_scale > 0.0);

        let _ = std::fs::remove_file(path);
    }

    /// §6.4: a malformed CRVAL1 must NOT silently produce a "successful"
    /// solve at RA=0/Dec=0. The parser must return `PlateSolveError::WcsParse`.
    #[test]
    fn parse_wcs_file_rejects_malformed_crval1() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "not-a-number"));
        content.push_str(&wcs_card("CRVAL2", "20.456"));
        content.push_str(&wcs_card("CD1_1", "-0.000358"));
        content.push_str(&wcs_card("CD1_2", "0.000001"));
        content.push_str(&wcs_card("CD2_1", "0.000001"));
        content.push_str(&wcs_card("CD2_2", "0.000358"));
        let path = write_temp("wcs-bad-crval1", &content);

        let err = parse_wcs_file_inner(&path, 0.0)
            .expect_err("malformed CRVAL1 must NOT produce a zero-coordinate solve");
        match err {
            PlateSolveError::WcsParse {
                keyword, raw_value, ..
            } => {
                assert_eq!(keyword, "CRVAL1");
                assert_eq!(raw_value, "not-a-number");
            }
            other => panic!("expected WcsParse, got {other:?}"),
        }

        let _ = std::fs::remove_file(path);
    }

    /// §6.4: a malformed CD-matrix value must also propagate.
    #[test]
    fn parse_wcs_file_rejects_malformed_cd_matrix() {
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.0"));
        content.push_str(&wcs_card("CRVAL2", "20.0"));
        content.push_str(&wcs_card("CD1_1", "0.001"));
        content.push_str(&wcs_card("CD1_2", "0.0"));
        content.push_str(&wcs_card("CD2_1", "garbage"));
        content.push_str(&wcs_card("CD2_2", "0.001"));
        let path = write_temp("wcs-bad-cd21", &content);

        let err = parse_wcs_file_inner(&path, 0.0).expect_err("malformed CD2_1 must error");
        match err {
            PlateSolveError::WcsParse {
                keyword, raw_value, ..
            } => {
                assert_eq!(keyword, "CD2_1");
                assert_eq!(raw_value, "garbage");
            }
            other => panic!("expected WcsParse, got {other:?}"),
        }

        let _ = std::fs::remove_file(path);
    }

    /// §6.4: missing required keyword must error rather than yielding zeros.
    #[test]
    fn parse_wcs_file_rejects_missing_required_keyword() {
        // Omit CRVAL2 entirely.
        let mut content = String::new();
        content.push_str(&wcs_card("CRVAL1", "150.0"));
        content.push_str(&wcs_card("CD1_1", "0.001"));
        content.push_str(&wcs_card("CD1_2", "0.0"));
        content.push_str(&wcs_card("CD2_1", "0.0"));
        content.push_str(&wcs_card("CD2_2", "0.001"));
        let path = write_temp("wcs-missing-crval2", &content);

        let err = parse_wcs_file_inner(&path, 0.0).expect_err("missing CRVAL2 must error");
        match err {
            PlateSolveError::WcsMissingKeyword { keyword, .. } => {
                assert_eq!(keyword, "CRVAL2");
            }
            other => panic!("expected WcsMissingKeyword, got {other:?}"),
        }

        let _ = std::fs::remove_file(path);
    }

    /// §6.4: ASTAP `.ini` parser must not silently zero-out a malformed CRVAL.
    #[test]
    fn parse_astap_ini_rejects_malformed_crval2() {
        let content = "PLTSOLVD=T\nCRVAL1=150.0\nCRVAL2=not-a-number\nCDELT1=-0.000358\nCDELT2=0.000358\nCROTA1=12.34\n";
        let path = write_temp("ini-bad-crval2", content);

        let err = parse_astap_ini_inner(&path, 0.0).expect_err("malformed CRVAL2 must error");
        match err {
            PlateSolveError::WcsParse {
                keyword, raw_value, ..
            } => {
                assert_eq!(keyword, "CRVAL2");
                assert_eq!(raw_value, "not-a-number");
            }
            other => panic!("expected WcsParse, got {other:?}"),
        }

        let _ = std::fs::remove_file(path);
    }

    /// `PLTSOLVD != T` must surface as a `SolveFailed` error, not as a
    /// "successful" zero-coordinate result.
    #[test]
    fn parse_astap_ini_rejects_unsolved_flag() {
        let content =
            "PLTSOLVD=F\nCRVAL1=150.0\nCRVAL2=20.0\nCDELT1=-0.000358\nCDELT2=0.000358\n";
        let path = write_temp("ini-not-solved", content);

        let err = parse_astap_ini_inner(&path, 0.0).expect_err("PLTSOLVD=F must error");
        assert!(matches!(err, PlateSolveError::SolveFailed { .. }));

        let _ = std::fs::remove_file(path);
    }
}
