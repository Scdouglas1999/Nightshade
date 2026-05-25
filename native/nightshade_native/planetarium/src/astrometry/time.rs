//! Astronomical time scales: UTC, UT1, TT, and Julian centuries (TT).
//!
//! Leap-second history is a built-in table through 2026 (IERS Bulletin C /
//! IANA `leap-seconds.list`). A pack-loaded table replaces this in a later task.
//! ΔUT1 uses zero correction until the `iers_eop` spline ships (Task 19 scope).

pub use crate::types::AstroTime;

/// Julian date of the J2000.0 epoch in TT (IAU definition).
pub const J2000_JD_TT: f64 = 2_451_545.0;

/// TT − TAI offset in seconds (IAU 2009; SOFA `iauTttai`).
pub const TT_MINUS_TAI_SEC: f64 = 32.184;

/// Days per Julian century (Gregorian year length in the Julian century definition).
pub const DAYS_PER_JULIAN_CENTURY: f64 = 36_525.0;

/// Seconds per day.
const SECONDS_PER_DAY: f64 = 86_400.0;

/// UTC instant (JD at 00:00:00 UTC) from which a `tai_minus_utc` value applies until the next row.
struct LeapSecondEpoch {
    jd_utc: f64,
    tai_minus_utc: i32,
}

/// IERS TAI−UTC step table (1972-01-01 through 2017-01-01; valid through 2026).
///
/// Source: IERS Bulletin C via IANA `leap-seconds.list`
/// (<https://data.iana.org/time-zones/data/leap-seconds.list>).
/// No leap seconds were inserted between 2017-01-01 and 2026; dates after the last
/// row use the final offset (37 s).
const LEAP_SECONDS: &[LeapSecondEpoch] = &[
    LeapSecondEpoch {
        jd_utc: 2_441_317.5,
        tai_minus_utc: 10,
    }, // 1972-01-01
    LeapSecondEpoch {
        jd_utc: 2_441_485.5,
        tai_minus_utc: 11,
    }, // 1972-07-01
    LeapSecondEpoch {
        jd_utc: 2_441_786.5,
        tai_minus_utc: 12,
    }, // 1973-01-01
    LeapSecondEpoch {
        jd_utc: 2_442_351.5,
        tai_minus_utc: 13,
    }, // 1974-01-01
    LeapSecondEpoch {
        jd_utc: 2_442_717.5,
        tai_minus_utc: 14,
    }, // 1975-01-01
    LeapSecondEpoch {
        jd_utc: 2_443_082.5,
        tai_minus_utc: 15,
    }, // 1976-01-01
    LeapSecondEpoch {
        jd_utc: 2_443_448.5,
        tai_minus_utc: 16,
    }, // 1977-01-01
    LeapSecondEpoch {
        jd_utc: 2_443_813.5,
        tai_minus_utc: 17,
    }, // 1978-01-01
    LeapSecondEpoch {
        jd_utc: 2_444_179.5,
        tai_minus_utc: 18,
    }, // 1979-01-01
    LeapSecondEpoch {
        jd_utc: 2_444_544.5,
        tai_minus_utc: 19,
    }, // 1980-01-01
    LeapSecondEpoch {
        jd_utc: 2_445_377.5,
        tai_minus_utc: 20,
    }, // 1981-07-01
    LeapSecondEpoch {
        jd_utc: 2_445_743.5,
        tai_minus_utc: 21,
    }, // 1982-07-01
    LeapSecondEpoch {
        jd_utc: 2_446_108.5,
        tai_minus_utc: 22,
    }, // 1983-07-01
    LeapSecondEpoch {
        jd_utc: 2_446_839.5,
        tai_minus_utc: 23,
    }, // 1985-07-01
    LeapSecondEpoch {
        jd_utc: 2_447_669.5,
        tai_minus_utc: 24,
    }, // 1988-01-01
    LeapSecondEpoch {
        jd_utc: 2_448_400.5,
        tai_minus_utc: 25,
    }, // 1990-01-01
    LeapSecondEpoch {
        jd_utc: 2_448_765.5,
        tai_minus_utc: 26,
    }, // 1991-01-01
    LeapSecondEpoch {
        jd_utc: 2_449_232.5,
        tai_minus_utc: 27,
    }, // 1992-07-01
    LeapSecondEpoch {
        jd_utc: 2_449_597.5,
        tai_minus_utc: 28,
    }, // 1993-07-01
    LeapSecondEpoch {
        jd_utc: 2_449_962.5,
        tai_minus_utc: 29,
    }, // 1994-07-01
    LeapSecondEpoch {
        jd_utc: 2_450_630.5,
        tai_minus_utc: 30,
    }, // 1996-01-01
    LeapSecondEpoch {
        jd_utc: 2_451_098.5,
        tai_minus_utc: 31,
    }, // 1997-07-01
    LeapSecondEpoch {
        jd_utc: 2_451_179.5,
        tai_minus_utc: 32,
    }, // 1999-01-01
    LeapSecondEpoch {
        jd_utc: 2_453_737.5,
        tai_minus_utc: 33,
    }, // 2006-01-01
    LeapSecondEpoch {
        jd_utc: 2_455_319.5,
        tai_minus_utc: 34,
    }, // 2009-01-01
    LeapSecondEpoch {
        jd_utc: 2_456_109.5,
        tai_minus_utc: 35,
    }, // 2012-07-01
    LeapSecondEpoch {
        jd_utc: 2_456_774.5,
        tai_minus_utc: 36,
    }, // 2015-07-01
    LeapSecondEpoch {
        jd_utc: 2_457_663.5,
        tai_minus_utc: 37,
    }, // 2017-01-01
];

/// Julian Date at 00:00:00 UTC for a Gregorian calendar date (Meeus eq. 7.1).
#[cfg(test)]
pub(crate) fn jd_utc_midnight(year: i32, month: u32, day: u32) -> f64 {
    let (y, m) = if month <= 2 {
        (year - 1, month + 12)
    } else {
        (year, month)
    };
    let a = y / 100;
    let b = 2 - a + a / 4;
    (365.25 * f64::from(y + 4716)).floor()
        + (30.6001 * f64::from(m + 1)).floor()
        + f64::from(day)
        + f64::from(b)
        - 1524.5
}

/// TAI−UTC in seconds for the given UTC Julian date.
///
/// Dates before the first table epoch use the first offset (1972-01-01 definition).
pub fn tai_minus_utc_at_jd_utc(jd_utc: f64) -> i32 {
    let mut offset = LEAP_SECONDS[0].tai_minus_utc;
    for epoch in LEAP_SECONDS {
        if jd_utc >= epoch.jd_utc {
            offset = epoch.tai_minus_utc;
        } else {
            break;
        }
    }
    offset
}

/// TT − UTC offset in seconds: `(TAI−UTC) + (TT−TAI)`.
#[inline]
pub fn tt_minus_utc_seconds(jd_utc: f64) -> f64 {
    f64::from(tai_minus_utc_at_jd_utc(jd_utc)) + TT_MINUS_TAI_SEC
}

/// ΔUT1 in seconds (UT1 − UTC). Zero until the IERS EOP spline is loaded (later task).
#[inline]
pub fn delta_ut1_seconds(_jd_utc: f64) -> f64 {
    0.0
}

impl AstroTime {
    /// Build time from a UTC Julian date (JD).
    ///
    /// `jd_ut1 = jd_utc + ΔUT1`; `jd_tt = jd_utc + (TAI−UTC + 32.184) / 86400`.
    pub fn from_jd_utc(jd_utc: f64) -> Self {
        let tt_offset_days = tt_minus_utc_seconds(jd_utc) / SECONDS_PER_DAY;
        let ut1_offset_days = delta_ut1_seconds(jd_utc) / SECONDS_PER_DAY;
        Self {
            jd_utc,
            jd_ut1: jd_utc + ut1_offset_days,
            jd_tt: jd_utc + tt_offset_days,
        }
    }

    /// Julian centuries since J2000.0 measured in TT (SOFA `t` / precession argument).
    #[inline]
    pub fn julian_centuries_tt(&self) -> f64 {
        (self.jd_tt - J2000_JD_TT) / DAYS_PER_JULIAN_CENTURY
    }
}

/// SGP4 satellite propagation (TEME); see [`sgp4_prop`].
#[path = "sgp4_prop.rs"]
pub mod sgp4_prop;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn leap_epoch_jd_matches_meeus() {
        assert!((jd_utc_midnight(1999, 1, 1) - 2_451_179.5).abs() < 1e-6);
        assert!((jd_utc_midnight(2000, 1, 1) + 0.5 - 2_451_545.0).abs() < 1e-6);
    }
}
