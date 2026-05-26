//! IAU constellation stick-figure line segments (J2000 RA hours / Dec degrees).
//!
//! Ported from `packages/nightshade_planetarium/lib/src/catalogs/constellation_data.dart`.
//! Boundaries are a separate table (future task).

/// One line segment between two J2000 equatorial endpoints.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ConstellationSegment {
    /// Start right ascension (hours).
    pub start_ra_hours: f32,
    /// Start declination (degrees).
    pub start_dec_deg: f32,
    /// End right ascension (hours).
    pub end_ra_hours: f32,
    /// End declination (degrees).
    pub end_dec_deg: f32,
}

/// Stick-figure lines for one IAU constellation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ConstellationLines {
    /// Three-letter IAU abbreviation (e.g. `"Ori"`).
    pub abbrev: &'static str,
    /// English proper name.
    pub name: &'static str,
    /// Label centroid RA (hours).
    pub center_ra_hours: f32,
    /// Label centroid declination (degrees).
    pub center_dec_deg: f32,
    /// Line segments for this constellation.
    pub segments: &'static [ConstellationSegment],
}

/// Number of IAU constellations with stick-figure line data.
pub const CONSTELLATION_COUNT: usize = 88;

/// Total line segments across all constellations.
pub const LINE_SEGMENT_COUNT: usize = 364;

/// GPU line vertices (two per segment: start + end).
pub const LINE_VERTEX_COUNT: usize = 728;

/// Convert J2000 equatorial coordinates to a unit ICRS direction.
#[must_use]
pub fn icrs_dir_from_j2000(ra_hours: f32, dec_deg: f32) -> [f32; 3] {
    let ra_rad = ra_hours * (std::f32::consts::PI / 12.0);
    let dec_rad = dec_deg.to_radians();
    let (sin_dec, cos_dec) = dec_rad.sin_cos();
    let (sin_ra, cos_ra) = ra_rad.sin_cos();
    [cos_dec * cos_ra, cos_dec * sin_ra, sin_dec]
}

/// Total GPU vertices for constellation stick figures (2 per segment).
#[must_use]
pub fn line_vertex_count() -> usize {
    LINE_VERTEX_COUNT
}

/// Look up constellation line data by IAU abbreviation (case-insensitive).
#[must_use]
pub fn find_by_abbreviation(abbrev: &str) -> Option<&'static ConstellationLines> {
    let key = abbrev.trim();
    CONSTELLATIONS
        .iter()
        .find(|c| c.abbrev.eq_ignore_ascii_case(key))
}

const SEGMENTS_ORI: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 5.9195,
        start_dec_deg: 7.407,
        end_ra_hours: 5.5334,
        end_dec_deg: -0.2991,
    },
    ConstellationSegment {
        start_ra_hours: 5.4188,
        start_dec_deg: 6.3497,
        end_ra_hours: 5.6793,
        end_dec_deg: -1.9426,
    },
    ConstellationSegment {
        start_ra_hours: 5.5334,
        start_dec_deg: -0.2991,
        end_ra_hours: 5.6036,
        end_dec_deg: -1.2019,
    },
    ConstellationSegment {
        start_ra_hours: 5.6036,
        start_dec_deg: -1.2019,
        end_ra_hours: 5.6793,
        end_dec_deg: -1.9426,
    },
    ConstellationSegment {
        start_ra_hours: 5.6793,
        start_dec_deg: -1.9426,
        end_ra_hours: 5.7958,
        end_dec_deg: -9.6697,
    },
    ConstellationSegment {
        start_ra_hours: 5.5334,
        start_dec_deg: -0.2991,
        end_ra_hours: 5.2422,
        end_dec_deg: -8.2017,
    },
    ConstellationSegment {
        start_ra_hours: 5.9195,
        start_dec_deg: 7.407,
        end_ra_hours: 5.4188,
        end_dec_deg: 6.3497,
    },
];

const SEGMENTS_UMA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 11.0621,
        start_dec_deg: 61.751,
        end_ra_hours: 11.0306,
        end_dec_deg: 56.3824,
    },
    ConstellationSegment {
        start_ra_hours: 11.0306,
        start_dec_deg: 56.3824,
        end_ra_hours: 11.8968,
        end_dec_deg: 53.6948,
    },
    ConstellationSegment {
        start_ra_hours: 11.8968,
        start_dec_deg: 53.6948,
        end_ra_hours: 12.2571,
        end_dec_deg: 57.0326,
    },
    ConstellationSegment {
        start_ra_hours: 12.2571,
        start_dec_deg: 57.0326,
        end_ra_hours: 11.0621,
        end_dec_deg: 61.751,
    },
    ConstellationSegment {
        start_ra_hours: 12.2571,
        start_dec_deg: 57.0326,
        end_ra_hours: 12.9004,
        end_dec_deg: 55.9598,
    },
    ConstellationSegment {
        start_ra_hours: 12.9004,
        start_dec_deg: 55.9598,
        end_ra_hours: 13.3988,
        end_dec_deg: 54.9254,
    },
    ConstellationSegment {
        start_ra_hours: 13.3988,
        start_dec_deg: 54.9254,
        end_ra_hours: 13.7923,
        end_dec_deg: 49.3133,
    },
];

const SEGMENTS_CAS: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 0.153,
        start_dec_deg: 59.1498,
        end_ra_hours: 0.6752,
        end_dec_deg: 56.5373,
    },
    ConstellationSegment {
        start_ra_hours: 0.6752,
        start_dec_deg: 56.5373,
        end_ra_hours: 0.9453,
        end_dec_deg: 60.7167,
    },
    ConstellationSegment {
        start_ra_hours: 0.9453,
        start_dec_deg: 60.7167,
        end_ra_hours: 1.4306,
        end_dec_deg: 60.2352,
    },
    ConstellationSegment {
        start_ra_hours: 1.4306,
        start_dec_deg: 60.2352,
        end_ra_hours: 1.9065,
        end_dec_deg: 63.67,
    },
];

const SEGMENTS_CYG: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 20.6905,
        start_dec_deg: 45.2803,
        end_ra_hours: 19.512,
        end_dec_deg: 27.9597,
    },
    ConstellationSegment {
        start_ra_hours: 20.3706,
        start_dec_deg: 40.2567,
        end_ra_hours: 19.7489,
        end_dec_deg: 45.1309,
    },
    ConstellationSegment {
        start_ra_hours: 20.3706,
        start_dec_deg: 40.2567,
        end_ra_hours: 21.2156,
        end_dec_deg: 30.2269,
    },
    ConstellationSegment {
        start_ra_hours: 20.6905,
        start_dec_deg: 45.2803,
        end_ra_hours: 20.3706,
        end_dec_deg: 40.2567,
    },
];

const SEGMENTS_LEO: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 10.1395,
        start_dec_deg: 11.9672,
        end_ra_hours: 10.3328,
        end_dec_deg: 19.8415,
    },
    ConstellationSegment {
        start_ra_hours: 10.3328,
        start_dec_deg: 19.8415,
        end_ra_hours: 10.122,
        end_dec_deg: 23.7743,
    },
    ConstellationSegment {
        start_ra_hours: 10.122,
        start_dec_deg: 23.7743,
        end_ra_hours: 10.2787,
        end_dec_deg: 26.0072,
    },
    ConstellationSegment {
        start_ra_hours: 10.2787,
        start_dec_deg: 26.0072,
        end_ra_hours: 9.7644,
        end_dec_deg: 26.0068,
    },
    ConstellationSegment {
        start_ra_hours: 10.2787,
        start_dec_deg: 26.0072,
        end_ra_hours: 11.2351,
        end_dec_deg: 20.5236,
    },
    ConstellationSegment {
        start_ra_hours: 11.2351,
        start_dec_deg: 20.5236,
        end_ra_hours: 11.8177,
        end_dec_deg: 14.572,
    },
    ConstellationSegment {
        start_ra_hours: 10.1395,
        start_dec_deg: 11.9672,
        end_ra_hours: 11.2351,
        end_dec_deg: 20.5236,
    },
];

const SEGMENTS_SCO: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 16.0053,
        start_dec_deg: -22.6217,
        end_ra_hours: 16.4901,
        end_dec_deg: -26.432,
    },
    ConstellationSegment {
        start_ra_hours: 16.4901,
        start_dec_deg: -26.432,
        end_ra_hours: 16.8364,
        end_dec_deg: -34.2933,
    },
    ConstellationSegment {
        start_ra_hours: 16.8364,
        start_dec_deg: -34.2933,
        end_ra_hours: 17.2024,
        end_dec_deg: -37.2959,
    },
    ConstellationSegment {
        start_ra_hours: 17.2024,
        start_dec_deg: -37.2959,
        end_ra_hours: 17.5601,
        end_dec_deg: -37.1038,
    },
    ConstellationSegment {
        start_ra_hours: 17.5601,
        start_dec_deg: -37.1038,
        end_ra_hours: 17.7081,
        end_dec_deg: -39.0299,
    },
];

const SEGMENTS_GEM: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 7.5767,
        start_dec_deg: 31.8884,
        end_ra_hours: 7.7553,
        end_dec_deg: 28.0262,
    },
    ConstellationSegment {
        start_ra_hours: 7.5767,
        start_dec_deg: 31.8884,
        end_ra_hours: 7.0683,
        end_dec_deg: 20.5703,
    },
    ConstellationSegment {
        start_ra_hours: 7.7553,
        start_dec_deg: 28.0262,
        end_ra_hours: 7.185,
        end_dec_deg: 16.5403,
    },
    ConstellationSegment {
        start_ra_hours: 7.0683,
        start_dec_deg: 20.5703,
        end_ra_hours: 6.6285,
        end_dec_deg: 16.3993,
    },
    ConstellationSegment {
        start_ra_hours: 7.185,
        start_dec_deg: 16.5403,
        end_ra_hours: 6.7328,
        end_dec_deg: 12.8959,
    },
];

const SEGMENTS_PEG: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 0.1398,
        start_dec_deg: 29.0904,
        end_ra_hours: 23.0629,
        end_dec_deg: 28.0828,
    },
    ConstellationSegment {
        start_ra_hours: 23.0629,
        start_dec_deg: 28.0828,
        end_ra_hours: 23.0798,
        end_dec_deg: 15.2053,
    },
    ConstellationSegment {
        start_ra_hours: 23.0798,
        start_dec_deg: 15.2053,
        end_ra_hours: 0.2201,
        end_dec_deg: 15.1836,
    },
    ConstellationSegment {
        start_ra_hours: 0.2201,
        start_dec_deg: 15.1836,
        end_ra_hours: 0.1398,
        end_dec_deg: 29.0904,
    },
    ConstellationSegment {
        start_ra_hours: 23.0629,
        start_dec_deg: 28.0828,
        end_ra_hours: 22.1168,
        end_dec_deg: 25.345,
    },
    ConstellationSegment {
        start_ra_hours: 22.1168,
        start_dec_deg: 25.345,
        end_ra_hours: 21.744,
        end_dec_deg: 9.8749,
    },
];

const SEGMENTS_AND: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 0.1398,
        start_dec_deg: 29.0904,
        end_ra_hours: 1.1621,
        end_dec_deg: 35.6206,
    },
    ConstellationSegment {
        start_ra_hours: 1.1621,
        start_dec_deg: 35.6206,
        end_ra_hours: 2.065,
        end_dec_deg: 42.3297,
    },
];

const SEGMENTS_TAU: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 4.5988,
        start_dec_deg: 16.5093,
        end_ra_hours: 4.4762,
        end_dec_deg: 15.962,
    },
    ConstellationSegment {
        start_ra_hours: 4.4762,
        start_dec_deg: 15.962,
        end_ra_hours: 4.3291,
        end_dec_deg: 15.6277,
    },
    ConstellationSegment {
        start_ra_hours: 4.3291,
        start_dec_deg: 15.6277,
        end_ra_hours: 4.0113,
        end_dec_deg: 12.4904,
    },
    ConstellationSegment {
        start_ra_hours: 4.5988,
        start_dec_deg: 16.5093,
        end_ra_hours: 5.4382,
        end_dec_deg: 28.6074,
    },
    ConstellationSegment {
        start_ra_hours: 4.4762,
        start_dec_deg: 15.962,
        end_ra_hours: 5.6276,
        end_dec_deg: 21.1425,
    },
];

const SEGMENTS_CMA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 6.7524,
        start_dec_deg: -16.7161,
        end_ra_hours: 6.3783,
        end_dec_deg: -17.9559,
    },
    ConstellationSegment {
        start_ra_hours: 6.7524,
        start_dec_deg: -16.7161,
        end_ra_hours: 7.1399,
        end_dec_deg: -26.3932,
    },
    ConstellationSegment {
        start_ra_hours: 7.1399,
        start_dec_deg: -26.3932,
        end_ra_hours: 6.9771,
        end_dec_deg: -28.9722,
    },
    ConstellationSegment {
        start_ra_hours: 6.9771,
        start_dec_deg: -28.9722,
        end_ra_hours: 6.6111,
        end_dec_deg: -32.5085,
    },
];

const SEGMENTS_LYR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 18.6156,
        start_dec_deg: 38.7837,
        end_ra_hours: 18.7462,
        end_dec_deg: 37.605,
    },
    ConstellationSegment {
        start_ra_hours: 18.6156,
        start_dec_deg: 38.7837,
        end_ra_hours: 18.9782,
        end_dec_deg: 36.8986,
    },
    ConstellationSegment {
        start_ra_hours: 18.9782,
        start_dec_deg: 36.8986,
        end_ra_hours: 18.9077,
        end_dec_deg: 33.3627,
    },
    ConstellationSegment {
        start_ra_hours: 18.9077,
        start_dec_deg: 33.3627,
        end_ra_hours: 18.8348,
        end_dec_deg: 33.3629,
    },
    ConstellationSegment {
        start_ra_hours: 18.8348,
        start_dec_deg: 33.3629,
        end_ra_hours: 18.9782,
        end_dec_deg: 36.8986,
    },
];

const SEGMENTS_AQL: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 19.8464,
        start_dec_deg: 8.8683,
        end_ra_hours: 19.7714,
        end_dec_deg: 10.6132,
    },
    ConstellationSegment {
        start_ra_hours: 19.8464,
        start_dec_deg: 8.8683,
        end_ra_hours: 19.9216,
        end_dec_deg: 6.4067,
    },
    ConstellationSegment {
        start_ra_hours: 19.7714,
        start_dec_deg: 10.6132,
        end_ra_hours: 19.1042,
        end_dec_deg: 13.8635,
    },
    ConstellationSegment {
        start_ra_hours: 19.9216,
        start_dec_deg: 6.4067,
        end_ra_hours: 20.1886,
        end_dec_deg: -0.8215,
    },
];

const SEGMENTS_CRU: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 12.5194,
        start_dec_deg: -57.1132,
        end_ra_hours: 12.4433,
        end_dec_deg: -63.099,
    },
    ConstellationSegment {
        start_ra_hours: 12.7953,
        start_dec_deg: -59.6888,
        end_ra_hours: 12.2523,
        end_dec_deg: -58.7489,
    },
];

const SEGMENTS_PER: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 3.4054,
        start_dec_deg: 49.8612,
        end_ra_hours: 3.0795,
        end_dec_deg: 53.5065,
    },
    ConstellationSegment {
        start_ra_hours: 3.4054,
        start_dec_deg: 49.8612,
        end_ra_hours: 3.7155,
        end_dec_deg: 47.7876,
    },
    ConstellationSegment {
        start_ra_hours: 3.7155,
        start_dec_deg: 47.7876,
        end_ra_hours: 3.1364,
        end_dec_deg: 40.9557,
    },
    ConstellationSegment {
        start_ra_hours: 3.1364,
        start_dec_deg: 40.9557,
        end_ra_hours: 2.8449,
        end_dec_deg: 38.3188,
    },
];

const SEGMENTS_BOO: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 14.2612,
        start_dec_deg: 19.1825,
        end_ra_hours: 13.9116,
        end_dec_deg: 18.3979,
    },
    ConstellationSegment {
        start_ra_hours: 13.9116,
        start_dec_deg: 18.3979,
        end_ra_hours: 14.5308,
        end_dec_deg: 30.3713,
    },
    ConstellationSegment {
        start_ra_hours: 14.5308,
        start_dec_deg: 30.3713,
        end_ra_hours: 14.7499,
        end_dec_deg: 27.0743,
    },
    ConstellationSegment {
        start_ra_hours: 14.7499,
        start_dec_deg: 27.0743,
        end_ra_hours: 14.2612,
        end_dec_deg: 19.1825,
    },
    ConstellationSegment {
        start_ra_hours: 14.5308,
        start_dec_deg: 30.3713,
        end_ra_hours: 15.0322,
        end_dec_deg: 40.3906,
    },
    ConstellationSegment {
        start_ra_hours: 14.7499,
        start_dec_deg: 27.0743,
        end_ra_hours: 15.0322,
        end_dec_deg: 40.3906,
    },
];

const SEGMENTS_VIR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 13.4199,
        start_dec_deg: -11.1614,
        end_ra_hours: 12.6943,
        end_dec_deg: -1.4494,
    },
    ConstellationSegment {
        start_ra_hours: 12.6943,
        start_dec_deg: -1.4494,
        end_ra_hours: 12.9264,
        end_dec_deg: 3.3975,
    },
    ConstellationSegment {
        start_ra_hours: 12.9264,
        start_dec_deg: 3.3975,
        end_ra_hours: 13.0367,
        end_dec_deg: 10.9592,
    },
    ConstellationSegment {
        start_ra_hours: 12.6943,
        start_dec_deg: -1.4494,
        end_ra_hours: 11.8446,
        end_dec_deg: 1.7648,
    },
];

const SEGMENTS_UMI: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 2.5302,
        start_dec_deg: 89.2641,
        end_ra_hours: 17.5369,
        end_dec_deg: 86.5863,
    },
    ConstellationSegment {
        start_ra_hours: 17.5369,
        start_dec_deg: 86.5863,
        end_ra_hours: 16.2917,
        end_dec_deg: 75.7555,
    },
    ConstellationSegment {
        start_ra_hours: 16.2917,
        start_dec_deg: 75.7555,
        end_ra_hours: 15.7345,
        end_dec_deg: 77.7945,
    },
    ConstellationSegment {
        start_ra_hours: 15.7345,
        start_dec_deg: 77.7945,
        end_ra_hours: 14.8451,
        end_dec_deg: 74.1554,
    },
    ConstellationSegment {
        start_ra_hours: 14.8451,
        start_dec_deg: 74.1554,
        end_ra_hours: 15.3453,
        end_dec_deg: 71.834,
    },
    ConstellationSegment {
        start_ra_hours: 15.3453,
        start_dec_deg: 71.834,
        end_ra_hours: 16.2917,
        end_dec_deg: 75.7555,
    },
];

const SEGMENTS_DRA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 17.5074,
        start_dec_deg: 52.3014,
        end_ra_hours: 17.5073,
        end_dec_deg: 51.489,
    },
    ConstellationSegment {
        start_ra_hours: 17.5073,
        start_dec_deg: 51.489,
        end_ra_hours: 17.1465,
        end_dec_deg: 54.4689,
    },
    ConstellationSegment {
        start_ra_hours: 17.1465,
        start_dec_deg: 54.4689,
        end_ra_hours: 16.401,
        end_dec_deg: 61.5142,
    },
    ConstellationSegment {
        start_ra_hours: 16.401,
        start_dec_deg: 61.5142,
        end_ra_hours: 15.4155,
        end_dec_deg: 58.966,
    },
    ConstellationSegment {
        start_ra_hours: 15.4155,
        start_dec_deg: 58.966,
        end_ra_hours: 14.0732,
        end_dec_deg: 64.3758,
    },
    ConstellationSegment {
        start_ra_hours: 14.0732,
        start_dec_deg: 64.3758,
        end_ra_hours: 12.558,
        end_dec_deg: 69.7882,
    },
    ConstellationSegment {
        start_ra_hours: 12.558,
        start_dec_deg: 69.7882,
        end_ra_hours: 11.5233,
        end_dec_deg: 69.3311,
    },
    ConstellationSegment {
        start_ra_hours: 17.5074,
        start_dec_deg: 52.3014,
        end_ra_hours: 17.1465,
        end_dec_deg: 54.4689,
    },
];

const SEGMENTS_CEP: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 21.3097,
        start_dec_deg: 62.5856,
        end_ra_hours: 23.6557,
        end_dec_deg: 77.6323,
    },
    ConstellationSegment {
        start_ra_hours: 23.6557,
        start_dec_deg: 77.6323,
        end_ra_hours: 23.1888,
        end_dec_deg: 75.3875,
    },
    ConstellationSegment {
        start_ra_hours: 23.1888,
        start_dec_deg: 75.3875,
        end_ra_hours: 22.4868,
        end_dec_deg: 58.2012,
    },
    ConstellationSegment {
        start_ra_hours: 22.4868,
        start_dec_deg: 58.2012,
        end_ra_hours: 21.3097,
        end_dec_deg: 62.5856,
    },
    ConstellationSegment {
        start_ra_hours: 22.4868,
        start_dec_deg: 58.2012,
        end_ra_hours: 22.8282,
        end_dec_deg: 66.2007,
    },
    ConstellationSegment {
        start_ra_hours: 22.8282,
        start_dec_deg: 66.2007,
        end_ra_hours: 23.1888,
        end_dec_deg: 75.3875,
    },
];

const SEGMENTS_SGR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 18.4029,
        start_dec_deg: -34.3844,
        end_ra_hours: 18.3498,
        end_dec_deg: -29.8282,
    },
    ConstellationSegment {
        start_ra_hours: 18.3498,
        start_dec_deg: -29.8282,
        end_ra_hours: 18.2296,
        end_dec_deg: -25.4217,
    },
    ConstellationSegment {
        start_ra_hours: 18.2296,
        start_dec_deg: -25.4217,
        end_ra_hours: 18.921,
        end_dec_deg: -26.2967,
    },
    ConstellationSegment {
        start_ra_hours: 18.921,
        start_dec_deg: -26.2967,
        end_ra_hours: 19.1632,
        end_dec_deg: -27.6698,
    },
    ConstellationSegment {
        start_ra_hours: 19.1632,
        start_dec_deg: -27.6698,
        end_ra_hours: 19.0434,
        end_dec_deg: -29.8801,
    },
    ConstellationSegment {
        start_ra_hours: 19.0434,
        start_dec_deg: -29.8801,
        end_ra_hours: 18.4029,
        end_dec_deg: -34.3844,
    },
    ConstellationSegment {
        start_ra_hours: 18.2296,
        start_dec_deg: -25.4217,
        end_ra_hours: 18.7608,
        end_dec_deg: -26.9907,
    },
    ConstellationSegment {
        start_ra_hours: 18.7608,
        start_dec_deg: -26.9907,
        end_ra_hours: 18.921,
        end_dec_deg: -26.2967,
    },
    ConstellationSegment {
        start_ra_hours: 18.4029,
        start_dec_deg: -34.3844,
        end_ra_hours: 18.2965,
        end_dec_deg: -36.7615,
    },
];

const SEGMENTS_CAP: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 20.294,
        start_dec_deg: -12.5082,
        end_ra_hours: 20.3502,
        end_dec_deg: -14.7815,
    },
    ConstellationSegment {
        start_ra_hours: 20.3502,
        start_dec_deg: -14.7815,
        end_ra_hours: 21.0991,
        end_dec_deg: -17.2327,
    },
    ConstellationSegment {
        start_ra_hours: 21.0991,
        start_dec_deg: -17.2327,
        end_ra_hours: 21.3716,
        end_dec_deg: -16.8344,
    },
    ConstellationSegment {
        start_ra_hours: 21.3716,
        start_dec_deg: -16.8344,
        end_ra_hours: 21.618,
        end_dec_deg: -16.6617,
    },
    ConstellationSegment {
        start_ra_hours: 21.618,
        start_dec_deg: -16.6617,
        end_ra_hours: 21.4444,
        end_dec_deg: -22.4115,
    },
    ConstellationSegment {
        start_ra_hours: 21.4444,
        start_dec_deg: -22.4115,
        end_ra_hours: 20.768,
        end_dec_deg: -25.271,
    },
    ConstellationSegment {
        start_ra_hours: 20.768,
        start_dec_deg: -25.271,
        end_ra_hours: 20.294,
        end_dec_deg: -12.5082,
    },
];

const SEGMENTS_AQR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 22.0965,
        start_dec_deg: -0.3197,
        end_ra_hours: 22.3614,
        end_dec_deg: -1.3875,
    },
    ConstellationSegment {
        start_ra_hours: 22.3614,
        start_dec_deg: -1.3875,
        end_ra_hours: 22.4806,
        end_dec_deg: -0.0198,
    },
    ConstellationSegment {
        start_ra_hours: 22.4806,
        start_dec_deg: -0.0198,
        end_ra_hours: 22.877,
        end_dec_deg: -7.5799,
    },
    ConstellationSegment {
        start_ra_hours: 22.877,
        start_dec_deg: -7.5799,
        end_ra_hours: 22.5906,
        end_dec_deg: -13.5925,
    },
    ConstellationSegment {
        start_ra_hours: 22.5906,
        start_dec_deg: -13.5925,
        end_ra_hours: 22.8264,
        end_dec_deg: -13.5924,
    },
    ConstellationSegment {
        start_ra_hours: 22.877,
        start_dec_deg: -7.5799,
        end_ra_hours: 22.8264,
        end_dec_deg: -13.5924,
    },
];

const SEGMENTS_PSC: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 2.034,
        start_dec_deg: 2.7636,
        end_ra_hours: 1.5247,
        end_dec_deg: 15.3458,
    },
    ConstellationSegment {
        start_ra_hours: 1.5247,
        start_dec_deg: 15.3458,
        end_ra_hours: 1.6905,
        end_dec_deg: 19.2934,
    },
    ConstellationSegment {
        start_ra_hours: 1.6905,
        start_dec_deg: 19.2934,
        end_ra_hours: 1.0496,
        end_dec_deg: 21.4716,
    },
    ConstellationSegment {
        start_ra_hours: 1.0496,
        start_dec_deg: 21.4716,
        end_ra_hours: 0.8114,
        end_dec_deg: 7.5853,
    },
    ConstellationSegment {
        start_ra_hours: 0.8114,
        start_dec_deg: 7.5853,
        end_ra_hours: 23.6659,
        end_dec_deg: 5.6262,
    },
    ConstellationSegment {
        start_ra_hours: 23.6659,
        start_dec_deg: 5.6262,
        end_ra_hours: 23.4487,
        end_dec_deg: 6.379,
    },
    ConstellationSegment {
        start_ra_hours: 23.4487,
        start_dec_deg: 6.379,
        end_ra_hours: 23.286,
        end_dec_deg: 3.2821,
    },
    ConstellationSegment {
        start_ra_hours: 23.286,
        start_dec_deg: 3.2821,
        end_ra_hours: 23.4487,
        end_dec_deg: 6.379,
    },
];

const SEGMENTS_ARI: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 2.1195,
        start_dec_deg: 23.4624,
        end_ra_hours: 1.9106,
        end_dec_deg: 20.8081,
    },
    ConstellationSegment {
        start_ra_hours: 1.9106,
        start_dec_deg: 20.8081,
        end_ra_hours: 1.892,
        end_dec_deg: 19.294,
    },
    ConstellationSegment {
        start_ra_hours: 2.1195,
        start_dec_deg: 23.4624,
        end_ra_hours: 2.8332,
        end_dec_deg: 27.2607,
    },
];

const SEGMENTS_CNC: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 8.7447,
        start_dec_deg: 18.1542,
        end_ra_hours: 8.7213,
        end_dec_deg: 21.4686,
    },
    ConstellationSegment {
        start_ra_hours: 8.7213,
        start_dec_deg: 21.4686,
        end_ra_hours: 8.2752,
        end_dec_deg: 9.1857,
    },
    ConstellationSegment {
        start_ra_hours: 8.7213,
        start_dec_deg: 21.4686,
        end_ra_hours: 9.1843,
        end_dec_deg: 22.0431,
    },
    ConstellationSegment {
        start_ra_hours: 8.7447,
        start_dec_deg: 18.1542,
        end_ra_hours: 8.9778,
        end_dec_deg: 11.8577,
    },
];

const SEGMENTS_LIB: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 14.8461,
        start_dec_deg: -16.0418,
        end_ra_hours: 15.2832,
        end_dec_deg: -9.3829,
    },
    ConstellationSegment {
        start_ra_hours: 15.2832,
        start_dec_deg: -9.3829,
        end_ra_hours: 15.5921,
        end_dec_deg: -14.7894,
    },
    ConstellationSegment {
        start_ra_hours: 15.5921,
        start_dec_deg: -14.7894,
        end_ra_hours: 14.8461,
        end_dec_deg: -16.0418,
    },
    ConstellationSegment {
        start_ra_hours: 15.5921,
        start_dec_deg: -14.7894,
        end_ra_hours: 15.0681,
        end_dec_deg: -25.2819,
    },
];

const SEGMENTS_OPH: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 17.5822,
        start_dec_deg: 12.56,
        end_ra_hours: 17.7243,
        end_dec_deg: 4.5674,
    },
    ConstellationSegment {
        start_ra_hours: 17.7243,
        start_dec_deg: 4.5674,
        end_ra_hours: 17.1726,
        end_dec_deg: -15.7249,
    },
    ConstellationSegment {
        start_ra_hours: 17.1726,
        start_dec_deg: -15.7249,
        end_ra_hours: 16.619,
        end_dec_deg: -10.5671,
    },
    ConstellationSegment {
        start_ra_hours: 16.619,
        start_dec_deg: -10.5671,
        end_ra_hours: 16.3052,
        end_dec_deg: -4.6925,
    },
    ConstellationSegment {
        start_ra_hours: 16.3052,
        start_dec_deg: -4.6925,
        end_ra_hours: 17.5822,
        end_dec_deg: 12.56,
    },
    ConstellationSegment {
        start_ra_hours: 17.1726,
        start_dec_deg: -15.7249,
        end_ra_hours: 17.7981,
        end_dec_deg: -24.9996,
    },
];

const SEGMENTS_SER: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 15.7378,
        start_dec_deg: 6.4254,
        end_ra_hours: 15.812,
        end_dec_deg: 15.4218,
    },
    ConstellationSegment {
        start_ra_hours: 15.812,
        start_dec_deg: 15.4218,
        end_ra_hours: 15.5802,
        end_dec_deg: 15.6618,
    },
    ConstellationSegment {
        start_ra_hours: 15.7378,
        start_dec_deg: 6.4254,
        end_ra_hours: 15.9423,
        end_dec_deg: 3.4335,
    },
    ConstellationSegment {
        start_ra_hours: 15.9423,
        start_dec_deg: 3.4335,
        end_ra_hours: 15.847,
        end_dec_deg: 4.4776,
    },
    ConstellationSegment {
        start_ra_hours: 18.3553,
        start_dec_deg: -2.8987,
        end_ra_hours: 18.9367,
        end_dec_deg: 4.2037,
    },
    ConstellationSegment {
        start_ra_hours: 18.9367,
        start_dec_deg: 4.2037,
        end_ra_hours: 18.3553,
        end_dec_deg: -2.8987,
    },
];

const SEGMENTS_HER: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 16.5034,
        start_dec_deg: 21.4897,
        end_ra_hours: 16.3649,
        end_dec_deg: 19.153,
    },
    ConstellationSegment {
        start_ra_hours: 16.3649,
        start_dec_deg: 19.153,
        end_ra_hours: 17.2508,
        end_dec_deg: 24.8392,
    },
    ConstellationSegment {
        start_ra_hours: 17.2508,
        start_dec_deg: 24.8392,
        end_ra_hours: 16.688,
        end_dec_deg: 31.6028,
    },
    ConstellationSegment {
        start_ra_hours: 16.688,
        start_dec_deg: 31.6028,
        end_ra_hours: 16.5034,
        end_dec_deg: 21.4897,
    },
    ConstellationSegment {
        start_ra_hours: 16.5034,
        start_dec_deg: 21.4897,
        end_ra_hours: 16.1464,
        end_dec_deg: 14.0333,
    },
    ConstellationSegment {
        start_ra_hours: 16.3649,
        start_dec_deg: 19.153,
        end_ra_hours: 17.2442,
        end_dec_deg: 14.3902,
    },
    ConstellationSegment {
        start_ra_hours: 17.2508,
        start_dec_deg: 24.8392,
        end_ra_hours: 17.5822,
        end_dec_deg: 12.56,
    },
    ConstellationSegment {
        start_ra_hours: 16.688,
        start_dec_deg: 31.6028,
        end_ra_hours: 17.3941,
        end_dec_deg: 37.1459,
    },
];

const SEGMENTS_AUR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 5.2783,
        start_dec_deg: 45.9981,
        end_ra_hours: 5.9953,
        end_dec_deg: 44.9474,
    },
    ConstellationSegment {
        start_ra_hours: 5.9953,
        start_dec_deg: 44.9474,
        end_ra_hours: 5.992,
        end_dec_deg: 37.2126,
    },
    ConstellationSegment {
        start_ra_hours: 5.992,
        start_dec_deg: 37.2126,
        end_ra_hours: 5.4382,
        end_dec_deg: 28.6074,
    },
    ConstellationSegment {
        start_ra_hours: 5.4382,
        start_dec_deg: 28.6074,
        end_ra_hours: 5.0331,
        end_dec_deg: 33.1661,
    },
    ConstellationSegment {
        start_ra_hours: 5.0331,
        start_dec_deg: 33.1661,
        end_ra_hours: 5.1089,
        end_dec_deg: 41.2346,
    },
    ConstellationSegment {
        start_ra_hours: 5.1089,
        start_dec_deg: 41.2346,
        end_ra_hours: 5.2783,
        end_dec_deg: 45.9981,
    },
];

const SEGMENTS_CMI: &[ConstellationSegment] = &[ConstellationSegment {
    start_ra_hours: 7.6553,
    start_dec_deg: 5.225,
    end_ra_hours: 7.4527,
    end_dec_deg: 8.2893,
}];

const SEGMENTS_CRV: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 12.4977,
        start_dec_deg: -23.3968,
        end_ra_hours: 12.5735,
        end_dec_deg: -16.5159,
    },
    ConstellationSegment {
        start_ra_hours: 12.5735,
        start_dec_deg: -16.5159,
        end_ra_hours: 12.1685,
        end_dec_deg: -22.6197,
    },
    ConstellationSegment {
        start_ra_hours: 12.1685,
        start_dec_deg: -22.6197,
        end_ra_hours: 12.4977,
        end_dec_deg: -23.3968,
    },
    ConstellationSegment {
        start_ra_hours: 12.1685,
        start_dec_deg: -22.6197,
        end_ra_hours: 12.1398,
        end_dec_deg: -24.7289,
    },
    ConstellationSegment {
        start_ra_hours: 12.4977,
        start_dec_deg: -23.3968,
        end_ra_hours: 12.1398,
        end_dec_deg: -24.7289,
    },
];

const SEGMENTS_CRT: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 10.9965,
        start_dec_deg: -18.2989,
        end_ra_hours: 11.1943,
        end_dec_deg: -22.8264,
    },
    ConstellationSegment {
        start_ra_hours: 11.1943,
        start_dec_deg: -22.8264,
        end_ra_hours: 11.4148,
        end_dec_deg: -17.684,
    },
    ConstellationSegment {
        start_ra_hours: 11.4148,
        start_dec_deg: -17.684,
        end_ra_hours: 11.3225,
        end_dec_deg: -14.7785,
    },
    ConstellationSegment {
        start_ra_hours: 11.3225,
        start_dec_deg: -14.7785,
        end_ra_hours: 10.9965,
        end_dec_deg: -18.2989,
    },
];

const SEGMENTS_CEN: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 14.6599,
        start_dec_deg: -60.8353,
        end_ra_hours: 14.0637,
        end_dec_deg: -60.373,
    },
    ConstellationSegment {
        start_ra_hours: 14.0637,
        start_dec_deg: -60.373,
        end_ra_hours: 13.6648,
        end_dec_deg: -53.4664,
    },
    ConstellationSegment {
        start_ra_hours: 13.6648,
        start_dec_deg: -53.4664,
        end_ra_hours: 12.6917,
        end_dec_deg: -48.9597,
    },
    ConstellationSegment {
        start_ra_hours: 12.6917,
        start_dec_deg: -48.9597,
        end_ra_hours: 14.1114,
        end_dec_deg: -36.37,
    },
    ConstellationSegment {
        start_ra_hours: 13.6648,
        start_dec_deg: -53.4664,
        end_ra_hours: 13.9253,
        end_dec_deg: -47.2884,
    },
    ConstellationSegment {
        start_ra_hours: 13.9253,
        start_dec_deg: -47.2884,
        end_ra_hours: 14.1114,
        end_dec_deg: -36.37,
    },
];

const SEGMENTS_LUP: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 14.6985,
        start_dec_deg: -47.3884,
        end_ra_hours: 14.9758,
        end_dec_deg: -43.134,
    },
    ConstellationSegment {
        start_ra_hours: 14.9758,
        start_dec_deg: -43.134,
        end_ra_hours: 15.356,
        end_dec_deg: -40.6474,
    },
    ConstellationSegment {
        start_ra_hours: 15.356,
        start_dec_deg: -40.6474,
        end_ra_hours: 15.5856,
        end_dec_deg: -41.1668,
    },
    ConstellationSegment {
        start_ra_hours: 15.5856,
        start_dec_deg: -41.1668,
        end_ra_hours: 15.3783,
        end_dec_deg: -44.6896,
    },
    ConstellationSegment {
        start_ra_hours: 15.3783,
        start_dec_deg: -44.6896,
        end_ra_hours: 14.6985,
        end_dec_deg: -47.3884,
    },
];

const SEGMENTS_CRB: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 15.578,
        start_dec_deg: 26.7147,
        end_ra_hours: 15.463,
        end_dec_deg: 29.1057,
    },
    ConstellationSegment {
        start_ra_hours: 15.463,
        start_dec_deg: 29.1057,
        end_ra_hours: 15.7126,
        end_dec_deg: 31.3592,
    },
    ConstellationSegment {
        start_ra_hours: 15.578,
        start_dec_deg: 26.7147,
        end_ra_hours: 15.9899,
        end_dec_deg: 26.8779,
    },
    ConstellationSegment {
        start_ra_hours: 15.9899,
        start_dec_deg: 26.8779,
        end_ra_hours: 16.024,
        end_dec_deg: 29.8511,
    },
    ConstellationSegment {
        start_ra_hours: 16.024,
        start_dec_deg: 29.8511,
        end_ra_hours: 15.9592,
        end_dec_deg: 30.2882,
    },
    ConstellationSegment {
        start_ra_hours: 15.9592,
        start_dec_deg: 30.2882,
        end_ra_hours: 15.7126,
        end_dec_deg: 31.3592,
    },
];

const SEGMENTS_COM: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 13.1664,
        start_dec_deg: 17.5293,
        end_ra_hours: 13.1979,
        end_dec_deg: 27.8781,
    },
    ConstellationSegment {
        start_ra_hours: 13.1979,
        start_dec_deg: 27.8781,
        end_ra_hours: 12.4491,
        end_dec_deg: 28.2685,
    },
];

const SEGMENTS_CVN: &[ConstellationSegment] = &[ConstellationSegment {
    start_ra_hours: 12.9338,
    start_dec_deg: 38.3183,
    end_ra_hours: 12.5624,
    end_dec_deg: 41.3574,
}];

const SEGMENTS_TRI: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 1.8853,
        start_dec_deg: 29.5789,
        end_ra_hours: 2.1591,
        end_dec_deg: 34.9872,
    },
    ConstellationSegment {
        start_ra_hours: 2.1591,
        start_dec_deg: 34.9872,
        end_ra_hours: 2.2886,
        end_dec_deg: 33.8473,
    },
    ConstellationSegment {
        start_ra_hours: 2.2886,
        start_dec_deg: 33.8473,
        end_ra_hours: 1.8853,
        end_dec_deg: 29.5789,
    },
];

const SEGMENTS_SGE: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 19.679,
        start_dec_deg: 18.0139,
        end_ra_hours: 19.7894,
        end_dec_deg: 18.534,
    },
    ConstellationSegment {
        start_ra_hours: 19.7894,
        start_dec_deg: 18.534,
        end_ra_hours: 19.9838,
        end_dec_deg: 19.492,
    },
    ConstellationSegment {
        start_ra_hours: 19.679,
        start_dec_deg: 18.0139,
        end_ra_hours: 19.6844,
        end_dec_deg: 17.4763,
    },
];

const SEGMENTS_VUL: &[ConstellationSegment] = &[ConstellationSegment {
    start_ra_hours: 19.4784,
    start_dec_deg: 24.665,
    end_ra_hours: 20.6337,
    end_dec_deg: 27.7545,
}];

const SEGMENTS_DEL: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 20.6259,
        start_dec_deg: 14.5952,
        end_ra_hours: 20.5537,
        end_dec_deg: 11.3032,
    },
    ConstellationSegment {
        start_ra_hours: 20.5537,
        start_dec_deg: 11.3032,
        end_ra_hours: 20.7243,
        end_dec_deg: 15.0746,
    },
    ConstellationSegment {
        start_ra_hours: 20.7243,
        start_dec_deg: 15.0746,
        end_ra_hours: 20.7763,
        end_dec_deg: 16.1243,
    },
    ConstellationSegment {
        start_ra_hours: 20.7763,
        start_dec_deg: 16.1243,
        end_ra_hours: 20.6259,
        end_dec_deg: 14.5952,
    },
    ConstellationSegment {
        start_ra_hours: 20.7763,
        start_dec_deg: 16.1243,
        end_ra_hours: 20.624,
        end_dec_deg: 11.3714,
    },
];

const SEGMENTS_EQU: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 21.1726,
        start_dec_deg: 10.0063,
        end_ra_hours: 21.2415,
        end_dec_deg: 6.8112,
    },
    ConstellationSegment {
        start_ra_hours: 21.2415,
        start_dec_deg: 6.8112,
        end_ra_hours: 21.2635,
        end_dec_deg: 5.2481,
    },
];

const SEGMENTS_LAC: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 22.5216,
        start_dec_deg: 50.2825,
        end_ra_hours: 22.3925,
        end_dec_deg: 46.5365,
    },
    ConstellationSegment {
        start_ra_hours: 22.3925,
        start_dec_deg: 46.5365,
        end_ra_hours: 22.4082,
        end_dec_deg: 43.1233,
    },
    ConstellationSegment {
        start_ra_hours: 22.4082,
        start_dec_deg: 43.1233,
        end_ra_hours: 22.492,
        end_dec_deg: 39.6477,
    },
    ConstellationSegment {
        start_ra_hours: 22.492,
        start_dec_deg: 39.6477,
        end_ra_hours: 22.3502,
        end_dec_deg: 37.7489,
    },
];

const SEGMENTS_ERI: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 1.6286,
        start_dec_deg: -57.2367,
        end_ra_hours: 2.971,
        end_dec_deg: -40.3047,
    },
    ConstellationSegment {
        start_ra_hours: 2.971,
        start_dec_deg: -40.3047,
        end_ra_hours: 3.549,
        end_dec_deg: -21.6328,
    },
    ConstellationSegment {
        start_ra_hours: 3.549,
        start_dec_deg: -21.6328,
        end_ra_hours: 3.721,
        end_dec_deg: -12.1019,
    },
    ConstellationSegment {
        start_ra_hours: 3.721,
        start_dec_deg: -12.1019,
        end_ra_hours: 4.758,
        end_dec_deg: -3.2543,
    },
    ConstellationSegment {
        start_ra_hours: 4.758,
        start_dec_deg: -3.2543,
        end_ra_hours: 5.1308,
        end_dec_deg: -5.0863,
    },
];

const SEGMENTS_FOR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 3.2013,
        start_dec_deg: -28.9877,
        end_ra_hours: 2.8182,
        end_dec_deg: -32.4059,
    },
    ConstellationSegment {
        start_ra_hours: 2.8182,
        start_dec_deg: -32.4059,
        end_ra_hours: 2.0747,
        end_dec_deg: -29.2967,
    },
];

const SEGMENTS_SCL: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 0.9764,
        start_dec_deg: -29.3572,
        end_ra_hours: 23.5497,
        end_dec_deg: -28.1302,
    },
    ConstellationSegment {
        start_ra_hours: 23.5497,
        start_dec_deg: -28.1302,
        end_ra_hours: 23.3145,
        end_dec_deg: -32.532,
    },
    ConstellationSegment {
        start_ra_hours: 23.3145,
        start_dec_deg: -32.532,
        end_ra_hours: 23.8153,
        end_dec_deg: -28.1302,
    },
];

const SEGMENTS_CET: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 0.7265,
        start_dec_deg: -17.9866,
        end_ra_hours: 1.1432,
        end_dec_deg: -10.1822,
    },
    ConstellationSegment {
        start_ra_hours: 1.1432,
        start_dec_deg: -10.1822,
        end_ra_hours: 1.734,
        end_dec_deg: -15.9376,
    },
    ConstellationSegment {
        start_ra_hours: 1.734,
        start_dec_deg: -15.9376,
        end_ra_hours: 0.7265,
        end_dec_deg: -17.9866,
    },
    ConstellationSegment {
        start_ra_hours: 1.1432,
        start_dec_deg: -10.1822,
        end_ra_hours: 2.3222,
        end_dec_deg: -2.9776,
    },
    ConstellationSegment {
        start_ra_hours: 2.3222,
        start_dec_deg: -2.9776,
        end_ra_hours: 3.0382,
        end_dec_deg: 4.0897,
    },
];

const SEGMENTS_PHE: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 0.4382,
        start_dec_deg: -42.3061,
        end_ra_hours: 1.1013,
        end_dec_deg: -46.7185,
    },
    ConstellationSegment {
        start_ra_hours: 1.1013,
        start_dec_deg: -46.7185,
        end_ra_hours: 1.4728,
        end_dec_deg: -43.3186,
    },
    ConstellationSegment {
        start_ra_hours: 1.4728,
        start_dec_deg: -43.3186,
        end_ra_hours: 0.4382,
        end_dec_deg: -42.3061,
    },
    ConstellationSegment {
        start_ra_hours: 1.1013,
        start_dec_deg: -46.7185,
        end_ra_hours: 1.5207,
        end_dec_deg: -49.0728,
    },
];

const SEGMENTS_GRU: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 22.1372,
        start_dec_deg: -46.9609,
        end_ra_hours: 22.4877,
        end_dec_deg: -43.4956,
    },
    ConstellationSegment {
        start_ra_hours: 22.4877,
        start_dec_deg: -43.4956,
        end_ra_hours: 22.7111,
        end_dec_deg: -46.8847,
    },
    ConstellationSegment {
        start_ra_hours: 22.7111,
        start_dec_deg: -46.8847,
        end_ra_hours: 22.1372,
        end_dec_deg: -46.9609,
    },
    ConstellationSegment {
        start_ra_hours: 22.4877,
        start_dec_deg: -43.4956,
        end_ra_hours: 23.0146,
        end_dec_deg: -45.2464,
    },
];

const SEGMENTS_PAV: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 20.4275,
        start_dec_deg: -56.7351,
        end_ra_hours: 20.0093,
        end_dec_deg: -66.2031,
    },
    ConstellationSegment {
        start_ra_hours: 20.0093,
        start_dec_deg: -66.2031,
        end_ra_hours: 18.717,
        end_dec_deg: -71.428,
    },
    ConstellationSegment {
        start_ra_hours: 18.717,
        start_dec_deg: -71.428,
        end_ra_hours: 17.7628,
        end_dec_deg: -64.7235,
    },
    ConstellationSegment {
        start_ra_hours: 17.7628,
        start_dec_deg: -64.7235,
        end_ra_hours: 20.4275,
        end_dec_deg: -56.7351,
    },
];

const SEGMENTS_TUC: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 22.3085,
        start_dec_deg: -60.2596,
        end_ra_hours: 23.2905,
        end_dec_deg: -58.2358,
    },
    ConstellationSegment {
        start_ra_hours: 23.2905,
        start_dec_deg: -58.2358,
        end_ra_hours: 0.5256,
        end_dec_deg: -62.9581,
    },
    ConstellationSegment {
        start_ra_hours: 0.5256,
        start_dec_deg: -62.9581,
        end_ra_hours: 22.3085,
        end_dec_deg: -60.2596,
    },
];

const SEGMENTS_IND: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 20.6263,
        start_dec_deg: -47.2915,
        end_ra_hours: 20.9131,
        end_dec_deg: -58.4542,
    },
    ConstellationSegment {
        start_ra_hours: 20.9131,
        start_dec_deg: -58.4542,
        end_ra_hours: 21.3312,
        end_dec_deg: -53.4493,
    },
    ConstellationSegment {
        start_ra_hours: 21.3312,
        start_dec_deg: -53.4493,
        end_ra_hours: 20.6263,
        end_dec_deg: -47.2915,
    },
];

const SEGMENTS_MIC: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 20.8329,
        start_dec_deg: -33.7797,
        end_ra_hours: 21.299,
        end_dec_deg: -32.1726,
    },
    ConstellationSegment {
        start_ra_hours: 21.299,
        start_dec_deg: -32.1726,
        end_ra_hours: 21.021,
        end_dec_deg: -41.3869,
    },
];

const SEGMENTS_PSA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 22.9607,
        start_dec_deg: -29.6222,
        end_ra_hours: 22.5254,
        end_dec_deg: -32.346,
    },
    ConstellationSegment {
        start_ra_hours: 22.5254,
        start_dec_deg: -32.346,
        end_ra_hours: 22.1407,
        end_dec_deg: -32.9884,
    },
    ConstellationSegment {
        start_ra_hours: 22.1407,
        start_dec_deg: -32.9884,
        end_ra_hours: 22.6779,
        end_dec_deg: -27.0435,
    },
    ConstellationSegment {
        start_ra_hours: 22.6779,
        start_dec_deg: -27.0435,
        end_ra_hours: 22.9607,
        end_dec_deg: -29.6222,
    },
];

const SEGMENTS_ARA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 17.5307,
        start_dec_deg: -49.8761,
        end_ra_hours: 17.4216,
        end_dec_deg: -55.5299,
    },
    ConstellationSegment {
        start_ra_hours: 17.4216,
        start_dec_deg: -55.5299,
        end_ra_hours: 17.2526,
        end_dec_deg: -56.3776,
    },
    ConstellationSegment {
        start_ra_hours: 17.2526,
        start_dec_deg: -56.3776,
        end_ra_hours: 17.5181,
        end_dec_deg: -60.6836,
    },
    ConstellationSegment {
        start_ra_hours: 17.5307,
        start_dec_deg: -49.8761,
        end_ra_hours: 16.9776,
        end_dec_deg: -55.9901,
    },
    ConstellationSegment {
        start_ra_hours: 16.9776,
        start_dec_deg: -55.9901,
        end_ra_hours: 17.2526,
        end_dec_deg: -56.3776,
    },
];

const SEGMENTS_CRA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 19.1579,
        start_dec_deg: -37.9044,
        end_ra_hours: 19.167,
        end_dec_deg: -39.3407,
    },
    ConstellationSegment {
        start_ra_hours: 19.167,
        start_dec_deg: -39.3407,
        end_ra_hours: 18.8125,
        end_dec_deg: -43.6805,
    },
    ConstellationSegment {
        start_ra_hours: 19.1579,
        start_dec_deg: -37.9044,
        end_ra_hours: 19.1068,
        end_dec_deg: -37.0635,
    },
    ConstellationSegment {
        start_ra_hours: 19.1068,
        start_dec_deg: -37.0635,
        end_ra_hours: 18.978,
        end_dec_deg: -37.1071,
    },
];

const SEGMENTS_TEL: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 18.4494,
        start_dec_deg: -45.9685,
        end_ra_hours: 18.4806,
        end_dec_deg: -49.0704,
    },
    ConstellationSegment {
        start_ra_hours: 18.4806,
        start_dec_deg: -49.0704,
        end_ra_hours: 18.187,
        end_dec_deg: -45.9546,
    },
];

const SEGMENTS_NOR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 16.3297,
        start_dec_deg: -50.1555,
        end_ra_hours: 16.4536,
        end_dec_deg: -47.5548,
    },
    ConstellationSegment {
        start_ra_hours: 16.4536,
        start_dec_deg: -47.5548,
        end_ra_hours: 16.1099,
        end_dec_deg: -45.1731,
    },
    ConstellationSegment {
        start_ra_hours: 16.1099,
        start_dec_deg: -45.1731,
        end_ra_hours: 16.3297,
        end_dec_deg: -50.1555,
    },
];

const SEGMENTS_CIR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 14.7083,
        start_dec_deg: -64.9753,
        end_ra_hours: 15.3909,
        end_dec_deg: -59.3208,
    },
    ConstellationSegment {
        start_ra_hours: 15.3909,
        start_dec_deg: -59.3208,
        end_ra_hours: 15.3893,
        end_dec_deg: -59.3219,
    },
];

const SEGMENTS_TRA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 16.811,
        start_dec_deg: -69.0277,
        end_ra_hours: 15.919,
        end_dec_deg: -63.43,
    },
    ConstellationSegment {
        start_ra_hours: 15.919,
        start_dec_deg: -63.43,
        end_ra_hours: 15.315,
        end_dec_deg: -68.6795,
    },
    ConstellationSegment {
        start_ra_hours: 15.315,
        start_dec_deg: -68.6795,
        end_ra_hours: 16.811,
        end_dec_deg: -69.0277,
    },
];

const SEGMENTS_MUS: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 12.6194,
        start_dec_deg: -69.1356,
        end_ra_hours: 12.7711,
        end_dec_deg: -68.108,
    },
    ConstellationSegment {
        start_ra_hours: 12.7711,
        start_dec_deg: -68.108,
        end_ra_hours: 13.0378,
        end_dec_deg: -71.5491,
    },
    ConstellationSegment {
        start_ra_hours: 13.0378,
        start_dec_deg: -71.5491,
        end_ra_hours: 12.3533,
        end_dec_deg: -72.1329,
    },
    ConstellationSegment {
        start_ra_hours: 12.3533,
        start_dec_deg: -72.1329,
        end_ra_hours: 12.6194,
        end_dec_deg: -69.1356,
    },
];

const SEGMENTS_CHA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 8.3088,
        start_dec_deg: -76.9199,
        end_ra_hours: 10.5914,
        end_dec_deg: -78.6077,
    },
    ConstellationSegment {
        start_ra_hours: 10.5914,
        start_dec_deg: -78.6077,
        end_ra_hours: 12.3057,
        end_dec_deg: -79.3122,
    },
    ConstellationSegment {
        start_ra_hours: 12.3057,
        start_dec_deg: -79.3122,
        end_ra_hours: 10.7627,
        end_dec_deg: -80.5401,
    },
    ConstellationSegment {
        start_ra_hours: 10.7627,
        start_dec_deg: -80.5401,
        end_ra_hours: 8.3088,
        end_dec_deg: -76.9199,
    },
];

const SEGMENTS_VOL: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 7.2806,
        start_dec_deg: -67.9572,
        end_ra_hours: 8.1319,
        end_dec_deg: -68.6167,
    },
    ConstellationSegment {
        start_ra_hours: 8.1319,
        start_dec_deg: -68.6167,
        end_ra_hours: 7.6966,
        end_dec_deg: -72.6062,
    },
    ConstellationSegment {
        start_ra_hours: 7.6966,
        start_dec_deg: -72.6062,
        end_ra_hours: 7.2806,
        end_dec_deg: -67.9572,
    },
    ConstellationSegment {
        start_ra_hours: 8.1319,
        start_dec_deg: -68.6167,
        end_ra_hours: 9.0408,
        end_dec_deg: -66.3961,
    },
];

const SEGMENTS_PIC: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 6.803,
        start_dec_deg: -61.9414,
        end_ra_hours: 5.7882,
        end_dec_deg: -51.0665,
    },
    ConstellationSegment {
        start_ra_hours: 5.7882,
        start_dec_deg: -51.0665,
        end_ra_hours: 5.8305,
        end_dec_deg: -56.1667,
    },
];

const SEGMENTS_DOR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 4.5666,
        start_dec_deg: -55.045,
        end_ra_hours: 5.5604,
        end_dec_deg: -62.4897,
    },
    ConstellationSegment {
        start_ra_hours: 5.5604,
        start_dec_deg: -62.4897,
        end_ra_hours: 4.2667,
        end_dec_deg: -51.4867,
    },
    ConstellationSegment {
        start_ra_hours: 4.2667,
        start_dec_deg: -51.4867,
        end_ra_hours: 4.5666,
        end_dec_deg: -55.045,
    },
];

const SEGMENTS_RET: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 4.2404,
        start_dec_deg: -62.4739,
        end_ra_hours: 3.7365,
        end_dec_deg: -64.8071,
    },
    ConstellationSegment {
        start_ra_hours: 3.7365,
        start_dec_deg: -64.8071,
        end_ra_hours: 4.0132,
        end_dec_deg: -63.2528,
    },
    ConstellationSegment {
        start_ra_hours: 4.0132,
        start_dec_deg: -63.2528,
        end_ra_hours: 3.9791,
        end_dec_deg: -61.3998,
    },
    ConstellationSegment {
        start_ra_hours: 3.9791,
        start_dec_deg: -61.3998,
        end_ra_hours: 4.2404,
        end_dec_deg: -62.4739,
    },
];

const SEGMENTS_HOR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 4.2335,
        start_dec_deg: -42.2944,
        end_ra_hours: 2.6237,
        end_dec_deg: -52.5435,
    },
    ConstellationSegment {
        start_ra_hours: 2.6237,
        start_dec_deg: -52.5435,
        end_ra_hours: 2.9806,
        end_dec_deg: -64.0712,
    },
];

const SEGMENTS_CAE: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 4.6761,
        start_dec_deg: -41.8638,
        end_ra_hours: 4.7009,
        end_dec_deg: -37.1444,
    },
    ConstellationSegment {
        start_ra_hours: 4.7009,
        start_dec_deg: -37.1444,
        end_ra_hours: 5.0733,
        end_dec_deg: -35.4829,
    },
];

const SEGMENTS_COL: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 5.66,
        start_dec_deg: -34.0741,
        end_ra_hours: 5.9588,
        end_dec_deg: -35.7703,
    },
    ConstellationSegment {
        start_ra_hours: 5.9588,
        start_dec_deg: -35.7703,
        end_ra_hours: 5.5206,
        end_dec_deg: -35.4706,
    },
    ConstellationSegment {
        start_ra_hours: 5.66,
        start_dec_deg: -34.0741,
        end_ra_hours: 6.3684,
        end_dec_deg: -33.4364,
    },
    ConstellationSegment {
        start_ra_hours: 5.9588,
        start_dec_deg: -35.7703,
        end_ra_hours: 6.3684,
        end_dec_deg: -33.4364,
    },
];

const SEGMENTS_LEP: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 5.5456,
        start_dec_deg: -17.8222,
        end_ra_hours: 5.4706,
        end_dec_deg: -20.7594,
    },
    ConstellationSegment {
        start_ra_hours: 5.4706,
        start_dec_deg: -20.7594,
        end_ra_hours: 5.091,
        end_dec_deg: -22.3712,
    },
    ConstellationSegment {
        start_ra_hours: 5.091,
        start_dec_deg: -22.3712,
        end_ra_hours: 5.2155,
        end_dec_deg: -16.2054,
    },
    ConstellationSegment {
        start_ra_hours: 5.2155,
        start_dec_deg: -16.2054,
        end_ra_hours: 5.5456,
        end_dec_deg: -17.8222,
    },
    ConstellationSegment {
        start_ra_hours: 5.5456,
        start_dec_deg: -17.8222,
        end_ra_hours: 5.741,
        end_dec_deg: -14.168,
    },
    ConstellationSegment {
        start_ra_hours: 5.4706,
        start_dec_deg: -20.7594,
        end_ra_hours: 5.8553,
        end_dec_deg: -20.8791,
    },
];

const SEGMENTS_MON: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 7.6873,
        start_dec_deg: -9.5516,
        end_ra_hours: 6.4802,
        end_dec_deg: -7.033,
    },
    ConstellationSegment {
        start_ra_hours: 6.4802,
        start_dec_deg: -7.033,
        end_ra_hours: 6.2475,
        end_dec_deg: -6.2751,
    },
    ConstellationSegment {
        start_ra_hours: 6.2475,
        start_dec_deg: -6.2751,
        end_ra_hours: 7.1975,
        end_dec_deg: -0.4927,
    },
];

const SEGMENTS_HYA: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 8.6277,
        start_dec_deg: -5.4467,
        end_ra_hours: 8.7232,
        end_dec_deg: 6.4189,
    },
    ConstellationSegment {
        start_ra_hours: 8.7232,
        start_dec_deg: 6.4189,
        end_ra_hours: 8.9233,
        end_dec_deg: 5.9456,
    },
    ConstellationSegment {
        start_ra_hours: 8.9233,
        start_dec_deg: 5.9456,
        end_ra_hours: 9.2398,
        end_dec_deg: 2.3141,
    },
    ConstellationSegment {
        start_ra_hours: 8.6277,
        start_dec_deg: -5.4467,
        end_ra_hours: 9.4596,
        end_dec_deg: -8.6586,
    },
    ConstellationSegment {
        start_ra_hours: 9.4596,
        start_dec_deg: -8.6586,
        end_ra_hours: 10.1765,
        end_dec_deg: -12.3541,
    },
    ConstellationSegment {
        start_ra_hours: 10.1765,
        start_dec_deg: -12.3541,
        end_ra_hours: 11.5505,
        end_dec_deg: -31.8577,
    },
    ConstellationSegment {
        start_ra_hours: 11.5505,
        start_dec_deg: -31.8577,
        end_ra_hours: 13.3152,
        end_dec_deg: -23.1716,
    },
    ConstellationSegment {
        start_ra_hours: 13.3152,
        start_dec_deg: -23.1716,
        end_ra_hours: 14.1062,
        end_dec_deg: -26.6822,
    },
];

const SEGMENTS_SEX: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 10.1322,
        start_dec_deg: -0.3719,
        end_ra_hours: 10.4993,
        end_dec_deg: -0.6375,
    },
    ConstellationSegment {
        start_ra_hours: 10.4993,
        start_dec_deg: -0.6375,
        end_ra_hours: 9.8753,
        end_dec_deg: -8.1055,
    },
];

const SEGMENTS_ANT: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 10.4526,
        start_dec_deg: -31.0678,
        end_ra_hours: 9.4874,
        end_dec_deg: -35.9514,
    },
    ConstellationSegment {
        start_ra_hours: 9.4874,
        start_dec_deg: -35.9514,
        end_ra_hours: 10.4526,
        end_dec_deg: -31.0678,
    },
];

const SEGMENTS_PYX: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 8.7266,
        start_dec_deg: -33.1863,
        end_ra_hours: 8.8417,
        end_dec_deg: -35.3082,
    },
    ConstellationSegment {
        start_ra_hours: 8.8417,
        start_dec_deg: -35.3082,
        end_ra_hours: 8.8425,
        end_dec_deg: -27.7101,
    },
];

const SEGMENTS_PUP: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 8.0594,
        start_dec_deg: -40.0036,
        end_ra_hours: 7.8218,
        end_dec_deg: -24.8597,
    },
    ConstellationSegment {
        start_ra_hours: 7.8218,
        start_dec_deg: -24.8597,
        end_ra_hours: 7.2856,
        end_dec_deg: -37.0975,
    },
    ConstellationSegment {
        start_ra_hours: 7.2856,
        start_dec_deg: -37.0975,
        end_ra_hours: 8.0594,
        end_dec_deg: -40.0036,
    },
    ConstellationSegment {
        start_ra_hours: 6.6291,
        start_dec_deg: -43.196,
        end_ra_hours: 7.2856,
        end_dec_deg: -37.0975,
    },
];

const SEGMENTS_VEL: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 8.1586,
        start_dec_deg: -47.3367,
        end_ra_hours: 8.7452,
        end_dec_deg: -54.7087,
    },
    ConstellationSegment {
        start_ra_hours: 8.7452,
        start_dec_deg: -54.7087,
        end_ra_hours: 9.5115,
        end_dec_deg: -40.4668,
    },
    ConstellationSegment {
        start_ra_hours: 9.5115,
        start_dec_deg: -40.4668,
        end_ra_hours: 9.133,
        end_dec_deg: -43.4326,
    },
    ConstellationSegment {
        start_ra_hours: 9.133,
        start_dec_deg: -43.4326,
        end_ra_hours: 8.1586,
        end_dec_deg: -47.3367,
    },
];

const SEGMENTS_CAR: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 6.3992,
        start_dec_deg: -52.6956,
        end_ra_hours: 9.22,
        end_dec_deg: -59.2753,
    },
    ConstellationSegment {
        start_ra_hours: 9.22,
        start_dec_deg: -59.2753,
        end_ra_hours: 9.2847,
        end_dec_deg: -69.7172,
    },
    ConstellationSegment {
        start_ra_hours: 9.2847,
        start_dec_deg: -69.7172,
        end_ra_hours: 10.7156,
        end_dec_deg: -64.3944,
    },
    ConstellationSegment {
        start_ra_hours: 10.7156,
        start_dec_deg: -64.3944,
        end_ra_hours: 9.22,
        end_dec_deg: -59.2753,
    },
    ConstellationSegment {
        start_ra_hours: 6.3992,
        start_dec_deg: -52.6956,
        end_ra_hours: 8.3752,
        end_dec_deg: -59.5096,
    },
    ConstellationSegment {
        start_ra_hours: 8.3752,
        start_dec_deg: -59.5096,
        end_ra_hours: 9.22,
        end_dec_deg: -59.2753,
    },
];

const SEGMENTS_OCT: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 14.4487,
        start_dec_deg: -83.6679,
        end_ra_hours: 22.7676,
        end_dec_deg: -81.3816,
    },
    ConstellationSegment {
        start_ra_hours: 22.7676,
        start_dec_deg: -81.3816,
        end_ra_hours: 21.6912,
        end_dec_deg: -77.3899,
    },
    ConstellationSegment {
        start_ra_hours: 21.6912,
        start_dec_deg: -77.3899,
        end_ra_hours: 14.4487,
        end_dec_deg: -83.6679,
    },
];

const SEGMENTS_MEN: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 6.1706,
        start_dec_deg: -74.7531,
        end_ra_hours: 5.5313,
        end_dec_deg: -76.3414,
    },
    ConstellationSegment {
        start_ra_hours: 5.5313,
        start_dec_deg: -76.3414,
        end_ra_hours: 4.9198,
        end_dec_deg: -74.9372,
    },
    ConstellationSegment {
        start_ra_hours: 4.9198,
        start_dec_deg: -74.9372,
        end_ra_hours: 5.0451,
        end_dec_deg: -71.3143,
    },
];

const SEGMENTS_HYI: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 1.9795,
        start_dec_deg: -61.5697,
        end_ra_hours: 0.4293,
        end_dec_deg: -77.2542,
    },
    ConstellationSegment {
        start_ra_hours: 0.4293,
        start_dec_deg: -77.2542,
        end_ra_hours: 3.7873,
        end_dec_deg: -74.2389,
    },
    ConstellationSegment {
        start_ra_hours: 3.7873,
        start_dec_deg: -74.2389,
        end_ra_hours: 1.9795,
        end_dec_deg: -61.5697,
    },
];

const SEGMENTS_APS: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 14.7977,
        start_dec_deg: -79.0447,
        end_ra_hours: 16.3343,
        end_dec_deg: -78.8949,
    },
    ConstellationSegment {
        start_ra_hours: 16.3343,
        start_dec_deg: -78.8949,
        end_ra_hours: 16.7181,
        end_dec_deg: -77.5167,
    },
    ConstellationSegment {
        start_ra_hours: 16.7181,
        start_dec_deg: -77.5167,
        end_ra_hours: 16.3397,
        end_dec_deg: -73.3898,
    },
];

const SEGMENTS_SCT: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 18.5862,
        start_dec_deg: -8.244,
        end_ra_hours: 18.7862,
        end_dec_deg: -4.7477,
    },
    ConstellationSegment {
        start_ra_hours: 18.7862,
        start_dec_deg: -4.7477,
        end_ra_hours: 18.4871,
        end_dec_deg: -14.5656,
    },
    ConstellationSegment {
        start_ra_hours: 18.4871,
        start_dec_deg: -14.5656,
        end_ra_hours: 18.5862,
        end_dec_deg: -8.244,
    },
];

const SEGMENTS_CAM: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 4.9008,
        start_dec_deg: 66.3426,
        end_ra_hours: 5.0569,
        end_dec_deg: 60.4425,
    },
    ConstellationSegment {
        start_ra_hours: 5.0569,
        start_dec_deg: 60.4425,
        end_ra_hours: 3.8397,
        end_dec_deg: 71.3325,
    },
    ConstellationSegment {
        start_ra_hours: 3.8397,
        start_dec_deg: 71.3325,
        end_ra_hours: 4.9008,
        end_dec_deg: 66.3426,
    },
];

const SEGMENTS_LYN: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 9.3509,
        start_dec_deg: 34.3926,
        end_ra_hours: 9.0109,
        end_dec_deg: 41.7829,
    },
    ConstellationSegment {
        start_ra_hours: 9.0109,
        start_dec_deg: 41.7829,
        end_ra_hours: 8.3803,
        end_dec_deg: 43.1882,
    },
    ConstellationSegment {
        start_ra_hours: 8.3803,
        start_dec_deg: 43.1882,
        end_ra_hours: 6.9552,
        end_dec_deg: 55.7074,
    },
    ConstellationSegment {
        start_ra_hours: 6.9552,
        start_dec_deg: 55.7074,
        end_ra_hours: 6.3271,
        end_dec_deg: 59.0108,
    },
];

const SEGMENTS_LMI: &[ConstellationSegment] = &[
    ConstellationSegment {
        start_ra_hours: 10.4644,
        start_dec_deg: 36.7074,
        end_ra_hours: 10.8889,
        end_dec_deg: 34.2148,
    },
    ConstellationSegment {
        start_ra_hours: 10.8889,
        start_dec_deg: 34.2148,
        end_ra_hours: 9.8734,
        end_dec_deg: 35.2447,
    },
];

/// All IAU constellation stick-figure line tables.
pub const CONSTELLATIONS: &[ConstellationLines] = &[
    ConstellationLines {
        abbrev: "Ori",
        name: "Orion",
        center_ra_hours: 5.5,
        center_dec_deg: 0.0,
        segments: SEGMENTS_ORI,
    },
    ConstellationLines {
        abbrev: "UMa",
        name: "Ursa Major",
        center_ra_hours: 11.0,
        center_dec_deg: 55.0,
        segments: SEGMENTS_UMA,
    },
    ConstellationLines {
        abbrev: "Cas",
        name: "Cassiopeia",
        center_ra_hours: 1.0,
        center_dec_deg: 60.0,
        segments: SEGMENTS_CAS,
    },
    ConstellationLines {
        abbrev: "Cyg",
        name: "Cygnus",
        center_ra_hours: 20.5,
        center_dec_deg: 40.0,
        segments: SEGMENTS_CYG,
    },
    ConstellationLines {
        abbrev: "Leo",
        name: "Leo",
        center_ra_hours: 10.7,
        center_dec_deg: 15.0,
        segments: SEGMENTS_LEO,
    },
    ConstellationLines {
        abbrev: "Sco",
        name: "Scorpius",
        center_ra_hours: 16.9,
        center_dec_deg: -30.0,
        segments: SEGMENTS_SCO,
    },
    ConstellationLines {
        abbrev: "Gem",
        name: "Gemini",
        center_ra_hours: 7.1,
        center_dec_deg: 25.0,
        segments: SEGMENTS_GEM,
    },
    ConstellationLines {
        abbrev: "Peg",
        name: "Pegasus",
        center_ra_hours: 22.7,
        center_dec_deg: 20.0,
        segments: SEGMENTS_PEG,
    },
    ConstellationLines {
        abbrev: "And",
        name: "Andromeda",
        center_ra_hours: 0.8,
        center_dec_deg: 38.0,
        segments: SEGMENTS_AND,
    },
    ConstellationLines {
        abbrev: "Tau",
        name: "Taurus",
        center_ra_hours: 4.5,
        center_dec_deg: 17.0,
        segments: SEGMENTS_TAU,
    },
    ConstellationLines {
        abbrev: "CMa",
        name: "Canis Major",
        center_ra_hours: 6.8,
        center_dec_deg: -22.0,
        segments: SEGMENTS_CMA,
    },
    ConstellationLines {
        abbrev: "Lyr",
        name: "Lyra",
        center_ra_hours: 18.8,
        center_dec_deg: 36.0,
        segments: SEGMENTS_LYR,
    },
    ConstellationLines {
        abbrev: "Aql",
        name: "Aquila",
        center_ra_hours: 19.7,
        center_dec_deg: 3.0,
        segments: SEGMENTS_AQL,
    },
    ConstellationLines {
        abbrev: "Cru",
        name: "Crux",
        center_ra_hours: 12.5,
        center_dec_deg: -60.0,
        segments: SEGMENTS_CRU,
    },
    ConstellationLines {
        abbrev: "Per",
        name: "Perseus",
        center_ra_hours: 3.4,
        center_dec_deg: 42.0,
        segments: SEGMENTS_PER,
    },
    ConstellationLines {
        abbrev: "Boo",
        name: "Bootes",
        center_ra_hours: 14.7,
        center_dec_deg: 30.0,
        segments: SEGMENTS_BOO,
    },
    ConstellationLines {
        abbrev: "Vir",
        name: "Virgo",
        center_ra_hours: 13.0,
        center_dec_deg: -4.0,
        segments: SEGMENTS_VIR,
    },
    ConstellationLines {
        abbrev: "UMi",
        name: "Ursa Minor",
        center_ra_hours: 15.0,
        center_dec_deg: 75.0,
        segments: SEGMENTS_UMI,
    },
    ConstellationLines {
        abbrev: "Dra",
        name: "Draco",
        center_ra_hours: 15.0,
        center_dec_deg: 65.0,
        segments: SEGMENTS_DRA,
    },
    ConstellationLines {
        abbrev: "Cep",
        name: "Cepheus",
        center_ra_hours: 22.0,
        center_dec_deg: 65.0,
        segments: SEGMENTS_CEP,
    },
    ConstellationLines {
        abbrev: "Sgr",
        name: "Sagittarius",
        center_ra_hours: 19.0,
        center_dec_deg: -28.0,
        segments: SEGMENTS_SGR,
    },
    ConstellationLines {
        abbrev: "Cap",
        name: "Capricornus",
        center_ra_hours: 21.0,
        center_dec_deg: -18.0,
        segments: SEGMENTS_CAP,
    },
    ConstellationLines {
        abbrev: "Aqr",
        name: "Aquarius",
        center_ra_hours: 22.3,
        center_dec_deg: -10.0,
        segments: SEGMENTS_AQR,
    },
    ConstellationLines {
        abbrev: "Psc",
        name: "Pisces",
        center_ra_hours: 0.5,
        center_dec_deg: 12.0,
        segments: SEGMENTS_PSC,
    },
    ConstellationLines {
        abbrev: "Ari",
        name: "Aries",
        center_ra_hours: 2.5,
        center_dec_deg: 22.0,
        segments: SEGMENTS_ARI,
    },
    ConstellationLines {
        abbrev: "Cnc",
        name: "Cancer",
        center_ra_hours: 8.7,
        center_dec_deg: 20.0,
        segments: SEGMENTS_CNC,
    },
    ConstellationLines {
        abbrev: "Lib",
        name: "Libra",
        center_ra_hours: 15.2,
        center_dec_deg: -16.0,
        segments: SEGMENTS_LIB,
    },
    ConstellationLines {
        abbrev: "Oph",
        name: "Ophiuchus",
        center_ra_hours: 17.3,
        center_dec_deg: -4.0,
        segments: SEGMENTS_OPH,
    },
    ConstellationLines {
        abbrev: "Ser",
        name: "Serpens",
        center_ra_hours: 16.0,
        center_dec_deg: 6.0,
        segments: SEGMENTS_SER,
    },
    ConstellationLines {
        abbrev: "Her",
        name: "Hercules",
        center_ra_hours: 17.4,
        center_dec_deg: 27.0,
        segments: SEGMENTS_HER,
    },
    ConstellationLines {
        abbrev: "Aur",
        name: "Auriga",
        center_ra_hours: 6.0,
        center_dec_deg: 42.0,
        segments: SEGMENTS_AUR,
    },
    ConstellationLines {
        abbrev: "CMi",
        name: "Canis Minor",
        center_ra_hours: 7.6,
        center_dec_deg: 6.0,
        segments: SEGMENTS_CMI,
    },
    ConstellationLines {
        abbrev: "Crv",
        name: "Corvus",
        center_ra_hours: 12.3,
        center_dec_deg: -18.0,
        segments: SEGMENTS_CRV,
    },
    ConstellationLines {
        abbrev: "Crt",
        name: "Crater",
        center_ra_hours: 11.3,
        center_dec_deg: -15.0,
        segments: SEGMENTS_CRT,
    },
    ConstellationLines {
        abbrev: "Cen",
        name: "Centaurus",
        center_ra_hours: 13.5,
        center_dec_deg: -47.0,
        segments: SEGMENTS_CEN,
    },
    ConstellationLines {
        abbrev: "Lup",
        name: "Lupus",
        center_ra_hours: 15.3,
        center_dec_deg: -42.0,
        segments: SEGMENTS_LUP,
    },
    ConstellationLines {
        abbrev: "CrB",
        name: "Corona Borealis",
        center_ra_hours: 15.9,
        center_dec_deg: 30.0,
        segments: SEGMENTS_CRB,
    },
    ConstellationLines {
        abbrev: "Com",
        name: "Coma Berenices",
        center_ra_hours: 12.8,
        center_dec_deg: 23.0,
        segments: SEGMENTS_COM,
    },
    ConstellationLines {
        abbrev: "CVn",
        name: "Canes Venatici",
        center_ra_hours: 13.1,
        center_dec_deg: 40.0,
        segments: SEGMENTS_CVN,
    },
    ConstellationLines {
        abbrev: "Tri",
        name: "Triangulum",
        center_ra_hours: 2.2,
        center_dec_deg: 32.0,
        segments: SEGMENTS_TRI,
    },
    ConstellationLines {
        abbrev: "Sge",
        name: "Sagitta",
        center_ra_hours: 19.8,
        center_dec_deg: 18.5,
        segments: SEGMENTS_SGE,
    },
    ConstellationLines {
        abbrev: "Vul",
        name: "Vulpecula",
        center_ra_hours: 20.2,
        center_dec_deg: 25.0,
        segments: SEGMENTS_VUL,
    },
    ConstellationLines {
        abbrev: "Del",
        name: "Delphinus",
        center_ra_hours: 20.7,
        center_dec_deg: 13.0,
        segments: SEGMENTS_DEL,
    },
    ConstellationLines {
        abbrev: "Equ",
        name: "Equuleus",
        center_ra_hours: 21.2,
        center_dec_deg: 8.0,
        segments: SEGMENTS_EQU,
    },
    ConstellationLines {
        abbrev: "Lac",
        name: "Lacerta",
        center_ra_hours: 22.5,
        center_dec_deg: 45.0,
        segments: SEGMENTS_LAC,
    },
    ConstellationLines {
        abbrev: "Eri",
        name: "Eridanus",
        center_ra_hours: 3.3,
        center_dec_deg: -29.0,
        segments: SEGMENTS_ERI,
    },
    ConstellationLines {
        abbrev: "For",
        name: "Fornax",
        center_ra_hours: 2.8,
        center_dec_deg: -30.0,
        segments: SEGMENTS_FOR,
    },
    ConstellationLines {
        abbrev: "Scl",
        name: "Sculptor",
        center_ra_hours: 0.5,
        center_dec_deg: -32.0,
        segments: SEGMENTS_SCL,
    },
    ConstellationLines {
        abbrev: "Cet",
        name: "Cetus",
        center_ra_hours: 1.7,
        center_dec_deg: -10.0,
        segments: SEGMENTS_CET,
    },
    ConstellationLines {
        abbrev: "Phe",
        name: "Phoenix",
        center_ra_hours: 0.9,
        center_dec_deg: -48.0,
        segments: SEGMENTS_PHE,
    },
    ConstellationLines {
        abbrev: "Gru",
        name: "Grus",
        center_ra_hours: 22.5,
        center_dec_deg: -45.0,
        segments: SEGMENTS_GRU,
    },
    ConstellationLines {
        abbrev: "Pav",
        name: "Pavo",
        center_ra_hours: 19.6,
        center_dec_deg: -63.0,
        segments: SEGMENTS_PAV,
    },
    ConstellationLines {
        abbrev: "Tuc",
        name: "Tucana",
        center_ra_hours: 23.8,
        center_dec_deg: -65.0,
        segments: SEGMENTS_TUC,
    },
    ConstellationLines {
        abbrev: "Ind",
        name: "Indus",
        center_ra_hours: 21.5,
        center_dec_deg: -55.0,
        segments: SEGMENTS_IND,
    },
    ConstellationLines {
        abbrev: "Mic",
        name: "Microscopium",
        center_ra_hours: 21.0,
        center_dec_deg: -36.0,
        segments: SEGMENTS_MIC,
    },
    ConstellationLines {
        abbrev: "PsA",
        name: "Piscis Austrinus",
        center_ra_hours: 22.3,
        center_dec_deg: -31.0,
        segments: SEGMENTS_PSA,
    },
    ConstellationLines {
        abbrev: "Ara",
        name: "Ara",
        center_ra_hours: 17.3,
        center_dec_deg: -53.0,
        segments: SEGMENTS_ARA,
    },
    ConstellationLines {
        abbrev: "CrA",
        name: "Corona Australis",
        center_ra_hours: 18.6,
        center_dec_deg: -40.0,
        segments: SEGMENTS_CRA,
    },
    ConstellationLines {
        abbrev: "Tel",
        name: "Telescopium",
        center_ra_hours: 18.3,
        center_dec_deg: -50.0,
        segments: SEGMENTS_TEL,
    },
    ConstellationLines {
        abbrev: "Nor",
        name: "Norma",
        center_ra_hours: 16.0,
        center_dec_deg: -50.0,
        segments: SEGMENTS_NOR,
    },
    ConstellationLines {
        abbrev: "Cir",
        name: "Circinus",
        center_ra_hours: 14.6,
        center_dec_deg: -63.0,
        segments: SEGMENTS_CIR,
    },
    ConstellationLines {
        abbrev: "TrA",
        name: "Triangulum Australe",
        center_ra_hours: 16.1,
        center_dec_deg: -65.0,
        segments: SEGMENTS_TRA,
    },
    ConstellationLines {
        abbrev: "Mus",
        name: "Musca",
        center_ra_hours: 12.5,
        center_dec_deg: -70.0,
        segments: SEGMENTS_MUS,
    },
    ConstellationLines {
        abbrev: "Cha",
        name: "Chamaeleon",
        center_ra_hours: 10.7,
        center_dec_deg: -79.0,
        segments: SEGMENTS_CHA,
    },
    ConstellationLines {
        abbrev: "Vol",
        name: "Volans",
        center_ra_hours: 7.8,
        center_dec_deg: -69.0,
        segments: SEGMENTS_VOL,
    },
    ConstellationLines {
        abbrev: "Pic",
        name: "Pictor",
        center_ra_hours: 5.7,
        center_dec_deg: -53.0,
        segments: SEGMENTS_PIC,
    },
    ConstellationLines {
        abbrev: "Dor",
        name: "Dorado",
        center_ra_hours: 5.2,
        center_dec_deg: -60.0,
        segments: SEGMENTS_DOR,
    },
    ConstellationLines {
        abbrev: "Ret",
        name: "Reticulum",
        center_ra_hours: 3.9,
        center_dec_deg: -60.0,
        segments: SEGMENTS_RET,
    },
    ConstellationLines {
        abbrev: "Hor",
        name: "Horologium",
        center_ra_hours: 3.3,
        center_dec_deg: -53.0,
        segments: SEGMENTS_HOR,
    },
    ConstellationLines {
        abbrev: "Cae",
        name: "Caelum",
        center_ra_hours: 4.7,
        center_dec_deg: -38.0,
        segments: SEGMENTS_CAE,
    },
    ConstellationLines {
        abbrev: "Col",
        name: "Columba",
        center_ra_hours: 5.9,
        center_dec_deg: -35.0,
        segments: SEGMENTS_COL,
    },
    ConstellationLines {
        abbrev: "Lep",
        name: "Lepus",
        center_ra_hours: 5.5,
        center_dec_deg: -19.0,
        segments: SEGMENTS_LEP,
    },
    ConstellationLines {
        abbrev: "Mon",
        name: "Monoceros",
        center_ra_hours: 7.2,
        center_dec_deg: -3.0,
        segments: SEGMENTS_MON,
    },
    ConstellationLines {
        abbrev: "Hya",
        name: "Hydra",
        center_ra_hours: 10.2,
        center_dec_deg: -20.0,
        segments: SEGMENTS_HYA,
    },
    ConstellationLines {
        abbrev: "Sex",
        name: "Sextans",
        center_ra_hours: 10.3,
        center_dec_deg: -2.0,
        segments: SEGMENTS_SEX,
    },
    ConstellationLines {
        abbrev: "Ant",
        name: "Antlia",
        center_ra_hours: 10.3,
        center_dec_deg: -34.0,
        segments: SEGMENTS_ANT,
    },
    ConstellationLines {
        abbrev: "Pyx",
        name: "Pyxis",
        center_ra_hours: 8.9,
        center_dec_deg: -27.0,
        segments: SEGMENTS_PYX,
    },
    ConstellationLines {
        abbrev: "Pup",
        name: "Puppis",
        center_ra_hours: 7.3,
        center_dec_deg: -32.0,
        segments: SEGMENTS_PUP,
    },
    ConstellationLines {
        abbrev: "Vel",
        name: "Vela",
        center_ra_hours: 9.4,
        center_dec_deg: -47.0,
        segments: SEGMENTS_VEL,
    },
    ConstellationLines {
        abbrev: "Car",
        name: "Carina",
        center_ra_hours: 8.7,
        center_dec_deg: -63.0,
        segments: SEGMENTS_CAR,
    },
    ConstellationLines {
        abbrev: "Oct",
        name: "Octans",
        center_ra_hours: 22.0,
        center_dec_deg: -82.0,
        segments: SEGMENTS_OCT,
    },
    ConstellationLines {
        abbrev: "Men",
        name: "Mensa",
        center_ra_hours: 5.4,
        center_dec_deg: -77.0,
        segments: SEGMENTS_MEN,
    },
    ConstellationLines {
        abbrev: "Hyi",
        name: "Hydrus",
        center_ra_hours: 2.3,
        center_dec_deg: -72.0,
        segments: SEGMENTS_HYI,
    },
    ConstellationLines {
        abbrev: "Aps",
        name: "Apus",
        center_ra_hours: 16.0,
        center_dec_deg: -75.0,
        segments: SEGMENTS_APS,
    },
    ConstellationLines {
        abbrev: "Sct",
        name: "Scutum",
        center_ra_hours: 18.7,
        center_dec_deg: -10.0,
        segments: SEGMENTS_SCT,
    },
    ConstellationLines {
        abbrev: "Cam",
        name: "Camelopardalis",
        center_ra_hours: 6.1,
        center_dec_deg: 69.0,
        segments: SEGMENTS_CAM,
    },
    ConstellationLines {
        abbrev: "Lyn",
        name: "Lynx",
        center_ra_hours: 8.0,
        center_dec_deg: 48.0,
        segments: SEGMENTS_LYN,
    },
    ConstellationLines {
        abbrev: "LMi",
        name: "Leo Minor",
        center_ra_hours: 10.2,
        center_dec_deg: 33.0,
        segments: SEGMENTS_LMI,
    },
];
