//! Synthetic frame generation for the simulator camera.
//!
//! Extracted from the `DriverType::Simulator` download arm so the frame can be
//! run through the REAL star detector in a unit test. That matters more than
//! usual here: every focus, HFR and grading result an operator sees while
//! evaluating Nightshade without hardware is measured against this buffer, so if
//! it is not detectable-star-bearing, those subsystems silently report nothing
//! and the simulator quietly teaches the wrong thing.
//!
//! History: the original buffer was all zeros, which `[IMAGE_VALIDATION]`
//! correctly rejected as a dead frame, so no simulated sequence could run. That
//! was replaced by a faint gradient plus four flat 6x6 blocks of 50,000 ADU —
//! enough to pass validation, but the detector found NONE of them (every frame
//! logged "no stars detected for HFR calculation", autofocus died with
//! "Insufficient stars detected. Only 0 stars found (minimum: 10)", and the
//! HFR-degradation / focus-drift triggers had nothing to measure). Hence the
//! Gaussian field below, plus the tests that hold it to the detector's bar.

/// Simulated sensor dimensions for the synthetic download.
///
/// Narrower than the singleton's declared sensor (4144x2822) because tests rely
/// on a deterministic image size and the singleton declares no subframe.
pub const SIM_W: usize = 1920;
pub const SIM_H: usize = 1080;

/// Focuser position at which simulated stars are sharpest.
///
/// Chosen to sit INSIDE the default autofocus sweep but off its centre. The
/// focuser starts at 25000 and the default sweep spans roughly +/-200 steps, so:
///   * putting true focus at the centre (25000) would let an algorithm that never
///     moved appear to succeed, and
///   * putting it at the edge (25200, tried first) gives the sweep a monotonic
///     slope instead of a V — the parabola fit then degenerates and autofocus
///     correctly refuses it with "curve fit R² 0.000 is below 0.700".
///
/// 25075 brackets the minimum on both sides while still requiring real movement.
pub const SIM_TRUE_FOCUS: i32 = 25_075;

const SIM_STAR_COUNT: usize = 45;
/// Sharpest achievable star sigma, in pixels.
const SIM_MIN_SIGMA: f64 = 1.6;
/// Sigma growth per focuser step away from [`SIM_TRUE_FOCUS`].
///
/// Sized so the DEFAULT autofocus sweep sees enough HFR spread to satisfy the
/// routine's `MIN_HFR_VARIANCE` V-curve check. At 0.0025 the sweep produced only
/// 0.68 of spread and autofocus correctly refused it ("No valid V-curve
/// detected"), which made the whole routine untestable against the simulator.
const SIM_SIGMA_PER_STEP: f64 = 0.006;
/// Total flux per star, held constant as it defocuses, so a blurred star spreads
/// out rather than merely dimming — that is what gives an autofocus sweep a
/// V-curve instead of a brightness ramp.
const SIM_STAR_FLUX: f64 = 550_000.0;

/// Star sigma (pixels) for a given focuser position.
pub fn sim_star_sigma(focus_position: Option<i32>) -> f64 {
    // A camera-only rig has no focuser to defocus it: treat that as in-focus so
    // plain capture tests still get sharp stars.
    let position = focus_position.unwrap_or(SIM_TRUE_FOCUS);
    let defocus = (position - SIM_TRUE_FOCUS).abs() as f64;
    SIM_MIN_SIGMA + defocus * SIM_SIGMA_PER_STEP
}

/// Build the simulator's synthetic frame with the whole star field translated by
/// `(offset_x, offset_y)` pixels.
///
/// The offset is what makes guiding exercisable without a mount: the simulated
/// mount accumulates guide-pulse and drift displacement (see
/// `api::devices::simulation::sim_guide_offset_px`) and passes it here, so the
/// built-in guider sees its own pulses move the stars. Without it every
/// calibration attempt died on "Calibration response on east axis was too small
/// (0.000px)" — the pulse op returned `Ok` but nothing moved — which made
/// calibration, closed-loop correction and dithering untestable offline.
pub fn synthesize_sim_frame_with_offset(
    focus_position: Option<i32>,
    offset_x: f64,
    offset_y: f64,
) -> Vec<u16> {
    let mut data = vec![0u16; SIM_W * SIM_H];
    for y in 0..SIM_H {
        let row = y * SIM_W;
        for x in 0..SIM_W {
            // Faint gradient (~200..600 ADU): deterministic and never uniform,
            // so it passes the all-identical dead-frame check.
            data[row + x] = 200 + (((x + y) % 400) as u16);
        }
    }

    let sigma = sim_star_sigma(focus_position);
    let two_sigma_sq = 2.0 * sigma * sigma;
    let amplitude = SIM_STAR_FLUX / (std::f64::consts::TAU * sigma * sigma);
    let radius = (3.0 * sigma).ceil() as isize;

    // Fixed-seed LCG: the field is identical run to run, so tests can assert on
    // star counts and HFR without tolerating a reshuffled field.
    let mut seed: u64 = 0x5EED_1234_ABCD_0001;
    let mut next_rand = move || {
        seed = seed
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (seed >> 33) as f64 / (1u64 << 31) as f64
    };

    for _ in 0..SIM_STAR_COUNT {
        // Inset from the edges so every star's full profile fits on the sensor.
        // The mount offset is added AFTER the inset so the field translates as a
        // rigid body: a star near the edge can clip off-sensor under a large
        // offset, exactly as it would on a real drifting mount (the per-pixel
        // bounds check below handles that).
        let margin = radius as f64 + 2.0;
        let cx = margin + next_rand() * (SIM_W as f64 - 2.0 * margin) + offset_x;
        let cy = margin + next_rand() * (SIM_H as f64 - 2.0 * margin) + offset_y;
        // Some brightness spread, so the detector sees a realistic magnitude
        // range rather than 45 identical stars.
        let star_amp = amplitude * (0.45 + 0.55 * next_rand());
        let cxi = cx as isize;
        let cyi = cy as isize;
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                let px = cxi + dx;
                let py = cyi + dy;
                if px < 0 || py < 0 || px >= SIM_W as isize || py >= SIM_H as isize {
                    continue;
                }
                let r_sq = (px as f64 - cx).powi(2) + (py as f64 - cy).powi(2);
                let value = star_amp * (-r_sq / two_sigma_sq).exp();
                if value < 1.0 {
                    continue;
                }
                let idx = py as usize * SIM_W + px as usize;
                // Saturate rather than wrap: a wrapped bright core would read as
                // a black hole in the middle of a star.
                data[idx] = data[idx].saturating_add(value.min(65_535.0) as u16);
            }
        }
    }
    data
}

#[cfg(test)]
mod tests {
    use super::*;
    use nightshade_imaging::{detect_stars_with_stats, ImageData, StarDetectionConfig};

    fn detect(focus_position: Option<i32>) -> (usize, Option<f64>) {
        let buffer = synthesize_sim_frame_with_offset(focus_position, 0.0, 0.0);
        let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
        let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
        let hfrs: Vec<f64> = result.stars.iter().map(|s| s.hfr).collect();
        let median = if hfrs.is_empty() {
            None
        } else {
            let mut sorted = hfrs.clone();
            sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
            Some(sorted[sorted.len() / 2])
        };
        (result.stars.len(), median)
    }

    /// The bar that matters: the DEFAULT detector config, and the 10-star
    /// minimum the autofocus routine enforces.
    #[test]
    fn in_focus_frame_yields_enough_detectable_stars_for_autofocus() {
        let (count, hfr) = detect(Some(SIM_TRUE_FOCUS));
        assert!(
            count >= 10,
            "in-focus simulated frame produced {count} detectable stars; autofocus \
             requires at least 10 and previously failed with 0"
        );
        let hfr = hfr.expect("stars were detected, so an HFR must be measurable");
        assert!(
            hfr.is_finite() && hfr > 0.5 && hfr < 12.0,
            "in-focus HFR {hfr} is not a plausible measurement"
        );
    }

    /// A camera-only rig (no focuser connected) must still get sharp stars.
    #[test]
    fn frame_without_a_focuser_is_in_focus() {
        let (count, _) = detect(None);
        assert!(count >= 10, "no-focuser frame produced only {count} stars");
    }

    /// The V-curve: defocusing must RAISE measured HFR, or an autofocus sweep
    /// has no minimum to find and the whole routine is untestable.
    #[test]
    fn defocus_increases_measured_hfr() {
        let (_, focused) = detect(Some(SIM_TRUE_FOCUS));
        let (_, defocused) = detect(Some(SIM_TRUE_FOCUS + 900));
        let focused = focused.expect("in-focus stars detected");
        let defocused = defocused.expect("defocused stars still detected");
        assert!(
            defocused > focused,
            "defocused HFR {defocused} must exceed in-focus HFR {focused} for an \
             autofocus sweep to converge"
        );
    }

    /// Defocus must be symmetric about true focus, so the sweep sees a genuine
    /// V rather than a monotonic slope it can walk off the end of.
    #[test]
    fn defocus_is_symmetric_about_true_focus() {
        let inside = sim_star_sigma(Some(SIM_TRUE_FOCUS - 800));
        let outside = sim_star_sigma(Some(SIM_TRUE_FOCUS + 800));
        assert!((inside - outside).abs() < 1e-9);
        assert!(inside > sim_star_sigma(Some(SIM_TRUE_FOCUS)));
    }

    /// Centroid of the brightest detected star, for offset assertions.
    fn brightest_centroid(offset_x: f64, offset_y: f64) -> (f64, f64) {
        let buffer = synthesize_sim_frame_with_offset(Some(SIM_TRUE_FOCUS), offset_x, offset_y);
        let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
        let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
        let star = result
            .stars
            .iter()
            .max_by(|a, b| a.flux.partial_cmp(&b.flux).unwrap())
            .expect("stars detected");
        (star.x, star.y)
    }

    /// A guide pulse has to MOVE the field, and move it the way it was asked to.
    /// The built-in guider derives its calibration from exactly this measurement,
    /// and while the simulated pulse was a no-op it always aborted with
    /// "Calibration response on east axis was too small (0.000px)".
    #[test]
    fn offset_translates_the_star_field() {
        let (base_x, base_y) = brightest_centroid(0.0, 0.0);
        let (east_x, east_y) = brightest_centroid(6.0, 0.0);
        assert!(
            (east_x - base_x - 6.0).abs() < 0.5,
            "east offset moved the centroid from {base_x:.2} to {east_x:.2}; expected +6px"
        );
        assert!(
            (east_y - base_y).abs() < 0.5,
            "an x-only offset must not move the centroid in y ({base_y:.2} -> {east_y:.2})"
        );

        let (north_x, north_y) = brightest_centroid(0.0, 6.0);
        assert!(
            (north_y - base_y - 6.0).abs() < 0.5,
            "north offset moved the centroid from {base_y:.2} to {north_y:.2}; expected +6px"
        );
        assert!(
            (north_x - base_x).abs() < 0.5,
            "a y-only offset must not move the centroid in x ({base_x:.2} -> {north_x:.2})"
        );
    }

    /// The offset must not cost the frame its detectability: the guider needs a
    /// star field at every point of a calibration, not just at the origin.
    #[test]
    fn offset_frame_still_yields_detectable_stars() {
        for (dx, dy) in [(0.0, 0.0), (12.0, -8.0), (-60.0, 60.0), (60.0, -60.0)] {
            let buffer = synthesize_sim_frame_with_offset(Some(SIM_TRUE_FOCUS), dx, dy);
            let image = ImageData::from_u16(SIM_W as u32, SIM_H as u32, 1, &buffer);
            let result = detect_stars_with_stats(&image, &StarDetectionConfig::default());
            assert!(
                result.stars.len() >= 10,
                "offset ({dx}, {dy}) left only {} detectable stars; the guider needs a \
                 usable field across its whole excursion range",
                result.stars.len()
            );
        }
    }

    /// A pulse response has to clear the guider's 0.2px "too small" floor while
    /// staying well inside its 20px star-match radius — outside that band
    /// calibration either refuses the response or matches the wrong star.
    #[test]
    fn calibration_pulse_response_is_measurable_and_matchable() {
        // Mirrors the simulated mount's 6 px/sec at the guider's default 250 ms
        // calibration pulse.
        let per_pulse = 6.0 * 0.250;
        assert!(
            per_pulse > 0.2,
            "per-pulse response {per_pulse}px is below the guider's 0.2px floor"
        );
        // Dec calibration issues two forward pulses before measuring.
        assert!(
            per_pulse * 2.0 < 20.0,
            "two-pulse Dec response {}px exceeds the 20px match radius",
            per_pulse * 2.0
        );
        let (base_x, _) = brightest_centroid(0.0, 0.0);
        let (moved_x, _) = brightest_centroid(per_pulse, 0.0);
        assert!(
            (moved_x - base_x) > 0.2,
            "a single calibration pulse shifted the measured centroid only {:.3}px",
            moved_x - base_x
        );
    }

    /// The autofocus routine rejects a sweep whose HFR spread is below its
    /// `MIN_HFR_VARIANCE` (1.0) as "no valid V-curve". The simulated focus
    /// response therefore has to produce more spread than that across the
    /// DEFAULT sweep window, or autofocus is untestable without hardware —
    /// which is exactly how it failed before this was tuned (spread 0.68).
    #[test]
    fn default_sweep_window_spans_enough_hfr_for_a_v_curve() {
        // The focuser starts at 25000 and the default sweep covers about
        // +/-200 steps around it in 50-step increments.
        let positions: Vec<i32> = (24_800..=25_200).step_by(50).collect();
        let hfrs: Vec<f64> = positions
            .iter()
            .map(|p| {
                detect(Some(*p))
                    .1
                    .expect("stars detected at every sweep point")
            })
            .collect();

        let min = hfrs.iter().cloned().fold(f64::INFINITY, f64::min);
        let max = hfrs.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        assert!(
            max - min > 1.0,
            "sweep HFR spread {:.2} (min {:.2}, max {:.2}) must exceed the \
             routine's MIN_HFR_VARIANCE of 1.0",
            max - min,
            min,
            max
        );

        // And the minimum must fall INSIDE the window rather than at an edge, so
        // the parabola fit has points on both sides.
        let argmin = hfrs
            .iter()
            .enumerate()
            .min_by(|a, b| a.1.partial_cmp(b.1).unwrap())
            .map(|(i, _)| i)
            .unwrap();
        assert!(
            argmin > 0 && argmin < hfrs.len() - 1,
            "best focus landed at sweep edge index {argmin} of {}; the fit \
             degenerates to a slope and autofocus refuses it",
            hfrs.len()
        );
    }
}
