use super::*;

// =============================================================================
// Slew-to-pole start mode (start_from_current = false)
// =============================================================================

/// Max wall-clock for the pole-region slew to settle before we abort + fail.
pub(crate) const POLE_SLEW_TIMEOUT_SECS: u64 = 120;
/// Fallback settle wait when the driver cannot report `slewing`.
pub(crate) const POLE_SLEW_SETTLE_SECS: u64 = 8;
/// How far from the true pole the pole-region target sits, in degrees. 30° puts
/// the scope at the outer edge of the classic TPPA region (≈30° around the
/// pole) while keeping the 3-point rotation-arc geometry well conditioned
/// (cos 60° = 0.5 of the RA step projects onto the sky, versus a near-degenerate
/// projection right at the pole).
pub(crate) const POLE_REGION_OFFSET_DEG: f64 = 30.0;

/// Outcome of the pole-region slew preamble.
pub(crate) enum SlewOutcome {
    /// The mount reached and settled on the pole-region target.
    Settled,
    /// The user cancelled during the slew (the mount was aborted).
    Cancelled,
    /// A newer run took over during the slew (the mount was aborted).
    Superseded,
}

/// Compute the "slew to pole region" target `(ra_hours, dec_degrees)`.
///
/// The target sits on the local meridian (RA == LST, i.e. hour angle 0) so it
/// culminates — highest above the horizon, least atmosphere, best for plate
/// solving — and [`POLE_REGION_OFFSET_DEG`] from the celestial pole toward the
/// equator so the subsequent three-point RA arc keeps good geometry. Northern
/// observers point at +Dec, southern at −Dec.
///
/// Pure and deterministic given `(lst_hours, is_north)` so it can be unit
/// tested without hardware.
pub(crate) fn pole_region_target(lst_hours: f64, is_north: bool) -> (f64, f64) {
    let ra_hours = lst_hours.rem_euclid(24.0);
    let dec_degrees = if is_north {
        90.0 - POLE_REGION_OFFSET_DEG
    } else {
        -90.0 + POLE_REGION_OFFSET_DEG
    };
    (ra_hours, dec_degrees)
}

/// Slew the mount to the pole region and wait — with abort ordering — until the
/// motion actually settles.
///
/// Ordering guarantees (adversarially important): a cancellation or supersession
/// observed *while slewing* issues `mount_abort_slew` BEFORE returning, so the
/// mount is commanded to stop before the caller settles/idles. A driver that
/// cannot report `slewing` falls back to a bounded fixed settle rather than
/// spinning. A hard timeout also aborts and fails truthfully — it never reports
/// the slew as done early.
pub(crate) async fn slew_to_pole_region(
    mount_id: &str,
    is_north: bool,
    longitude_deg: f64,
    generation: u64,
) -> Result<SlewOutcome, String> {
    use nightshade_sequencer::meridian::{julian_day, local_sidereal_time};

    let now = chrono::Utc::now();
    let jd = julian_day(&now);
    let lst = local_sidereal_time(jd, longitude_deg);
    let (target_ra_h, target_dec) = pole_region_target(lst, is_north);

    emit_polar_status(
        &format!(
            "Slewing to pole region (RA {:.2}h, Dec {:.0}°)...",
            target_ra_h, target_dec
        ),
        "measuring",
        0,
    );

    let device_ops = create_unified_device_ops();

    // Honour a cancel/supersede that arrives before the slew is even issued.
    match polar_loop_control(generation) {
        PolarLoopControl::Continue => {}
        PolarLoopControl::Superseded => return Ok(SlewOutcome::Superseded),
        PolarLoopControl::Cancelled => return Ok(SlewOutcome::Cancelled),
    }

    device_ops
        .mount_slew_to_coordinates(mount_id, target_ra_h, target_dec)
        .await
        .map_err(|e| format!("Failed to slew to pole region: {}", e))?;

    // Wait for settle. `mount_slew_to_coordinates` may return before the mount
    // physically stops (async drivers), so poll `slewing`.
    let deadline = Instant::now() + Duration::from_secs(POLE_SLEW_TIMEOUT_SECS);
    loop {
        match polar_loop_control(generation) {
            PolarLoopControl::Continue => {}
            PolarLoopControl::Superseded => {
                let _ = device_ops.mount_abort_slew(mount_id).await;
                return Ok(SlewOutcome::Superseded);
            }
            PolarLoopControl::Cancelled => {
                let _ = device_ops.mount_abort_slew(mount_id).await;
                return Ok(SlewOutcome::Cancelled);
            }
        }

        match device_ops.mount_is_slewing(mount_id).await {
            Ok(false) => break, // settled
            Ok(true) => {}      // keep waiting
            Err(e) => {
                // Driver can't report slew state — do a bounded fixed settle
                // rather than busy-looping forever, then proceed.
                tracing::warn!(
                    "mount_is_slewing failed ({}); using {}s fixed settle",
                    e,
                    POLE_SLEW_SETTLE_SECS
                );
                tokio::time::sleep(Duration::from_secs(POLE_SLEW_SETTLE_SECS)).await;
                break;
            }
        }

        if Instant::now() >= deadline {
            let _ = device_ops.mount_abort_slew(mount_id).await;
            return Err(format!(
                "Timed out after {}s waiting for the mount to reach the pole region",
                POLE_SLEW_TIMEOUT_SECS
            ));
        }

        tokio::time::sleep(Duration::from_millis(500)).await;
    }

    // Short mechanical settle after motion stops before the first exposure.
    tokio::time::sleep(Duration::from_secs(1)).await;
    Ok(SlewOutcome::Settled)
}
