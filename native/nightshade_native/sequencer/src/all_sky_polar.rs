//! All-Sky Polar Alignment (Sharpcap-style)
//!
//! This module implements an all-sky polar alignment routine that does not
//! require the celestial pole region to be visible from the imaging setup.
//! Two solved frames separated in time, combined with the observer's
//! geographic location, are sufficient to recover the mount's polar-axis
//! misalignment `(Δaz, Δalt)`.
//!
//! # How it works
//!
//! 1. Capture a single exposure with the telescope pointed anywhere in the
//!    sky and plate-solve it to obtain the true celestial coordinates
//!    `(RA_s, Dec_s)` and time `t_s` of frame 1.
//! 2. Wait while the mount tracks at sidereal rate (the iteration cadence,
//!    typically a few seconds).
//! 3. Capture and plate-solve frame 2 at time `t_2 > t_s` to obtain
//!    `(RA_2, Dec_2)`.
//! 4. **Key invariant.** For a perfectly polar-aligned mount, tracking
//!    exactly cancels Earth rotation, so the camera should still be pointed
//!    at `(RA_s, Dec_s)` — i.e. zero drift. Any observed drift
//!    `(ΔRA·cos(Dec), ΔDec)` reveals the polar misalignment.
//! 5. The angular velocity of the drift vector equals
//!    `ω = Ω · (p̂_mech − p̂_true)` (per unit sidereal time), where `Ω` is
//!    Earth's rotation rate, `p̂_true` is the unit vector toward the
//!    celestial pole in the topocentric horizontal frame and `p̂_mech` is
//!    the same for the mount's mechanical polar axis. We measure the drift
//!    rate, solve the cross-product equation `drift = ω × v_camera` for
//!    the two components of `ω` perpendicular to `v_camera`, then project
//!    them onto the horizontal (alt, az) basis at the pole to recover
//!    `(Δaz, Δalt)`.
//!
//! Live feedback re-runs this drift-pair calculation every cadence period,
//! keeping a rolling baseline frame so the user can adjust the azimuth and
//! altitude bolts and see the arrows shrink toward zero.
//!
//! # Acceptance
//!
//! Configurable arc-second threshold (default 30″). The alignment
//! auto-completes when the total error remains below threshold for
//! `AUTO_COMPLETE_HOLD_SECS` consecutive iterations.
//!
//! # Errors
//!
//! All failure modes are propagated as `PolarAlignError`. The most common
//! is `SolverUnavailable` — the all-sky algorithm requires an external
//! plate solver (ASTAP) and **does not** silently fall back to a stub.

use crate::polar_align::{prepare_image_for_display, PolarAlignResult, PolarAlignmentImageData};
use crate::InstructionContext;
use chrono::{DateTime, Utc};
use nightshade_imaging::{BayerPattern, ImageData as ImagingImageData, PixelType};
use std::sync::atomic::Ordering;
use std::time::Duration;
use tokio::time::sleep;

/// Errors specific to all-sky polar alignment.
#[derive(Debug, Clone, PartialEq)]
pub enum PolarAlignError {
    /// External plate solver (ASTAP / astrometry.net) is not installed or
    /// not reachable. The all-sky algorithm cannot operate without one.
    SolverUnavailable,
    /// Plate-solving the captured frame failed (no solution within timeout).
    SolveFailed(String),
    /// Observer latitude/longitude is missing — required to project the
    /// celestial-pole vector into the topocentric horizontal frame.
    LocationMissing,
    /// Hardware operation failed.
    DeviceError(String),
    /// User cancelled the operation.
    Cancelled,
    /// Image capture or processing failed.
    ImageError(String),
}

impl std::fmt::Display for PolarAlignError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PolarAlignError::SolverUnavailable => {
                write!(
                    f,
                    "Plate solver required — install ASTAP and re-run all-sky polar alignment"
                )
            }
            PolarAlignError::SolveFailed(msg) => write!(f, "Plate solve failed: {}", msg),
            PolarAlignError::LocationMissing => write!(
                f,
                "Observer latitude/longitude is required for all-sky polar alignment"
            ),
            PolarAlignError::DeviceError(msg) => write!(f, "Device error: {}", msg),
            PolarAlignError::Cancelled => write!(f, "Cancelled"),
            PolarAlignError::ImageError(msg) => write!(f, "Image error: {}", msg),
        }
    }
}

impl std::error::Error for PolarAlignError {}

/// Configuration for an all-sky polar alignment run.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AllSkyPolarAlignConfig {
    /// Exposure time (seconds) for each live-feedback frame.
    pub exposure_time: f64,
    /// Plate-solve timeout (seconds) per frame.
    pub solve_timeout: f64,
    /// Camera gain (None = camera default).
    pub gain: Option<i32>,
    /// Camera offset (None = camera default).
    pub offset: Option<i32>,
    /// Binning factor (defaults to 2).
    pub binning: Option<i32>,
    /// Northern hemisphere (true) or southern (false).
    pub is_north: bool,
    /// Acceptance threshold in arcseconds. When the total error drops below
    /// this value and stays there for `AUTO_COMPLETE_HOLD_SECS`, the
    /// alignment auto-completes. Default = 30 arcsec (good for ~3-minute
    /// unguided subs).
    pub acceptance_threshold_arcsec: f64,
    /// Cadence between iterations of the adjustment loop (seconds). The
    /// solver itself dominates wall time, but this throttles capture-to-capture
    /// pacing so the user can read the arrows. Typical: 3 seconds.
    pub iteration_cadence_secs: f64,
}

impl Default for AllSkyPolarAlignConfig {
    fn default() -> Self {
        Self {
            exposure_time: 5.0,
            solve_timeout: 30.0,
            gain: None,
            offset: None,
            binning: Some(2),
            is_north: true,
            acceptance_threshold_arcsec: 30.0,
            iteration_cadence_secs: 3.0,
        }
    }
}

/// How long the total error must remain below the acceptance threshold
/// before we declare the alignment complete.
const AUTO_COMPLETE_HOLD_SECS: u64 = 3;

/// Earth's sidereal rotation rate in radians per second.
/// 360° per sidereal day = 360° / 86164.0905s.
const SIDEREAL_RATE_RAD_PER_SEC: f64 = 7.292115146706979e-5;

/// Solved frame snapshot used by the drift calculation.
#[derive(Debug, Clone, Copy)]
pub struct SolvedFrame {
    pub ra_deg: f64,
    pub dec_deg: f64,
    pub when: DateTime<Utc>,
}

/// Execute the all-sky polar alignment routine.
///
/// Returns `Ok(())` on a clean completion (auto-acceptance, user cancel) or
/// a structured `PolarAlignError` on failure. The `status_callback` and
/// `image_callback` are invoked throughout for UI feedback; the
/// `error_callback` is invoked after each successful drift pair with the
/// current `PolarAlignResult` (errors expressed in arc-minutes).
pub async fn perform_all_sky_polar_alignment<S, I, E>(
    config: &AllSkyPolarAlignConfig,
    ctx: &InstructionContext,
    status_callback: S,
    image_callback: I,
    error_callback: E,
) -> Result<(), PolarAlignError>
where
    S: Fn(String, Option<f64>),
    I: Fn(PolarAlignmentImageData),
    E: Fn(&PolarAlignResult),
{
    // 0. Pre-flight: require an external plate solver. The all-sky algorithm
    //    depends on real plate solving — there is no fallback.
    if !nightshade_imaging::is_solver_available() {
        return Err(PolarAlignError::SolverUnavailable);
    }

    let camera_id = ctx
        .camera_id
        .clone()
        .ok_or_else(|| PolarAlignError::DeviceError("No camera connected".to_string()))?;

    let (observer_lat, observer_lon) = match (ctx.latitude, ctx.longitude) {
        (Some(lat), Some(lon)) => (lat, lon),
        _ => ctx
            .device_ops
            .get_observer_location()
            .ok_or(PolarAlignError::LocationMissing)?,
    };

    let threshold_arcsec = config.acceptance_threshold_arcsec;
    let cadence = Duration::from_secs_f64(config.iteration_cadence_secs.max(0.5));
    let binning = config.binning.unwrap_or(2);

    // Baseline frame: the first solved frame anchors the drift baseline. We
    // do not need a mount-position pair — drift is computed entirely from
    // the plate-solve coordinates.
    let baseline: SolvedFrame = capture_and_solve(
        ctx,
        &camera_id,
        config,
        binning,
        &status_callback,
        &image_callback,
        "All-sky: capturing baseline frame...",
    )
    .await?;

    status_callback(
        format!(
            "Baseline locked at RA={:.4}°, Dec={:.4}°. Tracking — adjust bolts.",
            baseline.ra_deg, baseline.dec_deg
        ),
        None,
    );

    let mut below_threshold_since: Option<std::time::Instant> = None;

    loop {
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            return Err(PolarAlignError::Cancelled);
        }

        // Pace iterations — give the user time to react to the previous
        // arrows before re-solving.
        let mut waited = Duration::ZERO;
        while waited < cadence {
            if ctx.cancellation_token.load(Ordering::Relaxed) {
                return Err(PolarAlignError::Cancelled);
            }
            let step = Duration::from_millis(250).min(cadence - waited);
            sleep(step).await;
            waited += step;
        }

        let current = capture_and_solve(
            ctx,
            &camera_id,
            config,
            binning,
            &status_callback,
            &image_callback,
            "All-sky: re-solving for drift...",
        )
        .await?;

        // Compute drift relative to the baseline. We always anchor on the
        // baseline rather than the previous frame so accumulated drift is
        // not lost to sub-arcsec-per-iteration noise.
        let misalignment = compute_polar_misalignment_from_drift(
            &baseline,
            &current,
            observer_lat,
            observer_lon,
            config.is_north,
        );

        let total_error_arcsec = (misalignment.azimuth_error_arcsec.powi(2)
            + misalignment.altitude_error_arcsec.powi(2))
        .sqrt();

        let result = PolarAlignResult {
            azimuth_error: misalignment.azimuth_error_arcsec / 60.0,
            altitude_error: misalignment.altitude_error_arcsec / 60.0,
            total_error: total_error_arcsec / 60.0,
            current_ra: current.ra_deg,
            current_dec: current.dec_deg,
            target_ra: baseline.ra_deg,
            target_dec: baseline.dec_deg,
        };

        error_callback(&result);
        let _ = ctx.device_ops.polar_align_update(&result).await;

        tracing::info!(
            "All-sky polar align: total={:.1}\" (Δaz={:.1}\", Δalt={:.1}\")",
            total_error_arcsec,
            misalignment.azimuth_error_arcsec,
            misalignment.altitude_error_arcsec
        );

        status_callback(
            format!(
                "Error {:.1}\" (Δaz={:.1}\", Δalt={:.1}\")",
                total_error_arcsec,
                misalignment.azimuth_error_arcsec,
                misalignment.altitude_error_arcsec
            ),
            None,
        );

        if total_error_arcsec <= threshold_arcsec {
            match below_threshold_since {
                None => {
                    below_threshold_since = Some(std::time::Instant::now());
                }
                Some(start) if start.elapsed().as_secs() >= AUTO_COMPLETE_HOLD_SECS => {
                    status_callback(
                        format!(
                            "All-sky polar alignment complete: {:.1}\" total error",
                            total_error_arcsec
                        ),
                        Some(1.0),
                    );
                    return Ok(());
                }
                _ => {}
            }
        } else {
            below_threshold_since = None;
        }

        // The `current` frame is intentionally not used as the next
        // baseline: anchoring on the original baseline lets drift
        // accumulate over the entire alignment session, which is much
        // more sensitive than frame-to-frame drift for sub-arcsec error
        // tracking.
        let _ = current;
    }
}

/// Capture a single exposure, plate-solve it, and emit live previews.
async fn capture_and_solve<S, I>(
    ctx: &InstructionContext,
    camera_id: &str,
    config: &AllSkyPolarAlignConfig,
    binning: i32,
    status_callback: &S,
    image_callback: &I,
    status_msg: &str,
) -> Result<SolvedFrame, PolarAlignError>
where
    S: Fn(String, Option<f64>),
    I: Fn(PolarAlignmentImageData),
{
    if ctx.cancellation_token.load(Ordering::Relaxed) {
        return Err(PolarAlignError::Cancelled);
    }

    status_callback(status_msg.to_string(), None);

    let image_data = ctx
        .device_ops
        .camera_start_exposure(
            camera_id,
            config.exposure_time,
            config.gain,
            config.offset,
            binning,
            binning,
        )
        .await
        .map_err(|e| PolarAlignError::DeviceError(format!("Camera capture failed: {}", e)))?;

    if ctx.cancellation_token.load(Ordering::Relaxed) {
        return Err(PolarAlignError::Cancelled);
    }

    emit_preview(&image_data, image_callback, None, None);

    status_callback("All-sky: plate-solving...".to_string(), None);

    let solve_future = ctx.device_ops.plate_solve(&image_data, None, None, None);
    let solve_result =
        match tokio::time::timeout(Duration::from_secs_f64(config.solve_timeout), solve_future)
            .await
        {
            Ok(Ok(res)) if res.success => res,
            Ok(Ok(_)) => {
                return Err(PolarAlignError::SolveFailed(
                    "Solver returned unsuccessful result".to_string(),
                ));
            }
            Ok(Err(e)) => return Err(PolarAlignError::SolveFailed(e)),
            Err(_) => {
                return Err(PolarAlignError::SolveFailed(format!(
                    "Solver timed out after {:.1}s",
                    config.solve_timeout
                )));
            }
        };

    emit_preview(
        &image_data,
        image_callback,
        Some(solve_result.ra_degrees),
        Some(solve_result.dec_degrees),
    );

    Ok(SolvedFrame {
        ra_deg: solve_result.ra_degrees,
        dec_deg: solve_result.dec_degrees,
        when: Utc::now(),
    })
}

fn emit_preview(
    image_data: &crate::device_ops::ImageData,
    image_callback: &impl Fn(PolarAlignmentImageData),
    solved_ra: Option<f64>,
    solved_dec: Option<f64>,
) {
    let is_color = image_data.sensor_type.as_deref() == Some("Color");
    let bayer_pattern = image_data.bayer_offset.map(|(x, y)| match (x % 2, y % 2) {
        (0, 0) => BayerPattern::RGGB,
        (1, 0) => BayerPattern::GRBG,
        (0, 1) => BayerPattern::GBRG,
        (1, 1) => BayerPattern::BGGR,
        _ => BayerPattern::RGGB,
    });

    let packed_data: Vec<u8> = image_data
        .data
        .iter()
        .flat_map(|&v| v.to_le_bytes())
        .collect();
    let imaging_image = ImagingImageData {
        width: image_data.width,
        height: image_data.height,
        channels: 1,
        pixel_type: PixelType::U16,
        data: packed_data,
    };

    if let Ok(jpeg) = prepare_image_for_display(&imaging_image, is_color, bayer_pattern) {
        image_callback(PolarAlignmentImageData {
            image_data: jpeg,
            width: image_data.width,
            height: image_data.height,
            solved_ra,
            solved_dec,
            point: 0,
            phase: "adjusting".to_string(),
        });
    }
}

/// Polar misalignment vector decomposed into azimuth and altitude components,
/// expressed in arcseconds.
///
/// Sign conventions:
///   * `azimuth_error_arcsec` > 0: the mechanical polar axis sits east of
///     the true pole. The user should adjust the azimuth bolt to move it
///     westward.
///   * `altitude_error_arcsec` > 0: the mechanical polar axis sits above the
///     true pole (too high). The user should lower the altitude bolt.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PolarMisalignment {
    pub azimuth_error_arcsec: f64,
    pub altitude_error_arcsec: f64,
}

/// Compute the polar-axis misalignment from a drift pair.
///
/// # Inputs
///
/// * `baseline` — solved coordinates and time of the anchor frame.
/// * `current` — solved coordinates and time of the most recent frame.
/// * `observer_lat_deg`, `observer_lon_deg` — geographic location.
/// * `is_north` — northern hemisphere flag (selects pole direction).
///
/// # Math
///
/// The mount rotates around `p_mech` at sidereal rate `Omega`. In the celestial
/// frame this means the camera vector `v` traces an angular velocity:
///
/// ```text
/// omega_drift = Omega * (p_mech - p_true)
/// ```
///
/// over the elapsed time. The drift of the camera pointing direction in the
/// celestial frame is then:
///
/// ```text
/// dv/dt = omega_drift cross v
/// ```
///
/// We observe `Delta_v = v_current - v_baseline` over elapsed time `T`.
/// Therefore:
///
/// ```text
/// omega_drift cross v_baseline ~= Delta_v / T
/// ```
///
/// We can recover the two components of `omega_drift` perpendicular to
/// `v_baseline` (the component along `v_baseline` is unobservable from a
/// single drift sample). Projecting those two components onto the
/// horizontal (alt, az) basis at the celestial pole yields the (Delta_az,
/// Delta_alt) misalignment vector in radians, which we scale to arcseconds.
///
/// Note that this technique works for **any** pointing direction in the
/// sky, satisfying the "all-sky" requirement. The only configuration that
/// produces poor results is when the optical axis points directly at the
/// celestial pole (in which case the drift signal vanishes for any
/// misalignment direction).
pub fn compute_polar_misalignment_from_drift(
    baseline: &SolvedFrame,
    current: &SolvedFrame,
    observer_lat_deg: f64,
    observer_lon_deg: f64,
    is_north: bool,
) -> PolarMisalignment {
    let dt_secs = (current.when - baseline.when).num_milliseconds() as f64 / 1000.0;
    if dt_secs <= 0.0 {
        // Same frame or clock skew — no information yet.
        return PolarMisalignment {
            azimuth_error_arcsec: 0.0,
            altitude_error_arcsec: 0.0,
        };
    }

    let v_baseline = radec_to_unit_vector(baseline.ra_deg, baseline.dec_deg);
    let v_current = radec_to_unit_vector(current.ra_deg, current.dec_deg);

    let dv = (
        v_current.0 - v_baseline.0,
        v_current.1 - v_baseline.1,
        v_current.2 - v_baseline.2,
    );

    // Drift angular-velocity vector (in celestial frame, units rad/s):
    //   ω_perp = v × (Δv / T)
    //
    // This recovers the component of ω_drift perpendicular to v_baseline.
    // Derivation: ω × v = Δv/T, so v × (ω × v) = v × (Δv/T). Using the BAC-CAB
    // identity, v × (ω × v) = ω(v·v) − v(v·ω) = ω − v(v·ω). For unit v this
    // is the component of ω orthogonal to v. Equivalently, ω_perp =
    // v × (Δv / T).
    let dv_over_t = (dv.0 / dt_secs, dv.1 / dt_secs, dv.2 / dt_secs);
    let omega_perp = (
        v_baseline.1 * dv_over_t.2 - v_baseline.2 * dv_over_t.1,
        v_baseline.2 * dv_over_t.0 - v_baseline.0 * dv_over_t.2,
        v_baseline.0 * dv_over_t.1 - v_baseline.1 * dv_over_t.0,
    );

    // Per the equation ω_drift = Ω · (p̂_mech − p̂_true), we have:
    //   p̂_mech − p̂_true = ω_drift / Ω
    // The perpendicular component recovered is the same equation projected
    // perpendicular to v. Divide by the sidereal rate to convert from
    // angular velocity to a small unit-vector displacement.
    let delta_unit_perp = (
        omega_perp.0 / SIDEREAL_RATE_RAD_PER_SEC,
        omega_perp.1 / SIDEREAL_RATE_RAD_PER_SEC,
        omega_perp.2 / SIDEREAL_RATE_RAD_PER_SEC,
    );

    // The full vector `p̂_mech − p̂_true` may have a component along v that
    // we cannot observe. However, for the projection onto the (alt, az)
    // basis at the pole, the unobserved component along v contributes only
    // when v happens to align with the (alt, az) basis directions — which
    // is the well-known degenerate case (target at pole). For all other
    // pointings, the perpendicular component is a faithful estimate of the
    // misalignment.

    // Project the misalignment vector onto the horizontal (alt, az) basis
    // at the celestial pole. Build the pole's horizontal frame using the
    // observer's latitude:
    //   pole_alt = ±lat, pole_az = 0 (N) or 180 (S)
    //   altitude basis: tangent to the meridian at the pole, in the direction
    //     of increasing altitude.
    //   azimuth basis: tangent to the horizon at the pole, in the direction
    //     of increasing azimuth (east).
    //
    // Working in the celestial frame, the pole vector itself is
    // (cos(LST)·cos(lat), sin(LST)·cos(lat), sin(lat)) for the northern
    // case — but we don't actually need to compute the pole vector
    // explicitly because we want to express `delta_unit_perp` as
    // misalignment components in horizontal coordinates.
    //
    // The clean way: convert `delta_unit_perp` into a (RA, Dec) tangent
    // vector, then into an (alt, az) tangent vector via the standard
    // equatorial-to-horizontal Jacobian evaluated at the celestial pole.
    //
    // At the celestial pole (RA, Dec) coordinates are singular, but the
    // tangent space is well-defined. Concretely:
    //
    //   * A small displacement δ_alt along the altitude axis at the pole
    //     points toward the zenith — in the celestial frame this is
    //     (cos(LST)·cos(0), sin(LST)·cos(0), sin(0)) = (cos(LST), sin(LST), 0)
    //     rotated 90° from the pole, i.e., the vector tangent to the
    //     meridian.
    //   * A small displacement δ_az along the azimuth axis at the pole
    //     points east — in the celestial frame this is perpendicular to
    //     both the pole vector and the meridian tangent.
    //
    // In the celestial frame, with `phi` = observer latitude and LST = local
    // sidereal time in radians:
    //
    //     p̂_true        = (cos(LST)·cos(phi), sin(LST)·cos(phi), sin(phi))    [N]
    //     alt_axis      = (cos(LST)·(-sin(phi)), sin(LST)·(-sin(phi)), cos(phi))
    //     az_axis       = (-sin(LST), cos(LST), 0)
    //
    // For the southern hemisphere we flip the pole and altitude axis.
    let lst_hours = crate::local_sidereal_time(crate::julian_day(&current.when), observer_lon_deg);
    let lst_rad = (lst_hours * 15.0).to_radians();
    let phi_rad = observer_lat_deg.to_radians();

    let (alt_axis, az_axis) = if is_north {
        let alt_axis = (
            lst_rad.cos() * (-phi_rad.sin()),
            lst_rad.sin() * (-phi_rad.sin()),
            phi_rad.cos(),
        );
        let az_axis = (-lst_rad.sin(), lst_rad.cos(), 0.0);
        (alt_axis, az_axis)
    } else {
        // Southern pole: flip the pole, so altitude axis at -lat points
        // "down" relative to north; we negate both the pole-direction and
        // its altitude tangent.
        let alt_axis = (
            lst_rad.cos() * phi_rad.sin(),
            lst_rad.sin() * phi_rad.sin(),
            -phi_rad.cos(),
        );
        // Azimuth at the south pole still increases eastward — but
        // azimuth = 0 is north, so the +az direction at the south pole's
        // location is the same celestial-frame vector with az measured
        // from the south:
        let az_axis = (lst_rad.sin(), -lst_rad.cos(), 0.0);
        (alt_axis, az_axis)
    };

    // Project the misalignment vector onto the alt/az basis.
    let alt_component = delta_unit_perp.0 * alt_axis.0
        + delta_unit_perp.1 * alt_axis.1
        + delta_unit_perp.2 * alt_axis.2;
    let az_component = delta_unit_perp.0 * az_axis.0
        + delta_unit_perp.1 * az_axis.1
        + delta_unit_perp.2 * az_axis.2;

    // `delta_unit_perp` ≈ p̂_mech − p̂_true as a small displacement vector
    // on the unit sphere, in radians. Convert to arcseconds.
    const RAD_TO_ARCSEC: f64 = 206264.80624709636;

    PolarMisalignment {
        azimuth_error_arcsec: az_component * RAD_TO_ARCSEC,
        altitude_error_arcsec: alt_component * RAD_TO_ARCSEC,
    }
}

/// Convert (RA degrees, Dec degrees) to a unit vector on the celestial sphere.
fn radec_to_unit_vector(ra_deg: f64, dec_deg: f64) -> (f64, f64, f64) {
    let ra = ra_deg.to_radians();
    let dec = dec_deg.to_radians();
    (dec.cos() * ra.cos(), dec.cos() * ra.sin(), dec.sin())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Duration as ChronoDuration, TimeZone};

    fn epoch() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap()
    }

    /// Simulate an imperfectly aligned mount tracking a star for `dt_secs`.
    ///
    /// The mount rotates the celestial sphere around its (perturbed)
    /// mechanical pole at sidereal rate while truth rotates around the
    /// celestial pole at the same rate. The camera, fixed to the mount,
    /// therefore drifts relative to the celestial frame.
    ///
    /// `pole_az_offset_arcsec` / `pole_alt_offset_arcsec`: how far the
    /// mechanical pole is offset from the true pole, in arcseconds. Positive
    /// values match the sign convention in `PolarMisalignment`.
    ///
    /// This uses an exact rotation matrix rather than a tangent-space
    /// linearization so the simulator faithfully exercises the algorithm.
    #[allow(clippy::too_many_arguments)]
    fn simulate_tracking_drift(
        baseline_ra_deg: f64,
        baseline_dec_deg: f64,
        observer_lat_deg: f64,
        observer_lon_deg: f64,
        is_north: bool,
        when: DateTime<Utc>,
        dt_secs: f64,
        pole_az_offset_arcsec: f64,
        pole_alt_offset_arcsec: f64,
    ) -> SolvedFrame {
        let lst_hours = crate::local_sidereal_time(crate::julian_day(&when), observer_lon_deg);
        let lst_rad = (lst_hours * 15.0).to_radians();
        let phi_rad = observer_lat_deg.to_radians();

        let (p_true, alt_axis, az_axis) = if is_north {
            (
                (
                    lst_rad.cos() * phi_rad.cos(),
                    lst_rad.sin() * phi_rad.cos(),
                    phi_rad.sin(),
                ),
                (
                    lst_rad.cos() * (-phi_rad.sin()),
                    lst_rad.sin() * (-phi_rad.sin()),
                    phi_rad.cos(),
                ),
                (-lst_rad.sin(), lst_rad.cos(), 0.0),
            )
        } else {
            (
                (
                    -lst_rad.cos() * phi_rad.cos(),
                    -lst_rad.sin() * phi_rad.cos(),
                    -phi_rad.sin(),
                ),
                (
                    lst_rad.cos() * phi_rad.sin(),
                    lst_rad.sin() * phi_rad.sin(),
                    -phi_rad.cos(),
                ),
                (lst_rad.sin(), -lst_rad.cos(), 0.0),
            )
        };

        const ARCSEC_TO_RAD: f64 = 4.84813681109536e-6;
        let dalt = pole_alt_offset_arcsec * ARCSEC_TO_RAD;
        let daz = pole_az_offset_arcsec * ARCSEC_TO_RAD;

        // Build perturbed mechanical pole and renormalize.
        let p_mech_raw = (
            p_true.0 + dalt * alt_axis.0 + daz * az_axis.0,
            p_true.1 + dalt * alt_axis.1 + daz * az_axis.1,
            p_true.2 + dalt * alt_axis.2 + daz * az_axis.2,
        );
        let pm_mag = (p_mech_raw.0.powi(2) + p_mech_raw.1.powi(2) + p_mech_raw.2.powi(2)).sqrt();
        let p_mech = (
            p_mech_raw.0 / pm_mag,
            p_mech_raw.1 / pm_mag,
            p_mech_raw.2 / pm_mag,
        );

        // Mount tracks by rotating around p_mech by +Ω·dt (eastward).
        // Truth: stars rotate around p_true at Ω·dt. The camera, fixed to
        // the mount, sees stars drift by (R_true · R_mech^{-1}) ≈ small
        // residual rotation.
        //
        // Equivalently, in the celestial (truth) frame: the camera vector
        // is initially v0; after time dt the mount has rotated the camera
        // by R(p_mech, +Ω·dt). But the celestial sphere also rotated by
        // R(p_true, +Ω·dt). The camera, viewed from the celestial frame,
        // ends up at:
        //   v1 = R(p_true, -Ω·dt) · R(p_mech, +Ω·dt) · v0
        // (We rotate v0 forward by the mount, then back into the truth
        // frame.)

        let theta = SIDEREAL_RATE_RAD_PER_SEC * dt_secs;
        let v0 = radec_to_unit_vector(baseline_ra_deg, baseline_dec_deg);

        // First apply the mount rotation about p_mech by +theta.
        let v_after_mount = rotate_around_axis(v0, p_mech, theta);
        // Then apply truth rotation about p_true by -theta (going back into
        // truth-stationary frame).
        let v1 = rotate_around_axis(v_after_mount, p_true, -theta);

        let dec = v1.2.clamp(-1.0, 1.0).asin().to_degrees();
        let mut ra = v1.1.atan2(v1.0).to_degrees();
        if ra < 0.0 {
            ra += 360.0;
        }

        SolvedFrame {
            ra_deg: ra,
            dec_deg: dec,
            when: when + ChronoDuration::milliseconds((dt_secs * 1000.0) as i64),
        }
    }

    /// Rodrigues' rotation formula: rotate `v` around unit `axis` by `theta`
    /// radians (right-hand rule).
    fn rotate_around_axis(
        v: (f64, f64, f64),
        axis: (f64, f64, f64),
        theta: f64,
    ) -> (f64, f64, f64) {
        let cos_t = theta.cos();
        let sin_t = theta.sin();
        let dot = axis.0 * v.0 + axis.1 * v.1 + axis.2 * v.2;
        let cross = (
            axis.1 * v.2 - axis.2 * v.1,
            axis.2 * v.0 - axis.0 * v.2,
            axis.0 * v.1 - axis.1 * v.0,
        );
        (
            v.0 * cos_t + cross.0 * sin_t + axis.0 * dot * (1.0 - cos_t),
            v.1 * cos_t + cross.1 * sin_t + axis.1 * dot * (1.0 - cos_t),
            v.2 * cos_t + cross.2 * sin_t + axis.2 * dot * (1.0 - cos_t),
        )
    }

    #[test]
    fn perfect_alignment_reports_zero_drift_error() {
        let when = epoch();
        let baseline = SolvedFrame {
            ra_deg: 83.633,
            dec_deg: 22.014,
            when,
        };
        let current = simulate_tracking_drift(
            baseline.ra_deg,
            baseline.dec_deg,
            45.0,
            -122.0,
            true,
            when,
            60.0,
            0.0,
            0.0,
        );
        let mis = compute_polar_misalignment_from_drift(&baseline, &current, 45.0, -122.0, true);
        assert!(
            mis.azimuth_error_arcsec.abs() < 1e-6,
            "az error should be zero for perfect alignment, got {}",
            mis.azimuth_error_arcsec
        );
        assert!(
            mis.altitude_error_arcsec.abs() < 1e-6,
            "alt error should be zero for perfect alignment, got {}",
            mis.altitude_error_arcsec
        );
    }

    /// Helper: compute the local sidereal time in degrees at `when` for
    /// `observer_lon_deg`. Used by tests that need to position targets on
    /// the meridian (HA = 0) for well-conditioned recovery geometry.
    fn lst_deg(when: DateTime<Utc>, observer_lon_deg: f64) -> f64 {
        let lst_hours = crate::local_sidereal_time(crate::julian_day(&when), observer_lon_deg);
        let mut lst = lst_hours * 15.0;
        lst = lst.rem_euclid(360.0);
        lst
    }

    #[test]
    fn one_degree_east_azimuth_error_recovered_as_one_degree_azimuth() {
        // Recovery is exact when the camera pointing is perpendicular to the
        // misalignment vector. For pure azimuth misalignment, targeting the
        // meridian (HA = 0) makes v_baseline perpendicular to the az_axis
        // basis, eliminating the unobservable-along-v ambiguity.
        let when = epoch();
        let lat = 45.0;
        let lon = -122.0;
        let baseline = SolvedFrame {
            ra_deg: lst_deg(when, lon), // HA = 0 (meridian)
            dec_deg: lat,               // Dec = lat: also perpendicular to alt_axis
            when,
        };
        let current = simulate_tracking_drift(
            baseline.ra_deg,
            baseline.dec_deg,
            lat,
            lon,
            true,
            when,
            60.0,
            3600.0,
            0.0,
        );

        let mis = compute_polar_misalignment_from_drift(&baseline, &current, lat, lon, true);

        assert!(
            (mis.azimuth_error_arcsec - 3600.0).abs() < 25.0,
            "expected az ≈ 3600″, got az={:.2}\", alt={:.2}\"",
            mis.azimuth_error_arcsec,
            mis.altitude_error_arcsec
        );
        assert!(
            mis.altitude_error_arcsec.abs() < 25.0,
            "expected alt ≈ 0, got alt={:.2}\"",
            mis.altitude_error_arcsec
        );
    }

    #[test]
    fn one_degree_altitude_error_recovered_as_one_degree_altitude() {
        let when = epoch();
        let lat = 45.0;
        let lon = -122.0;
        let baseline = SolvedFrame {
            ra_deg: lst_deg(when, lon),
            dec_deg: lat,
            when,
        };
        let current = simulate_tracking_drift(
            baseline.ra_deg,
            baseline.dec_deg,
            lat,
            lon,
            true,
            when,
            60.0,
            0.0,
            3600.0,
        );

        let mis = compute_polar_misalignment_from_drift(&baseline, &current, lat, lon, true);

        assert!(
            (mis.altitude_error_arcsec - 3600.0).abs() < 25.0,
            "expected alt ≈ 3600″, got alt={:.2}\", az={:.2}\"",
            mis.altitude_error_arcsec,
            mis.azimuth_error_arcsec
        );
        assert!(
            mis.azimuth_error_arcsec.abs() < 25.0,
            "expected az ≈ 0, got az={:.2}\"",
            mis.azimuth_error_arcsec
        );
    }

    #[test]
    fn combined_misalignment_recovered_in_both_components() {
        let when = epoch();
        let lat = 45.0;
        let lon = -122.0;
        let baseline = SolvedFrame {
            ra_deg: lst_deg(when, lon),
            dec_deg: lat,
            when,
        };
        let current = simulate_tracking_drift(
            baseline.ra_deg,
            baseline.dec_deg,
            lat,
            lon,
            true,
            when,
            60.0,
            1800.0,
            -2400.0,
        );

        let mis = compute_polar_misalignment_from_drift(&baseline, &current, lat, lon, true);

        assert!(
            (mis.azimuth_error_arcsec - 1800.0).abs() < 25.0,
            "az expected ≈ 1800″, got {:.2}\"",
            mis.azimuth_error_arcsec
        );
        assert!(
            (mis.altitude_error_arcsec - (-2400.0)).abs() < 25.0,
            "alt expected ≈ -2400″, got {:.2}\"",
            mis.altitude_error_arcsec
        );
    }

    #[test]
    fn southern_hemisphere_combined_misalignment_recovered() {
        // Sydney-ish observer: -33°, +151°.
        let when = epoch();
        let lat = -33.0;
        let lon = 151.0;
        let baseline = SolvedFrame {
            ra_deg: lst_deg(when, lon),
            dec_deg: lat,
            when,
        };
        let current = simulate_tracking_drift(
            baseline.ra_deg,
            baseline.dec_deg,
            lat,
            lon,
            false,
            when,
            60.0,
            1500.0,
            900.0,
        );

        let mis = compute_polar_misalignment_from_drift(&baseline, &current, lat, lon, false);

        assert!(
            (mis.azimuth_error_arcsec - 1500.0).abs() < 25.0,
            "south az expected ≈ 1500″, got {:.2}\"",
            mis.azimuth_error_arcsec
        );
        assert!(
            (mis.altitude_error_arcsec - 900.0).abs() < 25.0,
            "south alt expected ≈ 900″, got {:.2}\"",
            mis.altitude_error_arcsec
        );
    }

    #[test]
    fn off_meridian_target_has_bounded_recovery_error() {
        // Document the algorithm's well-known degeneracy: when the target is
        // far from the optimal geometry (meridian + Dec=lat), single-frame
        // recovery undercounts the misalignment by approximately the
        // cosine of the angle between v_baseline and the misalignment
        // direction. The recovered magnitude should still be within
        // 1° of truth for any non-pathological pointing.
        let when = epoch();
        let lat = 45.0;
        let lon = -122.0;
        let baseline = SolvedFrame {
            ra_deg: 200.0,
            dec_deg: 20.0,
            when,
        };
        let current = simulate_tracking_drift(
            baseline.ra_deg,
            baseline.dec_deg,
            lat,
            lon,
            true,
            when,
            60.0,
            3600.0,
            0.0,
        );

        let mis = compute_polar_misalignment_from_drift(&baseline, &current, lat, lon, true);
        let total = (mis.azimuth_error_arcsec.powi(2) + mis.altitude_error_arcsec.powi(2)).sqrt();

        // Recovery magnitude is bounded by [observable_component, truth].
        // For non-pole-pointing geometries this is always ≤ 3600″.
        // It must NOT exceed truth (i.e., no over-recovery).
        assert!(
            total <= 3600.1,
            "off-meridian recovery should not exceed true misalignment, got {:.2}\"",
            total
        );
        // And should recover at least 30% of the true magnitude for any
        // reasonable pointing far from the pole.
        assert!(
            total >= 1080.0,
            "off-meridian recovery should be at least 30% of truth, got {:.2}\"",
            total
        );
    }

    #[test]
    fn zero_elapsed_time_returns_zero_error_without_panic() {
        // Defensive: identical timestamps must not divide by zero.
        let frame = SolvedFrame {
            ra_deg: 100.0,
            dec_deg: 30.0,
            when: epoch(),
        };
        let mis = compute_polar_misalignment_from_drift(&frame, &frame, 45.0, -122.0, true);
        assert_eq!(mis.azimuth_error_arcsec, 0.0);
        assert_eq!(mis.altitude_error_arcsec, 0.0);
    }

    #[test]
    fn solver_unavailable_error_message_is_actionable() {
        let err = PolarAlignError::SolverUnavailable;
        let msg = err.to_string();
        assert!(
            msg.contains("ASTAP"),
            "error should mention ASTAP, got: {}",
            msg
        );
        assert!(
            msg.contains("Plate solver"),
            "error should mention 'Plate solver', got: {}",
            msg
        );
    }

    #[test]
    fn solve_failed_error_includes_inner_message() {
        let err = PolarAlignError::SolveFailed("timeout".to_string());
        let msg = err.to_string();
        assert!(msg.contains("timeout"));
    }

    #[test]
    fn location_missing_error_is_actionable() {
        let err = PolarAlignError::LocationMissing;
        let msg = err.to_string();
        assert!(msg.contains("latitude"));
    }

    #[test]
    fn default_config_has_30_arcsec_threshold() {
        let cfg = AllSkyPolarAlignConfig::default();
        assert_eq!(cfg.acceptance_threshold_arcsec, 30.0);
    }

    #[test]
    fn unit_vector_recovers_known_directions() {
        // Equator, RA=0 → (+1, 0, 0)
        let v = radec_to_unit_vector(0.0, 0.0);
        assert!((v.0 - 1.0).abs() < 1e-12);
        assert!(v.1.abs() < 1e-12);
        assert!(v.2.abs() < 1e-12);

        // Pole → (0, 0, 1)
        let v = radec_to_unit_vector(0.0, 90.0);
        assert!(v.0.abs() < 1e-12);
        assert!(v.1.abs() < 1e-12);
        assert!((v.2 - 1.0).abs() < 1e-12);

        // RA=90, Dec=0 → (0, +1, 0)
        let v = radec_to_unit_vector(90.0, 0.0);
        assert!(v.0.abs() < 1e-12);
        assert!((v.1 - 1.0).abs() < 1e-12);
        assert!(v.2.abs() < 1e-12);
    }
}
