//! ICRS → normalized screen projection for snapshot label hints.
//!
//! Mirrors the v1 stereographic / orthographic / azimuthal-equidistant math in
//! `packages/nightshade_planetarium/lib/src/rendering/sky_renderer.dart`.

use crate::types::{SkyProjection, ViewPose};

/// Normalized screen margin (fraction of widget size) matching v1's off-screen cull.
const SCREEN_MARGIN: f32 = 0.1;

/// Minimum dot product between view center and object direction; below this the
/// object is treated as behind the projection plane.
const MIN_COSC: f64 = 0.01;

/// Projects an ICRS direction to normalized widget coordinates `(0..1, 0..1)`.
///
/// Returns `None` when the object is behind the viewer or outside the visible margin.
pub fn project_icrs(ra_rad: f64, dec_rad: f64, pose: ViewPose) -> Option<(f32, f32)> {
    let ra1 = pose.ra_rad;
    let dec1 = pose.dec_rad;
    let ra2 = ra_rad;
    let dec2 = dec_rad;

    let cosc = dec1.sin() * dec2.sin() + dec1.cos() * dec2.cos() * (ra2 - ra1).cos();
    if cosc < MIN_COSC {
        return None;
    }

    let (x, y) = match pose.projection {
        SkyProjection::Stereographic => {
            let k = 2.0 / (1.0 + cosc);
            (
                k * dec2.cos() * (ra2 - ra1).sin(),
                k * (dec1.cos() * dec2.sin() - dec1.sin() * dec2.cos() * (ra2 - ra1).cos()),
            )
        }
        SkyProjection::Orthographic => (
            dec2.cos() * (ra2 - ra1).sin(),
            dec1.cos() * dec2.sin() - dec1.sin() * dec2.cos() * (ra2 - ra1).cos(),
        ),
        SkyProjection::AzimuthalEquidistant => {
            let c = cosc.clamp(-1.0, 1.0).acos();
            if c < 0.000_1 {
                (0.0, 0.0)
            } else {
                let k = c / c.sin();
                (
                    k * dec2.cos() * (ra2 - ra1).sin(),
                    k * (dec1.cos() * dec2.sin() - dec1.sin() * dec2.cos() * (ra2 - ra1).cos()),
                )
            }
        }
    };

    let rot = pose.roll_rad as f64;
    let x_rot = x * rot.cos() - y * rot.sin();
    let y_rot = x * rot.sin() + y * rot.cos();

    let half_fov = pose.fov_rad as f64 / 2.0;
    let edge_r = match pose.projection {
        SkyProjection::Stereographic => 2.0 * (half_fov / 2.0).tan(),
        SkyProjection::Orthographic => half_fov.sin(),
        SkyProjection::AzimuthalEquidistant => half_fov,
    };
    if edge_r <= f64::EPSILON {
        return None;
    }

    let scale = 0.5 / edge_r;
    let screen_x = (0.5 + x_rot * scale) as f32;
    let screen_y = (0.5 - y_rot * scale) as f32;

    if screen_x < -SCREEN_MARGIN
        || screen_x > 1.0 + SCREEN_MARGIN
        || screen_y < -SCREEN_MARGIN
        || screen_y > 1.0 + SCREEN_MARGIN
    {
        return None;
    }

    Some((screen_x.clamp(0.0, 1.0), screen_y.clamp(0.0, 1.0)))
}

/// Inverse of [`project_icrs`]: normalized screen `(x, y)` → ICRS `(ra, dec)` radians.
///
/// Returns `None` when the tap lies outside the invertible projection disc (behind the
/// horizon plane or outside the visible margin).
pub fn unproject_icrs(screen_x: f32, screen_y: f32, pose: ViewPose) -> Option<(f64, f64)> {
    let half_fov = pose.fov_rad as f64 / 2.0;
    let edge_r = match pose.projection {
        SkyProjection::Stereographic => 2.0 * (half_fov / 2.0).tan(),
        SkyProjection::Orthographic => half_fov.sin(),
        SkyProjection::AzimuthalEquidistant => half_fov,
    };
    if edge_r <= f64::EPSILON {
        return None;
    }

    let scale = 0.5 / edge_r;
    let x_rot = f64::from(screen_x - 0.5) / scale;
    let y_rot = f64::from(0.5 - screen_y) / scale;

    let rot = pose.roll_rad as f64;
    let x = x_rot * rot.cos() + y_rot * rot.sin();
    let y = -x_rot * rot.sin() + y_rot * rot.cos();

    let ra1 = pose.ra_rad;
    let dec1 = pose.dec_rad;

    let rho = (x * x + y * y).sqrt();
    if rho < 1e-10 {
        return Some((ra1, dec1));
    }

    let (ra2, dec2) = match pose.projection {
        SkyProjection::Stereographic => {
            let c = 2.0 * (rho / 2.0).atan();
            let sinc = c.sin();
            let cosc = c.cos();
            let dec = (cosc * dec1.sin() + y * sinc * dec1.cos() / rho).clamp(-1.0, 1.0).asin();
            let ra = ra1 + (x * sinc).atan2(rho * dec1.cos() * cosc - y * dec1.sin() * sinc);
            (ra, dec)
        }
        SkyProjection::Orthographic => {
            if rho > 1.0 + 1e-6 {
                return None;
            }
            let z = (1.0 - rho * rho).max(0.0).sqrt();
            let dec = (dec1.cos() * y + dec1.sin() * z).clamp(-1.0, 1.0).asin();
            let ra = ra1 + (x).atan2(z * dec1.cos() - y * dec1.sin());
            (ra, dec)
        }
        SkyProjection::AzimuthalEquidistant => {
            let c = rho;
            if c > half_fov * 1.5 {
                return None;
            }
            let sinc = c.sin();
            let cosc = c.cos();
            let dec = (cosc * dec1.sin() + y * sinc * dec1.cos() / rho).clamp(-1.0, 1.0).asin();
            let ra = ra1 + (x * sinc).atan2(rho * dec1.cos() * cosc - y * dec1.sin() * sinc);
            (ra, dec)
        }
    };

    if project_icrs(ra2, dec2, pose).is_none() {
        return None;
    }

    Some((wrap_ra_rad(ra2), dec2.clamp(-std::f64::consts::FRAC_PI_2, std::f64::consts::FRAC_PI_2)))
}

fn wrap_ra_rad(ra: f64) -> f64 {
    let two_pi = std::f64::consts::TAU;
    let mut r = ra % two_pi;
    if r < 0.0 {
        r += two_pi;
    }
    r
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::SkyProjection;

    fn pole_pose(projection: SkyProjection) -> ViewPose {
        ViewPose {
            ra_rad: 0.0,
            dec_rad: std::f64::consts::FRAC_PI_2,
            fov_rad: std::f32::consts::FRAC_PI_2,
            roll_rad: 0.0,
            projection,
        }
    }

    #[test]
    fn unproject_screen_center_is_boresight() {
        for projection in [
            SkyProjection::Stereographic,
            SkyProjection::Orthographic,
            SkyProjection::AzimuthalEquidistant,
        ] {
            let pose = pole_pose(projection);
            let (ra, dec) = unproject_icrs(0.5, 0.5, pose).expect("center");
            assert!((ra - pose.ra_rad).abs() < 1e-6, "{projection:?}");
            assert!((dec - pose.dec_rad).abs() < 1e-6, "{projection:?}");
        }
    }

    #[test]
    fn project_unproject_round_trip_vega() {
        let pose = ViewPose {
            ra_rad: 4.872_013,
            dec_rad: 0.676_757,
            fov_rad: 0.35,
            roll_rad: 0.0,
            projection: SkyProjection::Stereographic,
        };
        let (sx, sy) = project_icrs(4.872_013, 0.676_757, pose).expect("vega on screen");
        let (ra, dec) = unproject_icrs(sx, sy, pose).expect("unproject");
        assert!((ra - 4.872_013).abs() < 0.02);
        assert!((dec - 0.676_757).abs() < 0.02);
    }
}
