//! J2000 → mean-of-date ("JNOW") coordinate conversion for the mount
//! boundary.
//!
//! Every catalog, plate solver, and internal coordinate in Nightshade is
//! J2000/ICRS, but GOTO mounts overwhelmingly expect apparent/topocentric
//! coordinates of date: ASCOM mounts default to `equTopocentric`, the INDI
//! `EQUATORIAL_EOD_COORD` property is JNOW by definition, and native
//! LX200-protocol mounts are JNOW. Sending raw J2000 to a JNOW mount lands
//! the initial GOTO ~50.3″ × (years since 2000) off — about 22′ in 2026 —
//! which closed-loop centering then has to claw back with an extra
//! solve/sync iteration (and a raw slew without centering simply misses).
//!
//! Scope deliberately limited to **precession** (IAU 1976 / Meeus ch. 21):
//! nutation (≤ 17″) and annual aberration (≤ 20.5″) are an order of
//! magnitude below the dominant term and well inside every mount's pointing
//! noise; plate-solve centering owns the last arcminute regardless.
//!
//! Direction policy: only coordinates SENT to the mount (slew / sync) are
//! converted. Coordinates READ from the mount stay in the mount's native
//! frame, exactly as before — the trigger monitor's hour-angle math
//! (HA = LST − RA_of_date) is only correct with of-date RA, and the
//! conversion of inputs alone keeps the mount's internal pointing model in
//! a single consistent frame.

/// Julian centuries of TT since J2000.0 for a given Julian day.
fn centuries_since_j2000(jd: f64) -> f64 {
    (jd - 2451545.0) / 36525.0
}

/// Precess J2000.0 equatorial coordinates to mean-of-date at Julian day
/// [`jd`]. RA in hours, Dec in degrees; returns (ra_hours, dec_degrees).
///
/// Meeus, *Astronomical Algorithms* 2nd ed., eq. 21.3 + 21.4 (the rigorous
/// rotation, not the annual-rate approximation — exact at any epoch
/// separation and stable at the pole).
pub fn precess_j2000_to_jd(ra_hours: f64, dec_deg: f64, jd: f64) -> (f64, f64) {
    let t = centuries_since_j2000(jd);

    // Precession angles in arcseconds (eq. 21.3 with J2000 start epoch).
    let zeta = (2306.2181 + (0.30188 + 0.017998 * t) * t) * t;
    let z = (2306.2181 + (1.09468 + 0.018203 * t) * t) * t;
    let theta = (2004.3109 - (0.42665 + 0.041833 * t) * t) * t;

    let arcsec = std::f64::consts::PI / (180.0 * 3600.0);
    let zeta = zeta * arcsec;
    let z = z * arcsec;
    let theta = theta * arcsec;

    let ra0 = ra_hours * 15.0_f64.to_radians();
    let dec0 = dec_deg.to_radians();

    // Eq. 21.4.
    let a = dec0.cos() * (ra0 + zeta).sin();
    let b = theta.cos() * dec0.cos() * (ra0 + zeta).cos() - theta.sin() * dec0.sin();
    let c = theta.sin() * dec0.cos() * (ra0 + zeta).cos() + theta.cos() * dec0.sin();

    let ra = z + a.atan2(b);
    let dec = c.asin();

    let mut ra_hours_out = ra.to_degrees() / 15.0;
    ra_hours_out = ra_hours_out.rem_euclid(24.0);
    (ra_hours_out, dec.to_degrees())
}

/// Precess J2000.0 coordinates to mean-of-date **now**.
pub fn j2000_to_jnow(ra_hours: f64, dec_deg: f64) -> (f64, f64) {
    let jd = nightshade_sequencer::meridian::julian_day(&chrono::Utc::now());
    precess_j2000_to_jd(ra_hours, dec_deg, jd)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Meeus example 21.b: θ Persei. After proper motion to the target
    /// epoch the J2000 place is α = 2h44m12.975s, δ = +49°13′39.90″;
    /// precessing to JD 2462088.69 (2028 Nov 13.19 TD) must give
    /// α = 2h46m11.331s, δ = +49°20′54.54″.
    #[test]
    fn meeus_example_21b() {
        let ra0 = 2.0 + 44.0 / 60.0 + 12.975 / 3600.0;
        let dec0 = 49.0 + 13.0 / 60.0 + 39.90 / 3600.0;
        let (ra, dec) = precess_j2000_to_jd(ra0, dec0, 2462088.69);

        let ra_expected = 2.0 + 46.0 / 60.0 + 11.331 / 3600.0;
        let dec_expected = 49.0 + 20.0 / 60.0 + 54.54 / 3600.0;

        // 0.1 s of RA ≈ 1.5″; 0.05″ in Dec. Generous but sub-arcsecond.
        assert!(
            (ra - ra_expected).abs() * 3600.0 < 0.1,
            "RA {} vs expected {}",
            ra,
            ra_expected
        );
        assert!(
            (dec - dec_expected).abs() * 3600.0 < 0.5,
            "Dec {} vs expected {}",
            dec,
            dec_expected
        );
    }

    /// At J2000 the transform must be the identity.
    #[test]
    fn identity_at_j2000() {
        let (ra, dec) = precess_j2000_to_jd(5.5, -20.25, 2451545.0);
        assert!((ra - 5.5).abs() < 1e-9);
        assert!((dec + 20.25).abs() < 1e-9);
    }

    /// RA must stay normalized across the 0h/24h wrap.
    #[test]
    fn ra_wraps_at_24h() {
        let (ra, _) = precess_j2000_to_jd(23.999, 0.0, 2461041.5); // ~2026
        assert!((0.0..24.0).contains(&ra), "ra={ra}");
    }
}
