//! Kepler-equation solver and Keplerian minor-body propagation.
//!
//! Classical osculating elements (MPC-style: a, e, i, Ω, ω, M₀, epoch) are
//! advanced with a two-body Kepler solver and converted to heliocentric
//! ecliptic J2000 coordinates. Geocentric equatorial positions use a
//! simplified Earth ephemeris (matching the v1 Dart catalog propagator).
//!
//! INTEGRATE: add `pub mod kepler;` to `astrometry/mod.rs`.

use glam::DVec3;

/// Julian date of J2000.0 TT.
pub const J2000_JD: f64 = 2_451_545.0;

/// Mean obliquity of the ecliptic at J2000.0 (radians, IAU 2006).
pub const OBLIQUITY_J2000_RAD: f64 = 23.439_291_111_f64.to_radians();

/// Eccentricity above which Halley's method is used (near-parabolic orbits).
pub const NEAR_PARABOLIC_ECCENTRICITY: f64 = 0.80;

/// Kepler iteration tolerance (radians).
pub const KEPLER_TOLERANCE_RAD: f64 = 1.0e-14;

/// Maximum Kepler solver iterations.
pub const KEPLER_MAX_ITERATIONS: u32 = 30;

const DEG_TO_RAD: f64 = std::f64::consts::PI / 180.0;
const RAD_TO_DEG: f64 = 180.0 / std::f64::consts::PI;

/// Minor-body classification for magnitude models (future pipeline use).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MinorBodyKind {
    /// Main-belt or near-Earth asteroid.
    Asteroid,
    /// Comet (may use tail rendering in the render pipeline).
    Comet,
}

/// Keplerian osculating elements at `epoch_jd` (MPC convention).
///
/// Angles are in degrees; `semi_major_axis_au` is in astronomical units.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct OrbitalElements {
    /// Epoch of osculation (Julian date, TT).
    pub epoch_jd: f64,
    /// Semi-major axis (AU).
    pub semi_major_axis_au: f64,
    /// Orbital eccentricity (0 ≤ e < 1).
    pub eccentricity: f64,
    /// Inclination (degrees).
    pub inclination_deg: f64,
    /// Longitude of ascending node Ω (degrees).
    pub longitude_ascending_node_deg: f64,
    /// Argument of perihelion ω (degrees).
    pub argument_perihelion_deg: f64,
    /// Mean anomaly at epoch M₀ (degrees).
    pub mean_anomaly_deg: f64,
}

/// Heliocentric ecliptic J2000 state (AU).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HeliocentricState {
    /// Position vector (x, y, z) in AU, ecliptic J2000.
    pub position_au: DVec3,
    /// Heliocentric distance (AU).
    pub distance_au: f64,
}

/// Geocentric equatorial J2000 apparent direction.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GeocentricEquatorial {
    /// Right ascension (hours, 0–24).
    pub ra_hours: f64,
    /// Declination (degrees, −90…+90).
    pub dec_deg: f64,
    /// Geocentric distance (AU).
    pub distance_au: f64,
    /// Heliocentric distance (AU).
    pub heliocentric_distance_au: f64,
}

impl OrbitalElements {
    /// Orbital period in days (Kepler's third law, solar mass).
    #[inline]
    pub fn period_days(&self) -> f64 {
        365.25 * self.semi_major_axis_au.powf(1.5)
    }

    /// Mean motion in degrees per day.
    #[inline]
    pub fn mean_motion_deg_per_day(&self) -> f64 {
        360.0 / self.period_days()
    }
}

/// Solve Kepler's equation `E − e sin E = M` for elliptic orbits.
///
/// Uses Newton–Raphson for moderate eccentricity and Halley's method when
/// `e ≥` [`NEAR_PARABOLIC_ECCENTRICITY`] for robust convergence near e ≈ 1.
#[inline]
pub fn solve_kepler(mean_anomaly_rad: f64, eccentricity: f64) -> f64 {
    let m = normalize_angle_rad(mean_anomaly_rad);
    let e = eccentricity.clamp(0.0, 1.0 - 1.0e-12);

    let mut e_anomaly = initial_eccentric_anomaly_guess(m, e);

    if e >= NEAR_PARABOLIC_ECCENTRICITY {
        halley_kepler(m, e, &mut e_anomaly);
    } else {
        newton_kepler(m, e, &mut e_anomaly);
    }

    e_anomaly
}

/// Residual of Kepler's equation: `E − e sin E − M` (radians).
#[inline]
pub fn kepler_equation_residual(
    eccentric_anomaly_rad: f64,
    mean_anomaly_rad: f64,
    eccentricity: f64,
) -> f64 {
    eccentric_anomaly_rad - eccentricity * eccentric_anomaly_rad.sin() - mean_anomaly_rad
}

/// Heliocentric ecliptic J2000 position at Julian date `jd_tt`.
pub fn heliocentric_ecliptic_j2000(elements: &OrbitalElements, jd_tt: f64) -> HeliocentricState {
    let mean_anomaly_rad = mean_anomaly_at(elements, jd_tt);
    let e = elements.eccentricity;
    let e_anomaly = solve_kepler(mean_anomaly_rad, e);

    let (sin_e, cos_e) = e_anomaly.sin_cos();
    let true_anomaly = ((1.0 - e * e).sqrt() * sin_e).atan2(cos_e - e);
    let r = elements.semi_major_axis_au * (1.0 - e * cos_e);

    let (x_orb, y_orb) = (r * true_anomaly.cos(), r * true_anomaly.sin());
    let position_au = orbital_plane_to_ecliptic(
        x_orb,
        y_orb,
        elements.argument_perihelion_deg * DEG_TO_RAD,
        elements.longitude_ascending_node_deg * DEG_TO_RAD,
        elements.inclination_deg * DEG_TO_RAD,
    );

    HeliocentricState {
        distance_au: r,
        position_au,
    }
}

/// Geocentric equatorial J2000 position (simplified Earth ephemeris).
pub fn geocentric_equatorial_j2000(elements: &OrbitalElements, jd_tt: f64) -> GeocentricEquatorial {
    let helio = heliocentric_ecliptic_j2000(elements, jd_tt);
    let earth = earth_heliocentric_ecliptic_j2000(jd_tt);
    let geo_ecl = helio.position_au - earth;

    let (sin_eps, cos_eps) = OBLIQUITY_J2000_RAD.sin_cos();
    let x_eq = geo_ecl.x;
    let y_eq = geo_ecl.y * cos_eps - geo_ecl.z * sin_eps;
    let z_eq = geo_ecl.y * sin_eps + geo_ecl.z * cos_eps;

    let distance_au = DVec3::new(x_eq, y_eq, z_eq).length();
    let mut ra_deg = y_eq.atan2(x_eq) * RAD_TO_DEG;
    if ra_deg < 0.0 {
        ra_deg += 360.0;
    }
    let dec_deg = (z_eq / distance_au).clamp(-1.0, 1.0).asin() * RAD_TO_DEG;

    GeocentricEquatorial {
        ra_hours: ra_deg / 15.0,
        dec_deg,
        distance_au,
        heliocentric_distance_au: helio.distance_au,
    }
}

/// Mean anomaly (radians) at `jd_tt`.
#[inline]
pub fn mean_anomaly_at(elements: &OrbitalElements, jd_tt: f64) -> f64 {
    let days = jd_tt - elements.epoch_jd;
    let m_deg =
        (elements.mean_anomaly_deg + elements.mean_motion_deg_per_day() * days).rem_euclid(360.0);
    m_deg * DEG_TO_RAD
}

#[inline]
fn normalize_angle_rad(angle: f64) -> f64 {
    angle.rem_euclid(std::f64::consts::TAU)
}

/// Initial guess for eccentric anomaly (Danby / Meeus style).
fn initial_eccentric_anomaly_guess(mean_anomaly_rad: f64, eccentricity: f64) -> f64 {
    if eccentricity < 0.8 {
        return mean_anomaly_rad + eccentricity * mean_anomaly_rad.sin();
    }

    // High-eccentricity starter: cubic root approximation near perihelion.
    if mean_anomaly_rad < std::f64::consts::PI {
        let k = (6.0 * mean_anomaly_rad / (eccentricity * std::f64::consts::PI)).cbrt();
        k * eccentricity * std::f64::consts::PI / 6.0 + mean_anomaly_rad
    } else {
        std::f64::consts::PI
            - (6.0 * (std::f64::consts::TAU - mean_anomaly_rad)
                / (eccentricity * std::f64::consts::PI))
                .cbrt()
                * eccentricity
                * std::f64::consts::PI
                / 6.0
            + mean_anomaly_rad
            - std::f64::consts::PI
    }
}

fn newton_kepler(mean_anomaly_rad: f64, eccentricity: f64, e_anomaly: &mut f64) {
    for _ in 0..KEPLER_MAX_ITERATIONS {
        let residual = kepler_equation_residual(*e_anomaly, mean_anomaly_rad, eccentricity);
        if residual.abs() < KEPLER_TOLERANCE_RAD {
            return;
        }
        let derivative = 1.0 - eccentricity * e_anomaly.cos();
        *e_anomaly -= residual / derivative;
    }
}

fn halley_kepler(mean_anomaly_rad: f64, eccentricity: f64, e_anomaly: &mut f64) {
    for _ in 0..KEPLER_MAX_ITERATIONS {
        let sin_e = e_anomaly.sin();
        let cos_e = e_anomaly.cos();
        let f = *e_anomaly - eccentricity * sin_e - mean_anomaly_rad;
        if f.abs() < KEPLER_TOLERANCE_RAD {
            return;
        }
        let fp = 1.0 - eccentricity * cos_e;
        let fpp = eccentricity * sin_e;
        let denominator = 2.0 * fp * fp - f * fpp;
        if denominator.abs() < f64::EPSILON {
            // Degenerate Halley step — fall back to one Newton correction.
            *e_anomaly -= f / fp;
        } else {
            *e_anomaly -= (2.0 * f * fp) / denominator;
        }
    }
}

fn orbital_plane_to_ecliptic(
    x_orb: f64,
    y_orb: f64,
    argument_perihelion_rad: f64,
    longitude_node_rad: f64,
    inclination_rad: f64,
) -> DVec3 {
    let (sin_w, cos_w) = argument_perihelion_rad.sin_cos();
    let (sin_n, cos_n) = longitude_node_rad.sin_cos();
    let (sin_i, cos_i) = inclination_rad.sin_cos();

    let x = x_orb * (cos_w * cos_n - sin_w * sin_n * cos_i)
        - y_orb * (sin_w * cos_n + cos_w * sin_n * cos_i);
    let y = x_orb * (cos_w * sin_n + sin_w * cos_n * cos_i)
        - y_orb * (sin_w * sin_n - cos_w * cos_n * cos_i);
    let z = x_orb * sin_w * sin_i + y_orb * cos_w * sin_i;

    DVec3::new(x, y, z)
}

/// Simplified Earth heliocentric ecliptic position (matches v1 Dart propagator).
fn earth_heliocentric_ecliptic_j2000(jd_tt: f64) -> DVec3 {
    let t = (jd_tt - J2000_JD) / 36_525.0;
    let l = (100.466_46 + 36_000.769_83 * t + 0.000_303_2 * t * t).rem_euclid(360.0);
    let m = (357.529_11 + 35_999.050_29 * t - 0.000_153_7 * t * t).rem_euclid(360.0);
    let e = 0.016_708_634 - 0.000_042_037 * t;
    let m_rad = m * DEG_TO_RAD;

    let c = (1.914_6 - 0.004_817 * t) * m_rad.sin()
        + 0.019_993 * (2.0 * m_rad).sin()
        + 0.000_290 * (3.0 * m_rad).sin();

    let true_lon = (l + c) * DEG_TO_RAD;
    let v = (m + c) * DEG_TO_RAD;
    let r = 1.000_001_018 * (1.0 - e * e) / (1.0 + e * v.cos());

    let earth_lon = true_lon + std::f64::consts::PI;
    DVec3::new(r * earth_lon.cos(), r * earth_lon.sin(), 0.0)
}
