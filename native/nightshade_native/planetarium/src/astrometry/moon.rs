//! ELP2000-82B geocentric Moon (truncated main problem, ~50 terms).
//!
//! Semi-analytical lunar theory of Chapront-Touzé & Chapront (CDS VI/79). This module
//! evaluates the **Main Problem** Fourier/Poisson series with the 50 largest-amplitude
//! terms (20 longitude, 15 latitude, 15 distance) from the published coefficient tables.
//!
//! Output frame: mean dynamical ecliptic and equinox of J2000 (ELP internal frame).
//! Longitude includes mean mean longitude *W*₁; values are normalized to \[0, 360°).
//!
//! Visual-grade accuracy: ~1′ vs the full main-problem series; sub-arcminute at J2000.0
//! against low-precision almanac ephemerides.
//!
//! INTEGRATE: add `pub mod moon;` to `astrometry/mod.rs`.

/// J2000.0 epoch in TT (matches `time::J2000_JD_TT`).
pub const MOON_J2000_JD_TT: f64 = 2_451_545.0;

/// Days per Julian century (matches `time::DAYS_PER_JULIAN_CENTURY`).
pub const DAYS_PER_JULIAN_CENTURY: f64 = 36_525.0;

/// Arcseconds in a full circle (360°).
pub const ARCSEC_PER_CIRCLE: f64 = 1_296_000.0;

/// π arcseconds (ELP angular unit conversion).
const ARCSEC_PER_PI: f64 = 648_000.0;

/// Radians per arcsecond.
const ARCSEC_TO_RAD: f64 = std::f64::consts::PI / ARCSEC_PER_PI;

/// Number of retained main-problem terms (20 + 15 + 15).
pub const TRUNCATED_TERM_COUNT: usize = 50;

/// Geocentric ecliptic position in the ELP2000-82B mean J2000 frame.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MoonEclipticJ2000 {
    /// Ecliptic longitude (degrees, normalized 0 ≤ λ < 360).
    pub longitude_deg: f64,
    /// Ecliptic latitude (degrees).
    pub latitude_deg: f64,
    /// Geocentric distance (km).
    pub distance_km: f64,
}

/// Geocentric equatorial position (mean equator/equinox of J2000).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MoonEquatorialJ2000 {
    /// Right ascension (radians, 0 ≤ α < 2π).
    pub ra_rad: f64,
    /// Declination (radians).
    pub dec_rad: f64,
    /// Geocentric distance (km).
    pub distance_km: f64,
}

/// ELP2000 argument index: *W*₁ (mean mean longitude).
const W1: usize = 0;
/// Mean longitude of lunar perigee *W*₂.
const W2: usize = 1;
/// Mean longitude of ascending node *W*₃.
const W3: usize = 2;
/// Mean heliocentric longitude of Earth–Moon barycenter *T*.
const T: usize = 3;
/// Mean longitude of Earth–Moon perigee ϖ′.
const OBP: usize = 4;

/// Polynomial coefficients for ELP arguments (arcseconds); CDS VI/79 p. 10.
const ELP_ARGUMENT_COEFFS: [[f64; 5]; 5] = [
    [785_939.955_71, 1_732_559_343.736_04, -5.888_3, 0.006_604, -3.169e-5],
    [300_071.674_75, 14_643_420.263_2, -38.277_6, -0.045_047, 2.130_1e-4],
    [450_160.398_16, -6_967_919.362_2, 6.362_2, 0.007_625, -3.586e-5],
    [361_679.220_59, 129_597_742.275_8, -0.020_2, 9.0e-6, 1.5e-7],
    [370_574.427_53, 1_161.228_3, 0.532_7, -1.38e-4, 0.0],
];

/// Delaunay index: *D* = *W*₁ − *T* + π.
const D: usize = 0;
/// *l*′ = *T* − ϖ′.
const LP: usize = 1;
/// *l* = *W*₁ − *W*₂.
const L: usize = 2;
/// *F* = *W*₁ − *W*₃.
const F: usize = 3;

/// Main-problem term: Σ *A* sin\|cos\(*i*₁*D* + *i*₂*l*′ + *i*₃*l* + *i*₄*F*).
#[derive(Clone, Copy)]
struct TruncatedTerm {
    i_d: i8,
    i_lp: i8,
    i_l: i8,
    i_f: i8,
    amplitude_arcsec: f64,
    use_cosine: bool,
}

/// Longitude series (sin); 20 largest |*A*| terms.
const LONGITUDE_TERMS: [TruncatedTerm; 20] = [
    term(0, 0, 1, 0, 22_639.55, false),
    term(2, 0, -1, 0, 4_586.430_61, false),
    term(2, 0, 0, 0, 2_369.912_27, false),
    term(0, 0, 2, 0, 769.023_26, false),
    term(0, 1, 0, 0, -666.441_86, false),
    term(0, 0, 0, 2, -411.602_87, false),
    term(2, 0, -2, 0, 211.654_87, false),
    term(2, -1, -1, 0, 205.443_15, false),
    term(2, 0, 1, 0, 191.955_75, false),
    term(2, -1, 0, 0, 164.734_58, false),
    term(0, 1, -1, 0, -147.326_54, false),
    term(1, 0, 0, 0, -124.988_06, false),
    term(0, 1, 1, 0, -109.384_19, false),
    term(2, 0, 0, -2, 55.178_01, false),
    term(0, 0, 1, 2, -45.100_32, false),
    term(0, 0, 1, -2, 39.533_93, false),
    term(4, 0, -1, 0, 38.429_74, false),
    term(0, 0, 3, 0, 36.123_64, false),
    term(4, 0, -2, 0, 30.772_47, false),
    term(2, 1, -1, 0, -28.398_1, false),
];

/// Latitude series (sin); 15 largest |*A*| terms.
const LATITUDE_TERMS: [TruncatedTerm; 15] = [
    term(0, 0, 0, 1, 18_461.4, false),
    term(0, 0, 1, 1, 1_010.174_3, false),
    term(0, 0, 1, -1, 999.700_79, false),
    term(2, 0, 0, -1, 623.657_83, false),
    term(2, 0, -1, 1, 199.485_15, false),
    term(2, 0, -1, -1, 166.575_28, false),
    term(2, 0, 0, 1, 117.261_61, false),
    term(0, 0, 2, 1, 61.912_29, false),
    term(2, 0, 1, -1, 33.357_43, false),
    term(0, 0, 2, -1, 31.759_85, false),
    term(2, -1, 0, -1, 29.577_94, false),
    term(2, 0, -2, -1, 15.566_35, false),
    term(2, 0, 1, 1, 15.121_65, false),
    term(2, 1, 0, -1, -12.094_7, false),
    term(2, -1, -1, 1, 8.868_53, false),
];

/// Distance series (cos); 15 largest |*A*| terms.
const DISTANCE_TERMS: [TruncatedTerm; 15] = [
    term(0, 0, 0, 0, 385_000.527_19, true),
    term(0, 0, 1, 0, -20_905.322_06, true),
    term(2, 0, -1, 0, -3_699.104_68, true),
    term(2, 0, 0, 0, -2_955.966_51, true),
    term(0, 0, 2, 0, -569.923_32, true),
    term(2, 0, -2, 0, 246.157_68, true),
    term(2, -1, 0, 0, -204.593_57, true),
    term(2, 0, 1, 0, -170.732_74, true),
    term(2, -1, -1, 0, -152.143_14, true),
    term(0, 1, -1, 0, -129.624_76, true),
    term(1, 0, 0, 0, 108.742_65, true),
    term(0, 1, 1, 0, 104.758_96, true),
    term(0, 0, 1, -2, 79.661_83, true),
    term(0, 1, 0, 0, 48.890_1, true),
    term(4, 0, -1, 0, -34.782_45, true),
];

const fn term(i_d: i8, i_lp: i8, i_l: i8, i_f: i8, amp: f64, cos: bool) -> TruncatedTerm {
    TruncatedTerm {
        i_d,
        i_lp,
        i_l,
        i_f,
        amplitude_arcsec: amp,
        use_cosine: cos,
    }
}

/// Julian centuries since J2000.0 TT from Julian Date (TT).
#[inline]
pub fn julian_centuries_from_jd_tt(jd_tt: f64) -> f64 {
    (jd_tt - MOON_J2000_JD_TT) / DAYS_PER_JULIAN_CENTURY
}

/// Evaluate a 5-term polynomial in `t` (arcseconds).
#[inline]
fn poly5(coeffs: &[f64; 5], t: f64) -> f64 {
    coeffs[0] + t * (coeffs[1] + t * (coeffs[2] + t * (coeffs[3] + t * coeffs[4])))
}

/// ELP2000 arguments *W*₁…ϖ′ and Delaunay *D*, *l*′, *l*, *F* (arcseconds).
fn elp_and_delaunay_arcsec(t: f64) -> ([f64; 5], [f64; 4]) {
    let mut w = [0.0; 5];
    for i in 0..5 {
        w[i] = poly5(&ELP_ARGUMENT_COEFFS[i], t);
    }
    let delaunay = [
        w[W1] - w[T] + ARCSEC_PER_PI,
        w[T] - w[OBP],
        w[W1] - w[W2],
        w[W1] - w[W3],
    ];
    (w, delaunay)
}

/// Sum a truncated main-problem series at Delaunay arguments (arcseconds).
fn sum_series(terms: &[TruncatedTerm], delaunay: &[f64; 4]) -> f64 {
    let mut sum = 0.0;
    for term in terms {
        let arg = (f64::from(term.i_d) * delaunay[D]
            + f64::from(term.i_lp) * delaunay[LP]
            + f64::from(term.i_l) * delaunay[L]
            + f64::from(term.i_f) * delaunay[F])
            * ARCSEC_TO_RAD;
        sum += term.amplitude_arcsec
            * if term.use_cosine { arg.cos() } else { arg.sin() };
    }
    sum
}

/// Normalize ELP longitude (arcseconds) to \[0, `ARCSEC_PER_CIRCLE`).
#[inline]
pub fn normalize_longitude_arcsec(lon: f64) -> f64 {
    let mut x = lon % ARCSEC_PER_CIRCLE;
    if x < 0.0 {
        x += ARCSEC_PER_CIRCLE;
    }
    x
}

/// Mean obliquity of the J2000 ecliptic (radians) for equatorial conversion.
#[inline]
fn mean_obliquity_j2000_rad(t: f64) -> f64 {
    let arcsec = 84_381.406
        - 46.836_769 * t
        - 0.000_183_1 * t * t
        + 0.002_003_40 * t * t * t
        - 0.000_000_576 * t * t * t * t
        - 0.000_000_043_4 * t * t * t * t * t;
    arcsec * ARCSEC_TO_RAD
}

/// Geocentric ecliptic Moon from TT Julian Date (mean ecliptic/equinox J2000).
pub fn moon_ecliptic_j2000_from_jd_tt(jd_tt: f64) -> MoonEclipticJ2000 {
    let t = julian_centuries_from_jd_tt(jd_tt);
    let (w, delaunay) = elp_and_delaunay_arcsec(t);
    let lon = normalize_longitude_arcsec(w[W1] + sum_series(&LONGITUDE_TERMS, &delaunay));
    let lat = sum_series(&LATITUDE_TERMS, &delaunay);
    let dist = sum_series(&DISTANCE_TERMS, &delaunay);
    MoonEclipticJ2000 {
        longitude_deg: lon / 3600.0,
        latitude_deg: lat / 3600.0,
        distance_km: dist,
    }
}

/// Mean equator J2000 (α, δ) from ecliptic (λ, β) in degrees at TT epoch `jd_tt`.
///
/// Uses the unit-vector rotation form to avoid a `tan(β)` singularity at the
/// ecliptic poles. The previous tangent-identity formula divided by `cos(β)` and
/// would silently return the wrong α for high ecliptic latitudes.
pub fn ecliptic_to_equatorial_j2000_rad(
    longitude_deg: f64,
    latitude_deg: f64,
    jd_tt: f64,
) -> (f64, f64) {
    let t = julian_centuries_from_jd_tt(jd_tt);
    let eps = mean_obliquity_j2000_rad(t);
    let (sin_lon, cos_lon) = longitude_deg.to_radians().sin_cos();
    let (sin_lat, cos_lat) = latitude_deg.to_radians().sin_cos();
    let (sin_eps, cos_eps) = eps.sin_cos();

    // Ecliptic unit vector → rectangular.
    let x_ecl = cos_lat * cos_lon;
    let y_ecl = cos_lat * sin_lon;
    let z_ecl = sin_lat;

    // Rotate by −ε about X to land on mean equator J2000.
    let x_eq = x_ecl;
    let y_eq = y_ecl * cos_eps - z_ecl * sin_eps;
    let z_eq = y_ecl * sin_eps + z_ecl * cos_eps;

    let ra = y_eq.atan2(x_eq);
    let dec = z_eq.clamp(-1.0, 1.0).asin();
    (normalize_ra_rad(ra), dec)
}

/// Geocentric equatorial Moon (mean equator/equinox J2000) from TT Julian Date.
pub fn moon_equatorial_j2000_from_jd_tt(jd_tt: f64) -> MoonEquatorialJ2000 {
    let ecl = moon_ecliptic_j2000_from_jd_tt(jd_tt);
    let (ra_rad, dec_rad) =
        ecliptic_to_equatorial_j2000_rad(ecl.longitude_deg, ecl.latitude_deg, jd_tt);
    MoonEquatorialJ2000 {
        ra_rad,
        dec_rad,
        distance_km: ecl.distance_km,
    }
}

/// Normalize RA to \[0, 2π).
#[inline]
fn normalize_ra_rad(ra: f64) -> f64 {
    let two_pi = std::f64::consts::TAU;
    let mut a = ra % two_pi;
    if a < 0.0 {
        a += two_pi;
    }
    a
}

/// Angular separation (radians) between two equatorial directions.
pub fn angular_separation_rad(ra1: f64, dec1: f64, ra2: f64, dec2: f64) -> f64 {
    let (s1, c1) = dec1.sin_cos();
    let (s2, c2) = dec2.sin_cos();
    let cos_dra = (ra1 - ra2).cos();
    (s1 * s2 + c1 * c2 * cos_dra).clamp(-1.0, 1.0).acos()
}

/// Angular separation (arcminutes).
#[inline]
pub fn angular_separation_arcmin(ra1: f64, dec1: f64, ra2: f64, dec2: f64) -> f64 {
    angular_separation_rad(ra1, dec1, ra2, dec2).to_degrees() * 60.0
}
