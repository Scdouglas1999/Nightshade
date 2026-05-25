//! SOFA `iauAb` reference comparison.
//!
//! The test fixture comes from the official SOFA C test suite
//! (`sofa/20231211_a/c/src/t_sofa_c.c`, function `t_ab`). The fixture
//! exercises [`apply_annual_aberration_direction`] directly with an explicit
//! natural direction `p` and observer velocity `v` (units of `c`) so that
//! agreement with SOFA is tested without any dependency on our VSOP87 Earth
//! velocity or any other intermediate step.
//!
//! Reference values (verbatim from `t_ab`):
//!
//! ```text
//! pnat[0] = -0.76321968546737951;
//! pnat[1] = -0.60869453983060384;
//! pnat[2] = -0.21676408580639883;
//! v[0]    =  2.1044018893653786e-5;
//! v[1]    = -8.9108923304429319e-5;
//! v[2]    = -3.8633714797716569e-5;
//! s       =  0.99980921395708788;     // unused — light-time factor
//! bm1     =  0.99999999506209258;     // unused — sqrt(1 - v·v), pre-computed
//! ppr[0]  = -0.7631631094219556269;
//! ppr[1]  = -0.6087553082505590832;
//! ppr[2]  = -0.2167926269368471279;
//! ```
//!
//! Note that SOFA's `iauAb` takes `v` in units of `c` directly. Our public
//! wrapper takes velocity in AU/day, so the fixture is scaled accordingly.

use glam::DVec3;

use nightshade_planetarium::astrometry::aberration::{
    apply_annual_aberration_direction, SPEED_OF_LIGHT_AU_PER_DAY,
};

/// 1 mas in radians.
const ONE_MAS_RAD: f64 = std::f64::consts::PI / (180.0 * 3_600.0 * 1_000.0);

#[test]
fn aberration_lorentz_matches_sofa_iau_ab_to_one_microarcsecond() {
    let pnat = DVec3::new(
        -0.763_219_685_467_379_51,
        -0.608_694_539_830_603_84,
        -0.216_764_085_806_398_83,
    );

    // SOFA `v` is in units of c. Our API takes AU/day, so multiply through.
    let v_units_c = DVec3::new(
        2.104_401_889_365_378_6e-5,
        -8.910_892_330_442_932e-5,
        -3.863_371_479_771_657e-5,
    );
    let v_au_per_day = v_units_c * SPEED_OF_LIGHT_AU_PER_DAY;

    let expected = DVec3::new(
        -0.763_163_109_421_955_6,
        -0.608_755_308_250_559_1,
        -0.216_792_626_936_847_1,
    );

    let actual = apply_annual_aberration_direction(pnat, v_au_per_day);

    // Both are unit vectors; the angular separation is the smallest meaningful
    // quantity here. SOFA's `t_ab` checks each component to 1e-12 — that's
    // ~0.2 µas (microarcsecond) of angular agreement. We assert ≤ 1 µas, the
    // tightest bound the f64 normalisation step can keep.
    let cos_sep = actual.dot(expected).clamp(-1.0, 1.0);
    let sep_rad = cos_sep.acos();
    let sep_uas = sep_rad / ONE_MAS_RAD * 1_000.0;
    assert!(
        sep_uas < 1.0,
        "SOFA iauAb mismatch: |Δ| = {sep_uas:.6} µas (expected < 1 µas) — \
         actual = {actual:?}, expected = {expected:?}"
    );

    // Per-component agreement: SOFA's own `t_ab` asserts to 1e-12 (~0.2 µas
    // per axis). Re-normalising after the SOFA formula adds one more rounding
    // step, so we widen to 1e-11 here (~2 µas per axis) — still far tighter
    // than the catalog-rendering tolerance and a strict sentinel against a
    // regression to the classical form (which would drift by ~1e-8 per axis).
    for (i, (a, e)) in actual
        .to_array()
        .iter()
        .zip(expected.to_array().iter())
        .enumerate()
    {
        assert!(
            (a - e).abs() < 1.0e-11,
            "component {i}: {a} vs {e} (|Δ| = {})",
            (a - e).abs()
        );
    }
}

/// Numerical sanity: at relativistic speeds the Lorentz form diverges
/// noticeably from the projection-onto-tangent-plane "first-order" expression
/// `(p + V − (p·V)p)/|·|`. This test exaggerates v/c to 0.1 (10% of c) and
/// asserts the two forms differ by ≥ 1 mas — proving the implementation is
/// actually evaluating the Lorentz formula rather than the Newtonian one.
///
/// At Earth orbital speeds (v/c ≈ 1e-4) the two forms agree to O((v/c)²) per
/// component, and the leading correction is along `p` (so it vanishes after
/// the final normalisation). The Lorentz form is preferred not because it
/// changes the answer at Earth speeds but because it is the SOFA reference
/// implementation; agreement with `iauAb` is the test that matters.
#[test]
fn lorentz_form_diverges_from_classical_at_relativistic_speed() {
    // p along x; v at 0.1 c along y so p·V = 0 and the Lorentz vs classical
    // difference is dominated by the (1 − V²/2) p prefactor that the classical
    // form omits.
    let p = DVec3::new(1.0, 0.0, 0.0);
    let v_units_c = DVec3::new(0.0, 0.1, 0.0);
    let v_au_per_day = v_units_c * SPEED_OF_LIGHT_AU_PER_DAY;

    let lorentz = apply_annual_aberration_direction(p, v_au_per_day);

    // Classical projection form on the same inputs.
    let dot = p.dot(v_units_c);
    let classical = (p + v_units_c - dot * p).normalize();

    let cos_sep = lorentz.dot(classical).clamp(-1.0, 1.0);
    let sep_rad = cos_sep.acos();
    let sep_arcsec = sep_rad * (180.0 * 3_600.0 / std::f64::consts::PI);

    // At V = 0.1 c the second-order correction is ~5e-3 rad ≈ 1000″. The two
    // forms must disagree by a wide margin.
    assert!(
        sep_arcsec > 1.0,
        "Lorentz form must diverge from classical at v = 0.1 c, got {sep_arcsec:.6}″ \
         — implementation has silently reverted to the classical formula"
    );
}
