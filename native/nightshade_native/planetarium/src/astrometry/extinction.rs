//! Atmospheric extinction lookup for star rendering.
//!
//! Port of `AtmosphericExtinctionLUT` in
//! `packages/nightshade_planetarium/lib/src/rendering/sky_renderer.dart`
//! (91 entries for altitudes 0–90°, linear interpolation).

/// Brightness multiplier and horizon reddening for a given altitude (degrees).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ExtinctionSample {
    /// Multiplier for star brightness in \[0.5, 1.0\] below 30° altitude.
    pub brightness_factor: f64,
    /// Color lerp amount toward warm horizon color in \[0.0, 0.4\].
    pub red_shift: f64,
}

/// Precomputed 91-entry table: index = integer altitude in degrees (0..=90).
const LUT: [(f64, f64); 91] = build_lut();

const fn build_lut() -> [(f64, f64); 91] {
    let mut table = [(1.0, 0.0); 91];
    let mut alt = 0usize;
    while alt < 91 {
        if alt >= 30 {
            table[alt] = (1.0, 0.0);
        } else {
            let alt_f = alt as f64;
            let extinction_factor = clamp01(alt_f / 30.0) * 0.5 + 0.5;
            let red_shift = (1.0 - extinction_factor) * 0.4;
            table[alt] = (extinction_factor, red_shift);
        }
        alt += 1;
    }
    table
}

const fn clamp01(x: f64) -> f64 {
    if x < 0.0 {
        0.0
    } else if x > 1.0 {
        1.0
    } else {
        x
    }
}

/// Integer-altitude table entry (no interpolation).
#[inline]
pub fn lut_entry(altitude_deg: u8) -> ExtinctionSample {
    let idx = altitude_deg.min(90) as usize;
    let (brightness_factor, red_shift) = LUT[idx];
    ExtinctionSample {
        brightness_factor,
        red_shift,
    }
}

/// Look up extinction for a given altitude in degrees (linear interpolation).
///
/// Matches Dart `AtmosphericExtinctionLUT.lookup`: at or above 30° returns unity;
/// at or below 0° clamps to the horizon entry.
pub fn lookup(altitude_deg: f64) -> ExtinctionSample {
    if altitude_deg >= 30.0 {
        return ExtinctionSample {
            brightness_factor: 1.0,
            red_shift: 0.0,
        };
    }
    if altitude_deg <= 0.0 {
        let (brightness_factor, red_shift) = LUT[0];
        return ExtinctionSample {
            brightness_factor,
            red_shift,
        };
    }

    let lower = altitude_deg.floor() as usize;
    let upper = lower + 1;
    if upper > 90 {
        let (brightness_factor, red_shift) = LUT[90];
        return ExtinctionSample {
            brightness_factor,
            red_shift,
        };
    }

    let t = altitude_deg - lower as f64;
    let (b_low, r_low) = LUT[lower];
    let (b_high, r_high) = LUT[upper];
    ExtinctionSample {
        brightness_factor: b_low + (b_high - b_low) * t,
        red_shift: r_low + (r_high - r_low) * t,
    }
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn horizon_entry_matches_dart() {
        let s = lut_entry(0);
        assert!((s.brightness_factor - 0.5).abs() < 1e-15);
        assert!((s.red_shift - 0.2).abs() < 1e-15);
    }
}
