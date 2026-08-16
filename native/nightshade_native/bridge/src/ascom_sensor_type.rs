//! ASCOM `SensorType` → Bayer element order.
//!
//! ASCOM ICameraV3 defines `SensorType` as 0 Monochrome, 1 Color, 2 RGGB,
//! 3 CMYG, 4 CMYG2, 5 LRGB. The ordinal names the colour-filter *family*, never
//! the element order: every RGGB-family mosaic reports 2, and which corner of
//! the 2×2 block holds red is carried only by `BayerOffsetX`/`BayerOffsetY`.
//! Type 1 is a direct-colour sensor with no Bayer mask, so its offsets name
//! nothing; types 3..=5 are mosaics with no RGGB-style order to name.
//!
//! Deriving a pattern from the family ordinal alone transposes red and blue on
//! a BGGR or GRBG sensor and writes the wrong `BAYERPAT` into the FITS header,
//! and neither is recoverable from the saved frame. `None` therefore means "the
//! pattern is unknown", which leaves the frame undebayered and the `BAYERPAT`
//! card unwritten rather than debayered wrongly.
//!
//! Both ASCOM transports carry this same enum — the Windows COM worker in
//! `ascom_wrapper` and the Alpaca HTTP download path — so the mapping lives
//! here, compiled and regression-tested on every platform.

use nightshade_native::camera::BayerPattern;

/// The `SensorType` ordinal for an RGGB-family colour-filter array, the one
/// family whose element order [`BayerPattern`] can name.
pub const SENSOR_TYPE_RGGB: i32 = 2;

/// True when `SensorType` names an RGGB-family mosaic, so `BayerOffsetX` and
/// `BayerOffsetY` are worth the two property reads.
///
/// Monochrome (0) and direct-colour (1) sensors carry no Bayer mask, the CMYG
/// (3), CMYG2 (4) and LRGB (5) mosaics have no RGGB-style order, and an
/// unreadable `SensorType` names nothing at all — the offsets are skipped for
/// every one of them.
pub fn has_nameable_bayer_order(sensor_type: i32) -> bool {
    sensor_type == SENSOR_TYPE_RGGB
}

/// True when `SensorType` names one of the colour families (1..=5).
///
/// Colour and Bayer order are independent answers: a direct-colour sensor
/// (type 1) is colour with no Bayer mask, and the CMYG/CMYG2/LRGB mosaics are
/// colour with no RGGB-style order. An ordinal outside the enum names no
/// family, so it reads monochrome — debayering a mono frame is a no-op, while
/// treating a frame as colour on a guess is not.
pub fn is_colour_sensor(sensor_type: i32) -> bool {
    (1..=5).contains(&sensor_type)
}

/// Derive the Bayer element order from `SensorType` plus the
/// `BayerOffsetX`/`BayerOffsetY` pair.
///
/// The result is `None` whenever the offsets do not pin an order down: the
/// sensor family has none to name, an offset is unreadable (`None`), or the
/// pair falls outside the 2×2 block.
pub fn bayer_pattern_from_sensor(
    sensor_type: i32,
    offset_x: Option<i32>,
    offset_y: Option<i32>,
) -> Option<BayerPattern> {
    if !has_nameable_bayer_order(sensor_type) {
        return None;
    }
    match (offset_x, offset_y) {
        (Some(0), Some(0)) => Some(BayerPattern::Rggb),
        (Some(1), Some(0)) => Some(BayerPattern::Grbg),
        (Some(0), Some(1)) => Some(BayerPattern::Gbrg),
        (Some(1), Some(1)) => Some(BayerPattern::Bggr),
        (x, y) => {
            tracing::warn!(
                "ASCOM camera reports SensorType={} with unusable Bayer offsets \
                 (x: {:?}, y: {:?}); leaving the Bayer pattern unknown rather than \
                 guessing an element order",
                sensor_type,
                x,
                y
            );
            None
        }
    }
}

/// The FITS `BAYERPAT` spelling of a pattern.
//
// The only non-test caller is the `#[cfg(windows)]` ASCOM COM worker, so
// off-Windows this is reached solely by the regression suite below; the allow
// keeps the `-D warnings` gate green while the logic stays compiled and tested
// everywhere.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn bayer_pattern_fits_name(pattern: BayerPattern) -> &'static str {
    match pattern {
        BayerPattern::Rggb => "RGGB",
        BayerPattern::Grbg => "GRBG",
        BayerPattern::Gbrg => "GBRG",
        BayerPattern::Bggr => "BGGR",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The offset pair, not the `SensorType` ordinal, names the element order:
    /// all four corners are reachable from the one RGGB-family ordinal.
    #[test]
    fn rggb_family_reads_the_order_out_of_the_offsets() {
        assert_eq!(
            bayer_pattern_from_sensor(2, Some(0), Some(0)),
            Some(BayerPattern::Rggb)
        );
        assert_eq!(
            bayer_pattern_from_sensor(2, Some(1), Some(0)),
            Some(BayerPattern::Grbg)
        );
        assert_eq!(
            bayer_pattern_from_sensor(2, Some(0), Some(1)),
            Some(BayerPattern::Gbrg)
        );
        assert_eq!(
            bayer_pattern_from_sensor(2, Some(1), Some(1)),
            Some(BayerPattern::Bggr)
        );
    }

    /// A BGGR sensor is never reported as RGGB: that transposes red and blue in
    /// every debayered frame and stamps the wrong `BAYERPAT`.
    #[test]
    fn rggb_family_does_not_assume_rggb() {
        assert_eq!(
            bayer_pattern_from_sensor(2, Some(1), Some(1)),
            Some(BayerPattern::Bggr),
            "the offset pair, not the SensorType ordinal, names the element order"
        );
    }

    /// SensorType 1 is a direct-colour sensor with no Bayer mask: it is colour,
    /// its offsets are meaningless, and no `BAYERPAT` card is produced.
    #[test]
    fn direct_colour_sensor_is_colour_without_a_pattern() {
        assert!(is_colour_sensor(1));
        assert!(!has_nameable_bayer_order(1));
        assert_eq!(bayer_pattern_from_sensor(1, Some(0), Some(0)), None);
        assert_eq!(bayer_pattern_from_sensor(1, Some(1), Some(1)), None);
        assert_eq!(bayer_pattern_from_sensor(1, None, None), None);
    }

    /// Monochrome is neither colour nor masked.
    #[test]
    fn monochrome_sensor_has_no_pattern() {
        assert!(!is_colour_sensor(0));
        assert!(!has_nameable_bayer_order(0));
        assert_eq!(bayer_pattern_from_sensor(0, Some(0), Some(0)), None);
    }

    /// CMYG (3), CMYG2 (4) and LRGB (5) are colour and do carry offsets, but
    /// they index a mosaic [`BayerPattern`] cannot name, so the pattern stays
    /// unknown.
    #[test]
    fn non_rggb_mosaics_have_no_nameable_order() {
        for sensor_type in [3, 4, 5] {
            assert!(is_colour_sensor(sensor_type));
            assert!(
                !has_nameable_bayer_order(sensor_type),
                "SensorType={sensor_type} has no RGGB-style order to name"
            );
            for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                assert_eq!(
                    bayer_pattern_from_sensor(sensor_type, Some(x), Some(y)),
                    None,
                    "SensorType={sensor_type} offsets ({x}, {y}) named an RGGB pattern"
                );
            }
        }
    }

    /// An unreadable offset leaves the pattern unknown instead of defaulting to
    /// the (0, 0) corner.
    #[test]
    fn unreadable_offsets_leave_the_pattern_unknown() {
        assert_eq!(bayer_pattern_from_sensor(2, None, Some(0)), None);
        assert_eq!(bayer_pattern_from_sensor(2, Some(0), None), None);
        assert_eq!(bayer_pattern_from_sensor(2, None, None), None);
    }

    /// An offset pair outside the 2×2 block is unknown, not RGGB.
    #[test]
    fn out_of_range_offsets_leave_the_pattern_unknown() {
        assert_eq!(bayer_pattern_from_sensor(2, Some(2), Some(0)), None);
        assert_eq!(bayer_pattern_from_sensor(2, Some(-1), Some(1)), None);
        assert_eq!(bayer_pattern_from_sensor(2, Some(0), Some(7)), None);
    }

    /// An ordinal outside the enum names no family, so the frame is neither
    /// claimed colour nor debayered.
    #[test]
    fn out_of_enum_sensor_type_is_mono_without_a_pattern() {
        for sensor_type in [-1, 6, 99] {
            assert!(
                !is_colour_sensor(sensor_type),
                "SensorType={sensor_type} is outside the enum and names no family"
            );
            assert!(!has_nameable_bayer_order(sensor_type));
            assert_eq!(
                bayer_pattern_from_sensor(sensor_type, Some(0), Some(0)),
                None
            );
        }
    }

    /// Verbatim copy of `ascom_wrapper::camera::bayer_pattern_from_sensor`,
    /// which is `#[cfg(windows)]` and so cannot compile on a Linux host. The
    /// copy keeps the COM worker's adapter under test here.
    fn ascom_wrapper_adapter(
        sensor_type: i32,
        offset_x: Option<i32>,
        offset_y: Option<i32>,
    ) -> Option<String> {
        bayer_pattern_from_sensor(sensor_type, offset_x, offset_y)
            .map(|pattern| bayer_pattern_fits_name(pattern).to_string())
    }

    /// The COM worker's adapter answers the same families the same way, and
    /// renders only the four `BAYERPAT` spellings `map_bayer_pattern` accepts.
    #[test]
    fn ascom_wrapper_adapter_matches_the_shared_mapping() {
        assert_eq!(
            ascom_wrapper_adapter(2, Some(0), Some(0)).as_deref(),
            Some("RGGB")
        );
        assert_eq!(
            ascom_wrapper_adapter(2, Some(1), Some(0)).as_deref(),
            Some("GRBG")
        );
        assert_eq!(
            ascom_wrapper_adapter(2, Some(0), Some(1)).as_deref(),
            Some("GBRG")
        );
        assert_eq!(
            ascom_wrapper_adapter(2, Some(1), Some(1)).as_deref(),
            Some("BGGR")
        );
        // Offsets unreadable on an RGGB-family sensor, and outside the block.
        assert_eq!(ascom_wrapper_adapter(2, None, Some(0)), None);
        assert_eq!(ascom_wrapper_adapter(2, Some(0), None), None);
        assert_eq!(ascom_wrapper_adapter(2, None, None), None);
        assert_eq!(ascom_wrapper_adapter(2, Some(2), Some(0)), None);
        // Monochrome, direct colour, and the CMYG/CMYG2/LRGB mosaics.
        for sensor_type in [0, 1, 3, 4, 5, -1] {
            assert_eq!(
                ascom_wrapper_adapter(sensor_type, Some(0), Some(0)),
                None,
                "SensorType={sensor_type} produced a BAYERPAT card"
            );
        }
    }

    /// The FITS spelling round-trips: every pattern the mapping produces has a
    /// `BAYERPAT` name, and that name maps back to the same pattern.
    #[test]
    fn fits_names_round_trip() {
        for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let pattern =
                bayer_pattern_from_sensor(2, Some(x), Some(y)).expect("offsets name a pattern");
            let name = bayer_pattern_fits_name(pattern);
            let back = match name {
                "RGGB" => BayerPattern::Rggb,
                "GRBG" => BayerPattern::Grbg,
                "GBRG" => BayerPattern::Gbrg,
                "BGGR" => BayerPattern::Bggr,
                other => panic!("offsets ({x}, {y}) produced unmappable BAYERPAT {other}"),
            };
            assert_eq!(back, pattern);
        }
    }
}
