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

/// (RA, Dec) in degrees → Cartesian unit vector (same convention as
/// `calculate_center_of_rotation`).
fn radec_to_unit(ra_deg: f64, dec_deg: f64) -> (f64, f64, f64) {
    let ra = ra_deg.to_radians();
    let dec = dec_deg.to_radians();
    (dec.cos() * ra.cos(), dec.cos() * ra.sin(), dec.sin())
}

/// Cartesian unit vector → (RA, Dec) in degrees, RA normalised to [0, 360).
fn unit_to_radec(v: (f64, f64, f64)) -> (f64, f64) {
    let dec = v.2.clamp(-1.0, 1.0).asin();
    let mut ra = v.1.atan2(v.0);
    if ra < 0.0 {
        ra += 2.0 * std::f64::consts::PI;
    }
    (ra.to_degrees(), dec.to_degrees())
}

/// Track the mount's mechanical axis through a live adjustment.
///
/// During the adjustment phase the operator turns the alt/az bolts, which
/// moves the whole mount head — both the optics and the mechanical rotation
/// axis — rigidly. The geodesic (minimal) rotation that carried the reference
/// star from its INITIAL solved position to its CURRENT solved position is
/// therefore the same rigid rotation that moved the axis (exact in the
/// small-angle limit, and convergent: the displayed error reaches zero exactly
/// when the live axis reaches the pole). Applying it to the measured initial
/// axis yields the LIVE axis.
///
/// P1-3: previously the adjustment loop recomputed the error from the FIXED
/// initial axis every frame, so the displayed error vector never responded to
/// the user's adjustments — they were aligning blind. Returns the live axis
/// (RA, Dec) in degrees.
pub(super) fn rotate_axis_by_star_motion(
    axis: (f64, f64),
    star_initial: (f64, f64),
    star_current: (f64, f64),
) -> (f64, f64) {
    let a = radec_to_unit(star_initial.0, star_initial.1);
    let b = radec_to_unit(star_current.0, star_current.1);
    let v = radec_to_unit(axis.0, axis.1);

    // Rotation taking a → b: axis k = (a × b) normalised, angle = atan2(|a×b|, a·b).
    let cross = (
        a.1 * b.2 - a.2 * b.1,
        a.2 * b.0 - a.0 * b.2,
        a.0 * b.1 - a.1 * b.0,
    );
    let cross_mag = (cross.0 * cross.0 + cross.1 * cross.1 + cross.2 * cross.2).sqrt();
    let dot = a.0 * b.0 + a.1 * b.1 + a.2 * b.2;

    // No appreciable motion (a ≈ b), or the degenerate antipodal case that
    // cannot arise from a small adjustment → leave the axis unchanged.
    if cross_mag < 1e-12 {
        return axis;
    }
    let k = (cross.0 / cross_mag, cross.1 / cross_mag, cross.2 / cross_mag);
    let angle = cross_mag.atan2(dot);
    let (sin_t, cos_t) = (angle.sin(), angle.cos());

    // Rodrigues' rotation: v_rot = v cosθ + (k × v) sinθ + k (k·v)(1 − cosθ).
    let kv = k.0 * v.0 + k.1 * v.1 + k.2 * v.2;
    let kxv = (
        k.1 * v.2 - k.2 * v.1,
        k.2 * v.0 - k.0 * v.2,
        k.0 * v.1 - k.1 * v.0,
    );
    let rotated = (
        v.0 * cos_t + kxv.0 * sin_t + k.0 * kv * (1.0 - cos_t),
        v.1 * cos_t + kxv.1 * sin_t + k.1 * kv * (1.0 - cos_t),
        v.2 * cos_t + kxv.2 * sin_t + k.2 * kv * (1.0 - cos_t),
    );
    unit_to_radec(rotated)
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

    #[test]
    fn rotate_axis_no_star_motion_leaves_axis_unchanged() {
        let axis = (10.0, 89.0);
        let (ra, dec) = rotate_axis_by_star_motion(axis, (5.0, 45.0), (5.0, 45.0));
        assert!((ra - axis.0).abs() < 1e-9, "ra {ra}");
        assert!((dec - axis.1).abs() < 1e-9, "dec {dec}");
    }

    #[test]
    fn rotate_axis_tracks_a_pure_polar_rotation() {
        // A reference star on the equator rotated 30° about the celestial pole
        // (Z axis) moves along a great circle, so the recovered geodesic
        // rotation IS the +30° Z-rotation. Applied to an axis at (50°, 80°) it
        // must add 30° of RA and leave Dec fixed.
        let (ra, dec) = rotate_axis_by_star_motion((50.0, 80.0), (0.0, 0.0), (30.0, 0.0));
        assert!((ra - 80.0).abs() < 1e-6, "ra {ra}");
        assert!((dec - 80.0).abs() < 1e-6, "dec {dec}");
    }
}
