//! VSOP87D truncated series: heliocentric ecliptic J2000 (L, B, R).
//!
//! Coefficients match `packages/nightshade_planetarium` `planetary_positions.dart`
//! (~1 arcminute visual accuracy). Time argument `t` is Julian millennia from J2000.0 TT.
//!
//! INTEGRATE: add `pub mod vsop87;` to `astrometry/mod.rs`.

/// VSOP87D epoch (J2000.0) in TT Julian date.
pub const VSOP87_J2000_JD: f64 = 2_451_545.0;
/// Julian millennia per VSOP87 time unit.
pub const DAYS_PER_JULIAN_MILLENNIUM: f64 = 365_250.0;
/// Mean obliquity of the ecliptic at J2000.0 (degrees, IAU 2006).
pub const MEAN_OBLIQUITY_J2000_DEG: f64 = 23.439_291_111;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VsopBody {
    Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HeliocentricEcliptic {
    pub longitude_rad: f64,
    pub latitude_rad: f64,
    pub distance_au: f64,
}

#[inline]
pub fn julian_millennia_tt(jd_tt: f64) -> f64 {
    (jd_tt - VSOP87_J2000_JD) / DAYS_PER_JULIAN_MILLENNIUM
}

fn eval_terms(terms: &[(f64, f64, f64)], t: f64) -> f64 {
    terms.iter().fold(0.0, |acc, &(a, b, c)| acc + a * (b + c * t).cos())
}

fn eval_component(
    c0: &[(f64, f64, f64)],
    c1: &[(f64, f64, f64)],
    c2: &[(f64, f64, f64)],
    t: f64,
) -> f64 {
    let mut v = eval_terms(c0, t);
    if !c1.is_empty() { v += t * eval_terms(c1, t); }
    if !c2.is_empty() { v += t * t * eval_terms(c2, t); }
    v / 1e8
}

fn normalize_longitude_rad(lon: f64) -> f64 {
    use std::f64::consts::TAU;
    let mut lon = lon % TAU;
    if lon < 0.0 { lon += TAU; }
    lon
}

/// Mean obliquity of the ecliptic (degrees) at `jd_tt`.
///
/// Linear approximation of IAU 2006 P03 (Hilton/Capitaine 2006): ε(T) ≈ 23.439291°
/// − 0.0130042° T, where T is centuries TT since J2000.0. Higher-order terms are
/// dropped here for the visual planetarium because they contribute < 0.1″ over the
/// VSOP87D validity span (±1000 years) — well below the catalog rendering tolerance.
/// For arcsecond-grade frame chains use `astrometry::precession::mean_obliquity_from_julian_centuries_tt`.
fn mean_obliquity_deg(jd_tt: f64) -> f64 {
    let t = (jd_tt - VSOP87_J2000_JD) / 36_525.0;
    MEAN_OBLIQUITY_J2000_DEG - 0.013_004_2 * t
}

/// Convert ecliptic spherical coordinates `(λ, β)` to equatorial `(α, δ)` (radians).
///
/// Uses the unit-vector rotation form (rotate ecliptic frame by `-ε` about the X axis)
/// rather than the Meeus tangent identity to avoid a singularity at the ecliptic poles.
/// The Meeus form `tan(α) = (sin(λ)cos(ε) − tan(β)sin(ε)) / cos(λ)` is undefined when
/// `cos(β) → 0` (β = ±90°), and the previous implementation papered over it with a
/// `.max(1e-12)` clamp that silently returned the wrong α for high-latitude inputs.
pub fn ecliptic_to_equatorial_rad(
    longitude_rad: f64,
    latitude_rad: f64,
    obliquity_rad: f64,
) -> (f64, f64) {
    let (sin_lon, cos_lon) = longitude_rad.sin_cos();
    let (sin_lat, cos_lat) = latitude_rad.sin_cos();
    let (sin_eps, cos_eps) = obliquity_rad.sin_cos();

    // Ecliptic unit vector (λ, β) → rectangular.
    let x_ecl = cos_lat * cos_lon;
    let y_ecl = cos_lat * sin_lon;
    let z_ecl = sin_lat;

    // Rotate about X by −ε to get equatorial (FK5/ICRS-aligned for VSOP87D).
    let x_eq = x_ecl;
    let y_eq = y_ecl * cos_eps - z_ecl * sin_eps;
    let z_eq = y_ecl * sin_eps + z_ecl * cos_eps;

    let dec = z_eq.clamp(-1.0, 1.0).asin();
    let ra = y_eq.atan2(x_eq).rem_euclid(std::f64::consts::TAU);
    (ra, dec)
}

const EARTH_B0: &[(f64, f64, f64)] = &[
    (280.0, 3.199, 84334.662),
    (102.0, 5.422, 5507.553),
    (80.0, 3.88, 5223.69),
];

const EARTH_L0: &[(f64, f64, f64)] = &[
    (175347046.0, 0.0, 0.0),
    (3341656.0, 4.6692568, 6283.07585),
    (34894.0, 4.6261, 12566.1517),
    (3497.0, 2.7441, 5753.3849),
    (3418.0, 2.8289, 3.5231),
    (3136.0, 3.6277, 77713.7715),
    (2676.0, 4.4181, 7860.4194),
    (2343.0, 6.1352, 3930.2097),
    (1324.0, 0.7425, 11506.7698),
    (1273.0, 2.0371, 529.691),
    (1199.0, 1.1096, 1577.3435),
];

const EARTH_L1: &[(f64, f64, f64)] = &[
    (628331966747.0, 0.0, 0.0),
    (206059.0, 2.678235, 6283.07585),
    (4303.0, 2.6351, 12566.1517),
];

const EARTH_L2: &[(f64, f64, f64)] = &[
    (52919.0, 0.0, 0.0),
    (8720.0, 1.0721, 6283.0758),
];

const EARTH_R0: &[(f64, f64, f64)] = &[
    (100013989.0, 0.0, 0.0),
    (1670700.0, 3.0984635, 6283.07585),
    (13956.0, 3.0552, 12566.1517),
    (3084.0, 5.1985, 77713.7715),
    (1628.0, 1.1739, 5753.3849),
    (1576.0, 2.8469, 7860.4194),
    (925.0, 5.453, 11506.77),
    (542.0, 4.564, 3930.21),
];

const EARTH_R1: &[(f64, f64, f64)] = &[
    (103019.0, 1.10749, 6283.07585),
    (1721.0, 1.0644, 12566.1517),
];

const MERCURY_B0: &[(f64, f64, f64)] = &[
    (11737529.0, 1.98357499, 26087.90314157),
    (2388077.0, 5.0373896, 52175.8062831),
    (1222840.0, 3.1415927, 0.0),
    (543252.0, 1.796444, 78263.709425),
    (129779.0, 4.832325, 104351.612566),
    (31867.0, 1.58088, 130439.51571),
];

const MERCURY_B1: &[(f64, f64, f64)] = &[
    (429151.0, 3.501698, 26087.903142),
    (146234.0, 3.141593, 0.0),
    (22675.0, 0.01515, 52175.80628),
];

const MERCURY_L0: &[(f64, f64, f64)] = &[
    (440250710.0, 0.0, 0.0),
    (40989415.0, 1.48302034, 26087.90314157),
    (5046294.0, 4.4778549, 52175.8062831),
    (855347.0, 1.165203, 78263.709425),
    (165590.0, 4.119692, 104351.612566),
    (34562.0, 0.77931, 130439.51571),
    (7583.0, 3.7135, 156527.4188),
];

const MERCURY_L1: &[(f64, f64, f64)] = &[
    (2608814706223.0, 0.0, 0.0),
    (1126008.0, 6.2170397, 26087.9031416),
    (303471.0, 3.055655, 52175.806283),
    (80538.0, 6.10455, 78263.70942),
];

const MERCURY_L2: &[(f64, f64, f64)] = &[
    (53050.0, 0.0, 0.0),
    (16904.0, 4.69072, 26087.90314),
    (7397.0, 1.3474, 52175.8063),
];

const MERCURY_R0: &[(f64, f64, f64)] = &[
    (39528272.0, 0.0, 0.0),
    (7834132.0, 6.1923372, 26087.9031416),
    (795526.0, 2.959897, 52175.806283),
    (121282.0, 6.010642, 78263.709425),
    (21922.0, 2.7782, 104351.61257),
    (4354.0, 5.8289, 130439.5157),
];

const MERCURY_R1: &[(f64, f64, f64)] = &[
    (217348.0, 4.656172, 26087.903142),
    (44142.0, 1.42386, 52175.80628),
    (10094.0, 4.47466, 78263.70942),
];

const VENUS_B0: &[(f64, f64, f64)] = &[
    (5923638.0, 0.2670278, 10213.2855462),
    (40108.0, 1.14737, 20426.57109),
    (32815.0, 3.14159, 0.0),
    (1011.0, 1.0895, 30639.8566),
];

const VENUS_B1: &[(f64, f64, f64)] = &[
    (513348.0, 1.803643, 10213.285546),
    (4380.0, 3.3862, 20426.5711),
    (199.0, 0.0, 0.0),
];

const VENUS_L0: &[(f64, f64, f64)] = &[
    (317614667.0, 0.0, 0.0),
    (1353968.0, 5.5931332, 10213.2855462),
    (89892.0, 5.3065, 20426.57109),
    (5477.0, 4.4163, 7860.4194),
    (3456.0, 2.6996, 11790.6291),
    (2372.0, 2.9938, 3930.2097),
    (1664.0, 4.2502, 1577.3435),
    (1438.0, 4.1575, 9683.5946),
];

const VENUS_L1: &[(f64, f64, f64)] = &[
    (1021352943053.0, 0.0, 0.0),
    (95708.0, 2.46424, 10213.28555),
    (14445.0, 0.51625, 20426.57109),
];

const VENUS_L2: &[(f64, f64, f64)] = &[
    (54127.0, 0.0, 0.0),
    (3891.0, 0.3451, 10213.2855),
    (1338.0, 2.0201, 20426.5711),
];

const VENUS_R0: &[(f64, f64, f64)] = &[
    (72334821.0, 0.0, 0.0),
    (489824.0, 4.021518, 10213.285546),
    (1658.0, 4.9021, 20426.5711),
    (1632.0, 2.8455, 7860.4194),
    (1378.0, 1.1285, 11790.6291),
    (498.0, 2.587, 9683.595),
];

const VENUS_R1: &[(f64, f64, f64)] = &[
    (34551.0, 0.89199, 10213.28555),
    (234.0, 1.772, 20426.571),
];

const MARS_B0: &[(f64, f64, f64)] = &[
    (3197135.0, 3.7683204, 3340.6124267),
    (298033.0, 4.10617, 6681.224853),
    (289105.0, 0.0, 0.0),
    (31366.0, 4.44651, 10021.83728),
    (3484.0, 4.7881, 13362.4497),
];

const MARS_B1: &[(f64, f64, f64)] = &[
    (350069.0, 5.368478, 3340.612427),
    (14116.0, 3.14159, 0.0),
    (9671.0, 5.4788, 6681.2249),
];

const MARS_L0: &[(f64, f64, f64)] = &[
    (620347712.0, 0.0, 0.0),
    (18656368.0, 5.050371, 3340.6124267),
    (1108217.0, 5.4009984, 6681.2248534),
    (91798.0, 5.75479, 10021.83728),
    (27745.0, 5.9705, 3.52312),
    (12316.0, 0.84956, 2810.92146),
    (10610.0, 2.93959, 2281.2305),
    (8927.0, 4.157, 0.0173),
    (8716.0, 6.1101, 13362.4497),
];

const MARS_L1: &[(f64, f64, f64)] = &[
    (334085627474.0, 0.0, 0.0),
    (1458227.0, 3.6042605, 3340.6124267),
    (164901.0, 3.926313, 6681.224853),
    (19963.0, 4.26594, 10021.83728),
    (3452.0, 4.7321, 3.5231),
];

const MARS_L2: &[(f64, f64, f64)] = &[
    (58016.0, 2.04979, 3340.61243),
    (54188.0, 0.0, 0.0),
    (13908.0, 2.45742, 6681.22485),
    (2465.0, 2.8, 10021.8373),
];

const MARS_R0: &[(f64, f64, f64)] = &[
    (153033488.0, 0.0, 0.0),
    (14184953.0, 3.47971284, 3340.6124267),
    (660776.0, 3.817834, 6681.224853),
    (46179.0, 4.15595, 10021.83728),
    (8110.0, 5.5596, 2810.9215),
    (7485.0, 1.7724, 5621.8429),
    (5523.0, 1.3644, 2281.2305),
];

const MARS_R1: &[(f64, f64, f64)] = &[
    (1107433.0, 2.0325052, 3340.6124267),
    (103176.0, 2.370718, 6681.224853),
    (12877.0, 0.0, 0.0),
    (10816.0, 2.70888, 10021.83728),
];

const JUPITER_B0: &[(f64, f64, f64)] = &[
    (2268616.0, 3.5585261, 529.6909651),
    (110090.0, 0.0, 0.0),
    (109972.0, 3.908093, 1059.38193),
    (8101.0, 3.6051, 522.5774),
    (6438.0, 0.3063, 536.8045),
];

const JUPITER_B1: &[(f64, f64, f64)] = &[
    (177352.0, 5.701665, 529.690965),
    (3230.0, 5.7794, 1059.3819),
    (3081.0, 5.4746, 522.5774),
];

const JUPITER_L0: &[(f64, f64, f64)] = &[
    (59954691.0, 0.0, 0.0),
    (9695899.0, 5.0619179, 529.6909651),
    (573610.0, 1.444062, 7.113547),
    (306389.0, 5.417347, 1059.38193),
    (97178.0, 4.14265, 632.78374),
    (72903.0, 3.64043, 522.57742),
    (64264.0, 3.41145, 103.09277),
    (39806.0, 2.29377, 419.48464),
    (38858.0, 1.27232, 316.39187),
];

const JUPITER_L1: &[(f64, f64, f64)] = &[
    (52993480757.0, 0.0, 0.0),
    (489741.0, 4.220667, 529.690965),
    (228919.0, 6.026475, 7.113547),
    (27655.0, 4.57266, 1059.38193),
    (20721.0, 5.45939, 522.57742),
    (12106.0, 0.16986, 536.80451),
];

const JUPITER_L2: &[(f64, f64, f64)] = &[
    (47234.0, 4.32148, 7.11355),
    (38966.0, 0.0, 0.0),
    (30629.0, 2.93021, 529.69097),
    (3189.0, 1.055, 522.5774),
];

const JUPITER_R0: &[(f64, f64, f64)] = &[
    (520887429.0, 0.0, 0.0),
    (25209327.0, 3.4910864, 529.69096509),
    (610600.0, 3.841154, 1059.38193),
    (282029.0, 2.574199, 632.783739),
    (187647.0, 2.075904, 522.577418),
    (86793.0, 0.71001, 419.48464),
    (72063.0, 0.21466, 536.80451),
    (65517.0, 5.97996, 316.39187),
];

const JUPITER_R1: &[(f64, f64, f64)] = &[
    (1271802.0, 2.6493751, 529.6909651),
    (61662.0, 3.00076, 1059.38193),
    (53444.0, 3.89718, 522.57742),
    (41390.0, 0.0, 0.0),
];

const SATURN_B0: &[(f64, f64, f64)] = &[
    (4330678.0, 3.6028443, 213.2990954),
    (240348.0, 2.852385, 426.598191),
    (84746.0, 0.0, 0.0),
    (34116.0, 0.57297, 206.18555),
    (30863.0, 3.48442, 220.41264),
];

const SATURN_B1: &[(f64, f64, f64)] = &[
    (397555.0, 5.3329, 213.299095),
    (49479.0, 3.14159, 0.0),
    (18572.0, 6.09919, 426.59819),
];

const SATURN_L0: &[(f64, f64, f64)] = &[
    (87401354.0, 0.0, 0.0),
    (11107660.0, 3.9620509, 213.29909544),
    (1414151.0, 4.5858152, 7.113547),
    (398379.0, 0.52112, 206.185548),
    (350769.0, 3.303299, 426.598191),
    (206816.0, 0.246584, 103.092774),
    (79271.0, 3.84007, 220.41264),
    (23990.0, 4.66977, 110.20632),
    (16574.0, 0.43719, 419.48464),
];

const SATURN_L1: &[(f64, f64, f64)] = &[
    (21354295596.0, 0.0, 0.0),
    (1296855.0, 1.8282054, 213.2990954),
    (564348.0, 2.885001, 7.113547),
    (107679.0, 2.277699, 206.185548),
    (98323.0, 1.0807, 426.59819),
    (40255.0, 2.04128, 220.41264),
];

const SATURN_L2: &[(f64, f64, f64)] = &[
    (116441.0, 1.179879, 7.113547),
    (91921.0, 0.07425, 213.2991),
    (90592.0, 0.0, 0.0),
    (15277.0, 4.06492, 206.18555),
    (10631.0, 0.25778, 220.41264),
];

const SATURN_R0: &[(f64, f64, f64)] = &[
    (955758136.0, 0.0, 0.0),
    (52921382.0, 2.3922622, 213.29909544),
    (1873680.0, 5.2354961, 206.1855484),
    (1464664.0, 1.6476305, 426.5981909),
    (821891.0, 5.9352, 316.39187),
    (547507.0, 5.015326, 103.092774),
    (371684.0, 2.271148, 220.412642),
];

const SATURN_R1: &[(f64, f64, f64)] = &[
    (6182981.0, 0.2584352, 213.2990954),
    (506578.0, 0.711147, 206.185548),
    (341394.0, 5.796358, 426.598191),
    (188491.0, 0.47216, 220.41264),
    (186262.0, 3.141593, 0.0),
];

const URANUS_B0: &[(f64, f64, f64)] = &[
    (1346278.0, 2.6187781, 74.7815986),
    (62341.0, 5.08111, 149.5632),
    (61601.0, 3.14159, 0.0),
    (9964.0, 1.616, 76.2661),
    (9926.0, 0.5763, 73.2971),
];

const URANUS_B1: &[(f64, f64, f64)] = &[
    (206366.0, 4.123943, 74.781599),
    (4825.0, 3.1416, 0.0),
    (4439.0, 0.5205, 149.5632),
];

const URANUS_L0: &[(f64, f64, f64)] = &[
    (548129294.0, 0.0, 0.0),
    (9260408.0, 0.8910642, 74.7815986),
    (1504248.0, 3.6271926, 1.4844727),
    (365982.0, 1.899622, 73.297126),
    (272328.0, 3.358237, 149.563197),
    (70328.0, 5.39254, 63.7359),
    (68893.0, 6.09292, 76.26607),
    (61999.0, 2.26952, 2.96895),
];

const URANUS_L1: &[(f64, f64, f64)] = &[
    (7502543122.0, 0.0, 0.0),
    (154458.0, 5.242017, 74.781599),
    (24456.0, 1.71256, 1.48447),
    (9258.0, 0.4284, 11.0457),
];

const URANUS_L2: &[(f64, f64, f64)] = &[
    (53033.0, 0.0, 0.0),
    (2358.0, 2.2601, 74.7816),
    (769.0, 4.526, 11.046),
];

const URANUS_R0: &[(f64, f64, f64)] = &[
    (1921264848.0, 0.0, 0.0),
    (88784984.0, 5.60377527, 74.78159857),
    (3440836.0, 0.328361, 73.2971259),
    (2055653.0, 1.7829517, 149.5631971),
    (649322.0, 4.522473, 76.266071),
    (602248.0, 3.860038, 63.735898),
    (496404.0, 1.401399, 454.909367),
];

const URANUS_R1: &[(f64, f64, f64)] = &[
    (1479896.0, 3.6719405, 74.7815986),
    (71212.0, 6.22601, 63.7359),
    (68627.0, 6.13411, 149.5632),
    (46620.0, 3.14159, 0.0),
];

const NEPTUNE_B0: &[(f64, f64, f64)] = &[
    (3088623.0, 1.4410437, 38.1330356),
    (27780.0, 5.91272, 76.26607),
    (27624.0, 0.0, 0.0),
    (15448.0, 3.50877, 39.61751),
    (15355.0, 2.52124, 36.64856),
];

const NEPTUNE_B1: &[(f64, f64, f64)] = &[
    (227279.0, 3.807931, 38.133036),
    (1803.0, 1.9758, 76.2661),
    (1433.0, 3.1416, 0.0),
];

const NEPTUNE_L0: &[(f64, f64, f64)] = &[
    (531188633.0, 0.0, 0.0),
    (1798476.0, 2.9010127, 38.1330356),
    (1019728.0, 0.4858092, 1.4844727),
    (124532.0, 4.830081, 36.648563),
    (42064.0, 5.41055, 2.96895),
    (37715.0, 6.09222, 35.16409),
    (33785.0, 1.24489, 76.26607),
];

const NEPTUNE_L1: &[(f64, f64, f64)] = &[
    (3837687717.0, 0.0, 0.0),
    (16604.0, 4.86319, 1.48447),
    (15807.0, 2.27923, 38.13304),
];

const NEPTUNE_L2: &[(f64, f64, f64)] = &[
    (53893.0, 0.0, 0.0),
    (296.0, 1.855, 38.133),
];

const NEPTUNE_R0: &[(f64, f64, f64)] = &[
    (3007013206.0, 0.0, 0.0),
    (27062259.0, 1.32999459, 38.13303564),
    (1691764.0, 3.2518614, 36.6485629),
    (807831.0, 5.185928, 1.484473),
    (537761.0, 4.521139, 35.16409),
    (495726.0, 1.571057, 491.557929),
    (274572.0, 1.845523, 175.16606),
];

const NEPTUNE_R1: &[(f64, f64, f64)] = &[
    (236339.0, 0.70498, 38.133036),
    (13220.0, 3.32015, 1.48447),
    (8622.0, 6.2163, 35.1641),
];

fn heliocentric_earth(t: f64) -> HeliocentricEcliptic {
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(eval_component(EARTH_L0, EARTH_L1, EARTH_L2, t)),
        latitude_rad: eval_component(EARTH_B0, &[], &[], t),
        distance_au: eval_component(EARTH_R0, EARTH_R1, &[], t),
    }
}

fn heliocentric_mercury(t: f64) -> HeliocentricEcliptic {
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(eval_component(MERCURY_L0, MERCURY_L1, MERCURY_L2, t)),
        latitude_rad: eval_component(MERCURY_B0, MERCURY_B1, &[], t),
        distance_au: eval_component(MERCURY_R0, MERCURY_R1, &[], t),
    }
}

fn heliocentric_venus(t: f64) -> HeliocentricEcliptic {
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(eval_component(VENUS_L0, VENUS_L1, VENUS_L2, t)),
        latitude_rad: eval_component(VENUS_B0, VENUS_B1, &[], t),
        distance_au: eval_component(VENUS_R0, VENUS_R1, &[], t),
    }
}

fn heliocentric_mars(t: f64) -> HeliocentricEcliptic {
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(eval_component(MARS_L0, MARS_L1, MARS_L2, t)),
        latitude_rad: eval_component(MARS_B0, MARS_B1, &[], t),
        distance_au: eval_component(MARS_R0, MARS_R1, &[], t),
    }
}

fn heliocentric_jupiter(t: f64) -> HeliocentricEcliptic {
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(eval_component(JUPITER_L0, JUPITER_L1, JUPITER_L2, t)),
        latitude_rad: eval_component(JUPITER_B0, JUPITER_B1, &[], t),
        distance_au: eval_component(JUPITER_R0, JUPITER_R1, &[], t),
    }
}

fn heliocentric_saturn(t: f64) -> HeliocentricEcliptic {
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(eval_component(SATURN_L0, SATURN_L1, SATURN_L2, t)),
        latitude_rad: eval_component(SATURN_B0, SATURN_B1, &[], t),
        distance_au: eval_component(SATURN_R0, SATURN_R1, &[], t),
    }
}

fn heliocentric_uranus(t: f64) -> HeliocentricEcliptic {
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(eval_component(URANUS_L0, URANUS_L1, URANUS_L2, t)),
        latitude_rad: eval_component(URANUS_B0, URANUS_B1, &[], t),
        distance_au: eval_component(URANUS_R0, URANUS_R1, &[], t),
    }
}

fn heliocentric_neptune(t: f64) -> HeliocentricEcliptic {
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(eval_component(NEPTUNE_L0, NEPTUNE_L1, NEPTUNE_L2, t)),
        latitude_rad: eval_component(NEPTUNE_B0, NEPTUNE_B1, &[], t),
        distance_au: eval_component(NEPTUNE_R0, NEPTUNE_R1, &[], t),
    }
}

/// Heliocentric ecliptic position for a major planet (VSOP87D, J2000 ecliptic).
pub fn heliocentric_ecliptic(body: VsopBody, t: f64) -> HeliocentricEcliptic {
    match body {
        VsopBody::Mercury => heliocentric_mercury(t),
        VsopBody::Venus => heliocentric_venus(t),
        VsopBody::Earth => heliocentric_earth(t),
        VsopBody::Mars => heliocentric_mars(t),
        VsopBody::Jupiter => heliocentric_jupiter(t),
        VsopBody::Saturn => heliocentric_saturn(t),
        VsopBody::Uranus => heliocentric_uranus(t),
        VsopBody::Neptune => heliocentric_neptune(t),
    }
}

fn ecliptic_rectangular(lon: f64, lat: f64, r: f64) -> (f64, f64, f64) {
    let (sl, cl) = lon.sin_cos();
    let (sb, cb) = lat.sin_cos();
    (r * cb * cl, r * cb * sl, r * sb)
}

/// Geocentric ecliptic position (planet or Sun) from heliocentric VSOP87D.
pub fn geocentric_ecliptic(body: VsopBody, t: f64) -> HeliocentricEcliptic {
    let earth = heliocentric_earth(t);
    let (xe, ye, ze) = ecliptic_rectangular(
        earth.longitude_rad,
        earth.latitude_rad,
        earth.distance_au,
    );
    let (xp, yp, zp, rp) = if body == VsopBody::Earth {
        (0.0, 0.0, 0.0, 0.0)
    } else {
        let p = heliocentric_ecliptic(body, t);
        let (x, y, z) = ecliptic_rectangular(p.longitude_rad, p.latitude_rad, p.distance_au);
        (x, y, z, p.distance_au)
    };
    let _ = rp;
    let x = xp - xe;
    let y = yp - ye;
    let z = zp - ze;
    let d = (x * x + y * y + z * z).sqrt();
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad(y.atan2(x)),
        latitude_rad: (z / d).clamp(-1.0, 1.0).asin(),
        distance_au: d,
    }
}

/// Geocentric ecliptic Sun (negated Earth heliocentric vector).
pub fn sun_geocentric_ecliptic(t: f64) -> HeliocentricEcliptic {
    let earth = heliocentric_earth(t);
    let (x, y, z) = ecliptic_rectangular(
        earth.longitude_rad,
        earth.latitude_rad,
        earth.distance_au,
    );
    let d = earth.distance_au;
    HeliocentricEcliptic {
        longitude_rad: normalize_longitude_rad((-y).atan2(-x)),
        latitude_rad: (-z / d).clamp(-1.0, 1.0).asin(),
        distance_au: d,
    }
}

/// Equatorial apparent position of the Sun (geocentric, J2000 equator) at TT Julian date.
pub fn sun_equatorial_rad(jd_tt: f64) -> (f64, f64) {
    let t = julian_millennia_tt(jd_tt);
    let ecl = sun_geocentric_ecliptic(t);
    let eps = mean_obliquity_deg(jd_tt).to_radians();
    ecliptic_to_equatorial_rad(ecl.longitude_rad, ecl.latitude_rad, eps)
}

/// Equatorial apparent position of a planet at TT Julian date.
pub fn planet_equatorial_rad(body: VsopBody, jd_tt: f64) -> (f64, f64) {
    let t = julian_millennia_tt(jd_tt);
    let ecl = geocentric_ecliptic(body, t);
    let eps = mean_obliquity_deg(jd_tt).to_radians();
    ecliptic_to_equatorial_rad(ecl.longitude_rad, ecl.latitude_rad, eps)
}

