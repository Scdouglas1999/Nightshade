//! Saemundsson atmospheric refraction (visual planetarium).
//!
//! INTEGRATE: add `pub mod refraction;` to `astrometry/mod.rs`.
//!
//! Inverse Sæmundsson formula (geometric/true altitude → refraction), consistent with
//! Bennett (1982) to ~0.1′ for altitudes above a few degrees (Wikipedia). Standard
//! atmosphere: 1010 hPa, 10 °C; scaled for observer pressure and temperature.
//!
//! See `docs/plans/2026-05-25-planetarium-v2-design.md` §7.6.

/// Standard pressure for the Sæmundsson coefficients (101.0 kPa = 1010 hPa).
pub const STANDARD_PRESSURE_HPA: f64 = 1010.0;

/// Standard temperature for the Sæmundsson coefficients (°C).
pub const STANDARD_TEMPERATURE_C: f64 = 10.0;

/// True altitudes below this return zero refraction (matches Dart `astronomy_calculations`).
const REFRACTION_CUTOFF_DEG: f64 = -2.0;

/// Zenith altitudes at or above this are treated as zero refraction (numerical noise).
const ZENITH_CLAMP_DEG: f64 = 89.9;

const DEG_TO_RAD: f64 = std::f64::consts::PI / 180.0;

/// Refraction error.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
pub enum RefractionError {
    /// Altitude was non-finite or outside \[-90°, 90°\].
    #[error("altitude must be finite and in [-90, 90] degrees, got {0}")]
    InvalidAltitude(f64),
}

/// Pressure/temperature scale relative to the Sæmundsson standard atmosphere.
///
/// Wikipedia: multiply refraction by `(P/101 kPa) × (283/(273+T))` with P in kPa.
#[inline]
pub fn refraction_scale(pressure_hpa: f64, temperature_c: f64) -> f64 {
    (pressure_hpa / STANDARD_PRESSURE_HPA) * (283.0 / (273.0 + temperature_c))
}

/// Sæmundsson refraction in arcminutes at standard pressure and temperature.
///
/// `true_altitude_deg` is the geometric (unrefracted) altitude in degrees.
/// Returns zero for true altitudes below [`REFRACTION_CUTOFF_DEG`].
#[inline]
pub fn refraction_arcmin_standard(true_altitude_deg: f64) -> Result<f64, RefractionError> {
    refraction_arcmin(true_altitude_deg, STANDARD_PRESSURE_HPA, STANDARD_TEMPERATURE_C)
}

/// Sæmundsson refraction in arcminutes with pressure and temperature scaling.
#[inline]
pub fn refraction_arcmin(
    true_altitude_deg: f64,
    pressure_hpa: f64,
    temperature_c: f64,
) -> Result<f64, RefractionError> {
    validate_altitude(true_altitude_deg)?;
    if true_altitude_deg < REFRACTION_CUTOFF_DEG {
        return Ok(0.0);
    }
    if true_altitude_deg >= ZENITH_CLAMP_DEG {
        return Ok(0.0);
    }
    let r = saemundsson_arcmin_core(true_altitude_deg) * refraction_scale(pressure_hpa, temperature_c);
    Ok(r.max(0.0))
}

/// Sæmundsson refraction in degrees (add to true altitude for apparent).
#[inline]
pub fn refraction_deg(
    true_altitude_deg: f64,
    pressure_hpa: f64,
    temperature_c: f64,
) -> Result<f64, RefractionError> {
    Ok(refraction_arcmin(true_altitude_deg, pressure_hpa, temperature_c)? / 60.0)
}

/// Convert true (geometric) altitude to apparent by adding refraction.
#[inline]
pub fn true_to_apparent_altitude(
    true_altitude_deg: f64,
    pressure_hpa: f64,
    temperature_c: f64,
) -> Result<f64, RefractionError> {
    Ok(true_altitude_deg + refraction_deg(true_altitude_deg, pressure_hpa, temperature_c)?)
}

/// Convert apparent altitude to true by subtracting refraction (iterative).
///
/// Five iterations converge to sub-arcsecond for altitudes above the horizon (Dart uses three,
/// which is sufficient above ~5°).
#[inline]
pub fn apparent_to_true_altitude(
    apparent_altitude_deg: f64,
    pressure_hpa: f64,
    temperature_c: f64,
) -> Result<f64, RefractionError> {
    validate_altitude(apparent_altitude_deg)?;
    if apparent_altitude_deg < REFRACTION_CUTOFF_DEG {
        return Ok(apparent_altitude_deg);
    }
    let mut true_alt = apparent_altitude_deg;
    for _ in 0..5 {
        let r = refraction_deg(true_alt, pressure_hpa, temperature_c)?;
        true_alt = apparent_altitude_deg - r;
    }
    Ok(true_alt)
}

#[inline]
fn validate_altitude(altitude_deg: f64) -> Result<(), RefractionError> {
    if !altitude_deg.is_finite() || !(-90.0..=90.0).contains(&altitude_deg) {
        return Err(RefractionError::InvalidAltitude(altitude_deg));
    }
    Ok(())
}

/// Core Sæmundsson formula: R = 1.02 / tan(h + 10.3/(h + 5.11)) arcmin.
#[inline]
fn saemundsson_arcmin_core(true_altitude_deg: f64) -> f64 {
    let h = true_altitude_deg;
    let arg_deg = h + 10.3 / (h + 5.11);
    1.02 / (arg_deg * DEG_TO_RAD).tan()
}
