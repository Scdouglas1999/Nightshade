//! ELP2000-82B truncated Moon — comparison to published approximate positions.
//!
//! Until `astrometry/mod.rs` exports `moon`, tests compile the module via `path`.

#[path = "../src/astrometry/moon.rs"]
mod moon;

use moon::{
    angular_separation_arcmin, ecliptic_to_equatorial_j2000_rad, moon_ecliptic_j2000_from_jd_tt,
    moon_equatorial_j2000_from_jd_tt, MoonEclipticJ2000, TRUNCATED_TERM_COUNT,
};

/// Task tolerance: truncated ~50-term series vs published approximate (< 1 arcmin).
const MAX_ARCMIN: f64 = 1.0;

/// Distance tolerance vs full main-problem reference (km).
const MAX_DIST_KM: f64 = 50.0;

fn ecliptic_separation_arcmin(a: MoonEclipticJ2000, b: (f64, f64)) -> f64 {
    let ra1 = a.longitude_deg.to_radians();
    let dec1 = a.latitude_deg.to_radians();
    let ra2 = b.0.to_radians();
    let dec2 = b.1.to_radians();
    angular_separation_arcmin(ra1, dec1, ra2, dec2)
}

/// Published reference: ELP2000-82B main problem (CDS VI/79, all 2645 terms), TT Julian date.
struct ElpMainProblemRef {
    jd_tt: f64,
    longitude_deg: f64,
    latitude_deg: f64,
    distance_km: f64,
}

const ELP_MAIN_PROBLEM_REFS: &[ElpMainProblemRef] = &[
    ElpMainProblemRef {
        jd_tt: 2_451_545.0,
        longitude_deg: 223.314_138_851_535_7,
        latitude_deg: 5.165_257_511_774_715,
        distance_km: 402_446.662_848_980_9,
    },
    ElpMainProblemRef {
        jd_tt: 2_458_850.5,
        longitude_deg: 357.731_318_328_678_6,
        latitude_deg: -5.200_333_276_124_04,
        distance_km: 404_576.372_070_166_75,
    },
    ElpMainProblemRef {
        jd_tt: 2_460_477.0,
        longitude_deg: 188.413_106_591_966_43,
        latitude_deg: 0.363_786_356_337_137,
        distance_km: 403_524.006_542_387_77,
    },
    ElpMainProblemRef {
        jd_tt: 2_448_068.5,
        longitude_deg: 137.352_378_589_436_4,
        latitude_deg: -0.864_072_446_904_796_2,
        distance_km: 375_741.521_020_332_7,
    },
];

/// J2000.0: DE421 geocentric ecliptic (Skyfield); ≈ almanac-grade at the epoch.
const J2000_DE421_ECLIPTIC: (f64, f64, f64) = (223.318_025_949_222_1, 5.171_309_927_234_373, 402_414.600_155_946_5);

#[test]
fn truncated_term_count_is_fifty() {
    assert_eq!(TRUNCATED_TERM_COUNT, 50);
}

#[test]
fn within_one_arcmin_of_elp_main_problem_at_four_epochs() {
    for r in ELP_MAIN_PROBLEM_REFS {
        let got = moon_ecliptic_j2000_from_jd_tt(r.jd_tt);
        let sep = ecliptic_separation_arcmin(got, (r.longitude_deg, r.latitude_deg));
        assert!(
            sep < MAX_ARCMIN,
            "JD {} ecliptic sep {sep:.4}′ (max {MAX_ARCMIN}′)",
            r.jd_tt
        );
        assert!(
            (got.distance_km - r.distance_km).abs() < MAX_DIST_KM,
            "JD {} distance Δ {} km",
            r.jd_tt,
            got.distance_km - r.distance_km
        );

        let eq = moon_equatorial_j2000_from_jd_tt(r.jd_tt);
        let (ref_ra, ref_dec) =
            ecliptic_to_equatorial_j2000_rad(r.longitude_deg, r.latitude_deg, r.jd_tt);
        let sep_eq = angular_separation_arcmin(eq.ra_rad, eq.dec_rad, ref_ra, ref_dec);
        assert!(
            sep_eq < MAX_ARCMIN,
            "JD {} equatorial vs ecliptic ref sep {sep_eq:.4}′",
            r.jd_tt
        );
    }
}

#[test]
fn j2000_within_one_arcmin_of_de421_ecliptic() {
    let got = moon_ecliptic_j2000_from_jd_tt(2_451_545.0);
    let sep = ecliptic_separation_arcmin(
        got,
        (J2000_DE421_ECLIPTIC.0, J2000_DE421_ECLIPTIC.1),
    );
    assert!(
        sep < MAX_ARCMIN,
        "J2000 vs DE421 ecliptic separation {sep:.4}′"
    );
}

#[test]
fn longitude_normalized_zero_to_three_sixty() {
    let ecl = moon_ecliptic_j2000_from_jd_tt(2_458_850.5);
    assert!((0.0..360.0).contains(&ecl.longitude_deg));
}

#[test]
fn j2000_distance_near_published_km() {
    let ecl = moon_ecliptic_j2000_from_jd_tt(2_451_545.0);
    assert!((ecl.distance_km - J2000_DE421_ECLIPTIC.2).abs() < MAX_DIST_KM);
}
