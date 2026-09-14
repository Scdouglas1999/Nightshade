use super::*;

// How a polar-alignment frame is plate solved.
//
// Every frame in this feature is taken within ~30° of the celestial pole with
// the mount pointing where the mount says it points. That is a position hint,
// and it is the difference between an ASTAP run that searches one cone of sky
// and one that searches all of it: on the owner's rig a hinted capture solves
// in ~5 s while the same field solved blind took 26.5 s on a good night and
// blew through a 30 s budget on a bad one. The pointing model is unaligned
// during polar alignment — that is the whole point of running it — so the hint
// carries a deliberately generous search radius instead of the 5° a
// centring solve uses, and a hinted attempt that fails still falls back to the
// blind solve that used to be the only path.

/// Search radius for a polar-alignment hinted solve, in degrees.
///
/// The measurement points sit [`POLE_REGION_OFFSET_DEG`] from the pole, so a
/// radius of the same size covers the entire pole region the run can be
/// pointing at even if the mount's idea of its own position is wrong by the
/// full width of that region. A polar-aligned-by-eyeball mount is typically
/// off by a degree or two; this absorbs an unsynced one.
pub(crate) const POLAR_SOLVE_SEARCH_RADIUS_DEG: f64 = POLE_REGION_OFFSET_DEG;

/// Largest `-r` ASTAP accepts: half the sky, measured from the hint, is every
/// direction there is. Anything beyond it is a blind solve wearing a hint.
pub(crate) const ASTAP_MAX_SEARCH_RADIUS_DEG: f64 = 180.0;

/// Per-frame solve budget when the caller does not specify one.
///
/// 30 s was the old default and it failed on the owner's laptop against a
/// full-resolution blind solve. 90 s covers a hinted attempt, a blind
/// fallback, and the margin ASTAP needs to report its own timeout.
pub(crate) const DEFAULT_POLAR_SOLVE_TIMEOUT_SECS: f64 = 90.0;

/// Smallest budget a caller may configure. Below this neither attempt can
/// finish and the run only produces timeouts.
const MIN_POLAR_SOLVE_TIMEOUT_SECS: f64 = 5.0;

/// Share of the frame budget the hinted attempt may spend before the blind
/// fallback gets the rest. A hinted solve succeeds in seconds or not at all,
/// so half the budget is already far more than it needs — and leaving the
/// other half means a hinted attempt that fails never costs the run its
/// fallback.
const HINTED_BUDGET_FRACTION: f64 = 0.5;

/// Floor under the hinted attempt's share, so a short configured budget still
/// gives the fast path a fair chance.
const MIN_HINTED_ATTEMPT_SECS: f64 = 15.0;

/// Below this there is no point starting a blind solve: it cannot finish, and
/// the frame is better reported as failed than spent waiting.
const MIN_BLIND_FALLBACK_SECS: f64 = 10.0;

/// How far the async watchdog sits beyond the solver's own process timeout.
///
/// ASTAP is killed by its own process runner at the attempt budget, which
/// returns a truthful "ASTAP timed out after N seconds" and releases the
/// solver gate immediately. This watchdog exists only for a solve that wedges
/// somewhere other than the child process, so it must fire strictly later —
/// tonight both fired at 30 s and the run reported the two as separate
/// failures of the same frame.
const SOLVE_WATCHDOG_MARGIN_SECS: f64 = 5.0;

/// Frames wider than this on their long side are downsampled for the solve.
///
/// ASTAP needs stars, not pixels. A 4656 x 3520 frame carries several times
/// the stars a solve uses, and halving each axis quarters the pixels ASTAP has
/// to search through.
const POLAR_DOWNSAMPLE_LONG_SIDE_PX: u32 = 3000;

/// The ASTAP `-z` factor meaning "read the frame as it is".
const NO_DOWNSAMPLE: u32 = 1;

/// The mount's own idea of where it is pointing, ready to hand to a solver.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct PolarSolveHint {
    /// Degrees, `[0, 360)` — the unit `plate_solve_near_scaled` takes.
    pub(crate) ra_degrees: f64,
    /// Degrees, `[-90, 90]`.
    pub(crate) dec_degrees: f64,
    /// Degrees.
    pub(crate) search_radius_deg: f64,
}

/// Build a solve hint from a mount status report.
///
/// `ra_hours` is the unit [`MountStatus::right_ascension`] is in; the solver
/// wants degrees. Returns `None` for a report that cannot be a position — a
/// NaN from a driver that failed to read the axis, or a declination outside
/// the sphere — because a confidently wrong hint costs more than no hint: it
/// sends ASTAP to search a cone the field is not in, and only then falls back.
pub(crate) fn polar_solve_hint_from_mount(
    ra_hours: f64,
    dec_degrees: f64,
) -> Option<PolarSolveHint> {
    if !ra_hours.is_finite() || !dec_degrees.is_finite() {
        return None;
    }
    if !(-90.0..=90.0).contains(&dec_degrees) {
        return None;
    }
    Some(PolarSolveHint {
        ra_degrees: (ra_hours.rem_euclid(24.0)) * 15.0,
        dec_degrees,
        search_radius_deg: POLAR_SOLVE_SEARCH_RADIUS_DEG.clamp(0.0, ASTAP_MAX_SEARCH_RADIUS_DEG),
    })
}

/// Read the mount's position for a solve hint, or `None` when it cannot say.
///
/// A driver that cannot report a position is not an error for the run: polar
/// alignment solved blind before this existed and still does whenever the
/// answer is `None`.
pub(crate) async fn read_polar_solve_hint(mount_id: &str) -> Option<PolarSolveHint> {
    match get_device_manager().mount_get_status(mount_id).await {
        Ok(status) => {
            let hint = polar_solve_hint_from_mount(status.right_ascension, status.declination);
            if hint.is_none() {
                tracing::warn!(
                    "Polar alignment: mount reported an unusable position \
                     (RA {:?} h, Dec {:?}°); solving blind",
                    status.right_ascension,
                    status.declination
                );
            }
            hint
        }
        Err(e) => {
            tracing::warn!(
                "Polar alignment: could not read the mount position for a solve hint ({}); \
                 solving blind",
                e
            );
            None
        }
    }
}

/// The ASTAP `-z` downsample factor for a polar-alignment frame.
///
/// Binning and downsampling compound: a 4x4 frame halved again is a sixteenth
/// of the sensor in each axis, which throws away the faint stars the solve
/// depends on. So a frame that was already binned in hardware is solved as it
/// is, and only an unbinned oversized frame is downsampled.
///
/// This does not touch the scale hint. ASTAP's `-fov` is the angular height of
/// the field, and the field is the same field however many pixels ASTAP reads
/// it at — see `build_astap_args`, which derives `-fov` from the frame's own
/// NAXIS2 and never consults the downsample factor.
pub(crate) fn polar_solve_downsample(width_px: u32, height_px: u32, binning: i32) -> u32 {
    if binning >= 2 {
        return NO_DOWNSAMPLE;
    }
    if width_px.max(height_px) > POLAR_DOWNSAMPLE_LONG_SIDE_PX {
        2
    } else {
        NO_DOWNSAMPLE
    }
}

/// How one frame's solve budget is split between the hinted attempt and the
/// blind fallback. Seconds; `0.0` means "do not attempt".
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct PolarSolveBudget {
    pub(crate) hinted_secs: f64,
    pub(crate) blind_secs: f64,
}

/// Split a frame's solve budget so both attempts fit inside it.
///
/// The operator configured a per-frame timeout and that is what the frame is
/// allowed to take — a hinted attempt followed by a full-length blind one
/// would silently double it, and three points would run six times the
/// configured budget before the run failed.
pub(crate) fn split_polar_solve_budget(total_secs: f64, has_hint: bool) -> PolarSolveBudget {
    let total = if total_secs.is_finite() {
        total_secs.clamp(
            MIN_POLAR_SOLVE_TIMEOUT_SECS,
            f64::from(u16::MAX), // far beyond any real solve; keeps the cast below sane
        )
    } else {
        DEFAULT_POLAR_SOLVE_TIMEOUT_SECS
    };

    if !has_hint {
        return PolarSolveBudget {
            hinted_secs: 0.0,
            blind_secs: total,
        };
    }

    let hinted = (total * HINTED_BUDGET_FRACTION)
        .max(MIN_HINTED_ATTEMPT_SECS)
        .min(total);
    let remaining = total - hinted;
    PolarSolveBudget {
        hinted_secs: hinted,
        // A fallback that cannot finish is worse than none: it spends the
        // operator's night to arrive at the same failure.
        blind_secs: if remaining >= MIN_BLIND_FALLBACK_SECS {
            remaining
        } else {
            0.0
        },
    }
}

/// The process timeout ASTAP itself is given for one attempt.
///
/// It is the attempt's whole budget, so the solver — not an async watchdog
/// racing it — is what decides the attempt is over, kills the child and says
/// so. The watchdog is [`SOLVE_WATCHDOG_MARGIN_SECS`] later.
pub(crate) fn astap_process_timeout_secs(attempt_secs: f64) -> u32 {
    attempt_secs.ceil().clamp(1.0, 3600.0) as u32
}

/// Which attempt produced a solution.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PolarSolvePath {
    Hinted,
    Blind,
}

impl PolarSolvePath {
    fn label(self) -> &'static str {
        match self {
            Self::Hinted => "hinted",
            Self::Blind => "blind",
        }
    }
}

/// Plate solve one polar-alignment frame: hinted first, blind as the fallback.
///
/// `what` names the frame for the operator ("point 1", "the adjustment
/// frame"). `scale_arcsec_px` is the measured plate scale of the frame as
/// taken. The returned error text is what the operator sees, and it names the
/// attempts that were actually made rather than implying only one was.
pub(crate) async fn solve_polar_frame(
    what: &str,
    file_path: &str,
    hint: Option<PolarSolveHint>,
    scale_arcsec_px: Option<f64>,
    downsample: u32,
    timeout_secs: f64,
) -> Result<crate::api::plate_solve::PlateSolveResult, String> {
    let budget = split_polar_solve_budget(timeout_secs, hint.is_some());

    let mut hinted_failure: Option<String> = None;
    if let (Some(hint), true) = (hint, budget.hinted_secs > 0.0) {
        tracing::info!(
            "Polar alignment {}: hinted solve at mount RA {:.4}°, Dec {:.4}° \
             (search radius {:.0}°, -z {}, {:.0}s)",
            what,
            hint.ra_degrees,
            hint.dec_degrees,
            hint.search_radius_deg,
            downsample,
            budget.hinted_secs
        );
        let attempt = run_polar_solve_attempt(
            PolarSolvePath::Hinted,
            file_path,
            Some(hint),
            scale_arcsec_px,
            downsample,
            budget.hinted_secs,
        )
        .await;
        match attempt {
            Ok(result) if result.success => {
                tracing::info!(
                    "Polar alignment {}: solved by the HINTED path in {:.1}s",
                    what,
                    result.solve_time_secs
                );
                return Ok(result);
            }
            Ok(result) => {
                hinted_failure = Some(
                    result
                        .error
                        .unwrap_or_else(|| "no solution found".to_string()),
                )
            }
            Err(e) => hinted_failure = Some(e),
        }

        let reason = hinted_failure.as_deref().unwrap_or("unknown");
        if budget.blind_secs > 0.0 {
            tracing::warn!(
                "Polar alignment {}: the hinted solve failed ({}); falling back to a \
                 blind solve with the remaining {:.0}s",
                what,
                reason,
                budget.blind_secs
            );
        } else {
            return Err(format!(
                "Plate solve failed for {} after a hinted attempt of {:.0}s ({}). \
                 The remaining budget was too short for a blind retry — raise the \
                 solve timeout.",
                what, budget.hinted_secs, reason
            ));
        }
    }

    let attempt = run_polar_solve_attempt(
        PolarSolvePath::Blind,
        file_path,
        None,
        scale_arcsec_px,
        downsample,
        budget.blind_secs,
    )
    .await;

    match attempt {
        Ok(result) if result.success => {
            tracing::info!(
                "Polar alignment {}: solved by the BLIND path in {:.1}s",
                what,
                result.solve_time_secs
            );
            Ok(result)
        }
        Ok(result) => Err(format_polar_solve_failure(
            what,
            hinted_failure.as_deref(),
            &result
                .error
                .unwrap_or_else(|| "no solution found".to_string()),
        )),
        Err(e) => Err(format_polar_solve_failure(
            what,
            hinted_failure.as_deref(),
            &e,
        )),
    }
}

/// One solver invocation, guarded by a watchdog that fires strictly after the
/// solver's own process timeout.
async fn run_polar_solve_attempt(
    path: PolarSolvePath,
    file_path: &str,
    hint: Option<PolarSolveHint>,
    scale_arcsec_px: Option<f64>,
    downsample: u32,
    attempt_secs: f64,
) -> Result<crate::api::plate_solve::PlateSolveResult, String> {
    let process_timeout = astap_process_timeout_secs(attempt_secs);
    let owned_path = file_path.to_string();
    let solve = async move {
        match hint {
            Some(hint) => {
                crate::api::plate_solve::plate_solve_near_scaled(
                    owned_path,
                    hint.ra_degrees,
                    hint.dec_degrees,
                    hint.search_radius_deg,
                    Some(process_timeout),
                    scale_arcsec_px,
                    Some(downsample),
                )
                .await
            }
            None => {
                crate::api::plate_solve::plate_solve_blind_scaled(
                    owned_path,
                    Some(process_timeout),
                    scale_arcsec_px,
                    Some(downsample),
                )
                .await
            }
        }
    };

    let watchdog = Duration::from_secs_f64(attempt_secs + SOLVE_WATCHDOG_MARGIN_SECS);
    match tokio::time::timeout(watchdog, solve).await {
        Ok(Ok(result)) => Ok(result),
        Ok(Err(e)) => Err(format!("{:?}", e)),
        Err(_) => Err(format!(
            "the {} solve did not return within {:.0}s",
            path.label(),
            watchdog.as_secs_f64()
        )),
    }
}

/// Operator-facing failure text that names every attempt that was made.
fn format_polar_solve_failure(what: &str, hinted: Option<&str>, blind: &str) -> String {
    match hinted {
        Some(hinted) => format!(
            "Plate solve failed for {}: the hinted solve failed ({}) and the blind \
             fallback failed ({})",
            what, hinted, blind
        ),
        None => format!("Plate solve failed for {}: {}", what, blind),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_mount_report_becomes_a_degrees_hint() {
        let hint = polar_solve_hint_from_mount(2.0, 58.27).expect("a finite report is a hint");
        assert!(
            (hint.ra_degrees - 30.0).abs() < 1e-9,
            "hours must become degrees"
        );
        assert!((hint.dec_degrees - 58.27).abs() < 1e-9);
    }

    /// A mount that has wrapped past 24 h (or reports a negative hour angle as
    /// RA) still names a real place in the sky.
    #[test]
    fn a_wrapped_right_ascension_folds_into_the_circle() {
        let hint = polar_solve_hint_from_mount(25.0, 0.0).expect("hint");
        assert!((hint.ra_degrees - 15.0).abs() < 1e-9);
        let hint = polar_solve_hint_from_mount(-1.0, 0.0).expect("hint");
        assert!((hint.ra_degrees - 345.0).abs() < 1e-9);
    }

    /// The radius is generous because the pointing model is unaligned — that
    /// is what the run is measuring — but it is never sent past what ASTAP
    /// accepts.
    #[test]
    fn the_search_radius_covers_the_pole_region_and_is_clamped() {
        let hint = polar_solve_hint_from_mount(6.0, 60.0).expect("hint");
        assert!(
            hint.search_radius_deg >= POLE_REGION_OFFSET_DEG,
            "the points sit {}° from the pole; a smaller radius can miss them",
            POLE_REGION_OFFSET_DEG
        );
        assert!(hint.search_radius_deg <= ASTAP_MAX_SEARCH_RADIUS_DEG);
    }

    /// A driver that cannot read its axes hands back NaN or nonsense. Blind is
    /// the honest answer; a fabricated hint sends ASTAP to the wrong cone.
    #[test]
    fn an_unusable_mount_report_produces_no_hint() {
        assert!(polar_solve_hint_from_mount(f64::NAN, 45.0).is_none());
        assert!(polar_solve_hint_from_mount(3.0, f64::NAN).is_none());
        assert!(polar_solve_hint_from_mount(3.0, 91.0).is_none());
        assert!(polar_solve_hint_from_mount(3.0, -91.0).is_none());
    }

    /// Tonight's frame: 4656 x 3520 unbinned.
    #[test]
    fn a_large_unbinned_frame_is_downsampled() {
        assert_eq!(polar_solve_downsample(4656, 3520, 1), 2);
    }

    /// Binning already threw away three quarters of the pixels; doing it again
    /// costs stars the solve needs.
    #[test]
    fn an_already_binned_frame_is_never_downsampled_again() {
        assert_eq!(polar_solve_downsample(4656, 3520, 2), NO_DOWNSAMPLE);
        assert_eq!(polar_solve_downsample(2328, 1760, 2), NO_DOWNSAMPLE);
        assert_eq!(polar_solve_downsample(1164, 880, 4), NO_DOWNSAMPLE);
    }

    /// A small sensor has no pixels to spare.
    #[test]
    fn a_small_unbinned_frame_is_left_alone() {
        assert_eq!(polar_solve_downsample(3000, 2000, 1), NO_DOWNSAMPLE);
        assert_eq!(polar_solve_downsample(1936, 1096, 1), NO_DOWNSAMPLE);
    }

    /// The two attempts together may not outrun the configured per-frame
    /// timeout.
    #[test]
    fn both_attempts_fit_inside_the_configured_budget() {
        let budget = split_polar_solve_budget(DEFAULT_POLAR_SOLVE_TIMEOUT_SECS, true);
        assert!(budget.hinted_secs > 0.0 && budget.blind_secs > 0.0);
        assert!(
            budget.hinted_secs + budget.blind_secs <= DEFAULT_POLAR_SOLVE_TIMEOUT_SECS + 1e-9,
            "{budget:?} outruns the operator's timeout"
        );
        assert!(
            budget.blind_secs >= 30.0,
            "the blind fallback must still beat the 26.5s a blind solve took on the rig: {budget:?}"
        );
    }

    /// With no hint the blind solve is the only attempt, so it gets everything.
    #[test]
    fn a_frame_with_no_hint_spends_the_whole_budget_solving_blind() {
        let budget = split_polar_solve_budget(90.0, false);
        assert_eq!(budget.hinted_secs, 0.0);
        assert_eq!(budget.blind_secs, 90.0);
    }

    /// A short configured budget still gives the fast path its floor, and
    /// refuses to start a blind solve that cannot finish in what is left.
    #[test]
    fn a_short_budget_keeps_the_hinted_floor_and_drops_a_hopeless_fallback() {
        let budget = split_polar_solve_budget(20.0, true);
        assert_eq!(budget.hinted_secs, MIN_HINTED_ATTEMPT_SECS);
        assert_eq!(budget.blind_secs, 0.0);
    }

    /// A nonsense timeout from the wire cannot produce a zero- or
    /// negative-length attempt.
    #[test]
    fn an_impossible_timeout_is_clamped_rather_than_obeyed() {
        let budget = split_polar_solve_budget(0.0, true);
        assert!(budget.hinted_secs >= MIN_POLAR_SOLVE_TIMEOUT_SECS);
        let budget = split_polar_solve_budget(f64::NAN, false);
        assert_eq!(budget.blind_secs, DEFAULT_POLAR_SOLVE_TIMEOUT_SECS);
    }

    /// ASTAP owns the deadline: it is handed the attempt's whole budget, so it
    /// reports its own timeout and releases the solver gate instead of being
    /// killed by a watchdog that fired at the same instant.
    #[test]
    fn astap_gets_the_whole_attempt_and_the_watchdog_sits_behind_it() {
        let budget = split_polar_solve_budget(DEFAULT_POLAR_SOLVE_TIMEOUT_SECS, false);
        let process = astap_process_timeout_secs(budget.blind_secs);
        assert_eq!(process, 90);
        assert!(
            f64::from(process) >= budget.blind_secs,
            "ASTAP must not be killed before the frame gives up"
        );
        assert!(
            budget.blind_secs + SOLVE_WATCHDOG_MARGIN_SECS > f64::from(process),
            "the watchdog must fire after ASTAP's own timeout, not with it"
        );
    }
}
