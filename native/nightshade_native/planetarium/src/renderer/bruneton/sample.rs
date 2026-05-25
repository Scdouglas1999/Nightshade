//! CPU sampling helpers for LUT validation (mirrors Bruneton texture coordinate mapping).

use super::constants::{
    TRANSMITTANCE_TEXTURE_HEIGHT, TRANSMITTANCE_TEXTURE_WIDTH,
};
use super::params::PrecomputeConfig;

/// Map atmosphere `(r, mu)` to transmittance LUT normalized UV (Bruneton `GetTransmittanceTextureUvFromRMu`).
#[must_use]
pub fn transmittance_uv_from_r_mu(config: &PrecomputeConfig, r_km: f64, mu: f64) -> (f64, f64) {
    let bottom = config.bottom_radius_m / config.length_unit_in_meters;
    let top = config.top_radius_m / config.length_unit_in_meters;
    assert!(r_km >= bottom && r_km <= top);
    assert!((-1.0..=1.0).contains(&mu));

    let h = (top * top - bottom * bottom).sqrt();
    let rho = (r_km * r_km - bottom * bottom).max(0.0).sqrt();
    let d = distance_to_top(r_km, mu, bottom, top);
    let d_min = top - r_km;
    let d_max = rho + h;
    let x_mu = (d - d_min) / (d_max - d_min);
    let x_r = rho / h;
    (
        unit_to_tex_coord(x_mu, TRANSMITTANCE_TEXTURE_WIDTH),
        unit_to_tex_coord(x_r, TRANSMITTANCE_TEXTURE_HEIGHT),
    )
}

fn distance_to_top(r: f64, mu: f64, bottom: f64, top: f64) -> f64 {
    let discriminant = r * r * (mu * mu - 1.0) + top * top;
    (-r * mu + discriminant.max(0.0).sqrt()).max(0.0)
}

fn unit_to_tex_coord(unit: f64, size: u32) -> f64 {
    ((0.5 / f64::from(size)) + unit * (1.0 - 1.0 / f64::from(size))).clamp(0.0, 1.0)
}

/// Bilinear sample of a row-major `width × height` RGBA f32 LUT.
#[must_use]
pub fn sample_transmittance_rgba(
    data: &[f32],
    width: u32,
    height: u32,
    u: f64,
    v: f64,
) -> [f32; 4] {
    let fx = u * f64::from(width - 1);
    let fy = v * f64::from(height - 1);
    let x0 = fx.floor() as u32;
    let y0 = fy.floor() as u32;
    let x1 = (x0 + 1).min(width - 1);
    let y1 = (y0 + 1).min(height - 1);
    let tx = (fx - f64::from(x0)) as f32;
    let ty = (fy - f64::from(y0)) as f32;

    let c00 = pixel(data, width, x0, y0);
    let c10 = pixel(data, width, x1, y0);
    let c01 = pixel(data, width, x0, y1);
    let c11 = pixel(data, width, x1, y1);
    lerp4(lerp4(c00, c10, tx), lerp4(c01, c11, tx), ty)
}

fn pixel(data: &[f32], width: u32, x: u32, y: u32) -> [f32; 4] {
    let i = ((y * width + x) * 4) as usize;
    [data[i], data[i + 1], data[i + 2], data[i + 3]]
}

fn lerp4(a: [f32; 4], b: [f32; 4], t: f32) -> [f32; 4] {
    [
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    ]
}
