//! The 2026-09-09 rig sweep, replayed through the shipped fitter.
use nightshade_sequencer::autofocus::{
    AutofocusConfig, AutofocusMethod, FocusDataPoint, VCurveAutofocus,
};

fn pt(position: i32, hfr: f64) -> FocusDataPoint {
    FocusDataPoint {
        position,
        hfr,
        fwhm: None,
        star_count: 10,
    }
}

fn rig_sweep() -> Vec<FocusDataPoint> {
    vec![
        pt(2275, 7.69),
        pt(2350, 7.20),
        pt(2425, 4.47),
        pt(2500, 2.69),
        pt(2575, 5.70),
        pt(2650, 9.46),
        pt(2725, 14.14),
        pt(2800, 14.75),
        pt(2875, 14.43),
    ]
}

fn run(method: AutofocusMethod, points: Vec<FocusDataPoint>) -> (i32, f64) {
    let af = VCurveAutofocus::new(AutofocusConfig {
        method,
        step_size: 75,
        steps_out: 4,
        ..Default::default()
    });
    let r = af.find_best_focus(points).expect("fit");
    (r.best_position, r.curve_fit_quality)
}

#[test]
fn rig_sweep_lands_near_the_focus_the_operator_had_to_nudge_to() {
    // Ground truth, from the rig: the best sample was 2500 and a parabola
    // through its two neighbours puts the vertex at 2490. The operator landed
    // real focus at encoder 2441 — reached moving DOWN, so with that focuser's
    // ~50 steps of backlash the optics were at ~2490 in this sweep's
    // (approached-from-below) frame. The sweep chose 2471.
    for method in [
        AutofocusMethod::Hyperbolic,
        AutofocusMethod::VCurve,
        AutofocusMethod::Quadratic,
    ] {
        let (position, quality) = run(method, rig_sweep());
        println!("{:?} -> {} (R²={:.3})", method, position, quality);
        assert!(
            (2480..=2510).contains(&position),
            "{:?} put best focus at {}, outside the 2480-2510 the usable samples support",
            method,
            position
        );
        assert!(quality > 0.94, "{:?} fit quality {:.3}", method, quality);
    }
}

#[test]
fn a_clean_symmetric_sweep_is_left_alone() {
    // Nothing to narrow: a well-behaved V-curve must fit over every point it
    // sampled, or the rule is reshaping good data.
    let clean: Vec<_> = (-4..=4)
        .map(|k: i32| {
            let position = 5000 + k * 100;
            let hfr = 2.0 + 0.04 * (k * 100).abs() as f64;
            pt(position, hfr)
        })
        .collect();

    for method in [AutofocusMethod::VCurve, AutofocusMethod::Quadratic] {
        let (position, quality) = run(method, clean.clone());
        println!("clean {:?} -> {} (R²={:.3})", method, position, quality);
        assert!(
            (4980..=5020).contains(&position),
            "{:?} moved the vertex of a clean sweep to {}",
            method,
            position
        );
        assert!(quality > 0.9);
    }
}
