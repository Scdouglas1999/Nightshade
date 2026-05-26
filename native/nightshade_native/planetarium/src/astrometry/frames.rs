//! ICRS → CIRS → TIRS → topocentric horizontal frame chain.
//!
//! Composes IAU 2006 precession, IAU 2000B nutation, Earth Rotation Angle, and
//! observer latitude/longitude. Atmospheric refraction is applied when converting
//! to apparent horizontal coordinates (see [`FrameChain::icrs_to_apparent_horizontal`]).
//!
//! See `docs/plans/2026-05-25-planetarium-v2-design.md` §7.2.

use glam::{DMat3, DVec3};

use crate::astrometry::earth_rotation::era_from_jd_ut1;
use crate::astrometry::nutation::{
    nutation_from_julian_centuries_tt, nutation_matrix_from_julian_centuries_tt,
};
use crate::astrometry::precession::precession_matrix_from_jd_tt;
use crate::astrometry::refraction::{true_to_apparent_altitude, RefractionError};
use crate::astrometry::time::J2000_JD_TT;
use crate::types::{AstroTime, Observer};

/// Topocentric horizontal direction (geometric/true or apparent).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HorizontalCoords {
    /// Altitude above horizon (radians, geometric unless noted).
    pub altitude_rad: f64,
    /// Azimuth from north through east (radians).
    pub azimuth_rad: f64,
}

/// Cached rotation chain for one epoch and observer.
///
/// Matrices use column vectors: `v_out = matrix * v_in`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FrameChain {
    /// ICRS (GCRS) → CIRS (true equator, true equinox of date).
    pub precession_nutation: DMat3,
    /// CIRS → ITRS (Earth-fixed, geocentric).
    pub earth_rotation: DMat3,
    /// ITRS → topocentric East–North–Up.
    pub observer_rotation: DMat3,
    /// Annual aberration correction (ICRS); zero until VSOP87 aberration task.
    pub aberration_delta: DVec3,
    time: AstroTime,
    observer: Observer,
}

impl FrameChain {
    /// Build the frame chain for `time` and `observer`.
    #[inline]
    pub fn r#for(time: AstroTime, observer: Observer) -> Self {
        Self::build(time, observer)
    }

    /// Build the frame chain for `time` and `observer`.
    pub fn build(time: AstroTime, observer: Observer) -> Self {
        let date1 = J2000_JD_TT;
        let date2 = time.jd_tt - J2000_JD_TT;
        let t = time.julian_centuries_tt();

        let precession = precession_matrix_from_jd_tt(date1, date2);
        let (dpsi, deps) = nutation_from_julian_centuries_tt(t);
        let nutation = nutation_matrix_from_julian_centuries_tt(t, dpsi, deps);
        let precession_nutation = nutation * precession;

        let era = era_from_jd_ut1(time.jd_ut1);
        let earth_rotation = DMat3::from_rotation_z(era);

        let lmst = time.lmst(observer.longitude_rad);
        let cirs_to_enu = cirs_to_enu_matrix(lmst, observer.latitude_rad);
        let observer_rotation = cirs_to_enu * earth_rotation.transpose();

        Self {
            precession_nutation,
            earth_rotation,
            observer_rotation,
            aberration_delta: DVec3::ZERO,
            time,
            observer,
        }
    }

    /// Combined geometric rotation: ICRS unit vector → ENU (east, north, up).
    #[inline]
    pub fn icrs_to_horizontal(&self) -> DMat3 {
        self.observer_rotation * self.earth_rotation * self.precession_nutation
    }

    /// Transform an ICRS direction to geometric (unrefracted) horizontal coordinates.
    ///
    /// Uses CIRS intermediate coordinates and local sidereal time (ERA is folded into LMST).
    #[inline]
    pub fn icrs_to_geometric_horizontal(&self, direction_icrs: DVec3) -> HorizontalCoords {
        let dir_cirs = (self.precession_nutation * direction_icrs.normalize()).normalize();
        let (ra, dec) = direction_to_ra_dec(dir_cirs);
        let hour_angle = self
            .time
            .lmst(self.observer.longitude_rad)
            .rem_euclid(std::f64::consts::TAU)
            - ra;
        hadec_to_horizontal(hour_angle, dec, self.observer.latitude_rad)
    }

    /// Transform an ICRS direction to apparent horizontal coordinates (adds refraction).
    pub fn icrs_to_apparent_horizontal(
        &self,
        direction_icrs: DVec3,
    ) -> Result<HorizontalCoords, RefractionError> {
        let mut h = self.icrs_to_geometric_horizontal(direction_icrs);
        let alt_deg = h.altitude_rad.to_degrees();
        h.altitude_rad = true_to_apparent_altitude(
            alt_deg,
            f64::from(self.observer.pressure_hpa),
            f64::from(self.observer.temperature_c),
        )?
        .to_radians();
        Ok(h)
    }

    /// Epoch used to build this chain.
    #[inline]
    pub fn time(&self) -> AstroTime {
        self.time
    }

    /// Observer used to build this chain.
    #[inline]
    pub fn observer(&self) -> Observer {
        self.observer
    }
}

/// CIRS → ENU at east-positive latitude `latitude_rad` and local mean sidereal time `lmst`.
fn cirs_to_enu_matrix(lmst: f64, latitude_rad: f64) -> DMat3 {
    DMat3::from_cols(
        cirs_direction_to_enu(DVec3::X, lmst, latitude_rad),
        cirs_direction_to_enu(DVec3::Y, lmst, latitude_rad),
        cirs_direction_to_enu(DVec3::Z, lmst, latitude_rad),
    )
}

/// Map a CIRS direction to its ENU unit vector via HA/Dec.
fn cirs_direction_to_enu(direction_cirs: DVec3, lmst: f64, latitude_rad: f64) -> DVec3 {
    let (ra, dec) = direction_to_ra_dec(direction_cirs);
    let hour_angle = lmst.rem_euclid(std::f64::consts::TAU) - ra;
    horizontal_to_enu(hadec_to_horizontal(hour_angle, dec, latitude_rad))
}

/// Horizontal coordinates → ENU unit vector (east, north, up).
fn horizontal_to_enu(horizontal: HorizontalCoords) -> DVec3 {
    let (sin_az, cos_az) = horizontal.azimuth_rad.sin_cos();
    let (sin_alt, cos_alt) = horizontal.altitude_rad.sin_cos();
    DVec3::new(cos_alt * sin_az, cos_alt * cos_az, sin_alt)
}

/// True equator-of-date unit vector → (RA, Dec) in radians.
fn direction_to_ra_dec(direction: DVec3) -> (f64, f64) {
    let d = direction.normalize();
    let ra = d.y.atan2(d.x).rem_euclid(std::f64::consts::TAU);
    let dec = d.z.clamp(-1.0, 1.0).asin();
    (ra, dec)
}

/// Hour angle / declination / latitude → geometric altitude and azimuth (radians).
///
/// Matches `CelestialCoordinate.toHorizontal` in Dart and SOFA `eraAe2hd` conventions
/// (azimuth north through east).
fn hadec_to_horizontal(hour_angle_rad: f64, dec_rad: f64, latitude_rad: f64) -> HorizontalCoords {
    let (sin_ha, cos_ha) = hour_angle_rad.sin_cos();
    let (sin_dec, cos_dec) = dec_rad.sin_cos();
    let (sin_lat, cos_lat) = latitude_rad.sin_cos();

    let sin_alt = sin_dec * sin_lat + cos_dec * cos_lat * cos_ha;
    let altitude_rad = sin_alt.clamp(-1.0, 1.0).asin();

    let y = -sin_ha * cos_dec;
    let x = sin_dec * cos_lat - cos_dec * sin_lat * cos_ha;
    let azimuth_rad = y.atan2(x).rem_euclid(std::f64::consts::TAU);

    HorizontalCoords {
        altitude_rad,
        azimuth_rad,
    }
}

/// ENU unit vector → altitude and azimuth (north-referenced, east-positive).
#[inline]
fn enu_to_horizontal(enu: DVec3) -> HorizontalCoords {
    let east = enu.x;
    let north = enu.y;
    let up = enu.z.clamp(-1.0, 1.0);
    HorizontalCoords {
        altitude_rad: up.asin(),
        azimuth_rad: east.atan2(north).rem_euclid(std::f64::consts::TAU),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::AstroTime;

    const POLE: DVec3 = DVec3::new(0.0, 0.0, 1.0);

    #[test]
    fn matrix_chain_matches_hadec_for_celestial_pole() {
        let time = AstroTime::from_jd_utc(2_451_545.0);
        let observer = Observer {
            latitude_rad: 0.7,
            longitude_rad: -1.2,
            ..Observer::default()
        };
        let chain = FrameChain::build(time, observer);
        let hadec = chain.icrs_to_geometric_horizontal(POLE);
        let enu = (chain.icrs_to_horizontal() * POLE).normalize();
        let matrix = enu_to_horizontal(enu);
        assert!((hadec.altitude_rad - matrix.altitude_rad).abs() < 1e-10);
        assert!((hadec.azimuth_rad - matrix.azimuth_rad).abs() < 1e-10);
    }
}
