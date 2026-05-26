//! Variable star metadata catalog: count, v1 spot checks, query helpers.

use nightshade_planetarium::catalog::{
    brighter_than, by_constellation, by_kind, estimate_magnitude, find_by_name, icrs_dir,
    julian_date_from_utc, mag_range, search_variable_stars, variable_stars, VariableStarKind,
    VARIABLE_STAR_COUNT,
};

#[test]
fn star_count_matches_v1() {
    assert_eq!(VARIABLE_STAR_COUNT, 97);
    assert_eq!(variable_stars().len(), VARIABLE_STAR_COUNT);
}

#[test]
fn known_stars_match_v1_coordinates() {
    let mira = find_by_name("Mira").expect("Mira");
    assert_eq!(mira.constellation, "Cet");
    assert!((mira.ra_hours - 2.3219).abs() < 1e-4);
    assert!((mira.dec_deg - (-2.9776)).abs() < 1e-3);
    assert_eq!(mira.kind, VariableStarKind::Mira);
    assert_eq!(mira.period_days, Some(331.96));
    assert!((mira.mag_max - 2.0).abs() < 1e-3);
    assert!((mira.mag_min - 10.1).abs() < 1e-3);

    let algol = find_by_name("Algol").expect("Algol");
    assert_eq!(algol.kind, VariableStarKind::EclipsingAlgol);
    assert!((algol.ra_hours - 3.1361).abs() < 1e-4);
    assert!((algol.dec_deg - 40.9556).abs() < 1e-3);

    let delta_cep = find_by_name("Delta Cephei").expect("Delta Cep");
    assert_eq!(delta_cep.kind, VariableStarKind::Cepheid);
    assert!((delta_cep.period_days.unwrap() - 5.3663).abs() < 1e-3);
}

#[test]
fn kind_labels_match_v1() {
    assert_eq!(VariableStarKind::Mira.display_name(), "Mira (Long Period)");
    assert_eq!(VariableStarKind::Mira.abbreviation(), "M");
    assert_eq!(VariableStarKind::EclipsingAlgol.abbreviation(), "EA");
    assert_eq!(VariableStarKind::Other.display_name(), "Variable");
}

#[test]
fn mag_range_and_icrs_dir() {
    let mira = find_by_name("Mira").unwrap();
    assert!((mag_range(mira) - 8.1).abs() < 1e-3);
    let dir = icrs_dir(mira);
    let len = (dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2]).sqrt();
    assert!((len - 1.0).abs() < 1e-5);
}

#[test]
fn estimate_magnitude_no_period_returns_midpoint() {
    let gam_cas = find_by_name("Gamma Cassiopeiae").unwrap();
    assert!(gam_cas.period_days.is_none());
    let mag = estimate_magnitude(gam_cas, julian_date_from_utc(2020, 1, 1, 0, 0, 0));
    assert!((mag - 2.3).abs() < 0.01);
}

#[test]
fn brighter_than_filters_by_mag_max() {
    let bright = brighter_than(3.0);
    assert!(bright.iter().all(|s| s.mag_max <= 3.0));
    assert!(find_by_name("Mira").is_some_and(|s| bright.contains(&s)));
    assert!(find_by_name("Eta Carinae").is_some_and(|s| bright.contains(&s)));
}

#[test]
fn by_kind_and_constellation() {
    let miras = by_kind(VariableStarKind::Mira);
    assert!(miras.len() >= 15);
    assert!(miras.iter().all(|s| s.kind == VariableStarKind::Mira));

    let ori = by_constellation("Ori");
    assert!(!ori.is_empty());
    assert!(ori
        .iter()
        .all(|s| s.constellation.eq_ignore_ascii_case("Ori")));
}

#[test]
fn search_finds_name_designation_and_constellation() {
    let by_name = search_variable_stars("algol");
    assert!(by_name.iter().any(|s| s.name == "Algol"));

    let by_desig = search_variable_stars("omi cet");
    assert!(by_desig.iter().any(|s| s.name == "Mira"));

    let by_const = search_variable_stars("cep");
    assert!(by_const.iter().any(|s| s.constellation == "Cep"));
}

#[test]
fn find_by_name_case_insensitive() {
    assert_eq!(find_by_name("mira").unwrap().name, "Mira");
}
