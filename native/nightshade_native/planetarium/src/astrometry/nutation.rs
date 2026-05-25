//! IAU 2000B nutation (78-term truncated: 77 luni-solar + planetary offset).
//!
//! Algorithms match IAU SOFA `eraNut00b` (ERFA). Reference: McCarthy & Luzum (2003);
//! MHB_2000_SHORT series (Luzum 2001).

use crate::astrometry::time::{DAYS_PER_JULIAN_CENTURY, J2000_JD_TT};

/// Arcseconds to radians (SOFA `ERFA_DAS2R`).
const ARCSEC_TO_RAD: f64 = std::f64::consts::PI / (180.0 * 3_600.0);

/// Milliarcseconds to radians (SOFA `ERFA_DMAS2R`).
const MAS_TO_RAD: f64 = ARCSEC_TO_RAD / 1_000.0;

/// 0.1 microarcsecond to radians (SOFA `U2R` in `eraNut00b`).
const TENTH_UAS_TO_RAD: f64 = ARCSEC_TO_RAD / 1e7;

/// Arcseconds in a full circle (SOFA `ERFA_TURNAS`).
const TURNAS_ARCSEC: f64 = 1_296_000.0;

/// Fixed planetary offset in lieu of truncated planetary terms (SOFA `eraNut00b`).
const DPSI_PLANETARY_RAD: f64 = -0.135 * MAS_TO_RAD;
const DEPS_PLANETARY_RAD: f64 = 0.388 * MAS_TO_RAD;

/// Nutation series term (luni-solar); coefficients in 0.1 μas and 0.1 μas/century.
struct NutationTerm {
    nl: i8,
    nlp: i8,
    nf: i8,
    nd: i8,
    nom: i8,
    ps: f64,
    pst: f64,
    pc: f64,
    ec: f64,
    ect: f64,
    es: f64,
}

/// IAU 2000B luni-solar series (77 terms); SOFA `eraNut00b` table.
const NUTATION_TERMS: &[NutationTerm] = &[
    NutationTerm { nl: 0, nlp: 0, nf: 0, nd: 0, nom: 1, ps: -172064161.0, pst: -174666.0, pc: 33386.0, ec: 92052331.0, ect: 9086.0, es: 15377.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 2, nd: -2, nom: 2, ps: -13170906.0, pst: -1675.0, pc: -13696.0, ec: 5730336.0, ect: -3015.0, es: -4587.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 2, nd: 0, nom: 2, ps: -2276413.0, pst: -234.0, pc: 2796.0, ec: 978459.0, ect: -485.0, es: 1374.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 0, nd: 0, nom: 2, ps: 2074554.0, pst: 207.0, pc: -698.0, ec: -897492.0, ect: 470.0, es: -291.0 },
    NutationTerm { nl: 0, nlp: 1, nf: 0, nd: 0, nom: 0, ps: 1475877.0, pst: -3633.0, pc: 11817.0, ec: 73871.0, ect: -184.0, es: -1924.0 },
    NutationTerm { nl: 0, nlp: 1, nf: 2, nd: -2, nom: 2, ps: -516821.0, pst: 1226.0, pc: -524.0, ec: 224386.0, ect: -677.0, es: -174.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 0, nd: 0, nom: 0, ps: 711159.0, pst: 73.0, pc: -872.0, ec: -6750.0, ect: 0.0, es: 358.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 2, nd: 0, nom: 1, ps: -387298.0, pst: -367.0, pc: 380.0, ec: 200728.0, ect: 18.0, es: 318.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 2, nd: 0, nom: 2, ps: -301461.0, pst: -36.0, pc: 816.0, ec: 129025.0, ect: -63.0, es: 367.0 },
    NutationTerm { nl: 0, nlp: -1, nf: 2, nd: -2, nom: 2, ps: 215829.0, pst: -494.0, pc: 111.0, ec: -95929.0, ect: 299.0, es: 132.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 2, nd: -2, nom: 1, ps: 128227.0, pst: 137.0, pc: 181.0, ec: -68982.0, ect: -9.0, es: 39.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 2, nd: 0, nom: 2, ps: 123457.0, pst: 11.0, pc: 19.0, ec: -53311.0, ect: 32.0, es: -4.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 0, nd: 2, nom: 0, ps: 156994.0, pst: 10.0, pc: -168.0, ec: -1235.0, ect: 0.0, es: 82.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 0, nd: 0, nom: 1, ps: 63110.0, pst: 63.0, pc: 27.0, ec: -33228.0, ect: 0.0, es: -9.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 0, nd: 0, nom: 1, ps: -57976.0, pst: -63.0, pc: -189.0, ec: 31429.0, ect: 0.0, es: -75.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 2, nd: 2, nom: 2, ps: -59641.0, pst: -11.0, pc: 149.0, ec: 25543.0, ect: -11.0, es: 66.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 2, nd: 0, nom: 1, ps: -51613.0, pst: -42.0, pc: 129.0, ec: 26366.0, ect: 0.0, es: 78.0 },
    NutationTerm { nl: -2, nlp: 0, nf: 2, nd: 0, nom: 1, ps: 45893.0, pst: 50.0, pc: 31.0, ec: -24236.0, ect: -10.0, es: 20.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 0, nd: 2, nom: 0, ps: 63384.0, pst: 11.0, pc: -150.0, ec: -1220.0, ect: 0.0, es: 29.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 2, nd: 2, nom: 2, ps: -38571.0, pst: -1.0, pc: 158.0, ec: 16452.0, ect: -11.0, es: 68.0 },
    NutationTerm { nl: 0, nlp: -2, nf: 2, nd: -2, nom: 2, ps: 32481.0, pst: 0.0, pc: 0.0, ec: -13870.0, ect: 0.0, es: 0.0 },
    NutationTerm { nl: -2, nlp: 0, nf: 0, nd: 2, nom: 0, ps: -47722.0, pst: 0.0, pc: -18.0, ec: 477.0, ect: 0.0, es: -25.0 },
    NutationTerm { nl: 2, nlp: 0, nf: 2, nd: 0, nom: 2, ps: -31046.0, pst: -1.0, pc: 131.0, ec: 13238.0, ect: -11.0, es: 59.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 2, nd: -2, nom: 2, ps: 28593.0, pst: 0.0, pc: -1.0, ec: -12338.0, ect: 10.0, es: -3.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 2, nd: 0, nom: 1, ps: 20441.0, pst: 21.0, pc: 10.0, ec: -10758.0, ect: 0.0, es: -3.0 },
    NutationTerm { nl: 2, nlp: 0, nf: 0, nd: 0, nom: 0, ps: 29243.0, pst: 0.0, pc: -74.0, ec: -609.0, ect: 0.0, es: 13.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 2, nd: 0, nom: 0, ps: 25887.0, pst: 0.0, pc: -66.0, ec: -550.0, ect: 0.0, es: 11.0 },
    NutationTerm { nl: 0, nlp: 1, nf: 0, nd: 0, nom: 1, ps: -14053.0, pst: -25.0, pc: 79.0, ec: 8551.0, ect: -2.0, es: -45.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 0, nd: 2, nom: 1, ps: 15164.0, pst: 10.0, pc: 11.0, ec: -8001.0, ect: 0.0, es: -1.0 },
    NutationTerm { nl: 0, nlp: 2, nf: 2, nd: -2, nom: 2, ps: -15794.0, pst: 72.0, pc: -16.0, ec: 6850.0, ect: -42.0, es: -5.0 },
    NutationTerm { nl: 0, nlp: 0, nf: -2, nd: 2, nom: 0, ps: 21783.0, pst: 0.0, pc: 13.0, ec: -167.0, ect: 0.0, es: 13.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 0, nd: -2, nom: 1, ps: -12873.0, pst: -10.0, pc: -37.0, ec: 6953.0, ect: 0.0, es: -14.0 },
    NutationTerm { nl: 0, nlp: -1, nf: 0, nd: 0, nom: 1, ps: -12654.0, pst: 11.0, pc: 63.0, ec: 6415.0, ect: 0.0, es: 26.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 2, nd: 2, nom: 1, ps: -10204.0, pst: 0.0, pc: 25.0, ec: 5222.0, ect: 0.0, es: 15.0 },
    NutationTerm { nl: 0, nlp: 2, nf: 0, nd: 0, nom: 0, ps: 16707.0, pst: -85.0, pc: -10.0, ec: 168.0, ect: -1.0, es: 10.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 2, nd: 2, nom: 2, ps: -7691.0, pst: 0.0, pc: 44.0, ec: 3268.0, ect: 0.0, es: 19.0 },
    NutationTerm { nl: -2, nlp: 0, nf: 2, nd: 0, nom: 0, ps: -11024.0, pst: 0.0, pc: -14.0, ec: 104.0, ect: 0.0, es: 2.0 },
    NutationTerm { nl: 0, nlp: 1, nf: 2, nd: 0, nom: 2, ps: 7566.0, pst: -21.0, pc: -11.0, ec: -3250.0, ect: 0.0, es: -5.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 2, nd: 2, nom: 1, ps: -6637.0, pst: -11.0, pc: 25.0, ec: 3353.0, ect: 0.0, es: 14.0 },
    NutationTerm { nl: 0, nlp: -1, nf: 2, nd: 0, nom: 2, ps: -7141.0, pst: 21.0, pc: 8.0, ec: 3070.0, ect: 0.0, es: 4.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 0, nd: 2, nom: 1, ps: -6302.0, pst: -11.0, pc: 2.0, ec: 3272.0, ect: 0.0, es: 4.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 2, nd: -2, nom: 1, ps: 5800.0, pst: 10.0, pc: 2.0, ec: -3045.0, ect: 0.0, es: -1.0 },
    NutationTerm { nl: 2, nlp: 0, nf: 2, nd: -2, nom: 2, ps: 6443.0, pst: 0.0, pc: -7.0, ec: -2768.0, ect: 0.0, es: -4.0 },
    NutationTerm { nl: -2, nlp: 0, nf: 0, nd: 2, nom: 1, ps: -5774.0, pst: -11.0, pc: -15.0, ec: 3041.0, ect: 0.0, es: -5.0 },
    NutationTerm { nl: 2, nlp: 0, nf: 2, nd: 0, nom: 1, ps: -5350.0, pst: 0.0, pc: 21.0, ec: 2695.0, ect: 0.0, es: 12.0 },
    NutationTerm { nl: 0, nlp: -1, nf: 2, nd: -2, nom: 1, ps: -4752.0, pst: -11.0, pc: -3.0, ec: 2719.0, ect: 0.0, es: -3.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 0, nd: -2, nom: 1, ps: -4940.0, pst: -11.0, pc: -21.0, ec: 2720.0, ect: 0.0, es: -9.0 },
    NutationTerm { nl: -1, nlp: -1, nf: 0, nd: 2, nom: 0, ps: 7350.0, pst: 0.0, pc: -8.0, ec: -51.0, ect: 0.0, es: 4.0 },
    NutationTerm { nl: 2, nlp: 0, nf: 0, nd: -2, nom: 1, ps: 4065.0, pst: 0.0, pc: 6.0, ec: -2206.0, ect: 0.0, es: 1.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 0, nd: 2, nom: 0, ps: 6579.0, pst: 0.0, pc: -24.0, ec: -199.0, ect: 0.0, es: 2.0 },
    NutationTerm { nl: 0, nlp: 1, nf: 2, nd: -2, nom: 1, ps: 3579.0, pst: 0.0, pc: 5.0, ec: -1900.0, ect: 0.0, es: 1.0 },
    NutationTerm { nl: 1, nlp: -1, nf: 0, nd: 0, nom: 0, ps: 4725.0, pst: 0.0, pc: -6.0, ec: -41.0, ect: 0.0, es: 3.0 },
    NutationTerm { nl: -2, nlp: 0, nf: 2, nd: 0, nom: 2, ps: -3075.0, pst: 0.0, pc: -2.0, ec: 1313.0, ect: 0.0, es: -1.0 },
    NutationTerm { nl: 3, nlp: 0, nf: 2, nd: 0, nom: 2, ps: -2904.0, pst: 0.0, pc: 15.0, ec: 1233.0, ect: 0.0, es: 7.0 },
    NutationTerm { nl: 0, nlp: -1, nf: 0, nd: 2, nom: 0, ps: 4348.0, pst: 0.0, pc: -10.0, ec: -81.0, ect: 0.0, es: 2.0 },
    NutationTerm { nl: 1, nlp: -1, nf: 2, nd: 0, nom: 2, ps: -2878.0, pst: 0.0, pc: 8.0, ec: 1232.0, ect: 0.0, es: 4.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 0, nd: 1, nom: 0, ps: -4230.0, pst: 0.0, pc: 5.0, ec: -20.0, ect: 0.0, es: -2.0 },
    NutationTerm { nl: -1, nlp: -1, nf: 2, nd: 2, nom: 2, ps: -2819.0, pst: 0.0, pc: 7.0, ec: 1207.0, ect: 0.0, es: 3.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 2, nd: 0, nom: 0, ps: -4056.0, pst: 0.0, pc: 5.0, ec: 40.0, ect: 0.0, es: -2.0 },
    NutationTerm { nl: 0, nlp: -1, nf: 2, nd: 2, nom: 2, ps: -2647.0, pst: 0.0, pc: 11.0, ec: 1129.0, ect: 0.0, es: 5.0 },
    NutationTerm { nl: -2, nlp: 0, nf: 0, nd: 0, nom: 1, ps: -2294.0, pst: 0.0, pc: -10.0, ec: 1266.0, ect: 0.0, es: -4.0 },
    NutationTerm { nl: 1, nlp: 1, nf: 2, nd: 0, nom: 2, ps: 2481.0, pst: 0.0, pc: -7.0, ec: -1062.0, ect: 0.0, es: -3.0 },
    NutationTerm { nl: 2, nlp: 0, nf: 0, nd: 0, nom: 1, ps: 2179.0, pst: 0.0, pc: -2.0, ec: -1129.0, ect: 0.0, es: -2.0 },
    NutationTerm { nl: -1, nlp: 1, nf: 0, nd: 1, nom: 0, ps: 3276.0, pst: 0.0, pc: 1.0, ec: -9.0, ect: 0.0, es: 0.0 },
    NutationTerm { nl: 1, nlp: 1, nf: 0, nd: 0, nom: 0, ps: -3389.0, pst: 0.0, pc: 5.0, ec: 35.0, ect: 0.0, es: -2.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 2, nd: 0, nom: 0, ps: 3339.0, pst: 0.0, pc: -13.0, ec: -107.0, ect: 0.0, es: 1.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 2, nd: -2, nom: 1, ps: -1987.0, pst: 0.0, pc: -6.0, ec: 1073.0, ect: 0.0, es: -2.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 0, nd: 0, nom: 2, ps: -1981.0, pst: 0.0, pc: 0.0, ec: 854.0, ect: 0.0, es: 0.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 0, nd: 1, nom: 0, ps: 4026.0, pst: 0.0, pc: -353.0, ec: -553.0, ect: 0.0, es: -139.0 },
    NutationTerm { nl: 0, nlp: 0, nf: 2, nd: 1, nom: 2, ps: 1660.0, pst: 0.0, pc: -5.0, ec: -710.0, ect: 0.0, es: -2.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 2, nd: 4, nom: 2, ps: -1521.0, pst: 0.0, pc: 9.0, ec: 647.0, ect: 0.0, es: 4.0 },
    NutationTerm { nl: -1, nlp: 1, nf: 0, nd: 1, nom: 1, ps: 1314.0, pst: 0.0, pc: 0.0, ec: -700.0, ect: 0.0, es: 0.0 },
    NutationTerm { nl: 0, nlp: -2, nf: 2, nd: -2, nom: 1, ps: -1283.0, pst: 0.0, pc: 0.0, ec: 672.0, ect: 0.0, es: 0.0 },
    NutationTerm { nl: 1, nlp: 0, nf: 2, nd: 2, nom: 1, ps: -1331.0, pst: 0.0, pc: 8.0, ec: 663.0, ect: 0.0, es: 4.0 },
    NutationTerm { nl: -2, nlp: 0, nf: 2, nd: 2, nom: 2, ps: 1383.0, pst: 0.0, pc: -2.0, ec: -594.0, ect: 0.0, es: -2.0 },
    NutationTerm { nl: -1, nlp: 0, nf: 0, nd: 0, nom: 2, ps: 1405.0, pst: 0.0, pc: 4.0, ec: -610.0, ect: 0.0, es: 2.0 },
    NutationTerm { nl: 1, nlp: 1, nf: 2, nd: -2, nom: 2, ps: 1290.0, pst: 0.0, pc: 0.0, ec: -556.0, ect: 0.0, es: 0.0 },
];

/// Julian centuries since J2000.0 TT from a two-part Julian Date (SOFA `t`).
#[inline]
fn julian_centuries_tt(date1: f64, date2: f64) -> f64 {
    ((date1 - J2000_JD_TT) + date2) / DAYS_PER_JULIAN_CENTURY
}

#[inline]
fn fmod_positive(x: f64, modulus: f64) -> f64 {
    let mut r = x % modulus;
    if r < 0.0 {
        r += modulus;
    }
    r
}

/// Delaunay fundamental arguments (radians); Simon et al. (1994) / SOFA `eraNut00b`.
fn delaunay_arguments_rad(t: f64) -> (f64, f64, f64, f64, f64) {
    let el = fmod_positive(485_868.249_036 + 1_717_915_923.217_8 * t, TURNAS_ARCSEC) * ARCSEC_TO_RAD;
    let elp = fmod_positive(128_7104.793_05 + 129_596_581.048_1 * t, TURNAS_ARCSEC) * ARCSEC_TO_RAD;
    let f = fmod_positive(335_779.526_232 + 1_739_527_262.847_8 * t, TURNAS_ARCSEC) * ARCSEC_TO_RAD;
    let d = fmod_positive(1_072_260.703_69 + 1_602_961_601.209_0 * t, TURNAS_ARCSEC) * ARCSEC_TO_RAD;
    let om = fmod_positive(450_160.398_036 - 6_962_890.543_1 * t, TURNAS_ARCSEC) * ARCSEC_TO_RAD;
    (el, elp, f, d, om)
}

/// Luni-solar nutation components (radians) before planetary offset; SOFA `eraNut00b`.
fn luni_solar_nutation_rad(t: f64) -> (f64, f64) {
    let (el, elp, f, d, om) = delaunay_arguments_rad(t);
    let mut dp = 0.0;
    let mut de = 0.0;

    for term in NUTATION_TERMS.iter().rev() {
        let arg = fmod_positive(
            f64::from(term.nl) * el
                + f64::from(term.nlp) * elp
                + f64::from(term.nf) * f
                + f64::from(term.nd) * d
                + f64::from(term.nom) * om,
            std::f64::consts::TAU,
        );
        let (sarg, carg) = arg.sin_cos();
        dp += (term.ps + term.pst * t) * sarg + term.pc * carg;
        de += (term.ec + term.ect * t) * carg + term.es * sarg;
    }

    (dp * TENTH_UAS_TO_RAD, de * TENTH_UAS_TO_RAD)
}

/// Nutation in longitude and obliquity (radians); SOFA `eraNut00b`.
///
/// Components are with respect to the equinox and ecliptic of date.
pub fn nutation_from_julian_centuries_tt(t: f64) -> (f64, f64) {
    let (dpsils, depsls) = luni_solar_nutation_rad(t);
    (
        dpsils + DPSI_PLANETARY_RAD,
        depsls + DEPS_PLANETARY_RAD,
    )
}

/// Nutation from a two-part TT Julian Date; SOFA `eraNut00b`.
#[inline]
pub fn nutation_from_jd_tt(date1: f64, date2: f64) -> (f64, f64) {
    nutation_from_julian_centuries_tt(julian_centuries_tt(date1, date2))
}
