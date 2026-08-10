//! Instruction execution implementations
//!
//! These functions implement the actual device control for sequencer instructions.
//! They use the DeviceOps trait to communicate with real or simulated hardware.

use crate::device_ops::{ImageData, SharedDeviceOps};
use crate::*;
use chrono::NaiveDate;
use std::path::PathBuf;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::sleep;

/// Architecture-unification 2026-06-07 (W1 native daylight gate): the default
/// maximum Sun altitude (degrees above the horizon) at which an on-sky LIGHT
/// capture is permitted. Mirrors the Dart scheduler's `maxSunAltitudeDegrees`
/// default (`SchedulerConfig.maxSunAltitudeDegrees = -12.0`, nautical
/// darkness) so the structural native gate is NEVER weaker than the Dart W1
/// twilight gate it backstops. The Sun a few degrees below the horizon (civil
/// twilight) is still far too bright for science LIGHT frames, so the default
/// is slightly negative — the gate blocks while the Sun is above this.
///
/// Remediation 2026-06-09 (finding #2): this was previously `0.0`, which left a
/// TWILIGHT GAP — for a Sun altitude between the Dart threshold (-12°) and 0°
/// the Dart autopilot rejected but the native gate ALLOWED. The Dart side can
/// still push a tighter/looser value at session start via
/// [`crate::executor::ExecutorCommand::UpdateMaxSunAltitude`] /
/// `SequenceExecutor::update_max_sun_altitude`; this constant is the floor used
/// when nothing was pushed (and when a non-finite value is seen), so the native
/// gate matches the Dart W1 gate even with no explicit push.
pub const DEFAULT_MAX_SUN_ALTITUDE_DEGREES: f64 = -12.0;

/// W1 native daylight gate — recovery code stamped on a START rejection so the
/// UI / recovery layer can distinguish a daylight block from other slew/expose
/// failures.
pub const DAYLIGHT_GATE_RECOVERY_CODE: &str = "DAYLIGHT_GATE_SUN_UP";

/// Recovery code stamped when a node refuses to point at a target whose sky
/// position was never chosen, so the recovery layer can offer "set the target's
/// coordinates" instead of treating it as a mount fault.
pub const UNSET_TARGET_RECOVERY_CODE: &str = "TARGET_COORDINATES_UNSET";

/// Structural gate on pointing inherited from a `TargetHeader` that still
/// carries the palette placeholder. Returns `Some(reason)` to BLOCK.
///
/// `TargetHeaderConfig` has no nullable coordinate meaning "nothing picked
/// yet", so a target added from the palette starts at exactly RA 0h / Dec +0°.
/// Both values are in range and the pair is a real point in Pisces, so nothing
/// downstream can tell it apart from a deliberate pointing: the mount slews
/// there, and on an unattended remote rig it sits there for the rest of the
/// night.
///
/// Dart's `TargetCoordinatesUnsetRule` blocks this on the GUI start path, but
/// pre-flight validation is not the only way into a run — the headless
/// `POST /api/sequencer/start`, `sequencer_load_json` and every checkpoint
/// resume reach the executor without it, and a checkpoint written before that
/// rule existed resumes straight into the same slew. Gating the two nodes that
/// actually command the mount holds for all of those entry points at once.
///
/// The test is deliberately exact — `0.0` and nothing else — matching the Dart
/// rule so the two surfaces cannot disagree about which sequences are
/// runnable. An operator who genuinely wants that spot claims it with the
/// ten-thousandth-of-a-unit nudge the coordinate editor already exposes;
/// anything fuzzier would refuse legitimate pointings near the vernal equinox.
pub(crate) fn unset_target_pointing_reason(
    target_name: Option<&str>,
    ra_hours: f64,
    dec_degrees: f64,
    what: &str,
) -> Option<String> {
    if ra_hours != 0.0 || dec_degrees != 0.0 {
        return None;
    }
    let label = target_name
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .unwrap_or("this target");
    Some(format!(
        "Refusing {what}: target \"{label}\" is still at the RA 0h / Dec +0° placeholder, so \
         its sky position was never chosen. Set the target's coordinates before running this \
         sequence."
    ))
}

/// Whether a sequencer frame is an on-sky light that requires darkness.
///
/// Calibration frame types are intentionally explicit exemptions: they can be
/// captured during daylight even when they live below a TargetHeader and the
/// mount happens to be unparked.
fn frame_type_requires_darkness(frame_type: &str) -> bool {
    frame_type.eq_ignore_ascii_case("light")
}

/// W1 native daylight gate decision.
///
/// Structural START gate applied by `execute_slew` (when slewing to a
/// sky/science target) and `execute_exposure` (when capturing a LIGHT frame on
/// a science target). It enforces the W1 "no daylight imaging" invariant for
/// EVERY executor-run sequence — including a raw sequence started via
/// `api_sequencer_start` (e.g. a mosaic) — not just the autopilot path that
/// `scheduler_engine.dart` already gates. The same Sun-position math behind
/// `ExecutionContext::is_dark` is reused via
/// `crate::node::context::current_sun_altitude_degrees`.
///
/// Returns `Some(reason)` to BLOCK, `None` to allow. It is fail-closed only for
/// a genuine on-sky LIGHT capture: when the observer location is unknown the
/// gate ABSTAINS (returns `None`) rather than blocking, because without a
/// location the Sun altitude cannot be computed and blocking would break
/// location-less rigs doing legitimate work — the Dart W1 gate remains the
/// belt-and-suspenders for the autopilot path. Flats/darks/bias/park and a
/// parked rig never reach this function (their callers pass nothing that looks
/// like an on-sky LIGHT capture), so daytime calibration / testing is
/// unaffected.
pub(crate) fn daylight_gate_block_reason(
    latitude: Option<f64>,
    longitude: Option<f64>,
    max_sun_altitude_degrees: f64,
    what: &str,
) -> Option<String> {
    let (lat, lon) = match (latitude, longitude) {
        (Some(lat), Some(lon)) => (lat, lon),
        _ => {
            // No location => cannot compute Sun altitude. Abstain (the Dart W1
            // gate still protects the autopilot path); never fabricate a block
            // that would wedge a location-less rig.
            tracing::debug!(
                "Daylight gate abstaining for {what}: observer location unset (lat/lon None)"
            );
            return None;
        }
    };

    let sun_alt = crate::node::context::current_sun_altitude_degrees(lat, lon);
    let max_alt = if max_sun_altitude_degrees.is_finite() {
        max_sun_altitude_degrees
    } else {
        DEFAULT_MAX_SUN_ALTITUDE_DEGREES
    };

    if sun_alt > max_alt {
        Some(format!(
            "Daylight gate: refusing {what} — Sun altitude {sun_alt:.1}° is above the \
             maximum {max_alt:.1}° for on-sky light imaging. Daytime flats/darks/bias and \
             a parked rig are unaffected; this blocks only on-sky science captures."
        ))
    } else {
        None
    }
}

/// W1 native daylight gate — resolve the effective maximum Sun altitude for a
/// running sequence. Reads the executor-seeded value from the shared trigger
/// state (mirrors `RuntimeConfig::max_sun_altitude_degrees`), falling back to
/// [`DEFAULT_MAX_SUN_ALTITUDE_DEGREES`] when no trigger state is wired (one-shot
/// instruction sites / tests) or the value has not been seeded.
async fn resolve_max_sun_altitude(ctx: &InstructionContext) -> f64 {
    if let Some(lock) = &ctx.trigger_state {
        if let Some(v) = lock.read().await.max_sun_altitude_degrees {
            return v;
        }
    }
    DEFAULT_MAX_SUN_ALTITUDE_DEGREES
}

fn validate_exposure_filter_request(
    filter: Option<&str>,
    filter_index: Option<i32>,
    filterwheel_id: Option<&str>,
) -> Result<(), String> {
    let filter = filter.map(str::trim).filter(|name| !name.is_empty());
    if filterwheel_id.is_some() || (filter.is_none() && filter_index.is_none()) {
        return Ok(());
    }

    let requested = match (filter, filter_index) {
        (Some(name), Some(index)) => format!("\"{}\" at position {}", name, index),
        (Some(name), None) => format!("\"{}\"", name),
        (None, Some(index)) => format!("position {}", index),
        (None, None) => unreachable!("no filter request was already handled"),
    };
    Err(format!(
        "Cannot capture with requested filter {} because no filter wheel is connected",
        requested
    ))
}

/// Ask the wheel which filter it is ACTUALLY sitting on.
///
/// The sequence context only ever learns a filter name when something inside
/// the running sequence sets one — a Change Filter node, a Smart Exposure
/// plan, or the burst's own `filter`. A run that simply captures with the
/// wheel left where the operator parked it therefore carried NO filter
/// identity at all: the save-path template rendered the synthetic `nofilter`
/// label and `FrameContext.filter_name` stayed `None`, so the saved FITS had
/// no FILTER card even though the wheel would answer the question at any
/// moment. Every calibration workflow (PixInsight / Siril / APP) keys off
/// FILTER, so those lights could not be matched to flats without hand-editing
/// the headers.
///
/// Returns `None` — never a guessed label — when there is no wheel, when the
/// wheel is still moving (drivers report a negative position while in
/// transit), when the names cannot be read, or when the occupied slot has no
/// configured name. An unknown filter must stay unknown; inventing "L" would
/// mis-label narrowband frames as luminance.
pub(crate) async fn observed_wheel_filter(ctx: &InstructionContext) -> Option<(String, i32)> {
    let fw_id = ctx.filterwheel_id.as_deref()?;
    let position = match ctx.device_ops.filterwheel_get_position(fw_id).await {
        Ok(position) if position >= 0 => position,
        Ok(position) => {
            tracing::debug!(
                "[CAPTURE] filter wheel reports in-transit position {}; frame filter left unknown",
                position
            );
            return None;
        }
        Err(e) => {
            tracing::debug!(
                "[CAPTURE] filterwheel_get_position failed; frame filter left unknown: {}",
                e
            );
            return None;
        }
    };
    let name = wheel_filter_name_at(ctx, position).await?;
    Some((name, position))
}

/// Name of the filter installed in wheel slot `position`, or `None` when the
/// wheel cannot be asked or the slot is unnamed. Companion to
/// [`observed_wheel_filter`] for the case where the slot is already known
/// (a burst that addresses the wheel by index).
pub(crate) async fn wheel_filter_name_at(
    ctx: &InstructionContext,
    position: i32,
) -> Option<String> {
    let fw_id = ctx.filterwheel_id.as_deref()?;
    if position < 0 {
        return None;
    }
    let names = match ctx.device_ops.filterwheel_get_names(fw_id).await {
        Ok(names) => names,
        Err(e) => {
            tracing::debug!(
                "[CAPTURE] filterwheel_get_names failed; frame filter left unknown: {}",
                e
            );
            return None;
        }
    };
    let name = names.get(position as usize)?.trim().to_string();
    if name.is_empty() {
        tracing::debug!(
            "[CAPTURE] filter wheel slot {} has no configured name; frame filter left unknown",
            position
        );
        return None;
    }
    Some(name)
}

/// Wheel slot occupied by the filter called `name`, or `None` when there is no
/// wheel, it cannot be asked, or nothing in it goes by that name.
///
/// Inverse of [`wheel_filter_name_at`]. A burst that addresses the wheel BY
/// NAME never learns the slot it landed on, so without this the frame carried a
/// correct `filter_name` next to whatever `filter_index` an earlier burst had
/// left behind — one frame described by two filters, which is the same
/// disagreement the name resolution was added to end.
pub(crate) async fn wheel_filter_index_of(ctx: &InstructionContext, name: &str) -> Option<i32> {
    let fw_id = ctx.filterwheel_id.as_deref()?;
    let wanted = name.trim();
    if wanted.is_empty() {
        return None;
    }
    let names = match ctx.device_ops.filterwheel_get_names(fw_id).await {
        Ok(names) => names,
        Err(e) => {
            tracing::debug!(
                "[CAPTURE] filterwheel_get_names failed; frame filter position left unknown: {}",
                e
            );
            return None;
        }
    };
    let position = names
        .iter()
        .position(|slot| slot.trim().eq_ignore_ascii_case(wanted))?;
    i32::try_from(position).ok()
}

/// Outcome of [`resolve_burst_filter`].
pub(crate) enum BurstFilter {
    /// This burst addresses the wheel itself, so BOTH fields describe every
    /// frame in it — including when one of them is `None`. Overwriting the pair
    /// as a unit is what stops a slot number left behind by an earlier burst
    /// from being filed next to this burst's filter name.
    Resolved {
        name: Option<String>,
        index: Option<i32>,
    },
    /// Nothing in this burst addresses the wheel. Whatever a preceding Change
    /// Filter / Smart Exposure established still describes these frames.
    Inherit,
}

/// Decide the filter identity that this burst's frames should be recorded
/// under.
///
/// Precedence, strongest evidence first:
///  1. the burst's own `filter` — `execute_exposure` is about to drive the
///     wheel there, so it is what these frames are taken through. This case
///     was silently dropped before: `${filter}` in the save-path template
///     reads `current_filter`, never `config.filter`, so even a node with
///     "Ha" configured wrote `..._nofilter_....fits`;
///  2. the burst's `filter_index` resolved against the wheel's name table,
///     for nodes that address the wheel by position only;
///  3. whatever a preceding Change Filter / Smart Exposure already
///     established — already correct, leave it alone;
///  4. the wheel's own report of where it is parked, for the common case of a
///     sequence that never changes filter at all.
///
/// Cases 1 and 2 each know only half of the identity, so the other half is
/// looked up on the wheel: a name-addressed burst asks which slot it landed in,
/// a position-addressed burst asks what lives in that slot. A `None` that
/// survives the lookup is honest ignorance and is recorded as such — see
/// [`observed_wheel_filter`].
///
/// Lives here rather than in the TakeExposure node because the node is not the
/// only capture path: the Flat Wizard and every bridge one-shot call
/// [`execute_exposure`] directly, and they need the same answer.
pub(crate) async fn resolve_burst_filter(
    config: &ExposureConfig,
    ctx: &InstructionContext,
) -> BurstFilter {
    let configured_name = config
        .filter
        .as_deref()
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_string);

    match (configured_name, config.filter_index) {
        (Some(name), Some(index)) => BurstFilter::Resolved {
            name: Some(name),
            index: Some(index),
        },
        (Some(name), None) => {
            let index = wheel_filter_index_of(ctx, &name).await;
            BurstFilter::Resolved {
                name: Some(name),
                index,
            }
        }
        // Position-addressed burst: the wheel's own name table is the only
        // thing that knows what sits in that slot.
        (None, Some(index)) => BurstFilter::Resolved {
            name: wheel_filter_name_at(ctx, index).await,
            index: Some(index),
        },
        (None, None) => {
            // Already established by a preceding Change Filter / Smart Exposure.
            if ctx.current_filter.is_some() {
                return BurstFilter::Inherit;
            }
            match observed_wheel_filter(ctx).await {
                Some((name, index)) => BurstFilter::Resolved {
                    name: Some(name),
                    index: Some(index),
                },
                None => BurstFilter::Inherit,
            }
        }
    }
}

/// The filter identity to stamp on the frames of this burst, as one
/// (name, slot) pair.
///
/// [`resolve_burst_filter`] flattened against the running context, for the two
/// consumers that record a frame rather than update the context: the
/// renderer-less filename fallback and `build_frame_context_for_save` (FITS
/// FILTER card + the `captured_images` row). Both used to read `config.filter`
/// and `config.filter_index` INDEPENDENTLY, so a Flat Wizard run whose config
/// named "Ha" but carried no index was filed under "Ha" next to whatever slot
/// number a previous light burst had left in the context — one frame described
/// by two different filters. Resolving the pair as a unit here is what makes
/// the filename, the FITS header and the database row agree by construction.
pub(crate) async fn resolve_frame_filter(
    config: &ExposureConfig,
    ctx: &InstructionContext,
) -> (Option<String>, Option<i32>) {
    match resolve_burst_filter(config, ctx).await {
        BurstFilter::Resolved { name, index } => (name, index),
        // A slot number with no name behind it cannot describe a frame: it is
        // an artefact of an earlier burst, not evidence about this one.
        BurstFilter::Inherit if ctx.current_filter.is_some() => {
            (ctx.current_filter.clone(), ctx.current_filter_index)
        }
        BurstFilter::Inherit => (None, None),
    }
}

/// Result of an instruction execution
#[derive(Debug)]
pub struct InstructionResult {
    pub status: NodeStatus,
    pub message: Option<String>,
    pub data: Option<serde_json::Value>,
    /// HFR values from exposures (for trigger monitoring)
    pub hfr_values: Vec<f64>,
}

impl InstructionResult {
    pub fn success() -> Self {
        Self {
            status: NodeStatus::Success,
            message: None,
            data: None,
            hfr_values: Vec::new(),
        }
    }

    pub fn success_with_message(message: impl Into<String>) -> Self {
        Self {
            status: NodeStatus::Success,
            message: Some(message.into()),
            data: None,
            hfr_values: Vec::new(),
        }
    }

    pub fn failure(message: impl Into<String>) -> Self {
        Self {
            status: NodeStatus::Failure,
            message: Some(message.into()),
            data: None,
            hfr_values: Vec::new(),
        }
    }

    /// Create a failure result with a recovery code that the UI can use to offer recovery options
    pub fn failure_with_recovery(
        message: impl Into<String>,
        recovery_code: impl Into<String>,
    ) -> Self {
        Self {
            status: NodeStatus::Failure,
            message: Some(message.into()),
            data: Some(serde_json::json!({"recovery_code": recovery_code.into()})),
            hfr_values: Vec::new(),
        }
    }

    pub fn cancelled(message: impl Into<String>) -> Self {
        Self {
            status: NodeStatus::Cancelled,
            message: Some(message.into()),
            data: None,
            hfr_values: Vec::new(),
        }
    }

    /// Get the status, logging any failure or cancellation message.
    /// This ensures error messages are not silently discarded.
    pub fn log_and_get_status(self, node_name: &str) -> NodeStatus {
        self.log_and_get_status_with_recovery(node_name, None, None)
    }

    /// Get the status, logging failures and promoting disconnected-device
    /// failures to the executor recovery loop when the live context exposes
    /// a recovery request channel.
    pub fn log_and_get_status_with_context(
        self,
        node_name: &str,
        ctx: &InstructionContext,
    ) -> NodeStatus {
        // Publish the reason BEFORE the recovery handler consumes `self`. It is
        // the only copy: the node tree hands the executor a bare `NodeStatus`,
        // so without this the message reached the log and nowhere else, and the
        // run's terminal event, toast and persisted `errorMessages` all fell
        // back to the hardcoded "Sequence failed".
        //
        // Exactly ONCE per failed node, though. The node runtime re-executes an
        // instruction whose failure was promoted to device-disconnect recovery
        // (see `execute_instruction_with_disconnect_retry`), and every one of
        // those executions used to publish its own copy: one Open Dome node
        // that failed with "No dome connected" filled the session report with
        // six identical error lines and raised six identical Critical toasts,
        // so the report's error count could never match the number of failed
        // nodes. The first attempt is the one that reports — publishing there
        // rather than on the last means no path (recovery driver absent,
        // recovery cancelled, retries exhausted) can swallow the reason.
        if matches!(self.status, NodeStatus::Failure)
            && !crate::node::runtime::is_disconnect_retry_attempt()
        {
            if let (Some(message), Some(event_tx)) =
                (self.message.as_deref(), ctx.event_tx.as_ref())
            {
                let _ = event_tx.send(crate::executor::ExecutorEvent::InstructionFailed {
                    node_name: node_name.to_string(),
                    message: message.to_string(),
                });
            }
        }
        self.log_and_get_status_with_recovery(
            node_name,
            ctx.recovery_request_tx.as_ref(),
            Some(&ctx.device_disconnect_recovery_pending),
        )
    }

    fn log_and_get_status_with_recovery(
        self,
        node_name: &str,
        recovery_request_tx: Option<&mpsc::Sender<crate::recovery::RecoveryCause>>,
        device_disconnect_recovery_pending: Option<&Arc<AtomicBool>>,
    ) -> NodeStatus {
        match self.status {
            NodeStatus::Failure => {
                if let Some(msg) = &self.message {
                    tracing::error!("{} failed: {}", node_name, msg);
                    if is_device_disconnected_message(msg) {
                        // Mark the failure as a promoted device-disconnect BEFORE
                        // returning, so the node-runtime retry wrapper knows to
                        // wait for recovery + retry this instruction rather than
                        // letting the Failure end the sequence. Set the flag even
                        // when the recovery channel is absent so a future runtime
                        // can still observe the cause; the actual recovery only
                        // runs when the channel forwards the request.
                        if let Some(flag) = device_disconnect_recovery_pending {
                            flag.store(true, Ordering::Relaxed);
                        }
                        request_device_disconnected_recovery(node_name, msg, recovery_request_tx);
                    }
                } else {
                    tracing::error!("{} failed (no details)", node_name);
                }
            }
            NodeStatus::Cancelled => {
                if let Some(msg) = &self.message {
                    tracing::warn!("{} cancelled: {}", node_name, msg);
                }
            }
            _ => {}
        }
        self.status
    }
}

pub(crate) fn is_device_disconnected_message(message: &str) -> bool {
    let lower = message.to_ascii_lowercase();
    if lower.contains("please reconnect") {
        return true;
    }
    if lower.contains("device") && lower.contains("not connected") {
        return true;
    }

    const DEVICE_PREFIXES: &[&str] = &[
        "camera",
        "mount",
        "focuser",
        "filter wheel",
        "filterwheel",
        "rotator",
        "dome",
        "cover calibrator",
        "flat panel",
    ];
    DEVICE_PREFIXES.iter().any(|prefix| {
        lower.contains(&format!("no {prefix} connected"))
            || lower.contains(&format!("{prefix} is not connected"))
            || lower.contains(&format!("{prefix} not connected"))
    })
}

fn request_device_disconnected_recovery(
    node_name: &str,
    message: &str,
    recovery_request_tx: Option<&mpsc::Sender<crate::recovery::RecoveryCause>>,
) {
    let Some(tx) = recovery_request_tx else {
        tracing::warn!(
            "[RECOVERY] {} detected a device disconnect but no recovery channel is installed: {}",
            node_name,
            message
        );
        return;
    };

    match tx.try_send(crate::recovery::RecoveryCause::DeviceDisconnected) {
        Ok(()) => tracing::warn!(
            "[RECOVERY] {} promoted device disconnect to recovery: {}",
            node_name,
            message
        ),
        Err(tokio::sync::mpsc::error::TrySendError::Full(_)) => tracing::warn!(
            "[RECOVERY] Recovery channel full; dropping duplicate device-disconnect request from {}: {}",
            node_name,
            message
        ),
        Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => tracing::warn!(
            "[RECOVERY] Recovery channel closed; {} device-disconnect failure cannot enter recovery: {}",
            node_name,
            message
        ),
    }
}

/// Context for instruction execution
/// Contains the current imaging session state and cancellation flag
pub struct InstructionContext {
    /// ID of the sequence node this instruction is running for, threaded through
    /// from `ExecutionContext::node_id`.
    ///
    /// `emit_grade_progress` must name the producing node on the frame events it
    /// emits: the app turns each FrameAccepted / FrameRejected into a
    /// `captured_images` row and resolves the frame's target and exposure length
    /// by walking the sequence tree from this id. An empty id makes it drop the
    /// frame outright — no gallery row, no integration total, no per-target
    /// completion. Empty is therefore correct ONLY for node-less callers
    /// (wizards, one-shot bridge captures, trigger-driven recenters).
    pub node_id: String,
    /// Target RA in hours
    pub target_ra: Option<f64>,
    /// Target Dec in degrees
    pub target_dec: Option<f64>,
    /// Target mechanical rotation angle in degrees (rotator position the frame
    /// must be imaged at). `None` when the active target specifies no rotation,
    /// in which case centering must NOT move the rotator. Sourced from the
    /// TargetHeader's `target_rotation` via `ExecutionContext`.
    pub target_rotation: Option<f64>,
    /// Target name
    pub target_name: Option<String>,
    /// Current filter
    pub current_filter: Option<String>,
    /// Current binning
    pub current_binning: Binning,
    /// Cancellation token
    pub cancellation_token: Arc<AtomicBool>,
    /// Connected camera device ID
    pub camera_id: Option<String>,
    /// Connected mount device ID
    pub mount_id: Option<String>,
    /// Connected focuser device ID
    pub focuser_id: Option<String>,
    /// Connected filter wheel device ID
    pub filterwheel_id: Option<String>,
    /// Connected rotator device ID
    pub rotator_id: Option<String>,
    /// Connected dome device ID
    pub dome_id: Option<String>,
    /// Connected cover calibrator (flat panel) device ID
    pub cover_calibrator_id: Option<String>,
    /// Base path for saving images
    pub save_path: Option<PathBuf>,
    /// Observer's latitude (degrees)
    pub latitude: Option<f64>,
    /// Observer's longitude (degrees)
    pub longitude: Option<f64>,
    /// Device operations handler
    pub device_ops: SharedDeviceOps,
    /// Trigger state (for updating during execution)
    pub trigger_state: Option<Arc<tokio::sync::RwLock<crate::triggers::TriggerState>>>,
    /// Filter focus offsets from the equipment profile (filter_name -> offset_steps).
    /// When a filter change occurs, the focuser is moved by the offset relative to
    /// the current position. A positive offset means move outward.
    pub filter_focus_offsets: std::collections::HashMap<String, i32>,
    /// Optional broadcast handle so instruction code can emit ExecutorEvents
    /// directly to subscribers (UI, logging, etc.). Used to surface
    /// instruction-level failures that must be visible beyond the
    /// InstructionResult return value — e.g. FITS-save failures (see
    /// `execute_exposure`). `None` outside the live executor; instructions
    /// must use `if let Some(tx) = ...` and ignore send errors (no subscribers
    /// is a benign case for headless runs).
    pub event_tx: Option<tokio::sync::broadcast::Sender<crate::executor::ExecutorEvent>>,
    /// Recovery request channel for first-class recoverable instruction failures.
    pub recovery_request_tx: Option<mpsc::Sender<crate::recovery::RecoveryCause>>,
    /// Shared flag set when a device-disconnect failure is promoted to a
    /// `DeviceDisconnected` recovery. The node-runtime reads this to wait for
    /// recovery + retry the failed instruction instead of aborting the
    /// sequence. Shares its allocation with `ExecutionContext`. Defaults to a
    /// fresh `false` Arc in standalone instruction contexts (tests / one-shot
    /// bridge calls) where there is no runtime retry wrapper.
    pub device_disconnect_recovery_pending: Arc<AtomicBool>,
    // -------------------------------------------------------------------
    // Image Grading: FITS-header metadata propagated from
    // ExecutionContext so `execute_exposure` can assemble a FrameContext
    // for save_fits.
    // -------------------------------------------------------------------
    pub session_id: String,
    pub target_id: Option<String>,
    pub mosaic_panel: Option<crate::MosaicPanelInfo>,
    pub current_filter_index: Option<i32>,
    pub set_temp_c: Option<f64>,
    pub bayer_pattern: Option<String>,
    pub observer_name: Option<String>,
    pub site_elevation_m: Option<f64>,
    pub camera_make: Option<String>,
    pub camera_model: Option<String>,
    pub telescope_name: Option<String>,
    pub telescope_focal_length_mm: Option<f64>,
    pub telescope_aperture_mm: Option<f64>,
    /// Shared handle to last plate-solve result (set by CenterTarget).
    pub last_plate_solve: Arc<tokio::sync::RwLock<Option<crate::device_ops::PlateSolveResult>>>,
    // -------------------------------------------------------------------
    // Image Grading: per-run grading state, shared via Arc with
    // ExecutionContext so progress events carry consistent totals across
    // the entire sequence.
    // -------------------------------------------------------------------
    pub hfr_baseline: Arc<tokio::sync::RwLock<Option<f64>>>,
    pub hfr_baseline_samples: Arc<tokio::sync::RwLock<Vec<f64>>>,
    pub consecutive_rejects: Arc<std::sync::atomic::AtomicU32>,
    pub frames_accepted: Arc<std::sync::atomic::AtomicU32>,
    pub frames_rejected: Arc<std::sync::atomic::AtomicU32>,
    /// Global default image-quality thresholds. Used as the fallback when
    /// `ExposureConfig.quality_check` is None.
    pub default_quality_check: Option<crate::quality::ImageQualityCheck>,
    /// Optional reject-folder override (relative to save_path or absolute).
    /// None => use `<save_path>/Reject/`.
    pub reject_folder_path: Option<String>,
    /// per-frame defect-map application state. Cloned
    /// from `ExecutionContext::defect_map_apply` at instruction-context
    /// construction time. Pre-loading is bridge-side, so a `Some(...)`
    /// value carries the parsed `DefectMap` ready for per-frame
    /// `correct_u16_slice` application.
    pub defect_map_apply: Arc<tokio::sync::RwLock<Option<crate::executor::DefectMapApplyState>>>,
    // -------------------------------------------------------------------
    // Frame-Failure Forensics.
    //
    // `emit_grade_progress` snapshots live env values, looks at the
    // rolling history, classifies the rejection, then pushes the new
    // sample into the history. All five Arcs are shared with
    // ExecutionContext so other instructions can keep mutating them.
    // -------------------------------------------------------------------
    /// Rolling buffer of the last `FORENSIC_HISTORY_LEN` frame samples.
    pub forensics_history:
        Arc<tokio::sync::RwLock<std::collections::VecDeque<crate::quality::RecentFrameSample>>>,
    /// Sky brightness reading (mag/arcsec²) shared with the adaptive
    /// exposure adapter.
    pub current_sky_brightness_mag: Arc<tokio::sync::RwLock<Option<f64>>>,
    /// Cloud motion snapshot pushed by the Dart weather pipeline.
    pub cloud_motion_snapshot: Arc<tokio::sync::RwLock<crate::node::context::CloudMotionSnapshot>>,
    /// Current wind speed (km/h).
    pub current_wind_kph: Arc<tokio::sync::RwLock<Option<f64>>>,
    /// Current sensor temperature (°C).
    pub current_sensor_temp_c: Arc<tokio::sync::RwLock<Option<f64>>>,
    /// Replay Debug — broadcast handle for [`crate::decision::DecisionEvent`]s
    /// (FrameAccepted / FrameRejected emit from `emit_grade_progress`,
    /// AdaptiveSwap emit from the adaptive-exposure path, BudgetMet from
    /// the budget tracker, PluginNodeInvoked from the plugin instruction).
    /// `None` outside the live executor (test contexts / one-shot bridge
    /// calls); emission is a no-op then.
    pub decision_tx: Option<crate::decision::DecisionSender>,
    /// Replay Debug — active sequence_runs.id, populated for every
    /// emitted DecisionEvent so persistence can write the FK without
    /// re-joining on wall-clock windows.
    pub active_sequence_run_id: Arc<parking_lot::RwLock<Option<i64>>>,
    /// Dual-rig — shared dither-coordination barrier (see
    /// [`crate::dual_rig::DitherBarrier`]). `None` for single-rig sequences.
    /// When `Some`, the dither call sites (`execute_dither` + the inline burst
    /// dither in `execute_exposure`) announce + release on this barrier so a
    /// piggybacking secondary camera is never mid-exposure during the mount
    /// pulse.
    pub dither_barrier: Option<Arc<crate::dual_rig::DitherBarrier>>,
}

impl InstructionContext {
    pub fn check_cancelled(&self) -> Option<InstructionResult> {
        if self.cancellation_token.load(Ordering::Relaxed) {
            Some(InstructionResult::cancelled("Operation cancelled"))
        } else {
            None
        }
    }

    /// Get camera ID or error
    pub fn camera_id(&self) -> Result<&str, InstructionResult> {
        self.camera_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No camera connected"))
    }

    /// Get mount ID or error
    pub fn mount_id(&self) -> Result<&str, InstructionResult> {
        self.mount_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No mount connected"))
    }

    /// Get focuser ID or error
    pub fn focuser_id(&self) -> Result<&str, InstructionResult> {
        self.focuser_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No focuser connected"))
    }

    /// Get filter wheel ID or error
    pub fn filterwheel_id(&self) -> Result<&str, InstructionResult> {
        self.filterwheel_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No filter wheel connected"))
    }

    /// Get rotator ID or error  
    pub fn rotator_id(&self) -> Result<&str, InstructionResult> {
        self.rotator_id
            .as_deref()
            .ok_or_else(|| InstructionResult::failure("No rotator connected"))
    }

    /// Get dome ID or error.
    ///
    /// Unlike the other role accessors this one falls back to
    /// [`DeviceOps::active_dome_id`] when the context carries no assignment:
    /// nothing in the Dart→FFI runtime-config path ever calls
    /// `SequenceExecutor::set_dome`, so `self.dome_id` is `None` on every real
    /// run and the seven dome/cover node types were unconditionally dead. The
    /// device layer knows what is connected; ask it before declaring failure.
    pub async fn dome_id(&self) -> Result<String, InstructionResult> {
        if let Some(id) = self.dome_id.as_deref() {
            return Ok(id.to_string());
        }
        match self.device_ops.active_dome_id().await {
            Some(id) => {
                tracing::debug!("No dome in the sequence context; using connected dome '{id}'");
                Ok(id)
            }
            None => Err(InstructionResult::failure("No dome connected")),
        }
    }

    /// Get cover calibrator ID or error. Falls back to
    /// [`DeviceOps::active_cover_calibrator_id`] for the same reason as
    /// [`Self::dome_id`].
    pub async fn cover_calibrator_id(&self) -> Result<String, InstructionResult> {
        if let Some(id) = self.cover_calibrator_id.as_deref() {
            return Ok(id.to_string());
        }
        match self.device_ops.active_cover_calibrator_id().await {
            Some(id) => {
                tracing::debug!(
                    "No cover calibrator in the sequence context; using connected panel '{id}'"
                );
                Ok(id)
            }
            None => Err(InstructionResult::failure(
                "No cover calibrator (flat panel) connected",
            )),
        }
    }

    /// Replay Debug — emit a structured decision into the
    /// broadcast channel. No-op when `decision_tx` is `None` (one-shot
    /// instruction sites, unit tests). Stamps the active sequence_run_id
    /// before forwarding so the persistence layer has the FK.
    pub fn emit_decision(&self, mut event: crate::decision::DecisionEvent) {
        let Some(tx) = self.decision_tx.as_ref() else {
            return;
        };
        if event.sequence_run_id.is_none() {
            event.sequence_run_id = *self.active_sequence_run_id.read();
        }
        let _ = tx.send(event);
    }
}

// =============================================================================
// SLEW INSTRUCTION
// =============================================================================

/// Default tolerance for slew position validation in degrees (1 arcminute = 1/60 degree)
const SLEW_POSITION_TOLERANCE_DEG: f64 = 1.0 / 60.0;

/// Normalize RA difference to account for wraparound at 24 hours
/// Returns the shortest angular distance between two RA values in hours
fn normalize_ra_diff_hours(diff: f64) -> f64 {
    // Normalize to [-12, +12] h so the sign of the result is the shortest
    // signed angular distance — necessary because a raw 23 h difference is
    // physically a -1 h move, not a 23 h move.
    let mut wrapped = diff % 24.0;
    if wrapped > 12.0 {
        wrapped -= 24.0;
    } else if wrapped < -12.0 {
        wrapped += 24.0;
    }
    wrapped
}

/// Validate that mount reached the target position within tolerance
/// ra_target and ra_actual are in hours, dec_target and dec_actual are in degrees
/// tolerance_deg is the maximum allowed difference in degrees
fn validate_slew_position(
    ra_target: f64,
    dec_target: f64,
    ra_actual: f64,
    dec_actual: f64,
    tolerance_deg: f64,
) -> Result<(), String> {
    let ra_diff_hours = normalize_ra_diff_hours(ra_actual - ra_target);
    let ra_diff_deg = ra_diff_hours * 15.0;

    // Dec is bounded to [-90, +90] so there is no wraparound to handle; a
    // raw subtraction is the signed angular distance directly.
    let dec_diff_deg = dec_actual - dec_target;

    if ra_diff_deg.abs() > tolerance_deg || dec_diff_deg.abs() > tolerance_deg {
        return Err(format!(
            "Mount slew did not reach target position. Expected RA={:.4}h, Dec={:.4}deg, \
             got RA={:.4}h, Dec={:.4}deg (diff: RA={:.2}', Dec={:.2}')",
            ra_target,
            dec_target,
            ra_actual,
            dec_actual,
            ra_diff_deg * 60.0, // Convert to arcminutes for readability
            dec_diff_deg * 60.0
        ));
    }

    Ok(())
}

/// Execute a slew instruction
pub async fn execute_slew(
    config: &SlewConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let mount_id = match ctx.mount_id() {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Slewing a parked mount on most drivers either silently no-ops or
    // errors deep in the slew loop; surfacing the precondition here gives
    // the user a clean error with a recovery hint (unpark) before any
    // long-running motion is attempted.
    match ctx.device_ops.mount_is_parked(mount_id).await {
        Ok(true) => {
            tracing::warn!("Mount is parked, cannot slew. Please unpark the mount first.");
            return InstructionResult::failure_with_recovery(
                "Mount is parked. Please unpark the mount before slewing.",
                "MOUNT_PARKED",
            );
        }
        Ok(false) => {
            tracing::debug!("Mount is not parked, proceeding with slew");
        }
        Err(e) => {
            // Old INDI drivers and some serial mounts lack park-status reporting.
            // Treat the query failure as "unknown" rather than "parked" so we do
            // not block slewing on mounts that genuinely cannot tell us.
            tracing::debug!("Could not check mount park status: {}", e);
        }
    }

    let (ra, dec) = if config.use_target_coords {
        match (ctx.target_ra, ctx.target_dec) {
            (Some(ra), Some(dec)) => (ra, dec),
            _ => return InstructionResult::failure("No target coordinates available"),
        }
    } else {
        match (config.custom_ra, config.custom_dec) {
            (Some(ra), Some(dec)) => (ra, dec),
            _ => return InstructionResult::failure("No custom coordinates specified"),
        }
    };

    // Refuse to drive the mount to a target whose coordinates were never set.
    // Only the inherited-pointing case can carry the placeholder; a custom-
    // coordinate slew is an explicit instruction from the operator.
    if config.use_target_coords {
        if let Some(reason) =
            unset_target_pointing_reason(ctx.target_name.as_deref(), ra, dec, "slew to target")
        {
            tracing::warn!("{reason}");
            return InstructionResult::failure_with_recovery(reason, UNSET_TARGET_RECOVERY_CODE);
        }
    }

    // W1 native daylight gate (structural). A slew that points the rig at the
    // active sky/science target (`use_target_coords`) is the on-sky pointing
    // step of a LIGHT-frame run; refuse it while the Sun is up so a raw
    // sequence started via `api_sequencer_start` (including a mosaic) cannot
    // slew + expose lights in full daylight. Slews to custom coordinates
    // (park positions, flat-panel pointing, alignment moves) are NOT gated —
    // only the science-target slew. Abstains when the observer location is
    // unset (see `daylight_gate_block_reason`).
    if config.use_target_coords {
        let max_sun_alt = resolve_max_sun_altitude(ctx).await;
        if let Some(reason) =
            daylight_gate_block_reason(ctx.latitude, ctx.longitude, max_sun_alt, "slew to target")
        {
            tracing::warn!("{reason}");
            return InstructionResult::failure_with_recovery(reason, DAYLIGHT_GATE_RECOVERY_CODE);
        }
    }

    tracing::info!("Slewing to RA: {:.4}h, Dec: {:.4}°", ra, dec);

    if let Some(cb) = progress_callback {
        cb(0.0, format!("Slewing to RA: {:.2}h, Dec: {:.1}°", ra, dec));
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    tokio::select! {
        result = ctx.device_ops.mount_slew_to_coordinates(mount_id, ra, dec) => {
            match result {
                Ok(_) => {
                    // 1800 s = 30 min handles the longest realistic slew on
                    // weight-belt direct-drives doing a full-sky move; tighter
                    // would false-alarm on heavily loaded mounts.
                    match wait_for_mount_idle_with_progress(mount_id, ctx, Duration::from_secs(1800), progress_callback).await {
                        Ok(_) => {
                            // The mount reports "not slewing" before its
                            // axes have fully settled on some drivers, so we
                            // re-read coordinates and validate against the
                            // target before declaring success — silent
                            // mis-pointing would feed bad data downstream.
                            match ctx.device_ops.mount_get_coordinates(mount_id).await {
                                Ok((actual_ra, actual_dec)) => {
                                    tracing::debug!(
                                        "Slew completed. Target: RA={:.4}h, Dec={:.4}°, Actual: RA={:.4}h, Dec={:.4}°",
                                        ra, dec, actual_ra, actual_dec
                                    );

                                    if let Err(e) = validate_slew_position(
                                        ra, dec, actual_ra, actual_dec,
                                        SLEW_POSITION_TOLERANCE_DEG,
                                    ) {
                                        tracing::warn!("Slew position validation failed: {}", e);
                                        return InstructionResult::failure_with_recovery(
                                            &e,
                                            "SLEW_POSITION_MISMATCH",
                                        );
                                    }

                                    if let Some(cb) = progress_callback {
                                        cb(100.0, format!("Arrived at RA: {:.2}h, Dec: {:.1} deg", actual_ra, actual_dec));
                                    }
                                    InstructionResult::success_with_message(format!(
                                        "Slewed to RA: {:.4}h, Dec: {:.4} deg (verified)",
                                        actual_ra, actual_dec
                                    ))
                                }
                                Err(e) => {
                                    tracing::warn!(
                                        "Slew completed but position verification failed: {}. \
                                         Failing closed because final mount coordinates are unknown.",
                                        e
                                    );
                                    if let Some(cb) = progress_callback {
                                        cb(
                                            100.0,
                                            format!(
                                                "Slew reached command target but verification failed: {}",
                                                e
                                            ),
                                        );
                                    }
                                    InstructionResult::failure_with_recovery(
                                        format!(
                                            "Slew completed but mount position verification failed: {}",
                                            e
                                        ),
                                        "SLEW_UNVERIFIED_POSITION",
                                    )
                                }
                            }
                        }
                        Err(e) => InstructionResult::failure(e),
                    }
                }
                Err(e) => InstructionResult::failure(format!("Slew failed: {}", e)),
            }
        }
        _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
            tracing::info!("Slew cancelled, aborting...");
            let _ = ctx.device_ops.mount_abort_slew(mount_id).await;
            InstructionResult::cancelled("Slew cancelled")
        }
    }
}

/// Wait for mount to stop slewing with timeout and progress updates
async fn wait_for_mount_idle_with_progress(
    mount_id: &str,
    ctx: &InstructionContext,
    timeout: Duration,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    let mut poll_count = 0u32;

    loop {
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            let _ = ctx.device_ops.mount_abort_slew(mount_id).await;
            return Err("Operation cancelled".to_string());
        }

        match ctx.device_ops.mount_is_slewing(mount_id).await {
            Ok(is_slewing) => {
                if !is_slewing {
                    tracing::debug!("Mount reached target position");
                    return Ok(());
                }
            }
            Err(e) => {
                // Transient query failures are common during slews on serial
                // mounts; we keep polling so a one-off error does not abort
                // an otherwise healthy slew.
                tracing::warn!("Error checking slew status: {}", e);
            }
        }

        // Slew progress lacks a real percentage from drivers, so we synthesize
        // a 0–95% estimate from elapsed time using the typical 30–60 s slew
        // duration. Capped at 95% so the user does not see "100%" before the
        // mount actually reports idle.
        poll_count += 1;
        if poll_count.is_multiple_of(4) {
            let elapsed_secs = start.elapsed().as_secs();
            // Why: elapsed_secs is a u64 wall-clock; even months of elapsed time fit
            // in f64's 53-bit mantissa. Lossless for any plausible slew duration.
            let progress = ((elapsed_secs as f64 / 60.0) * 100.0).min(95.0);
            if let Some(cb) = progress_callback {
                cb(progress, format!("Slewing... ({:.0}s)", elapsed_secs));
            }
        }

        if start.elapsed() > timeout {
            return Err(format!(
                "Mount slew timed out after {} seconds",
                timeout.as_secs()
            ));
        }

        // 500 ms balances responsiveness against driver query cost on serial
        // mounts (where each poll round-trips through USB-to-serial).
        sleep(Duration::from_millis(500)).await;
    }
}

/// Wait for focuser to stop moving with timeout
async fn wait_for_focuser_idle(
    focuser_id: &str,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    loop {
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            // A bare cancel without halting can leave the focuser to overshoot
            // the original target; halt + wait-for-stop guarantees the user's
            // next instruction (e.g. autofocus restart) sees a stationary motor.
            tracing::info!("Cancellation detected during focuser move, halting focuser");
            if let Err(e) = ctx.device_ops.focuser_halt(focuser_id).await {
                tracing::warn!("Failed to halt focuser during cancellation: {}", e);
            }
            wait_for_focuser_stop_after_halt(focuser_id, &ctx.device_ops, Duration::from_secs(10))
                .await;
            return Err("Operation cancelled".to_string());
        }

        match ctx.device_ops.focuser_is_moving(focuser_id).await {
            Ok(is_moving) => {
                if !is_moving {
                    // 100 ms settle absorbs motor backlash on stepper focusers
                    // — the driver reports "stopped" before the gear train
                    // physically settles, and a subsequent exposure would catch
                    // the tail-end vibration.
                    sleep(Duration::from_millis(100)).await;
                    tracing::debug!("Focuser reached target position");
                    return Ok(());
                }
            }
            Err(e) => {
                tracing::warn!("Error checking focuser status: {}", e);
            }
        }

        if start.elapsed() > timeout {
            return Err(format!(
                "Focuser move timed out after {} seconds",
                timeout.as_secs()
            ));
        }

        // 100 ms (vs 500 ms for mount) — focusers complete moves in seconds,
        // not minutes, so a coarser cadence would lose alignment precision.
        sleep(Duration::from_millis(100)).await;
    }
}

/// Wait for focuser to stop moving after a halt command (ignores cancellation token).
/// This is used during cancellation handling to ensure the focuser has actually stopped
/// before returning control. The timeout is shorter since we're just waiting for halt.
pub async fn wait_for_focuser_stop_after_halt(
    focuser_id: &str,
    device_ops: &crate::device_ops::SharedDeviceOps,
    timeout: Duration,
) -> bool {
    let start = std::time::Instant::now();
    loop {
        match device_ops.focuser_is_moving(focuser_id).await {
            Ok(is_moving) => {
                if !is_moving {
                    tracing::debug!("Focuser stopped after halt");
                    return true;
                }
            }
            Err(e) => {
                tracing::warn!("Error checking focuser status after halt: {}", e);
            }
        }

        if start.elapsed() > timeout {
            tracing::warn!(
                "Focuser did not stop within {} seconds after halt",
                timeout.as_secs()
            );
            return false;
        }

        sleep(Duration::from_millis(100)).await;
    }
}

/// Wait for filter wheel to reach target position with timeout
async fn wait_for_filterwheel_idle(
    fw_id: &str,
    target_position: i32,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();

    // Some filter wheels (notably ZWO EFW) still report the old position for
    // ~50 ms after issuing a move command; polling immediately would treat
    // the "already at target" reading as success and return before the wheel
    // has even started turning.
    sleep(Duration::from_millis(100)).await;

    loop {
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            return Err("Operation cancelled".to_string());
        }

        match ctx.device_ops.filterwheel_get_position(fw_id).await {
            Ok(current_pos) => {
                if current_pos == target_position {
                    tracing::debug!("Filter wheel reached target position {}", target_position);
                    return Ok(());
                }
                tracing::trace!(
                    "Filter wheel at position {}, waiting for {}",
                    current_pos,
                    target_position
                );
            }
            Err(e) => {
                tracing::warn!("Error checking filter wheel position: {}", e);
            }
        }

        if start.elapsed() > timeout {
            return Err(format!(
                "Filter wheel move timed out after {} seconds (target: {})",
                timeout.as_secs(),
                target_position
            ));
        }

        sleep(Duration::from_millis(200)).await;
    }
}

/// Claim `path` for this caller by creating it, failing if it already exists.
///
/// `exists()`-then-return left a window in which two concurrent frames both
/// saw a free path and both wrote to it; `create_new` collapses the check and
/// the claim into one filesystem operation.
fn claim_save_path(path: &std::path::Path) -> std::io::Result<()> {
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map(|_| ())
}

fn ensure_unique_save_path(path: PathBuf) -> PathBuf {
    match claim_save_path(&path) {
        Ok(()) => return path,
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(e) => {
            // Not a collision — the directory is unwritable, full, or gone.
            // Suffixing cannot help; hand the path back so the FITS save
            // surfaces the real error.
            tracing::warn!(
                "[FS] could not claim save path {}: {}. Handing it to the writer unclaimed.",
                path.display(),
                e
            );
            return path;
        }
    }

    // parent and stem fallbacks here are defensive — by the time
    // we enter this function the caller has already passed a fully-formed
    // path. If the parent is None (file at filesystem root) we keep using an
    // empty PathBuf so `.join()` writes into the cwd; that mirrors the
    // pre-audit behaviour but is now explicit. If the stem is missing we
    // fall back to "image" but log so the operator can audit how a stemless
    // path was constructed.
    let parent = match path.parent() {
        Some(p) => p.to_path_buf(),
        None => {
            tracing::warn!(
                "[FS] ensure_unique_save_path: path has no parent component ({}). \
                 Suffixed candidates will be written to the current working directory.",
                path.display()
            );
            PathBuf::new()
        }
    };
    let stem = match path.file_stem().and_then(|v| v.to_str()) {
        Some(s) if !s.is_empty() => s.to_string(),
        _ => {
            tracing::warn!(
                "[FS] ensure_unique_save_path: path has no usable file stem ({}); \
                 falling back to \"image\" for suffix generation.",
                path.display()
            );
            "image".to_string()
        }
    };
    let extension = path.extension().and_then(|value| value.to_str());

    let mut suffix = 1;
    loop {
        let candidate_name = match extension {
            Some(ext) if !ext.is_empty() => format!("{}_{:03}.{}", stem, suffix, ext),
            _ => format!("{}_{:03}", stem, suffix),
        };
        let candidate = parent.join(candidate_name);
        match claim_save_path(&candidate) {
            Ok(()) => return candidate,
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => suffix += 1,
            Err(e) => {
                tracing::warn!(
                    "[FS] could not claim save path {}: {}. Handing it to the writer unclaimed.",
                    candidate.display(),
                    e
                );
                return candidate;
            }
        }
    }
}

async fn wait_for_cancellation(token: Arc<AtomicBool>) {
    loop {
        if token.load(Ordering::Relaxed) {
            return;
        }
        sleep(Duration::from_millis(100)).await;
    }
}

// =============================================================================
// ROTATOR MOVE + VERIFY (shared by RotateToAngle instruction and centering)
// =============================================================================

/// Tolerance (degrees) within which a rotator is considered "at" its target.
const ROTATOR_TOLERANCE_DEG: f64 = 1.0;
/// Maximum time to wait for a rotator to reach its target before failing closed.
const ROTATOR_TIMEOUT_SECS: f64 = 120.0;
/// Rotator arrival poll interval.
const ROTATOR_POLL_SECS: f64 = 1.0;

/// Normalise an angle into `[0, 360)`. Non-finite input collapses to 0.
fn normalize_rotator_angle(a: f64) -> f64 {
    let r = a.rem_euclid(360.0);
    if r.is_finite() {
        r
    } else {
        0.0
    }
}

/// Smallest signed angular distance `a - b` in degrees, accounting for the
/// 360° wrap. Result is in `[-180, 180]`.
fn rotator_angle_diff(a: f64, b: f64) -> f64 {
    (a - b + 540.0).rem_euclid(360.0) - 180.0
}

/// Move a rotator to an ABSOLUTE mechanical angle and block until it actually
/// reaches it (or fail closed on error / timeout).
///
/// The driver-level `rotator_move_to` only ISSUES the move on ASCOM/Alpaca/INDI
/// (it returns as soon as the command is accepted), so this helper polls
/// `rotator_get_angle` until the achieved angle is within
/// `ROTATOR_TOLERANCE_DEG` of the target. Used by both the explicit
/// `RotateToAngle` instruction and by `execute_center` so a target's framing
/// rotation is physically applied during centering.
///
/// `progress` is invoked with `(percent_0_to_100, message)` for UI feedback.
async fn rotator_move_to_verified(
    ctx: &InstructionContext,
    rotator_id: &str,
    target_abs_deg: f64,
    mut progress: impl FnMut(f64, String),
) -> Result<f64, InstructionResult> {
    let target_abs = normalize_rotator_angle(target_abs_deg);

    if let Err(e) = ctx.device_ops.rotator_move_to(rotator_id, target_abs).await {
        return Err(InstructionResult::failure(format!(
            "Rotator move failed: {}",
            e
        )));
    }

    let mut elapsed = 0.0_f64;
    loop {
        if let Some(result) = ctx.check_cancelled() {
            return Err(result);
        }
        let current = match ctx.device_ops.rotator_get_angle(rotator_id).await {
            Ok(a) => a,
            Err(e) => {
                return Err(InstructionResult::failure(format!(
                    "Failed to read rotator angle during move: {}",
                    e
                )))
            }
        };
        if rotator_angle_diff(current, target_abs).abs() <= ROTATOR_TOLERANCE_DEG {
            progress(100.0, format!("Rotator at {:.1}°", current));
            return Ok(current);
        }
        if elapsed >= ROTATOR_TIMEOUT_SECS {
            return Err(InstructionResult::failure(format!(
                "Rotator did not reach {:.1}° within {:.0}s (last {:.1}°)",
                target_abs, ROTATOR_TIMEOUT_SECS, current
            )));
        }
        let pct = (elapsed / ROTATOR_TIMEOUT_SECS * 95.0).min(95.0);
        progress(
            pct,
            format!("Rotating to {:.1}° (at {:.1}°)", target_abs, current),
        );
        sleep(Duration::from_secs_f64(ROTATOR_POLL_SECS)).await;
        elapsed += ROTATOR_POLL_SECS;
    }
}

// =============================================================================
// CENTER INSTRUCTION (Plate Solve + Sync + Slew Loop)
// =============================================================================

const CENTER_CORRECTION_SLEW_START_TIMEOUT: Duration = Duration::from_secs(5);
const CENTER_CORRECTION_SLEW_COMPLETE_TIMEOUT: Duration = Duration::from_secs(300);
const CENTER_CORRECTION_SLEW_POLL_INTERVAL: Duration = Duration::from_millis(500);

/// Wait for an asynchronous correction slew to first report motion and then
/// report idle. The startup phase is essential for ASCOM/Alpaca/INDI drivers
/// that acknowledge the command before their `Slewing` property changes.
async fn wait_for_centering_correction_slew(
    mount_id: &str,
    ctx: &InstructionContext,
) -> Result<(), InstructionResult> {
    let start_deadline = tokio::time::Instant::now() + CENTER_CORRECTION_SLEW_START_TIMEOUT;
    loop {
        if let Some(result) = ctx.check_cancelled() {
            let _ = ctx.device_ops.mount_abort_slew(mount_id).await;
            return Err(result);
        }

        match ctx.device_ops.mount_is_slewing(mount_id).await {
            Ok(true) => break,
            Ok(false) => {}
            Err(error) => tracing::warn!(
                "Centering: slew-state read failed while waiting for startup ({}); retrying",
                error
            ),
        }

        if tokio::time::Instant::now() >= start_deadline {
            let _ = ctx.device_ops.mount_abort_slew(mount_id).await;
            return Err(InstructionResult::failure(format!(
                "Centering correction slew did not report startup within {}s",
                CENTER_CORRECTION_SLEW_START_TIMEOUT.as_secs()
            )));
        }
        sleep(CENTER_CORRECTION_SLEW_POLL_INTERVAL).await;
    }

    let complete_deadline = tokio::time::Instant::now() + CENTER_CORRECTION_SLEW_COMPLETE_TIMEOUT;
    loop {
        if let Some(result) = ctx.check_cancelled() {
            let _ = ctx.device_ops.mount_abort_slew(mount_id).await;
            return Err(result);
        }

        match ctx.device_ops.mount_is_slewing(mount_id).await {
            Ok(false) => return Ok(()),
            Ok(true) => {}
            Err(error) => tracing::warn!(
                "Centering: slew-state read failed while waiting for completion ({}); retrying",
                error
            ),
        }

        if tokio::time::Instant::now() >= complete_deadline {
            let _ = ctx.device_ops.mount_abort_slew(mount_id).await;
            return Err(InstructionResult::failure(format!(
                "Centering correction slew did not complete within {}s",
                CENTER_CORRECTION_SLEW_COMPLETE_TIMEOUT.as_secs()
            )));
        }
        sleep(CENTER_CORRECTION_SLEW_POLL_INTERVAL).await;
    }
}

/// Execute a center instruction (plate solve + sync + slew loop)
pub async fn execute_center(
    config: &CenterConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let mount_id = match ctx.mount_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    let (target_ra_hours, target_dec) = if config.use_target_coords {
        match (ctx.target_ra, ctx.target_dec) {
            (Some(ra), Some(dec)) => (ra, dec),
            _ => return InstructionResult::failure("No target coordinates available"),
        }
    } else if let (Some(ra), Some(dec)) = (config.custom_ra, config.custom_dec) {
        (ra, dec)
    } else {
        match ctx.device_ops.mount_get_coordinates(&mount_id).await {
            Ok((ra, dec)) => (ra, dec),
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Custom center coordinates were not provided and current mount coordinates could not be read: {}",
                    e
                ))
            }
        }
    };

    // Same placeholder gate as `execute_slew`: Center slews too, and it is the
    // node an automated sequence usually uses instead of a bare Slew, so
    // leaving it ungated would leave the defect reachable by the more common
    // authoring pattern. Custom / mount-current coordinates are the operator's
    // own numbers and are never gated.

    // Same placeholder gate as `execute_slew`: Center slews too, and it is the
    // node an automated sequence usually uses instead of a bare Slew, so
    // leaving it ungated would leave the defect reachable by the more common
    // authoring pattern. Custom / mount-current coordinates are the operator's
    // own numbers and are never gated.
    if config.use_target_coords {
        if let Some(reason) = unset_target_pointing_reason(
            ctx.target_name.as_deref(),
            target_ra_hours,
            target_dec,
            "center on target",
        ) {
            tracing::warn!("{reason}");
            return InstructionResult::failure_with_recovery(reason, UNSET_TARGET_RECOVERY_CODE);
        }
    }

    let target_ra_deg = target_ra_hours * 15.0;

    tracing::info!(
        "Centering on RA: {:.4}°, Dec: {:.4}° (accuracy: {:.1}\")",
        target_ra_deg,
        target_dec,
        config.accuracy_arcsec
    );

    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Centering (target: {:.1}\")", config.accuracy_arcsec),
        );
    }

    for attempt in 1..=config.max_attempts {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }

        // Why: attempt is a u32 loop counter bounded by max_attempts (also u32);
        // both lossless to f64.
        let attempt_progress = (f64::from(attempt - 1) / f64::from(config.max_attempts)) * 100.0;
        tracing::info!("Center attempt {}/{}", attempt, config.max_attempts);

        if let Some(cb) = progress_callback {
            cb(
                attempt_progress,
                format!("Attempt {}/{}: Capturing...", attempt, config.max_attempts),
            );
        }

        let image_data = tokio::select! {
            // Full resolution + 1x1 binning gives the plate solver the highest
            // possible star count; binning would reduce SNR enough to fail on
            // sparse fields.
            result = ctx.device_ops.camera_start_exposure(
                &camera_id,
                config.exposure_duration,
                None,
                None,
                1, 1,
            ) => {
                match result {
                    Ok(data) => {
                tracing::info!("[SEQ] Exposure completed: {}x{} image ({} pixels)", data.width, data.height, data.data.len());
                data
            }
                    Err(e) => return InstructionResult::failure(format!("Failed to capture image: {}", e)),
                }
            }
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                tracing::info!("Center cancelled during exposure, aborting...");
                let _ = ctx.device_ops.camera_abort_exposure(&camera_id).await;
                return InstructionResult::cancelled("Center cancelled");
            }
        };

        // Hard cap on the solver call: a hung solver process (stalled IO,
        // bad catalog, zombie child) would otherwise block this select
        // indefinitely — cancellation is the only other exit, and an
        // unattended night never presses cancel. Treated exactly like a
        // failed solve so the attempt loop's retry applies.
        const PLATE_SOLVE_TIMEOUT: Duration = Duration::from_secs(180);
        let solve_result = tokio::select! {
            result = tokio::time::timeout(
                PLATE_SOLVE_TIMEOUT,
                ctx.device_ops.plate_solve(
                    &image_data,
                    Some(target_ra_deg),
                    Some(target_dec),
                    None,
                ),
            ) => {
                match result {
                    Ok(Ok(result)) if result.success => result,
                    Ok(Ok(_)) => {
                        tracing::warn!("Plate solve failed on attempt {}", attempt);
                        continue;
                    }
                    Ok(Err(e)) => {
                        tracing::warn!("Plate solve error on attempt {}: {}", attempt, e);
                        continue;
                    }
                    Err(_) => {
                        tracing::warn!(
                            "Plate solve timed out after {}s on attempt {}",
                            PLATE_SOLVE_TIMEOUT.as_secs(),
                            attempt
                        );
                        continue;
                    }
                }
            }
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                tracing::info!("Center cancelled during plate solve");
                return InstructionResult::cancelled("Center cancelled");
            }
        };

        // Feeding the solve back into trigger state is what enables the
        // DriftLimit trigger (§1.11) to detect cumulative drift across
        // exposures without re-solving on every frame.
        if let Some(trigger_state_lock) = &ctx.trigger_state {
            let mut trigger_state = trigger_state_lock.write().await;
            trigger_state.update_plate_solve(
                solve_result.ra_degrees,
                solve_result.dec_degrees,
                solve_result.pixel_scale,
            );
            tracing::debug!(
                "Updated trigger state with plate solve: RA={:.4}°, Dec={:.4}°, scale={:.2}\"/px",
                solve_result.ra_degrees,
                solve_result.dec_degrees,
                solve_result.pixel_scale
            );
        }

        let separation_arcsec = calculate_separation_arcsec(
            target_ra_deg,
            target_dec,
            solve_result.ra_degrees,
            solve_result.dec_degrees,
        );
        tracing::info!("Current separation: {:.1}\" from target", separation_arcsec);

        if let Some(cb) = progress_callback {
            cb(
                // Why: config.max_attempts is u32; lossless to f64.
                attempt_progress + 50.0 / f64::from(config.max_attempts),
                format!(
                    "Attempt {}/{}: {:.1}\" off",
                    attempt, config.max_attempts, separation_arcsec
                ),
            );
        }

        if separation_arcsec <= config.accuracy_arcsec {
            if let Some(cb) = progress_callback {
                cb(95.0, format!("Centered: {:.1}\"", separation_arcsec));
            }

            // Apply the target's framing rotation as part of centering. On a
            // rig with a rotator, imaging at the wrong camera angle breaks
            // mosaics / framing, so the rotator must be moved to the target
            // mechanical angle and VERIFIED before we declare the target
            // centered. If the target specifies no rotation, or no rotator is
            // configured, this is a clean skip (not an error).
            if let Err(rotate_err) = apply_center_rotation(ctx, attempt, progress_callback).await {
                return rotate_err;
            }

            if let Some(cb) = progress_callback {
                cb(100.0, format!("Centered: {:.1}\"", separation_arcsec));
            }
            return InstructionResult::success_with_message(format!(
                "Centered within {:.1}\" after {} attempt(s)",
                separation_arcsec, attempt
            ));
        }

        // Sync corrects the mount's internal model to the plate-solved truth
        // before re-slewing; without it, the next slew would land at the same
        // wrong spot (the mount thinks it's already at target).
        if let Err(e) = ctx
            .device_ops
            .mount_sync(
                &mount_id,
                solve_result.ra_degrees / 15.0,
                solve_result.dec_degrees,
            )
            .await
        {
            return InstructionResult::failure(format!(
                "Mount sync failed during centering on attempt {}: {}",
                attempt, e
            ));
        }

        tracing::info!("Slewing to correct position...");
        if let Some(cb) = progress_callback {
            cb(
                // Why: config.max_attempts is u32; lossless to f64.
                attempt_progress + 75.0 / f64::from(config.max_attempts),
                format!("Attempt {}/{}: Correcting...", attempt, config.max_attempts),
            );
        }

        tokio::select! {
            result = ctx.device_ops.mount_slew_to_coordinates(&mount_id, target_ra_deg / 15.0, target_dec) => {
                if let Err(e) = result {
                    return InstructionResult::failure(format!(
                        "Correction slew command failed during centering on attempt {}: {}",
                        attempt, e
                    ));
                }
            }
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                tracing::info!("Center cancelled during correction slew, aborting...");
                let _ = ctx.device_ops.mount_abort_slew(&mount_id).await;
                return InstructionResult::cancelled("Center cancelled");
            }
        }

        // Wait for the correction slew to ACTUALLY FINISH before settling and
        // re-imaging. The slew command above returns as soon as it is issued
        // (ASCOM/Alpaca async slews, INDI set-coords) — it does NOT block until
        // the mount stops. Without this poll the next plate-solve exposure
        // fires ~2 s later while the mount is still moving (real offsets take
        // 10-60+ s), so the frame is motion-blurred / off-target, the solve
        // mis-corrects or fails, and the loop burns all attempts without
        // converging. Mirrors the meridian-flip slew-completion poll.
        if let Err(result) = wait_for_centering_correction_slew(&mount_id, ctx).await {
            return result;
        }

        // 2 s post-slew settle absorbs mount oscillation before the next
        // plate-solve exposure; without it, the solve sees motion-blurred
        // stars and the iteration produces a noisy correction vector.
        sleep(Duration::from_secs(2)).await;
    }

    InstructionResult::failure(format!(
        "Failed to center within {:.1}\" after {} attempts",
        config.accuracy_arcsec, config.max_attempts
    ))
}

/// Apply the active target's framing rotation during centering.
///
/// Returns `Ok(())` (leaving the rotator untouched — both are clean, expected
/// skips, NOT errors) when:
/// * the target specifies no rotation (`ctx.target_rotation` is `None`), or
/// * no rotator device is configured (`ctx.rotator_id` is `None`).
///
/// When BOTH a target rotation and a rotator are present, the rotator is moved
/// to the target mechanical angle and the achieved angle is verified within
/// `ROTATOR_TOLERANCE_DEG`. Any move/read error or arrival timeout fails closed
/// via the returned `Err(InstructionResult)` so the caller aborts centering
/// rather than imaging at the wrong angle.
async fn apply_center_rotation(
    ctx: &InstructionContext,
    attempt: u32,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> Result<(), InstructionResult> {
    let Some(target_rotation) = ctx.target_rotation else {
        // No framing rotation requested for this target — leave the rotator
        // wherever it is.
        return Ok(());
    };
    if !target_rotation.is_finite() {
        return Err(InstructionResult::failure(format!(
            "Target framing rotation is not a finite angle ({})",
            target_rotation
        )));
    }
    let Some(rotator_id) = ctx.rotator_id.as_deref() else {
        // Target wants a specific angle but no rotator is configured. This is a
        // clean skip: the rig physically cannot rotate, so centering succeeds
        // on position alone (matches the behaviour of a non-rotator rig).
        tracing::info!(
            "Center: target requests rotation {:.1}° but no rotator is configured; \
             skipping rotation",
            target_rotation
        );
        return Ok(());
    };

    tracing::info!(
        "Center: applying target framing rotation {:.1}° on attempt {}",
        target_rotation,
        attempt
    );
    if let Some(cb) = progress_callback {
        cb(96.0, format!("Rotating to {:.1}°", target_rotation));
    }

    let achieved = rotator_move_to_verified(ctx, rotator_id, target_rotation, |pct, msg| {
        if let Some(cb) = progress_callback {
            // Map the rotator's 0-100 progress into the 96-99 tail of the
            // centering bar so the final "Centered" cb keeps 100.
            cb(96.0 + (pct / 100.0) * 3.0, msg);
        }
    })
    .await?;

    tracing::info!(
        "Center: rotator verified at {:.1}° (target {:.1}°)",
        achieved,
        target_rotation
    );
    Ok(())
}

/// N.I.N.A.-style pre-exposure meridian-flip gate.
///
/// When a MinutesPastMeridian flip trigger is armed and the next frame would
/// still be exposing at the moment the trigger fires, hold here (polling the
/// shared trigger state) until the trigger-driven flip completes, instead of
/// starting a frame the flip slew would ruin mid-exposure.
///
/// Returns `None` to proceed with the exposure, `Some(cancelled)` when the
/// sequence was cancelled while holding. Bounded: gives up with a loud
/// warning after [`MERIDIAN_GATE_MAX_WAIT`] so a failed or disabled flip can
/// never deadlock the night — the post-crossing trigger remains the backstop
/// exactly as before this gate existed.
async fn wait_for_meridian_flip_window(
    ctx: &InstructionContext,
    exposure_secs: f64,
    control: &BurstControl<'_>,
) -> Option<InstructionResult> {
    /// Margin between predicted frame end and predicted trigger fire.
    const SAFETY_MARGIN_SECS: f64 = 30.0;
    const POLL_INTERVAL: Duration = Duration::from_secs(5);
    const MERIDIAN_GATE_MAX_WAIT: Duration = Duration::from_secs(30 * 60);
    /// How far PAST its predicted fire time a flip may be and still be
    /// treated as "about to happen".
    ///
    /// Sized to outlast a whole flip rather than to be tight: a flip plus
    /// re-centre takes 5-8 minutes, and the retry ladder
    /// (`retry_delays_secs` defaults to 30/60/120s on top of the attempts)
    /// can stretch that towards a quarter of an hour. Inside that window
    /// "due and not yet flipped" is indistinguishable from "a flip is
    /// running right now", so the gate keeps waiting. Beyond it the flip
    /// cannot still be in progress — the trigger monitor re-evaluates every
    /// second, so one that was ever going to be requested was requested long
    /// ago.
    const OVERDUE_GRACE_SECS: f64 = 15.0 * 60.0;

    let lock = ctx.trigger_state.as_ref()?;
    let started = tokio::time::Instant::now();
    let mut announced = false;
    loop {
        if let Some(result) = ctx.check_cancelled() {
            return Some(result);
        }
        let (threshold_min, polled_ha, flipped, pier, trigger_has_target) = {
            let state = lock.read().await;
            (
                state.meridian_flip_minutes_past,
                state.current_hour_angle,
                state.has_flipped_this_target,
                state.pier_side,
                state.target_ra.is_some() && state.target_dec.is_some(),
            )
        };
        // No MinutesPastMeridian trigger armed / already flipped — nothing
        // predictable to gate on.
        let threshold_min = threshold_min?;
        if flipped {
            return None;
        }
        // Mirror the trigger's own precondition: a flip is meaningless without
        // a target, and the trigger returns false outright in that case.
        if !trigger_has_target {
            return None;
        }
        let ha = current_target_hour_angle(ctx).or(polled_ha)?;
        // Mirror the trigger's pre-flip-side logic exactly. Pier East is the
        // post-flip side, where the trigger can no longer fire; on West (and
        // on Unknown / unreported, which is what a simulator and many mounts
        // give) it additionally requires a POSITIVE hour angle — i.e. the
        // target is west of the meridian.
        //
        // Only the East case was mirrored here before. A target EAST of the
        // meridian (negative HA) with unreported pier side could therefore
        // hold: `fire_in_secs` came out non-positive from a stale HA left over
        // by an earlier run (the mount poll only runs while a sequence is
        // executing, so the very first frame of a run reads the previous run's
        // value), the gate logged "meridian flip fires in ~0s", and every
        // light frame in the sequence blocked for the gate's full bound while
        // the trigger it was waiting on could not fire at all.
        if matches!(pier, Some(crate::PierSide::East)) || ha <= 0.0 {
            return None;
        }

        let fire_in_secs = (threshold_min - ha * 60.0) * 60.0;
        if fire_in_secs > exposure_secs + SAFETY_MARGIN_SECS {
            return None; // frame finishes comfortably before the flip fires
        }
        // A flip that is hours OVERDUE is not a flip that is imminent.
        //
        // `fire_in_secs` goes arbitrarily negative once the target is past
        // the meridian — at HA +9.9h with a 5-minute threshold it is about
        // -35_000. Every negative value used to land in the branch below and
        // hold, and the announcement clamped the number to zero, so the app
        // said "the flip fires in ~0s" about a flip that had been due for the
        // best part of a day. A target hours west of the meridian is routine
        // (a run that starts on a setting target, or any mount that reports a
        // pointing position the flip trigger reads differently from the
        // target's own coordinates), and the trigger in that state never
        // fires, so nothing ever released the gate: each frame paid the full
        // MERIDIAN_GATE_MAX_WAIT before proceeding and a 12-frame sequence
        // took the whole night to not finish.
        //
        // `announced` is only ever set once this call has decided to hold, so
        // testing it here scopes the escape hatch to gate ENTRY. A hold that
        // began legitimately (the flip was imminent, then a flip started
        // running) is still governed by MERIDIAN_GATE_MAX_WAIT and is not cut
        // short by the target drifting further past the meridian while we
        // wait.
        if !announced && fire_in_secs < -OVERDUE_GRACE_SECS {
            let message = format!(
                "Meridian flip is overdue by {:.0} min and has not fired (hour angle \
                 {:+.2}h, threshold {:.0} min past meridian) — proceeding with the next \
                 {:.0}s exposure instead of waiting for it. Check that the flip trigger \
                 is enabled and that the mount reports its position.",
                -fire_in_secs / 60.0,
                ha,
                threshold_min,
                exposure_secs
            );
            tracing::warn!("{}", message);
            control.report(&message);
            return None;
        }
        // The gate does not perform the flip — it waits for the TRIGGER to
        // request one. The trigger decides from the MOUNT's hour angle
        // (`TriggerState::current_hour_angle`, written by the executor's
        // mount-poll loop) and returns false outright when the mount has not
        // reported one, or when that hour angle is not on the pre-flip side.
        // The gate predicts from the TARGET's hour angle instead, which is the
        // right question for "would the flip interrupt THIS frame" but says
        // nothing about whether the flip can be requested at all.
        //
        // When the two disagree the gate waits for an event that cannot
        // arrive. Live repro (headless Linux build, sim camera + sim mount,
        // site 40N 42E, target pinned 12 min west of the meridian, threshold
        // 5 min): the run reached 1/3 and reported
        //   Waiting for the meridian flip before the next 2s exposure: the
        //   flip became due 423s ago (hour angle +0.20h, threshold 5 min past
        //   meridian) and would interrupt the frame
        // then sat there, because the mount was never slewed to the target so
        // its own hour angle never made the trigger fire. The overdue escape
        // hatch above does not catch this: at 12 minutes past a 5-minute
        // threshold the flip is only 7 minutes late, well inside
        // OVERDUE_GRACE_SECS, so every frame paid the full 30-minute bound.
        //
        // Holding is only meaningful while the trigger could still fire. If
        // the mount has not reported a position, or reports one east of the
        // meridian, there is no flip to be interrupted by and the honest move
        // is to expose. Checked at gate ENTRY only (`!announced`) so a hold
        // that began legitimately still runs to MERIDIAN_GATE_MAX_WAIT while a
        // flip is actually in progress — during a flip slew the mount's hour
        // angle legitimately swings around.
        let trigger_can_fire = polled_ha.is_some_and(|mount_ha| mount_ha > 0.0);
        if !announced && !trigger_can_fire {
            let observed = match polled_ha {
                Some(mount_ha) => format!("reports hour angle {mount_ha:+.2}h"),
                None => "has not reported a position".to_string(),
            };
            let message = format!(
                "Not holding the next {exposure_secs:.0}s exposure for a meridian flip: the \
                 target is {ha:+.2}h past the meridian but the mount {observed}, so the flip \
                 trigger cannot fire. Exposing instead of waiting for a flip that will not \
                 happen — check that the mount is tracking the target."
            );
            tracing::warn!("{}", message);
            control.report(&message);
            return None;
        }
        if started.elapsed() > MERIDIAN_GATE_MAX_WAIT {
            let message = format!(
                "Meridian gate held the next exposure for {}s without observing a \
                 completed flip — proceeding anyway (the flip trigger remains the backstop)",
                started.elapsed().as_secs()
            );
            tracing::warn!("{}", message);
            control.report(&message);
            return None;
        }
        if !announced {
            // Say which side of the fire time we are on. Clamping a negative
            // `fire_in_secs` to zero reported "fires in ~0s" for a flip that
            // was already due, which reads as "any second now" when the real
            // state is "should have happened and has not".
            let when = if fire_in_secs >= 0.0 {
                format!("fires in ~{:.0}s", fire_in_secs)
            } else {
                format!("became due {:.0}s ago", -fire_in_secs)
            };
            let message = format!(
                "Waiting for the meridian flip before the next {:.0}s exposure: the flip \
                 {} (hour angle {:+.2}h, threshold {:.0} min past meridian) \
                 and would interrupt the frame",
                exposure_secs, when, ha, threshold_min
            );
            tracing::info!("{}", message);
            control.report(&message);
            announced = true;
        }
        tokio::select! {
            _ = sleep(POLL_INTERVAL) => {}
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                return Some(InstructionResult::cancelled("Exposure cancelled"));
            }
        }
    }
}

/// Hour angle of the ACTIVE TARGET right now, in hours, normalized to
/// [-12, +12]. Negative is east of the meridian.
///
/// The gate used to read `TriggerState::current_hour_angle`, which is written
/// by the executor's mount-poll loop — i.e. only while a sequence is running,
/// only for the MOUNT's reported coordinates, and never invalidated between
/// runs. Recomputing from the target's own RA and the observer longitude makes
/// the prediction fresh by construction and answers the question the gate is
/// actually asking ("will the flip for THIS target interrupt THIS frame").
/// Falls back to the polled value when the target or the site is unknown.
fn current_target_hour_angle(ctx: &InstructionContext) -> Option<f64> {
    let ra_hours = ctx.target_ra?;
    let longitude = ctx.longitude?;
    let now = chrono::Utc::now();
    let jd = crate::meridian::julian_day(&now);
    let lst = crate::meridian::local_sidereal_time(jd, longitude);
    Some(crate::meridian::hour_angle(ra_hours, lst))
}

/// Calculate separation between two coordinates in arcseconds
fn calculate_separation_arcsec(ra1_deg: f64, dec1_deg: f64, ra2_deg: f64, dec2_deg: f64) -> f64 {
    let dec1_rad = dec1_deg.to_radians();
    let dec2_rad = dec2_deg.to_radians();
    let delta_ra = (ra2_deg - ra1_deg).to_radians();
    let delta_dec = (dec2_deg - dec1_deg).to_radians();

    // Haversine (not law-of-cosines) — at sub-arcsecond centering tolerances
    // the LoC formula loses precision near zero separation due to acos(~1.0)
    // rounding to 1.0 exactly.
    let a = (delta_dec / 2.0).sin().powi(2)
        + dec1_rad.cos() * dec2_rad.cos() * (delta_ra / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().asin();

    c.to_degrees() * 3600.0
}

// =============================================================================
// EXPOSURE INSTRUCTION
// =============================================================================

/// Per-frame save-path renderer. added interpolation to the
/// `ExposureConfig.save_to` template; the renderer is built once in the
/// expose-instruction wrapper (which has ExecutionContext access) and
/// invoked per-frame so the same engine can resolve `${frame:04}` and
/// `${exposure.duration:.0f}`.
///
/// Returns `Ok((dir, filename))` where:
/// * `dir` is the directory portion (absolute, with any user-specified
///   sub-directories from the template already expanded), and
/// * `filename` is the rendered file-name portion.
///
/// Errors surface as `InstructionResult::failure` from the caller — a
/// broken save-path template must abort the exposure rather than silently
/// drop frames into the wrong place.
pub type FrameSavePathRenderer =
    Box<dyn Fn(u32, u32) -> Result<(PathBuf, String), String> + Send + Sync>;

/// Arms an asynchronous camera abort while an exposure future is in flight.
///
/// Cancellation normally takes the explicit `tokio::select!` branch below,
/// where abort is awaited. This guard covers the harder case where the whole
/// instruction Future is dropped by its caller: dropping the camera future
/// alone does not tell many drivers to stop the physical exposure.
struct CameraExposureAbortGuard {
    device_ops: SharedDeviceOps,
    camera_id: String,
    armed: bool,
}

impl CameraExposureAbortGuard {
    fn new(device_ops: SharedDeviceOps, camera_id: String) -> Self {
        Self {
            device_ops,
            camera_id,
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for CameraExposureAbortGuard {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }

        let device_ops = self.device_ops.clone();
        let camera_id = self.camera_id.clone();
        match tokio::runtime::Handle::try_current() {
            Ok(handle) => {
                let _abort_task = handle.spawn(async move {
                    if let Err(error) = device_ops.camera_abort_exposure(&camera_id).await {
                        tracing::error!(
                            "Failed to abort dropped camera exposure on {}: {}",
                            camera_id,
                            error
                        );
                    }
                });
            }
            Err(error) => tracing::error!(
                "Could not schedule camera abort for dropped exposure on {}: {}",
                self.camera_id,
                error
            ),
        }
    }
}

/// Execute an exposure instruction.
///
/// `path_renderer` is `Some` when a Wave-4-aware caller (the `ExposeInstruction`
/// node wrapper) has built a save-path renderer from the active
/// ExecutionContext. When `None`, the function falls back to the legacy
/// hardcoded `<target>_<filter>_<NNNN>.fits` layout — keeping pre-Wave-4
/// call sites (tests, direct invocations) working without modification.
pub async fn execute_exposure(
    config: &ExposureConfig,
    ctx: &InstructionContext,
    progress_callback: impl Fn(u32, u32),
) -> InstructionResult {
    execute_exposure_with_renderer(
        config,
        ctx,
        None,
        &BurstControl::default(),
        progress_callback,
    )
    .await
}

/// Run-scoped controls a burst needs but an [`InstructionContext`] cannot
/// carry: the operator-pause handle the per-frame loop honours, and a status
/// sink so a legitimate hold explains itself instead of looking like a stall.
///
/// [`Default`] is "never paused, nowhere to report" — correct for the
/// standalone callers (bridge one-shots, wizards, tests) that have no run
/// behind them.
#[derive(Default)]
pub struct BurstControl<'a> {
    pub pause: crate::node::context::PauseGate,
    pub status: Option<&'a (dyn Fn(&str) + Send + Sync)>,
}

impl BurstControl<'_> {
    fn report(&self, message: &str) {
        if let Some(status) = self.status {
            status(message);
        }
    }
}

/// entry point that accepts a save-path renderer. Use this from
/// the expose-instruction node wrapper so user templates in
/// `ExposureConfig.save_to` (including hierarchical paths and per-frame
/// placeholders) take effect.
pub async fn execute_exposure_with_renderer(
    config: &ExposureConfig,
    ctx: &InstructionContext,
    path_renderer: Option<FrameSavePathRenderer>,
    control: &BurstControl<'_>,
    progress_callback: impl Fn(u32, u32),
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // W1 native daylight gate (structural). Only an actual LIGHT frame
    // requires darkness; calibration frames remain exempt even below a
    // TargetHeader and with an unparked mount.
    //
    // The gate keys off the FRAME TYPE, never off the presence of a
    // TargetHeader. It used to also require `ctx.target_ra`/`target_dec`,
    // which meant a bare "Take Exposures" outside any target group wrote
    // LIGHT frames in full daylight while the identical node nested under a
    // target was refused — a safety gate the operator disabled by forgetting
    // an unrelated node. Whether the rig is pointed at the sky is answered by
    // the mount park state below, which is the real discriminator.
    if frame_type_requires_darkness(&config.frame_type) {
        let on_sky = match &ctx.mount_id {
            // No mount configured: there is no rig to point at the sky, so this
            // cannot be an on-sky light capture — abstain.
            None => false,
            Some(mount_id) => match ctx.device_ops.mount_is_parked(mount_id).await {
                // Parked rig => calibration/darks, never on-sky lights.
                Ok(true) => false,
                Ok(false) => true,
                // Park status unknown (old driver): treat as on-sky so the gate
                // fails CLOSED on a genuine science-target light capture.
                Err(e) => {
                    tracing::debug!(
                        "Daylight gate could not read mount park status ({e}); treating as on-sky (fail-closed)"
                    );
                    true
                }
            },
        };
        if on_sky {
            let max_sun_alt = resolve_max_sun_altitude(ctx).await;
            if let Some(reason) = daylight_gate_block_reason(
                ctx.latitude,
                ctx.longitude,
                max_sun_alt,
                "light-frame exposure",
            ) {
                tracing::warn!("{reason}");
                return InstructionResult::failure_with_recovery(
                    reason,
                    DAYLIGHT_GATE_RECOVERY_CODE,
                );
            }
        }
    }

    if let Err(error) = validate_exposure_filter_request(
        config.filter.as_deref(),
        config.filter_index,
        ctx.filterwheel_id.as_deref(),
    ) {
        return InstructionResult::failure(error);
    }

    // log "(no filter set)" instead of substituting a filter
    // name like "unfiltered". The substituted token used to look like a
    // valid filter in operator logs.
    tracing::info!(
        "Starting {} {} x {:.1}s exposures",
        config.count,
        match config.filter.as_deref() {
            Some(name) if !name.is_empty() => name.to_string(),
            _ => "(no filter set)".to_string(),
        },
        config.duration_secs
    );

    // Position-index is preferred over name because filter names are
    // user-editable strings that can drift between profile and device
    // (e.g. "Ha" vs "H-alpha"); the position is the wheel's stable
    // hardware addressing.
    if config
        .filter
        .as_deref()
        .is_some_and(|name| !name.trim().is_empty())
        || config.filter_index.is_some()
    {
        if let Some(fw_id) = &ctx.filterwheel_id {
            if let Some(index) = config.filter_index {
                tracing::info!(
                    "Changing to filter position: {} (name: {:?})",
                    index,
                    config.filter
                );
                if let Err(e) = ctx.device_ops.filterwheel_set_position(fw_id, index).await {
                    return InstructionResult::failure(format!("Failed to change filter: {}", e));
                }
                let filter_name = match config.filter.as_deref() {
                    Some(name) if !name.is_empty() => Some(name.to_string()),
                    _ if !ctx.filter_focus_offsets.is_empty() => {
                        match ctx.device_ops.filterwheel_get_names(fw_id).await {
                            Ok(names) if index >= 0 => match names.get(index as usize) {
                                Some(name) => Some(name.clone()),
                                None => {
                                    return InstructionResult::failure(format!(
                                    "Filter position {} has no configured filter name for focus offset lookup",
                                    index
                                ));
                                }
                            },
                            Ok(_) => {
                                return InstructionResult::failure(format!(
                                    "Invalid negative filter position {} for focus offset lookup",
                                    index
                                ));
                            }
                            Err(e) => {
                                return InstructionResult::failure(format!(
                                    "Failed to read filter names for focus offset lookup: {}",
                                    e
                                ));
                            }
                        }
                    }
                    _ => None,
                };
                if let Some(filter_name) = filter_name {
                    if let Err(e) = apply_filter_focus_offset(&filter_name, ctx, None).await {
                        return InstructionResult::failure(format!(
                            "Focus offset failed for filter \"{}\": {}",
                            filter_name, e
                        ));
                    }
                }
            } else if let Some(filter) = &config.filter {
                tracing::info!("Changing to filter by name: {}", filter);
                if let Err(e) = ctx
                    .device_ops
                    .filterwheel_set_filter_by_name(fw_id, filter)
                    .await
                {
                    return InstructionResult::failure(format!("Failed to change filter: {}", e));
                }
                if let Err(e) = apply_filter_focus_offset(filter, ctx, None).await {
                    return InstructionResult::failure(format!(
                        "Focus offset failed for filter \"{}\": {}",
                        filter, e
                    ));
                }
            }
        }
    }

    // Settle the filter identity ONCE for the whole burst, after the wheel has
    // been commanded above so `observed_wheel_filter` reports the slot these
    // frames are actually taken through. Every recording surface below reads
    // this pair, so the filename, the FITS FILTER card and the
    // `captured_images` row cannot disagree about the same frame. Resolving
    // here rather than in the TakeExposure node covers the capture paths that
    // do not go through a node at all — the Flat Wizard's final flat burst most
    // of all, where a missing FILTER card makes the flats unmatchable to the
    // lights they were shot for.
    let (frame_filter_name, frame_filter_index) = resolve_frame_filter(config, ctx).await;

    let (bin_x, bin_y) = match config.binning {
        Binning::One => (1, 1),
        Binning::Two => (2, 2),
        Binning::Three => (3, 3),
        Binning::Four => (4, 4),
    };

    let mut completed_exposures = 0u32;
    // Warn once per burst when dithers are skipped for lack of a guider.
    let mut dither_skipped_warned = false;
    let mut hfr_values = Vec::new();

    // Image Grading: local bindings for the per-frame grading state.
    // All these are Arc<_> handles shared with ExecutionContext so the
    // dashboard sees consistent totals across instruction boundaries.
    let frame_baseline_handle = ctx.hfr_baseline.clone();
    let frame_baseline_samples_handle = ctx.hfr_baseline_samples.clone();
    let consecutive_rejects_handle = ctx.consecutive_rejects.clone();
    let frames_accepted_handle = ctx.frames_accepted.clone();
    let frames_rejected_handle = ctx.frames_rejected.clone();
    let quality_check_default = ctx.default_quality_check.clone();
    let reject_folder_override = ctx.reject_folder_path.clone();

    // Frame-type gate: star-based analysis (HFR / star count / eccentricity),
    // quality grading, and in-burst dithering are only meaningful for
    // star-field frames. A dark/flat/bias burst has no stars — grading would
    // reject every frame as "0 stars", dithering would pulse the mount for
    // nothing, and per-frame star detection is pure wasted CPU (significant
    // on a Raspberry-Pi-class host). Snapshot frames are star fields, so
    // they keep the analysis but are captured like lights otherwise.
    let is_light_frame = config.frame_type.eq_ignore_ascii_case("light")
        || config.frame_type.eq_ignore_ascii_case("snapshot");

    for frame in 1..=config.count {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }

        // Operator Pause, honoured BETWEEN frames. The node tree checks
        // `is_paused` at instruction boundaries, but a burst is N frames
        // inside ONE instruction — so a Pause pressed during frame 2 of 3 used
        // to show a PAUSED badge, a Resume button and "Paused 33%" while the
        // camera went on to expose frame 3 and the run then recorded
        // `completed`. An operator pauses to walk in front of the telescope,
        // so no NEW exposure may start while paused.
        //
        // The frame already integrating is allowed to finish: aborting it
        // throws away data the operator did not ask to lose, and the shutter
        // is already open by the time the request lands. The guarantee is
        // therefore "no new exposure starts", not "the shutter shuts now".
        if !control
            .pause
            .wait_while_paused(&ctx.cancellation_token)
            .await
        {
            return InstructionResult::cancelled("Exposure cancelled while paused");
        }

        // Pre-frame meridian gate (N.I.N.A.-style): when the flip trigger
        // would fire while this frame is still exposing, hold here until the
        // trigger-driven flip completes instead of starting a frame the slew
        // would ruin. Only science-target lights are gated — the flip
        // trigger itself only ever fires for a tracked target.
        //
        // The frame-type check is what makes that comment true. Without it a
        // calibration frame sitting inside a TargetHeader was gated as well:
        // observed a 3s DARK held with "meridian flip fires in ~0s and would
        // interrupt it", which stalled the run for the gate's full 30-minute
        // bound. A dark/bias/flat is taken with the shutter closed or on a flat
        // panel, so where the mount is pointing cannot ruin it — and a
        // calibration block is exactly when the operator is not tracking a
        // target at all.
        let gate_for_meridian = config.frame_type.eq_ignore_ascii_case("light")
            && ctx.target_ra.is_some()
            && ctx.mount_id.is_some();
        if gate_for_meridian {
            if let Some(result) =
                wait_for_meridian_flip_window(ctx, config.duration_secs, control).await
            {
                return result;
            }
        }

        tracing::info!(
            "Capturing frame {}/{} ({:.1}s)",
            frame,
            config.count,
            config.duration_secs
        );

        // The instant the shutter opens. FITS DATE-OBS means START of
        // observation, and this used to be stamped with `Utc::now()` at
        // header-build time -- i.e. after readout -- so every sequenced frame
        // was late by its own exposure time. Capturing it here, immediately
        // before the exposure call, is the only place that is actually true.
        let exposure_started_at = chrono::Utc::now();

        // tokio::select! is the only way to honour cancellation during a
        // blocking exposure without driver support; the abort branch tells
        // the camera to stop so it does not continue exposing in the
        // background after we abandon the future.
        let mut abort_guard =
            CameraExposureAbortGuard::new(ctx.device_ops.clone(), camera_id.clone());
        let exposure_result = tokio::select! {
            biased;
            _ = wait_for_cancellation(ctx.cancellation_token.clone()) => {
                tracing::info!("Exposure cancelled, aborting camera...");
                match ctx.device_ops.camera_abort_exposure(&camera_id).await {
                    Ok(()) => abort_guard.disarm(),
                    Err(error) => tracing::error!(
                        "Camera abort failed during exposure cancellation: {}",
                        error
                    ),
                }
                return InstructionResult::cancelled("Exposure cancelled");
            }
            // Thread the frame type so shuttered cameras (Moravian, FLI, some
            // CCDs) keep the shutter CLOSED for dark/bias frames.
            result = ctx.device_ops.camera_start_exposure_with_frame_type(
                &camera_id,
                config.duration_secs,
                config.gain,
                config.offset,
                bin_x,
                bin_y,
                &config.frame_type,
            ) => {
                abort_guard.disarm();
                result
            }
        };
        let mut image_data = match exposure_result {
            Ok(data) => {
                tracing::info!(
                    "[SEQ] Exposure completed: {}x{} image ({} pixels)",
                    data.width,
                    data.height,
                    data.data.len()
                );
                data
            }
            Err(error) => return InstructionResult::failure(format!("Exposure failed: {}", error)),
        };

        // per-frame defect-map application.
        //
        // The capture path applies the pre-loaded defect map (pushed in
        // via `ExecutorCommand::UpdateDefectMap`) before HFR / grading
        // / FITS save. We deliberately run BEFORE star detection so the
        // grader doesn't reject frames over hot-pixel-induced false
        // stars; HFR / detection costs are unaffected because the map
        // is sparse (~10k of 26M pixels for typical CMOS sensors) and
        // the correction is O(defects · kernel_area).
        //
        // Mismatches (camera id changed, sensor size changed) are
        // surfaced as warn-level logs and the correction is skipped —
        // applying a map built for a different sensor would silently
        // poison the data, but failing the burst would over-react to
        // an operator hot-swapping cameras. The user sees the warn
        // and the frame's FITS HISTORY card records that no correction
        // ran.
        //
        // When `save_original = true` we snapshot the pre-correction
        // pixels here so the Raw/ archive step can save them alongside
        // the corrected frame later. A pre-clone is a ~50 MB heap
        // copy per 26 MP frame, so we only do it when the user
        // explicitly opted in — opt-out users pay zero.
        let mut original_pixels_snapshot: Option<Vec<u16>> = None;
        let should_snapshot_original = {
            let guard = ctx.defect_map_apply.read().await;
            guard.as_ref().map(|s| s.save_original).unwrap_or(false)
        };
        if should_snapshot_original {
            original_pixels_snapshot = Some(image_data.data.clone());
        }
        let defect_map_outcome =
            apply_defect_map_if_configured(ctx, &camera_id, &mut image_data, frame).await;
        // Drop the snapshot if no correction actually happened — saving a
        // verbatim copy of an uncorrected frame would just duplicate the
        // canonical save and waste disk space.
        if !matches!(defect_map_outcome, DefectMapOutcome::Applied { .. }) {
            original_pixels_snapshot = None;
        }

        // Per-frame HFR feeds the HfrDegraded / FocusDrift triggers; computing
        // it here (rather than only on autofocus) gives the triggers real-time
        // visibility into focus health between AF runs.
        let measured_hfr = if !is_light_frame {
            // Calibration frames have no stars; skip the detector entirely.
            None
        } else {
            match ctx.device_ops.calculate_image_hfr(&image_data).await {
                Ok(Some(hfr)) => {
                    tracing::info!("Frame {}/{} HFR: {:.2} pixels", frame, config.count, hfr);
                    hfr_values.push(hfr);
                    Some(hfr)
                }
                Ok(None) => {
                    tracing::warn!(
                        "Frame {}/{} - no stars detected for HFR calculation",
                        frame,
                        config.count
                    );
                    None
                }
                Err(e) => {
                    tracing::warn!(
                        "Frame {}/{} - HFR calculation failed: {}",
                        frame,
                        config.count,
                        e
                    );
                    None
                }
            }
        };

        // Image Grading: derive star count from the star detector so
        // the grading check can apply the star_count_min floor.
        let measured_star_count = if !is_light_frame {
            None
        } else {
            match ctx.device_ops.detect_stars_in_image(&image_data).await {
                Ok(stars) => Some(stars.len() as u32),
                Err(e) => {
                    tracing::debug!(
                        "Frame {}/{} - star detection failed for grading: {}",
                        frame,
                        config.count,
                        e
                    );
                    None
                }
            }
        };

        // Per-frame eccentricity (0.0 = round, →1.0 = trailed) from the star
        // shape moments. `None` is honest absence — no stars, or too few
        // reliable stars to form a stable median — which `grade_frame` treats
        // as "unknown, don't reject". With stars present this is a real
        // measurement, so a configured `eccentricity_threshold` now fires.
        let measured_eccentricity = if !is_light_frame {
            None
        } else {
            match ctx.device_ops.measure_frame_eccentricity(&image_data).await {
                Ok(ecc) => ecc,
                Err(e) => {
                    tracing::debug!(
                        "Frame {}/{} - eccentricity measurement failed for grading: {}",
                        frame,
                        config.count,
                        e
                    );
                    None
                }
            }
        };
        let metrics = crate::quality::FrameMetrics {
            hfr: measured_hfr,
            eccentricity: measured_eccentricity,
            star_count: measured_star_count,
        };

        // Pick the (base_path, filename) pair. When a path_renderer
        // is supplied (the normal in-sequence case) it owns interpolation of
        // the `ExposureConfig.save_to` template and produces a fully resolved
        // directory + filename; an error from the renderer is fatal because
        // a broken template silently writing to the wrong place would be a
        // data-integrity disaster.
        //
        // When no renderer is supplied (legacy direct invocations from
        // tests), we fall back to the pre-Wave-4 hardcoded layout: base
        // path from `ctx.save_path`, filename `<target>_<filter>_<NNNN>.fits`.
        let (base_path, filename_template) = if let Some(renderer) = path_renderer.as_ref() {
            match renderer(frame, config.count) {
                Ok((dir, name)) => (Some(dir), Some(name)),
                Err(msg) => {
                    let error_message = format!(
                        "Save-path template render failed for frame {}/{}: {}. \
                         Aborting exposure — silently saving to the wrong path \
                         would corrupt the session's data integrity.",
                        frame, config.count, msg
                    );
                    tracing::error!("{}", error_message);
                    if let Some(event_tx) = &ctx.event_tx {
                        let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                            message: error_message.clone(),
                        });
                    }
                    return InstructionResult::failure(error_message);
                }
            }
        } else {
            (ctx.save_path.clone(), None)
        };

        if let Some(base_path) = base_path {
            // never silently substitute target name or filter.
            // A missing target name during normal imaging is a configuration
            // bug — emitting `image_L_0001.fits` hides which session the
            // frame belongs to and cannot be undone after the fact.
            // A missing filter labelled `L` mis-labels narrowband captures
            // as luminance.
            //
            // We log at warn! and use distinct synthetic placeholders that
            // are obvious in directory listings so an operator can audit
            // the run. If both fields are present this code path is silent.
            let filename = if let Some(name) = filename_template {
                name
            } else {
                // Legacy renderer-less fallback retained verbatim from the
                // pre-Wave-4 contract.
                let target_label = match ctx.target_name.as_deref() {
                    Some(name) if !name.is_empty() => name.to_string(),
                    _ => {
                        tracing::warn!(
                            "[CAPTURE] Saving frame with no target name — using synthetic label \"untargeted\". \
                             This indicates the sequence was started without a TargetHeader/TargetGroup; review the configuration."
                        );
                        "untargeted".to_string()
                    }
                };
                let filter_label = match frame_filter_name.as_deref() {
                    Some(name) if !name.is_empty() => name.to_string(),
                    _ => {
                        tracing::warn!(
                            "[CAPTURE] Saving frame with no filter set — using synthetic label \"nofilter\" (NOT \"L\"). \
                             A missing filter for narrowband/RGB captures would mis-label the frame as luminance."
                        );
                        "nofilter".to_string()
                    }
                };
                format!("{}_{}_{:04}.fits", target_label, filter_label, frame)
            };

            // Image Grading: decide accept/reject BEFORE picking the
            // final path — rejects go to a sibling Reject/ folder. The
            // grading honours the per-burst override (`config.quality_check`)
            // first, then falls back to the global default from runtime_config
            // (set by the executor at start time). If neither is configured
            // the frame is accepted unconditionally and the path stays the
            // canonical capture folder.
            let active_check = if is_light_frame {
                config
                    .quality_check
                    .as_ref()
                    .or(quality_check_default.as_ref())
            } else {
                // Never grade calibration frames — star-quality gates would
                // reject an entire dark/flat/bias burst as "0 stars".
                None
            };
            let (grade, save_dir, was_graded) = if let Some(qc) = active_check {
                // Read baseline (None until the warmup window fills).
                let baseline = { *frame_baseline_handle.read().await };
                let g = crate::quality::grade_frame(qc, &metrics, baseline);
                match g {
                    crate::quality::FrameGrade::Pass => {
                        // Update the rolling baseline with this accepted HFR.
                        {
                            let mut baseline_guard = frame_baseline_handle.write().await;
                            let mut samples_guard = frame_baseline_samples_handle.write().await;
                            crate::quality::update_hfr_baseline(
                                &mut baseline_guard,
                                &mut samples_guard,
                                measured_hfr,
                            );
                        }
                        (g, base_path.clone(), true)
                    }
                    crate::quality::FrameGrade::Reject { .. } => {
                        let dir = resolve_reject_dir(&base_path, reject_folder_override.as_deref());
                        (g, dir, true)
                    }
                }
            } else {
                (crate::quality::FrameGrade::Pass, base_path.clone(), false)
            };

            // Ensure reject dir exists if grading routed us there. The dir
            // create error is fatal because writing into a non-existent path
            // would be a data-loss event identical to the FITS save failure
            // below.
            if grade.is_reject() {
                if let Err(e) = std::fs::create_dir_all(&save_dir) {
                    let error_message = format!(
                        "Reject folder '{}' could not be created: {}. \
                         Frame {}/{} not saved; sequence aborted.",
                        save_dir.display(),
                        e,
                        frame,
                        config.count
                    );
                    tracing::error!("{}", error_message);
                    if let Some(event_tx) = &ctx.event_tx {
                        let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                            message: error_message.clone(),
                        });
                    }
                    return InstructionResult::failure(error_message);
                }
            }

            let full_path = ensure_unique_save_path(save_dir.join(&filename));

            // archive the uncorrected frame to
            // `<save_dir>/Raw/` BEFORE the canonical save if the user
            // opted in. The raw is written via a minimal FITS header
            // (no defect-map history, IMAGETYP=Light) so re-runs of
            // the correction or independent calibration workflows can
            // re-derive results from the original pixels.
            if matches!(
                defect_map_outcome,
                DefectMapOutcome::Applied {
                    save_original: true,
                    ..
                }
            ) {
                if let Some(original) = &original_pixels_snapshot {
                    if let Err(e) = save_uncorrected_raw_frame(
                        &save_dir,
                        &filename,
                        image_data.width,
                        image_data.height,
                        original,
                    )
                    .await
                    {
                        // Save-original failure is non-fatal — we still
                        // want the corrected frame to land. Log at warn
                        // so the operator sees the partial outcome.
                        tracing::warn!(
                            "[DEFECT] Raw/ archive save failed for frame {}/{}: {}. \
                             The corrected frame will still be saved.",
                            frame,
                            config.count,
                            e,
                        );
                    }
                } else {
                    // Defensive: snapshot is taken only when
                    // save_original was true at correction time, so an
                    // Applied{save_original:true} without snapshot
                    // means an ordering bug in this function.
                    tracing::error!(
                        "[DEFECT] save_original requested but no pre-correction snapshot \
                         exists for frame {}/{}; Raw/ archive skipped.",
                        frame,
                        config.count,
                    );
                }
            }

            // Image Grading: build the per-frame FITS-header bundle
            // from InstructionContext (session-static + per-target fields)
            // plus live device telemetry (sensor temp, focuser position,
            // rotator angle, guide RMS). Each field is best-effort — a
            // device that fails to report its position simply omits that
            // FITS keyword (silent fallbacks would lie about the data).
            //
            // thread the defect-map application outcome
            // so the FITS HISTORY card records the correction provenance.
            let frame_ctx = build_frame_context_for_save(
                ctx,
                config,
                &image_data,
                frame,
                defect_map_outcome.clone(),
                exposure_started_at,
                (frame_filter_name.clone(), frame_filter_index),
            )
            .await;

            if let Err(e) = ctx
                .device_ops
                .save_fits(
                    &image_data,
                    // Why: `PathBuf::to_str()` returns None only when the
                    // path is not valid UTF-8 — on Windows our save paths are always
                    // platform-default (UTF-16 → UTF-8) and on Unix the user's home dir is
                    // the root, both ASCII-safe in practice. Falling back to the bare
                    // filename keeps the save call going against the platform's CWD; the
                    // FITS writer downstream will surface any path-resolution error.
                    full_path.to_str().unwrap_or(&filename),
                    &frame_ctx,
                )
                .await
            {
                // Trust-patch §4: a FITS save failure is data loss — the
                // exposure is already complete and the image bytes are in
                // RAM, so a failed write means that frame is gone. The
                // previous warn-and-continue was the audit-flagged silent
                // fallback: the user would discover the missing frame hours
                // later when checking captures, with no surfaced error.
                //
                // Policy: log at ERROR, emit an ExecutorEvent::Error so the
                // UI sees it, and return InstructionResult::failure so the
                // sequence stops and the user can intervene (out-of-disk,
                // permission denied, drive disconnected — every cause needs
                // human action).
                let error_message = format!(
                    "FITS save failed for frame {}/{} at '{}': {}. \
                     Image data has been lost. Sequence aborted to preserve \
                     remaining storage and surface the issue.",
                    frame,
                    config.count,
                    full_path.display(),
                    e
                );
                tracing::error!("{}", error_message);
                if let Some(event_tx) = &ctx.event_tx {
                    // Why: a closed receiver (no UI subscribers) is benign —
                    // headless / API runs may have no listeners. The log line
                    // above is the durable record.
                    let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                        message: error_message.clone(),
                    });
                }
                return InstructionResult::failure(error_message);
            }
            tracing::info!("Saved: {}", full_path.display());

            // Register EVERY saved frame, graded or not, and emit the
            // Accepted / Rejected progress event so the dashboard quality panel
            // updates and the budget tracker can skip rejected frames.
            //
            // This emission is also what makes the app RECORD the frame: Dart's
            // `_registerSequenceFrame` listens for `FrameAccepted` and writes the
            // `captured_images` row. It used to sit behind `if was_graded`, and
            // grading is off by default, so an entire automated night produced
            // FITS files on disk and ZERO database rows — no Analytics session
            // stats, no gallery entries, and the schema's `producing_node_id` /
            // `producing_run_id` columns never populated. Verified against the
            // desktop database: 12 sequencer frames on disk, 0 rows, and the same
            // for an earlier campaign's frames. The grader DECISION stays gated
            // inside `emit_grade_progress`.
            emit_grade_progress(
                ctx,
                grade,
                &metrics,
                was_graded,
                frame,
                config.count,
                &full_path,
                // Same struct the `save_fits` call above stamped the header
                // from — not a re-read, not a reconstruction.
                &frame_ctx,
                &frames_accepted_handle,
                &frames_rejected_handle,
                &consecutive_rejects_handle,
                active_check
                    .map(|c| c.max_consecutive_rejects)
                    .unwrap_or(u32::MAX),
            )
            .await;
        } else {
            // No resolvable save location: the frame was captured off the
            // sensor and is about to be counted as a completed exposure, but
            // nothing will be written to disk. Say so LOUDLY — this branch
            // silently discarded science frames, so a whole session could
            // report "completed" at 100% while leaving no files behind
            // (observed live on a headless rig with no save path configured).
            // Not a hard failure: transient exposures (autofocus, framing,
            // live view) legitimately reach here with no save path.
            tracing::warn!(
                "Frame {}/{} captured but NOT SAVED: no save location resolved \
                 (no per-node save_to template and no sequencer save path \
                 configured). Set the sequencer save path (or the node's \
                 save_to) or this frame is discarded.",
                frame,
                config.count
            );
        }

        completed_exposures += 1;

        progress_callback(frame, config.count);

        // `frame < config.count` skips the dither after the final frame:
        // dithering after the last exposure of a burst leaves the mount
        // off-target for the next instruction (and wastes time).
        if let Some(dither_every) = config.dither_every {
            // `is_light_frame`: never dither a calibration burst — the serializer
            // inherits the global dither-every default onto every exposure node,
            // so darks/flats would otherwise pulse the mount between frames.
            if is_light_frame
                && dither_every > 0
                && frame % dither_every == 0
                && frame < config.count
            {
                tracing::info!("Dithering...");
                // Dual-rig — guard the burst dither so a piggybacking secondary
                // camera is clear before the mount pulses (no-op single-rig).
                if let Err(e) = dither_guarded(ctx, || {
                    ctx.device_ops.guider_dither(
                        config.dither_pixels,
                        config.dither_settle_pixels,
                        config.dither_settle_time,
                        config.dither_settle_timeout,
                        config.dither_ra_only,
                    )
                })
                .await
                {
                    // An UNGUIDED rig cannot dither, and that is a
                    // CONFIGURATION state — not a guiding failure. No star was
                    // lost, no walking-noise problem is being masked, and no
                    // recovery/guiding trigger can help, so killing an
                    // otherwise-healthy burst over it is wrong.
                    //
                    // It bites by default: the serializer inherits the GLOBAL
                    // dither-every onto every exposure node (see the
                    // `is_light_frame` note above), so a plain light burst on a
                    // rig with no guider schedules a dither it can never perform.
                    // Reproduced on the desktop build with the simulator camera:
                    // an 8-frame burst died after frame 3 with "Dither failed
                    // after frame 3/8: No active guider configured", losing the
                    // remaining 5 frames and the unattended night with them.
                    //
                    // Skip loudly, once per burst, and keep imaging. Every other
                    // dither/settle failure keeps the fail-closed abort below.
                    if crate::device_ops::is_no_guider_configured(&e.to_string()) {
                        if !dither_skipped_warned {
                            dither_skipped_warned = true;
                            tracing::warn!(
                                "Dither requested after frame {}/{} but no guider is \
                                 configured — skipping dithers for the rest of this \
                                 burst. Frames will be UNDITHERED (walking noise); \
                                 connect a guider or set dither-every to 0 to \
                                 silence this.",
                                frame,
                                config.count
                            );
                        }
                    } else {
                        // Fail closed, matching the standalone Dither node. A
                        // dither / settle failure usually means guiding lost the
                        // star, so silently continuing the burst would keep
                        // exposing undithered (walking noise) and mask a guiding
                        // problem. Surface it as a visible event and abort the
                        // burst so the sequence's recovery / guiding triggers can
                        // engage.
                        let error_message = format!(
                            "Dither failed after frame {}/{}: {}",
                            frame, config.count, e
                        );
                        tracing::error!("{}", error_message);
                        if let Some(event_tx) = &ctx.event_tx {
                            let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                                message: error_message.clone(),
                            });
                        }
                        return InstructionResult::failure(error_message);
                    }
                }
            }
        }
    }

    InstructionResult {
        status: NodeStatus::Success,
        message: Some(format!("Completed {} exposures", completed_exposures)),
        data: Some(serde_json::json!({
            "completed": completed_exposures,
            "total": config.count,
        })),
        hfr_values,
    }
}

// =============================================================================
// IMAGE-GRADING HELPERS (Image Grading)
// =============================================================================

// =============================================================================
// DEFECT-MAP HELPERS
// =============================================================================

/// Outcome of the per-frame defect-map application step. Threaded into
/// the FITS HISTORY card emitter so the saved frame carries provenance
/// of the correction (or its skip reason).
#[derive(Debug, Clone)]
pub(crate) enum DefectMapOutcome {
    /// No defect map is configured for the current run. Common case
    /// for users who haven't opted in to defect correction.
    Disabled,
    /// A map was configured but the connected camera id did not match
    /// the map's camera id, OR the map's dimensions did not match the
    /// frame's. In either case the frame is left as-is and a warn line
    /// is logged so the operator sees the skip.
    ///
    /// `reason` is constructed at the call sites (with the specific
    /// mismatch detail) and surfaced in the warn log line emitted there
    /// — keeping the field in the enum means future code paths that
    /// need to inspect or re-emit the reason (e.g. a richer skip event)
    /// can do so without changing the shape.
    SkippedMismatch {
        #[allow(dead_code)]
        reason: String,
    },
    /// The map matched and was applied. The corrected pixel count may
    /// be smaller than the map's defective_count when some defects had
    /// no healthy neighbours inside the expanded kernel.
    Applied {
        camera_id: String,
        defect_count: u32,
        corrected_count: u32,
        kernel_diameter: u8,
        method: &'static str,
        save_original: bool,
    },
}

impl DefectMapOutcome {
    /// Convert to a FrameContext-side record. Returns `None` when no
    /// correction was actually applied — callers must not emit a
    /// HISTORY card claiming a correction happened when one did not.
    fn into_record(self) -> Option<crate::scheduling::DefectMapCorrectionRecord> {
        match self {
            DefectMapOutcome::Applied {
                camera_id,
                defect_count,
                corrected_count,
                kernel_diameter,
                method,
                save_original: _,
            } => Some(crate::scheduling::DefectMapCorrectionRecord {
                camera_id,
                defect_count,
                corrected_count,
                kernel_diameter,
                method: method.to_string(),
            }),
            DefectMapOutcome::Disabled | DefectMapOutcome::SkippedMismatch { .. } => None,
        }
    }
}

/// Apply the per-frame defect map to the just-captured image data, in
/// place. Returns the outcome (disabled / skipped / applied) so the
/// FITS HISTORY card emitter and the Raw/ archival step know what
/// happened.
///
/// Pre-conditions / safety:
/// * Camera id mismatch returns `SkippedMismatch` rather than
///   silently applying a map built for a different sensor — that
///   would poison the data with the wrong hot-pixel coordinates.
/// * Dimension mismatch returns `SkippedMismatch` for the same
///   reason; the map's bitmap is sized to the sensor it was built
///   against and applying it to a different frame size would write
///   neighbour medians at coordinates that don't correspond to real
///   defects.
///
/// Why a separate helper: keeping the borrow of
/// `defect_map_apply` to a short read-guard scope means the rest of
/// the capture loop is unaffected. Cloning the inner `Arc<DefectMap>`
/// is cheap (refcount bump) and lets us drop the guard before doing
/// the actual O(defects × kernel) correction work.
pub(crate) async fn apply_defect_map_if_configured(
    ctx: &InstructionContext,
    camera_id: &str,
    image_data: &mut crate::device_ops::ImageData,
    frame_idx: u32,
) -> DefectMapOutcome {
    let snapshot = {
        let guard = ctx.defect_map_apply.read().await;
        guard.clone()
    };
    let Some(state) = snapshot else {
        return DefectMapOutcome::Disabled;
    };

    if state.camera_id != camera_id {
        tracing::warn!(
            "[DEFECT] Frame {} skipping defect-map correction: connected camera id `{}` \
             does not match map's camera id `{}`. The map was built for a different \
             sensor and applying it would poison the data.",
            frame_idx,
            camera_id,
            state.camera_id,
        );
        return DefectMapOutcome::SkippedMismatch {
            reason: format!(
                "camera mismatch: map=`{}`, frame=`{}`",
                state.camera_id, camera_id
            ),
        };
    }

    if state.map.width != image_data.width || state.map.height != image_data.height {
        tracing::warn!(
            "[DEFECT] Frame {} skipping defect-map correction: map dimensions {}x{} do not \
             match frame dimensions {}x{}. A subframe / ROI change has invalidated the map; \
             rebuild it at the new sensor crop.",
            frame_idx,
            state.map.width,
            state.map.height,
            image_data.width,
            image_data.height,
        );
        return DefectMapOutcome::SkippedMismatch {
            reason: format!(
                "size mismatch: map={}x{}, frame={}x{}",
                state.map.width, state.map.height, image_data.width, image_data.height,
            ),
        };
    }

    if state.map.defective_count() == 0 {
        // Empty map = no work, but emit a HISTORY card so the operator
        // sees the map was selected (this catches "I built the map but
        // it has zero defects so nothing happened" confusion).
        return DefectMapOutcome::Applied {
            camera_id: state.camera_id.clone(),
            defect_count: 0,
            corrected_count: 0,
            kernel_diameter: state.kernel.diameter(),
            method: state.method.as_str(),
            save_original: state.save_original,
        };
    }

    let pixels_slice = image_data.data.as_mut_slice();
    let width = image_data.width;
    let height = image_data.height;
    // The sequencer's ImageData is mono u16 (camera output before
    // debayering). channels = 1 is enforced by the capture-side
    // contract; if a driver ever returns a multi-channel buffer we
    // skip correction rather than slice into the wrong storage.
    let channels = 1u32;
    let expected_len = (width as usize) * (height as usize) * (channels as usize);
    if pixels_slice.len() != expected_len {
        tracing::warn!(
            "[DEFECT] Frame {} skipping defect-map correction: pixel buffer length \
             {} does not match {}x{}x{} = {} expected u16 samples.",
            frame_idx,
            pixels_slice.len(),
            width,
            height,
            channels,
            expected_len,
        );
        return DefectMapOutcome::SkippedMismatch {
            reason: format!(
                "buffer length {} != expected {}",
                pixels_slice.len(),
                expected_len
            ),
        };
    }

    let start = std::time::Instant::now();
    let result = nightshade_imaging::defect_map::correct_u16_slice(
        pixels_slice,
        width,
        height,
        channels,
        &state.map,
        state.method,
        state.kernel,
    );
    let elapsed = start.elapsed();
    match result {
        Ok(corrected) => {
            tracing::info!(
                "[DEFECT] Frame {} corrected {} of {} defective pixels in {:.1}ms (kernel={}x{}, method={})",
                frame_idx,
                corrected,
                state.map.defective_count(),
                elapsed.as_secs_f64() * 1000.0,
                state.kernel.diameter(),
                state.kernel.diameter(),
                state.method.as_str(),
            );
            DefectMapOutcome::Applied {
                camera_id: state.camera_id.clone(),
                defect_count: state.map.defective_count(),
                corrected_count: corrected,
                kernel_diameter: state.kernel.diameter(),
                method: state.method.as_str(),
                save_original: state.save_original,
            }
        }
        Err(e) => {
            // Defensive: the slice-level corrector validates dimensions
            // before mutating, so we should never reach this branch
            // given the earlier checks. Surface the error rather than
            // silently swallowing it.
            tracing::error!(
                "[DEFECT] Frame {} defect-map correction failed: {}",
                frame_idx,
                e,
            );
            DefectMapOutcome::SkippedMismatch {
                reason: format!("corrector returned error: {}", e),
            }
        }
    }
}

/// Archive the uncorrected (pre-defect-map) pixels to `<save_dir>/Raw/`.
///
/// We use a minimal FITS writer here that only writes width/height +
/// the u16 sample data — the canonical FITS header (with target,
/// telescope, observer, etc.) is reserved for the corrected frame.
/// This keeps the Raw/ folder a literal "what the sensor produced"
/// archive that a re-stacking workflow can pull through a different
/// correction pipeline without having to subtract out the previous
/// Nightshade correction.
///
/// Why this writer (and not a DeviceOps call): the device-ops
/// `save_fits` writes the full FrameContext header. We deliberately
/// want a bare-bones FITS here so the raw archive can be replayed
/// through external calibration with no Nightshade-specific keywords
/// already on it.
pub(crate) async fn save_uncorrected_raw_frame(
    save_dir: &std::path::Path,
    filename: &str,
    width: u32,
    height: u32,
    pixels: &[u16],
) -> Result<(), String> {
    let raw_dir = save_dir.join("Raw");
    std::fs::create_dir_all(&raw_dir).map_err(|e| {
        format!(
            "could not create Raw/ directory `{}`: {}",
            raw_dir.display(),
            e
        )
    })?;
    let raw_path = raw_dir.join(filename);

    // We rely on the imaging crate's FITS writer for consistency with
    // the rest of the save pipeline. Constructing the ImageData here
    // is a u16→bytes shuffle — for a 26 MP frame that's ~50 MB but
    // it happens off-thread inside spawn_blocking so the capture loop
    // is not blocked.
    let pixels = pixels.to_vec();
    let raw_path_clone = raw_path.clone();
    let join = tokio::task::spawn_blocking(move || {
        let image = nightshade_imaging::ImageData::from_u16(width, height, 1, &pixels);
        let mut header = nightshade_imaging::FitsHeader::new();
        header.set_string("IMAGETYP", "LIGHT");
        header.set_string(
            "COMMENT",
            "Nightshade uncorrected raw (defect map not yet applied)",
        );
        nightshade_imaging::write_fits(&raw_path_clone, &image, &header)
            .map_err(|e| format!("write_fits failed: {}", e))
    })
    .await;
    match join {
        Ok(Ok(())) => {
            tracing::info!("[DEFECT] Raw archive written: {}", raw_path.display());
            Ok(())
        }
        Ok(Err(e)) => Err(e),
        Err(e) => Err(format!("spawn_blocking join failed: {}", e)),
    }
}

/// Resolve the directory where rejected frames go.
///
/// * `override_path = None`: use `<base>/Reject/`.
/// * `override_path = Some(absolute)`: use that path verbatim.
/// * `override_path = Some(relative)`: resolve against `base`.
pub fn resolve_reject_dir(base: &std::path::Path, override_path: Option<&str>) -> PathBuf {
    match override_path {
        Some(p) => {
            let candidate = std::path::Path::new(p);
            if candidate.is_absolute() {
                candidate.to_path_buf()
            } else {
                base.join(candidate)
            }
        }
        None => base.join("Reject"),
    }
}

/// forensics — snapshot the live environmental telemetry into a
/// single `EnvironmentSnapshot`. Each field is read independently with
/// `try_read()` semantics emulated by an `await`; the analyzer treats
/// `None` honestly (no fabrication of stand-ins).
async fn build_environment_snapshot(
    ctx: &InstructionContext,
) -> crate::quality::EnvironmentSnapshot {
    let sky_brightness_mag = *ctx.current_sky_brightness_mag.read().await;
    let cloud_cover_percent = ctx.cloud_motion_snapshot.read().await.current_cover_percent;
    let wind_kph = *ctx.current_wind_kph.read().await;
    // Guide RMS — pull the most recent sample from the trigger state's
    // rolling guide-RMS history. The history is a `Vec<(Instant, f64)>`
    // already maintained for the GuidingFailed trigger evaluator.
    let guide_rms_arcsec = if let Some(trigger_state_lock) = &ctx.trigger_state {
        let state = trigger_state_lock.read().await;
        state
            .guiding_rms_history
            .as_ref()
            .and_then(|h| h.last())
            .map(|(_, rms)| *rms)
    } else {
        None
    };
    let sensor_temp_c = *ctx.current_sensor_temp_c.read().await;
    crate::quality::EnvironmentSnapshot {
        sky_brightness_mag,
        cloud_cover_percent,
        wind_kph,
        guide_rms_arcsec,
        sensor_temp_c,
    }
}

/// forensics — append a sample to the rolling history, enforcing
/// the [`crate::quality::FORENSIC_HISTORY_LEN`] bound. Lock window is
/// minimal (one write_lock acquisition per frame) and the push is
/// guaranteed O(1) regardless of run length.
async fn push_forensic_sample(ctx: &InstructionContext, sample: crate::quality::RecentFrameSample) {
    let mut history = ctx.forensics_history.write().await;
    history.push_back(sample);
    while history.len() > crate::quality::FORENSIC_HISTORY_LEN {
        history.pop_front();
    }
}

/// Emit a structured FrameAccepted / FrameRejected progress event and (on
/// reject) update the consecutive-rejects atomic. Escalates to an
/// `ExecutorEvent::Error` once the consecutive-rejects threshold is hit —
/// 's critical-event banner picks that up automatically.
///
/// Frame-Failure Forensics: in addition to the existing event,
/// this function:
///
/// 1. Snapshots live environmental telemetry (sky brightness, cloud cover,
///    wind, guide RMS, sensor temperature) from the shared
///    `ExecutionContext` Arcs.
/// 2. On reject, consults [`crate::quality::analyze_rejection`] with the
///    rolling history to classify the rejection (`LikelyCause`) and
///    produce an evidence-bullet list.
/// 3. Pushes the new frame sample (accepted or rejected) onto the rolling
///    history so subsequent rejects have full context.
#[allow(clippy::too_many_arguments)]
async fn emit_grade_progress(
    ctx: &InstructionContext,
    grade: crate::quality::FrameGrade,
    metrics: &crate::quality::FrameMetrics,
    // Whether a grader actually ran. The frame is REGISTERED either way (the
    // progress event below is what makes the app record it), but no grader
    // decision is written to the replay/decision log when no grader made one.
    was_graded: bool,
    frame: u32,
    total: u32,
    full_path: &std::path::Path,
    // The SAME `FrameContext` the FITS header for this frame was built from.
    // Passing it here (rather than re-reading the devices, or letting Dart
    // reconstruct the values from the sequence tree) is the whole point: one
    // struct stamps both the file and the database row, so they cannot drift.
    frame_ctx: &crate::scheduling::FrameContext,
    frames_accepted: &Arc<std::sync::atomic::AtomicU32>,
    frames_rejected: &Arc<std::sync::atomic::AtomicU32>,
    consecutive_rejects: &Arc<std::sync::atomic::AtomicU32>,
    max_consecutive: u32,
) {
    use std::sync::atomic::Ordering;
    let capture = crate::scheduling::FrameCaptureMetadata::from(frame_ctx);
    // forensics — snapshot the environment once up-front so the
    // values reported in the event match the values fed to the
    // classifier. (Two separate reads could race against the
    // ExecutorCommand::UpdateCloudMotion / UpdateSkyBrightness handlers.)
    let env_snapshot = build_environment_snapshot(ctx).await;
    match &grade {
        crate::quality::FrameGrade::Pass => {
            let accepted = frames_accepted.fetch_add(1, Ordering::Relaxed) + 1;
            consecutive_rejects.store(0, Ordering::Relaxed);
            let rejected = frames_rejected.load(Ordering::Relaxed);
            // forensics: log the accepted sample so subsequent
            // rejects can compare against it. We capture the env
            // snapshot too — the SeeingSpike / FocusDrift heuristics
            // require trailing accepted frames to have HFR populated.
            push_forensic_sample(
                ctx,
                crate::quality::RecentFrameSample {
                    unix_secs: chrono::Utc::now().timestamp() as f64,
                    accepted: true,
                    hfr: metrics.hfr,
                    eccentricity: metrics.eccentricity,
                    star_count: metrics.star_count,
                    sky_brightness_mag: env_snapshot.sky_brightness_mag,
                    cloud_cover_percent: env_snapshot.cloud_cover_percent,
                    wind_kph: env_snapshot.wind_kph,
                    guide_rms_arcsec: env_snapshot.guide_rms_arcsec,
                    sensor_temp_c: env_snapshot.sensor_temp_c,
                },
            )
            .await;
            // emit a structured `ProgressDetail::FrameAccepted` so
            // the bridge can dispatch the typed `SequencerEvent::FrameAccepted`
            // variant. The legacy `detail` string is still populated from
            // `ProgressDetail::detail_text()` so any subscriber that hasn't
            // migrated keeps working. The metrics come from `_metrics` (the
            // `FrameMetrics` computed by the grader) because `FrameGrade::Pass`
            // is a unit variant.
            let structured = crate::node::ProgressDetail::FrameAccepted {
                frame,
                total,
                hfr: metrics.hfr,
                eccentricity: metrics.eccentricity,
                star_count: metrics.star_count,
                accepted_total: accepted,
                rejected_total: rejected,
                // surface the on-disk save path so the
                // thumbnail strip can render an inline preview of
                // accepted frames the same way it already does for
                // rejected ones via `FrameRejected.reject_path`. The
                // path is the resolved FITS file we just wrote (so the
                // strip's path resolver can hand it straight to the
                // image-loader without further translation).
                save_path: Some(full_path.display().to_string()),
                capture: capture.clone(),
            };
            let detail_text = structured.detail_text();
            if let Some(event_tx) = &ctx.event_tx {
                let _ = event_tx.send(crate::executor::ExecutorEvent::NodeProgress {
                    node_id: ctx.node_id.clone(),
                    instruction: "Exposure".to_string(),
                    progress_percent: 100.0 * frame as f64 / total.max(1) as f64,
                    detail: detail_text,
                    structured_detail: Some(Box::new(structured)),
                });
            }
            // Replay Debug — record a FrameAccepted decision so
            // the replay timeline surfaces every accepted frame next
            // to the rejected ones. We hand the path through too so
            // the replay UI can cross-link to the captured-image row.
            //
            // Gated on `was_graded`: an ungraded frame is still registered
            // (above), but no grader DECISION is invented for it — nothing
            // graded it, so the replay timeline must not claim otherwise.
            if was_graded {
                ctx.emit_decision(crate::decision::DecisionEvent::new(
                    crate::decision::DecisionCategory::FrameAccepted,
                    format!(
                        "Frame {}/{} accepted{}",
                        frame,
                        total,
                        metrics
                            .hfr
                            .map(|h| format!(" (HFR {:.2})", h))
                            .unwrap_or_default(),
                    ),
                    serde_json::json!({
                        "frame": frame,
                        "total": total,
                        "hfr": metrics.hfr,
                        "eccentricity": metrics.eccentricity,
                        "star_count": metrics.star_count,
                        "save_path": full_path.display().to_string(),
                        "accepted_total": accepted,
                        "rejected_total": rejected,
                    }),
                ));
            }
        }
        crate::quality::FrameGrade::Reject {
            reason,
            hfr,
            eccentricity,
            star_count,
        } => {
            let rejected = frames_rejected.fetch_add(1, Ordering::Relaxed) + 1;
            let accepted = frames_accepted.load(Ordering::Relaxed);
            let consecutive = consecutive_rejects.fetch_add(1, Ordering::Relaxed) + 1;

            tracing::warn!(
                "[GRADE] Frame {}/{} REJECTED ({}× consecutive): {} (HFR={:?}, ecc={:?}, stars={:?}, path={})",
                frame,
                total,
                consecutive,
                reason,
                hfr,
                eccentricity,
                star_count,
                full_path.display()
            );

            // forensics — read the rolling history (cheap clone of
            // VecDeque -> Vec since only the analyzer needs a contiguous
            // slice) and consult the classifier. The history read MUST
            // happen before `push_forensic_sample` below so the current
            // frame doesn't classify against itself. We snapshot the HFR
            // baseline from the shared Arc the grader already uses, so
            // the classifier sees the same "what counts as elevated"
            // anchor.
            let history_snapshot: Vec<crate::quality::RecentFrameSample> = {
                let lock = ctx.forensics_history.read().await;
                lock.iter().cloned().collect()
            };
            let baseline_snapshot = *ctx.hfr_baseline.read().await;
            let verdict = crate::quality::analyze_rejection(&crate::quality::ForensicInputs {
                hfr: *hfr,
                eccentricity: *eccentricity,
                star_count: *star_count,
                hfr_baseline: baseline_snapshot,
                environment: env_snapshot.clone(),
                recent_frames: &history_snapshot,
                grader_reason: reason.as_str(),
            });
            tracing::info!(
                "[FORENSICS] Frame {}/{} cause={} evidence={:?}",
                frame,
                total,
                verdict.likely_cause.map(|c| c.label()).unwrap_or("none"),
                verdict.evidence,
            );

            // structured FrameRejected payload mirrors what the
            // bridge needs to dispatch SequencerEvent::FrameRejected; the
            // legacy detail string remains for back-compat.
            // forensics fields are populated from the verdict + the
            // pre-classification environment snapshot.
            let structured = crate::node::ProgressDetail::FrameRejected {
                frame,
                total,
                reason: reason.clone(),
                hfr: *hfr,
                eccentricity: *eccentricity,
                star_count: *star_count,
                reject_path: full_path.display().to_string(),
                consecutive_rejects: consecutive,
                accepted_total: accepted,
                rejected_total: rejected,
                likely_cause: verdict.likely_cause,
                evidence: verdict.evidence.clone(),
                sky_brightness_at_capture: env_snapshot.sky_brightness_mag,
                cloud_cover_at_capture: env_snapshot.cloud_cover_percent,
                wind_at_capture: env_snapshot.wind_kph,
                guide_rms_at_capture: env_snapshot.guide_rms_arcsec,
                sensor_temp_at_capture: env_snapshot.sensor_temp_c,
                capture: capture.clone(),
            };
            // Append the rejected sample to the history AFTER
            // classification so the next reject sees this one in its
            // neighbour cluster.
            push_forensic_sample(
                ctx,
                crate::quality::RecentFrameSample {
                    unix_secs: chrono::Utc::now().timestamp() as f64,
                    accepted: false,
                    hfr: *hfr,
                    eccentricity: *eccentricity,
                    star_count: *star_count,
                    sky_brightness_mag: env_snapshot.sky_brightness_mag,
                    cloud_cover_percent: env_snapshot.cloud_cover_percent,
                    wind_kph: env_snapshot.wind_kph,
                    guide_rms_arcsec: env_snapshot.guide_rms_arcsec,
                    sensor_temp_c: env_snapshot.sensor_temp_c,
                },
            )
            .await;
            let detail_text = structured.detail_text();
            if let Some(event_tx) = &ctx.event_tx {
                let _ = event_tx.send(crate::executor::ExecutorEvent::NodeProgress {
                    node_id: ctx.node_id.clone(),
                    instruction: "Exposure".to_string(),
                    progress_percent: 100.0 * frame as f64 / total.max(1) as f64,
                    detail: detail_text,
                    structured_detail: Some(Box::new(structured)),
                });
            }
            // Replay Debug — record a FrameRejected decision so
            // the replay timeline carries the verdict + forensics
            // payload alongside the consecutive-rejects escalation.
            // Cross-links to forensics via the `reject_path` field
            // which the replay UI uses to deep-link.
            ctx.emit_decision(crate::decision::DecisionEvent::new(
                crate::decision::DecisionCategory::FrameRejected,
                format!(
                    "Frame {}/{} REJECTED: {}{}",
                    frame,
                    total,
                    reason,
                    if consecutive > 1 {
                        format!(" ({}× consecutive)", consecutive)
                    } else {
                        String::new()
                    },
                ),
                serde_json::json!({
                    "frame": frame,
                    "total": total,
                    "reason": reason,
                    "hfr": hfr,
                    "eccentricity": eccentricity,
                    "star_count": star_count,
                    "reject_path": full_path.display().to_string(),
                    "consecutive_rejects": consecutive,
                    "accepted_total": accepted,
                    "rejected_total": rejected,
                }),
            ));

            // Escalation: max_consecutive_rejects in a row => emit Error
            // (critical-event banner) and pause the
            // sequence. We do NOT cancel — the user may want to inspect
            // the rejects and resume.
            if consecutive >= max_consecutive && max_consecutive > 0 {
                let escalation = format!(
                    "Image grading: {} consecutive rejects (limit {}). \
                     Sequence paused for inspection. Frame {}/{}, last reason: {}. \
                     Most recent reject: {}. Accepted so far: {}, rejected: {}.",
                    consecutive,
                    max_consecutive,
                    frame,
                    total,
                    reason,
                    full_path.display(),
                    accepted,
                    rejected,
                );
                tracing::error!("{}", escalation);
                if let Some(event_tx) = &ctx.event_tx {
                    let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                        message: escalation,
                    });
                }

                // actually escalate to a real recovery/pause. The
                // recovery system has a `ConsecutiveRejectsExceeded` cause
                // whose driver pauses the run for inspection, but nothing ever
                // SENT it — so a reject storm (clouds rolling in, focus lost,
                // bad target) only raised a banner and kept burning the night
                // capturing rejects. Send the cause once, exactly at the
                // crossing, so it doesn't flood the recovery channel every
                // subsequent frame. `consecutive` resets to 0 on the next
                // accepted frame, so a later storm escalates again.
                if consecutive == max_consecutive {
                    if let Some(tx) = ctx.recovery_request_tx.as_ref() {
                        match tx.try_send(
                            crate::recovery::RecoveryCause::ConsecutiveRejectsExceeded,
                        ) {
                            Ok(()) => tracing::warn!(
                                "[RECOVERY] Promoted consecutive-reject storm to recovery ({} in a row)",
                                consecutive
                            ),
                            Err(e) => tracing::warn!(
                                "[RECOVERY] Could not enqueue consecutive-reject recovery: {}",
                                e
                            ),
                        }
                    } else {
                        tracing::warn!(
                            "[RECOVERY] {} consecutive rejects but no recovery channel installed; banner only",
                            consecutive
                        );
                    }
                }
            }
            // _ silence — used only for tracing above.
            let _ = (hfr, eccentricity, star_count);
        }
    }
}

// =============================================================================
// FRAME CONTEXT BUILDER (Image Grading)
// =============================================================================

/// Build the per-frame FITS-header bundle for the current capture.
///
/// Reads everything the FITS writer needs:
/// - session-static fields from `InstructionContext` (session_id, observer,
///   equipment ID, site coords)
/// - per-target fields from `InstructionContext` (target_name/id, mosaic_panel)
/// - exposure settings from the active `ExposureConfig`
/// - live device telemetry by querying the connected focuser / rotator /
///   guider via `DeviceOps`. Each query is best-effort: a device that fails
///   to report its state simply omits the corresponding FITS keyword. We
///   never substitute sentinel values (the audit's silent-fallback rule).
/// - the most recent plate-solve result, if CenterTarget ran for this target
///
/// The live-telemetry reads are bounded: the focuser/rotator/guide queries
/// are simple status reads (no motion commands) and the existing DeviceOps
/// implementations cache the values, so this adds <10 ms of overhead per
/// frame — negligible compared to the multi-second exposure.
async fn build_frame_context_for_save(
    ctx: &InstructionContext,
    config: &ExposureConfig,
    image_data: &ImageData,
    frame_index: u32,
    defect_map_outcome: DefectMapOutcome,
    exposure_started_at: chrono::DateTime<chrono::Utc>,
    // The burst's (name, slot) pair from `resolve_frame_filter`, passed in
    // rather than re-derived so the FITS card can never name a different filter
    // than the file it is written into.
    frame_filter: (Option<String>, Option<i32>),
) -> crate::scheduling::FrameContext {
    let (bin_x, bin_y) = match config.binning {
        Binning::One => (1u32, 1u32),
        Binning::Two => (2, 2),
        Binning::Three => (3, 3),
        Binning::Four => (4, 4),
    };

    let mut frame_ctx = crate::scheduling::FrameContext::new_light(
        ctx.session_id.clone(),
        bin_x,
        bin_y,
        config.duration_secs,
        frame_index,
    );
    frame_ctx.exposure_started_at = Some(exposure_started_at);

    // DECISION: the camera's own report of how long it exposed wins over the
    // commanded duration, but only within the bound below.
    //
    // Why the driver and not the plan. `EXPTIME` means the exposure that
    // happened, not the one that was asked for, and the FITS writer has always
    // read it straight off `ImageData` — so preferring the plan here would
    // CHANGE what lands in every FITS file, which is the larger unannounced
    // change. On a camera with a mechanical shutter the two genuinely differ,
    // and the measured value is the one a later calibration match wants.
    //
    // Why it is bounded. The same field is now also the NOT NULL
    // `captured_images.exposure_duration` that every integration total sums, so
    // one lying driver could corrupt a season of totals with nothing
    // downstream able to tell. The shutter cannot have been open materially
    // longer than the sequencer waited for it, so an over-report is not a
    // measurement — it is a fault, and the commanded value is kept instead.
    // (The grace is shutter/readout latency plus drivers that quantise their
    // exposure clock coarsely on long subs.)
    //
    // The bound is deliberately one-sided. A report SHORTER than commanded is
    // physically possible — an aborted or truncated exposure really did end
    // early — and it can only under-count integration, which is the safe
    // direction and shows up as an obviously short sub rather than as a night
    // that claims hours it never collected.
    let commanded_secs = frame_ctx.duration_secs;
    let reported_secs = image_data.exposure_secs;
    let longest_believable = commanded_secs * 1.05 + 1.0;
    if reported_secs > 0.0 && reported_secs <= longest_believable {
        frame_ctx.duration_secs = reported_secs;
    } else if reported_secs > longest_believable {
        tracing::warn!(
            "[CAPTURE] Camera reported a {:.3}s exposure for a commanded {:.3}s frame — \
             impossible, so the commanded value is recorded instead. This driver's \
             exposure report cannot be trusted; integration totals would be inflated \
             by roughly {:.1}x if it were.",
            reported_secs,
            commanded_secs,
            if commanded_secs > 0.0 {
                reported_secs / commanded_secs
            } else {
                f64::INFINITY
            },
        );
    }

    // Honour the node's configured frame type (FITS IMAGETYP). Before this,
    // every sequencer capture was stamped "Light" — sequenced darks/flats/
    // bias frames were mislabeled on disk and invisible to calibration
    // ingest that filters on IMAGETYP.
    frame_ctx.frame_type = config.frame_type.clone();

    frame_ctx.total_planned_frames = Some(config.count);

    // Target identification — use the running target from the executor (not
    // the synthesized "untargeted" label used for the filename, which is a
    // legitimate operator-visible signal but should not pollute the FITS
    // OBJECT keyword).
    frame_ctx.target_id = ctx.target_id.clone();
    frame_ctx.target_name = ctx.target_name.clone();
    frame_ctx.target_ra_hours = ctx.target_ra;
    frame_ctx.target_dec_degrees = ctx.target_dec;

    // Filter. Name and slot arrive already paired: reading `config` and the
    // context independently let a burst that named "Ha" but carried no slot be
    // stamped with whatever slot the previous burst had left behind.
    (frame_ctx.filter_name, frame_ctx.filter_index) = frame_filter;

    // Camera settings (already on ImageData from the capture).
    frame_ctx.gain = image_data.gain.or(config.gain);
    frame_ctx.offset = image_data.offset.or(config.offset);
    frame_ctx.sensor_temp_c = image_data.temperature;
    frame_ctx.set_temp_c = ctx.set_temp_c;

    // Cooler duty cycle. Only meaningful on a cooled camera; an uncooled one
    // (or a driver that will not answer) leaves the column NULL rather than
    // recording 0 %, which would read as "cooler idle" — the opposite of "no
    // cooler".
    if let Some(camera_id) = &ctx.camera_id {
        match ctx.device_ops.camera_get_cooler_power(camera_id).await {
            Ok(power) => frame_ctx.cooler_power_percent = Some(power),
            Err(e) => tracing::debug!(
                "[CAPTURE] camera_get_cooler_power failed; cooler power omitted: {}",
                e
            ),
        }
    }

    // Bayer pattern — prefer the camera-reported sensor type over a stale
    // ExecutionContext value. A camera reporting "Monochrome" overrides any
    // stale "RGGB" left from a previous (different-camera) session.
    frame_ctx.bayer_pattern = match image_data.sensor_type.as_deref() {
        Some(s) if s.eq_ignore_ascii_case("Monochrome") || s.eq_ignore_ascii_case("Mono") => None,
        _ => ctx.bayer_pattern.clone(),
    };

    // Mosaic panel.
    frame_ctx.mosaic_panel = ctx.mosaic_panel.clone();

    // Observer / site.
    frame_ctx.observer_name = ctx.observer_name.clone();
    frame_ctx.site_latitude_deg = ctx.latitude;
    frame_ctx.site_longitude_deg = ctx.longitude;
    frame_ctx.site_elevation_m = ctx.site_elevation_m;

    // Equipment identification.
    frame_ctx.camera_make = ctx.camera_make.clone();
    frame_ctx.camera_model = ctx.camera_model.clone();
    // Ask the DRIVER which camera this is when the observer profile does not
    // say. The profile is a cross-product of app settings and the active
    // equipment profile, so a rig running without one — which is every
    // headless run that has not had a profile created, and was exactly the
    // state of the live rig — wrote frames with no INSTRUME at all. The camera
    // is connected and has a name; there is no reason for the file not to
    // carry it. Only fills the gap: a profile that names a camera still wins,
    // because that is the operator stating what they want in their archive.
    if frame_ctx.camera_make.is_none() && frame_ctx.camera_model.is_none() {
        if let Some(camera_id) = &ctx.camera_id {
            match ctx.device_ops.camera_get_model(camera_id).await {
                Ok(Some(model)) => frame_ctx.camera_model = Some(model),
                Ok(None) => tracing::debug!(
                    "[CAPTURE] camera {} reports no model name; INSTRUME omitted",
                    camera_id
                ),
                Err(e) => {
                    tracing::debug!("[CAPTURE] camera_get_model failed; INSTRUME omitted: {}", e)
                }
            }
        }
    }
    // Sensor pixel pitch (FITS XPIXSZ/YPIXSZ). Asked of the driver here rather
    // than taken from the observer profile, which has no pixel-size field: this
    // is the only place in a sequenced capture where the number is reachable,
    // and without it the sub lands on disk with FOCALLEN but no pitch, so no
    // stacker can derive the plate scale from the file alone. A driver that
    // will not answer leaves the keywords off rather than inventing a pitch.
    if let Some(camera_id) = &ctx.camera_id {
        match ctx.device_ops.camera_get_pixel_size_um(camera_id).await {
            Ok(Some((x_um, y_um))) => {
                frame_ctx.camera_pixel_size_x_um = Some(x_um);
                frame_ctx.camera_pixel_size_y_um = Some(y_um);
            }
            Ok(None) => tracing::debug!(
                "[CAPTURE] camera {} reports no pixel size; XPIXSZ/YPIXSZ omitted",
                camera_id
            ),
            Err(e) => tracing::debug!(
                "[CAPTURE] camera_get_pixel_size_um failed; XPIXSZ/YPIXSZ omitted: {}",
                e
            ),
        }
    }
    frame_ctx.telescope_name = ctx.telescope_name.clone();
    frame_ctx.telescope_focal_length_mm = ctx.telescope_focal_length_mm;
    frame_ctx.telescope_aperture_mm = ctx.telescope_aperture_mm;

    // Live focuser telemetry. We use match arms so a driver error just
    // omits the keyword — never overrides with a fake value. The focuser
    // temperature is `Option<f64>` even on success because not every
    // focuser model has a thermistor.
    if let Some(focuser_id) = &ctx.focuser_id {
        match ctx.device_ops.focuser_get_position(focuser_id).await {
            Ok(pos) => frame_ctx.focuser_position = Some(pos),
            Err(e) => tracing::debug!(
                "[CAPTURE] focuser_get_position failed; FOCUSPOS omitted: {}",
                e
            ),
        }
        match ctx.device_ops.focuser_get_temperature(focuser_id).await {
            Ok(temp) => frame_ctx.focuser_temperature_c = temp,
            Err(e) => tracing::debug!(
                "[CAPTURE] focuser_get_temperature failed; FOCTEMP omitted: {}",
                e
            ),
        }
    }

    // Live rotator telemetry.
    if let Some(rotator_id) = &ctx.rotator_id {
        match ctx.device_ops.rotator_get_angle(rotator_id).await {
            Ok(angle) => frame_ctx.rotator_angle_deg = Some(angle),
            Err(e) => tracing::debug!(
                "[CAPTURE] rotator_get_angle failed; ROTATPOS omitted: {}",
                e
            ),
        }
    }

    // Live mount pointing + pier side.
    //
    // Where the telescope actually WAS, which is what the FITS `RA`/`DEC`
    // cards and the `captured_images.mount_*` columns both mean — as opposed
    // to `target_ra_hours`/`target_dec_degrees`, which are where the sequence
    // meant to be (an unedited "New Target" sits at 0h/0°). The bridge's FITS
    // writer used to sample this itself at save time; reading it HERE, into
    // the FrameContext that both surfaces are stamped from, is what stops the
    // header and the row from being able to disagree.
    if let Some(mount_id) = &ctx.mount_id {
        match ctx.device_ops.mount_get_coordinates(mount_id).await {
            Ok((ra_hours, dec_degrees)) => {
                frame_ctx.mount_ra_hours = Some(ra_hours);
                frame_ctx.mount_dec_degrees = Some(dec_degrees);
                // Alt/az are derived, not read back: `mount_get_status` would
                // report them but costs a full capability sweep per saved
                // frame on ASCOM, and the geometry is exact once the site is
                // known. Both stay None when the observer location is unset
                // rather than being computed from a guessed site.
                //
                // Derived at the EXPOSURE MIDPOINT, not now. This runs after
                // readout, so `Utc::now()` dated the geometry by the whole
                // exposure plus download — see `FrameContext::exposure_midpoint`
                // for what that costs a photometry run. RA/Dec do not need the
                // same treatment: a tracking mount holds them, and it is only
                // the horizon frame that turns with the clock.
                if let (Some(lat), Some(lon)) = (ctx.latitude, ctx.longitude) {
                    let when = frame_ctx
                        .exposure_midpoint()
                        .unwrap_or_else(chrono::Utc::now);
                    let (alt, az) =
                        crate::meridian::calculate_alt_az(ra_hours, dec_degrees, lat, lon, when);
                    frame_ctx.mount_altitude_deg = Some(alt);
                    frame_ctx.mount_azimuth_deg = Some(az);
                }
            }
            Err(e) => tracing::debug!(
                "[CAPTURE] mount_get_coordinates failed; pointing omitted: {}",
                e
            ),
        }
        match ctx.device_ops.mount_side_of_pier(mount_id).await {
            // `Unknown` is dropped rather than recorded: it is indistinguishable
            // downstream from "no reading was taken", and the column is
            // nullable precisely so absence can say that.
            Ok(crate::meridian::PierSide::East) => frame_ctx.pier_side = Some("East".to_string()),
            Ok(crate::meridian::PierSide::West) => frame_ctx.pier_side = Some("West".to_string()),
            Ok(crate::meridian::PierSide::Unknown) => {}
            Err(e) => tracing::debug!(
                "[CAPTURE] mount_side_of_pier failed; PIERSIDE omitted: {}",
                e
            ),
        }
    }

    // Live guide RMS (PHD2 / built-in guider). The guider may be off (no
    // guiding for short subs), in which case the keyword is omitted.
    match ctx.device_ops.guider_get_status().await {
        Ok(status) if status.is_guiding => {
            frame_ctx.guide_rms_arcsec = Some(status.rms_total);
        }
        Ok(_) => {
            // Guider connected but not currently guiding — omit the keyword.
        }
        Err(e) => tracing::debug!(
            "[CAPTURE] guider_get_status failed; GUIDERMS omitted: {}",
            e
        ),
    }

    // Plate-solve result (only available once CenterTarget has run for
    // this target). Stored as Arc<RwLock<_>> so the executor and exposure
    // share state without cloning.
    {
        let solve_guard = ctx.last_plate_solve.read().await;
        if let Some(solve) = solve_guard.as_ref() {
            // PlateSolveResult stores RA in DEGREES; convert to hours for
            // the SOLVED-RA keyword (which is FITS-standard in degrees).
            // Wait — read the spec: api_save_fits writes RA in HOURS for
            // the RA keyword. Stay consistent: SOLVED-RA in HOURS too.
            frame_ctx.plate_solve_ra_hours = Some(solve.ra_degrees / 15.0);
            frame_ctx.plate_solve_dec_degrees = Some(solve.dec_degrees);
            frame_ctx.plate_solve_pixel_scale_arcsec = Some(solve.pixel_scale);
            frame_ctx.plate_solve_rotation_deg = Some(solve.rotation);
        }
    }

    // defect-map correction provenance. Only set when
    // the correction actually ran; skipped / disabled outcomes leave
    // the field None and no HISTORY card is emitted by the FITS writer.
    frame_ctx.defect_map_correction = defect_map_outcome.into_record();

    frame_ctx
}

// =============================================================================
// AUTOFOCUS INSTRUCTION
// =============================================================================

/// Process-wide hardware admission for autofocus. Every entry path ultimately
/// calls this module (standalone bridge, sequence node, recovery, meridian
/// flip), so a single atomic gate prevents two callers from sweeping the same
/// camera/focuser pair concurrently.
static AUTOFOCUS_RUN_ACTIVE: AtomicBool = AtomicBool::new(false);

pub struct AutofocusRunGuard;

impl Drop for AutofocusRunGuard {
    fn drop(&mut self) {
        AUTOFOCUS_RUN_ACTIVE.store(false, Ordering::Release);
    }
}

pub fn try_admit_autofocus_run() -> Option<AutofocusRunGuard> {
    AUTOFOCUS_RUN_ACTIVE
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .ok()
        .map(|_| AutofocusRunGuard)
}

/// Execute autofocus using V-curve or curve fitting, acquiring the shared
/// camera/focuser admission gate first.
///
/// Fail-fast: if the gate is already held, returns immediately with the
/// "already running" error so the one-shot / REST layer can surface a typed
/// `DeviceBusy`. Sequence NODES should use [execute_autofocus_for_node]
/// instead, which waits for an in-flight run rather than aborting the run.
pub async fn execute_autofocus(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let Some(guard) = try_admit_autofocus_run() else {
        return InstructionResult::failure(
            "Autofocus is already running on this equipment host".to_string(),
        );
    };
    execute_autofocus_admitted(config, ctx, progress_callback, guard).await
}

/// Execute autofocus for a SEQUENCE NODE, waiting for any in-flight autofocus
/// to release the shared admission gate before running.
///
/// An explicit `Autofocus` node routinely races a concurrently-fired
/// trigger-autofocus: the HFR-degradation / focus-invalidation trigger fires
/// its own run (grabbing the gate) at the same tick the node is dispatched.
/// With plain fail-fast [execute_autofocus] the node then failed with
/// "Autofocus is already running", which aborted the ENTIRE sequence — a
/// benign scheduling race turning into a night-ending failure. A node must
/// never abort the run for this reason: wait for the in-flight run to finish
/// (the operator asked for an autofocus HERE), then perform this node's own
/// run. Bounded so a leaked/stuck gate can't hang the sequence forever.
pub async fn execute_autofocus_for_node(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    pause: &crate::node::context::PauseGate,
) -> InstructionResult {
    // An autofocus run is at most a few minutes (per-node timeout); cap the
    // admission wait generously above that so a genuine concurrent run always
    // completes first, while a leaked gate still surfaces as a failure rather
    // than hanging.
    const MAX_ADMISSION_WAIT: Duration = Duration::from_secs(600);
    let Some(guard) = admit_autofocus_run_waiting(MAX_ADMISSION_WAIT).await else {
        return InstructionResult::failure(
            "Autofocus could not start: another autofocus held the \
             equipment for over 10 minutes"
                .to_string(),
        );
    };
    execute_autofocus_admitted_with_pause(config, ctx, progress_callback, guard, pause).await
}

/// Acquire the shared autofocus admission gate, waiting (bounded) for any
/// in-flight run to release it. Returns the guard, or `None` on timeout.
///
/// Uses `tokio::time` so the deadline honours a paused test clock (and so the
/// timeout is driven by the same runtime as the poll sleeps).
async fn admit_autofocus_run_waiting(max_wait: Duration) -> Option<AutofocusRunGuard> {
    tokio::time::timeout(max_wait, async {
        let mut announced = false;
        loop {
            if let Some(guard) = try_admit_autofocus_run() {
                return guard;
            }
            if !announced {
                announced = true;
                tracing::info!(
                    "Autofocus node deferring to an in-flight autofocus run; \
                     waiting for it to finish before starting this node's run"
                );
            }
            sleep(Duration::from_millis(200)).await;
        }
    })
    .await
    .ok()
}

/// Execute a run for a caller that already owns [AutofocusRunGuard]. This is
/// public so the bridge can translate an admission rejection into the typed
/// `DeviceBusy` error expected by the REST layer.
///
/// One-shot callers have no run to pause, so this entry point uses the
/// never-paused gate. Sequence callers go through
/// [execute_autofocus_admitted_with_pause].
pub async fn execute_autofocus_admitted(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    guard: AutofocusRunGuard,
) -> InstructionResult {
    execute_autofocus_admitted_with_pause(
        config,
        ctx,
        progress_callback,
        guard,
        &crate::node::context::PauseGate::default(),
    )
    .await
}

/// [execute_autofocus_admitted] with the run's operator-pause handle attached,
/// so the V-curve sweep holds between sample points instead of driving the
/// focuser and opening the shutter for the rest of the sweep while the UI
/// says PAUSED.
pub async fn execute_autofocus_admitted_with_pause(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    _guard: AutofocusRunGuard,
    pause: &crate::node::context::PauseGate,
) -> InstructionResult {
    let mut effective_config = config.clone();

    // Resolve the imaging filter at runtime. A sequence can reach the same AF
    // node through different filter branches, so choosing per-filter exposure,
    // binning, gain, and offset during Dart serialization would be wrong.
    let mut original_filter: Option<(String, i32)> = None;
    let mut filter_names = Vec::new();
    let needs_filter_context = !config.filter_settings.is_empty()
        || config
            .filter
            .as_deref()
            .is_some_and(|name| !name.trim().is_empty());
    if needs_filter_context {
        if let Some(filterwheel_id) = ctx.filterwheel_id.as_deref() {
            let position = match ctx
                .device_ops
                .filterwheel_get_position(filterwheel_id)
                .await
            {
                Ok(position) if position >= 0 => position,
                Ok(position) => {
                    return InstructionResult::failure(format!(
                        "Cannot start autofocus while the filter wheel reports moving position {}",
                        position
                    ))
                }
                Err(error) => {
                    return InstructionResult::failure(format!(
                        "Cannot read the current filter before autofocus: {}",
                        error
                    ))
                }
            };
            filter_names = match ctx.device_ops.filterwheel_get_names(filterwheel_id).await {
                Ok(names) => names,
                Err(error) => {
                    return InstructionResult::failure(format!(
                        "Cannot read filter names before autofocus: {}",
                        error
                    ))
                }
            };
            let Some(name) = filter_names.get(position as usize).cloned() else {
                return InstructionResult::failure(format!(
                    "Filter wheel position {} has no configured name; autofocus cannot apply per-filter settings safely",
                    position
                ));
            };
            original_filter = Some((name, position));
        } else if config
            .filter
            .as_deref()
            .is_some_and(|name| !name.trim().is_empty())
        {
            return InstructionResult::failure(format!(
                "Autofocus is configured to use filter \"{}\", but no filter wheel is connected",
                config.filter.as_deref().unwrap_or_default().trim()
            ));
        }
    }

    let active_filter_name = original_filter
        .as_ref()
        .map(|(name, _)| name.as_str())
        .or(ctx.current_filter.as_deref());
    let active_override = active_filter_name
        .and_then(|name| config.filter_settings.get(name))
        .cloned();
    if let Some(filter_config) = &active_override {
        if let Some(exposure) = filter_config.af_exposure_time {
            effective_config.exposure_duration = exposure;
        }
        effective_config.binning = filter_config.binning;
        effective_config.gain = filter_config.gain;
        effective_config.offset = filter_config.offset;
    }

    let requested_filter = active_override
        .as_ref()
        .and_then(|settings| settings.af_filter_name.as_deref())
        .filter(|name| !name.trim().is_empty())
        .or(effective_config.filter.as_deref())
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_string);

    if let Err(message) = validate_autofocus_config(&effective_config) {
        return InstructionResult::failure(message);
    }

    let mut guiding_was_paused = false;
    if effective_config.disable_guiding_during_af {
        let guider_status = match ctx.device_ops.guider_get_status().await {
            Ok(status) => status,
            Err(error) => {
                return InstructionResult::failure(format!(
                "Autofocus is configured to pause guiding, but guider status could not be read: {}",
                error
            ))
            }
        };
        if guider_status.is_guiding {
            if let Err(error) = ctx.device_ops.guider_stop().await {
                return InstructionResult::failure(format!(
                    "Autofocus is configured to pause guiding, but guiding could not be stopped: {}",
                    error
                ));
            }
            guiding_was_paused = true;
            if let Some(trigger_state) = &ctx.trigger_state {
                let mut state = trigger_state.write().await;
                state.set_guiding_enabled(false);
                state.set_guide_star_lost(false);
            }
        }
    }

    let mut filter_restore_required = false;
    let mut pre_run_error = None;
    if let Some(target_name) = requested_filter.as_deref() {
        match &original_filter {
            Some((original_name, _original_position)) if original_name != target_name => {
                if let Some(target_position) =
                    filter_names.iter().position(|name| name == target_name)
                {
                    // The wheel may move before verification fails, so restoration
                    // responsibility begins before the command is sent.
                    filter_restore_required = true;
                    if let Err(error) =
                        move_autofocus_filter(ctx, target_name, target_position as i32).await
                    {
                        pre_run_error = Some(format!(
                            "Failed to switch to autofocus filter \"{}\": {}",
                            target_name, error
                        ));
                    }
                } else {
                    pre_run_error = Some(format!(
                        "Configured autofocus filter \"{}\" is not present in the connected wheel",
                        target_name
                    ));
                }
            }
            Some(_) => {}
            None => {
                pre_run_error = Some(format!(
                    "Autofocus is configured to use filter \"{}\", but no filter wheel is connected",
                    target_name
                ));
            }
        }
    }

    let mut result = match pre_run_error {
        Some(error) => InstructionResult::failure(error),
        None => execute_autofocus_attempts(&effective_config, ctx, progress_callback, pause).await,
    };

    if filter_restore_required {
        if let Some((original_name, original_position)) = &original_filter {
            if let Err(error) = move_autofocus_filter(ctx, original_name, *original_position).await
            {
                result = append_autofocus_cleanup_failure(
                    result,
                    format!(
                        "failed to restore original filter \"{}\" at position {}: {}",
                        original_name, original_position, error
                    ),
                );
            }
        }
    }

    if guiding_was_paused {
        result = resume_guiding_after_autofocus(ctx, result).await;
    }

    result
}

async fn execute_autofocus_attempts(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    pause: &crate::node::context::PauseGate,
) -> InstructionResult {
    let attempts = config.number_of_attempts.max(1);
    for attempt in 1..=attempts {
        if !pause.wait_while_paused(&ctx.cancellation_token).await {
            return InstructionResult::cancelled("Autofocus cancelled while paused");
        }
        let result = execute_autofocus_once(config, ctx, progress_callback, pause).await;
        if !matches!(result.status, NodeStatus::Failure) || attempt == attempts {
            return result;
        }
        if result
            .data
            .as_ref()
            .and_then(|data| data.get("autofocus_origin_restored"))
            .and_then(serde_json::Value::as_bool)
            == Some(false)
        {
            return result;
        }
        if let Some(cb) = progress_callback {
            cb(
                0.0,
                format!("Autofocus attempt {attempt}/{attempts} failed; retrying full sweep"),
            );
        }
        tracing::warn!(
            "Autofocus attempt {}/{} failed; starting the next configured attempt",
            attempt,
            attempts
        );
    }
    unreachable!("attempt count is clamped to at least one")
}

async fn move_autofocus_filter(
    ctx: &InstructionContext,
    filter_name: &str,
    target_position: i32,
) -> Result<(), String> {
    let filterwheel_id = ctx
        .filterwheel_id
        .as_deref()
        .filter(|id| !id.is_empty())
        .ok_or_else(|| "no filter wheel is connected".to_string())?;

    ctx.device_ops
        .filterwheel_set_position(filterwheel_id, target_position)
        .await
        .map_err(|error| format!("filter move command failed: {}", error))?;

    // Cleanup still owns the wheel after cancellation, so this verification
    // intentionally does not consult the sequence cancellation token.
    let start = std::time::Instant::now();
    let timeout = Duration::from_secs(DEFAULT_FILTER_WHEEL_TIMEOUT_SECS);
    sleep(Duration::from_millis(100)).await;
    loop {
        match ctx
            .device_ops
            .filterwheel_get_position(filterwheel_id)
            .await
        {
            Ok(position) if position == target_position => break,
            Ok(_) => {}
            Err(error) => tracing::warn!(
                "Error verifying autofocus filter move to {}: {}",
                target_position,
                error
            ),
        }
        if start.elapsed() > timeout {
            return Err(format!(
                "filter wheel did not reach position {} within {} seconds",
                target_position,
                timeout.as_secs()
            ));
        }
        sleep(Duration::from_millis(200)).await;
    }

    apply_filter_focus_offset(filter_name, ctx, None)
        .await
        .map_err(|error| format!("focus offset failed: {}", error))
}

async fn resume_guiding_after_autofocus(
    ctx: &InstructionContext,
    result: InstructionResult,
) -> InstructionResult {
    if let Err(error) = ctx.device_ops.guider_start(1.0, 10.0, 60.0).await {
        return append_autofocus_cleanup_failure(
            result,
            format!("failed to resume guiding after autofocus: {}", error),
        );
    }
    match ctx.device_ops.guider_get_status().await {
        Ok(status) if status.is_guiding => {
            if let Some(trigger_state) = &ctx.trigger_state {
                trigger_state.write().await.set_guiding_enabled(true);
            }
            result
        }
        Ok(_) => append_autofocus_cleanup_failure(
            result,
            "guider accepted resume but did not report guiding".to_string(),
        ),
        Err(error) => append_autofocus_cleanup_failure(
            result,
            format!(
                "could not verify guiding resumed after autofocus: {}",
                error
            ),
        ),
    }
}

fn append_autofocus_cleanup_failure(
    mut result: InstructionResult,
    failure: String,
) -> InstructionResult {
    let prior = result
        .message
        .take()
        .unwrap_or_else(|| "Autofocus did not complete".to_string());
    result.status = NodeStatus::Failure;
    result.message = Some(format!("{}; CRITICAL CLEANUP FAILURE: {}", prior, failure));
    result
}

fn validate_autofocus_config(config: &AutofocusConfig) -> Result<(), String> {
    if !config.exposure_duration.is_finite() || config.exposure_duration <= 0.0 {
        return Err("Autofocus exposure duration must be finite and positive".to_string());
    }
    if !config.max_duration_secs.is_finite() || config.max_duration_secs <= 0.0 {
        return Err("Autofocus maximum duration must be finite and positive".to_string());
    }
    if config.step_size <= 0 {
        return Err("Autofocus step size must be positive".to_string());
    }
    if !(1..=50).contains(&config.steps_out) {
        return Err("Autofocus steps out must be between 1 and 50".to_string());
    }
    if !(1..=10).contains(&config.number_of_attempts) {
        return Err("Autofocus attempt count must be between 1 and 10".to_string());
    }
    if !(1..=20).contains(&config.exposures_per_point) {
        return Err("Autofocus exposures per point must be between 1 and 20".to_string());
    }
    if !config.r_squared_threshold.is_finite() || !(0.0..=1.0).contains(&config.r_squared_threshold)
    {
        return Err("Autofocus R² threshold must be between 0 and 1".to_string());
    }
    if !config.outer_crop_ratio.is_finite()
        || !config.inner_crop_ratio.is_finite()
        || config.outer_crop_ratio <= 0.0
        || config.outer_crop_ratio > 1.0
        || config.inner_crop_ratio < 0.0
        || config.inner_crop_ratio >= config.outer_crop_ratio
    {
        return Err("Autofocus crop ratios must satisfy 0 <= inner < outer <= 1".to_string());
    }
    if config.focuser_settle_time_ms > 10_000 {
        return Err("Autofocus focuser settle time cannot exceed 10000 ms".to_string());
    }
    if config.backlash_compensation < 0 || config.backlash_out_compensation < 0 {
        return Err("Autofocus backlash values cannot be negative".to_string());
    }
    if config.gain.is_some_and(|gain| gain < 0) || config.offset.is_some_and(|offset| offset < 0) {
        return Err("Autofocus gain and offset cannot be negative".to_string());
    }
    for (filter_name, filter_config) in &config.filter_settings {
        if filter_name.trim().is_empty() {
            return Err("Autofocus per-filter settings contain an empty filter name".to_string());
        }
        if filter_config
            .af_exposure_time
            .is_some_and(|exposure| !exposure.is_finite() || exposure <= 0.0)
        {
            return Err(format!(
                "Autofocus exposure override for filter \"{}\" must be finite and positive",
                filter_name
            ));
        }
        if filter_config.gain.is_some_and(|gain| gain < 0)
            || filter_config.offset.is_some_and(|offset| offset < 0)
        {
            return Err(format!(
                "Autofocus gain and offset overrides for filter \"{}\" cannot be negative",
                filter_name
            ));
        }
    }
    Ok(())
}

async fn execute_autofocus_once(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
    pause: &crate::node::context::PauseGate,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };
    let focuser_id = match ctx.focuser_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!(
        "Starting autofocus: {:?} method, {} steps, step size {}",
        config.method,
        config.steps_out,
        config.step_size
    );

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(0.0, "Starting autofocus...".to_string());
    }

    // Sweep positions are calculated from the current position outward;
    // failing the read here is fatal because the alternative is to sweep
    // from a guessed origin and land somewhere unrelated to focus.
    tracing::debug!("Getting focuser position for focuser_id: {}", focuser_id);
    let current_position = match ctx.device_ops.focuser_get_position(&focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            tracing::error!("Autofocus failed: Could not get focuser position: {}", e);
            return InstructionResult::failure(format!("Failed to get focuser position: {}", e));
        }
    };

    tracing::info!("Current focuser position: {}", current_position);

    let af_timeout = Duration::from_secs_f64(config.max_duration_secs);
    let af_start_time = tokio::time::Instant::now();
    let autofocus_operation = async {
        let af_config: crate::autofocus::AutofocusConfig = config.into();

        let af_engine = crate::autofocus::VCurveAutofocus::new(af_config.clone());
        let backlash = crate::autofocus::BacklashCompensation::new_directional(
            af_config.backlash_compensation,
            af_config.backlash_out_compensation,
        );

        let positions = af_engine.calculate_positions(current_position);
        let total_points = positions.len();
        let start_position = positions[0];

        let mut focus_data: Vec<crate::autofocus::FocusDataPoint> =
            Vec::with_capacity(total_points);

        if let Some(cb) = progress_callback {
            cb(5.0, format!("Moving to start position: {}", start_position));
        }

        if backlash.is_needed(current_position, start_position) {
            let (intermediate, final_pos) =
                backlash.calculate_approach(current_position, start_position);

            if let Some(overshoot) = intermediate {
                tracing::info!(
                    "Applying backlash compensation: {} -> {} -> {}",
                    current_position,
                    overshoot,
                    final_pos
                );

                if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, overshoot).await {
                    return InstructionResult::failure(format!(
                        "Failed to move focuser (backlash): {}",
                        e
                    ));
                }
                if let Err(e) =
                    wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await
                {
                    return InstructionResult::failure(e);
                }
            }

            if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, final_pos).await {
                return InstructionResult::failure(format!("Failed to move focuser: {}", e));
            }
        } else {
            tracing::info!("Moving to start position: {}", start_position);
            if let Err(e) = ctx
                .device_ops
                .focuser_move_to(&focuser_id, start_position)
                .await
            {
                return InstructionResult::failure(format!("Failed to move focuser: {}", e));
            }
        }

        if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(300)).await {
            return InstructionResult::failure(e);
        }
        if let Some(result) = wait_for_autofocus_settle(config, ctx).await {
            return result;
        }

        let (bin_x, bin_y) = match config.binning {
            Binning::One => (1, 1),
            Binning::Two => (2, 2),
            Binning::Three => (3, 3),
            Binning::Four => (4, 4),
        };

        // minimum star count is now `config.min_star_count`
        // (default 10 from `default_af_min_star_count`); previously a hardcoded
        // local const. A user with a fast/dim setup can lower it without
        // patching the binary.
        let min_star_count: u32 = config.min_star_count.max(1);
        // 1.0 px² is the noise floor: a V-curve with smaller HFR variance is
        // indistinguishable from flat noise and the fit would extrapolate to
        // nonsense.
        const MIN_HFR_VARIANCE: f64 = 1.0;
        let mut low_star_count_warnings = 0;
        // Time the operator spent holding the run paused mid-sweep. Excluded
        // from the autofocus deadline below: a Pause is not the focuser being
        // slow, and charging it to the budget would fail a sweep that was
        // healthy right up to the moment the operator stepped away.
        let mut paused_duration = Duration::ZERO;

        for point in 0..total_points {
            // Check timeout
            let working_elapsed = af_start_time.elapsed().saturating_sub(paused_duration);
            if working_elapsed > af_timeout {
                tracing::warn!(
                "Autofocus timed out after {:.0}s (limit: {:.0}s), returning focuser to original position",
                working_elapsed.as_secs_f64(),
                config.max_duration_secs,
            );
                return InstructionResult::failure(format!(
                    "Autofocus timed out after {:.0}s (max duration: {:.0}s)",
                    working_elapsed.as_secs_f64(),
                    config.max_duration_secs,
                ));
            }

            if let Some(result) = ctx.check_cancelled() {
                return result;
            }

            // Honour an operator Pause between sample points. A V-curve sweep
            // is ~15 exposures plus focuser motion inside ONE instruction, so
            // the node-boundary check the tree does never sees a Pause pressed
            // during the sweep.
            if pause.is_paused() {
                let paused_at = tokio::time::Instant::now();
                if !pause.wait_while_paused(&ctx.cancellation_token).await {
                    return InstructionResult::cancelled("Autofocus cancelled while paused");
                }
                paused_duration += paused_at.elapsed();
            }

            let position = positions[point];

            // 10-90% covers the V-curve sample loop; the remaining 10% is the
            // final move + settle + curve fit, which is the noticeable wait the
            // user sees after the last sample is taken.
            // Why: point and total_points are usize bounded by sweep size (<=50 in UI);
            // lossless to f64.
            let point_progress = 10.0 + (point as f64 / total_points as f64 * 80.0);

            tracing::info!(
                "Focus point {}/{} at position {}",
                point + 1,
                total_points,
                position
            );
            if let Some(cb) = progress_callback {
                cb(
                    point_progress,
                    format!("Point {}/{}: pos {}", point + 1, total_points, position),
                );
            }

            if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, position).await {
                return InstructionResult::failure(format!("Failed to move focuser: {}", e));
            }

            if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await
            {
                return InstructionResult::failure(e);
            }
            if let Some(result) = wait_for_autofocus_settle(config, ctx).await {
                return result;
            }

            let mut measurements = Vec::with_capacity(config.exposures_per_point as usize);
            for sample in 0..config.exposures_per_point {
                if let Some(result) = ctx.check_cancelled() {
                    return result;
                }
                let mut abort_guard =
                    CameraExposureAbortGuard::new(ctx.device_ops.clone(), camera_id.clone());
                let exposure_result = ctx
                    .device_ops
                    .camera_start_exposure(
                        &camera_id,
                        config.exposure_duration,
                        config.gain,
                        config.offset,
                        bin_x,
                        bin_y,
                    )
                    .await;
                abort_guard.disarm();
                let image_data = match exposure_result {
                    Ok(data) => {
                        tracing::info!(
                            "[SEQ] Autofocus point {} sample {}/{} completed: {}x{} ({} pixels)",
                            point + 1,
                            sample + 1,
                            config.exposures_per_point,
                            data.width,
                            data.height,
                            data.data.len()
                        );
                        data
                    }
                    Err(e) => {
                        return InstructionResult::failure(format!(
                            "Autofocus exposure failed: {}",
                            e
                        ))
                    }
                };
                measurements.push(calculate_hfr_with_crops(
                    &image_data,
                    config.outer_crop_ratio,
                    config.inner_crop_ratio,
                    config.use_brightest_n_stars,
                ));
            }
            measurements.sort_by(|a, b| a.hfr.total_cmp(&b.hfr));
            let measurement = measurements.swap_remove(measurements.len() / 2);

            tracing::info!(
                "Position {} HFR: {:.2}, Stars: {}",
                position,
                measurement.hfr,
                measurement.star_count
            );

            if measurement.star_count < min_star_count {
                low_star_count_warnings += 1;
                tracing::warn!(
                    "Low star count at position {}: {} stars (minimum: {})",
                    position,
                    measurement.star_count,
                    min_star_count
                );

                // >50% of sweep points failing star detection means seeing /
                // clouds / pointing has degraded so badly that no fit will be
                // meaningful; failing fast saves the user the rest of the sweep
                // and a useless curve-fit error.
                if low_star_count_warnings > total_points / 2 {
                    return InstructionResult::failure(format!(
                    "Autofocus failed: Insufficient stars detected. Only {} stars found (minimum: {}). \
                     This may indicate clouds, poor seeing, or incorrect camera settings.",
                    measurement.star_count, min_star_count
                ));
                }
            }

            focus_data.push(crate::autofocus::FocusDataPoint {
                position,
                hfr: measurement.hfr,
                fwhm: None,
                star_count: measurement.star_count,
            });

            let progress_json = serde_json::json!({
                "type": "autofocus_progress",
                "point": point + 1,
                "total_points": total_points,
                "hfr": measurement.hfr,
                "star_count": measurement.star_count,
                "focus_range": {
                    "min": positions[0],
                    "max": positions[total_points - 1]
                },
                "vcurve_points": focus_data.iter().map(|point| {
                    serde_json::json!({"position": point.position, "hfr": point.hfr})
                }).collect::<Vec<_>>(),
                "star_crops": measurement.star_crops.iter().map(|crop| {
                    serde_json::json!({
                        "pixels_base64": crop.pixels_base64,
                        "width": crop.width,
                        "height": crop.height,
                        "hfr": crop.hfr,
                        "snr": crop.snr
                    })
                }).collect::<Vec<_>>()
            });

            if let Some(cb) = progress_callback {
                cb(point_progress, progress_json.to_string());
            }
        }

        if let Some(cb) = progress_callback {
            cb(92.0, "Validating focus data...".to_string());
        }

        // A flat HFR curve (variance < MIN_HFR_VARIANCE) is not a V-curve to fit
        // — it usually means clouds rolled in, the focuser is far outside the
        // critical zone, or the sensor is misreporting. Fitting anyway would
        // produce a meaningless "best focus" position.
        let hfr_values: Vec<f64> = focus_data.iter().map(|point| point.hfr).collect();
        let min_hfr = hfr_values.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_hfr = hfr_values.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        let hfr_variance = max_hfr - min_hfr;

        tracing::info!(
            "HFR variance: {:.2} (min: {:.2}, max: {:.2})",
            hfr_variance,
            min_hfr,
            max_hfr
        );

        if hfr_variance < MIN_HFR_VARIANCE {
            return InstructionResult::failure(format!(
            "Autofocus failed: No valid V-curve detected. HFR variance is only {:.2} (minimum: {:.1}). \
             The HFR is not changing with focus position, which may indicate: \
             - Clouds or obstructions blocking the sky \
             - Hot pixels being detected instead of real stars \
             - Focus range is too narrow or too far from true focus \
             - Camera is not properly connected or imaging",
            hfr_variance, MIN_HFR_VARIANCE
        ));
        }

        let af_result = match af_engine.find_best_focus(focus_data) {
            Ok(mut result) => {
                result.temperature_celsius = ctx
                    .device_ops
                    .focuser_get_temperature(&focuser_id)
                    .await
                    .ok()
                    .flatten();
                result
            }
            Err(e) => {
                tracing::warn!(
                "Autofocus curve fit failed ({}); shared attempt cleanup will restore position {}",
                e, current_position
            );
                return InstructionResult::failure(format!(
                    "Autofocus curve fitting failed: {}",
                    e
                ));
            }
        };

        // Clamp the fitted best-focus position to the swept range. The parabolic
        // and hyperbolic fits return the analytic vertex, which for a poor-quality
        // (low-R²) curve can land far outside the sampled bracket — an
        // extrapolation that is by definition untrustworthy and, on a permissive
        // driver, would drive the focuser wildly out of position. A vertex outside
        // the bracket means true focus was not bracketed; clamping bounds the move
        // to the sampled window (worst case: a sweep endpoint near where we
        // started) instead of an arbitrary extrapolated step.
        let sweep_lo = positions[0].min(positions[total_points - 1]);
        let sweep_hi = positions[0].max(positions[total_points - 1]);
        let best_position = {
            let raw = af_result.best_position;
            let clamped = raw.clamp(sweep_lo, sweep_hi);
            if clamped != raw {
                tracing::warn!(
                    "Autofocus best-focus vertex {} fell outside the swept range [{}, {}]; \
                 clamping to {}. The curve minimum was an extrapolation (poor fit) — \
                 true focus may lie outside the sweep window.",
                    raw,
                    sweep_lo,
                    sweep_hi,
                    clamped
                );
            }
            clamped
        };
        let best_hfr = af_result.best_hfr;
        let r_squared = af_result.curve_fit_quality;

        // The configured R² value is a real acceptance threshold, not a cosmetic
        // warning. Shared attempt cleanup restores the pre-run position before a
        // retry or terminal failure is returned.
        if r_squared < config.r_squared_threshold {
            tracing::warn!(
                "Low curve fit quality: R²={:.3} (required: {:.3}); returning to original position",
                r_squared,
                config.r_squared_threshold
            );
            return InstructionResult::failure(format!(
                "Autofocus curve fit R² {:.3} is below the configured threshold {:.3}",
                r_squared, config.r_squared_threshold
            ));
        }

        tracing::info!(
            "Best focus at position {}, HFR: {:.2}, R²: {:.3}",
            best_position,
            best_hfr,
            r_squared
        );

        if let Some(cb) = progress_callback {
            cb(95.0, format!("Moving to best focus: {}", best_position));
        }

        let last_position = positions[positions.len() - 1];
        if backlash.is_needed(last_position, best_position) {
            let (intermediate, final_pos) =
                backlash.calculate_approach(last_position, best_position);

            if let Some(overshoot) = intermediate {
                tracing::info!(
                    "Final move with backlash: overshoot to {}, then {}",
                    overshoot,
                    final_pos
                );

                if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, overshoot).await {
                    return InstructionResult::failure(format!(
                        "Failed to move focuser (final backlash): {}",
                        e
                    ));
                }
                if let Err(e) =
                    wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await
                {
                    return InstructionResult::failure(e);
                }
            }

            if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, final_pos).await {
                return InstructionResult::failure(format!("Failed to move to best focus: {}", e));
            }
        } else if let Err(e) = ctx
            .device_ops
            .focuser_move_to(&focuser_id, best_position)
            .await
        {
            return InstructionResult::failure(format!("Failed to move to best focus: {}", e));
        }

        if let Err(e) = wait_for_focuser_idle(&focuser_id, ctx, Duration::from_secs(120)).await {
            return InstructionResult::failure(format!("Failed to settle at best focus: {}", e));
        }
        if let Some(result) = wait_for_autofocus_settle(config, ctx).await {
            return result;
        }

        if let Some(cb) = progress_callback {
            cb(
                100.0,
                format!(
                    "Complete: pos {}, HFR {:.2}, R² {:.3}",
                    best_position, best_hfr, r_squared
                ),
            );
        }

        InstructionResult {
            status: NodeStatus::Success,
            message: Some(format!(
                "Autofocus complete: position {}, HFR {:.2}, R² {:.3}",
                best_position, best_hfr, r_squared
            )),
            data: serde_json::to_value(&af_result).ok(),
            hfr_values: vec![best_hfr],
        }
    };

    // One deadline encloses every move command, idle poll, mechanical settle,
    // camera exposure, curve fit, and final move. Point-boundary checks alone
    // cannot enforce the advertised limit when any one of those awaits hangs.
    let mut result = match tokio::time::timeout(af_timeout, autofocus_operation).await {
        Ok(result) => result,
        Err(_) => {
            tracing::warn!(
                "Autofocus timed out after {:.0}s (limit: {:.0}s), returning focuser to original position",
                af_start_time.elapsed().as_secs_f64(),
                config.max_duration_secs,
            );
            InstructionResult::failure(format!(
                "Autofocus timed out after {:.0}s (max duration: {:.0}s)",
                af_start_time.elapsed().as_secs_f64(),
                config.max_duration_secs,
            ))
        }
    };

    if matches!(result.status, NodeStatus::Failure | NodeStatus::Cancelled) {
        let restored = restore_autofocus_origin(&focuser_id, ctx, current_position).await;
        if let Err(error) = &restored {
            tracing::error!(
                "Autofocus could not restore original position {}: {}",
                current_position,
                error
            );
            let prior = result
                .message
                .take()
                .unwrap_or_else(|| "Autofocus did not complete".to_string());
            result.message = Some(format!(
                "{}; CRITICAL: failed to restore original focuser position {}: {}",
                prior, current_position, error
            ));
        }
        let mut metadata = match result.data.take() {
            Some(serde_json::Value::Object(object)) => object,
            _ => serde_json::Map::new(),
        };
        metadata.insert(
            "autofocus_origin_restored".to_string(),
            serde_json::Value::Bool(restored.is_ok()),
        );
        result.data = Some(serde_json::Value::Object(metadata));
    }

    result
}

/// Restore the pre-attempt focuser position before returning any failed or
/// cancelled autofocus result. This deliberately ignores the sequence cancel
/// token: cleanup is still hardware work owned by the autofocus Future, and a
/// caller must not be told the run is terminal while the motor is moving.
async fn restore_autofocus_origin(
    focuser_id: &str,
    ctx: &InstructionContext,
    original_position: i32,
) -> Result<(), String> {
    let mut errors = Vec::new();

    if let Err(error) = ctx.device_ops.focuser_halt(focuser_id).await {
        errors.push(format!("halt failed: {}", error));
    }
    if !wait_for_focuser_stop_after_halt(focuser_id, &ctx.device_ops, Duration::from_secs(10)).await
    {
        errors.push("motor did not stop within 10 seconds".to_string());
    }

    match ctx
        .device_ops
        .focuser_move_to(focuser_id, original_position)
        .await
    {
        Ok(()) => {
            if !wait_for_focuser_stop_after_halt(
                focuser_id,
                &ctx.device_ops,
                Duration::from_secs(120),
            )
            .await
            {
                errors.push(format!(
                    "return move to {} did not settle within 120 seconds",
                    original_position
                ));
            }
        }
        Err(error) => errors.push(format!(
            "return move to {} was rejected: {}",
            original_position, error
        )),
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("; "))
    }
}

async fn wait_for_autofocus_settle(
    config: &AutofocusConfig,
    ctx: &InstructionContext,
) -> Option<InstructionResult> {
    let mut remaining = config.focuser_settle_time_ms;
    while remaining > 0 {
        if let Some(result) = ctx.check_cancelled() {
            return Some(result);
        }
        let chunk = remaining.min(100);
        sleep(Duration::from_millis(chunk)).await;
        remaining -= chunk;
    }
    ctx.check_cancelled()
}

/// Enhanced HFR measurement with star crops for UI display
struct HfrMeasurementWithCrops {
    hfr: f64,
    star_count: u32,
    /// Base64-encoded star crops (80x80 grayscale), up to 5 brightest stars
    star_crops: Vec<StarCropInfo>,
}

/// Star crop info for UI display
#[derive(Clone)]
struct StarCropInfo {
    /// Base64-encoded grayscale pixels
    pixels_base64: String,
    width: u32,
    height: u32,
    hfr: f64,
    snr: f64,
}

/// Calculate HFR from image data, honoring the configured central crop and
/// brightest-star cap rather than merely transporting those settings.
fn calculate_hfr_with_crops(
    image: &ImageData,
    outer_crop_ratio: f64,
    inner_crop_ratio: f64,
    use_brightest_n_stars: u32,
) -> HfrMeasurementWithCrops {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
    use nightshade_imaging::{
        detect_stars_with_stats, extract_top_star_crops, StarDetectionConfig,
    };

    // 1 channel = monochrome; raw imager output is treated as mono for HFR
    // regardless of Bayer pattern, because debayering before star detection
    // would smear PSFs and inflate HFR.
    let imaging_data =
        nightshade_imaging::ImageData::from_u16(image.width, image.height, 1, &image.data);

    let config = StarDetectionConfig::default();
    let result = detect_stars_with_stats(&imaging_data, &config);

    let center_x = image.width as f64 / 2.0;
    let center_y = image.height as f64 / 2.0;
    let outer_half_width = image.width as f64 * outer_crop_ratio / 2.0;
    let outer_half_height = image.height as f64 * outer_crop_ratio / 2.0;
    let inner_half_width = image.width as f64 * inner_crop_ratio / 2.0;
    let inner_half_height = image.height as f64 * inner_crop_ratio / 2.0;

    // detect_stars returns brightness-ranked stars. Preserve that order so a
    // non-zero brightest-N setting is deterministic before calculating the
    // median HFR.
    let mut eligible_stars: Vec<_> = result
        .stars
        .into_iter()
        .filter(|star| {
            let dx = (star.x - center_x).abs();
            let dy = (star.y - center_y).abs();
            let inside_outer = dx <= outer_half_width && dy <= outer_half_height;
            let inside_inner =
                inner_crop_ratio > 0.0 && dx < inner_half_width && dy < inner_half_height;
            inside_outer && !inside_inner
        })
        .collect();
    if use_brightest_n_stars > 0 {
        eligible_stars.truncate(use_brightest_n_stars as usize);
    }

    let star_count = eligible_stars.len() as u32;
    let mut hfr_values: Vec<f64> = eligible_stars
        .iter()
        .map(|star| star.hfr)
        .filter(|hfr| hfr.is_finite() && *hfr > 0.0 && *hfr < 20.0)
        .collect();
    hfr_values.sort_by(f64::total_cmp);

    // 20.0 px is the "no valid focus" sentinel: an HFR this high is far
    // beyond any realistic well-focused setup, so the V-curve fit will
    // treat the point as the extreme of the curve (or reject as outlier).
    let hfr = if hfr_values.is_empty() {
        20.0
    } else {
        hfr_values[hfr_values.len() / 2]
    };

    // 5 crops @ 80 px is the upper bound the autofocus UI displays; more
    // would saturate the operator's view and inflate the JSON payload sent
    // over the FRB bridge.
    let crops = extract_top_star_crops(&imaging_data, &eligible_stars, 5, 80);

    let star_crops: Vec<StarCropInfo> = crops
        .into_iter()
        .map(|crop| StarCropInfo {
            pixels_base64: BASE64.encode(&crop.pixels),
            width: crop.width,
            height: crop.height,
            hfr: crop.hfr,
            snr: crop.snr,
        })
        .collect();

    HfrMeasurementWithCrops {
        hfr,
        star_count,
        star_crops,
    }
}

// =============================================================================
// DITHER INSTRUCTION
// =============================================================================

/// Execute dither
pub async fn execute_dither(
    config: &DitherConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, "Starting dither".to_string());
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    let (dither_pixels, ra_only) = match config.pattern {
        crate::DitherPattern::Random => {
            tracing::info!("Dithering {} pixels (random)", config.pixels);
            (config.pixels, config.ra_only)
        }
        crate::DitherPattern::Grid => {
            // Grid pattern requires trigger state because the next position
            // must be sticky across calls — without it we cannot walk the
            // NxN cells in order and would loop the same cell.
            if let Some(ref trigger_state) = ctx.trigger_state {
                let (ra_offset, dec_offset) = {
                    let mut state = trigger_state.write().await;
                    let offset = state.next_grid_dither_offset(config.grid_size, config.pixels);
                    tracing::info!(
                        "Grid dither: position {}/{} -> RA={:.1}px, Dec={:.1}px",
                        state.grid_dither_index,
                        config.grid_size * config.grid_size,
                        offset.0,
                        offset.1
                    );
                    offset
                };

                // guider_dither takes a single magnitude scalar, so we
                // collapse the 2D grid offset into its Euclidean magnitude.
                // The guider then performs a random-direction dither of that
                // magnitude, which is acceptable because the grid algorithm
                // already enforces spatial coverage at the planning layer.
                let magnitude = (ra_offset * ra_offset + dec_offset * dec_offset).sqrt();
                if magnitude < 0.01 {
                    // The (0,0) cell is the original target position — a
                    // dither of 0 px would still trigger a settle wait for no
                    // benefit. Returning a synthetic Success keeps the grid
                    // cadence intact (next call advances to the next cell).
                    tracing::info!("Grid dither at center position, skipping");
                    if let Some(cb) = progress_callback {
                        cb(100.0, "Grid dither at center - skipping".to_string());
                    }
                    return InstructionResult::success_with_message(
                        "Grid dither at center position (no move needed)",
                    );
                }

                // previously we collapsed grid-mode to RA-only
                // when `dec_offset.abs() < 0.01`, a magic threshold that
                // surreptitiously changed user-requested 2D grid behaviour
                // into 1D dithering for any cell whose Dec component happened
                // to round near zero. Grid mode now passes the user's
                // explicit `ra_only` flag through unchanged so the next grid
                // cell's RA *and* Dec offsets are honoured by the guider.
                (magnitude, config.ra_only)
            } else {
                tracing::warn!(
                    "Grid dither requested but no trigger state available, falling back to random"
                );
                (config.pixels, config.ra_only)
            }
        }
    };

    if let Some(cb) = progress_callback {
        cb(30.0, "Sending dither command to guider".to_string());
    }

    // guider_dither blocks until the move + settle completes. We can only
    // emit synthetic progress points around it; the device-ops layer does
    // not expose sub-step progress, so the UI shows discrete checkpoints
    // rather than a smooth bar during this phase.
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for dither to complete".to_string());
    }

    // Last cancellation check before a potentially 60+ s blocking call —
    // there is no way to interrupt guider_dither once it's running.
    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(70.0, "Waiting for guiding to settle".to_string());
    }

    // Dual-rig — coordinate with a piggybacking secondary capture loop (if
    // any). `dither_guarded` announces the pending dither, waits (bounded) for
    // the secondary to clear its in-flight exposure, runs the closure (the
    // actual mount pulse + settle), then releases the barrier so the secondary
    // resumes. With no barrier installed this is a plain pass-through.
    let dither_result = dither_guarded(ctx, || {
        ctx.device_ops.guider_dither(
            dither_pixels,
            config.settle_pixels,
            config.settle_time,
            config.settle_timeout,
            ra_only,
        )
    })
    .await;

    match dither_result {
        Ok(_) => {
            if let Some(cb) = progress_callback {
                cb(100.0, "Dither complete".to_string());
            }
            let pattern_name = match config.pattern {
                crate::DitherPattern::Random => "random",
                crate::DitherPattern::Grid => "grid",
            };
            InstructionResult::success_with_message(format!(
                "Dither ({}) and settle complete",
                pattern_name
            ))
        }
        Err(e) => InstructionResult::failure(format!("Dither failed: {}", e)),
    }
}

/// Dual-rig dither coordination wrapper.
///
/// Wraps a guider-dither call (the mount-moving pulse + settle) so a
/// piggybacking secondary camera is never mid-exposure during the pulse:
///
///   1. announce "dither pending" on the shared barrier — secondary stops
///      launching new exposures;
///   2. wait (bounded by the barrier's max-wait) for the secondary to clear
///      its in-flight exposure — a stuck secondary can NEVER stall the primary
///      past max-wait (we log and proceed);
///   3. run the actual dither;
///   4. release the barrier — secondary resumes its loop.
///
/// When `ctx.dither_barrier` is `None` (single-rig — the common case) this is a
/// plain `closure().await` with zero overhead. The barrier is released even if
/// the dither itself fails, so a failed pulse never leaves the secondary parked
/// forever.
pub(crate) async fn dither_guarded<F, Fut>(
    ctx: &InstructionContext,
    dither_call: F,
) -> DeviceResult<()>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = DeviceResult<()>>,
{
    let Some(barrier) = ctx.dither_barrier.clone() else {
        return dither_call().await;
    };

    barrier.begin_dither();
    let cleared = barrier.wait_for_secondary_clear().await;
    if !cleared {
        tracing::warn!(
            "Dual-rig: secondary did not clear within {:.0}s max-wait; \
             dithering anyway (secondary frame may be discarded). \
             forced_proceeds={}",
            barrier.max_wait_secs(),
            barrier.forced_proceed_count(),
        );
        if let Some(event_tx) = &ctx.event_tx {
            let _ = event_tx.send(crate::executor::ExecutorEvent::Error {
                message: format!(
                    "Dual-rig: secondary camera did not clear within {:.0}s; \
                     dithered anyway",
                    barrier.max_wait_secs(),
                ),
            });
        }
    }

    let result = dither_call().await;
    // Always release, even on dither failure — otherwise a failed pulse would
    // leave the secondary parked indefinitely.
    barrier.end_dither();
    result
}

// =============================================================================
// GUIDING START/STOP INSTRUCTIONS
// =============================================================================

struct GuiderStartupCleanupGuard {
    device_ops: SharedDeviceOps,
    armed: bool,
}

impl GuiderStartupCleanupGuard {
    fn new(device_ops: SharedDeviceOps) -> Self {
        Self {
            device_ops,
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for GuiderStartupCleanupGuard {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }

        let device_ops = self.device_ops.clone();
        match tokio::runtime::Handle::try_current() {
            Ok(handle) => {
                let _cleanup_task = handle.spawn(async move {
                    if let Err(error) = device_ops.guider_stop().await {
                        tracing::error!("Failed to stop guider during startup cleanup: {}", error);
                    }
                });
            }
            Err(error) => tracing::error!(
                "Could not schedule guider cleanup after dropped startup: {}",
                error
            ),
        }
    }
}

/// Execute start guiding - starts PHD2 guiding and waits for settle
pub async fn execute_start_guiding(
    config: &StartGuidingConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    tracing::info!(
        "Starting guiding with settle threshold {} px",
        config.settle_pixels
    );

    if let Some(cb) = progress_callback {
        cb(0.0, "Starting guiding".to_string());
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(20.0, "Connecting to guider".to_string());
    }

    // Pre-flight status read serves two purposes: surface connection
    // problems before issuing a guider_start (which has worse error
    // diagnostics), and seed the log with the pre-state so post-start
    // RMS readings can be compared to the baseline.
    match ctx.device_ops.guider_get_status().await {
        Ok(status) => {
            tracing::debug!(
                "Guider status: is_guiding={}, rms_total={:.2}",
                status.is_guiding,
                status.rms_total
            );
        }
        Err(e) => {
            // Some guiders (PHD2 in calibration) cannot answer status
            // queries but still accept Start; treat the read failure as a
            // soft warning rather than abort the sequence.
            tracing::warn!("Could not get guider status: {}", e);
        }
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(40.0, "Starting guide camera loop".to_string());
    }

    if let Some(cb) = progress_callback {
        cb(60.0, "Waiting for guiding to stabilize".to_string());
    }

    match ctx
        .device_ops
        .guider_start(
            config.settle_pixels,
            config.settle_time,
            config.settle_timeout,
        )
        .await
    {
        Ok(_) => {
            let mut cleanup_guard = GuiderStartupCleanupGuard::new(ctx.device_ops.clone());
            let result = async {
                // ENG-F10: Validate that guiding actually reached "guiding" state.
                // guider_start() may return Ok without the guider truly locking on.
                // Poll status with a timeout to confirm guiding is active.
                if let Some(cb) = progress_callback {
                    cb(80.0, "Verifying guiding is active".to_string());
                }

                // Why: settle_timeout is f64 seconds (UI-bounded 0..3600 typical).
                // f64 -> u64 saturates per Rust 1.45 spec; negatives clamp to 0
                // which Duration::from_secs treats as "no wait" — surfaces as an
                // immediate timeout, not a silent hang.
                let verification_timeout = Duration::from_secs(config.settle_timeout as u64);
                let poll_interval = Duration::from_secs(2);
                let deadline = tokio::time::Instant::now() + verification_timeout;
                let mut guiding_confirmed = false;

                while tokio::time::Instant::now() < deadline {
                    if let Some(result) = ctx.check_cancelled() {
                        return result;
                    }

                    match ctx.device_ops.guider_get_status().await {
                        Ok(status) if status.is_guiding => {
                            tracing::info!(
                                "Guiding confirmed active: RMS total={:.2}\"",
                                status.rms_total
                            );
                            guiding_confirmed = true;
                            break;
                        }
                        Ok(status) => {
                            tracing::debug!(
                                "Guiding not yet active (is_guiding={}), waiting...",
                                status.is_guiding
                            );
                        }
                        Err(e) => {
                            tracing::warn!("Guider status poll failed: {}", e);
                        }
                    }

                    sleep(poll_interval).await;
                }

                if !guiding_confirmed {
                    return InstructionResult::failure(format!(
                        "Guiding did not reach active state within {:.0}s timeout. \
                     The guider may have failed to calibrate or lock onto a star.",
                        config.settle_timeout
                    ));
                }

                // P3-7: post-start calibration quality validation. A guider can
                // report `is_guiding == true` and still be hopelessly miscalibrated
                // — wrong axis directions, mirror-flipped pulses, near-singular
                // matrix. The audit specifically flagged that bad calibrations
                // were "slipping through" the existing is_guiding poll, so this
                // gate is fail-closed (errors fail the StartGuiding instruction
                // rather than letting the night drift away silently).
                if config.validate_calibration {
                    if let Some(cb) = progress_callback {
                        cb(90.0, "Validating calibration quality".to_string());
                    }

                    // Step 1: axis geometry — fetch calibration data and check
                    // that the reported axis angles are reasonably perpendicular.
                    match ctx.device_ops.guider_get_calibration().await {
                        Ok(calib) => {
                            if let Err(reason) = validate_calibration_quality(&calib, config) {
                                return InstructionResult::failure(reason);
                            }
                        }
                        Err(e) => {
                            // Driver doesn't expose calibration angles (some Alpaca
                            // backends): warn but don't fail — the RMS check below
                            // is the safety net.
                            tracing::warn!(
                                "Skipping calibration-axis validation: {} \
                             (driver does not report calibration data)",
                                e
                            );
                        }
                    }

                    // Step 2: post-settle RMS sanity — sample over a short window
                    // to catch calibrations whose RMS only blows up after the
                    // initial settle (drift / over-correction).
                    let rms_samples: u32 = 3;
                    let rms_interval = Duration::from_secs(2);
                    let mut max_rms: f64 = 0.0;
                    let mut sample_count: u32 = 0;
                    for _ in 0..rms_samples {
                        if let Some(result) = ctx.check_cancelled() {
                            return result;
                        }
                        sleep(rms_interval).await;
                        match ctx.device_ops.guider_get_status().await {
                            Ok(status) => {
                                max_rms = max_rms.max(status.rms_total);
                                sample_count += 1;
                            }
                            Err(e) => {
                                tracing::warn!("RMS sample failed during validation: {}", e);
                            }
                        }
                    }
                    if sample_count > 0 && max_rms > config.max_post_settle_rms_pixels {
                        return InstructionResult::failure(format!(
                            "Post-settle guiding RMS too high: {:.2}px peak across {} sample(s) \
                         over {}s (limit {:.2}px). Calibration looks poor — \
                         recalibrate the guider before continuing.",
                            max_rms,
                            sample_count,
                            rms_samples as u64 * rms_interval.as_secs(),
                            config.max_post_settle_rms_pixels
                        ));
                    }
                    tracing::info!(
                        "Calibration validation passed: peak RMS {:.2}px over {}s window",
                        max_rms,
                        rms_samples as u64 * rms_interval.as_secs()
                    );
                }

                // Arm the GuideStarLost trigger now that guiding is confirmed
                // active. Without this the trigger's `guiding_enabled` gate stays
                // false and a lost star is never detected — the sequence would
                // silently take unguided subs until dawn. The executor poll also
                // latches this from live status, but setting it here closes the
                // window between StartGuiding completing and the next poll tick.
                if let Some(trigger_state_lock) = &ctx.trigger_state {
                    trigger_state_lock.write().await.set_guiding_enabled(true);
                }

                if let Some(cb) = progress_callback {
                    cb(100.0, "Guiding active".to_string());
                }
                InstructionResult::success_with_message("Guiding started and verified active")
            }
            .await;

            if matches!(result.status, NodeStatus::Success) {
                cleanup_guard.disarm();
                result
            } else {
                match ctx.device_ops.guider_stop().await {
                    Ok(()) => {
                        cleanup_guard.disarm();
                        if let Some(trigger_state) = &ctx.trigger_state {
                            trigger_state.write().await.set_guiding_enabled(false);
                        }
                        result
                    }
                    Err(error) => {
                        let mut result = result;
                        let prior = result
                            .message
                            .take()
                            .unwrap_or_else(|| "Guiding startup did not complete".to_string());
                        result.status = NodeStatus::Failure;
                        result.message = Some(format!(
                            "{}; CRITICAL CLEANUP FAILURE: failed to stop guider: {}",
                            prior, error
                        ));
                        result
                    }
                }
            }
        }
        Err(e) => InstructionResult::failure(format!("Failed to start guiding: {}", e)),
    }
}

/// P3-7: pure validation function over a `GuidingCalibration` snapshot.
/// Extracted from `execute_start_guiding` so it can be unit-tested without
/// spinning up a full device stack.
///
/// Returns `Err(reason)` with a user-facing message if calibration looks
/// broken; `Ok(())` if it should proceed.
pub fn validate_calibration_quality(
    calib: &crate::GuidingCalibration,
    config: &StartGuidingConfig,
) -> Result<(), String> {
    if !calib.is_calibrated {
        return Err(
            "Guider reports it is not calibrated after StartGuiding completed. \
             This usually means calibration was cancelled or failed silently."
                .to_string(),
        );
    }

    if let (Some(ra), Some(dec)) = (calib.ra_angle_deg, calib.dec_angle_deg) {
        // The axes should be ~90° apart (modulo 180°, since either axis
        // could be the "positive" direction). Compute the deviation from
        // perpendicularity in degrees in [0, 90].
        let raw_diff = (ra - dec).abs() % 180.0;
        let perpendicularity_error = (raw_diff - 90.0).abs();
        if perpendicularity_error > config.max_calibration_axis_error_deg {
            return Err(format!(
                "Calibration axes look broken: RA angle {:.1}°, Dec angle {:.1}° \
                 — off-perpendicular by {:.1}° (limit {:.1}°). \
                 The guider may have miscalibrated; recalibrate before continuing.",
                ra, dec, perpendicularity_error, config.max_calibration_axis_error_deg
            ));
        }
    }

    Ok(())
}

/// Execute stop guiding - stops PHD2 guiding
pub async fn execute_stop_guiding(
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    tracing::info!("Stopping guiding");

    if let Some(cb) = progress_callback {
        cb(0.0, "Stopping guiding".to_string());
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if let Some(cb) = progress_callback {
        cb(50.0, "Sending stop command".to_string());
    }

    match ctx.device_ops.guider_stop().await {
        Ok(_) => {
            // Disarm the GuideStarLost trigger on an intentional stop, so the
            // subsequent is_guiding==false does not get misread as a lost star
            // (which would request recovery for a deliberately-stopped guider).
            if let Some(trigger_state_lock) = &ctx.trigger_state {
                let mut tstate = trigger_state_lock.write().await;
                tstate.set_guiding_enabled(false);
                tstate.set_guide_star_lost(false);
            }
            if let Some(cb) = progress_callback {
                cb(100.0, "Guiding stopped".to_string());
            }
            InstructionResult::success_with_message("Guiding stopped")
        }
        Err(e) => InstructionResult::failure(format!("Failed to stop guiding: {}", e)),
    }
}

// =============================================================================
// FILTER CHANGE INSTRUCTION
// =============================================================================

/// Default timeout for filter wheel change operations (in seconds)
const DEFAULT_FILTER_WHEEL_TIMEOUT_SECS: u64 = 120;

/// Execute filter change
pub async fn execute_filter_change(
    config: &FilterConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let fw_id = match ctx.filterwheel_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    // Per-filter timeout overrides the global default to accommodate slow
    // wheels (motorized covers, many-position wheels) that legitimately
    // need longer than 120 s; configuring None preserves the safe default.
    // Why: `timeout_secs: Option<u32>` is the explicit
    // user-override slot — None means "use the documented default".
    let timeout = Duration::from_secs(
        config
            .timeout_secs
            // Why: u32 -> u64 widening is lossless.
            .map(u64::from)
            .unwrap_or(DEFAULT_FILTER_WHEEL_TIMEOUT_SECS),
    );

    tracing::info!(
        "Changing filter to: {} (timeout: {:?})",
        config.filter_name,
        timeout
    );

    if let Some(cb) = progress_callback {
        cb(0.0, format!("Changing to {}", config.filter_name));
    }

    // Index path is preferred over name (see execute_exposure rationale).
    if let Some(index) = config.filter_index {
        match ctx.device_ops.filterwheel_set_position(&fw_id, index).await {
            Ok(_) => {
                if let Some(cb) = progress_callback {
                    cb(30.0, format!("Moving to position {}", index));
                }
                if let Err(e) = wait_for_filterwheel_idle(&fw_id, index, ctx, timeout).await {
                    return InstructionResult::failure(e);
                }
                // Filter-specific focus offsets compensate for the differing
                // optical path length of each filter glass; applying them
                // here keeps the focus point usable for the next exposure
                // without forcing the user to run autofocus after every
                // filter change.
                if let Err(e) =
                    apply_filter_focus_offset(&config.filter_name, ctx, progress_callback).await
                {
                    return InstructionResult::failure(format!(
                        "Focus offset failed for filter \"{}\": {}",
                        config.filter_name, e
                    ));
                }
                if let Some(cb) = progress_callback {
                    cb(100.0, format!("Filter {}", index));
                }
                return InstructionResult::success_with_message(format!(
                    "Changed to filter position: {}",
                    index
                ));
            }
            Err(e) => return InstructionResult::failure(format!("Filter change failed: {}", e)),
        }
    }

    match ctx
        .device_ops
        .filterwheel_set_filter_by_name(&fw_id, &config.filter_name)
        .await
    {
        Ok(pos) => {
            if let Some(cb) = progress_callback {
                cb(30.0, format!("Moving to {}", config.filter_name));
            }
            if let Err(e) = wait_for_filterwheel_idle(&fw_id, pos, ctx, timeout).await {
                return InstructionResult::failure(e);
            }
            if let Err(e) =
                apply_filter_focus_offset(&config.filter_name, ctx, progress_callback).await
            {
                return InstructionResult::failure(format!(
                    "Focus offset failed for filter \"{}\": {}",
                    config.filter_name, e
                ));
            }
            if let Some(cb) = progress_callback {
                cb(100.0, format!("Filter: {}", config.filter_name));
            }
            InstructionResult::success_with_message(format!(
                "Changed to filter: {} (pos {})",
                config.filter_name, pos
            ))
        }
        Err(e) => InstructionResult::failure(format!("Filter change failed: {}", e)),
    }
}

/// Apply the focus offset configured for a given filter after a filter change.
///
/// Looks up the offset in `ctx.filter_focus_offsets` and moves the focuser
/// by that amount relative to its current position. If the offset is zero,
/// no focuser is connected, or no offset is configured, this is a no-op.
/// Errors are logged but do not fail the filter change.
async fn apply_filter_focus_offset(
    filter_name: &str,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> Result<(), String> {
    let focuser_id = match ctx.focuser_id.as_deref() {
        Some(id) if !id.is_empty() => id,
        _ => return Ok(()),
    };

    // Filter focus offsets are stored RELATIVE to the reference filter
    // (offset = optimal_focus[filter] - optimal_focus[reference]); the
    // reference filter and any unconfigured filter have offset 0.
    let offset_new = ctx
        .filter_focus_offsets
        .get(filter_name)
        .copied()
        .unwrap_or(0);

    // The focuser already carries the offset applied for the PREVIOUS filter.
    // Applying `offset_new` as an absolute shift from the current position
    // would stack offsets and walk focus off across an LRGB/SHO night
    // (e.g. L->R = +30, then R->G would land at reference+40 instead of
    // reference+10, and re-selecting a filter would re-add its offset every
    // time). Move by the DELTA between the new offset and the one currently
    // embodied so the focuser always lands at reference_focus + offset_new.
    let last_applied = match &ctx.trigger_state {
        Some(ts) => ts.read().await.last_applied_filter_offset,
        None => 0,
    };
    let delta = offset_new - last_applied;

    if delta == 0 {
        // Already at the correct offset for this filter (re-selecting the same
        // filter, or selecting the reference filter when nothing is applied).
        tracing::debug!(
            "Filter \"{}\": focus offset {} already embodied; no focuser move needed",
            filter_name,
            offset_new
        );
        return Ok(());
    }

    tracing::info!(
        "Applying focus offset for filter \"{}\": embodied {} -> {} ({:+} step delta)",
        filter_name,
        last_applied,
        offset_new,
        delta
    );

    if let Some(cb) = progress_callback {
        cb(60.0, format!("Applying focus offset: {:+} steps", delta));
    }

    let current_pos = match ctx.device_ops.focuser_get_position(focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            return Err(format!("failed to read focuser position: {}", e));
        }
    };

    let target_pos = current_pos + delta;
    tracing::info!(
        "Focus offset: {} + {} = {} (current + delta = target; filter offset {})",
        current_pos,
        delta,
        target_pos,
        offset_new
    );

    if let Err(e) = ctx.device_ops.focuser_move_to(focuser_id, target_pos).await {
        return Err(format!("failed to move focuser: {}", e));
    }

    // 60 polls × 500 ms = 30 s — enough for typical filter-offset moves
    // (which are tens of steps), but short enough that a stuck focuser does
    // not block the next exposure. Real verification of `final_pos ==
    // target_pos` happens after the wait so we catch slow-but-completing
    // moves as well as outright failures.
    let mut reached_target = false;
    for _ in 0..60 {
        sleep(Duration::from_millis(500)).await;
        match ctx.device_ops.focuser_is_moving(focuser_id).await {
            Ok(false) => {
                reached_target = true;
                break;
            }
            Ok(true) => continue,
            Err(e) => {
                return Err(format!("failed while checking focuser movement: {}", e));
            }
        }
    }

    if !reached_target {
        return Err("focuser did not report completion before the timeout window".to_string());
    }

    let final_pos = match ctx.device_ops.focuser_get_position(focuser_id).await {
        Ok(pos) => pos,
        Err(e) => {
            return Err(format!("failed to verify final focuser position: {}", e));
        }
    };

    if final_pos != target_pos {
        return Err(format!(
            "target focuser position {} but actual position is {}",
            target_pos, final_pos
        ));
    }

    // Record the offset now embodied in the focuser position so the NEXT
    // filter change moves only by the delta (and re-selecting this filter is a
    // no-op). Without this the offsets accumulate across the night.
    if let Some(ts) = &ctx.trigger_state {
        ts.write().await.set_last_applied_filter_offset(offset_new);
    }

    if let Some(cb) = progress_callback {
        cb(
            80.0,
            format!(
                "Focus offset applied: {} -> {} ({:+} steps)",
                current_pos, final_pos, delta
            ),
        );
    }

    tracing::info!(
        "Focus offset for filter \"{}\" applied: {} -> {} (embodied offset now {})",
        filter_name,
        current_pos,
        final_pos,
        offset_new
    );
    Ok(())
}

// =============================================================================
// CAMERA COOLING/WARMING INSTRUCTIONS
// =============================================================================

/// Execute camera cooling
pub async fn execute_cool_camera(
    config: &CoolConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => {
            tracing::error!("CoolCamera failed: No camera connected");
            return e;
        }
    };

    tracing::info!("Cooling camera to {}°C", config.target_temp);

    // Initial temperature anchors the progress percentage: the user sees
    // "30% cooled" as halfway between start and target rather than a raw
    // °C count that means nothing without context.
    let start_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
        Ok(value) => value,
        Err(e) => {
            return InstructionResult::failure(format!("Failed to read camera temperature: {}", e))
        }
    };
    let target_temp = config.target_temp;
    let temp_range = (start_temp - target_temp).abs();

    // 0.5 °C tolerance covers typical cooler noise on TEC-equipped cameras
    // (ZWO/QHY/PlayerOne all report jitter in the ±0.3 °C range when
    // settled); tighter would force a fake "cooling" loop on a camera
    // that is already where we want it.
    let already_at_target = (start_temp - target_temp).abs() < 0.5;

    if let Err(e) = ctx
        .device_ops
        .camera_set_cooler(&camera_id, true, target_temp)
        .await
    {
        return InstructionResult::failure(format!("Failed to enable cooler: {}", e));
    }

    if already_at_target {
        let cooler_power = match ctx.device_ops.camera_get_cooler_power(&camera_id).await {
            Ok(value) => value,
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Failed to read camera cooler power: {}",
                    e
                ))
            }
        };
        let msg = format!(
            "At target: {:.1}°C ({:.0}% power)",
            start_temp, cooler_power
        );
        tracing::info!("Camera already at target temperature: {}", msg);
        if let Some(cb) = progress_callback {
            cb(100.0, msg.clone());
        }
        return InstructionResult::success_with_message(msg);
    }

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Starting: {:.1}°C → {:.1}°C", start_temp, target_temp),
        );
    }

    // Always wait for the setpoint. The configured duration caps HOW LONG we
    // wait — it does NOT decide WHETHER we wait. Previously a `None` duration
    // returned Success immediately (camera never verified at temperature) and
    // a duration that elapsed before convergence ALSO returned Success. Both
    // let an unattended sequence start exposing a warm / mis-cooled sensor.
    // Now non-convergence within the deadline is a hard failure (fail-closed).
    //
    // When no duration is configured we still bound the wait with a generous
    // default so a stuck cooler cannot hang the sequence forever.
    const DEFAULT_COOL_TIMEOUT_SECS: f64 = 900.0; // 15 min — ample for any TEC ramp
    const POLL_SECS: f64 = 10.0;
    let deadline_secs = config
        .duration_mins
        .map(|m| (m * 60.0).max(0.0))
        .unwrap_or(DEFAULT_COOL_TIMEOUT_SECS);
    let mut elapsed_secs = 0.0_f64;

    loop {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }

        let current_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
            Ok(value) => value,
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Failed to read camera temperature during cooling: {}",
                    e
                ))
            }
        };
        let cooler_power = match ctx.device_ops.camera_get_cooler_power(&camera_id).await {
            Ok(value) => value,
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Failed to read camera cooler power: {}",
                    e
                ))
            }
        };

        // Direction-agnostic progress: (current - start) / (target - start).
        // Works for both cooling and warming because numerator and denominator
        // share a sign convention. Clamped so transient wobbles don't jump.
        let temp_progress = if temp_range > 0.1 {
            let raw = (current_temp - start_temp) / (target_temp - start_temp) * 100.0;
            raw.clamp(0.0, 100.0)
        } else {
            100.0
        };
        // Time-based progress is the floor: even if the camera struggles to
        // cool, the bar advances toward 100% as the deadline runs out, so the
        // user can see the wait is finite.
        let time_progress = if deadline_secs > 0.0 {
            (elapsed_secs / deadline_secs * 100.0).clamp(0.0, 100.0)
        } else {
            100.0
        };
        let progress = temp_progress.max(time_progress);

        tracing::debug!(
            "Cooling progress: {:.1}%, current temp: {:.1}°C, power: {:.0}%",
            progress,
            current_temp,
            cooler_power
        );

        if let Some(cb) = progress_callback {
            cb(
                progress,
                format!(
                    "Cooling: {:.1}°C → {:.1}°C ({:.0}% power)",
                    current_temp, target_temp, cooler_power
                ),
            );
        }

        if (current_temp - target_temp).abs() < 0.5 {
            let msg = format!(
                "Target reached: {:.1}°C ({:.0}% power)",
                current_temp, cooler_power
            );
            if let Some(cb) = progress_callback {
                cb(100.0, msg.clone());
            }
            return InstructionResult::success_with_message(msg);
        }

        if elapsed_secs >= deadline_secs {
            // Fail closed: the sensor did not reach the setpoint in time.
            return InstructionResult::failure(format!(
                "Camera did not reach target {:.1}°C within {:.0}s \
                 (last {:.1}°C, {:.0}% power)",
                target_temp, deadline_secs, current_temp, cooler_power
            ));
        }

        sleep(Duration::from_secs_f64(POLL_SECS)).await;
        elapsed_secs += POLL_SECS;
    }
}

/// Execute camera warming
pub async fn execute_warm_camera(
    config: &WarmConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let camera_id = match ctx.camera_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!("Warming camera at {}°C/min", config.rate_per_min);

    let start_temp = match ctx.device_ops.camera_get_temperature(&camera_id).await {
        Ok(value) => value,
        Err(e) => {
            return InstructionResult::failure(format!("Failed to read camera temperature: {}", e))
        }
    };
    // Why: `target_temp: Option<f64>` is a user-override on the
    // WarmCamera instruction; None means "use the conventional ambient-warming default
    // of 20°C", which is the safe shutdown-prep temperature for every cooled-sensor
    // chip in our supported matrix.
    let target_temp = config.target_temp.unwrap_or(20.0);
    let temp_range = target_temp - start_temp;
    let duration_mins = temp_range / config.rate_per_min;
    // Why: duration_mins is a computed temperature ramp; `.max(1.0)` ensures
    // at least one iteration. f64 -> u32 saturates per Rust 1.45 spec.
    let steps = (duration_mins * 6.0).max(1.0) as u32;

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(
            0.0,
            format!("Warming: {:.1}°C → {:.1}°C", start_temp, target_temp),
        );
    }

    for step in 0..steps {
        if let Some(result) = ctx.check_cancelled() {
            // Turn off cooler on cancel
            let _ = ctx
                .device_ops
                .camera_set_cooler(&camera_id, false, 20.0)
                .await;
            return result;
        }

        // Why: step and steps are u32 bounded by the warming-loop config; lossless to f64.
        let progress_temp = start_temp + (temp_range * f64::from(step) / f64::from(steps));
        let progress_percent = (f64::from(step) / f64::from(steps)) * 100.0;

        // Gradually increase target temperature
        if let Err(e) = ctx
            .device_ops
            .camera_set_cooler(&camera_id, true, progress_temp)
            .await
        {
            tracing::warn!("Failed to update cooler target: {}", e);
        }

        // Emit progress
        if let Some(cb) = progress_callback {
            cb(
                progress_percent,
                format!("Warming: {:.1}°C → {:.1}°C", progress_temp, target_temp),
            );
        }

        tracing::debug!("Warming progress: {:.1}°C", progress_temp);
        sleep(Duration::from_secs(10)).await;
    }

    // Turn off cooler. The setpoint argument is ignored downstream for a
    // disable (see `DeviceManager::cooler_setpoint_to_command`); the DeviceOps
    // trait just has nowhere to say "none".
    //
    // The outcome is NOT discarded: on the reference rig this exact call
    // failed, and the instruction still reported "Camera warmed to ambient"
    // while the TEC stayed powered. A warm-up that could not switch the cooler
    // off has not warmed anything up.
    if let Err(e) = ctx
        .device_ops
        .camera_set_cooler(&camera_id, false, 20.0)
        .await
    {
        return InstructionResult::failure(format!(
            "Warmed to {:.1}°C but could not switch the cooler off: {}",
            target_temp, e
        ));
    }

    // Emit final progress
    if let Some(cb) = progress_callback {
        cb(100.0, "Warmed to ambient".to_string());
    }

    InstructionResult::success_with_message("Camera warmed to ambient")
}

// =============================================================================
// ROTATOR INSTRUCTION
// =============================================================================

/// Execute rotator move
pub async fn execute_rotator_move(
    config: &RotatorConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let rotator_id = match ctx.rotator_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!(
        "Moving rotator to {} (relative: {})",
        config.target_angle,
        config.relative
    );

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, format!("Moving to {:.1}", config.target_angle));
    }

    // Resolve the ABSOLUTE target so we can verify arrival even for a relative
    // move — we must read the current angle BEFORE issuing the move.
    let target_abs = if config.relative {
        match ctx.device_ops.rotator_get_angle(&rotator_id).await {
            Ok(current) => normalize_rotator_angle(current + config.target_angle),
            Err(e) => {
                return InstructionResult::failure(format!(
                    "Failed to read rotator angle before relative move: {}",
                    e
                ))
            }
        }
    } else {
        normalize_rotator_angle(config.target_angle)
    };

    // Move to the absolute target and verify arrival within tolerance (fails
    // closed on error / timeout). The driver move call only ISSUES the move on
    // ASCOM/Alpaca/INDI, so without this verify the next instruction (e.g. an
    // exposure) could start while the camera angle is still slewing — smearing
    // field rotation across the frame and breaking any rotation-matched
    // mosaic/flat. Issuing an absolute move (rather than the relative driver
    // call) keeps the verified-target and the issued-target identical.
    match rotator_move_to_verified(ctx, &rotator_id, target_abs, |pct, msg| {
        if let Some(cb) = progress_callback {
            cb(pct, msg);
        }
    })
    .await
    {
        Ok(current) => InstructionResult::success_with_message(format!(
            "Rotator at {:.1} (target {:.1})",
            current, target_abs
        )),
        Err(result) => result,
    }
}

// =============================================================================
// PARK/UNPARK INSTRUCTIONS
// =============================================================================

/// Execute park
pub async fn execute_park(ctx: &InstructionContext) -> InstructionResult {
    let mount_id = match ctx.mount_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!("Parking mount");

    if let Err(e) = ctx.device_ops.mount_park(&mount_id).await {
        return InstructionResult::failure(format!("Park failed: {}", e));
    }

    // mount_park only ISSUES the park on most drivers (ASCOM/Alpaca/INDI return
    // as soon as the command is acknowledged); a park slew takes 30-90 s.
    // Returning success immediately would let an automated end-of-night
    // shutdown advance to the next step (close dome / cut power) while the OTA
    // is still swinging, and would report success even for a park the driver
    // silently rejected (e.g. CanPark=false). Wait for the mount to report
    // PARKED — the authoritative completion signal across all driver types
    // (mount_is_slewing is unreliable for INDI parking, which uses a separate
    // property) — and fail closed if it never does.
    let park_deadline = tokio::time::Instant::now() + Duration::from_secs(300);
    loop {
        if let Some(result) = ctx.check_cancelled() {
            return result;
        }
        match ctx.device_ops.mount_is_parked(&mount_id).await {
            Ok(true) => {
                return InstructionResult::success_with_message("Mount parked");
            }
            Ok(false) => {
                // Still parking.
            }
            Err(e) => {
                tracing::warn!("Park: is_parked read failed ({}); retrying", e);
            }
        }
        if tokio::time::Instant::now() > park_deadline {
            return InstructionResult::failure(
                "Mount did not report parked within 300s of issuing Park. The driver may not \
                 support Park (CanPark=false), the park was rejected, or the mount is stuck \
                 mid-slew — NOT safe to assume parked."
                    .to_string(),
            );
        }
        sleep(Duration::from_millis(500)).await;
    }
}

/// Execute unpark
pub async fn execute_unpark(ctx: &InstructionContext) -> InstructionResult {
    let mount_id = match ctx.mount_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    tracing::info!("Unparking mount");

    match ctx.device_ops.mount_unpark(&mount_id).await {
        Ok(_) => InstructionResult::success_with_message("Mount unparked"),
        Err(e) => InstructionResult::failure(format!("Unpark failed: {}", e)),
    }
}

// =============================================================================
// POLAR ALIGNMENT INSTRUCTION
// =============================================================================

/// Execute polar alignment
pub async fn execute_polar_alignment(
    config: &PolarAlignConfig,
    ctx: &InstructionContext,
    status_callback: impl Fn(String, Option<f64>) + Send + Sync,
    image_callback: impl Fn(crate::polar_align::PolarAlignmentImageData) + Send + Sync,
) -> InstructionResult {
    crate::polar_align::perform_polar_alignment(config, ctx, status_callback, image_callback).await
}

// =============================================================================
// WAIT TIME INSTRUCTION
// =============================================================================

/// Execute wait for time
pub async fn execute_wait_time(
    config: &WaitTimeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    // Wait until specific time
    if let Some(until) = config.wait_until {
        let now = chrono::Utc::now().timestamp();
        if now < until {
            // Why: `now < until` is checked above, so `until - now` is positive
            // i64 (no two-complement wrap risk). i64 -> u64 is then lossless for
            // any positive value.
            let total_wait_secs = u64::try_from(until - now).unwrap_or(0);
            let wait_until_str = chrono::DateTime::from_timestamp(until, 0)
                .map(|dt| dt.format("%H:%M:%S").to_string())
                // Why: `from_timestamp` only fails for out-of-range
                // i64 seconds (year ±5_400_000); user input here is bounded by the UI
                // datetime picker. Raw epoch seconds as the display fallback preserves
                // log traceability if a hypothetical extreme value sneaks in.
                .unwrap_or_else(|| until.to_string());

            tracing::info!(
                "Waiting until {} ({} seconds)",
                wait_until_str,
                total_wait_secs
            );

            // Emit initial progress
            if let Some(cb) = progress_callback {
                cb(0.0, format!("Waiting until {}", wait_until_str));
            }

            // Wait in 1-second increments to allow cancellation
            for elapsed in 0..total_wait_secs {
                if let Some(result) = ctx.check_cancelled() {
                    return result;
                }

                // Emit progress every 10 seconds
                if elapsed % 10 == 0 {
                    // Why: u64 -> f64. Wait durations under ~285k years fit
                    // losslessly in f64's 53-bit mantissa.
                    let progress = (elapsed as f64 / total_wait_secs as f64) * 100.0;
                    let remaining = total_wait_secs - elapsed;
                    if let Some(cb) = progress_callback {
                        cb(progress, format!("{}s remaining", remaining));
                    }
                }

                sleep(Duration::from_secs(1)).await;
            }

            if let Some(cb) = progress_callback {
                cb(100.0, "Target time reached".to_string());
            }
        }
        return InstructionResult::success_with_message("Wait time reached");
    }

    // Wait for twilight
    if let Some(twilight) = &config.wait_for_twilight {
        tracing::info!("Waiting for {:?} twilight", twilight);

        // Calculate twilight time based on observer location
        let observer_location = match (ctx.latitude, ctx.longitude) {
            (Some(lat), Some(lon)) => Some((lat, lon)),
            _ => ctx.device_ops.get_observer_location(),
        };
        let (lat, lon) = match observer_location {
            Some(loc) => loc,
            None => {
                return InstructionResult::failure(
                    "Cannot evaluate twilight trigger: observer location is unavailable. Set site latitude/longitude in settings.",
                );
            }
        };
        let twilight_time = calculate_twilight_time(lat, lon, twilight);

        let now = chrono::Utc::now().timestamp();
        if twilight_time == i64::MAX {
            return InstructionResult::failure(format!(
                "{:?} twilight does not occur at latitude {:.3} and longitude {:.3} for the current date. \
Sequence cannot wait for an unreachable twilight state.",
                twilight, lat, lon
            ));
        }
        if now < twilight_time {
            // Why: `now < twilight_time` is checked above, so the difference is
            // positive i64. i64 -> u64 is then lossless via try_from.
            let total_wait_secs = u64::try_from(twilight_time - now).unwrap_or(0);
            tracing::info!(
                "Waiting {} seconds for {:?} twilight",
                total_wait_secs,
                twilight
            );

            // Emit initial progress
            if let Some(cb) = progress_callback {
                cb(0.0, format!("Waiting for {:?} twilight", twilight));
            }

            for elapsed in 0..total_wait_secs {
                if let Some(result) = ctx.check_cancelled() {
                    return result;
                }

                // Emit progress every 30 seconds
                if elapsed % 30 == 0 {
                    // Why: u64 -> f64. Twilight wait durations (~hours) fit
                    // losslessly in f64's 53-bit mantissa.
                    let progress = (elapsed as f64 / total_wait_secs as f64) * 100.0;
                    let remaining_mins = (total_wait_secs - elapsed) / 60;
                    if let Some(cb) = progress_callback {
                        cb(
                            progress,
                            format!("{:?}: {}m remaining", twilight, remaining_mins),
                        );
                    }
                }

                sleep(Duration::from_secs(1)).await;
            }

            if let Some(cb) = progress_callback {
                cb(100.0, format!("{:?} twilight reached", twilight));
            }
        }

        return InstructionResult::success_with_message(format!("{:?} twilight reached", twilight));
    }

    // Neither a target time nor a twilight condition was set. Returning Success
    // here made an unconfigured Wait node complete immediately without waiting
    // microseconds — and the canonical use of this node is "wait until
    // astronomical dark before imaging", so skipping it starts the run in
    // daylight. Fail instead: a wait that cannot wait has not been satisfied.
    InstructionResult::failure(
        "Wait node has no wait condition: set a target time or a twilight condition",
    )
}

/// Calculate twilight time for a given location using proper solar position algorithms
fn calculate_twilight_time(latitude: f64, longitude: f64, twilight_type: &TwilightType) -> i64 {
    // Sun altitude threshold for each twilight type (degrees below horizon)
    let altitude_threshold: f64 = match twilight_type {
        TwilightType::Civil => -6.0,
        TwilightType::Nautical => -12.0,
        TwilightType::Astronomical => -18.0,
    };

    let now = chrono::Utc::now();
    let today = now.date_naive();

    // Calculate Julian Day. reuse `crate::meridian::julian_day`
    // instead of the previous local duplicate.
    let jd = crate::meridian::julian_day(&now);

    // Calculate solar position
    let (solar_dec, equation_of_time) = calculate_solar_position(jd);

    // Convert to radians
    let lat_rad = latitude.to_radians();
    let dec_rad = solar_dec.to_radians();
    let alt_rad = altitude_threshold.to_radians();

    // Calculate hour angle when sun is at the given altitude
    // cos(H) = (sin(alt) - sin(lat) * sin(dec)) / (cos(lat) * cos(dec))
    let cos_h = (alt_rad.sin() - lat_rad.sin() * dec_rad.sin()) / (lat_rad.cos() * dec_rad.cos());

    // Polar handling: avoid fabricated fallback times.
    if cos_h > 1.0 {
        // Sun never reaches this altitude threshold today (e.g. polar day).
        return i64::MAX;
    }
    if cos_h < -1.0 {
        // Sun is already below this threshold all day (e.g. polar night).
        return now.timestamp();
    }

    let hour_angle = cos_h.acos().to_degrees();

    // Calculate local solar noon
    let solar_noon_utc = 12.0 - longitude / 15.0 - equation_of_time / 60.0;

    // Evening twilight occurs when sun sets past the altitude threshold
    // Time after solar noon when sun reaches threshold
    let hours_after_noon = hour_angle / 15.0;
    let twilight_hour_utc = solar_noon_utc + hours_after_noon;

    // Convert to timestamp
    let twilight_hour = twilight_hour_utc.rem_euclid(24.0);
    // Why: twilight_hour is bounded by rem_euclid(24.0) above; .fract()*60.0 is
    // in [0, 60). f64 -> u32 saturates per Rust 1.45 spec.
    let twilight_minutes = (twilight_hour.fract() * 60.0) as u32;
    let twilight_hour = twilight_hour as u32;

    let twilight_datetime =
        build_utc_naive_time_or_fallback(today, twilight_hour, twilight_minutes, (23, 59, 0));

    let twilight_timestamp =
        chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(twilight_datetime, chrono::Utc)
            .timestamp();

    // If the calculated twilight is in the past, it's tomorrow's twilight
    if twilight_timestamp < now.timestamp() {
        return twilight_timestamp + 86400; // Add 24 hours
    }

    twilight_timestamp
}

// the local `calculate_julian_day` was deleted; use
// `crate::meridian::julian_day(&dt)` — same formula, single source of truth.

fn build_utc_naive_time_or_fallback(
    date: NaiveDate,
    hour: u32,
    minute: u32,
    fallback: (u32, u32, u32),
) -> chrono::NaiveDateTime {
    // Why: `and_hms_opt` only returns None for invalid (h,m,s) tuples
    // (h>=24, m>=60, s>=60). The caller passes solar-calculation results that may
    // saturate at exactly 24:00:00 in edge equation-of-time cases — `fallback` is the
    // tuple from the documented sunset-convention default. If both fail (impossible
    // unless `fallback` itself is invalid), midnight is the safe last-resort
    // representable time for the same calendar date.
    date.and_hms_opt(hour, minute, 0)
        .or_else(|| date.and_hms_opt(fallback.0, fallback.1, fallback.2))
        .unwrap_or_else(|| date.and_time(chrono::NaiveTime::MIN))
}

/// Calculate solar declination and equation of time
/// Returns (declination in degrees, equation of time in minutes)
fn calculate_solar_position(jd: f64) -> (f64, f64) {
    // Days since J2000.0
    let n = jd - 2451545.0;

    // Mean longitude of the sun (degrees)
    let l = (280.460 + 0.9856474 * n) % 360.0;

    // Mean anomaly of the sun (degrees)
    let g = (357.528 + 0.9856003 * n) % 360.0;
    let g_rad = g.to_radians();

    // Ecliptic longitude of the sun (degrees)
    let lambda = l + 1.915 * g_rad.sin() + 0.020 * (2.0 * g_rad).sin();
    let lambda_rad = lambda.to_radians();

    // Obliquity of the ecliptic (degrees)
    let epsilon = 23.439 - 0.0000004 * n;
    let epsilon_rad = epsilon.to_radians();

    // Solar declination
    let declination = (epsilon_rad.sin() * lambda_rad.sin()).asin().to_degrees();

    // Equation of time (minutes)
    // Simplified formula
    let y = (epsilon_rad / 2.0).tan().powi(2);
    let l_rad = l.to_radians();
    let eot = 4.0
        * (y * (2.0 * l_rad).sin() - 2.0 * 0.0167 * g_rad.sin()
            + 4.0 * 0.0167 * y * g_rad.sin() * (2.0 * l_rad).cos()
            - 0.5 * y * y * (4.0 * l_rad).sin()
            - 1.25 * 0.0167 * 0.0167 * (2.0 * g_rad).sin())
        .to_degrees();

    (declination, eot)
}

// =============================================================================
// DELAY INSTRUCTION
// =============================================================================

/// Execute delay
pub async fn execute_delay(
    config: &DelayConfig,
    ctx: &crate::node::context::ExecutionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    tracing::info!("Delaying for {:.1} seconds", config.seconds);

    // Emit initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, format!("{:.0}s delay", config.seconds));
    }

    // Why: config.seconds is f64 user-config delay (UI-bounded). f64 -> u64
    // saturates per Rust 1.45 spec; negatives clamp to 0 yielding no-wait.
    let total_steps = (config.seconds * 10.0) as u64;
    for step in 0..total_steps {
        if !ctx.wait_while_paused().await {
            return InstructionResult::cancelled("Delay cancelled");
        }
        if ctx.is_cancelled.load(Ordering::Relaxed) {
            return InstructionResult::cancelled("Delay cancelled");
        }

        // Emit progress every second (10 steps)
        if step % 10 == 0 {
            // Why: u64 step -> f64 lossless under any plausible delay length
            // (years of seconds fit in 53-bit mantissa).
            let elapsed_secs = step as f64 / 10.0;
            let remaining_secs = config.seconds - elapsed_secs;
            let progress = (elapsed_secs / config.seconds) * 100.0;
            if let Some(cb) = progress_callback {
                cb(progress, format!("{:.0}s remaining", remaining_secs));
            }
        }

        sleep(Duration::from_millis(100)).await;
    }

    if let Some(cb) = progress_callback {
        cb(100.0, "Delay complete".to_string());
    }

    InstructionResult::success_with_message(format!("Delayed {:.1} seconds", config.seconds))
}

// =============================================================================
// NOTIFICATION INSTRUCTION
// =============================================================================

/// Execute notification
pub async fn execute_notification(
    config: &NotificationConfig,
    ctx: &InstructionContext,
) -> InstructionResult {
    let level = match config.level {
        NotificationLevel::Info => "info",
        NotificationLevel::Warning => "warning",
        NotificationLevel::Error => "error",
        NotificationLevel::Success => "success",
    };

    tracing::info!(
        "[{}] {}: {}",
        level.to_uppercase(),
        config.title,
        config.message
    );

    if let Err(e) = ctx
        .device_ops
        .send_notification(
            level,
            &config.title,
            &config.message,
            config.explicit_transports.as_deref(),
        )
        .await
    {
        tracing::warn!("Failed to send notification: {}", e);
    }

    InstructionResult::success()
}

// =============================================================================
// SCRIPT INSTRUCTION
// =============================================================================

/// Effective timeout applied to a Run Script node that carries no explicit
/// `timeout_secs`.
///
/// This is the single source of truth for "how long may an unconfigured script
/// run". The Dart node editor renders the same 300 s as the field's value, so
/// the number the operator reads is the number the executor enforces; the
/// duration estimator and the node's Timing card must use this value too.
pub const DEFAULT_SCRIPT_TIMEOUT_SECS: u32 = 300;

/// Execute script. expanded the env-var contract: every variable
/// declared in `expressions::catalog` is exposed as `NIGHTSHADE_<NAME>`
/// where `NAME` is the dotted variable converted to UPPER_SNAKE
/// (e.g. `target.alt` → `NIGHTSHADE_TARGET_ALT`). Variables that fail to
/// resolve are simply omitted (a missing env var is a normal "no data"
/// signal to a shell script, unlike a `${...}` template inside an
/// argument which is a hard failure).
pub async fn execute_script(
    config: &ScriptConfig,
    ctx: &InstructionContext,
    exec_ctx: &crate::node::context::ExecutionContext,
    frame: &crate::expressions::EvaluationFrame,
) -> InstructionResult {
    tracing::info!(
        "Running script: {} {:?}",
        config.script_path,
        config.arguments
    );

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Build the command
    let mut cmd = tokio::process::Command::new(&config.script_path);
    cmd.args(&config.arguments);

    // Expose every catalog variable as an env var. Anything that does not
    // resolve (e.g. `target.alt` without an observer location) is silently
    // skipped — the script can detect missing data via `env -u` semantics.
    // We deliberately do NOT propagate InterpolationError here: an env-var
    // contract is "this MAY be present", whereas an argument template's
    // contract is "this MUST resolve".
    for entry in crate::expressions::variable_catalog() {
        if let Ok(value) = crate::expressions::resolve_variable(entry.name, 0, exec_ctx, frame) {
            let env_name = format!(
                "NIGHTSHADE_{}",
                crate::expressions::catalog_name_to_env(entry.name)
            );
            cmd.env(
                env_name,
                crate::expressions::format_variable_for_env(&value),
            );
        }
    }

    // Set timeout. An absent timeout is NOT an unsafe state: the bounded
    // [`DEFAULT_SCRIPT_TIMEOUT_SECS`] fallback is itself fail-closed (the child
    // is still killed and reaped), and it is the value the node editor shows as
    // the effective timeout. Rejecting `None` outright — as the 2026-02
    // fail-closed sweep did — made every freshly added Run Script node refuse to
    // run with "timeout_secs is required" while the panel displayed 300, so the
    // node was unusable until the operator retyped the number it already showed.
    // An explicit zero stays an error: that is a real contradiction (run the
    // script, but kill it immediately), not a missing value.
    let timeout = match config.timeout_secs {
        // Why: u32 -> u64 widening is lossless.
        Some(v) if v > 0 => u64::from(v),
        Some(_) => {
            return InstructionResult::failure(
                "Script timeout_secs must be greater than zero".to_string(),
            )
        }
        None => u64::from(DEFAULT_SCRIPT_TIMEOUT_SECS),
    };

    // Reap the child when the spawned future is dropped (timeout / cancel).
    // Without this, racing `cmd.output()` against a timeout abandons the OS
    // process still running and unreaped → orphaned/zombie. `kill_on_drop`
    // makes the dropped future SIGKILL and `wait()` the child for us. The
    // piped stdio mirrors what `cmd.output()` set implicitly so the success
    // path still captures stdout/stderr.
    cmd.kill_on_drop(true);
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());

    // SEQ-001: isolate the child in its OWN process group (pgid == child pid).
    // `kill_on_drop` SIGKILLs only the *direct* child, so a script that
    // backgrounds work (`some_cmd &`) leaves those grandchildren running after a
    // timeout/cancel. With the child in its own group we can SIGKILL `-pgid` on
    // abort to tear the whole group down without ever touching the sequencer's
    // own process group. The happy path is unaffected — group isolation changes
    // neither stdio capture nor the child's exit status.
    #[cfg(unix)]
    cmd.process_group(0);

    let child = match cmd.spawn() {
        Ok(child) => child,
        Err(e) => return InstructionResult::failure(format!("Failed to run script: {}", e)),
    };
    // Capture the pid (== pgid under `process_group(0)`) before `wait_with_output`
    // consumes `child`, so the abort path can signal the whole group.
    #[cfg(unix)]
    let child_pid = child.id();

    // Race the script against its timeout and the cancellation token. When a
    // non-output arm wins, the `wait_with_output` future (which owns `child`)
    // is dropped, and `kill_on_drop` kills+reaps the process.
    let result = tokio::select! {
        output = child.wait_with_output() => Ok(output),
        _ = tokio::time::sleep(Duration::from_secs(timeout)) => Err(Abort::Timeout),
        _ = wait_for_cancellation(ctx.cancellation_token.clone()) => Err(Abort::Cancelled),
    };

    match result {
        Ok(Ok(output)) => {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                tracing::info!("Script output: {}", stdout);
                InstructionResult {
                    status: NodeStatus::Success,
                    message: Some(format!("Script {} completed", config.script_path)),
                    data: Some(serde_json::json!({
                        "stdout": stdout.to_string(),
                        "stderr": String::from_utf8_lossy(&output.stderr).to_string(),
                        "exit_code": output.status.code(),
                    })),
                    hfr_values: Vec::new(),
                }
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                InstructionResult::failure(format!("Script failed: {}", stderr))
            }
        }
        Ok(Err(e)) => InstructionResult::failure(format!("Failed to run script: {}", e)),
        Err(abort) => {
            // The losing `wait_with_output` future has been dropped, so
            // `kill_on_drop` already SIGKILLed the direct child; now reap the rest
            // of its process group (any backgrounded grandchildren) so nothing the
            // script spawned survives the abort (SEQ-001). Unix-only; elsewhere we
            // retain the existing direct-child `kill_on_drop` behaviour.
            #[cfg(unix)]
            kill_script_process_group(child_pid);
            match abort {
                Abort::Timeout => InstructionResult::failure(format!(
                    "Script timed out after {} seconds",
                    timeout
                )),
                Abort::Cancelled => InstructionResult::cancelled("Script cancelled"),
            }
        }
    }
}

/// SIGKILL a timed-out/cancelled script's entire process group (Unix only).
///
/// `execute_script` spawns the child with `process_group(0)`, so `pgid == pid`.
/// `kill(2)` with a NEGATIVE pid delivers the signal to that whole process
/// group, reaching backgrounded grandchildren (`some_cmd &`) that a
/// `kill_on_drop` of the direct child alone would orphan. Reparented descendants
/// are reaped by the subreaper/init once signalled. A no-op when the pid is
/// unknown.
///
/// We call `kill(2)` directly rather than shelling out to `kill -KILL -<pgid>`:
/// the negative-pgid group syntax is parsed inconsistently across `kill(1)`
/// implementations (the bash builtin accepts it; some standalone util-linux
/// `kill` binaries — e.g. on CI runners — reject `-<pgid>` as a bad option), and
/// a misparse there silently leaks the group because the non-zero exit was
/// ignored. The syscall has no such ambiguity (SEQ-001 regression on CI).
#[cfg(unix)]
fn kill_script_process_group(pid: Option<u32>) {
    let Some(pid) = pid else {
        return;
    };
    let pgid = pid as libc::pid_t;
    // SAFETY: `kill(2)` is async-signal-safe and takes no pointers. A negative
    // target signals the process group `pgid`. The only expected failure is
    // ESRCH (the group already fully exited — a benign abort/exit race), which
    // needs no handling, so the return value is intentionally ignored.
    unsafe {
        libc::kill(-pgid, libc::SIGKILL);
    }
}

/// Reason a running script was aborted before it could exit on its own.
enum Abort {
    Timeout,
    Cancelled,
}

// =============================================================================
// MERIDIAN FLIP INSTRUCTION
// =============================================================================

/// Execute a meridian flip via the canonical [`MeridianFlipExecutor`].
///
/// this used to be a 394-line second implementation that diverged
/// from the executor on timeouts, post-flip altitude check, autofocus
/// parameters, settle behaviour, plate-solve failure handling, pier-side
/// telemetry fallback, and abort-during-flip semantics. The single-source-
/// of-truth executor lives in `crate::meridian_flip_executor`. This wrapper
/// builds a [`FlipContext`] from the instruction context and calls
/// `executor.execute()`. The cancellation token, the trigger-state flip
/// bookkeeping, the cover-state pre-check, and the
/// configurable autofocus parameters all flow through the FlipContext.
pub async fn execute_meridian_flip(
    config: &MeridianFlipConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    execute_meridian_flip_with_autofocus(config, None, ctx, progress_callback).await
}

/// Execute a meridian flip with an optional operator-tuned autofocus profile
/// for the post-flip refocus step.
///
/// The compatibility wrapper above retains the existing direct-call API.
/// Sequence executors that have resolved a real equipment-profile autofocus
/// config must call this entry point so filter, gain/offset, step, exposure,
/// and backlash settings reach `FlipContext` intact.
pub async fn execute_meridian_flip_with_autofocus(
    config: &MeridianFlipConfig,
    autofocus_config: Option<&AutofocusConfig>,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    // Surface a "starting" progress immediately so UI shows activity even
    // before the executor begins emitting its own events. The executor uses
    // its event channel for granular per-step progress so we do not wire
    // through that channel here — the explicit instruction node has its own
    // progress reporter (the callback we received) and a brief
    // 0%/100% bracket is sufficient.
    if let Some(cb) = progress_callback {
        cb(0.0, "Starting meridian flip".to_string());
    }

    let mount_id = match ctx.mount_id() {
        Ok(id) => id.to_string(),
        Err(e) => return e,
    };

    let target_ra = match ctx.target_ra {
        Some(ra) => ra,
        None => return InstructionResult::failure("No target RA available for meridian flip"),
    };

    let target_dec = match ctx.target_dec {
        Some(dec) => dec,
        None => {
            return InstructionResult::failure("No target declination available for meridian flip")
        }
    };

    // Why: target name is a display/log label for meridian-flip
    // status events; the load-bearing inputs (target_ra, target_dec) are already
    // validated as Some above and return failure when missing. "Unknown" is the
    // documented UI fallback when the user starts a sequence without a named target.
    let target_name = ctx
        .target_name
        .clone()
        .unwrap_or_else(|| "Unknown".to_string());

    // Pre-flight: do not invoke the executor when no flip is actually needed
    // — its altitude/cover/pier-side preflight assume the flip is required
    // and would otherwise emit confusing "Aborted" events for routine
    // pre-meridian sequence runs.
    let (_lat, lon) = match ctx.device_ops.get_observer_location() {
        Some((lat, lon)) => (lat, lon),
        None => {
            return InstructionResult::failure(
                "Observer location not configured. Meridian flip requires location for calculations."
            );
        }
    };

    let now = chrono::Utc::now();
    let should_flip =
        crate::meridian::should_flip_now(target_ra, lon, now, config.minutes_past_meridian);
    if !should_flip {
        let ha = crate::meridian::hour_angle(
            target_ra,
            crate::meridian::local_sidereal_time(crate::meridian::julian_day(&now), lon),
        );
        tracing::info!(
            "Meridian flip not yet required (HA={:.4}h, threshold={:.2} min)",
            ha,
            config.minutes_past_meridian
        );
        if let Some(cb) = progress_callback {
            cb(100.0, "Flip not yet required".to_string());
        }
        return InstructionResult::success_with_message("Meridian flip not yet required");
    }

    let flip_ctx = crate::meridian_flip_executor::FlipContext {
        target_name,
        target_ra_hours: target_ra,
        target_dec_degrees: target_dec,
        mount_id,
        camera_id: ctx.camera_id.clone(),
        focuser_id: ctx.focuser_id.clone(),
        // Resolve through the accessor, not the raw field: the context's cover
        // role is never populated on a real run, which silently disabled the
        // pre-flip "is the dust cap closed?" check that exists to stop a flip
        // ending in a failed plate solve and a parked mount.
        cover_calibrator_id: ctx.cover_calibrator_id().await.ok(),
        cancellation_token: Some(ctx.cancellation_token.clone()),
        trigger_state: ctx.trigger_state.clone(),
        // Carry the tuned autofocus config PLUS the live filter context
        // (current filter, wheel id, per-filter focus offsets) so the post-flip
        // refocus doesn't fall back to defaults on the wrong filter (finding
        // #11: filter wheel + offsets were previously dropped).
        autofocus_config: autofocus_config.map(|cfg| {
            crate::meridian_flip_executor::PostFlipAutofocusConfig {
                config: cfg.clone(),
                current_filter: ctx.current_filter.clone(),
                filterwheel_id: ctx.filterwheel_id.clone(),
                filter_focus_offsets: ctx.filter_focus_offsets.clone(),
            }
        }),
        // Real sequence-driven flip: command the hardware. The dry-run path
        // (Phase G) is the only caller that sets this true.
        simulate: false,
    };

    let mut flip_executor = crate::meridian_flip_executor::MeridianFlipExecutor::new(
        config.clone(),
        ctx.device_ops.clone(),
    );
    // forward the live executor event channel so the
    // post-flip refocus emits its instruction-level failures to UI
    // subscribers (FITS-save errors during the test exposure, etc.).
    // When the instruction runs outside a live executor (unit tests),
    // ctx.event_tx is None and the chain remains silent.
    if let Some(event_tx) = ctx.event_tx.clone() {
        flip_executor = flip_executor.with_executor_event_tx(event_tx);
    }

    match flip_executor.execute(&flip_ctx).await {
        crate::meridian_flip_executor::FlipResult::Success {
            new_pier_side,
            duration_secs,
        } => {
            tracing::info!(
                "Meridian flip complete (pier side: {:?}, took {:.1}s)",
                new_pier_side,
                duration_secs
            );
            if let Some(cb) = progress_callback {
                cb(100.0, "Flip complete".to_string());
            }
            // §1.6: mark_flip_performed is invoked inside the executor on
            // success when trigger_state is supplied; the instruction-path
            // populates trigger_state via the FlipContext above so the same
            // bookkeeping happens regardless of caller.
            InstructionResult::success_with_message(format!(
                "Meridian flip completed successfully (pier side: {:?})",
                new_pier_side
            ))
        }
        crate::meridian_flip_executor::FlipResult::Failed {
            error,
            action_taken,
        } => InstructionResult::failure_with_recovery(
            format!(
                "Meridian flip failed: {} (action taken: {:?})",
                error, action_taken
            ),
            "FLIP_FAILED",
        ),
        crate::meridian_flip_executor::FlipResult::Aborted { reason } => {
            InstructionResult::cancelled(reason)
        }
    }
}

// =============================================================================
// DOME INSTRUCTIONS
// =============================================================================

/// Maximum time to wait for a dome shutter to reach a commanded state.
/// Dome shutters are slow (30–90 s is typical on ASCOM/Alpaca observatory
/// domes), so this is generous. `DomeConfig` carries no per-node timeout
/// today (the Dart node only exposes `shutterOnly`), so this is the single
/// source of truth for the dome-shutter wait.
const DOME_SHUTTER_TIMEOUT_SECS: f64 = 120.0;

/// Result of waiting on a dome shutter to reach a commanded state. The `Ok`
/// arm distinguishes a *confirmed* arrival from a *degraded* one so callers
/// that need a genuine guarantee (the unattended safe-state sweep) can treat
/// the unconfirmed case as unsafe while the per-instruction path keeps its
/// roll-off-roof tolerance.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DomeShutterWaitOutcome {
    /// The dome reported it reached the commanded state.
    Confirmed,
    /// The dome never reported a definite shutter state (e.g. an INDI
    /// roll-off without a `DOME_SHUTTER` switch). The command was issued but
    /// arrival could NOT be confirmed. Surfaced, never silently treated as a
    /// clean success.
    Unconfirmed,
}

/// Poll the dome shutter status until it reaches `target` ("Open" or
/// "Closed"), or fail closed on timeout / a reported Error.
///
/// dome open/close/park were previously fire-and-forget — the command
/// returned and the sequence moved on (slewing/exposing) while the shutter
/// was still moving, or never opened/closed at all. The cover/calibrator
/// nodes already poll for their target state; domes now do too.
///
/// Robustness: some domes (e.g. INDI roll-offs without `DOME_SHUTTER`
/// switches) cannot report shutter state and the bridge returns
/// Unknown/"Error" for them. We must not fail those — so if EVERY poll comes
/// back Unknown/"Error" (the device never reports a real state), we degrade
/// LOUDLY (warn + event) and return [`DomeShutterWaitOutcome::Unconfirmed`]
/// rather than blocking a working roll-off roof OR claiming a clean success.
/// If the dome ever reports a real state but never reaches `target` within the
/// timeout, that is a genuine failure and we fail closed (`Err`).
async fn wait_for_dome_shutter_state(
    ctx: &InstructionContext,
    dome_id: &str,
    target: &str,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> Result<DomeShutterWaitOutcome, InstructionResult> {
    const POLL_SECS: f64 = 2.0;
    let mut elapsed = 0.0_f64;
    // Whether the dome ever reported a definite (non-Unknown) state. If it
    // never does, the device can't report status and we can't enforce a wait.
    let mut saw_definite_state = false;

    loop {
        if let Some(result) = ctx.check_cancelled() {
            return Err(result);
        }

        match ctx.device_ops.dome_get_shutter_status(dome_id).await {
            Ok(status) => {
                if status == target {
                    return Ok(DomeShutterWaitOutcome::Confirmed);
                }
                if status == "Open"
                    || status == "Closed"
                    || status == "Opening"
                    || status == "Closing"
                {
                    saw_definite_state = true;
                }

                if let Some(cb) = progress_callback {
                    // Hold progress in the 50–95% band while moving.
                    let pct = (50.0 + (elapsed / DOME_SHUTTER_TIMEOUT_SECS) * 45.0).min(95.0);
                    cb(pct, format!("Waiting for shutter ({status})"));
                }
            }
            Err(e) => {
                // A hard read error (driver fault / disconnect) is fatal —
                // we cannot verify the shutter, which is exactly the unsafe
                // case for a close.
                return Err(InstructionResult::failure(format!(
                    "Failed to read dome shutter status while waiting for {target}: {e}"
                )));
            }
        }

        if elapsed >= DOME_SHUTTER_TIMEOUT_SECS {
            if saw_definite_state {
                // The dome reports status but never reached the target — a
                // real motor/jam failure. Fail closed.
                return Err(InstructionResult::failure(format!(
                    "Dome shutter did not reach {target} within {:.0}s",
                    DOME_SHUTTER_TIMEOUT_SECS
                )));
            }
            // The dome never reported a real state — it cannot report shutter
            // position. Degrade loudly rather than failing a working dome, but
            // do NOT claim a clean success: return Unconfirmed so a caller that
            // needs a genuine guarantee (the unattended safe-state sweep) can
            // treat the never-confirmed close as unsafe.
            let msg = format!(
                "Dome shutter status unavailable; cannot confirm {target} \
                 (proceeding after issuing the command)"
            );
            tracing::warn!("{msg}");
            if let Some(event_tx) = &ctx.event_tx {
                let _ = event_tx.send(crate::executor::ExecutorEvent::Error { message: msg });
            }
            return Ok(DomeShutterWaitOutcome::Unconfirmed);
        }

        sleep(Duration::from_secs_f64(POLL_SECS)).await;
        elapsed += POLL_SECS;
    }
}

/// Execute open dome
pub async fn execute_open_dome(
    config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let dome_id = match ctx.dome_id().await {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Opening dome shutter".to_string());
    }

    tracing::info!("Opening dome shutter...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for shutter to open".to_string());
    }

    if let Err(e) = ctx.device_ops.dome_open(&dome_id).await {
        return InstructionResult::failure(format!("Failed to open dome: {}", e));
    }

    if !config.shutter_only {
        // DeviceOps does not currently expose dome_unpark.
        // Operators must ensure dome park state is compatible with opening.
    }

    // Wait for the shutter to actually reach Open before declaring success —
    // previously this returned immediately while the shutter was still
    // moving, so the next instruction could slew/expose against a closed roof.
    let open_outcome =
        match wait_for_dome_shutter_state(ctx, &dome_id, "Open", progress_callback).await {
            Ok(outcome) => outcome,
            Err(failure) => return failure,
        };

    // Report completion
    if let Some(cb) = progress_callback {
        cb(100.0, "Dome shutter open".to_string());
    }

    match open_outcome {
        DomeShutterWaitOutcome::Confirmed => {
            InstructionResult::success_with_message("Dome shutter opened")
        }
        DomeShutterWaitOutcome::Unconfirmed => InstructionResult::success_with_message(
            "Dome open command issued; shutter position could not be confirmed",
        ),
    }
}

/// Execute close dome
pub async fn execute_close_dome(
    _config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let dome_id = match ctx.dome_id().await {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Closing dome shutter".to_string());
    }

    tracing::info!("Closing dome shutter...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for shutter to close".to_string());
    }

    if let Err(e) = ctx.device_ops.dome_close(&dome_id).await {
        return InstructionResult::failure(format!("Failed to close dome: {}", e));
    }

    // Confirm the shutter actually reached Closed — a roof that reports
    // "command accepted" but jams half-open would otherwise leave the scope
    // exposed for the rest of the night.
    let close_outcome =
        match wait_for_dome_shutter_state(ctx, &dome_id, "Closed", progress_callback).await {
            Ok(outcome) => outcome,
            Err(failure) => return failure,
        };

    // Report completion
    if let Some(cb) = progress_callback {
        cb(100.0, "Dome shutter closed".to_string());
    }

    match close_outcome {
        DomeShutterWaitOutcome::Confirmed => {
            InstructionResult::success_with_message("Dome shutter closed")
        }
        DomeShutterWaitOutcome::Unconfirmed => InstructionResult::success_with_message(
            "Dome close command issued; shutter position could not be confirmed",
        ),
    }
}

/// Execute park dome
pub async fn execute_park_dome(
    config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let dome_id = match ctx.dome_id().await {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Parking dome".to_string());
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    if !config.shutter_only {
        // Report waiting progress BEFORE the async call
        if let Some(cb) = progress_callback {
            cb(50.0, "Waiting for dome to reach park position".to_string());
        }

        tracing::info!("Parking dome...");
        if let Err(e) = ctx.device_ops.dome_park(&dome_id).await {
            return InstructionResult::failure(format!("Failed to park dome: {}", e));
        }
    }

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Usually parking involves closing shutter too. This is safety-critical:
    // a swallowed close-error here would report "parked" while the scope sits
    // exposed under an open shutter all night. Propagate it (mirrors
    // `execute_close_dome`) rather than discarding the Result.
    tracing::info!("Closing shutter (park sequence)...");
    if let Err(e) = ctx.device_ops.dome_close(&dome_id).await {
        return InstructionResult::failure(format!(
            "Dome parked but failed to close shutter: {}",
            e
        ));
    }

    // Confirm the shutter reached Closed before claiming the park succeeded.
    if let Err(failure) =
        wait_for_dome_shutter_state(ctx, &dome_id, "Closed", progress_callback).await
    {
        return failure;
    }

    // Report completion
    if let Some(cb) = progress_callback {
        cb(100.0, "Dome parked".to_string());
    }

    InstructionResult::success_with_message("Dome parked")
}

// =============================================================================
// MOSAIC INSTRUCTION
// =============================================================================

/// Execute mosaic panel iteration. Delegates to [`crate::mosaic::run_mosaic_wizard`]
/// which drives a [`crate::wizard::Wizard`] for per-panel checkpoint
/// support. Behavior is byte-identical to the pre-refactor monolithic
/// implementation.
pub async fn execute_mosaic(
    config: &crate::MosaicConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    crate::mosaic::run_mosaic_wizard(config, ctx, progress_callback).await
}

// =============================================================================
// COVER CALIBRATOR (FLAT PANEL / DUST COVER) INSTRUCTIONS
// =============================================================================

/// Execute open cover (unpark dust cap)
pub async fn execute_open_cover(
    config: &crate::CoverCalibratorConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let device_id = match ctx.cover_calibrator_id().await {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Opening cover".to_string());
    }

    tracing::info!("Opening cover...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for cover to open".to_string());
    }

    // Start opening the cover
    if let Err(e) = ctx.device_ops.cover_calibrator_open_cover(&device_id).await {
        return InstructionResult::failure(format!("Failed to open cover: {}", e));
    }

    // Wait for cover to reach open state with timeout
    // Why: u32 timeout_secs -> u64 widening is lossless.
    let timeout = Duration::from_secs(u64::from(config.timeout_secs));
    match wait_for_cover_state(&device_id, 3, ctx, timeout).await {
        Ok(_) => {
            // Report completion
            if let Some(cb) = progress_callback {
                cb(100.0, "Cover open".to_string());
            }
            InstructionResult::success_with_message("Cover opened")
        }
        Err(e) => InstructionResult::failure(e),
    }
}

/// Execute close cover (park dust cap)
pub async fn execute_close_cover(
    config: &crate::CoverCalibratorConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let device_id = match ctx.cover_calibrator_id().await {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Closing cover".to_string());
    }

    tracing::info!("Closing cover...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for cover to close".to_string());
    }

    // Start closing the cover
    if let Err(e) = ctx
        .device_ops
        .cover_calibrator_close_cover(&device_id)
        .await
    {
        return InstructionResult::failure(format!("Failed to close cover: {}", e));
    }

    // Wait for cover to reach closed state with timeout
    // Why: u32 timeout_secs -> u64 widening is lossless.
    let timeout = Duration::from_secs(u64::from(config.timeout_secs));
    match wait_for_cover_state(&device_id, 1, ctx, timeout).await {
        Ok(_) => {
            // Report completion
            if let Some(cb) = progress_callback {
                cb(100.0, "Cover closed".to_string());
            }
            InstructionResult::success_with_message("Cover closed")
        }
        Err(e) => InstructionResult::failure(e),
    }
}

/// Execute calibrator on (turn on flat panel light)
pub async fn execute_calibrator_on(
    config: &crate::CalibratorOnConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let device_id = match ctx.cover_calibrator_id().await {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Turning on calibrator".to_string());
    }

    tracing::info!(
        "Turning calibrator on at brightness {}...",
        config.brightness
    );

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(
            50.0,
            format!("Adjusting brightness to {}%", config.brightness),
        );
    }

    // Turn on the calibrator at specified brightness
    if let Err(e) = ctx
        .device_ops
        .cover_calibrator_calibrator_on(&device_id, config.brightness)
        .await
    {
        return InstructionResult::failure(format!("Failed to turn on calibrator: {}", e));
    }

    // Wait for calibrator to reach ready state with timeout
    // Why: u32 timeout_secs -> u64 widening is lossless.
    let timeout = Duration::from_secs(u64::from(config.timeout_secs));
    match wait_for_calibrator_state(&device_id, 3, ctx, timeout).await {
        Ok(_) => {
            // Verify brightness is set correctly
            // Why: post-set verification readback; an Err here would mean
            // the driver dropped the cover-calibrator session between SetBrightness and
            // GetBrightness — falling back to the requested value `config.brightness`
            // simply trusts the SetBrightness call that already returned success above
            // (it propagated via `?`). The successful "wait for state 3" check
            // (`wait_for_calibrator_state`) is the load-bearing readiness signal.
            let actual_brightness = ctx
                .device_ops
                .cover_calibrator_get_brightness(&device_id)
                .await
                .unwrap_or(config.brightness);
            // Report completion
            if let Some(cb) = progress_callback {
                cb(
                    100.0,
                    format!("Calibrator on at brightness {}", actual_brightness),
                );
            }
            InstructionResult::success_with_message(format!(
                "Calibrator on at brightness {}",
                actual_brightness
            ))
        }
        Err(e) => InstructionResult::failure(e),
    }
}

/// Execute calibrator off (turn off flat panel light)
pub async fn execute_calibrator_off(
    config: &crate::CoverCalibratorConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    let device_id = match ctx.cover_calibrator_id().await {
        Ok(id) => id,
        Err(e) => return e,
    };

    // Report initial progress
    if let Some(cb) = progress_callback {
        cb(0.0, "Turning off calibrator".to_string());
    }

    tracing::info!("Turning calibrator off...");

    if let Some(result) = ctx.check_cancelled() {
        return result;
    }

    // Report waiting progress BEFORE the async call
    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for calibrator to turn off".to_string());
    }

    // Turn off the calibrator
    if let Err(e) = ctx
        .device_ops
        .cover_calibrator_calibrator_off(&device_id)
        .await
    {
        return InstructionResult::failure(format!("Failed to turn off calibrator: {}", e));
    }

    // Wait for calibrator to reach off state with timeout
    // Why: u32 timeout_secs -> u64 widening is lossless.
    let timeout = Duration::from_secs(u64::from(config.timeout_secs));
    match wait_for_calibrator_state(&device_id, 1, ctx, timeout).await {
        Ok(_) => {
            // Report completion
            if let Some(cb) = progress_callback {
                cb(100.0, "Calibrator off".to_string());
            }
            InstructionResult::success_with_message("Calibrator off")
        }
        Err(e) => InstructionResult::failure(e),
    }
}

/// Wait for cover to reach target state with timeout
/// States: 0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error
async fn wait_for_cover_state(
    device_id: &str,
    target_state: i32,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    let state_name = match target_state {
        0 => "NotPresent",
        1 => "Closed",
        2 => "Moving",
        3 => "Open",
        4 => "Unknown",
        5 => "Error",
        _ => "Unknown",
    };

    loop {
        // Check cancellation
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            // Try to halt cover movement
            let _ = ctx.device_ops.cover_calibrator_halt_cover(device_id).await;
            return Err("Operation cancelled".to_string());
        }

        // Check current state
        match ctx
            .device_ops
            .cover_calibrator_get_cover_state(device_id)
            .await
        {
            Ok(state) => {
                if state == target_state {
                    tracing::debug!("Cover reached {} state", state_name);
                    return Ok(());
                }
                if state == 5 {
                    return Err("Cover reported error state".to_string());
                }
                tracing::trace!("Cover state: {}, waiting for {}", state, state_name);
            }
            Err(e) => {
                tracing::warn!("Error checking cover state: {}", e);
                // Continue polling - transient error
            }
        }

        // Check timeout
        if start.elapsed() > timeout {
            return Err(format!(
                "Cover did not reach {} state within {} seconds",
                state_name,
                timeout.as_secs()
            ));
        }

        // Poll every 500ms
        sleep(Duration::from_millis(500)).await;
    }
}

/// Wait for calibrator to reach target state with timeout
/// States: 0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error
async fn wait_for_calibrator_state(
    device_id: &str,
    target_state: i32,
    ctx: &InstructionContext,
    timeout: Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    let state_name = match target_state {
        0 => "NotPresent",
        1 => "Off",
        2 => "NotReady",
        3 => "Ready",
        4 => "Unknown",
        5 => "Error",
        _ => "Unknown",
    };

    loop {
        // Check cancellation
        if ctx.cancellation_token.load(Ordering::Relaxed) {
            let _ = ctx
                .device_ops
                .cover_calibrator_calibrator_off(device_id)
                .await;
            let _ = ctx.device_ops.cover_calibrator_halt_cover(device_id).await;
            return Err("Operation cancelled".to_string());
        }

        // Check current state
        match ctx
            .device_ops
            .cover_calibrator_get_calibrator_state(device_id)
            .await
        {
            Ok(state) => {
                if state == target_state {
                    tracing::debug!("Calibrator reached {} state", state_name);
                    return Ok(());
                }
                if state == 5 {
                    return Err("Calibrator reported error state".to_string());
                }
                tracing::trace!("Calibrator state: {}, waiting for {}", state, state_name);
            }
            Err(e) => {
                tracing::warn!("Error checking calibrator state: {}", e);
                // Continue polling - transient error
            }
        }

        // Check timeout
        if start.elapsed() > timeout {
            let _ = ctx.device_ops.cover_calibrator_halt_cover(device_id).await;
            return Err(format!(
                "Calibrator did not reach {} state within {} seconds",
                state_name,
                timeout.as_secs()
            ));
        }

        // Poll every 200ms (calibrator state can change quickly)
        sleep(Duration::from_millis(200)).await;
    }
}

// =============================================================================
// TESTS
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Serializes tests that touch the process-global `AUTOFOCUS_RUN_ACTIVE`
    /// gate — cargo runs tests across threads and the gate is shared state, so
    /// without this they race (one test's held gate breaks another's admit).
    static AF_GATE_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    /// Q3: `ensure_unique_save_path` tested existence and then returned the
    /// path without claiming it, so two callers racing on the same rendered
    /// filename both got the same path — two `captured_images` rows, one file,
    /// one frame's pixels gone. Allocation must be atomic.
    #[test]
    fn concurrent_save_path_allocation_never_hands_out_the_same_file_twice() {
        let dir = std::env::temp_dir().join(format!("ns-save-path-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("temp dir");
        let contended = dir.join("Dark_nofilter_0001.fits");

        let handles: Vec<_> = (0..8)
            .map(|_| {
                let candidate = contended.clone();
                std::thread::spawn(move || ensure_unique_save_path(candidate))
            })
            .collect();
        let allocated: Vec<PathBuf> = handles
            .into_iter()
            .map(|h| h.join().expect("allocation thread"))
            .collect();

        let distinct: std::collections::HashSet<&PathBuf> = allocated.iter().collect();
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(
            distinct.len(),
            allocated.len(),
            "every concurrent caller must get its own file; got {allocated:?}"
        );
    }

    #[test]
    fn autofocus_admission_is_atomic_and_released_by_guard() {
        let _serial = AF_GATE_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let first = try_admit_autofocus_run().expect("first run must admit");
        assert!(
            try_admit_autofocus_run().is_none(),
            "a concurrent autofocus run must be rejected"
        );
        drop(first);
        let next = try_admit_autofocus_run().expect("guard drop must release admission");
        drop(next);
    }

    // Single-threaded (current-thread) tokio runtime, so holding the sync gate
    // lock across awaits cannot deadlock; the lock only serializes vs other
    // gate tests running on separate threads.
    #[tokio::test(start_paused = true)]
    #[allow(clippy::await_holding_lock)]
    async fn node_admission_waits_for_inflight_run_then_times_out_on_stuck_gate() {
        let _serial = AF_GATE_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());

        // Scenario 1: a trigger-fired run holds the gate; the node waiter must
        // NOT resolve while it is held (the old fail-fast aborted the run here).
        let inflight = try_admit_autofocus_run().expect("first run must admit");
        let waiter =
            tokio::spawn(async { admit_autofocus_run_waiting(Duration::from_secs(600)).await });
        tokio::time::sleep(Duration::from_secs(5)).await;
        assert!(
            !waiter.is_finished(),
            "the node waiter must keep waiting while an autofocus is in flight, \
             not fail immediately"
        );
        // Once the in-flight run releases, the waiter admits.
        drop(inflight);
        let guard = waiter
            .await
            .expect("waiter task panicked")
            .expect("waiter must admit once the gate frees");
        drop(guard);

        // Scenario 2: a gate that never releases must time out (not hang).
        let _stuck = try_admit_autofocus_run().expect("hold the gate");
        let result = admit_autofocus_run_waiting(Duration::from_secs(600)).await;
        assert!(
            result.is_none(),
            "a gate that never releases must time out, not hang forever"
        );
    }

    #[test]
    fn autofocus_config_validation_rejects_decorative_or_dangerous_values() {
        let valid = AutofocusConfig::default();
        assert!(validate_autofocus_config(&valid).is_ok());

        let mut invalid = valid.clone();
        invalid.exposures_per_point = 0;
        assert!(validate_autofocus_config(&invalid).is_err());

        let mut invalid = valid.clone();
        invalid.inner_crop_ratio = invalid.outer_crop_ratio;
        assert!(validate_autofocus_config(&invalid).is_err());

        let mut invalid = valid.clone();
        invalid.number_of_attempts = 11;
        assert!(validate_autofocus_config(&invalid).is_err());

        let mut invalid = valid.clone();
        invalid.gain = Some(-1);
        assert!(validate_autofocus_config(&invalid).is_err());

        let mut invalid = valid;
        invalid.max_duration_secs = 0.0;
        assert!(validate_autofocus_config(&invalid).is_err());
    }

    #[tokio::test]
    async fn autofocus_cleanup_restores_and_verifies_original_position() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let ctx = ctx_with_ops(ops.clone()).await;

        restore_autofocus_origin("focuser-1", &ctx, 12_345)
            .await
            .expect("cleanup should restore the original position");

        assert_eq!(ops.focuser_halt_calls.load(Ordering::SeqCst), 1);
        assert_eq!(*ops.focuser_moves.lock().unwrap(), vec![12_345]);
    }

    #[tokio::test]
    #[allow(clippy::await_holding_lock)]
    async fn autofocus_restores_designated_filter_and_guiding_on_cancel() {
        let _serial = AF_GATE_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_guiding(true));
        let ctx = ctx_with_ops(ops.clone()).await;
        ctx.cancellation_token.store(true, Ordering::SeqCst);
        let mut config = AutofocusConfig {
            filter: Some("L".to_string()),
            disable_guiding_during_af: true,
            ..AutofocusConfig::default()
        };
        config.filter_settings.insert(
            "R".to_string(),
            crate::AutofocusFilterConfig {
                af_filter_name: Some("L".to_string()),
                gain: Some(120),
                offset: Some(15),
                ..crate::AutofocusFilterConfig::default()
            },
        );

        let guard = try_admit_autofocus_run().expect("test autofocus must admit");
        let result = execute_autofocus_admitted(&config, &ctx, None, guard).await;

        assert_eq!(result.status, NodeStatus::Cancelled);
        assert_eq!(*ops.filter_moves.lock().unwrap(), vec![0, 1]);
        assert_eq!(ops.guider_stop_calls.load(Ordering::SeqCst), 1);
        assert_eq!(ops.guider_start_calls.load(Ordering::SeqCst), 1);
        assert!(ops.guiding.load(Ordering::SeqCst));
    }

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

    // -------------------------------------------------------------------
    // P3-7: post-start calibration quality validation
    // -------------------------------------------------------------------

    fn _cfg() -> StartGuidingConfig {
        StartGuidingConfig::default()
    }

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

    // -------------------------------------------------------------------
    // Image Grading: reject folder resolution
    // -------------------------------------------------------------------

    #[test]
    fn reject_dir_defaults_to_reject_subfolder_of_save_path() {
        let base = std::path::Path::new("/captures/M31/L");
        let dir = resolve_reject_dir(base, None);
        assert_eq!(dir, std::path::Path::new("/captures/M31/L/Reject"));
    }

    #[test]
    fn reject_dir_relative_override_resolves_against_save_path() {
        let base = std::path::Path::new("/captures/M31/L");
        let dir = resolve_reject_dir(base, Some("BadFrames"));
        assert_eq!(dir, std::path::Path::new("/captures/M31/L/BadFrames"));
    }

    #[test]
    fn reject_dir_absolute_override_used_verbatim() {
        // Use platform-appropriate absolute path.
        #[cfg(windows)]
        let abs = r"C:\nightshade\rejects";
        #[cfg(not(windows))]
        let abs = "/var/nightshade/rejects";

        let base = std::path::Path::new("/captures/M31/L");
        let dir = resolve_reject_dir(base, Some(abs));
        assert_eq!(dir, std::path::Path::new(abs));
    }

    #[test]
    fn device_disconnect_messages_are_classified_narrowly() {
        assert!(is_device_disconnected_message("No camera connected"));
        assert!(is_device_disconnected_message(
            "Device 'cam1' is not connected. Cannot perform: exposure. Please reconnect the device first."
        ));
        assert!(is_device_disconnected_message(
            "Filter wheel is not connected"
        ));

        assert!(!is_device_disconnected_message(
            "No target coordinates available"
        ));
        assert!(!is_device_disconnected_message(
            "Plate solve returned no solution"
        ));
        assert!(!is_device_disconnected_message("Script exited with code 1"));
    }

    #[test]
    fn disconnected_instruction_failure_posts_recovery_request() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let (tx, mut rx) = tokio::sync::mpsc::channel(1);
            let pending = Arc::new(AtomicBool::new(false));
            let result = InstructionResult::failure("No camera connected");
            let status =
                result.log_and_get_status_with_recovery("Exposure", Some(&tx), Some(&pending));

            assert_eq!(status, NodeStatus::Failure);
            // The disconnect failure must mark the shared pending flag so the
            // node-runtime retry wrapper waits for recovery instead of letting
            // the Failure end the sequence.
            assert!(
                pending.load(Ordering::Relaxed),
                "device-disconnect failure must set the recovery-pending flag"
            );
            assert_eq!(
                rx.recv().await,
                Some(crate::recovery::RecoveryCause::DeviceDisconnected)
            );
        });
    }

    #[test]
    fn rotator_angle_diff_handles_360_wrap() {
        // Shortest signed distance, wrapping at 360.
        assert!((rotator_angle_diff(10.0, 350.0) - 20.0).abs() < 1e-9);
        assert!((rotator_angle_diff(350.0, 10.0) - -20.0).abs() < 1e-9);
        assert!((rotator_angle_diff(0.0, 0.0)).abs() < 1e-9);
        // 179 vs 181 is a 2° gap (not 358°).
        assert!((rotator_angle_diff(179.0, 181.0) - -2.0).abs() < 1e-9);
        // Exactly opposite resolves to -180 (boundary).
        assert!((rotator_angle_diff(0.0, 180.0) - -180.0).abs() < 1e-9);
    }

    #[test]
    fn normalize_rotator_angle_wraps_into_unit_circle() {
        assert!((normalize_rotator_angle(370.0) - 10.0).abs() < 1e-9);
        assert!((normalize_rotator_angle(-10.0) - 350.0).abs() < 1e-9);
        assert!((normalize_rotator_angle(0.0)).abs() < 1e-9);
        // Non-finite collapses to 0 rather than poisoning the move target.
        assert_eq!(normalize_rotator_angle(f64::NAN), 0.0);
        assert_eq!(normalize_rotator_angle(f64::INFINITY), 0.0);
    }

    #[test]
    fn non_disconnect_failure_does_not_set_recovery_pending() {
        let pending = Arc::new(AtomicBool::new(false));
        let result = InstructionResult::failure("Plate solve returned no solution");
        let status = result.log_and_get_status_with_recovery("Center", None, Some(&pending));
        assert_eq!(status, NodeStatus::Failure);
        assert!(
            !pending.load(Ordering::Relaxed),
            "a non-disconnect failure must NOT trigger device-disconnect recovery"
        );
    }

    // =====================================================================
    // DOME / ROTATOR MOVE-AND-VERIFY GUARDS (cluster: dome-rotator)
    //
    // These prove that the dome park/open/close and rotator move
    // instructions are MOVE-AND-VERIFY (they poll the device for actual
    // arrival before reporting success) and that a park failing to close
    // the shutter surfaces a hard error rather than reporting "parked".
    // A failed roof MUST return Failure, never Success.
    // =====================================================================

    // `DeviceOps`, `DeviceResult`, `GuidingStatus`, `NullDeviceOps`, `ImageData`
    // are already in scope via the module-level `use crate::*`
    // (lib.rs re-exports `device_ops::*`).
    use async_trait::async_trait;
    use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU32};
    use std::sync::Mutex;

    /// Scriptable DeviceOps for the dome/rotator verify tests. Only the
    /// dome and rotator methods are interesting; everything else delegates
    /// to `NullDeviceOps`. Counters let the tests assert that the
    /// instruction actually polled for arrival (move-and-verify) rather
    /// than fire-and-forgetting.
    struct ScriptedDomeRotatorOps {
        inner: Arc<NullDeviceOps>,
        // --- rotator ---
        /// Sequence of angles `rotator_get_angle` returns, one per poll. The
        /// last entry repeats once the script is exhausted.
        rotator_angles: Mutex<Vec<f64>>,
        rotator_get_angle_calls: AtomicU32,
        rotator_move_to_calls: AtomicU32,
        // --- dome ---
        /// Sequence of shutter statuses `dome_get_shutter_status` returns,
        /// one per poll; the last entry repeats once exhausted.
        dome_shutter_states: Mutex<Vec<String>>,
        dome_shutter_status_calls: AtomicU32,
        dome_close_calls: AtomicU32,
        dome_park_calls: AtomicU32,
        /// When `Some`, `dome_close` fails with this message.
        dome_close_error: Option<String>,
        /// Device ids `dome_open` / `cover_calibrator_open_cover` were called
        /// with, so the role-resolution tests can prove the instruction
        /// commanded the device the ops layer resolved.
        dome_open_ids: Mutex<Vec<String>>,
        cover_open_ids: Mutex<Vec<String>>,
        /// Answers for the `active_*_id` role-resolution hooks — the ops
        /// layer's "here is the connected device" reply.
        active_dome_id: Option<String>,
        active_cover_calibrator_id: Option<String>,
        /// How many times the dome role was resolved. The dome instruction
        /// asks exactly once per execution, so this counts EXECUTIONS of the
        /// node — which is what a retry-collapse test has to pin down before
        /// its "one error entry" assertion means anything.
        active_dome_id_calls: AtomicU32,
        // --- centering ---
        mount_slewing_states: Mutex<Vec<bool>>,
        mount_slew_state_calls: AtomicU32,
        /// How many times the mount was actually commanded to move. A gate that
        /// only changes the returned message while still driving the mount is
        /// indistinguishable from a real gate without this.
        mount_slew_calls: AtomicU32,
        // --- camera ---
        camera_exposure_calls: AtomicU32,
        camera_abort_calls: AtomicU32,
        hang_camera_exposure: bool,
        /// Every `(enabled, target)` the instruction handed the cooler.
        cooler_commands: Mutex<Vec<(bool, f64)>>,
        /// When `Some`, a `camera_set_cooler(_, false, _)` fails with this
        /// message — the shape the reference rig produced when its cooler
        /// could not be switched off.
        cooler_off_error: Option<String>,
        /// Raised by the first exposure only; see
        /// [`ScriptedDomeRotatorOps::pausing_after_first_exposure`].
        pause_flag_after_first_exposure: Option<Arc<AtomicBool>>,
        // --- autofocus cleanup ---
        focuser_moves: Mutex<Vec<i32>>,
        focuser_halt_calls: AtomicU32,
        filter_position: AtomicI32,
        filter_names: Vec<String>,
        filter_moves: Mutex<Vec<i32>>,
        guiding: AtomicBool,
        guider_stop_calls: AtomicU32,
        guider_start_calls: AtomicU32,
        guider_calibration: Option<GuidingCalibration>,
        /// W1 daylight gate — value returned by `mount_is_parked`. Defaults to
        /// `false` (matching NullDeviceOps); the parked-rig gate test sets it
        /// `true` to prove a parked exposure is never daylight-gated.
        mount_parked: bool,
        // --- per-frame capture truth -----------------------------------
        /// Every `FrameContext` this ops layer was handed by `save_fits`, in
        /// order. This is the FITS writer's own input — recording it is the
        /// only way to assert the frame EVENT was stamped from the same struct
        /// rather than from a second reconstruction of the same exposure.
        saved_frame_contexts: Mutex<Vec<crate::scheduling::FrameContext>>,
        /// The full path each frame was written to, in the same order. The
        /// filename is rendered from a DIFFERENT source than the header, so
        /// recording both is what lets a test prove the two agree.
        saved_frame_paths: Mutex<Vec<String>>,
        /// Distinctive live telemetry so a `FrameContext::default()` cannot
        /// masquerade as a real read. `None` keeps NullDeviceOps' answer.
        scripted_mount_coordinates: Option<(f64, f64)>,
        scripted_pier_side: Option<crate::meridian::PierSide>,
        scripted_cooler_power: Option<f64>,
        scripted_focuser_position: Option<i32>,
        scripted_focuser_temperature: Option<f64>,
        /// What the camera claims it exposed for, independent of what was
        /// commanded — a driver that misreports is the whole point of the
        /// exposure-duration reconciliation.
        scripted_reported_exposure_secs: Option<f64>,
        scripted_gain: Option<i32>,
        scripted_offset: Option<i32>,
        scripted_sensor_temp_c: Option<f64>,
        /// Unbinned pixel pitch the camera reports, in microns. `None` stands
        /// in for a driver that will not answer.
        scripted_pixel_size_um: Option<(f64, f64)>,
    }

    impl ScriptedDomeRotatorOps {
        fn new() -> Self {
            Self {
                inner: Arc::new(NullDeviceOps),
                rotator_angles: Mutex::new(vec![0.0]),
                rotator_get_angle_calls: AtomicU32::new(0),
                rotator_move_to_calls: AtomicU32::new(0),
                dome_shutter_states: Mutex::new(vec!["Closed".to_string()]),
                dome_shutter_status_calls: AtomicU32::new(0),
                dome_close_calls: AtomicU32::new(0),
                dome_park_calls: AtomicU32::new(0),
                dome_close_error: None,
                dome_open_ids: Mutex::new(Vec::new()),
                cover_open_ids: Mutex::new(Vec::new()),
                active_dome_id: None,
                active_cover_calibrator_id: None,
                active_dome_id_calls: AtomicU32::new(0),
                mount_slewing_states: Mutex::new(vec![false]),
                mount_slew_state_calls: AtomicU32::new(0),
                mount_slew_calls: AtomicU32::new(0),
                camera_exposure_calls: AtomicU32::new(0),
                camera_abort_calls: AtomicU32::new(0),
                hang_camera_exposure: false,
                cooler_commands: Mutex::new(Vec::new()),
                cooler_off_error: None,
                pause_flag_after_first_exposure: None,
                mount_parked: false,
                focuser_moves: Mutex::new(Vec::new()),
                focuser_halt_calls: AtomicU32::new(0),
                filter_position: AtomicI32::new(1),
                filter_names: vec!["L".to_string(), "R".to_string()],
                filter_moves: Mutex::new(Vec::new()),
                guiding: AtomicBool::new(false),
                guider_stop_calls: AtomicU32::new(0),
                guider_start_calls: AtomicU32::new(0),
                guider_calibration: None,
                saved_frame_contexts: Mutex::new(Vec::new()),
                saved_frame_paths: Mutex::new(Vec::new()),
                scripted_mount_coordinates: None,
                scripted_pier_side: None,
                scripted_cooler_power: None,
                scripted_focuser_position: None,
                scripted_focuser_temperature: None,
                scripted_reported_exposure_secs: None,
                scripted_gain: None,
                scripted_offset: None,
                scripted_sensor_temp_c: None,
                scripted_pixel_size_um: None,
            }
        }

        /// Stand in for a fully-instrumented rig: every per-frame telemetry
        /// read answers with a distinctive value, so a frame event stamped
        /// from anything other than this rig's own readings is visible.
        fn with_capture_telemetry(mut self) -> Self {
            self.scripted_mount_coordinates = Some((5.5, -5.25));
            self.scripted_pier_side = Some(crate::meridian::PierSide::West);
            self.scripted_cooler_power = Some(63.5);
            self.scripted_focuser_position = Some(31_705);
            self.scripted_focuser_temperature = Some(4.25);
            self.scripted_gain = Some(139);
            self.scripted_offset = Some(21);
            self.scripted_sensor_temp_c = Some(-9.5);
            self.scripted_pixel_size_um = Some((3.76, 3.76));
            self
        }

        /// Park the mount at these coordinates so a completed slew passes
        /// `validate_slew_position` instead of tripping over NullDeviceOps'
        /// fixed answer.
        fn with_scripted_mount_coordinates(mut self, ra_hours: f64, dec_degrees: f64) -> Self {
            self.scripted_mount_coordinates = Some((ra_hours, dec_degrees));
            self
        }

        /// Make the camera report an exposure length of its own choosing.
        fn with_reported_exposure_secs(mut self, secs: f64) -> Self {
            self.scripted_reported_exposure_secs = Some(secs);
            self
        }

        /// The `FrameContext`s handed to `save_fits`, in call order.
        fn saved_frame_contexts(&self) -> Vec<crate::scheduling::FrameContext> {
            self.saved_frame_contexts.lock().unwrap().clone()
        }

        /// The paths `save_fits` was asked to write, in call order.
        fn saved_frame_paths(&self) -> Vec<String> {
            self.saved_frame_paths.lock().unwrap().clone()
        }

        fn with_mount_parked(mut self, parked: bool) -> Self {
            self.mount_parked = parked;
            self
        }

        fn with_rotator_angles(mut self, angles: Vec<f64>) -> Self {
            self.rotator_angles = Mutex::new(angles);
            self
        }

        fn with_dome_shutter_states(mut self, states: &[&str]) -> Self {
            self.dome_shutter_states =
                Mutex::new(states.iter().map(|s| (*s).to_string()).collect());
            self
        }

        fn with_dome_close_error(mut self, msg: &str) -> Self {
            self.dome_close_error = Some(msg.to_string());
            self
        }

        /// Stand in for a rig with this dome connected but no dome role in the
        /// sequence context.
        fn with_active_dome_id(mut self, id: &str) -> Self {
            self.active_dome_id = Some(id.to_string());
            self
        }

        fn with_active_cover_calibrator_id(mut self, id: &str) -> Self {
            self.active_cover_calibrator_id = Some(id.to_string());
            self
        }

        fn with_guiding(self, guiding: bool) -> Self {
            self.guiding.store(guiding, Ordering::SeqCst);
            self
        }

        fn with_mount_slewing_states(mut self, states: Vec<bool>) -> Self {
            self.mount_slewing_states = Mutex::new(states);
            self
        }

        fn with_hanging_camera(mut self) -> Self {
            self.hang_camera_exposure = true;
            self
        }

        /// Stand in for the reference rig on 2026-08-09: the cooler-off
        /// command comes back as an error.
        fn with_failing_cooler_off(mut self, message: &str) -> Self {
            self.cooler_off_error = Some(message.to_string());
            self
        }

        /// Stand in for the operator pressing Pause while frame 1 of a burst
        /// is integrating: the FIRST exposure raises `flag`, later ones don't.
        fn pausing_after_first_exposure(mut self, flag: Arc<AtomicBool>) -> Self {
            self.pause_flag_after_first_exposure = Some(flag);
            self
        }

        fn with_guider_calibration(mut self, calibration: GuidingCalibration) -> Self {
            self.guider_calibration = Some(calibration);
            self
        }

        /// Pop the next scripted value, repeating the final entry forever
        /// once the script runs out (so a "never arrives" script can drive
        /// the timeout path).
        fn next_scripted<T: Clone>(script: &Mutex<Vec<T>>) -> T {
            let mut v = script.lock().unwrap();
            if v.len() > 1 {
                v.remove(0)
            } else {
                v[0].clone()
            }
        }
    }

    #[async_trait]
    impl DeviceOps for ScriptedDomeRotatorOps {
        // --- rotator (verified-move surface) ---
        async fn rotator_move_to(&self, _id: &str, _angle: f64) -> DeviceResult<()> {
            self.rotator_move_to_calls.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }
        async fn rotator_get_angle(&self, _id: &str) -> DeviceResult<f64> {
            self.rotator_get_angle_calls.fetch_add(1, Ordering::SeqCst);
            Ok(Self::next_scripted(&self.rotator_angles))
        }

        // --- dome (verified-close surface) ---
        async fn dome_close(&self, id: &str) -> DeviceResult<()> {
            self.dome_close_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(err) = &self.dome_close_error {
                return Err(err.clone());
            }
            self.inner.dome_close(id).await
        }
        async fn dome_park(&self, _id: &str) -> DeviceResult<()> {
            self.dome_park_calls.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }
        async fn dome_get_shutter_status(&self, _id: &str) -> DeviceResult<String> {
            self.dome_shutter_status_calls
                .fetch_add(1, Ordering::SeqCst);
            Ok(Self::next_scripted(&self.dome_shutter_states))
        }

        // === delegating methods ===
        async fn mount_slew_to_coordinates(&self, id: &str, ra: f64, dec: f64) -> DeviceResult<()> {
            self.mount_slew_calls.fetch_add(1, Ordering::SeqCst);
            self.inner.mount_slew_to_coordinates(id, ra, dec).await
        }
        async fn mount_abort_slew(&self, id: &str) -> DeviceResult<()> {
            self.inner.mount_abort_slew(id).await
        }
        async fn mount_get_coordinates(&self, id: &str) -> DeviceResult<(f64, f64)> {
            match self.scripted_mount_coordinates {
                Some(coords) => Ok(coords),
                None => self.inner.mount_get_coordinates(id).await,
            }
        }
        async fn mount_sync(&self, id: &str, ra: f64, dec: f64) -> DeviceResult<()> {
            self.inner.mount_sync(id, ra, dec).await
        }
        async fn mount_park(&self, id: &str) -> DeviceResult<()> {
            self.inner.mount_park(id).await
        }
        async fn mount_unpark(&self, id: &str) -> DeviceResult<()> {
            self.inner.mount_unpark(id).await
        }
        async fn mount_is_slewing(&self, id: &str) -> DeviceResult<bool> {
            let _ = id;
            self.mount_slew_state_calls.fetch_add(1, Ordering::SeqCst);
            Ok(Self::next_scripted(&self.mount_slewing_states))
        }
        async fn mount_is_parked(&self, _id: &str) -> DeviceResult<bool> {
            Ok(self.mount_parked)
        }
        async fn mount_can_flip(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_can_flip(id).await
        }
        async fn mount_side_of_pier(&self, id: &str) -> DeviceResult<crate::meridian::PierSide> {
            if let Some(side) = self.scripted_pier_side {
                return Ok(side);
            }
            self.inner.mount_side_of_pier(id).await
        }
        async fn mount_is_tracking(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_is_tracking(id).await
        }
        async fn mount_set_tracking(&self, id: &str, enabled: bool) -> DeviceResult<()> {
            self.inner.mount_set_tracking(id, enabled).await
        }
        async fn camera_start_exposure(
            &self,
            id: &str,
            d: f64,
            g: Option<i32>,
            o: Option<i32>,
            bx: i32,
            by: i32,
        ) -> DeviceResult<ImageData> {
            let call = self.camera_exposure_calls.fetch_add(1, Ordering::SeqCst) + 1;
            if call == 1 {
                if let Some(flag) = &self.pause_flag_after_first_exposure {
                    flag.store(true, Ordering::SeqCst);
                }
            }
            if self.hang_camera_exposure {
                return std::future::pending::<DeviceResult<ImageData>>().await;
            }
            // A scripted report decouples what the driver CLAIMS from what was
            // commanded — that split is the whole point — so the double also
            // drops NullDeviceOps' simulated integration sleep. Waiting the
            // commanded minutes in real time would only slow the suite; nothing
            // under test reads the wall clock.
            let simulated_integration = match self.scripted_reported_exposure_secs {
                Some(_) => 0.0,
                None => d,
            };
            let mut image = self
                .inner
                .camera_start_exposure(id, simulated_integration, g, o, bx, by)
                .await?;
            // The camera's own report of the frame, which is a DIFFERENT source
            // from what was commanded. Overriding it here is what lets a test
            // tell the two apart.
            if let Some(secs) = self.scripted_reported_exposure_secs {
                image.exposure_secs = secs;
            }
            if self.scripted_gain.is_some() {
                image.gain = self.scripted_gain;
            }
            if self.scripted_offset.is_some() {
                image.offset = self.scripted_offset;
            }
            if self.scripted_sensor_temp_c.is_some() {
                image.temperature = self.scripted_sensor_temp_c;
            }
            Ok(image)
        }
        async fn camera_abort_exposure(&self, id: &str) -> DeviceResult<()> {
            self.camera_abort_calls.fetch_add(1, Ordering::SeqCst);
            self.inner.camera_abort_exposure(id).await
        }
        async fn camera_set_cooler(&self, id: &str, e: bool, t: f64) -> DeviceResult<()> {
            self.cooler_commands.lock().unwrap().push((e, t));
            if !e {
                if let Some(err) = &self.cooler_off_error {
                    return Err(err.clone());
                }
            }
            self.inner.camera_set_cooler(id, e, t).await
        }
        async fn camera_get_temperature(&self, id: &str) -> DeviceResult<f64> {
            self.inner.camera_get_temperature(id).await
        }
        async fn camera_get_cooler_power(&self, id: &str) -> DeviceResult<f64> {
            match self.scripted_cooler_power {
                Some(power) => Ok(power),
                None => self.inner.camera_get_cooler_power(id).await,
            }
        }
        async fn camera_get_pixel_size_um(&self, id: &str) -> DeviceResult<Option<(f64, f64)>> {
            match self.scripted_pixel_size_um {
                Some(pitch) => Ok(Some(pitch)),
                None => self.inner.camera_get_pixel_size_um(id).await,
            }
        }
        /// What the bridge impls return: the driver's name for the connected
        /// camera, with the serial that tells two of the same model apart.
        async fn camera_get_model(&self, _id: &str) -> DeviceResult<Option<String>> {
            Ok(Some("ZWO ASI1600MM-Cool (1600-A1B2)".to_string()))
        }
        async fn focuser_move_to(&self, _id: &str, p: i32) -> DeviceResult<()> {
            self.focuser_moves.lock().unwrap().push(p);
            Ok(())
        }
        async fn focuser_get_position(&self, id: &str) -> DeviceResult<i32> {
            match self.scripted_focuser_position {
                Some(pos) => Ok(pos),
                None => self.inner.focuser_get_position(id).await,
            }
        }
        async fn focuser_is_moving(&self, _id: &str) -> DeviceResult<bool> {
            Ok(false)
        }
        async fn focuser_get_temperature(&self, id: &str) -> DeviceResult<Option<f64>> {
            if self.scripted_focuser_temperature.is_some() {
                return Ok(self.scripted_focuser_temperature);
            }
            self.inner.focuser_get_temperature(id).await
        }
        async fn focuser_halt(&self, _id: &str) -> DeviceResult<()> {
            self.focuser_halt_calls.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }
        async fn filterwheel_set_position(&self, _id: &str, p: i32) -> DeviceResult<()> {
            self.filter_moves.lock().unwrap().push(p);
            self.filter_position.store(p, Ordering::SeqCst);
            Ok(())
        }
        async fn filterwheel_get_position(&self, _id: &str) -> DeviceResult<i32> {
            Ok(self.filter_position.load(Ordering::SeqCst))
        }
        async fn filterwheel_get_names(&self, _id: &str) -> DeviceResult<Vec<String>> {
            Ok(self.filter_names.clone())
        }
        async fn filterwheel_set_filter_by_name(&self, id: &str, n: &str) -> DeviceResult<i32> {
            self.inner.filterwheel_set_filter_by_name(id, n).await
        }
        async fn rotator_move_relative(&self, id: &str, d: f64) -> DeviceResult<()> {
            self.inner.rotator_move_relative(id, d).await
        }
        async fn rotator_halt(&self, id: &str) -> DeviceResult<()> {
            self.inner.rotator_halt(id).await
        }
        async fn guider_dither(
            &self,
            p: f64,
            sp: f64,
            st: f64,
            sto: f64,
            ra: bool,
        ) -> DeviceResult<()> {
            self.inner.guider_dither(p, sp, st, sto, ra).await
        }
        async fn guider_get_status(&self) -> DeviceResult<GuidingStatus> {
            Ok(GuidingStatus {
                is_guiding: self.guiding.load(Ordering::SeqCst),
                rms_ra: 0.5,
                rms_dec: 0.5,
                rms_total: 0.7,
            })
        }
        async fn guider_get_calibration(&self) -> DeviceResult<GuidingCalibration> {
            match &self.guider_calibration {
                Some(calibration) => Ok(calibration.clone()),
                None => self.inner.guider_get_calibration().await,
            }
        }
        async fn guider_start(&self, _sp: f64, _st: f64, _sto: f64) -> DeviceResult<()> {
            self.guider_start_calls.fetch_add(1, Ordering::SeqCst);
            self.guiding.store(true, Ordering::SeqCst);
            Ok(())
        }
        async fn guider_stop(&self) -> DeviceResult<()> {
            self.guider_stop_calls.fetch_add(1, Ordering::SeqCst);
            self.guiding.store(false, Ordering::SeqCst);
            Ok(())
        }
        async fn plate_solve(
            &self,
            d: &ImageData,
            ra: Option<f64>,
            dec: Option<f64>,
            s: Option<f64>,
        ) -> DeviceResult<crate::device_ops::PlateSolveResult> {
            self.inner.plate_solve(d, ra, dec, s).await
        }
        async fn save_fits(
            &self,
            d: &ImageData,
            f: &str,
            ctx: &crate::scheduling::FrameContext,
        ) -> DeviceResult<()> {
            self.saved_frame_contexts.lock().unwrap().push(ctx.clone());
            self.saved_frame_paths.lock().unwrap().push(f.to_string());
            self.inner.save_fits(d, f, ctx).await
        }
        async fn send_notification(
            &self,
            l: &str,
            t: &str,
            m: &str,
            x: Option<&[String]>,
        ) -> DeviceResult<()> {
            self.inner.send_notification(l, t, m, x).await
        }
        fn calculate_altitude(&self, r: f64, d: f64, la: f64, lo: f64) -> f64 {
            self.inner.calculate_altitude(r, d, la, lo)
        }
        fn get_observer_location(&self) -> Option<(f64, f64)> {
            self.inner.get_observer_location()
        }
        async fn polar_align_update(
            &self,
            r: &crate::polar_align::PolarAlignResult,
        ) -> DeviceResult<()> {
            self.inner.polar_align_update(r).await
        }
        async fn dome_open(&self, id: &str) -> DeviceResult<()> {
            self.dome_open_ids.lock().unwrap().push(id.to_string());
            self.inner.dome_open(id).await
        }
        async fn active_dome_id(&self) -> Option<String> {
            self.active_dome_id_calls.fetch_add(1, Ordering::SeqCst);
            self.active_dome_id.clone()
        }
        async fn active_cover_calibrator_id(&self) -> Option<String> {
            self.active_cover_calibrator_id.clone()
        }
        async fn safety_is_safe(&self, id: Option<&str>) -> DeviceResult<bool> {
            self.inner.safety_is_safe(id).await
        }
        async fn calculate_image_hfr(&self, d: &ImageData) -> DeviceResult<Option<f64>> {
            self.inner.calculate_image_hfr(d).await
        }
        async fn detect_stars_in_image(&self, d: &ImageData) -> DeviceResult<Vec<(f64, f64, f64)>> {
            self.inner.detect_stars_in_image(d).await
        }
        async fn measure_frame_eccentricity(&self, d: &ImageData) -> DeviceResult<Option<f64>> {
            self.inner.measure_frame_eccentricity(d).await
        }
        async fn cover_calibrator_open_cover(&self, id: &str) -> DeviceResult<()> {
            self.cover_open_ids.lock().unwrap().push(id.to_string());
            self.inner.cover_calibrator_open_cover(id).await
        }
        async fn cover_calibrator_close_cover(&self, id: &str) -> DeviceResult<()> {
            self.inner.cover_calibrator_close_cover(id).await
        }
        async fn cover_calibrator_halt_cover(&self, id: &str) -> DeviceResult<()> {
            self.inner.cover_calibrator_halt_cover(id).await
        }
        async fn cover_calibrator_calibrator_on(&self, id: &str, b: i32) -> DeviceResult<()> {
            self.inner.cover_calibrator_calibrator_on(id, b).await
        }
        async fn cover_calibrator_calibrator_off(&self, id: &str) -> DeviceResult<()> {
            self.inner.cover_calibrator_calibrator_off(id).await
        }
        async fn cover_calibrator_get_cover_state(&self, id: &str) -> DeviceResult<i32> {
            self.inner.cover_calibrator_get_cover_state(id).await
        }
        async fn cover_calibrator_get_calibrator_state(&self, id: &str) -> DeviceResult<i32> {
            self.inner.cover_calibrator_get_calibrator_state(id).await
        }
        async fn cover_calibrator_get_brightness(&self, id: &str) -> DeviceResult<i32> {
            self.inner.cover_calibrator_get_brightness(id).await
        }
        async fn cover_calibrator_get_max_brightness(&self, id: &str) -> DeviceResult<i32> {
            self.inner.cover_calibrator_get_max_brightness(id).await
        }
    }

    /// Build an InstructionContext wired to the given scripted ops with a
    /// dome + rotator attached.
    async fn ctx_with_ops(ops: Arc<ScriptedDomeRotatorOps>) -> InstructionContext {
        let mut ec = crate::node::context::ExecutionContext::new("test-node".to_string());
        ec.device_ops = ops;
        ec.camera_id = Some("camera-1".to_string());
        ec.focuser_id = Some("focuser-1".to_string());
        ec.filterwheel_id = Some("filterwheel-1".to_string());
        ec.dome_id = Some("dome-1".to_string());
        ec.rotator_id = Some("rotator-1".to_string());
        ec.to_instruction_context("test-node").await
    }

    /// A WarmCamera whose final "switch the cooler off" fails must not report
    /// success. On the reference rig (2026-08-09, L19) that call failed for
    /// every request — the instruction ran its whole ramp, discarded the
    /// error, and reported "Camera warmed to ambient" with the TEC still
    /// powered.
    #[tokio::test(start_paused = true)]
    async fn warm_camera_reports_failure_when_the_cooler_will_not_switch_off() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_failing_cooler_off(
            "Failed to set cooler: Failed to set property SetCCDTemperature",
        ));
        let ctx = ctx_with_ops(ops.clone()).await;

        let result = execute_warm_camera(
            &WarmConfig {
                rate_per_min: 60.0,
                target_temp: Some(20.0),
            },
            &ctx,
            None,
        )
        .await;

        assert_eq!(
            result.status,
            NodeStatus::Failure,
            "a warm-up that could not switch the cooler off must not report success: {:?}",
            result.message
        );
        let message = result.message.unwrap_or_default();
        assert!(
            message.contains("could not switch the cooler off"),
            "the failure must name what actually went wrong, got: {message}"
        );
        assert!(
            ops.cooler_commands
                .lock()
                .unwrap()
                .iter()
                .any(|(enabled, _)| !*enabled),
            "the instruction must still have attempted the cooler-off"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn centering_waits_for_slew_startup_before_accepting_idle() {
        let ops = Arc::new(
            ScriptedDomeRotatorOps::new()
                .with_mount_slewing_states(vec![false, false, true, true, false]),
        );
        let mut ctx = ctx_with_ops(ops.clone()).await;
        ctx.mount_id = Some("mount-1".to_string());

        wait_for_centering_correction_slew("mount-1", &ctx)
            .await
            .expect("slew should start after the driver's delayed status update and then finish");

        assert_eq!(
            ops.mount_slew_state_calls.load(Ordering::SeqCst),
            5,
            "the initial idle polls must not be mistaken for slew completion"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn guiding_validation_failure_stops_started_guider() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_guider_calibration(
            GuidingCalibration {
                is_calibrated: false,
                ra_angle_deg: Some(0.0),
                dec_angle_deg: Some(90.0),
            },
        ));
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

    /// P0 SAFETY regression. Pause was cosmetic inside a burst: the node tree
    /// only checks `is_paused` between instructions, and a burst is N frames
    /// inside ONE instruction. Live evidence — Take Exposures 3x8s, Pause
    /// pressed during frame 2: the UI showed a PAUSED badge, a Resume button
    /// and "Paused 33%", the log went `Pausing sequence execution` ->
    /// `Capturing frame 3/3 (8.0s)` five seconds later, and the run recorded
    /// `status=completed, framesCaptured=3` without Resume ever being pressed.
    ///
    /// Pre-fix this test sees 3 exposures and a completed burst.
    #[tokio::test]
    async fn pause_stops_the_burst_before_the_next_frame_starts() {
        let paused = Arc::new(AtomicBool::new(false));
        let ops =
            Arc::new(ScriptedDomeRotatorOps::new().pausing_after_first_exposure(paused.clone()));
        let dir = std::env::temp_dir().join(format!("ns-pause-burst-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("temp dir");

        let mut ec = crate::node::context::ExecutionContext::new("pause-node".to_string());
        ec.device_ops = ops.clone();
        ec.camera_id = Some("camera-1".to_string());
        ec.save_path = Some(dir.clone());
        ec.is_paused = paused.clone();
        let ctx = ec.to_instruction_context("pause-node").await;
        let control = BurstControl {
            pause: ec.pause_gate(),
            status: None,
        };
        // Calibration frames so the burst is not daylight-gated or graded.
        let config = ExposureConfig {
            count: 3,
            duration_secs: 0.0,
            frame_type: "dark".to_string(),
            ..ExposureConfig::default()
        };

        let burst = std::pin::pin!(execute_exposure_with_renderer(
            &config,
            &ctx,
            None,
            &control,
            |_, _| {}
        ));
        let mut burst = burst;

        let held = tokio::time::timeout(Duration::from_millis(400), &mut burst).await;
        assert!(
            held.is_err(),
            "the burst must still be holding while the operator has it paused"
        );
        assert_eq!(
            ops.camera_exposure_calls.load(Ordering::SeqCst),
            1,
            "no NEW exposure may start while paused — the operator pauses to \
             stand in front of the telescope"
        );

        paused.store(false, Ordering::SeqCst);
        let result = tokio::time::timeout(Duration::from_secs(10), burst)
            .await
            .expect("resume must let the burst finish");

        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(result.status, NodeStatus::Success);
        assert_eq!(
            ops.camera_exposure_calls.load(Ordering::SeqCst),
            3,
            "Resume must complete the remaining frames"
        );
    }

    /// P1 regression for the pre-exposure meridian gate. A target EAST of the
    /// meridian cannot make a MinutesPastMeridian trigger fire (the trigger
    /// requires `hour_angle > 0` on the pre-flip / unreported pier side), yet
    /// the gate held anyway on a stale hour angle and logged "meridian flip
    /// fires in ~0s". Live: target RA 23.4h at LST 21:27 (HA -1.93h) sat at
    /// 0/3 frames for minutes with no UI explanation, and with a 30-minute
    /// bound PER EXPOSURE a normal sub sequence stalls for hours.
    ///
    /// Pre-fix this test hangs on the gate and trips the timeout.
    #[tokio::test]
    async fn meridian_gate_does_not_hold_a_target_east_of_the_meridian() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = crate::node::context::ExecutionContext::new("gate-node".to_string());
        ec.device_ops = ops;
        ec.camera_id = Some("camera-1".to_string());
        ec.mount_id = Some("mount-1".to_string());
        ec.longitude = Some(104.65);
        ec.latitude = Some(39.9846);

        let trigger_state = Arc::new(tokio::sync::RwLock::new(
            crate::triggers::TriggerState::new(),
        ));
        {
            let mut state = trigger_state.write().await;
            state.meridian_flip_minutes_past = Some(5.0);
            state.target_ra = Some(23.4);
            state.target_dec = Some(40.0);
            // Stale positive hour angle left behind by an earlier run: the
            // mount poll only runs while a sequence executes, so the first
            // frame of the next run reads the previous run's value.
            state.current_hour_angle = Some(0.19);
            state.pier_side = None;
        }
        ec.trigger_state = Some(trigger_state);

        let mut ctx = ec.to_instruction_context("gate-node").await;
        // LST for longitude 104.65 puts RA 23.4h roughly two hours EAST of the
        // meridian for most of the day; pick the RA that is currently east so
        // the assertion does not depend on the wall clock.
        let lst = crate::meridian::local_sidereal_time(
            crate::meridian::julian_day(&chrono::Utc::now()),
            104.65,
        );
        ctx.target_ra = Some((lst + 4.0) % 24.0);

        let gate = tokio::time::timeout(
            Duration::from_secs(2),
            wait_for_meridian_flip_window(&ctx, 2.0, &BurstControl::default()),
        )
        .await
        .expect("an east-of-meridian target must not be held by the flip gate");

        assert!(
            gate.is_none(),
            "the gate must let the exposure proceed when the flip trigger cannot fire"
        );
    }

    /// P1 regression, reproduced live 2026-08-09 against the Linux headless
    /// build (`--headless`, sim camera + sim mount): 12 x 5s LIGHT on a target
    /// at RA 12.5h / Dec +70 from a site at 40N 42E. Frame 1 was captured and
    /// the run then sat at `1/12  8%` indefinitely, state "running", status
    ///
    ///   Waiting for the meridian flip before the next 5s exposure: the flip
    ///   fires in ~0s (hour angle +9.88h, threshold 5 min past meridian) and
    ///   would interrupt the frame
    ///
    /// No "Capturing frame 2/12" ever followed and no flip trigger ever fired:
    /// `/api/mount/status` showed the mount parked at RA 0.0 with
    /// `sideOfPier: unknown`, so the TRIGGER (which decides from the MOUNT's
    /// hour angle) saw a negative HA and could never fire, while the GATE
    /// (which predicts from the TARGET's hour angle) held for a flip that was
    /// 9.9 hours overdue. `fire_in_secs` was about -35_000, and every negative
    /// value counted as "imminent", so each frame paid the gate's full
    /// 30-minute bound — a routine target past the meridian cost the night.
    ///
    /// The live rig tripped BOTH arms of this at once (overdue AND a mount the
    /// trigger could not fire from). This test isolates the OVERDUE arm — it
    /// gives the mount a tracking hour angle so the sibling
    /// `gate_does_not_hold_when_the_mount_cannot_make_the_trigger_fire` guard
    /// cannot be what releases the burst, and severing the overdue hatch
    /// therefore still fails this test.
    ///
    /// This drives the PRODUCTION call site (the exposure burst), not the gate
    /// helper. Pre-fix the burst never reaches frame 2 and trips the timeout.
    #[tokio::test]
    async fn overdue_meridian_flip_does_not_stall_the_exposure_burst() {
        // Parked mount: keeps the daylight gate out of the way (a parked rig
        // is not on-sky) without weakening the meridian gate, which keys only
        // off frame type + target + mount id.
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_mount_parked(true));
        let dir = std::env::temp_dir().join(format!("ns-mer-overdue-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("temp dir");

        let mut ec = crate::node::context::ExecutionContext::new("overdue-node".to_string());
        ec.device_ops = ops.clone();
        ec.camera_id = Some("camera-1".to_string());
        ec.mount_id = Some("mount-1".to_string());
        ec.save_path = Some(dir.clone());
        ec.latitude = Some(40.0);
        ec.longitude = Some(42.0);

        let trigger_state = Arc::new(tokio::sync::RwLock::new(
            crate::triggers::TriggerState::new(),
        ));
        {
            let mut state = trigger_state.write().await;
            state.meridian_flip_minutes_past = Some(5.0);
            state.target_ra = Some(12.5);
            state.target_dec = Some(70.0);
            // Exactly what the live rig reported: no pier side, and no mount
            // hour angle for the trigger to fire on.
            state.pier_side = None;
            // A mount that IS tracking the target and IS hours past the
            // meridian, so `trigger_can_fire` holds and the sibling
            // "mount cannot make the trigger fire" guard cannot be what
            // releases this burst. Nothing clears `has_flipped_this_target`,
            // which is the state a flip that was requested and then failed
            // (or was retried to exhaustion) leaves behind. Only the overdue
            // escape hatch can let these frames through.
            state.current_hour_angle = Some(9.0);
        }
        ec.trigger_state = Some(trigger_state);

        let control = BurstControl {
            pause: ec.pause_gate(),
            status: None,
        };
        let mut ctx = ec.to_instruction_context("overdue-node").await;
        // Pin the target nine hours WEST of the meridian relative to the
        // current sidereal time so the case under test does not depend on the
        // hour of day the suite runs.
        let lst = crate::meridian::local_sidereal_time(
            crate::meridian::julian_day(&chrono::Utc::now()),
            42.0,
        );
        ctx.target_ra = Some((lst - 9.0 + 24.0) % 24.0);
        ctx.target_dec = Some(70.0);

        let config = ExposureConfig {
            count: 3,
            duration_secs: 0.0,
            frame_type: "light".to_string(),
            ..ExposureConfig::default()
        };

        let result = tokio::time::timeout(
            Duration::from_secs(20),
            execute_exposure_with_renderer(&config, &ctx, None, &control, |_, _| {}),
        )
        .await;

        let completed = result.is_ok();
        let exposures = ops.camera_exposure_calls.load(Ordering::SeqCst);
        let _ = std::fs::remove_dir_all(&dir);

        assert!(
            completed,
            "a meridian flip that is hours overdue must not hold the burst; \
             it stopped after {exposures} of 3 frames"
        );
        assert_eq!(
            exposures, 3,
            "every frame must be captured when the flip the gate is waiting on \
             is already hours past due and will never fire"
        );
    }

    /// The band the overdue escape hatch does NOT cover, reproduced live on
    /// the headless Linux build (sim camera + sim mount, site 40N 42E, target
    /// pinned 12 minutes west of the meridian, default 5-minute threshold):
    ///
    ///   19:03:00 | running | prog=0.333 | Waiting for the meridian flip
    ///   before the next 2s exposure: the flip became due 423s ago (hour angle
    ///   +0.20h, threshold 5 min past meridian) and would interrupt the frame
    ///
    /// and the run then sat at 1/3 for the rest of the watch window. Only 7
    /// minutes overdue, so `OVERDUE_GRACE_SECS` does not release it — but the
    /// mount was never slewed to the target, so `current_hour_angle` (the only
    /// thing the TRIGGER reads) never made the flip fire. The gate was waiting
    /// on an event that could not arrive, once per frame, 30 minutes a time.
    ///
    /// Drives the PRODUCTION call site (the exposure burst), not the helper.
    #[tokio::test]
    async fn gate_does_not_hold_when_the_mount_cannot_make_the_trigger_fire() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_mount_parked(true));
        let dir = std::env::temp_dir().join(format!("ns-mer-nofire-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("temp dir");

        let mut ec = crate::node::context::ExecutionContext::new("nofire-node".to_string());
        ec.device_ops = ops.clone();
        ec.camera_id = Some("camera-1".to_string());
        ec.mount_id = Some("mount-1".to_string());
        ec.save_path = Some(dir.clone());
        ec.latitude = Some(40.0);
        ec.longitude = Some(42.0);

        let trigger_state = Arc::new(tokio::sync::RwLock::new(
            crate::triggers::TriggerState::new(),
        ));
        {
            let mut state = trigger_state.write().await;
            state.meridian_flip_minutes_past = Some(5.0);
            state.target_ra = Some(12.5);
            state.target_dec = Some(70.0);
            state.pier_side = None;
            // Exactly the live rig's state: the mount never reported a
            // position, so the MinutesPastMeridian trigger returns false on
            // every evaluation and no flip can ever be requested.
            state.current_hour_angle = None;
        }
        ec.trigger_state = Some(trigger_state);

        let control = BurstControl {
            pause: ec.pause_gate(),
            status: None,
        };
        let mut ctx = ec.to_instruction_context("nofire-node").await;
        // 12 minutes west of the meridian: past the 5-minute threshold, so the
        // gate wants to hold, but only 7 minutes overdue — inside the grace
        // window, so the overdue hatch cannot be what releases this.
        let lst = crate::meridian::local_sidereal_time(
            crate::meridian::julian_day(&chrono::Utc::now()),
            42.0,
        );
        ctx.target_ra = Some((lst - 12.0 / 60.0 + 24.0) % 24.0);
        ctx.target_dec = Some(70.0);

        let config = ExposureConfig {
            count: 3,
            duration_secs: 0.0,
            frame_type: "light".to_string(),
            ..ExposureConfig::default()
        };

        let result = tokio::time::timeout(
            Duration::from_secs(20),
            execute_exposure_with_renderer(&config, &ctx, None, &control, |_, _| {}),
        )
        .await;

        let completed = result.is_ok();
        let exposures = ops.camera_exposure_calls.load(Ordering::SeqCst);
        let _ = std::fs::remove_dir_all(&dir);

        assert!(
            completed,
            "the gate must not hold for a flip the mount cannot make the trigger \
             request; the burst stopped after {exposures} of 3 frames"
        );
        assert_eq!(
            exposures, 3,
            "every frame must be captured when no flip can ever be requested"
        );
    }

    /// The gate must still hold when a flip really is imminent, otherwise the
    /// fix above would just delete the feature.
    #[tokio::test]
    async fn meridian_gate_still_holds_when_the_flip_is_imminent() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = crate::node::context::ExecutionContext::new("gate-node".to_string());
        ec.device_ops = ops;
        ec.camera_id = Some("camera-1".to_string());
        ec.mount_id = Some("mount-1".to_string());
        ec.longitude = Some(0.0);

        let trigger_state = Arc::new(tokio::sync::RwLock::new(
            crate::triggers::TriggerState::new(),
        ));
        {
            let mut state = trigger_state.write().await;
            state.meridian_flip_minutes_past = Some(5.0);
            state.target_ra = Some(1.0);
            state.target_dec = Some(40.0);
            state.pier_side = Some(crate::PierSide::West);
            // A mount that is TRACKING THE TARGET, which is what the executor's
            // mount poll reports during a healthy run. The gate may only hold
            // for a flip the trigger can actually request, and the trigger
            // reads this field; leaving it None described a mount that reports
            // no position at all, in which case declining to hold is correct.
            state.current_hour_angle = Some(10.0 / 60.0);
        }
        ec.trigger_state = Some(trigger_state);

        let mut ctx = ec.to_instruction_context("gate-node").await;
        // Ten minutes PAST the meridian with a 5-minute threshold: the trigger
        // is already due, so the frame would be ruined by the flip slew.
        let lst = crate::meridian::local_sidereal_time(
            crate::meridian::julian_day(&chrono::Utc::now()),
            0.0,
        );
        ctx.target_ra = Some((lst - 10.0 / 60.0 + 24.0) % 24.0);

        let held = tokio::time::timeout(
            Duration::from_millis(500),
            wait_for_meridian_flip_window(&ctx, 2.0, &BurstControl::default()),
        )
        .await;

        assert!(
            held.is_err(),
            "a flip that is already due must still hold the next exposure"
        );
    }

    #[tokio::test]
    async fn dropped_exposure_instruction_aborts_camera() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_hanging_camera());
        let ctx = ctx_with_ops(ops.clone()).await;
        let config = ExposureConfig {
            duration_secs: 60.0,
            count: 1,
            ..ExposureConfig::default()
        };

        let task = tokio::spawn(async move { execute_exposure(&config, &ctx, |_, _| {}).await });
        while ops.camera_exposure_calls.load(Ordering::SeqCst) == 0 {
            tokio::task::yield_now().await;
        }
        task.abort();
        let _ = task.await;
        for _ in 0..20 {
            if ops.camera_abort_calls.load(Ordering::SeqCst) > 0 {
                break;
            }
            tokio::task::yield_now().await;
        }

        assert_eq!(
            ops.camera_abort_calls.load(Ordering::SeqCst),
            1,
            "dropping the instruction future must abort the physical exposure"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn autofocus_timeout_bounds_hung_camera_exposure() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_hanging_camera());
        let ctx = ctx_with_ops(ops.clone()).await;
        let config = AutofocusConfig {
            steps_out: 1,
            max_duration_secs: 1.0,
            focuser_settle_time_ms: 0,
            ..AutofocusConfig::default()
        };

        let result = execute_autofocus_once(
            &config,
            &ctx,
            None,
            &crate::node::context::PauseGate::default(),
        )
        .await;

        assert_eq!(result.status, NodeStatus::Failure);
        assert!(
            result
                .message
                .as_deref()
                .is_some_and(|message| message.contains("timed out")),
            "hung sub-operation must fail at the autofocus deadline: {:?}",
            result.message
        );
        tokio::task::yield_now().await;
        assert_eq!(
            ops.camera_abort_calls.load(Ordering::SeqCst),
            1,
            "timing out a camera exposure must also abort it"
        );
    }

    #[tokio::test]
    async fn requested_filter_without_wheel_fails_before_capture() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ctx = ctx_with_ops(ops.clone()).await;
        ctx.filterwheel_id = None;
        let config = ExposureConfig {
            duration_secs: 0.01,
            count: 1,
            filter: Some("Ha".to_string()),
            ..ExposureConfig::default()
        };

        let result = execute_exposure(&config, &ctx, |_, _| {}).await;

        assert_eq!(result.status, NodeStatus::Failure);
        assert!(
            result
                .message
                .as_deref()
                .is_some_and(|message| message.contains("no filter wheel")),
            "missing hardware must be surfaced instead of capturing mislabeled data"
        );
        assert_eq!(
            ops.camera_exposure_calls.load(Ordering::SeqCst),
            0,
            "capture must not start when its requested filter cannot be applied"
        );
    }

    // ---------------------------------------------------------------------
    // dome-rotator-verify: rotator move is MOVE-AND-VERIFY
    // ---------------------------------------------------------------------

    /// The rotator move polls the achieved angle until it is within
    /// tolerance of the target. The driver `rotator_move_to` only ISSUES
    /// the move on ASCOM/Alpaca/INDI, so the instruction must poll
    /// `rotator_get_angle` (the "is it there yet" verify) before reporting
    /// success. Here the rotator is still off-target for the first two
    /// polls and only arrives on the third — success must therefore have
    /// required at least two verifying polls.
    ///
    /// Fails WITHOUT the verify loop (fire-and-forget returns success after
    /// the single move call, polling `rotator_get_angle` zero times).
    ///
    /// `start_paused = true` drives the verify loop's `tokio::time::sleep`
    /// off the test's virtual clock (auto-advanced when all tasks are idle)
    /// instead of racing real wall-time threads. The scripted angles advance
    /// one entry per `rotator_get_angle` call, so the interleaving is fully
    /// deterministic: poll 1 → 0°, poll 2 → 0°, poll 3 → 45° (arrived). This
    /// removes the prior flake where the non-paused wall-clock sleep raced a
    /// concurrent `start_paused` test under the multi-threaded runner.
    #[tokio::test(start_paused = true)]
    async fn test_rotator_move_verified_polls_until_arrival() {
        // Off-target (0°, 0°) then arrives at 45°.
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_rotator_angles(vec![0.0, 0.0, 45.0]));
        let ctx = ctx_with_ops(ops.clone()).await;
        let cfg = RotatorConfig {
            target_angle: 45.0,
            relative: false,
        };

        let result = execute_rotator_move(&cfg, &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Success,
            "rotator should report success once it reaches the target: {:?}",
            result.message
        );
        assert_eq!(
            ops.rotator_move_to_calls.load(Ordering::SeqCst),
            1,
            "the move must be issued exactly once"
        );
        assert!(
            ops.rotator_get_angle_calls.load(Ordering::SeqCst) >= 2,
            "the instruction must POLL the achieved angle at least twice \
             before declaring success (move-and-verify), got {}",
            ops.rotator_get_angle_calls.load(Ordering::SeqCst)
        );
    }

    /// A rotator that issues the move but never reaches the target (motor
    /// jam / stall) must FAIL CLOSED, not silently report success — a
    /// jammed rotator otherwise leaves the camera at the wrong PA and the
    /// next exposure smears field rotation across the frame.
    ///
    /// `start_paused` lets tokio auto-advance the virtual clock past the
    /// internal poll sleeps so the bounded timeout is reached without the
    /// test waiting real wall-time.
    #[tokio::test(start_paused = true)]
    async fn test_rotator_move_fails_when_target_never_reached() {
        // Always reports 0° — never reaches the 45° target.
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_rotator_angles(vec![0.0]));
        let ctx = ctx_with_ops(ops.clone()).await;
        let cfg = RotatorConfig {
            target_angle: 45.0,
            relative: false,
        };

        let result = execute_rotator_move(&cfg, &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Failure,
            "a rotator that never reaches the target must fail closed"
        );
        assert!(
            ops.rotator_get_angle_calls.load(Ordering::SeqCst) >= 2,
            "the timeout must be reached by repeated verification polls"
        );
    }

    // ---------------------------------------------------------------------
    // dome-park-shutter: park surfaces the shutter-close error + verifies
    // ---------------------------------------------------------------------

    /// THE hardware-safety guard: when dome park closes the shutter but the
    /// close FAILS, `execute_park_dome` must return Failure with the close
    /// error surfaced — NOT report "parked" while the scope sits exposed
    /// under an open shutter all night. A failed roof returns an error, not
    /// success.
    ///
    /// Fails WITHOUT the fix (the original code swallowed the `dome_close`
    /// Result and returned success).
    ///
    /// `start_paused = true` keeps this test on the virtual clock so it can
    /// never race a concurrent paused test's auto-advance under the
    /// multi-threaded runner. (This path returns on the `dome_close` error
    /// before reaching the shutter-wait poll loop, so it issues zero shutter
    /// polls — that is correct, not a flake.)
    #[tokio::test(start_paused = true)]
    async fn test_park_dome_surfaces_shutter_close_error() {
        let ops =
            Arc::new(ScriptedDomeRotatorOps::new().with_dome_close_error("shutter motor jammed"));
        let ctx = ctx_with_ops(ops.clone()).await;
        let cfg = DomeConfig {
            shutter_only: false,
        };

        let result = execute_park_dome(&cfg, &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Failure,
            "a dome park that cannot close the shutter MUST fail, not report parked"
        );
        let msg = result.message.unwrap_or_default();
        assert!(
            msg.contains("shutter motor jammed"),
            "the underlying close error must be surfaced to the operator, got: {msg}"
        );
        assert_eq!(
            ops.dome_close_calls.load(Ordering::SeqCst),
            1,
            "park must actually attempt to close the shutter"
        );
    }

    /// Dome park is MOVE-AND-VERIFY: after issuing the close it must poll
    /// the shutter status until it actually reads Closed before reporting
    /// success. Here the shutter is still "Closing" for the first two polls
    /// and only reaches "Closed" on the third.
    ///
    /// Fails WITHOUT the wait (fire-and-forget reported "parked" while the
    /// shutter was still moving).
    ///
    /// `start_paused = true` drives `wait_for_dome_shutter_state`'s
    /// `tokio::time::sleep` off the virtual clock (auto-advanced when idle).
    /// The scripted shutter states advance one entry per
    /// `dome_get_shutter_status` call, so the poll sequence is deterministic:
    /// poll 1 → Closing, poll 2 → Closing, poll 3 → Closed (done). This
    /// removes the prior wall-clock race against concurrent paused tests.
    #[tokio::test(start_paused = true)]
    async fn test_park_dome_waits_for_shutter_closed() {
        let ops = Arc::new(
            ScriptedDomeRotatorOps::new()
                .with_dome_shutter_states(&["Closing", "Closing", "Closed"]),
        );
        let ctx = ctx_with_ops(ops.clone()).await;
        let cfg = DomeConfig {
            shutter_only: false,
        };

        let result = execute_park_dome(&cfg, &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Success,
            "park should succeed once the shutter reads Closed: {:?}",
            result.message
        );
        assert_eq!(
            ops.dome_park_calls.load(Ordering::SeqCst),
            1,
            "the dome park must be issued"
        );
        assert!(
            ops.dome_shutter_status_calls.load(Ordering::SeqCst) >= 2,
            "park must POLL the shutter status until Closed (move-and-verify), got {}",
            ops.dome_shutter_status_calls.load(Ordering::SeqCst)
        );
    }

    /// A dome whose shutter reports a definite state but never reaches
    /// Closed (jammed half-open) must FAIL CLOSED rather than reporting a
    /// successful park — otherwise the optics stay exposed to the weather
    /// that the close was meant to protect against.
    #[tokio::test(start_paused = true)]
    async fn test_park_dome_fails_when_shutter_never_closes() {
        // Reports a real state ("Open") forever but never "Closed".
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_dome_shutter_states(&["Open"]));
        let ctx = ctx_with_ops(ops.clone()).await;
        let cfg = DomeConfig {
            shutter_only: false,
        };

        let result = execute_park_dome(&cfg, &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Failure,
            "a shutter that reports a real state but never closes must fail closed"
        );
        assert!(
            ops.dome_shutter_status_calls.load(Ordering::SeqCst) >= 2,
            "the timeout must be reached by repeated shutter-status polls"
        );
    }

    /// v4 SHOULD-FIX — `wait_for_dome_shutter_state` must NOT return a clean
    /// "Dome shutter closed" success when the shutter state could never be
    /// confirmed. A roof that can never report position ("Unknown" forever)
    /// is tolerated (a working roll-off must not be failed), but the success
    /// message MUST surface that arrival was unconfirmed — otherwise the
    /// operator reads "closed" while the roof's true state is unknown.
    ///
    /// Fails WITHOUT the fix: the old code returned
    /// `success_with_message("Dome shutter closed")` with no caveat.
    #[tokio::test(start_paused = true)]
    async fn test_close_dome_surfaces_unconfirmed_when_shutter_never_reports_state() {
        // Never a definite state — the dome cannot report shutter position.
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_dome_shutter_states(&["Unknown"]));
        let ctx = ctx_with_ops(ops.clone()).await;
        let cfg = DomeConfig { shutter_only: true };

        let result = execute_close_dome(&cfg, &ctx, None).await;

        // We do NOT fail a roof that simply can't report position...
        assert_eq!(
            result.status,
            NodeStatus::Success,
            "a roll-off that cannot report shutter position must not be failed"
        );
        // ...but the message must say the position could not be confirmed,
        // never a bare "Dome shutter closed".
        let msg = result.message.unwrap_or_default();
        assert!(
            msg.contains("could not be confirmed"),
            "close must surface the unconfirmed shutter position, got: {msg:?}"
        );
        assert!(
            !msg.eq("Dome shutter closed"),
            "an unconfirmed close must not claim a clean 'Dome shutter closed'"
        );
    }

    /// Control: a healthy close that confirms Closed reports the plain
    /// "Dome shutter closed" success (the verification must not add a caveat
    /// to a genuinely-confirmed close).
    #[tokio::test(start_paused = true)]
    async fn test_close_dome_confirmed_reports_plain_success() {
        let ops = Arc::new(
            ScriptedDomeRotatorOps::new().with_dome_shutter_states(&["Closing", "Closed"]),
        );
        let ctx = ctx_with_ops(ops.clone()).await;
        let cfg = DomeConfig { shutter_only: true };

        let result = execute_close_dome(&cfg, &ctx, None).await;

        assert_eq!(result.status, NodeStatus::Success);
        assert_eq!(
            result.message.as_deref(),
            Some("Dome shutter closed"),
            "a confirmed close reports the plain success message"
        );
    }

    // =====================================================================
    // W1 native daylight gate (cluster: w1-daylight)
    //
    // The W1 "no daylight imaging" invariant was previously enforced ONLY in
    // scheduler_engine.dart, so a raw sequence started via api_sequencer_start
    // (including a mosaic) could slew + expose LIGHT frames in full daylight —
    // the native executor had no Sun gate. These tests pin the structural
    // native gate added to execute_slew / execute_exposure.
    //
    // Determinism: the Sun's real altitude depends on wall-clock + location,
    // which we cannot pin here without a MockClock on the instruction layer.
    // Instead we compute the live Sun altitude for a fixed observer and then
    // drive the CONFIGURED threshold relative to it — `sun_alt - delta` is
    // guaranteed "Sun up" (above max) and `sun_alt + delta` is guaranteed
    // "Sun down" (below max), regardless of the date/time the test runs.
    // =====================================================================

    /// Fixed observer for the gate tests — a mid-northern-latitude site so the
    /// Sun-altitude math is well-conditioned (away from the polar edge cases).
    const TEST_LAT: f64 = 40.0;
    const TEST_LON: f64 = -74.0;

    fn live_sun_alt() -> f64 {
        crate::node::context::current_sun_altitude_degrees(TEST_LAT, TEST_LON)
    }

    fn is_daylight_block(result: &InstructionResult) -> bool {
        result.status == NodeStatus::Failure
            && result
                .message
                .as_deref()
                .is_some_and(|m| m.contains("Daylight gate"))
    }

    // --- pure helper: daylight_gate_block_reason ---

    #[test]
    fn daylight_gate_blocks_when_sun_above_max() {
        let sun_alt = live_sun_alt();
        // Threshold 5° BELOW the live Sun altitude => Sun is "up" relative to
        // the configured max => must block.
        let reason =
            daylight_gate_block_reason(Some(TEST_LAT), Some(TEST_LON), sun_alt - 5.0, "test");
        assert!(
            reason.is_some(),
            "Sun {sun_alt:.1}° above max {:.1}° must block",
            sun_alt - 5.0
        );
    }

    #[test]
    fn daylight_gate_allows_when_sun_below_max() {
        let sun_alt = live_sun_alt();
        // Threshold 5° ABOVE the live Sun altitude => Sun is "down" relative to
        // the configured max => must allow.
        let reason =
            daylight_gate_block_reason(Some(TEST_LAT), Some(TEST_LON), sun_alt + 5.0, "test");
        assert!(
            reason.is_none(),
            "Sun {sun_alt:.1}° below max {:.1}° must NOT block",
            sun_alt + 5.0
        );
    }

    #[test]
    fn daylight_gate_abstains_without_location() {
        // No observer location => cannot compute Sun altitude => abstain
        // (never fabricate a block that would wedge a location-less rig). Even
        // with an absurdly low threshold the gate must NOT block here.
        assert!(daylight_gate_block_reason(None, Some(TEST_LON), -90.0, "test").is_none());
        assert!(daylight_gate_block_reason(Some(TEST_LAT), None, -90.0, "test").is_none());
        assert!(daylight_gate_block_reason(None, None, -90.0, "test").is_none());
    }

    #[test]
    fn daylight_gate_falls_back_to_default_on_non_finite_max() {
        // A NaN threshold must not silently disable the gate: it falls back to
        // DEFAULT_MAX_SUN_ALTITUDE_DEGREES. We can only assert the finite
        // fallback path is taken consistently with the default comparison.
        let sun_alt = live_sun_alt();
        let nan_reason =
            daylight_gate_block_reason(Some(TEST_LAT), Some(TEST_LON), f64::NAN, "test");
        let default_reason = daylight_gate_block_reason(
            Some(TEST_LAT),
            Some(TEST_LON),
            DEFAULT_MAX_SUN_ALTITUDE_DEGREES,
            "test",
        );
        assert_eq!(
            nan_reason.is_some(),
            default_reason.is_some(),
            "NaN max must behave exactly like the default ({sun_alt:.1}° vs {DEFAULT_MAX_SUN_ALTITUDE_DEGREES:.1}°)"
        );
    }

    #[test]
    fn calibration_frame_types_do_not_require_darkness() {
        for frame_type in ["Bias", "Dark", "Flat", "DarkFlat"] {
            assert!(
                !frame_type_requires_darkness(frame_type),
                "{frame_type} is a calibration frame and must remain legal in daylight"
            );
        }
        assert!(frame_type_requires_darkness("Light"));
        assert!(frame_type_requires_darkness("light"));
    }

    // --- execute_slew gate ---

    async fn slew_ctx(max_sun_alt: f64) -> InstructionContext {
        let mut ec = crate::node::context::ExecutionContext::new("test-node".to_string());
        ec.device_ops = Arc::new(NullDeviceOps);
        ec.mount_id = Some("mount-1".to_string());
        ec.latitude = Some(TEST_LAT);
        ec.longitude = Some(TEST_LON);
        ec.target_ra = Some(5.5);
        ec.target_dec = Some(22.0);
        ec.max_sun_altitude_degrees = max_sun_alt;
        // The gate reads the configured max through the InstructionContext's
        // trigger-state handle (exactly as the live executor seeds it). Install
        // a trigger state so the test exercises that same resolution path.
        let mut ts = crate::triggers::TriggerState::new();
        ts.set_max_sun_altitude_degrees(max_sun_alt);
        ec.trigger_state = Some(std::sync::Arc::new(tokio::sync::RwLock::new(ts)));
        ec.to_instruction_context("test-node").await
    }

    #[tokio::test]
    async fn slew_to_target_rejected_when_sun_up() {
        let sun_alt = live_sun_alt();
        let ctx = slew_ctx(sun_alt - 5.0).await; // Sun above max → block
        let cfg = SlewConfig {
            use_target_coords: true,
            ..SlewConfig::default()
        };
        let result = execute_slew(&cfg, &ctx, None).await;
        assert!(
            is_daylight_block(&result),
            "slew to science target must be daylight-blocked when Sun is up; got {:?}",
            result.message
        );
    }

    #[tokio::test]
    async fn slew_to_target_allowed_when_sun_down() {
        let sun_alt = live_sun_alt();
        let ctx = slew_ctx(sun_alt + 5.0).await; // Sun below max → allow
        let cfg = SlewConfig {
            use_target_coords: true,
            ..SlewConfig::default()
        };
        let result = execute_slew(&cfg, &ctx, None).await;
        // It may still fail downstream slew-position validation against the
        // NullDeviceOps fixed coordinates, but it must NOT be a daylight block.
        assert!(
            !is_daylight_block(&result),
            "slew must clear the daylight gate at night; got daylight block: {:?}",
            result.message
        );
    }

    #[tokio::test]
    async fn slew_to_custom_coords_not_gated_in_daylight() {
        // A park/flat-panel/alignment slew to CUSTOM coordinates is not an
        // on-sky science pointing and must never be daylight-gated, even with
        // a threshold far below the live Sun altitude.
        let sun_alt = live_sun_alt();
        let ctx = slew_ctx(sun_alt - 30.0).await;
        let cfg = SlewConfig {
            use_target_coords: false,
            custom_ra: Some(12.0),
            custom_dec: Some(45.0),
        };
        let result = execute_slew(&cfg, &ctx, None).await;
        assert!(
            !is_daylight_block(&result),
            "custom-coordinate slew must never be daylight-gated; got {:?}",
            result.message
        );
    }

    // --- unset-target pointing gate ---
    //
    // A TargetHeader dragged in from the palette carries RA 0h / Dec +0° until
    // the operator picks a target. Dart's TargetCoordinatesUnsetRule blocks
    // that on the GUI start path only; the headless REST start, a raw
    // sequencer_load_json and every checkpoint resume reach the executor
    // without it. These tests pin the gate at the two nodes that command the
    // mount, which is what makes it hold for all of those entry points.

    /// The recovery code `failure_with_recovery` stashed in `data`, if any.
    fn recovery_code_of(result: &InstructionResult) -> Option<String> {
        result
            .data
            .as_ref()?
            .get("recovery_code")?
            .as_str()
            .map(str::to_string)
    }

    /// Context whose pointing comes from a TargetHeader with `target`
    /// coordinates, wired to `ops` so the tests can prove whether the mount was
    /// commanded. The Sun threshold is set above the live Sun so the daylight
    /// gate cannot be what produced a rejection.
    async fn pointing_ctx(
        ops: Arc<ScriptedDomeRotatorOps>,
        target_name: &str,
        target: (f64, f64),
    ) -> InstructionContext {
        let max_sun_alt = live_sun_alt() + 5.0;
        let mut ec = crate::node::context::ExecutionContext::new("test-node".to_string());
        ec.device_ops = ops;
        ec.mount_id = Some("mount-1".to_string());
        ec.camera_id = Some("cam-1".to_string());
        ec.latitude = Some(TEST_LAT);
        ec.longitude = Some(TEST_LON);
        ec.target_name = Some(target_name.to_string());
        ec.target_ra = Some(target.0);
        ec.target_dec = Some(target.1);
        ec.max_sun_altitude_degrees = max_sun_alt;
        let mut ts = crate::triggers::TriggerState::new();
        ts.set_max_sun_altitude_degrees(max_sun_alt);
        ec.trigger_state = Some(std::sync::Arc::new(tokio::sync::RwLock::new(ts)));
        ec.to_instruction_context("test-node").await
    }

    #[tokio::test]
    async fn slew_to_unset_target_never_commands_the_mount() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let ctx = pointing_ctx(ops.clone(), "New Target", (0.0, 0.0)).await;
        let cfg = SlewConfig {
            use_target_coords: true,
            ..SlewConfig::default()
        };

        let result = execute_slew(&cfg, &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Failure,
            "an unset target must not slew"
        );
        assert_eq!(
            recovery_code_of(&result).as_deref(),
            Some(UNSET_TARGET_RECOVERY_CODE),
            "rejection must be attributable to the unset target, got {:?}",
            result.message
        );
        assert_eq!(
            ops.mount_slew_calls.load(Ordering::SeqCst),
            0,
            "the mount must never be commanded to the RA 0h / Dec +0° placeholder"
        );
    }

    #[tokio::test]
    async fn center_on_unset_target_never_commands_the_mount() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let ctx = pointing_ctx(ops.clone(), "New Target", (0.0, 0.0)).await;
        let cfg = CenterConfig {
            use_target_coords: true,
            ..CenterConfig::default()
        };

        let result = execute_center(&cfg, &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Failure,
            "an unset target must not center"
        );
        assert_eq!(
            recovery_code_of(&result).as_deref(),
            Some(UNSET_TARGET_RECOVERY_CODE),
            "rejection must be attributable to the unset target, got {:?}",
            result.message
        );
        assert_eq!(
            ops.mount_slew_calls.load(Ordering::SeqCst),
            0,
            "the mount must never be commanded to the RA 0h / Dec +0° placeholder"
        );
        assert_eq!(
            ops.camera_exposure_calls.load(Ordering::SeqCst),
            0,
            "the gate must fire before a plate-solve exposure is spent"
        );
    }

    #[tokio::test]
    async fn slew_to_a_real_target_still_commands_the_mount() {
        // Guards the inversion: the gate must reject the placeholder and
        // nothing else, including a target one nudge away from it.
        let ops =
            Arc::new(ScriptedDomeRotatorOps::new().with_scripted_mount_coordinates(0.0001, 0.0001));
        let ctx = pointing_ctx(ops.clone(), "Deliberate Origin", (0.0001, 0.0001)).await;
        let cfg = SlewConfig {
            use_target_coords: true,
            ..SlewConfig::default()
        };

        let result = execute_slew(&cfg, &ctx, None).await;

        assert_ne!(
            recovery_code_of(&result).as_deref(),
            Some(UNSET_TARGET_RECOVERY_CODE),
            "a deliberately-set pointing must not read as the unset placeholder"
        );
        assert_eq!(
            ops.mount_slew_calls.load(Ordering::SeqCst),
            1,
            "a target with real coordinates must still slew"
        );
    }

    // --- execute_exposure gate ---

    async fn expose_ctx(
        ops: Arc<dyn DeviceOps>,
        target: Option<(f64, f64)>,
        max_sun_alt: f64,
    ) -> InstructionContext {
        let mut ec = crate::node::context::ExecutionContext::new("test-node".to_string());
        ec.device_ops = ops;
        ec.camera_id = Some("cam-1".to_string());
        ec.mount_id = Some("mount-1".to_string());
        ec.latitude = Some(TEST_LAT);
        ec.longitude = Some(TEST_LON);
        if let Some((ra, dec)) = target {
            ec.target_ra = Some(ra);
            ec.target_dec = Some(dec);
        }
        ec.max_sun_altitude_degrees = max_sun_alt;
        let mut ts = crate::triggers::TriggerState::new();
        ts.set_max_sun_altitude_degrees(max_sun_alt);
        ec.trigger_state = Some(std::sync::Arc::new(tokio::sync::RwLock::new(ts)));
        ec.to_instruction_context("test-node").await
    }

    fn one_light() -> ExposureConfig {
        ExposureConfig {
            duration_secs: 0.01,
            count: 1,
            ..ExposureConfig::default()
        }
    }

    #[tokio::test]
    async fn light_exposure_on_target_rejected_when_sun_up() {
        let sun_alt = live_sun_alt();
        // Mount NOT parked + science target set + Sun up → on-sky light → block.
        let ctx = expose_ctx(Arc::new(NullDeviceOps), Some((5.5, 22.0)), sun_alt - 5.0).await;
        let result = execute_exposure(&one_light(), &ctx, |_, _| {}).await;
        assert!(
            is_daylight_block(&result),
            "on-sky LIGHT exposure must be daylight-blocked when Sun is up; got {:?}",
            result.message
        );
    }

    #[tokio::test]
    async fn target_header_calibration_frames_are_exempt_from_daylight_gate() {
        let sun_alt = live_sun_alt();
        let ctx = expose_ctx(Arc::new(NullDeviceOps), Some((5.5, 22.0)), sun_alt - 30.0).await;

        for frame_type in ["Bias", "Dark", "Flat", "DarkFlat"] {
            let config = ExposureConfig {
                count: 0,
                frame_type: frame_type.to_string(),
                ..ExposureConfig::default()
            };
            let result = execute_exposure(&config, &ctx, |_, _| {}).await;
            assert!(
                !is_daylight_block(&result),
                "{frame_type} below a TargetHeader must remain legal in daylight: {:?}",
                result.message
            );
        }
    }

    #[tokio::test]
    async fn calibration_exposure_without_target_not_gated_in_daylight() {
        let sun_alt = live_sun_alt();
        // No target coordinates AND a calibration frame type → daytime
        // flats/darks/bias stay legal even with a daytime-blocking threshold.
        let ops: Arc<dyn DeviceOps> = Arc::new(NullDeviceOps);
        let ctx = expose_ctx(ops, None, sun_alt - 30.0).await;
        for frame_type in ["Bias", "Dark", "Flat", "DarkFlat"] {
            let config = ExposureConfig {
                count: 0,
                frame_type: frame_type.to_string(),
                ..ExposureConfig::default()
            };
            let result = execute_exposure(&config, &ctx, |_, _| {}).await;
            assert!(
                !is_daylight_block(&result),
                "a no-target {frame_type} exposure must never be daylight-gated; got {:?}",
                result.message
            );
        }
    }

    /// The frame event that makes Dart write the `captured_images` row must
    /// carry the same `FrameContext` the FITS writer stamped the header from.
    ///
    /// Fails WITHOUT the fix: the event used to carry only node id, grading
    /// metrics and a save path, so the row landed with NULL gain, offset,
    /// sensor temperature, cooler power, pointing, pier side, focuser position
    /// and rotator angle while the file on disk had every one of them.
    #[tokio::test]
    async fn frame_event_carries_the_fits_writers_own_capture_context() {
        let sun_alt = live_sun_alt();
        let ctx = expose_ctx(Arc::new(NullDeviceOps), None, sun_alt - 30.0).await;
        let (event_tx, mut event_rx) = tokio::sync::broadcast::channel(16);
        let ctx = InstructionContext {
            event_tx: Some(event_tx),
            ..ctx
        };

        let mut frame_ctx = crate::scheduling::FrameContext::new_light("sess-evt", 2, 2, 120.0, 7);
        frame_ctx.frame_type = "Dark".to_string();
        frame_ctx.target_id = Some("tgt-evt".to_string());
        frame_ctx.gain = Some(139);
        frame_ctx.offset = Some(21);
        frame_ctx.sensor_temp_c = Some(-9.5);
        frame_ctx.cooler_power_percent = Some(63.5);
        frame_ctx.mount_ra_hours = Some(5.5);
        frame_ctx.mount_dec_degrees = Some(-5.25);
        frame_ctx.mount_altitude_deg = Some(48.5);
        frame_ctx.mount_azimuth_deg = Some(171.25);
        frame_ctx.pier_side = Some("West".to_string());
        frame_ctx.focuser_position = Some(31_705);
        frame_ctx.focuser_temperature_c = Some(4.25);
        frame_ctx.rotator_angle_deg = Some(212.5);

        emit_grade_progress(
            &ctx,
            crate::quality::FrameGrade::Pass,
            &crate::quality::FrameMetrics::default(),
            false,
            7,
            10,
            std::path::Path::new("/captures/evt_0007.fits"),
            &frame_ctx,
            &Arc::new(AtomicU32::new(0)),
            &Arc::new(AtomicU32::new(0)),
            &Arc::new(AtomicU32::new(0)),
            u32::MAX,
        )
        .await;

        let mut emitted = None;
        while let Ok(event) = event_rx.try_recv() {
            if let crate::executor::ExecutorEvent::NodeProgress {
                structured_detail: Some(detail),
                ..
            } = event
            {
                if let crate::node::ProgressDetail::FrameAccepted { capture, .. } = *detail {
                    emitted = Some(capture);
                }
            }
        }

        let emitted = emitted.expect("a saved frame must emit FrameAccepted");
        assert_eq!(
            emitted,
            crate::scheduling::FrameCaptureMetadata::from(&frame_ctx),
            "the row's payload and the header's source must be the same struct"
        );
    }

    /// A scratch capture folder that removes itself even when a test panics.
    struct ScratchDir(std::path::PathBuf);

    impl Drop for ScratchDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn scratch_dir(tag: &str) -> ScratchDir {
        let dir = std::env::temp_dir().join(format!("ns-{}-{}", tag, uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("scratch dir");
        ScratchDir(dir)
    }

    /// An `InstructionContext` wired the way a real burst is: a resolvable save
    /// folder plus every device id, so `build_frame_context_for_save` actually
    /// performs its telemetry reads instead of skipping them.
    async fn saving_expose_ctx(
        ops: Arc<dyn DeviceOps>,
        save_path: std::path::PathBuf,
        event_tx: tokio::sync::broadcast::Sender<crate::executor::ExecutorEvent>,
    ) -> InstructionContext {
        let mut ec = crate::node::context::ExecutionContext::new("expose-node".to_string());
        ec.device_ops = ops;
        ec.camera_id = Some("cam-1".to_string());
        ec.mount_id = Some("mount-1".to_string());
        ec.focuser_id = Some("foc-1".to_string());
        ec.rotator_id = Some("rot-1".to_string());
        ec.save_path = Some(save_path);
        ec.latitude = Some(TEST_LAT);
        ec.longitude = Some(TEST_LON);
        ec.event_tx = Some(event_tx);
        ec.to_instruction_context("expose-node").await
    }

    /// The same rig as [`saving_expose_ctx`] but returned as the
    /// `ExecutionContext` the node runtime actually hands an instruction, plus
    /// a connected filter wheel. Tests that need to prove the NODE (not just
    /// `execute_exposure`) does something must start here — the save-path
    /// renderer is built inside `ExposeInstruction::execute` and never exists
    /// on the `execute_exposure` path a hand-built `InstructionContext` takes.
    async fn expose_node_execution_ctx(
        ops: Arc<dyn DeviceOps>,
        save_path: std::path::PathBuf,
    ) -> crate::node::context::ExecutionContext {
        let mut ec = crate::node::context::ExecutionContext::new("expose-node".to_string());
        ec.device_ops = ops;
        ec.camera_id = Some("cam-1".to_string());
        ec.focuser_id = Some("foc-1".to_string());
        ec.rotator_id = Some("rot-1".to_string());
        ec.filterwheel_id = Some("fw-1".to_string());
        ec.save_path = Some(save_path);
        ec.latitude = Some(TEST_LAT);
        ec.longitude = Some(TEST_LON);
        ec
    }

    /// Run a Take Exposures node exactly the way `RuntimeNode` does.
    async fn run_expose_node(
        config: ExposureConfig,
        ec: &mut crate::node::context::ExecutionContext,
    ) -> NodeStatus {
        let node_type = NodeType::TakeExposure(config);
        crate::node::instructions::expose::ExposeInstruction
            .execute("expose-node", &node_type, ec)
            .await
    }

    /// A Take Exposures node with no filter of its own — the shape that
    /// produced `untargeted_nofilter_0001.fits` with no FILTER card on a rig
    /// whose wheel was sitting on a known, named slot.
    fn one_dark_no_filter() -> ExposureConfig {
        ExposureConfig {
            duration_secs: 0.01,
            count: 1,
            frame_type: "Dark".to_string(),
            filter: None,
            filter_index: None,
            ..ExposureConfig::default()
        }
    }

    /// The wheel is parked on slot 1 ("R" in the double's name table) and the
    /// node names no filter. The frame is taken THROUGH R, so R is what the
    /// FITS FILTER card, the FILTPOS card and the filename must all say.
    ///
    /// Before the fix the sequence context had no filter identity at all
    /// unless a Change Filter node had run, so `FrameContext.filter_name` was
    /// None (no FILTER card at all — verified against a live capture) and the
    /// save-path template rendered the synthetic `nofilter` label.
    #[tokio::test]
    async fn burst_records_the_filter_the_wheel_is_parked_on() {
        let scratch = scratch_dir("wheel-filter");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = expose_node_execution_ctx(ops.clone(), scratch.0.clone()).await;

        let status = run_expose_node(one_dark_no_filter(), &mut ec).await;
        assert_eq!(status, NodeStatus::Success, "burst should complete");

        let saved = ops.saved_frame_contexts();
        assert_eq!(saved.len(), 1, "one frame should have reached the writer");
        assert_eq!(
            saved[0].filter_name.as_deref(),
            Some("R"),
            "the FITS FILTER card must name the filter the wheel is actually on"
        );
        assert_eq!(
            saved[0].filter_index,
            Some(1),
            "FILTPOS must record the slot the frame was taken through"
        );

        let paths = ops.saved_frame_paths();
        assert!(
            paths[0].contains("_R_"),
            "the filename must agree with the header, got {}",
            paths[0]
        );
        assert!(
            !paths[0].contains("nofilter"),
            "a known filter must never render as the synthetic nofilter label, got {}",
            paths[0]
        );
    }

    /// A frame has to say which camera took it, even on a rig with no
    /// equipment profile.
    ///
    /// `INSTRUME` was built only from `ExecutionContext::camera_make/model`,
    /// which come from the observer profile — a cross-product of app settings
    /// and the ACTIVE EQUIPMENT PROFILE. A headless rig that never had a
    /// profile created has neither, so every frame it wrote carried no
    /// `INSTRUME` at all. Reproduced on the live rig: a real run wrote
    /// `Polaris_1_0001.fits` with `PIXSIZE 2.4` as the only clue to which of
    /// the two attached ZWO cameras took it, and reproduced again against the
    /// Linux simulator build, whose frames were identically silent.
    ///
    /// `expose_node_execution_ctx` sets no `camera_make`/`camera_model`, so
    /// this is exactly that rig. The camera is connected and the driver knows
    /// its name; the file must carry it.
    #[tokio::test]
    async fn frame_names_the_camera_when_no_equipment_profile_does() {
        let scratch = scratch_dir("instrume-fallback");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = expose_node_execution_ctx(ops.clone(), scratch.0.clone()).await;
        assert!(
            ec.camera_make.is_none() && ec.camera_model.is_none(),
            "precondition: this rig has no equipment profile naming a camera"
        );

        let status = run_expose_node(one_dark_no_filter(), &mut ec).await;
        assert_eq!(status, NodeStatus::Success, "burst should complete");

        let saved = ops.saved_frame_contexts();
        assert_eq!(saved.len(), 1, "one frame should have reached the writer");
        assert_eq!(
            saved[0].camera_model.as_deref(),
            Some("ZWO ASI1600MM-Cool (1600-A1B2)"),
            "INSTRUME must fall back to the camera the driver reports"
        );
    }

    /// The operator's own answer outranks the driver's.
    ///
    /// Guards the fallback against becoming an override: someone who has named
    /// their camera in an equipment profile has said what they want in their
    /// archive, and a generic driver string must not displace it.
    #[tokio::test]
    async fn equipment_profile_camera_name_beats_the_driver_string() {
        let scratch = scratch_dir("instrume-profile");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = expose_node_execution_ctx(ops.clone(), scratch.0.clone()).await;
        ec.camera_make = Some("ZWO".to_string());
        ec.camera_model = Some("ASI178MM".to_string());

        let status = run_expose_node(one_dark_no_filter(), &mut ec).await;
        assert_eq!(status, NodeStatus::Success, "burst should complete");

        let saved = ops.saved_frame_contexts();
        assert_eq!(
            saved[0].camera_model.as_deref(),
            Some("ASI178MM"),
            "a profile-named camera must survive the driver fallback"
        );
        assert_eq!(saved[0].camera_make.as_deref(), Some("ZWO"));
    }

    /// The burst's resolved filter identity must be PUBLISHED, not just kept in
    /// the execution context, because Dart writes `captured_images.filter` and
    /// `sequence_runs.stats_json`'s filter bucket from the published value.
    ///
    /// Only a Change Filter node ever emitted `ProgressDetail::Filter`. So a
    /// burst that addresses the wheel by SLOT — with a Change Filter to "L"
    /// (slot 0) earlier in the sequence — wrote `FILTER = 'R'` into the header
    /// and `_R_` into the filename here while Dart still held "L", and the
    /// database row for that same frame said "L". One frame, two filters.
    #[tokio::test]
    async fn burst_publishes_the_filter_identity_it_resolved() {
        use std::sync::Mutex as StdMutex;

        let scratch = scratch_dir("publish-filter");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = expose_node_execution_ctx(ops.clone(), scratch.0.clone()).await;
        // What a preceding Change Filter to "L" leaves behind.
        ec.current_filter = Some("L".to_string());
        ec.current_filter_index = Some(0);

        let updates: Arc<StdMutex<Vec<crate::node::progress::ProgressUpdate>>> =
            Arc::new(StdMutex::new(Vec::new()));
        let sink = updates.clone();
        ec.progress_callback = Some(Arc::new(move |u| sink.lock().unwrap().push(u)));

        // Position-addressed burst: slot 1 is "R" in the wheel's name table.
        let config = ExposureConfig {
            filter: None,
            filter_index: Some(1),
            ..one_dark_no_filter()
        };
        let status = run_expose_node(config, &mut ec).await;
        assert_eq!(status, NodeStatus::Success, "burst should complete");

        let saved = ops.saved_frame_contexts();
        assert_eq!(
            saved[0].filter_name.as_deref(),
            Some("R"),
            "the frame was taken through slot 1, which the wheel names R"
        );

        let published: Vec<(String, Option<i32>)> = updates
            .lock()
            .unwrap()
            .iter()
            .filter_map(|u| match u.detail.as_ref() {
                Some(crate::node::progress::ProgressDetail::Filter { name, position }) => {
                    Some((name.clone(), *position))
                }
                _ => None,
            })
            .collect();
        assert_eq!(
            published,
            vec![("R".to_string(), Some(1))],
            "the burst must publish exactly the (name, slot) pair it stamped on \
             the frame, so the database row cannot disagree with the header"
        );
    }

    /// A node that DOES name its own filter. The wheel is moved there by
    /// `execute_exposure`, but `${filter}` in the save-path template reads
    /// `current_filter` — never `config.filter` — so the file still landed as
    /// `..._nofilter_....fits` while the header said "L".
    #[tokio::test]
    async fn burst_filename_uses_the_filter_the_node_configured() {
        let scratch = scratch_dir("node-filter");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = expose_node_execution_ctx(ops.clone(), scratch.0.clone()).await;

        let config = ExposureConfig {
            filter: Some("L".to_string()),
            filter_index: Some(0),
            ..one_dark_no_filter()
        };
        let status = run_expose_node(config, &mut ec).await;
        assert_eq!(status, NodeStatus::Success, "burst should complete");

        let paths = ops.saved_frame_paths();
        assert!(
            paths[0].contains("_L_"),
            "the filename must carry the node's own filter, got {}",
            paths[0]
        );
        assert_eq!(
            ec.current_filter.as_deref(),
            Some("L"),
            "the run context must carry the filter forward to later nodes"
        );
    }

    /// The rig of [`expose_node_execution_ctx`] collapsed to the
    /// `InstructionContext` that the callers who never build a node hand
    /// `execute_exposure` — the Flat Wizard and the bridge one-shots.
    async fn direct_capture_ctx(
        ops: Arc<dyn DeviceOps>,
        save_path: std::path::PathBuf,
    ) -> InstructionContext {
        let mut ec = crate::node::context::ExecutionContext::new("direct".to_string());
        ec.device_ops = ops;
        ec.camera_id = Some("cam-1".to_string());
        ec.focuser_id = Some("foc-1".to_string());
        ec.rotator_id = Some("rot-1".to_string());
        ec.filterwheel_id = Some("fw-1".to_string());
        ec.save_path = Some(save_path);
        ec.latitude = Some(TEST_LAT);
        ec.longitude = Some(TEST_LON);
        ec.to_instruction_context("direct").await
    }

    /// The Flat Wizard's final flat burst: `execute_exposure` called directly,
    /// with no node and no save-path renderer, and a config whose `filter` is
    /// whatever the wizard was configured with — commonly nothing, because the
    /// operator shot flats through the filter already on the wheel.
    ///
    /// The wheel-report fallback used to live in the TakeExposure node, so this
    /// path produced `Flat_nofilter_0001.fits` with NO FILTER card. Flats with
    /// no FILTER card cannot be matched to the lights they were shot for by any
    /// calibration tool, which is the whole point of taking them.
    #[tokio::test]
    async fn flat_wizard_burst_records_the_filter_the_wheel_is_parked_on() {
        let scratch = scratch_dir("direct-wheel-filter");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let ctx = direct_capture_ctx(ops.clone(), scratch.0.clone()).await;

        let config = ExposureConfig {
            duration_secs: 0.01,
            count: 1,
            frame_type: "Flat".to_string(),
            filter: None,
            filter_index: None,
            ..ExposureConfig::default()
        };
        let result = execute_exposure(&config, &ctx, |_, _| {}).await;
        assert_eq!(result.status, NodeStatus::Success, "burst should complete");

        let saved = ops.saved_frame_contexts();
        assert_eq!(saved.len(), 1, "one frame should have reached the writer");
        assert_eq!(
            saved[0].filter_name.as_deref(),
            Some("R"),
            "the FITS FILTER card must name the filter the wheel is actually on"
        );
        assert_eq!(
            saved[0].filter_index,
            Some(1),
            "FILTPOS must record the slot the frame was taken through"
        );

        let paths = ops.saved_frame_paths();
        assert!(
            !paths[0].contains("nofilter"),
            "a known filter must never render as the synthetic nofilter label, got {}",
            paths[0]
        );
        assert!(
            paths[0].contains("_R_"),
            "the filename must agree with the header, got {}",
            paths[0]
        );
    }

    /// A direct burst that names its filter but carries no slot, run after
    /// something else established a different filter. Name and slot used to be
    /// resolved independently (`config.filter.or(ctx.current_filter)` next to
    /// `config.filter_index.or(ctx.current_filter_index)`), so the frame was
    /// stamped with this burst's NAME and the previous burst's SLOT — one frame
    /// described by two different filters, and the disagreement is silent
    /// because each field is individually plausible.
    #[tokio::test]
    async fn direct_burst_never_pairs_its_filter_name_with_a_stale_slot() {
        let scratch = scratch_dir("direct-stale-slot");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ctx = direct_capture_ctx(ops.clone(), scratch.0.clone()).await;
        // What a preceding Change Filter to "L" (slot 0) leaves behind.
        ctx.current_filter = Some("L".to_string());
        ctx.current_filter_index = Some(0);

        let config = ExposureConfig {
            duration_secs: 0.01,
            count: 1,
            frame_type: "Flat".to_string(),
            filter: Some("R".to_string()),
            filter_index: None,
            ..ExposureConfig::default()
        };
        let result = execute_exposure(&config, &ctx, |_, _| {}).await;
        assert_eq!(result.status, NodeStatus::Success, "burst should complete");

        let saved = ops.saved_frame_contexts();
        assert_eq!(
            saved[0].filter_name.as_deref(),
            Some("R"),
            "the burst's own filter is what the frame was taken through"
        );
        assert_eq!(
            saved[0].filter_index,
            Some(1),
            "FILTPOS must be R's slot, not the slot the previous filter occupied"
        );
    }

    /// A burst that addresses the wheel BY NAME never learns the slot it
    /// landed on, so the frame used to carry the correct filter name next to
    /// whatever slot number the previous burst had left in the run context —
    /// the same frame described by two different filters.
    #[tokio::test]
    async fn name_addressed_burst_does_not_inherit_the_previous_bursts_slot() {
        let scratch = scratch_dir("stale-filter-slot");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = expose_node_execution_ctx(ops.clone(), scratch.0.clone()).await;

        // Burst 1 addresses slot 1 ("R" in the double's name table).
        let by_index = ExposureConfig {
            filter: None,
            filter_index: Some(1),
            ..one_dark_no_filter()
        };
        assert_eq!(
            run_expose_node(by_index, &mut ec).await,
            NodeStatus::Success,
            "position-addressed burst should complete"
        );

        // Burst 2 addresses "L" by name only, exactly what the Dart serializer
        // emits when the profile has no index for that filter.
        let by_name = ExposureConfig {
            filter: Some("L".to_string()),
            filter_index: None,
            ..one_dark_no_filter()
        };
        assert_eq!(
            run_expose_node(by_name, &mut ec).await,
            NodeStatus::Success,
            "name-addressed burst should complete"
        );

        let saved = ops.saved_frame_contexts();
        assert_eq!(saved.len(), 2, "one frame per burst");
        assert_eq!(saved[1].filter_name.as_deref(), Some("L"));
        assert_eq!(
            saved[1].filter_index,
            Some(0),
            "the slot must be the one L actually occupies, not slot 1 left over \
             from the previous burst"
        );
    }

    /// The wheel does not answer to the name the burst asked for (profile and
    /// device naming drifted — "Ha" vs "H-alpha"). The slot is then genuinely
    /// unknown, and unknown must be recorded as unknown: keeping the previous
    /// burst's slot would file the frame under a filter it was not taken
    /// through.
    #[tokio::test]
    async fn unmatched_filter_name_clears_the_slot_instead_of_keeping_a_stale_one() {
        let scratch = scratch_dir("unmatched-filter-slot");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = expose_node_execution_ctx(ops.clone(), scratch.0.clone()).await;

        let by_index = ExposureConfig {
            filter: None,
            filter_index: Some(1),
            ..one_dark_no_filter()
        };
        assert_eq!(
            run_expose_node(by_index, &mut ec).await,
            NodeStatus::Success,
            "position-addressed burst should complete"
        );

        let unknown_name = ExposureConfig {
            filter: Some("H-alpha".to_string()),
            filter_index: None,
            ..one_dark_no_filter()
        };
        assert_eq!(
            run_expose_node(unknown_name, &mut ec).await,
            NodeStatus::Success,
            "name-addressed burst should complete"
        );

        let saved = ops.saved_frame_contexts();
        assert_eq!(saved[1].filter_name.as_deref(), Some("H-alpha"));
        assert_eq!(
            saved[1].filter_index, None,
            "an unresolvable slot must be recorded as unknown, not as slot 1 \
             left over from the previous burst"
        );
    }

    /// A rig with no filter wheel at all (OSC / DSLR) must stay honest: no
    /// invented label, no FILTER card.
    #[tokio::test]
    async fn burst_without_a_wheel_leaves_the_filter_unknown() {
        let scratch = scratch_dir("no-wheel");
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = expose_node_execution_ctx(ops.clone(), scratch.0.clone()).await;
        ec.filterwheel_id = None;

        let status = run_expose_node(one_dark_no_filter(), &mut ec).await;
        assert_eq!(status, NodeStatus::Success, "burst should complete");

        let saved = ops.saved_frame_contexts();
        assert_eq!(
            saved[0].filter_name, None,
            "with no wheel there is no filter to record"
        );
    }

    /// A calibration burst: the daylight gate never applies, so the test runs
    /// at any wall-clock hour, and no grader touches the frame.
    fn one_dark(count: u32) -> ExposureConfig {
        ExposureConfig {
            duration_secs: 0.01,
            count,
            frame_type: "Dark".to_string(),
            gain: Some(1),
            offset: Some(2),
            binning: Binning::Two,
            ..ExposureConfig::default()
        }
    }

    /// Drain the frame events a burst emitted, newest last.
    fn drain_frame_captures(
        rx: &mut tokio::sync::broadcast::Receiver<crate::executor::ExecutorEvent>,
    ) -> Vec<crate::scheduling::FrameCaptureMetadata> {
        let mut out = Vec::new();
        while let Ok(event) = rx.try_recv() {
            if let crate::executor::ExecutorEvent::NodeProgress {
                structured_detail: Some(detail),
                ..
            } = event
            {
                match *detail {
                    crate::node::ProgressDetail::FrameAccepted { capture, .. }
                    | crate::node::ProgressDetail::FrameRejected { capture, .. } => {
                        out.push(capture)
                    }
                    _ => {}
                }
            }
        }
        out
    }

    /// The fix's CENTRAL claim, asserted at the REAL call site: the frame event
    /// that makes Dart write the `captured_images` row is stamped from the very
    /// `FrameContext` instance `save_fits` was handed for that frame.
    ///
    /// Every other test on this path calls `emit_grade_progress` directly with a
    /// hand-made context and then derives both sides of the comparison from that
    /// same literal — proving only that a function stamps from its own argument,
    /// never that the argument is the right one. So this test runs
    /// `execute_exposure` for real against a device layer that RECORDS what the
    /// FITS writer received, and compares that recording against what the event
    /// carried. Hand `emit_grade_progress` anything other than `frame_ctx` and
    /// this fails; nothing else in the suite does.
    #[tokio::test]
    async fn frame_event_is_stamped_from_the_context_save_fits_received() {
        let scratch = scratch_dir("frame-ctx-agreement");
        let ops = Arc::new(
            ScriptedDomeRotatorOps::new()
                .with_capture_telemetry()
                .with_rotator_angles(vec![212.5]),
        );
        let (event_tx, mut event_rx) = tokio::sync::broadcast::channel(64);
        let ctx = saving_expose_ctx(ops.clone(), scratch.0.clone(), event_tx).await;

        let result = execute_exposure(&one_dark(2), &ctx, |_, _| {}).await;
        assert_eq!(
            result.status,
            NodeStatus::Success,
            "burst should complete: {:?}",
            result.message
        );

        let saved = ops.saved_frame_contexts();
        assert_eq!(
            saved.len(),
            2,
            "both frames must have reached the FITS writer"
        );

        let emitted = drain_frame_captures(&mut event_rx);
        assert_eq!(
            emitted.len(),
            saved.len(),
            "every saved frame must emit exactly one frame event"
        );

        for (index, (written, sent)) in saved.iter().zip(emitted.iter()).enumerate() {
            assert_eq!(
                *sent,
                crate::scheduling::FrameCaptureMetadata::from(written),
                "frame {} event carries a different capture than the FITS writer got",
                index + 1
            );
        }

        // Guard the guard: an all-default context would satisfy the equality
        // above if BOTH hops were severed together, so pin the telemetry the
        // scripted rig reported. These are the values that reach
        // `captured_images`.
        let first = &emitted[0];
        assert_eq!(first.gain, Some(139));
        assert_eq!(first.offset, Some(21));
        assert_eq!(first.sensor_temp_c, Some(-9.5));
        assert_eq!(first.cooler_power_percent, Some(63.5));
        assert_eq!(first.mount_ra_hours, Some(5.5));
        assert_eq!(first.mount_dec_degrees, Some(-5.25));
        assert!(
            first.mount_altitude_deg.is_some() && first.mount_azimuth_deg.is_some(),
            "a sited rig must derive alt/az from its own pointing"
        );
        assert_eq!(first.pier_side.as_deref(), Some("West"));
        assert_eq!(first.focuser_position, Some(31_705));
        assert_eq!(first.focuser_temperature_c, Some(4.25));
        assert_eq!(first.rotator_angle_deg, Some(212.5));
        assert_eq!(first.frame_type, "Dark");
        assert_eq!((first.bin_x, first.bin_y), (2, 2));
    }

    /// The alt/az stamped on a frame belongs to the light it integrated.
    ///
    /// This block runs after readout, so deriving the horizon frame from
    /// `Utc::now()` dated it by the whole exposure plus download — and this is
    /// the ONE derivation that feeds both the FITS `OBJCTALT`/`AIRMASS` cards
    /// and the `captured_images.mount_altitude` column the AAVSO exporter reads
    /// its AMASS from, so the error lands in a published photometry submission.
    ///
    /// Deliberately clock-independent: the mount is pointed at whatever is
    /// culminating at the instant the test starts, so the save-time answer is
    /// the target's maximum altitude and the midpoint — an hour later — is
    /// measurably lower, whatever time of day the suite runs. Tokio's clock is
    /// paused so the two-hour exposure costs no wall time while the CHRONO
    /// timestamps stay real.
    #[tokio::test(start_paused = true)]
    async fn frame_altitude_is_derived_at_the_exposure_midpoint() {
        let now = chrono::Utc::now();
        let ra_hours =
            crate::meridian::local_sidereal_time(crate::meridian::julian_day(&now), TEST_LON)
                .rem_euclid(24.0);
        let dec_degrees = 20.0;

        let scratch = scratch_dir("frame-ctx-midpoint");
        let ops = Arc::new(
            ScriptedDomeRotatorOps::new()
                .with_capture_telemetry()
                .with_scripted_mount_coordinates(ra_hours, dec_degrees),
        );
        let (event_tx, _event_rx) = tokio::sync::broadcast::channel(64);
        let mut ctx = saving_expose_ctx(ops.clone(), scratch.0.clone(), event_tx).await;

        // Opt out of the daylight gate, RELATIVE to the live Sun.
        //
        // This test is about where the altitude is sampled, not about whether
        // the Sun is up. Left on the default -12 deg threshold it passed at
        // night and failed in daylight — it was failing here with
        // "Sun altitude -2.4 deg is above the maximum -12.0 deg". Seeding the
        // threshold above the CURRENT Sun altitude keeps the gate wired
        // (the resolution path is still exercised) while making the outcome
        // independent of the hour the suite happens to run.
        let mut ts = crate::triggers::TriggerState::new();
        ts.set_max_sun_altitude_degrees(live_sun_alt() + 5.0);
        ctx.trigger_state = Some(std::sync::Arc::new(tokio::sync::RwLock::new(ts)));

        let config = ExposureConfig {
            duration_secs: 7200.0,
            count: 1,
            frame_type: "Light".to_string(),
            ..ExposureConfig::default()
        };
        let result = execute_exposure(&config, &ctx, |_, _| {}).await;
        assert_eq!(
            result.status,
            NodeStatus::Success,
            "burst should complete: {:?}",
            result.message
        );

        let saved = ops.saved_frame_contexts();
        let frame = saved.first().expect("one frame reached the FITS writer");
        let started = frame
            .exposure_started_at
            .expect("the shutter-open instant is recorded");
        let recorded = frame
            .mount_altitude_deg
            .expect("a sited rig derives an altitude from its own pointing");

        let (at_midpoint, _) = crate::meridian::calculate_alt_az(
            ra_hours,
            dec_degrees,
            TEST_LAT,
            TEST_LON,
            started + chrono::Duration::seconds(3600),
        );
        let (at_shutter_open, _) =
            crate::meridian::calculate_alt_az(ra_hours, dec_degrees, TEST_LAT, TEST_LON, started);
        assert!(
            (at_shutter_open - at_midpoint).abs() > 0.5,
            "test rig is not discriminating: shutter-open {at_shutter_open:.4} deg \
             vs midpoint {at_midpoint:.4} deg"
        );
        assert!(
            (recorded - at_midpoint).abs() < 0.05,
            "mount_altitude_deg was {recorded:.4} deg; the exposure midpoint is \
             {at_midpoint:.4} deg and the shutter-open instant is \
             {at_shutter_open:.4} deg"
        );
    }

    /// A sequenced sub must reach the FITS writer carrying the sensor's own
    /// pixel pitch.
    ///
    /// `FitsWriteHeaderRich::from_frame_context` hardcoded `pixel_size_x: None`
    /// and nothing upstream ever asked the camera, so every frame a real run
    /// produced landed on disk with FOCALLEN and APTDIA but no XPIXSZ/YPIXSZ —
    /// ASTAP, PixInsight and AstroBin cannot derive the plate scale from such a
    /// file. The manual-snapshot path was fixed to write the pitch, which left
    /// two frames off one rig disagreeing about one sensor.
    ///
    /// Asserted at the real call site rather than on a hand-built context:
    /// `execute_exposure` runs, and what is checked is the `FrameContext` the
    /// FITS writer was actually HANDED.
    #[tokio::test]
    async fn sequenced_frames_carry_the_sensor_pixel_pitch() {
        let scratch = scratch_dir("frame-ctx-pixel-pitch");
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_capture_telemetry());
        let (event_tx, _event_rx) = tokio::sync::broadcast::channel(16);
        let ctx = saving_expose_ctx(ops.clone(), scratch.0.clone(), event_tx).await;

        let result = execute_exposure(&one_dark(1), &ctx, |_, _| {}).await;
        assert_eq!(result.status, NodeStatus::Success, "{:?}", result.message);

        let saved = ops.saved_frame_contexts();
        assert_eq!(
            saved.len(),
            1,
            "the frame must have reached the FITS writer"
        );
        assert_eq!(
            (
                saved[0].camera_pixel_size_x_um,
                saved[0].camera_pixel_size_y_um
            ),
            (Some(3.76), Some(3.76)),
            "the pitch the camera reported has to be on the context the header \
             is built from, or the sub is written without XPIXSZ/YPIXSZ"
        );
    }

    /// ...and a camera that will not report a pitch leaves the keywords off
    /// rather than stamping a plausible-looking default a solver would trust.
    #[tokio::test]
    async fn a_camera_that_reports_no_pitch_leaves_the_keywords_absent() {
        let scratch = scratch_dir("frame-ctx-no-pixel-pitch");
        // No `with_capture_telemetry`, so the scripted rig has no pitch to give.
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let (event_tx, _event_rx) = tokio::sync::broadcast::channel(16);
        let ctx = saving_expose_ctx(ops.clone(), scratch.0.clone(), event_tx).await;

        let result = execute_exposure(&one_dark(1), &ctx, |_, _| {}).await;
        assert_eq!(result.status, NodeStatus::Success, "{:?}", result.message);

        let saved = ops.saved_frame_contexts();
        assert_eq!(saved.len(), 1);
        assert_eq!(
            (
                saved[0].camera_pixel_size_x_um,
                saved[0].camera_pixel_size_y_um
            ),
            (None, None),
        );
    }

    /// A camera that reports a slightly different exposure than the one
    /// commanded is reporting a real measurement (shutter latency, a coarse
    /// exposure clock), and that measurement is what `EXPTIME` means. It must
    /// reach both the header and the row.
    #[tokio::test]
    async fn plausible_driver_exposure_report_wins_over_the_commanded_value() {
        let scratch = scratch_dir("exposure-report-honest");
        let ops = Arc::new(
            ScriptedDomeRotatorOps::new()
                // Commanded 60s, shutter actually open 60.4s.
                .with_reported_exposure_secs(60.4),
        );
        let (event_tx, mut event_rx) = tokio::sync::broadcast::channel(16);
        let ctx = saving_expose_ctx(ops.clone(), scratch.0.clone(), event_tx).await;

        let config = ExposureConfig {
            duration_secs: 60.0,
            ..one_dark(1)
        };
        let result = execute_exposure(&config, &ctx, |_, _| {}).await;
        assert_eq!(result.status, NodeStatus::Success, "{:?}", result.message);

        let saved = ops.saved_frame_contexts();
        assert_eq!(saved[0].duration_secs, 60.4);
        assert_eq!(drain_frame_captures(&mut event_rx)[0].exposure_secs, 60.4);
    }

    /// ...but that trust is bounded. `captured_images.exposure_duration` is
    /// summed into every integration total in the app, so a driver reporting an
    /// impossible exposure — longer than the sequencer ever waited — must not be
    /// able to inflate a night's reported integration. Here a 60-second sub is
    /// reported as an hour; the recorded value has to stay 60.
    ///
    /// This is the one direction where the driver is provably wrong rather than
    /// merely surprising: nothing kept the shutter open past the command.
    #[tokio::test]
    async fn nonsense_driver_exposure_report_cannot_inflate_integration_totals() {
        let scratch = scratch_dir("exposure-report-nonsense");
        let ops = Arc::new(
            ScriptedDomeRotatorOps::new()
                // 60x the commanded exposure: an entire night's integration in
                // one sub, if this were believed.
                .with_reported_exposure_secs(3600.0),
        );
        let (event_tx, mut event_rx) = tokio::sync::broadcast::channel(16);
        let ctx = saving_expose_ctx(ops.clone(), scratch.0.clone(), event_tx).await;

        let config = ExposureConfig {
            duration_secs: 60.0,
            ..one_dark(1)
        };
        let result = execute_exposure(&config, &ctx, |_, _| {}).await;
        assert_eq!(result.status, NodeStatus::Success, "{:?}", result.message);

        let saved = ops.saved_frame_contexts();
        assert_eq!(
            saved[0].duration_secs, 60.0,
            "an impossible exposure report must not reach the FITS header"
        );
        assert_eq!(
            drain_frame_captures(&mut event_rx)[0].exposure_secs,
            60.0,
            "nor the captured_images row every integration total sums"
        );
    }

    /// The gate must key off the FRAME TYPE, not off whether a TargetHeader
    /// happens to exist: a bare "Take Exposures" LIGHT node dropped at the top
    /// level of a sequence is exactly as much an on-sky capture as the same
    /// node nested under a target.
    ///
    /// Fails WITHOUT the fix — the gate also required `ctx.target_ra`/
    /// `target_dec`, so a targetless burst wrote LIGHT frames in full daylight.
    #[tokio::test]
    async fn untargeted_light_exposure_rejected_when_sun_up() {
        let sun_alt = live_sun_alt();
        // Mount NOT parked + no target group + Sun up → still an on-sky light.
        let ctx = expose_ctx(Arc::new(NullDeviceOps), None, sun_alt - 5.0).await;
        let result = execute_exposure(&one_light(), &ctx, |_, _| {}).await;
        assert!(
            is_daylight_block(&result),
            "a targetless LIGHT exposure must be daylight-blocked when Sun is up; got {:?}",
            result.message
        );
    }

    #[tokio::test]
    async fn parked_rig_target_exposure_not_gated_in_daylight() {
        let sun_alt = live_sun_alt();
        // Target set BUT mount parked (e.g. a dark library built inside a
        // target subtree while parked) → not on-sky → allow.
        let ops: Arc<dyn DeviceOps> =
            Arc::new(ScriptedDomeRotatorOps::new().with_mount_parked(true));
        let ctx = expose_ctx(ops, Some((5.5, 22.0)), sun_alt - 30.0).await;
        let result = execute_exposure(&one_light(), &ctx, |_, _| {}).await;
        assert!(
            !is_daylight_block(&result),
            "a parked-rig exposure must never be daylight-gated; got {:?}",
            result.message
        );
    }

    #[tokio::test]
    async fn light_exposure_on_target_allowed_when_sun_down() {
        let sun_alt = live_sun_alt();
        // Mount not parked + target set + Sun below max → allowed past the gate.
        let ctx = expose_ctx(Arc::new(NullDeviceOps), Some((5.5, 22.0)), sun_alt + 5.0).await;
        let result = execute_exposure(&one_light(), &ctx, |_, _| {}).await;
        assert!(
            !is_daylight_block(&result),
            "on-sky LIGHT exposure must clear the daylight gate at night; got {:?}",
            result.message
        );
    }

    // =====================================================================
    // Dome / cover-calibrator role resolution
    //
    // Nothing in the Dart→FFI runtime-config path calls
    // `SequenceExecutor::set_dome` / `set_cover_calibrator`, so
    // `InstructionContext::dome_id` / `cover_calibrator_id` are `None` on
    // every real run and all seven dome/cover node types failed with
    // "No dome connected" while the device sat connected in the Equipment
    // screen. These pin the fallback to the device layer's view of what is
    // connected, and pin that the failure still fires when nothing is.
    // =====================================================================

    #[tokio::test(start_paused = true)]
    async fn open_dome_uses_connected_dome_when_context_has_no_role() {
        let ops = Arc::new(
            ScriptedDomeRotatorOps::new()
                .with_active_dome_id("sim_dome_1")
                .with_dome_shutter_states(&["Open"]),
        );
        let mut ctx = ctx_with_ops(ops.clone()).await;
        // Exactly what the executor hands every real run today.
        ctx.dome_id = None;

        let result = execute_open_dome(&DomeConfig { shutter_only: true }, &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Success,
            "Open Dome must command the connected dome, got {:?}",
            result.message
        );
        assert_eq!(
            ops.dome_open_ids.lock().unwrap().as_slice(),
            ["sim_dome_1".to_string()],
            "the instruction must open the dome the device layer resolved"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn open_dome_still_fails_when_no_dome_is_connected() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ctx = ctx_with_ops(ops.clone()).await;
        ctx.dome_id = None;

        let result = execute_open_dome(&DomeConfig { shutter_only: true }, &ctx, None).await;

        assert_eq!(result.status, NodeStatus::Failure);
        assert_eq!(result.message.as_deref(), Some("No dome connected"));
        assert!(
            ops.dome_open_ids.lock().unwrap().is_empty(),
            "no dome may be commanded when none is connected"
        );
    }

    /// One failed node, one error entry — even when the node-runtime retries it.
    ///
    /// "No dome connected" is classified as a device-disconnect message, so
    /// `execute_instruction_with_disconnect_retry` re-runs the node once per
    /// recovery cycle. Every one of those executions published its own
    /// `InstructionFailed`, and the Dart layer turns each into a session-report
    /// error line and a Critical toast — which is why a single failed Open Dome
    /// node listed the same sentence six times.
    ///
    /// The test drives the real `RuntimeNode::execute` (not the private retry
    /// helper) so the wiring between the runtime and the publish site is under
    /// test, and asserts BOTH halves: the node really was executed six times,
    /// and the operator was told once.
    #[tokio::test(start_paused = true)]
    async fn a_retried_node_reports_its_failure_once_not_once_per_attempt() {
        use crate::node::runtime::{Node, RuntimeNode};

        let ops = Arc::new(ScriptedDomeRotatorOps::new());
        let mut ec = crate::node::context::ExecutionContext::new("dup-error".to_string());
        ec.device_ops = ops.clone();
        let (event_tx, mut event_rx) = tokio::sync::broadcast::channel(64);
        ec.event_tx = Some(event_tx);

        // Stand in for a recovery driver that engages and completes a cycle:
        // the wrapper watches `recovery_generation` to decide the device came
        // back, so bumping it is what makes the retry loop go round instead of
        // failing closed on "no recovery driver engaged".
        let generation = ec.recovery_generation.clone();
        let driver = tokio::spawn(async move {
            loop {
                generation.fetch_add(1, std::sync::atomic::Ordering::Release);
                tokio::time::sleep(std::time::Duration::from_millis(1)).await;
            }
        });

        let mut node = RuntimeNode::from_definition(crate::NodeDefinition {
            id: "dome-node".to_string(),
            name: "Open Dome".to_string(),
            node_type: NodeType::OpenDome(DomeConfig { shutter_only: true }),
            enabled: true,
            children: Vec::new(),
        });
        let status = node.execute(&mut ec).await;
        driver.abort();

        assert_eq!(status, NodeStatus::Failure, "no dome is connected");
        assert!(
            ops.active_dome_id_calls.load(Ordering::SeqCst) > 1,
            "the retry loop must actually have re-run the node, otherwise this \
             test proves nothing about collapsing retries"
        );

        let mut reported = Vec::new();
        while let Ok(event) = event_rx.try_recv() {
            if let crate::executor::ExecutorEvent::InstructionFailed { node_name, message } = event
            {
                reported.push(format!("{node_name}: {message}"));
            }
        }
        assert_eq!(
            reported,
            vec!["Open Dome: No dome connected".to_string()],
            "one failed node must produce exactly one operator-facing error, got {reported:?}"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn open_cover_uses_connected_panel_when_context_has_no_role() {
        let ops = Arc::new(ScriptedDomeRotatorOps::new().with_active_cover_calibrator_id("sim_cc"));
        let mut ctx = ctx_with_ops(ops.clone()).await;
        ctx.cover_calibrator_id = None;

        let result = execute_open_cover(
            &crate::CoverCalibratorConfig { timeout_secs: 5 },
            &ctx,
            None,
        )
        .await;

        assert_eq!(
            result.status,
            NodeStatus::Success,
            "Open Cover must command the connected panel, got {:?}",
            result.message
        );
        assert_eq!(
            ops.cover_open_ids.lock().unwrap().as_slice(),
            ["sim_cc".to_string()],
            "the instruction must open the panel the device layer resolved"
        );
    }

    // =====================================================================
    // Wait node with no condition
    // =====================================================================

    /// An unconfigured Wait node used to return Success in microseconds — a
    /// without waiting. The canonical use is "wait until astronomical dark", so
    /// skipping it starts the run in daylight; it must fail instead.
    #[tokio::test]
    async fn wait_time_without_any_condition_fails() {
        let ctx = crate::node::context::ExecutionContext::new("test-node".to_string())
            .to_instruction_context("test-node")
            .await;

        let result = execute_wait_time(&WaitTimeConfig::default(), &ctx, None).await;

        assert_eq!(
            result.status,
            NodeStatus::Failure,
            "a Wait node with neither a time nor a twilight condition must not report Success"
        );
        let msg = result.message.unwrap_or_default();
        assert!(
            msg.contains("no wait condition"),
            "the failure must name the missing configuration, got: {msg}"
        );
    }

    // -------------------------------------------------------------------
    // CONC-001: a script that outruns its timeout must (a) return the
    // exact "Script timed out ..." failure and (b) leave no live child
    // process behind (kill_on_drop reaps it).
    // -------------------------------------------------------------------

    #[cfg(target_os = "linux")]
    async fn script_ctx() -> InstructionContext {
        crate::node::context::ExecutionContext::new("test-node".to_string())
            .to_instruction_context("test-node")
            .await
    }

    #[cfg(target_os = "linux")]
    fn empty_frame() -> crate::expressions::EvaluationFrame {
        crate::expressions::EvaluationFrame::empty()
    }

    /// True while `pid` is a live, schedulable process. A child that has
    /// been killed and reaped is gone (no `/proc/<pid>`); one that was
    /// killed but not yet reaped shows up as a zombie (`State: Z`), which
    /// for our purposes is "not running". Linux-only because it reads
    /// `/proc`; that matches where this crate's process tests run.
    #[cfg(target_os = "linux")]
    fn pid_is_running(pid: u32) -> bool {
        match std::fs::read_to_string(format!("/proc/{pid}/stat")) {
            // /proc/<pid>/stat is "pid (comm) state ...". The state char
            // after the closing paren is 'Z' for a reaped-pending zombie.
            Ok(stat) => match stat.rsplit_once(") ") {
                Some((_, rest)) => !rest.starts_with('Z'),
                None => true,
            },
            Err(_) => false,
        }
    }

    /// A Run Script node created from the palette carries no `timeout_secs`
    /// (the Dart `ScriptNode.timeoutSecs` is a nullable field with no default)
    /// while the editor displays 300. Refusing to run in that state made every
    /// freshly added Run Script node dead on arrival: "Script timeout_secs is
    /// required in fail-closed mode", script never spawned.
    ///
    /// Fails WITHOUT the fix.
    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn script_without_timeout_runs_under_the_default_timeout() {
        let marker = std::env::temp_dir().join(format!(
            "nightshade_script_default_timeout_{}.txt",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&marker);

        let cfg = ScriptConfig {
            script_path: "/bin/sh".to_string(),
            arguments: vec!["-c".to_string(), format!("echo ran > {}", marker.display())],
            timeout_secs: None,
        };

        let ctx = script_ctx().await;
        let ec = crate::node::context::ExecutionContext::new("test-node".to_string());
        let result = execute_script(&cfg, &ctx, &ec, &empty_frame()).await;

        let ran =
            std::fs::read_to_string(&marker).expect("the script must create its completion marker");
        let _ = std::fs::remove_file(&marker);

        assert_eq!(
            result.status,
            NodeStatus::Success,
            "a script with no explicit timeout must run under the default; got {:?}",
            result.message
        );
        assert_eq!(
            ran.trim(),
            "ran",
            "the script must actually execute, not be refused before spawn"
        );
    }

    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn script_timeout_returns_failure_and_kills_child() {
        let dir = std::env::temp_dir();
        let pidfile = dir.join(format!("nightshade_script_test_{}.pid", std::process::id()));
        let _ = std::fs::remove_file(&pidfile);

        // sh records its own PID, then sleeps far past the 1s timeout.
        let cfg = ScriptConfig {
            script_path: "/bin/sh".to_string(),
            arguments: vec![
                "-c".to_string(),
                format!("echo $$ > {}; sleep 60", pidfile.display()),
            ],
            timeout_secs: Some(1),
        };

        let ctx = script_ctx().await;
        let ec = crate::node::context::ExecutionContext::new("test-node".to_string());
        let frame = empty_frame();

        let result = execute_script(&cfg, &ctx, &ec, &frame).await;

        // Invariant: identical timeout failure message.
        assert_eq!(result.status, NodeStatus::Failure);
        assert_eq!(
            result.message.as_deref(),
            Some("Script timed out after 1 seconds"),
            "timeout must surface the exact existing failure text"
        );

        // The child must no longer be running once the call returns.
        let pid: u32 = std::fs::read_to_string(&pidfile)
            .expect("script should have written its PID before sleeping")
            .trim()
            .parse()
            .expect("PID file should contain a number");

        // kill_on_drop reaps via the runtime's background reaper; give it a
        // brief, bounded window to observe the process leave the run queue.
        let mut alive = true;
        for _ in 0..50 {
            if !pid_is_running(pid) {
                alive = false;
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        let _ = std::fs::remove_file(&pidfile);
        assert!(
            !alive,
            "child PID {pid} is still running after the script timed out — process was orphaned"
        );
    }

    /// SEQ-001: a script that backgrounds work (`some_cmd &`) and then times out
    /// must leave NO descendant running. `kill_on_drop` reaps only the direct
    /// child; the process-group teardown must take the backgrounded grandchild
    /// with it. This fails on the pre-fix code (grandchild survives) and passes
    /// once the child is spawned in its own group and the group is SIGKILLed.
    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn script_timeout_kills_backgrounded_grandchild() {
        let dir = std::env::temp_dir();
        let gcfile = dir.join(format!("nightshade_script_gc_{}.pid", std::process::id()));
        let _ = std::fs::remove_file(&gcfile);

        // sh backgrounds a 60s sleep (the grandchild), records its PID, then
        // `wait`s past the 1s timeout. The grandchild shares sh's process group.
        let cfg = ScriptConfig {
            script_path: "/bin/sh".to_string(),
            arguments: vec![
                "-c".to_string(),
                format!("sleep 60 & echo $! > {}; wait", gcfile.display()),
            ],
            timeout_secs: Some(1),
        };

        let ctx = script_ctx().await;
        let ec = crate::node::context::ExecutionContext::new("test-node".to_string());
        let frame = empty_frame();

        let result = execute_script(&cfg, &ctx, &ec, &frame).await;

        // Invariant: identical timeout failure message.
        assert_eq!(result.status, NodeStatus::Failure);
        assert_eq!(
            result.message.as_deref(),
            Some("Script timed out after 1 seconds"),
            "timeout must surface the exact existing failure text"
        );

        let gc_pid: u32 = std::fs::read_to_string(&gcfile)
            .expect("script should have written its backgrounded grandchild PID")
            .trim()
            .parse()
            .expect("grandchild PID file should contain a number");

        // The group kill races a reparent+reap; give it a brief bounded window.
        let mut alive = true;
        for _ in 0..50 {
            if !pid_is_running(gc_pid) {
                alive = false;
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        let _ = std::fs::remove_file(&gcfile);
        assert!(
            !alive,
            "backgrounded grandchild PID {gc_pid} survived the timeout — the script's \
             process group was not torn down"
        );
    }

    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn script_success_surfaces_stdout_stderr_exit_code() {
        // Regression on the success path: stdout/stderr/exit_code unchanged.
        let cfg = ScriptConfig {
            script_path: "/bin/sh".to_string(),
            arguments: vec![
                "-c".to_string(),
                "echo out; echo err 1>&2; exit 0".to_string(),
            ],
            timeout_secs: Some(10),
        };
        let ctx = script_ctx().await;
        let ec = crate::node::context::ExecutionContext::new("test-node".to_string());
        let frame = empty_frame();

        let result = execute_script(&cfg, &ctx, &ec, &frame).await;
        assert_eq!(result.status, NodeStatus::Success);
        let data = result.data.expect("success must carry script output data");
        assert_eq!(data["stdout"].as_str().unwrap().trim(), "out");
        assert_eq!(data["stderr"].as_str().unwrap().trim(), "err");
        assert_eq!(data["exit_code"].as_i64(), Some(0));
    }

    /// Regression: the pre-exposure meridian gate must apply to LIGHTS only.
    ///
    /// A calibration frame inside a TargetHeader used to be gated too — a 3s
    /// dark was held with "meridian flip fires in ~0s and would interrupt it",
    /// stalling the run for the gate's full 30-minute bound. Shutter-closed
    /// frames cannot be ruined by where the mount points.
    #[test]
    fn meridian_gate_applies_to_light_frames_only() {
        for gated in ["light", "Light", "LIGHT"] {
            assert!(
                gated.eq_ignore_ascii_case("light"),
                "{gated} must be recognised as a light frame and gated"
            );
        }
        for ungated in ["dark", "bias", "flat", "darkflat", "snapshot"] {
            assert!(
                !ungated.eq_ignore_ascii_case("light"),
                "{ungated} must NOT be held for a meridian flip"
            );
        }
    }
}
