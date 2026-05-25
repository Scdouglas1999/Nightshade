//! Spot-check the bundled variable-star table against published GCVS/AAVSO VSX
//! values for well-known variables. Catches accidental edits or generator-script
//! regressions that flip a digit in a period or magnitude.

use nightshade_planetarium::catalog::variable_stars::{find_by_name, stars};

/// Reference value: `name → (period_days_or_none, mag_max, mag_min)`.
///
/// Source: GCVS (Samus+ 2017, http://www.sai.msu.ru/gcvs/) cross-checked with
/// AAVSO VSX (https://www.aavso.org/vsx/). Period tolerance: ±0.01 d for
/// short-period pulsators, ±0.1 d for long-period (Mira-type), ±10 d for
/// recurrent dwarf-nova outburst cycle. Magnitude tolerance: ±0.05 mag,
/// reflecting GCVS quoting precision.
const REFS: &[(&str, Option<f32>, f32, f32, f32, f32)] = &[
    // (name, period, mag_max, mag_min, period_tol, mag_tol)
    ("Mira", Some(332.0), 2.0, 10.1, 1.0, 0.1),
    ("Chi Cygni", Some(408.05), 3.3, 14.2, 0.5, 0.1),
    ("R Cygni", Some(426.45), 6.1, 14.4, 0.5, 0.1),
    ("Delta Cephei", Some(5.3663), 3.48, 4.37, 0.01, 0.05),
    ("Eta Aquilae", Some(7.1767), 3.48, 4.39, 0.01, 0.05),
    ("RR Lyrae", Some(0.5669), 7.06, 8.12, 0.001, 0.05),
    ("Algol", Some(2.8673), 2.12, 3.39, 0.001, 0.05),
    ("R Coronae Borealis", None, 5.71, 14.8, 0.0, 0.1),
    ("U Geminorum", Some(102.7), 8.2, 14.9, 5.0, 0.1),
    ("T Tauri", None, 9.3, 13.5, 0.0, 0.1),
];

#[test]
fn well_known_variables_match_gcvs_vsx_within_tolerance() {
    for &(name, period, mag_max, mag_min, period_tol, mag_tol) in REFS {
        let star = find_by_name(name)
            .unwrap_or_else(|| panic!("variable star `{name}` missing from STARS table"));

        match (period, star.period_days) {
            (None, None) => {} // both irregular
            (Some(_), None) | (None, Some(_)) => {
                panic!(
                    "{name}: period presence mismatch — reference = {period:?}, catalog = {:?}",
                    star.period_days
                );
            }
            (Some(p_ref), Some(p_cat)) => {
                assert!(
                    (p_cat - p_ref).abs() <= period_tol,
                    "{name}: period {p_cat} d (catalog) vs {p_ref} d (GCVS/VSX), tol {period_tol} d"
                );
            }
        }

        assert!(
            (star.mag_max - mag_max).abs() <= mag_tol,
            "{name}: mag_max {} (catalog) vs {mag_max} (GCVS/VSX), tol {mag_tol}",
            star.mag_max
        );
        assert!(
            (star.mag_min - mag_min).abs() <= mag_tol,
            "{name}: mag_min {} (catalog) vs {mag_min} (GCVS/VSX), tol {mag_tol}",
            star.mag_min
        );
    }
}

#[test]
fn star_table_is_internally_consistent() {
    // mag_min (faintest) must be ≥ mag_max (brightest); they are magnitudes, so
    // a larger number is fainter.
    for star in stars() {
        assert!(
            star.mag_min >= star.mag_max,
            "{}: mag_min ({}) must be ≥ mag_max ({}) — magnitudes are inverted",
            star.name,
            star.mag_min,
            star.mag_max
        );
    }
}
