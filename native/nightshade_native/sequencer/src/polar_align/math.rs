//! Math helpers for three-point polar alignment.
//!
//! Extracted from the original monolithic `polar_align.rs` so the
//! state machine and the celestial-mechanics formulas can be tested
//! independently. No behavior change.

/// Calculate centre of rotation from 3 points using 3D plane fitting.
///
/// The three solved (RA, Dec) points define a plane on the unit
/// sphere; the mount's mechanical axis is the normal to that plane.
/// Degenerate (collinear) inputs return `(0, 90)` as a safe default.
pub(super) fn calculate_center_of_rotation(points: &[(f64, f64)]) -> (f64, f64) {
    if points.len() < 3 {
        return (0.0, 90.0);
    }

    // Convert spherical (RA, Dec) to Cartesian unit vectors.
    let vectors: Vec<(f64, f64, f64)> = points
        .iter()
        .map(|(ra, dec)| {
            let ra_rad = ra.to_radians();
            let dec_rad = dec.to_radians();
            (
                dec_rad.cos() * ra_rad.cos(),
                dec_rad.cos() * ra_rad.sin(),
                dec_rad.sin(),
            )
        })
        .collect();

    // Normal n = (p2 - p1) x (p3 - p1).
    let p1 = vectors[0];
    let p2 = vectors[1];
    let p3 = vectors[2];
    let v1 = (p2.0 - p1.0, p2.1 - p1.1, p2.2 - p1.2);
    let v2 = (p3.0 - p1.0, p3.1 - p1.1, p3.2 - p1.2);
    let nx = v1.1 * v2.2 - v1.2 * v2.1;
    let ny = v1.2 * v2.0 - v1.0 * v2.2;
    let nz = v1.0 * v2.1 - v1.1 * v2.0;

    let mag = (nx * nx + ny * ny + nz * nz).sqrt();
    if mag < 1e-9 {
        return (0.0, 90.0);
    }

    let nx = nx / mag;
    let ny = ny / mag;
    let nz = nz / mag;

    let center_dec_rad = nz.asin();
    let mut center_ra_rad = ny.atan2(nx);
    if center_ra_rad < 0.0 {
        center_ra_rad += 2.0 * std::f64::consts::PI;
    }

    (center_ra_rad.to_degrees(), center_dec_rad.to_degrees())
}

/// Compute (Δaz, Δalt, total) alignment error in arcminutes from the
/// mechanical axis coordinates and observer location.
pub(super) fn calculate_alignment_error_arcmin(
    axis_ra_degrees: f64,
    axis_dec_degrees: f64,
    is_north: bool,
    observer_latitude: f64,
    observer_longitude: f64,
    when: chrono::DateTime<chrono::Utc>,
) -> (f64, f64, f64) {
    let (axis_altitude, axis_azimuth) = equatorial_to_horizontal(
        axis_ra_degrees,
        axis_dec_degrees,
        observer_latitude,
        observer_longitude,
        when,
    );

    let pole_altitude = if is_north {
        observer_latitude
    } else {
        -observer_latitude
    };
    let pole_azimuth = if is_north { 0.0 } else { 180.0 };

    let altitude_error_arcmin = (pole_altitude - axis_altitude) * 60.0;
    let azimuth_error_arcmin = normalize_signed_angle_degrees(pole_azimuth - axis_azimuth) * 60.0;
    let total_error_arcmin = (altitude_error_arcmin.powi(2) + azimuth_error_arcmin.powi(2)).sqrt();

    (
        azimuth_error_arcmin,
        altitude_error_arcmin,
        total_error_arcmin,
    )
}

fn equatorial_to_horizontal(
    ra_degrees: f64,
    dec_degrees: f64,
    observer_latitude: f64,
    observer_longitude: f64,
    when: chrono::DateTime<chrono::Utc>,
) -> (f64, f64) {
    let lst_hours = crate::local_sidereal_time(crate::julian_day(&when), observer_longitude);
    let hour_angle_rad = ((lst_hours * 15.0) - ra_degrees).to_radians();
    let dec_rad = dec_degrees.to_radians();
    let lat_rad = observer_latitude.to_radians();

    let altitude = (lat_rad.sin() * dec_rad.sin()
        + lat_rad.cos() * dec_rad.cos() * hour_angle_rad.cos())
    .asin();

    let azimuth = (-hour_angle_rad.sin() * dec_rad.cos())
        .atan2(dec_rad.sin() * lat_rad.cos() - dec_rad.cos() * lat_rad.sin() * hour_angle_rad.cos())
        .to_degrees()
        .rem_euclid(360.0);

    (altitude.to_degrees(), azimuth)
}

fn normalize_signed_angle_degrees(angle_degrees: f64) -> f64 {
    let wrapped = angle_degrees.rem_euclid(360.0);
    if wrapped > 180.0 {
        wrapped - 360.0
    } else {
        wrapped
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn test_calculate_center_of_rotation() {
        // Perfect rotation around pole (0, 90).
        let points = vec![(0.0, 89.0), (20.0, 89.0), (40.0, 89.0)];
        let (_ra, dec) = calculate_center_of_rotation(&points);
        assert!((dec - 90.0).abs() < 0.1);
    }

    #[test]
    fn test_alignment_error_zero_at_true_pole() {
        let when = chrono::Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap();
        let (az_error, alt_error, total_error) =
            calculate_alignment_error_arcmin(123.0, 90.0, true, 45.0, -122.0, when);
        assert!(az_error.abs() < 1e-6);
        assert!(alt_error.abs() < 1e-6);
        assert!(total_error.abs() < 1e-6);
    }
}
