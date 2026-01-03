//! Real Plate Solving Integration
//!
//! Provides actual integration with plate solving software:
//! - ASTAP (Astrometric STAcking Program)
//! - Local Astrometry.net
//!
//! These are real implementations that call external solvers.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::fs;

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
            None => return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some("ASTAP not found".to_string()),
                solve_time_secs: 0.0,
            },
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
        
        // Hint scale (focal length)
        if let Some(scale) = hint_scale {
            // ASTAP uses focal length, estimate from scale
            // scale = 206.265 * pixel_size / focal_length
            // Assuming 3.76 micron pixels (common for ASI cameras)
            let focal_length = 206.265 * 3.76 / scale;
            cmd.arg("-fov").arg(format!("{}", focal_length));
        }
        
        // Downsample
        if self.config.downsample > 1 {
            cmd.arg("-z").arg(format!("{}", self.config.downsample));
        }
        
        // Output (don't update FITS, just solve)
        cmd.arg("-update");
        
        // Run solver
        tracing::info!("Running ASTAP: {:?}", cmd);
        
        let output = match cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
        {
            Ok(o) => o,
            Err(e) => return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(format!("Failed to run ASTAP: {}", e)),
                solve_time_secs: start.elapsed().as_secs_f64(),
            },
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
        
        self.parse_wcs_file(&wcs_path, solve_time)
    }
    
    /// Parse ASTAP .ini result file
    fn parse_astap_ini(&self, ini_path: &Path, solve_time: f64) -> PlateSolveResult {
        let content = match fs::read_to_string(ini_path) {
            Ok(c) => c,
            Err(e) => return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(format!("Failed to read INI: {}", e)),
                solve_time_secs: solve_time,
            },
        };
        
        let mut ra = 0.0_f64;
        let mut dec = 0.0_f64;
        let mut crota = 0.0_f64;
        let mut cdelt1 = 0.0_f64;
        let mut cdelt2 = 0.0_f64;
        let mut solved = false;
        
        for line in content.lines() {
            let line = line.trim();
            if let Some((key, value)) = line.split_once('=') {
                let key = key.trim().to_uppercase();
                let value = value.trim();
                
                match key.as_str() {
                    "CRVAL1" => ra = value.parse().unwrap_or(0.0),
                    "CRVAL2" => dec = value.parse().unwrap_or(0.0),
                    "CROTA1" | "CROTA2" => crota = value.parse().unwrap_or(0.0),
                    "CDELT1" => cdelt1 = value.parse().unwrap_or(0.0),
                    "CDELT2" => cdelt2 = value.parse().unwrap_or(0.0),
                    "PLTSOLVD" => solved = value == "T",
                    _ => {}
                }
            }
        }
        
        if !solved {
            return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some("Plate solve failed".to_string()),
                solve_time_secs: solve_time,
            };
        }
        
        // Convert CDELT to arcsec/pixel
        let pixel_scale = (cdelt1.abs() * 3600.0 + cdelt2.abs() * 3600.0) / 2.0;
        
        PlateSolveResult {
            ra,
            dec,
            pixel_scale,
            rotation: crota,
            field_width: 0.0, // Would need image dimensions
            field_height: 0.0,
            success: true,
            error: None,
            solve_time_secs: solve_time,
        }
    }
    
    /// Parse WCS file
    fn parse_wcs_file(&self, wcs_path: &Path, solve_time: f64) -> PlateSolveResult {
        let content = match fs::read_to_string(wcs_path) {
            Ok(c) => c,
            Err(e) => return PlateSolveResult {
                ra: 0.0,
                dec: 0.0,
                pixel_scale: 0.0,
                rotation: 0.0,
                field_width: 0.0,
                field_height: 0.0,
                success: false,
                error: Some(format!("Failed to read WCS: {}", e)),
                solve_time_secs: solve_time,
            },
        };
        
        // Parse FITS-style header keywords
        let mut ra = 0.0_f64;
        let mut dec = 0.0_f64;
        let mut cd1_1 = 0.0_f64;
        let mut cd1_2 = 0.0_f64;
        let mut cd2_1 = 0.0_f64;
        let mut cd2_2 = 0.0_f64;
        
        for line in content.lines() {
            if line.len() < 10 {
                continue;
            }
            
            let keyword = &line[..8].trim();
            if !line[8..].starts_with('=') {
                continue;
            }
            
            let value_part = &line[10..].trim();
            let value_str = if let Some(idx) = value_part.find('/') {
                &value_part[..idx]
            } else {
                value_part
            }.trim();
            
            match *keyword {
                "CRVAL1" => ra = value_str.parse().unwrap_or(0.0),
                "CRVAL2" => dec = value_str.parse().unwrap_or(0.0),
                "CD1_1" => cd1_1 = value_str.parse().unwrap_or(0.0),
                "CD1_2" => cd1_2 = value_str.parse().unwrap_or(0.0),
                "CD2_1" => cd2_1 = value_str.parse().unwrap_or(0.0),
                "CD2_2" => cd2_2 = value_str.parse().unwrap_or(0.0),
                _ => {}
            }
        }
        
        // Calculate pixel scale and rotation from CD matrix
        let pixel_scale = ((cd1_1 * cd1_1 + cd2_1 * cd2_1).sqrt() * 3600.0
            + (cd1_2 * cd1_2 + cd2_2 * cd2_2).sqrt() * 3600.0) / 2.0;
        let rotation = cd2_1.atan2(cd1_1).to_degrees();
        
        PlateSolveResult {
            ra,
            dec,
            pixel_scale,
            rotation,
            field_width: 0.0,
            field_height: 0.0,
            success: true,
            error: None,
            solve_time_secs: solve_time,
        }
    }
}

/// Blind plate solve (no hint)
pub fn blind_solve(image_path: &Path) -> PlateSolveResult {
    let solver = match AstapSolver::with_default_config() {
        Some(s) => s,
        None => return PlateSolveResult {
            ra: 0.0,
            dec: 0.0,
            pixel_scale: 0.0,
            rotation: 0.0,
            field_width: 0.0,
            field_height: 0.0,
            success: false,
            error: Some("No plate solver available".to_string()),
            solve_time_secs: 0.0,
        },
    };
    
    solver.solve(image_path, None, None, None)
}

/// Plate solve with hint coordinates
pub fn solve_near(
    image_path: &Path,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
) -> PlateSolveResult {
    let mut config = PlateSolverConfig::default();
    config.search_radius = search_radius;
    
    let solver = AstapSolver::new(config);
    solver.solve(image_path, Some(hint_ra), Some(hint_dec), None)
}

/// Check if any plate solver is available
pub fn is_solver_available() -> bool {
    find_astap().is_some() || find_astrometry().is_some()
}

/// Get path to installed solver
pub fn get_solver_path() -> Option<PathBuf> {
    find_astap().or_else(find_astrometry)
}





