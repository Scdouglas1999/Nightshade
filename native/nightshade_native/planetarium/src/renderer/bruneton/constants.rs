//! Bruneton 2020 precomputed texture dimensions (public `atmosphere/constants.h`).

/// Transmittance LUT width.
pub const TRANSMITTANCE_TEXTURE_WIDTH: u32 = 256;
/// Transmittance LUT height.
pub const TRANSMITTANCE_TEXTURE_HEIGHT: u32 = 64;

/// Scattering LUT depth (altitude).
pub const SCATTERING_TEXTURE_R_SIZE: u32 = 32;
/// Scattering LUT height (view zenith).
pub const SCATTERING_TEXTURE_MU_SIZE: u32 = 128;
/// Scattering LUT width factor (sun zenith).
pub const SCATTERING_TEXTURE_MU_S_SIZE: u32 = 32;
/// Scattering LUT width factor (view–sun angle).
pub const SCATTERING_TEXTURE_NU_SIZE: u32 = 8;

/// Scattering 3D width (`NU * MU_S`).
pub const SCATTERING_TEXTURE_WIDTH: u32 = SCATTERING_TEXTURE_NU_SIZE * SCATTERING_TEXTURE_MU_S_SIZE;
/// Scattering 3D height.
pub const SCATTERING_TEXTURE_HEIGHT: u32 = SCATTERING_TEXTURE_MU_SIZE;
/// Scattering 3D depth.
pub const SCATTERING_TEXTURE_DEPTH: u32 = SCATTERING_TEXTURE_R_SIZE;

/// Irradiance LUT width.
pub const IRRADIANCE_TEXTURE_WIDTH: u32 = 64;
/// Irradiance LUT height.
pub const IRRADIANCE_TEXTURE_HEIGHT: u32 = 16;

/// Default number of scattering orders (Bruneton `Model::Init` default).
pub const DEFAULT_SCATTERING_ORDERS: u32 = 4;

/// RGB wavelengths used for 3-wavelength radiance precompute (nm).
pub const LAMBDA_R: f64 = 680.0;
pub const LAMBDA_G: f64 = 550.0;
pub const LAMBDA_B: f64 = 440.0;

/// Max luminous efficacy (lm/W).
pub const MAX_LUMINOUS_EFFICACY: f64 = 683.0;

/// XYZ → linear sRGB (Bruneton `constants.h`).
pub const XYZ_TO_SRGB: [f64; 9] = [
    3.2406, -1.5372, -0.4986, -0.9689, 1.8758, 0.0415, 0.0557, -0.2040, 1.0570,
];
