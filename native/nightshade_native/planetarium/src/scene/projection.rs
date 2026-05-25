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
