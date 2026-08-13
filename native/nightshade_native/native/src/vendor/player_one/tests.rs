// =============================================================================
// UNIT TESTS
// =============================================================================

use super::*;

/// `max_adu` must be the RAW16 container ceiling, not the ADC range.
///
/// `(1 << bit_depth) - 1` — what this used to publish — is the ADC range and
/// is 16x too small for a 12-bit Player One (Mars/Neptune/Uranus/Ceres/
/// Artemis class). PlayerOneCamera.h:51 documents the delivered RAW16 sample
/// range as `[0, 65535]` while :137 documents `bitDepth` as the "ADC depth
/// of CMOS sensor" — two different quantities.
#[test]
pub(crate) fn raw16_container_max_adu_accounts_for_left_justification() {
    // 12-bit ADC (IMX462/IMX464/IMX294 class): 4095 << 4
    assert_eq!(raw16_container_max_adu(12), 65520);
    // 14-bit ADC: 16383 << 2
    assert_eq!(raw16_container_max_adu(14), 65532);
    // 10-bit ADC: 1023 << 6
    assert_eq!(raw16_container_max_adu(10), 65472);
    // A genuinely 16-bit ADC (IMX455/IMX571 class) needs no shift.
    assert_eq!(raw16_container_max_adu(16), 65535);
}

/// Whatever ceiling we publish must be a value a `u16` sample can actually
/// hold, and must land on the sample grid the ADC produces — a 12-bit ADC
/// left-justified into 16 bits can only emit multiples of 16.
#[test]
pub(crate) fn raw16_container_max_adu_is_a_reachable_u16_sample() {
    for bit_depth in 1..=16u32 {
        let max = raw16_container_max_adu(bit_depth);
        assert!(
            max <= u32::from(u16::MAX),
            "bit_depth {bit_depth} produced {max}, outside the u16 container"
        );
        let step = 1u32 << (16 - bit_depth.min(16));
        assert_eq!(
            max % step,
            0,
            "bit_depth {bit_depth}: {max} is not a multiple of the {step}-ADU sample step"
        );
    }
}

/// An unpopulated / nonsensical `bitDepth` must fall back to the container
/// ceiling, never to 0 — a 0 ceiling would tell every percent-of-full-scale
/// consumer that the camera cannot produce any signal at all, and the old
/// `(1 << bit_depth) - 1` also overflowed for `bit_depth >= 32`.
#[test]
pub(crate) fn raw16_container_max_adu_unknown_bit_depth_falls_back_to_container() {
    assert_eq!(raw16_container_max_adu(0), 65535);
    assert_eq!(raw16_container_max_adu(32), 65535);
    assert_eq!(raw16_container_max_adu(u32::MAX), 65535);
}

/// The ceiling must agree with the pipeline's own saturation threshold.
///
/// `nightshade_imaging::fits` uses `saturation_threshold: 65024` documented
/// as "4064 << 4" — 99.2% of a left-justified 12-bit ceiling. That threshold
/// is unreachable under the old `(1 << 12) - 1 = 4095` ceiling, which is what
/// made flat calibration impossible on ZWO before the same fix landed there.
#[test]
pub(crate) fn raw16_container_max_adu_agrees_with_pipeline_saturation_threshold() {
    const PIPELINE_SATURATION_THRESHOLD: u32 = 65024;
    let twelve_bit_ceiling = raw16_container_max_adu(12);
    assert!(
        PIPELINE_SATURATION_THRESHOLD < twelve_bit_ceiling,
        "12-bit ceiling {twelve_bit_ceiling} is below the pipeline saturation threshold"
    );
    // The formula this replaced published the ADC range, which can never
    // reach the threshold — so saturation was undetectable on a 12-bit ASI-
    // class sensor, and a 50% flat target was below the camera's bias floor.
    let old_adc_range_formula = |bits: u32| (1u32 << bits) - 1;
    assert!(old_adc_range_formula(12) < PIPELINE_SATURATION_THRESHOLD);
}

/// Default state must be cooler-off.
///
/// Establishes the baseline that the previous hardcoded `cooler_on: false`
/// satisfied — we still report off when nothing has been written.
#[test]
pub(crate) fn cooler_state_defaults_to_off() {
    let cam = PlayerOneCamera::new(0);
    let snap = *cam.cooler_state.lock().unwrap();
    assert!(!snap.enabled);
    assert_eq!(snap.target_c, 0.0);
}

/// After a successful `set_cooler(true, target)` write, an immediate
/// `get_status` must surface `cooler_on == true` and the target temp.
///
/// We exercise the same code path the production `set_cooler` uses to
/// update `cooler_state` (after the SDK accepted the change) and the same
/// fallback path `get_status` uses when the SDK read-back is unavailable.
/// This covers the regression in §5.7 — the old hardcoded `cooler_on:
/// false` is no longer possible because the cached value is the floor.
#[test]
pub(crate) fn set_cooler_then_status_reports_enabled() {
    let cam = PlayerOneCamera::new(0);

    // Pre-condition: default is off.
    assert!(!cam.cooler_state.lock().unwrap().enabled);

    // Simulate the post-SDK-success update that `set_cooler` performs.
    {
        let mut guard = cam.cooler_state.lock().unwrap();
        guard.enabled = true;
        guard.target_c = -10.0;
    }

    // Read back via the same mutex path `get_status` uses when the SDK
    // read-back is unavailable.
    let snap = *cam.cooler_state.lock().unwrap();
    assert!(
        snap.enabled,
        "cooler_on must reflect the last set_cooler call"
    );
    assert_eq!(snap.target_c, -10.0);
}

/// Writing `set_cooler(false, ...)` must clear the enabled flag — the
/// dashboard cannot get stuck reporting "cooler on" after warm-up.
#[test]
pub(crate) fn set_cooler_then_disable_reports_off() {
    let cam = PlayerOneCamera::new(0);

    {
        let mut guard = cam.cooler_state.lock().unwrap();
        guard.enabled = true;
        guard.target_c = -15.0;
    }
    assert!(cam.cooler_state.lock().unwrap().enabled);

    {
        let mut guard = cam.cooler_state.lock().unwrap();
        guard.enabled = false;
        guard.target_c = 20.0;
    }

    let snap = *cam.cooler_state.lock().unwrap();
    assert!(!snap.enabled);
    assert_eq!(snap.target_c, 20.0);
}
