//! Public value types crossing the FFI / render-thread boundary.
//!
//! All types are POD-friendly (no allocations on hot paths) and `Send + Sync`.

/// Sky projection mode.
#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SkyProjection {
    #[default]
    Stereographic = 0,
    Orthographic = 1,
    AzimuthalEquidistant = 2,
}

/// View pose: where the camera looks at the celestial sphere.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ViewPose {
    /// Right ascension of view center (radians, J2000).
    pub ra_rad: f64,
    /// Declination of view center (radians, J2000).
    pub dec_rad: f64,
    /// Field of view across the shorter screen axis (radians).
    pub fov_rad: f32,
    /// Roll about the view axis (radians).
    pub roll_rad: f32,
    pub projection: SkyProjection,
}

impl Default for ViewPose {
    fn default() -> Self {
        Self {
            ra_rad: 0.0,
            dec_rad: std::f64::consts::FRAC_PI_2, // celestial pole
            fov_rad: std::f32::consts::FRAC_PI_2, // 90°
            roll_rad: 0.0,
            projection: SkyProjection::Stereographic,
        }
    }
}

/// Observer location.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Observer {
    pub latitude_rad: f64,
    pub longitude_rad: f64,
    pub elevation_m: f64,
    pub pressure_hpa: f32,
    pub temperature_c: f32,
}

impl Default for Observer {
    fn default() -> Self {
        Self {
            latitude_rad: 0.0,
            longitude_rad: 0.0,
            elevation_m: 0.0,
            pressure_hpa: 1013.25,
            temperature_c: 10.0,
        }
    }
}

/// Astronomical time. See astrometry/time.rs.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AstroTime {
    pub jd_utc: f64,
    pub jd_ut1: f64,
    pub jd_tt: f64,
}

/// Per-layer visibility + quality knobs. Mirrors current `SkyRenderConfig` shape
/// so existing Dart providers map 1:1.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RenderConfig {
    pub show_stars: bool,
    pub show_constellations: bool,
    pub show_constellation_boundaries: bool,
    pub show_constellation_art: bool,
    pub show_equatorial_grid: bool,
    pub show_alt_az_grid: bool,
    pub show_galactic_grid: bool,
    pub show_ecliptic: bool,
    pub show_galactic_plane: bool,
    pub show_milky_way: bool,
    pub show_horizon: bool,
    pub show_atmosphere: bool,
    pub show_dsos: bool,
    pub show_solar_system: bool,
    pub show_satellites: bool,
    pub show_minor_planets: bool,
    pub show_variable_stars: bool,
    pub magnitude_limit: f32,
    pub quality: u32,      // 0=low, 1=medium, 2=high
    pub bortle_class: u32, // 1..9, 0 = no LP dome
    pub twinkle: bool,
}

impl Default for RenderConfig {
    fn default() -> Self {
        Self {
            show_stars: true,
            show_constellations: true,
            show_constellation_boundaries: false,
            show_constellation_art: false,
            show_equatorial_grid: false,
            show_alt_az_grid: false,
            show_galactic_grid: false,
            show_ecliptic: true,
            show_galactic_plane: false,
            show_milky_way: true,
            show_horizon: true,
            show_atmosphere: true,
            show_dsos: true,
            show_solar_system: true,
            show_satellites: false,
            show_minor_planets: false,
            show_variable_stars: false,
            magnitude_limit: 6.0,
            quality: 1,
            bortle_class: 4,
            twinkle: true,
        }
    }
}
