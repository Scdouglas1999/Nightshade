//! `slew` tests — moved verbatim out of the former single `instructions::tests`
//! module (release-pass C3 mechanical split). Shared fixtures stay in the parent
//! `tests` module and reach here through `use super::*;`.

use super::*;

#[test]
fn test_normalize_ra_diff_hours_no_wrap() {
    // Simple cases with no wraparound
    assert!((normalize_ra_diff_hours(1.0) - 1.0).abs() < 0.0001);
    assert!((normalize_ra_diff_hours(-1.0) - (-1.0)).abs() < 0.0001);
    assert!((normalize_ra_diff_hours(11.0) - 11.0).abs() < 0.0001);
    assert!((normalize_ra_diff_hours(-11.0) - (-11.0)).abs() < 0.0001);
}

#[test]
fn test_normalize_ra_diff_hours_wraparound() {
    // Wraparound cases: 23h to 1h should be 2h diff, not 22h
    assert!((normalize_ra_diff_hours(22.0) - (-2.0)).abs() < 0.0001);
    assert!((normalize_ra_diff_hours(-22.0) - 2.0).abs() < 0.0001);

    // 13 hours should wrap to -11 hours (shorter path)
    assert!((normalize_ra_diff_hours(13.0) - (-11.0)).abs() < 0.0001);
    assert!((normalize_ra_diff_hours(-13.0) - 11.0).abs() < 0.0001);

    // Edge case: exactly 12 hours
    assert!((normalize_ra_diff_hours(12.0).abs() - 12.0).abs() < 0.0001);
}

#[test]
fn test_validate_slew_position_success() {
    // Exact match
    assert!(validate_slew_position(12.0, 45.0, 12.0, 45.0, 1.0 / 60.0).is_ok());

    // Within tolerance (less than 1 arcminute = 1/60 degree)
    let small_diff = 0.5 / 60.0; // 0.5 arcminute
    let ra_diff_hours = small_diff / 15.0; // Convert degrees to hours
    assert!(validate_slew_position(
        12.0,
        45.0,
        12.0 + ra_diff_hours,
        45.0 + small_diff,
        1.0 / 60.0
    )
    .is_ok());
}

#[test]
fn test_validate_slew_position_ra_failure() {
    // RA exceeds tolerance (2 arcminutes when tolerance is 1)
    let large_diff_hours = (2.0 / 60.0) / 15.0; // 2 arcminutes in hours
    let result = validate_slew_position(12.0, 45.0, 12.0 + large_diff_hours, 45.0, 1.0 / 60.0);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("did not reach target"));
}

#[test]
fn test_validate_slew_position_dec_failure() {
    // Dec exceeds tolerance
    let large_diff_deg = 2.0 / 60.0; // 2 arcminutes
    let result = validate_slew_position(12.0, 45.0, 12.0, 45.0 + large_diff_deg, 1.0 / 60.0);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("did not reach target"));
}

#[test]
fn test_validate_slew_position_ra_wraparound() {
    // Test RA wraparound: target at 0.1h, actual at 23.9h should be 0.2h diff = 3 degrees
    // This is well within tolerance (we'll use a generous tolerance for this test)
    let tolerance = 5.0; // 5 degrees
    assert!(validate_slew_position(0.1, 45.0, 23.9, 45.0, tolerance).is_ok());

    // With 1 arcminute tolerance, 0.2h = 3 degrees should fail
    let result = validate_slew_position(0.1, 45.0, 23.9, 45.0, 1.0 / 60.0);
    assert!(result.is_err());
}
