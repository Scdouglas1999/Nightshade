//! `guiding` tests — moved verbatim out of the former single `instructions::tests`
//! module (release-pass C3 mechanical split). Shared fixtures stay in the parent
//! `tests` module and reach here through `use super::*;`.

use super::*;

#[test]
fn validate_calibration_rejects_uncalibrated_guider() {
    let calib = crate::GuidingCalibration {
        is_calibrated: false,
        ra_angle_deg: Some(0.0),
        dec_angle_deg: Some(90.0),
    };
    let result = validate_calibration_quality(&calib, &_cfg());
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("not calibrated"));
}

#[test]
fn validate_calibration_accepts_perpendicular_axes() {
    let calib = crate::GuidingCalibration {
        is_calibrated: true,
        ra_angle_deg: Some(0.0),
        dec_angle_deg: Some(90.0),
    };
    assert!(validate_calibration_quality(&calib, &_cfg()).is_ok());
}

#[test]
fn validate_calibration_accepts_perpendicular_axes_modulo_180() {
    // Same physical geometry as (0°, 90°) — either axis could be the
    // "positive" pulse direction. The validator must not penalise this.
    let calib = crate::GuidingCalibration {
        is_calibrated: true,
        ra_angle_deg: Some(180.0),
        dec_angle_deg: Some(90.0),
    };
    assert!(validate_calibration_quality(&calib, &_cfg()).is_ok());
}

#[test]
fn validate_calibration_accepts_axes_within_tolerance() {
    // 15° off perpendicular — under the 20° default ceiling.
    let calib = crate::GuidingCalibration {
        is_calibrated: true,
        ra_angle_deg: Some(0.0),
        dec_angle_deg: Some(75.0),
    };
    assert!(validate_calibration_quality(&calib, &_cfg()).is_ok());
}

#[test]
fn validate_calibration_rejects_grossly_non_perpendicular_axes() {
    // Axes parallel — calibration was almost certainly broken (mount
    // pulsed in the same direction for both axes).
    let calib = crate::GuidingCalibration {
        is_calibrated: true,
        ra_angle_deg: Some(0.0),
        dec_angle_deg: Some(0.0),
    };
    let result = validate_calibration_quality(&calib, &_cfg());
    assert!(result.is_err());
    let msg = result.unwrap_err();
    assert!(msg.contains("off-perpendicular"), "got: {}", msg);
}

#[test]
fn validate_calibration_passes_when_angles_missing() {
    // Driver didn't report angles — we can't validate geometry, but the
    // is_calibrated flag is true so we let it through. The RMS sampling
    // step is the safety net for this case.
    let calib = crate::GuidingCalibration {
        is_calibrated: true,
        ra_angle_deg: None,
        dec_angle_deg: None,
    };
    assert!(validate_calibration_quality(&calib, &_cfg()).is_ok());
}

#[test]
fn validate_calibration_honours_custom_tolerance() {
    // 25° off perpendicular — over default 20° ceiling but under custom 30°.
    let calib = crate::GuidingCalibration {
        is_calibrated: true,
        ra_angle_deg: Some(0.0),
        dec_angle_deg: Some(65.0),
    };
    let strict = StartGuidingConfig::default();
    assert!(validate_calibration_quality(&calib, &strict).is_err());

    let lax = StartGuidingConfig {
        max_calibration_axis_error_deg: 30.0,
        ..StartGuidingConfig::default()
    };
    assert!(validate_calibration_quality(&calib, &lax).is_ok());
}

#[tokio::test(start_paused = true)]
async fn guiding_validation_failure_stops_started_guider() {
    let ops = Arc::new(
        ScriptedDomeRotatorOps::new().with_guider_calibration(GuidingCalibration {
            is_calibrated: false,
            ra_angle_deg: Some(0.0),
            dec_angle_deg: Some(90.0),
        }),
    );
    let ctx = ctx_with_ops(ops.clone()).await;
    let config = StartGuidingConfig {
        settle_time: 0.0,
        settle_timeout: 10.0,
        ..StartGuidingConfig::default()
    };

    let result = execute_start_guiding(&config, &ctx, None).await;

    assert_eq!(result.status, NodeStatus::Failure);
    assert_eq!(ops.guider_start_calls.load(Ordering::SeqCst), 1);
    assert_eq!(
        ops.guider_stop_calls.load(Ordering::SeqCst),
        1,
        "every post-start validation failure must stop the guider before returning"
    );
    assert!(!ops.guiding.load(Ordering::SeqCst));
}
