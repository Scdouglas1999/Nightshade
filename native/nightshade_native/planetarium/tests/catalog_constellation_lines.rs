//! Constellation line catalog: count and per-constellation vertex totals vs v1.

use nightshade_planetarium::catalog::{
    find_by_abbreviation, line_vertex_count, ConstellationLines, CONSTELLATIONS,
    CONSTELLATION_COUNT, LINE_SEGMENT_COUNT, LINE_VERTEX_COUNT,
};

/// Per-constellation line segment counts from v1 `constellation_data.dart`.
const EXPECTED_SEGMENT_COUNTS: &[(&str, usize)] = &[
    ("And", 2),
    ("Ant", 2),
    ("Aps", 3),
    ("Aql", 4),
    ("Aqr", 6),
    ("Ara", 5),
    ("Ari", 3),
    ("Aur", 6),
    ("Boo", 6),
    ("CMa", 4),
    ("CMi", 1),
    ("CVn", 1),
    ("Cae", 2),
    ("Cam", 3),
    ("Cap", 7),
    ("Car", 6),
    ("Cas", 4),
    ("Cen", 6),
    ("Cep", 6),
    ("Cet", 5),
    ("Cha", 4),
    ("Cir", 2),
    ("Cnc", 4),
    ("Col", 4),
    ("Com", 2),
    ("CrA", 4),
    ("CrB", 6),
    ("Crt", 4),
    ("Cru", 2),
    ("Crv", 5),
    ("Cyg", 4),
    ("Del", 5),
    ("Dor", 3),
    ("Dra", 8),
    ("Equ", 2),
    ("Eri", 5),
    ("For", 2),
    ("Gem", 5),
    ("Gru", 4),
    ("Her", 8),
    ("Hor", 2),
    ("Hya", 8),
    ("Hyi", 3),
    ("Ind", 3),
    ("LMi", 2),
    ("Lac", 4),
    ("Leo", 7),
    ("Lep", 6),
    ("Lib", 4),
    ("Lup", 5),
    ("Lyn", 4),
    ("Lyr", 5),
    ("Men", 3),
    ("Mic", 2),
    ("Mon", 3),
    ("Mus", 4),
    ("Nor", 3),
    ("Oct", 3),
    ("Oph", 6),
    ("Ori", 7),
    ("Pav", 4),
    ("Peg", 6),
    ("Per", 4),
    ("Phe", 4),
    ("Pic", 2),
    ("PsA", 4),
    ("Psc", 8),
    ("Pup", 4),
    ("Pyx", 2),
    ("Ret", 4),
    ("Scl", 3),
    ("Sco", 5),
    ("Sct", 3),
    ("Ser", 6),
    ("Sex", 2),
    ("Sge", 3),
    ("Sgr", 9),
    ("Tau", 5),
    ("Tel", 2),
    ("TrA", 3),
    ("Tri", 3),
    ("Tuc", 3),
    ("UMa", 7),
    ("UMi", 6),
    ("Vel", 4),
    ("Vir", 4),
    ("Vol", 4),
    ("Vul", 1),
];

#[test]
fn constellation_count_is_88() {
    assert_eq!(CONSTELLATION_COUNT, 88);
    assert_eq!(CONSTELLATIONS.len(), 88);
    assert_eq!(EXPECTED_SEGMENT_COUNTS.len(), 88);
}

#[test]
fn total_line_vertex_count_matches_v1() {
    assert_eq!(LINE_SEGMENT_COUNT, 364);
    assert_eq!(LINE_VERTEX_COUNT, 728);
    assert_eq!(line_vertex_count(), LINE_VERTEX_COUNT);

    let computed_vertices: usize = CONSTELLATIONS.iter().map(|c| c.segments.len() * 2).sum();
    assert_eq!(computed_vertices, LINE_VERTEX_COUNT);
}

#[test]
fn per_constellation_vertex_counts_match_v1() {
    for &(abbrev, expected_segments) in EXPECTED_SEGMENT_COUNTS {
        let c = find_by_abbreviation(abbrev).unwrap_or_else(|| {
            panic!("missing constellation {abbrev}");
        });
        assert_eq!(
            c.segments.len(),
            expected_segments,
            "segment count for {abbrev}"
        );
        assert_eq!(
            c.segments.len() * 2,
            vertex_count(c),
            "vertex count for {abbrev}"
        );
    }
}

#[test]
fn find_by_abbreviation_case_insensitive() {
    let ori = find_by_abbreviation("ori").expect("Orion");
    assert_eq!(ori.abbrev, "Ori");
    assert_eq!(ori.name, "Orion");
    assert_eq!(ori.segments.len(), 7);
}

fn vertex_count(c: &ConstellationLines) -> usize {
    c.segments.len() * 2
}
