//! Curated variable-star metadata (J2000 RA hours / Dec degrees).
//!
//! Ported from `packages/nightshade_planetarium/lib/src/catalogs/variable_star_catalog.dart`.
//! Star table lives in `variable_stars_data.inc.rs` (generated via `scripts/gen_variable_stars.py`).

/// GCVS / VSX-style variable star classification.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum VariableStarKind {
    /// Mira-type long-period pulsating.
    Mira = 0,
    /// Cepheid pulsating.
    Cepheid,
    /// RR Lyrae pulsating.
    RrLyrae,
    /// Eclipsing binary (Algol-type).
    EclipsingAlgol,
    /// Eclipsing binary (Beta Lyrae-type).
    EclipsingBetaLyr,
    /// Eclipsing binary (W UMa-type).
    EclipsingWUma,
    /// Semi-regular pulsating.
    SemiRegular,
    /// Irregular variable.
    Irregular,
    /// Delta Scuti-type.
    DeltaScuti,
    /// Gamma Cassiopeiae (eruptive Be).
    GammaCas,
    /// R Coronae Borealis (fading eruptive).
    RCrB,
    /// Nova or recurrent nova.
    Nova,
    /// Dwarf nova / cataclysmic.
    DwarfNova,
    /// RS Canum Venaticorum.
    RsCVn,
    /// BY Draconis (spotted rotating).
    ByDra,
    /// Slowly pulsating B star.
    Spb,
    /// Other / unclassified.
    Other,
}

impl VariableStarKind {
    /// Human-readable label (matches v1 `displayName`).
    #[must_use]
    pub const fn display_name(self) -> &'static str {
        match self {
            Self::Mira => "Mira (Long Period)",
            Self::Cepheid => "Cepheid",
            Self::RrLyrae => "RR Lyrae",
            Self::EclipsingAlgol => "Eclipsing (Algol)",
            Self::EclipsingBetaLyr => "Eclipsing (Beta Lyrae)",
            Self::EclipsingWUma => "Eclipsing (W UMa)",
            Self::SemiRegular => "Semi-Regular",
            Self::Irregular => "Irregular",
            Self::DeltaScuti => "Delta Scuti",
            Self::GammaCas => "Gamma Cas (Be star)",
            Self::RCrB => "R CrB (Fading)",
            Self::Nova => "Nova",
            Self::DwarfNova => "Dwarf Nova",
            Self::RsCVn => "RS CVn",
            Self::ByDra => "BY Dra",
            Self::Spb => "Slowly Pulsating B",
            Self::Other => "Variable",
        }
    }

    /// Short GCVS-style abbreviation (matches v1 `abbreviation`).
    #[must_use]
    pub const fn abbreviation(self) -> &'static str {
        match self {
            Self::Mira => "M",
            Self::Cepheid => "CEP",
            Self::RrLyrae => "RR",
            Self::EclipsingAlgol => "EA",
            Self::EclipsingBetaLyr => "EB",
            Self::EclipsingWUma => "EW",
            Self::SemiRegular => "SR",
            Self::Irregular => "L",
            Self::DeltaScuti => "DSCT",
            Self::GammaCas => "GCAS",
            Self::RCrB => "RCB",
            Self::Nova => "N",
            Self::DwarfNova => "UG",
            Self::RsCVn => "RS",
            Self::ByDra => "BY",
            Self::Spb => "SPB",
            Self::Other => "VAR",
        }
    }
}

/// One curated variable star entry.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VariableStar {
    /// Common name (e.g. `"Mira"`, `"Algol"`).
    pub name: &'static str,
    /// Bayer / Flamsteed designation when known.
    pub designation: Option<&'static str>,
    /// Three-letter IAU constellation abbreviation.
    pub constellation: &'static str,
    /// J2000 right ascension (hours).
    pub ra_hours: f32,
    /// J2000 declination (degrees).
    pub dec_deg: f32,
    /// Variable-star classification (GCVS / VSX style).
    pub kind: VariableStarKind,
    /// Pulsation / eclipse period in days (`None` if irregular or unknown).
    pub period_days: Option<f32>,
    /// Maximum (brightest) visual magnitude.
    pub mag_max: f32,
    /// Minimum (faintest) visual magnitude.
    pub mag_min: f32,
    /// Spectral type string when known.
    pub spectral_type: Option<&'static str>,
}

/// Number of curated variable stars (v1 catalog size).
pub const STAR_COUNT: usize = 97;

include!("variable_stars_data.inc.rs");

/// All curated variable stars.
#[must_use]
pub const fn stars() -> &'static [VariableStar] {
    STARS
}

/// Visual magnitude span (`mag_min - mag_max`).
#[must_use]
pub const fn mag_range(star: &VariableStar) -> f32 {
    star.mag_min - star.mag_max
}

/// Convert J2000 equatorial coordinates to a unit ICRS direction.
#[must_use]
pub fn icrs_dir_from_j2000(ra_hours: f32, dec_deg: f32) -> [f32; 3] {
    let ra_rad = ra_hours * (std::f32::consts::PI / 12.0);
    let dec_rad = dec_deg.to_radians();
    let (sin_dec, cos_dec) = dec_rad.sin_cos();
    let (sin_ra, cos_ra) = ra_rad.sin_cos();
    [cos_dec * cos_ra, cos_dec * sin_ra, sin_dec]
}

/// Unit ICRS direction for this star.
#[must_use]
pub fn icrs_dir(star: &VariableStar) -> [f32; 3] {
    icrs_dir_from_j2000(star.ra_hours, star.dec_deg)
}

/// Julian Date from UTC civil time (matches v1 `_julianDate`).
#[must_use]
pub fn julian_date_from_utc(
    year: i32,
    month: u32,
    day: u32,
    hour: u32,
    minute: u32,
    second: u32,
) -> f64 {
    let d = f64::from(day)
        + f64::from(hour) / 24.0
        + f64::from(minute) / 1440.0
        + f64::from(second) / 86400.0;
    let month_i = i32::try_from(month).unwrap_or(1);
    let a = (14 - month_i) / 12;
    let y = f64::from(year + 4800 - a);
    let m = f64::from(month_i + 12 * a - 3);
    d + ((153.0 * m + 2.0) / 5.0).floor()
        + 365.0 * y
        + (y / 4.0).floor()
        - (y / 100.0).floor()
        + (y / 400.0).floor()
        - 32_045.0
        - 0.5
}

/// Approximate visual magnitude at `jd` using the v1 light-curve models.
#[must_use]
pub fn estimate_magnitude(star: &VariableStar, jd: f64) -> f32 {
    let Some(period) = star.period_days else {
        return (star.mag_max + star.mag_min) / 2.0;
    };
    if period <= 0.0 {
        return (star.mag_max + star.mag_min) / 2.0;
    }

    const J2000: f64 = 2_451_545.0;
    let phase = ((jd - J2000) / f64::from(period)) % 1.0;
    let phase = phase as f32;

    match star.kind {
        VariableStarKind::EclipsingAlgol => {
            let eclipse_width = 0.1f32;
            if phase < eclipse_width || phase > (1.0 - eclipse_width) {
                let eclipse_phase = if phase < 0.5 { phase } else { 1.0 - phase };
                let depth = (eclipse_phase / eclipse_width * std::f32::consts::PI).cos();
                star.mag_max + (star.mag_min - star.mag_max) * (1.0 + depth) / 2.0
            } else {
                star.mag_max
            }
        }
        VariableStarKind::Mira => {
            let light_phase = if phase < 0.35 {
                phase / 0.35
            } else {
                1.0 - (phase - 0.35) / 0.65
            };
            star.mag_min - (star.mag_min - star.mag_max) * light_phase
        }
        VariableStarKind::Cepheid => {
            let light_phase = if phase < 0.3 {
                phase / 0.3
            } else {
                1.0 - (phase - 0.3) / 0.7
            };
            star.mag_min - (star.mag_min - star.mag_max) * light_phase
        }
        _ => {
            let sin_phase = (phase * 2.0 * std::f32::consts::PI).sin();
            (star.mag_max + star.mag_min) / 2.0 - (star.mag_min - star.mag_max) / 2.0 * sin_phase
        }
    }
}

/// Look up a star by exact common name (case-insensitive).
#[must_use]
pub fn find_by_name(name: &str) -> Option<&'static VariableStar> {
    let key = name.trim();
    STARS.iter().find(|s| s.name.eq_ignore_ascii_case(key))
}

/// Stars at or brighter than `mag_limit` at maximum light (`mag_max <= mag_limit`).
#[must_use]
pub fn brighter_than(mag_limit: f32) -> Vec<&'static VariableStar> {
    STARS
        .iter()
        .filter(|s| s.mag_max <= mag_limit)
        .collect()
}

/// Stars of a given classification.
#[must_use]
pub fn by_kind(kind: VariableStarKind) -> Vec<&'static VariableStar> {
    STARS.iter().filter(|s| s.kind == kind).collect()
}

/// Stars in a constellation (abbreviation, case-insensitive).
#[must_use]
pub fn by_constellation(constellation: &str) -> Vec<&'static VariableStar> {
    let key = constellation.trim();
    STARS
        .iter()
        .filter(|s| s.constellation.eq_ignore_ascii_case(key))
        .collect()
}

/// Search by name, designation, or constellation substring (case-insensitive).
#[must_use]
pub fn search(query: &str) -> Vec<&'static VariableStar> {
    let lower = query.trim().to_ascii_lowercase();
    if lower.is_empty() {
        return Vec::new();
    }
    STARS
        .iter()
        .filter(|s| {
            s.name.to_ascii_lowercase().contains(&lower)
                || s.designation
                    .is_some_and(|d| d.to_ascii_lowercase().contains(&lower))
                || s.constellation.to_ascii_lowercase().contains(&lower)
        })
        .collect()
}
