//! SGP4 satellite orbit propagation in the TEME frame.
//!
//! Wraps the [`sgp4`] crate (Vallado et al., *Revisiting Spacetrack Report #3*).
//! Initialization and propagation use the AFSPC compatibility mode so results match
//! the canonical Spacetrack / `sgp4` verification dataset.

use glam::DVec3;
use sgp4::{
    Constants, Elements, Error as Sgp4Error, MinutesSinceEpoch, Prediction, TleError,
};

/// Maximum allowed position error (km) against the canonical verification suite.
pub const VERIFICATION_POSITION_TOLERANCE_KM: f64 = 1.0;

/// Maximum allowed velocity error (km/s) against the canonical verification suite.
pub const VERIFICATION_VELOCITY_TOLERANCE_KM_S: f64 = 1.0e-6;

/// Errors from TLE parsing or SGP4 propagation.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum Sgp4PropError {
    /// Two-line element set could not be parsed.
    #[error("TLE parse error: {0}")]
    TleParse(String),
    /// Epoch elements are invalid for SGP4 initialization.
    #[error("SGP4 element initialization: {0}")]
    Init(String),
    /// Propagation failed (decayed orbit, diverging eccentricity, etc.).
    #[error("SGP4 propagation failed: {0}")]
    Propagate(String),
}

impl From<TleError> for Sgp4PropError {
    fn from(err: TleError) -> Self {
        Self::TleParse(err.to_string())
    }
}

/// Satellite position and velocity in TEME (km, km/s).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TemeState {
    /// Position (x, y, z) in kilometers.
    pub position_km: DVec3,
    /// Velocity (vx, vy, vz) in kilometers per second.
    pub velocity_km_s: DVec3,
}

impl From<Prediction> for TemeState {
    fn from(prediction: Prediction) -> Self {
        Self {
            position_km: DVec3::from_array(prediction.position),
            velocity_km_s: DVec3::from_array(prediction.velocity),
        }
    }
}

/// Parsed TLE plus precomputed SGP4 constants for repeated propagation.
#[derive(Debug, Clone)]
pub struct SatellitePropagator {
    elements: Elements,
    constants: Constants,
}

impl SatellitePropagator {
    /// Parse a NORAD two-line element set and build propagator constants.
    pub fn from_tle(
        object_name: Option<String>,
        line1: &str,
        line2: &str,
    ) -> Result<Self, Sgp4PropError> {
        let elements = Elements::from_tle(object_name, line1.as_bytes(), line2.as_bytes())?;
        Self::from_elements(elements)
    }

    /// Build a propagator from already-parsed [`Elements`].
    pub fn from_elements(elements: Elements) -> Result<Self, Sgp4PropError> {
        let constants = Constants::from_elements_afspc_compatibility_mode(&elements)
            .map_err(|err| Sgp4PropError::Init(err.to_string()))?;
        Ok(Self { elements, constants })
    }

    /// Orbital elements (epoch, inclination, etc.).
    #[inline]
    pub fn elements(&self) -> &Elements {
        &self.elements
    }

    /// Propagate to `minutes_since_epoch` (minutes from the TLE epoch).
    pub fn propagate_minutes_since_epoch(
        &self,
        minutes_since_epoch: f64,
    ) -> Result<TemeState, Sgp4PropError> {
        let prediction = self
            .constants
            .propagate_afspc_compatibility_mode(MinutesSinceEpoch(minutes_since_epoch))
            .map_err(sgp4_propagate_error)?;
        Ok(TemeState::from(prediction))
    }
}

/// Parse TLE lines without building propagator constants.
#[inline]
pub fn parse_tle(
    object_name: Option<String>,
    line1: &str,
    line2: &str,
) -> Result<Elements, Sgp4PropError> {
    Elements::from_tle(object_name, line1.as_bytes(), line2.as_bytes()).map_err(Into::into)
}

/// Propagate a TLE once at `minutes_since_epoch` without retaining constants.
#[inline]
pub fn propagate_tle_minutes_since_epoch(
    object_name: Option<String>,
    line1: &str,
    line2: &str,
    minutes_since_epoch: f64,
) -> Result<TemeState, Sgp4PropError> {
    SatellitePropagator::from_tle(object_name, line1, line2)?
        .propagate_minutes_since_epoch(minutes_since_epoch)
}

/// Great-circle distance between two TEME position vectors (km).
#[inline]
pub fn position_error_km(a: DVec3, b: DVec3) -> f64 {
    (a - b).length()
}

fn sgp4_propagate_error(err: Sgp4Error) -> Sgp4PropError {
    Sgp4PropError::Propagate(err.to_string())
}
