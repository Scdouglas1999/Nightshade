//! Earth atmosphere parameters and GLSL header generation (Bruneton demo defaults).

use super::constants::{
    IRRADIANCE_TEXTURE_HEIGHT, IRRADIANCE_TEXTURE_WIDTH, LAMBDA_B, LAMBDA_G, LAMBDA_R,
    MAX_LUMINOUS_EFFICACY, SCATTERING_TEXTURE_DEPTH, SCATTERING_TEXTURE_HEIGHT,
    SCATTERING_TEXTURE_MU_SIZE, SCATTERING_TEXTURE_MU_S_SIZE, SCATTERING_TEXTURE_NU_SIZE,
    SCATTERING_TEXTURE_R_SIZE, SCATTERING_TEXTURE_WIDTH, TRANSMITTANCE_TEXTURE_HEIGHT,
    TRANSMITTANCE_TEXTURE_WIDTH,
};

/// Configuration for Bruneton LUT precomputation.
#[derive(Debug, Clone)]
pub struct PrecomputeConfig {
    /// Pack Rayleigh + multiple + Mie-R into one scattering texture (demo default).
    pub combine_scattering_textures: bool,
    /// Use 16-bit float textures where supported.
    pub half_precision: bool,
    /// Planet radius at sea level in meters.
    pub bottom_radius_m: f64,
    /// Top of atmosphere radius in meters.
    pub top_radius_m: f64,
    /// Shader length unit in meters (demo uses 1000 = km).
    pub length_unit_in_meters: f64,
}

impl Default for PrecomputeConfig {
    fn default() -> Self {
        Self {
            combine_scattering_textures: true,
            half_precision: true,
            bottom_radius_m: 6_360_000.0,
            top_radius_m: 6_420_000.0,
            length_unit_in_meters: 1_000.0,
        }
    }
}

/// Demo-equivalent Earth atmosphere used for precompute and reference LUT tests.
impl PrecomputeConfig {
    /// Matches `atmosphere/demo/demo.cc` `InitModel` (realistic solar, ozone, combined textures).
    #[must_use]
    pub fn earth_demo() -> Self {
        Self::default()
    }
}

/// GLSL `AtmosphereParameters` header for the three RGB wavelengths.
#[must_use]
pub fn glsl_atmosphere_header(config: &PrecomputeConfig) -> String {
    let lambdas = [LAMBDA_R, LAMBDA_G, LAMBDA_B];
    let spectra = build_demo_spectra();
    let sky_k = spectral_radiance_to_luminance_factors(
        &spectra.wavelengths,
        &spectra.solar_irradiance,
        -3.0,
        &lambdas,
    );
    let sun_k = spectral_radiance_to_luminance_factors(
        &spectra.wavelengths,
        &spectra.solar_irradiance,
        0.0,
        &lambdas,
    );

    let max_sun_zenith = if config.half_precision {
        102.0_f64.to_radians()
    } else {
        120.0_f64.to_radians()
    };

    let unit = config.length_unit_in_meters;
    let bottom = config.bottom_radius_m / unit;
    let top = config.top_radius_m / unit;

    let combined = if config.combine_scattering_textures {
        "#define COMBINED_SCATTERING_TEXTURES\n"
    } else {
        ""
    };

    format!(
        r#"{combined}const int TRANSMITTANCE_TEXTURE_WIDTH = {TRANSMITTANCE_TEXTURE_WIDTH};
const int TRANSMITTANCE_TEXTURE_HEIGHT = {TRANSMITTANCE_TEXTURE_HEIGHT};
const int SCATTERING_TEXTURE_R_SIZE = {SCATTERING_TEXTURE_R_SIZE};
const int SCATTERING_TEXTURE_MU_SIZE = {SCATTERING_TEXTURE_MU_SIZE};
const int SCATTERING_TEXTURE_MU_S_SIZE = {SCATTERING_TEXTURE_MU_S_SIZE};
const int SCATTERING_TEXTURE_NU_SIZE = {SCATTERING_TEXTURE_NU_SIZE};
const int IRRADIANCE_TEXTURE_WIDTH = {IRRADIANCE_TEXTURE_WIDTH};
const int IRRADIANCE_TEXTURE_HEIGHT = {IRRADIANCE_TEXTURE_HEIGHT};
const AtmosphereParameters ATMOSPHERE = AtmosphereParameters(
  {solar_irradiance},
  {sun_angular_radius},
  {bottom},
  {top},
  {rayleigh_density},
  {rayleigh_scattering},
  {mie_density},
  {mie_scattering},
  {mie_extinction},
  {mie_g},
  {absorption_density},
  {absorption_extinction},
  {ground_albedo},
  {mu_s_min});
const vec3 SKY_SPECTRAL_RADIANCE_TO_LUMINANCE = vec3({sky_r},{sky_g},{sky_b});
const vec3 SUN_SPECTRAL_RADIANCE_TO_LUMINANCE = vec3({sun_r},{sun_g},{sun_b});
"#,
        combined = combined,
        solar_irradiance = vec3_at_lambdas(
            &spectra.wavelengths,
            &spectra.solar_irradiance,
            &lambdas,
            1.0,
        ),
        sun_angular_radius = 0.00935 / 2.0,
        bottom = bottom,
        top = top,
        rayleigh_density = density_profile(&[rayleigh_layer()], unit),
        rayleigh_scattering = vec3_at_lambdas(
            &spectra.wavelengths,
            &spectra.rayleigh_scattering,
            &lambdas,
            unit,
        ),
        mie_density = density_profile(&[mie_layer()], unit),
        mie_scattering = vec3_at_lambdas(
            &spectra.wavelengths,
            &spectra.mie_scattering,
            &lambdas,
            unit,
        ),
        mie_extinction = vec3_at_lambdas(
            &spectra.wavelengths,
            &spectra.mie_extinction,
            &lambdas,
            unit,
        ),
        mie_g = 0.8,
        absorption_density = density_profile(&[ozone_layer_low(), ozone_layer_high()], unit),
        absorption_extinction = vec3_at_lambdas(
            &spectra.wavelengths,
            &spectra.absorption_extinction,
            &lambdas,
            unit,
        ),
        ground_albedo =
            vec3_at_lambdas(&spectra.wavelengths, &spectra.ground_albedo, &lambdas, 1.0,),
        mu_s_min = max_sun_zenith.cos(),
        sky_r = sky_k[0],
        sky_g = sky_k[1],
        sky_b = sky_k[2],
        sun_r = sun_k[0],
        sun_g = sun_k[1],
        sun_b = sun_k[2],
    )
}

/// Identity `luminance_from_radiance` for 3-wavelength radiance precompute.
#[must_use]
pub fn luminance_from_radiance_identity() -> [[f32; 3]; 3] {
    [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
}

struct DemoSpectra {
    wavelengths: Vec<f64>,
    solar_irradiance: Vec<f64>,
    rayleigh_scattering: Vec<f64>,
    mie_scattering: Vec<f64>,
    mie_extinction: Vec<f64>,
    absorption_extinction: Vec<f64>,
    ground_albedo: Vec<f64>,
}

fn build_demo_spectra() -> DemoSpectra {
    const LAMBDA_MIN: i32 = 360;
    const LAMBDA_MAX: i32 = 830;
    const SOLAR: [f64; 48] = [
        1.11776, 1.14259, 1.01249, 1.14716, 1.72765, 1.73054, 1.6887, 1.61253, 1.91198, 2.03474,
        2.02042, 2.02212, 1.93377, 1.95809, 1.91686, 1.8298, 1.8685, 1.8931, 1.85149, 1.8504,
        1.8341, 1.8345, 1.8147, 1.78158, 1.7533, 1.6965, 1.68194, 1.64654, 1.6048, 1.52143,
        1.55622, 1.5113, 1.474, 1.4482, 1.41018, 1.36775, 1.34188, 1.31429, 1.28303, 1.26758,
        1.2367, 1.2082, 1.18737, 1.14683, 1.12362, 1.1058, 1.07124, 1.04992,
    ];
    const OZONE: [f64; 48] = [
        1.18e-27, 2.182e-28, 2.818e-28, 6.636e-28, 1.527e-27, 2.763e-27, 5.52e-27, 8.451e-27,
        1.582e-26, 2.316e-26, 3.669e-26, 4.924e-26, 7.752e-26, 9.016e-26, 1.48e-25, 1.602e-25,
        2.139e-25, 2.755e-25, 3.091e-25, 3.5e-25, 4.266e-25, 4.672e-25, 4.398e-25, 4.701e-25,
        5.019e-25, 4.305e-25, 3.74e-25, 3.215e-25, 2.662e-25, 2.238e-25, 1.852e-25, 1.473e-25,
        1.209e-25, 9.423e-26, 7.455e-26, 6.566e-26, 5.105e-26, 4.15e-26, 4.228e-26, 3.237e-26,
        2.451e-26, 2.801e-26, 2.534e-26, 1.624e-26, 1.465e-26, 2.078e-26, 1.383e-26, 7.105e-27,
    ];
    const RAYLEIGH: f64 = 1.24062e-6;
    const RAYLEIGH_H: f64 = 8000.0;
    const MIE_H: f64 = 1200.0;
    const MIE_BETA: f64 = 5.328e-3;
    const MIE_ALBEDO: f64 = 0.9;
    const DOBSON: f64 = 2.687e20;
    const MAX_OZONE: f64 = 300.0 * DOBSON / 15_000.0;

    let mut wavelengths = Vec::new();
    let mut solar_irradiance = Vec::new();
    let mut rayleigh_scattering = Vec::new();
    let mut mie_scattering = Vec::new();
    let mut mie_extinction = Vec::new();
    let mut absorption_extinction = Vec::new();
    let mut ground_albedo = Vec::new();

    for l in (LAMBDA_MIN..=LAMBDA_MAX).step_by(10) {
        let lambda_um = f64::from(l) * 1e-3;
        let mie = MIE_BETA / MIE_H * lambda_um.powf(0.0);
        wavelengths.push(f64::from(l));
        solar_irradiance.push(SOLAR[((l - LAMBDA_MIN) / 10) as usize]);
        rayleigh_scattering.push(RAYLEIGH * lambda_um.powi(-4));
        mie_scattering.push(mie * MIE_ALBEDO);
        mie_extinction.push(mie);
        absorption_extinction.push(MAX_OZONE * OZONE[((l - LAMBDA_MIN) / 10) as usize]);
        ground_albedo.push(0.1);
    }

    DemoSpectra {
        wavelengths,
        solar_irradiance,
        rayleigh_scattering,
        mie_scattering,
        mie_extinction,
        absorption_extinction,
        ground_albedo,
    }
}

fn vec3_at_lambdas(wavelengths: &[f64], values: &[f64], lambdas: &[f64; 3], scale: f64) -> String {
    let r = interpolate(wavelengths, values, lambdas[0]) * scale;
    let g = interpolate(wavelengths, values, lambdas[1]) * scale;
    let b = interpolate(wavelengths, values, lambdas[2]) * scale;
    format!("vec3({r},{g},{b})")
}

fn density_profile(layers: &[DensityLayer], length_unit_m: f64) -> String {
    let mut parts = Vec::new();
    for layer in layers {
        parts.push(format!(
            "DensityProfileLayer({},{},{},{},{})",
            layer.width / length_unit_m,
            layer.exp_term,
            layer.exp_scale * length_unit_m,
            layer.linear_term * length_unit_m,
            layer.constant_term
        ));
    }
    while parts.len() < 2 {
        parts.insert(0, "DensityProfileLayer(0,0,0,0,0)".to_string());
    }
    format!(
        "DensityProfile(DensityProfileLayer[2]({},{}))",
        parts[0], parts[1]
    )
}

struct DensityLayer {
    width: f64,
    exp_term: f64,
    exp_scale: f64,
    linear_term: f64,
    constant_term: f64,
}

fn rayleigh_layer() -> DensityLayer {
    DensityLayer {
        width: 0.0,
        exp_term: 1.0,
        exp_scale: -1.0 / 8000.0,
        linear_term: 0.0,
        constant_term: 0.0,
    }
}

fn mie_layer() -> DensityLayer {
    DensityLayer {
        width: 0.0,
        exp_term: 1.0,
        exp_scale: -1.0 / 1200.0,
        linear_term: 0.0,
        constant_term: 0.0,
    }
}

fn ozone_layer_low() -> DensityLayer {
    DensityLayer {
        width: 25_000.0,
        exp_term: 0.0,
        exp_scale: 0.0,
        linear_term: 1.0 / 15.0,
        constant_term: -2.0 / 3.0,
    }
}

fn ozone_layer_high() -> DensityLayer {
    DensityLayer {
        width: 0.0,
        exp_term: 0.0,
        exp_scale: 0.0,
        linear_term: -1.0 / 15.0,
        constant_term: 8.0 / 3.0,
    }
}

fn interpolate(wavelengths: &[f64], values: &[f64], wavelength: f64) -> f64 {
    assert_eq!(wavelengths.len(), values.len());
    if wavelength < wavelengths[0] {
        return values[0];
    }
    for i in 0..wavelengths.len() - 1 {
        if wavelength < wavelengths[i + 1] {
            let u = (wavelength - wavelengths[i]) / (wavelengths[i + 1] - wavelengths[i]);
            return values[i] * (1.0 - u) + values[i + 1] * u;
        }
    }
    *values.last().expect("non-empty spectrum")
}

fn spectral_radiance_to_luminance_factors(
    wavelengths: &[f64],
    solar_irradiance: &[f64],
    lambda_power: f64,
    lambdas: &[f64; 3],
) -> [f64; 3] {
    let solar = [
        interpolate(wavelengths, solar_irradiance, lambdas[0]),
        interpolate(wavelengths, solar_irradiance, lambdas[1]),
        interpolate(wavelengths, solar_irradiance, lambdas[2]),
    ];
    let mut k = [0.0; 3];
    let dlambda = 1.0;
    for lambda in (360..830).step_by(1) {
        let lambda = f64::from(lambda);
        let x = cie_matching(lambda, 1);
        let y = cie_matching(lambda, 2);
        let z = cie_matching(lambda, 3);
        let r_bar = super::constants::XYZ_TO_SRGB[0] * x
            + super::constants::XYZ_TO_SRGB[1] * y
            + super::constants::XYZ_TO_SRGB[2] * z;
        let g_bar = super::constants::XYZ_TO_SRGB[3] * x
            + super::constants::XYZ_TO_SRGB[4] * y
            + super::constants::XYZ_TO_SRGB[5] * z;
        let b_bar = super::constants::XYZ_TO_SRGB[6] * x
            + super::constants::XYZ_TO_SRGB[7] * y
            + super::constants::XYZ_TO_SRGB[8] * z;
        let irradiance = interpolate(wavelengths, solar_irradiance, lambda);
        k[0] += r_bar * irradiance / solar[0] * (lambda / lambdas[0]).powf(lambda_power);
        k[1] += g_bar * irradiance / solar[1] * (lambda / lambdas[1]).powf(lambda_power);
        k[2] += b_bar * irradiance / solar[2] * (lambda / lambdas[2]).powf(lambda_power);
    }
    k[0] *= MAX_LUMINOUS_EFFICACY * dlambda;
    k[1] *= MAX_LUMINOUS_EFFICACY * dlambda;
    k[2] *= MAX_LUMINOUS_EFFICACY * dlambda;
    k
}

fn cie_matching(wavelength: f64, column: usize) -> f64 {
    const TABLE: [f64; 95 * 4] = [
        360.0,
        0.000129900000,
        0.000003917000,
        0.000606100000,
        365.0,
        0.000232100000,
        0.000006965000,
        0.001086000000,
        370.0,
        0.000414900000,
        0.000012390000,
        0.001946000000,
        375.0,
        0.000741600000,
        0.000022020000,
        0.003486000000,
        380.0,
        0.001368000000,
        0.000039000000,
        0.006450001000,
        385.0,
        0.002236000000,
        0.000064000000,
        0.010549990000,
        390.0,
        0.004243000000,
        0.000120000000,
        0.020050010000,
        395.0,
        0.007650000000,
        0.000217000000,
        0.036210000000,
        400.0,
        0.014310000000,
        0.000396000000,
        0.067850010000,
        405.0,
        0.023190000000,
        0.000640000000,
        0.110200000000,
        410.0,
        0.043510000000,
        0.001210000000,
        0.207400000000,
        415.0,
        0.077630000000,
        0.002180000000,
        0.371300000000,
        420.0,
        0.134380000000,
        0.004000000000,
        0.645600000000,
        425.0,
        0.214770000000,
        0.007300000000,
        1.039050100000,
        430.0,
        0.283900000000,
        0.011600000000,
        1.385600000000,
        435.0,
        0.328500000000,
        0.016840000000,
        1.622960000000,
        440.0,
        0.348280000000,
        0.023000000000,
        1.747060000000,
        445.0,
        0.348060000000,
        0.029800000000,
        1.782600000000,
        450.0,
        0.336200000000,
        0.038000000000,
        1.772110000000,
        455.0,
        0.318700000000,
        0.048000000000,
        1.744100000000,
        460.0,
        0.290800000000,
        0.060000000000,
        1.669200000000,
        465.0,
        0.251100000000,
        0.073900000000,
        1.528100000000,
        470.0,
        0.195360000000,
        0.090980000000,
        1.287640000000,
        475.0,
        0.142100000000,
        0.112600000000,
        1.041900000000,
        480.0,
        0.095640000000,
        0.139020000000,
        0.812950100000,
        485.0,
        0.057950010000,
        0.169300000000,
        0.616200000000,
        490.0,
        0.032010000000,
        0.208020000000,
        0.465180000000,
        495.0,
        0.014700000000,
        0.258600000000,
        0.353300000000,
        500.0,
        0.004900000000,
        0.323000000000,
        0.272000000000,
        505.0,
        0.002400000000,
        0.407300000000,
        0.212300000000,
        510.0,
        0.009300000000,
        0.503000000000,
        0.158200000000,
        515.0,
        0.029100000000,
        0.608200000000,
        0.111700000000,
        520.0,
        0.063270000000,
        0.710000000000,
        0.078249990000,
        525.0,
        0.109600000000,
        0.793200000000,
        0.057250010000,
        530.0,
        0.165500000000,
        0.862000000000,
        0.042160000000,
        535.0,
        0.225749900000,
        0.914850100000,
        0.029840000000,
        540.0,
        0.290400000000,
        0.954000000000,
        0.020300000000,
        545.0,
        0.359700000000,
        0.980300000000,
        0.013400000000,
        550.0,
        0.433449900000,
        0.994950100000,
        0.008749999000,
        555.0,
        0.512050100000,
        1.000000000000,
        0.005749999000,
        560.0,
        0.594500000000,
        0.995000000000,
        0.003900000000,
        565.0,
        0.678400000000,
        0.978600000000,
        0.002749999000,
        570.0,
        0.762100000000,
        0.952000000000,
        0.002100000000,
        575.0,
        0.842500000000,
        0.915400000000,
        0.001800000000,
        580.0,
        0.916300000000,
        0.870000000000,
        0.001650001000,
        585.0,
        0.978600000000,
        0.816300000000,
        0.001400000000,
        590.0,
        1.026300000000,
        0.757000000000,
        0.001100000000,
        595.0,
        1.056700000000,
        0.694900000000,
        0.001000000000,
        600.0,
        1.062200000000,
        0.631000000000,
        0.000800000000,
        605.0,
        1.045600000000,
        0.566800000000,
        0.000600000000,
        610.0,
        1.002600000000,
        0.503000000000,
        0.000340000000,
        615.0,
        0.938400000000,
        0.441200000000,
        0.000240000000,
        620.0,
        0.854449900000,
        0.381000000000,
        0.000190000000,
        625.0,
        0.751400000000,
        0.321000000000,
        0.000100000000,
        630.0,
        0.642400000000,
        0.265000000000,
        0.000049999990,
        635.0,
        0.541900000000,
        0.217000000000,
        0.000030000000,
        640.0,
        0.447900000000,
        0.175000000000,
        0.000020000000,
        645.0,
        0.360800000000,
        0.138200000000,
        0.000010000000,
        650.0,
        0.283500000000,
        0.107000000000,
        0.000000000000,
        655.0,
        0.218700000000,
        0.081600000000,
        0.000000000000,
        660.0,
        0.164900000000,
        0.061000000000,
        0.000000000000,
        665.0,
        0.121200000000,
        0.044580000000,
        0.000000000000,
        670.0,
        0.087400000000,
        0.032000000000,
        0.000000000000,
        675.0,
        0.063600000000,
        0.023200000000,
        0.000000000000,
        680.0,
        0.046770000000,
        0.017000000000,
        0.000000000000,
        685.0,
        0.032900000000,
        0.011920000000,
        0.000000000000,
        690.0,
        0.022700000000,
        0.008210000000,
        0.000000000000,
        695.0,
        0.015840000000,
        0.005723000000,
        0.000000000000,
        700.0,
        0.011359160000,
        0.004102000000,
        0.000000000000,
        705.0,
        0.008110916000,
        0.002929000000,
        0.000000000000,
        710.0,
        0.005790346000,
        0.002091000000,
        0.000000000000,
        715.0,
        0.004109457000,
        0.001484000000,
        0.000000000000,
        720.0,
        0.002899327000,
        0.001047000000,
        0.000000000000,
        725.0,
        0.002049190000,
        0.000740000000,
        0.000000000000,
        730.0,
        0.001439971000,
        0.000520000000,
        0.000000000000,
        735.0,
        0.000999949300,
        0.000361100000,
        0.000000000000,
        740.0,
        0.000690078600,
        0.000249200000,
        0.000000000000,
        745.0,
        0.000476021300,
        0.000171900000,
        0.000000000000,
        750.0,
        0.000332301100,
        0.000120000000,
        0.000000000000,
        755.0,
        0.000234826100,
        0.000084800000,
        0.000000000000,
        760.0,
        0.000166150500,
        0.000060000000,
        0.000000000000,
        765.0,
        0.000117413000,
        0.000042400000,
        0.000000000000,
        770.0,
        0.000083075270,
        0.000030000000,
        0.000000000000,
        775.0,
        0.000058706520,
        0.000021200000,
        0.000000000000,
        780.0,
        0.000041509940,
        0.000014990000,
        0.000000000000,
        785.0,
        0.000029353260,
        0.000010600000,
        0.000000000000,
        790.0,
        0.000020673830,
        0.000007465700,
        0.000000000000,
        795.0,
        0.000014559770,
        0.000005257800,
        0.000000000000,
        800.0,
        0.000010253980,
        0.000003702900,
        0.000000000000,
        805.0,
        0.000007221456,
        0.000002607800,
        0.000000000000,
        810.0,
        0.000005085868,
        0.000001836600,
        0.000000000000,
        815.0,
        0.000003581652,
        0.000001293400,
        0.000000000000,
        820.0,
        0.000002522525,
        0.000000910930,
        0.000000000000,
        825.0,
        0.000001776509,
        0.000000641530,
        0.000000000000,
        830.0,
        0.000001251141,
        0.000000451810,
        0.000000000000,
    ];
    if wavelength <= 360.0 || wavelength >= 830.0 {
        return 0.0;
    }
    let u = (wavelength - 360.0) / 5.0;
    let row = u.floor() as usize;
    let t = u - row as f64;
    TABLE[row * 4 + column] * (1.0 - t) + TABLE[(row + 1) * 4 + column] * t
}
