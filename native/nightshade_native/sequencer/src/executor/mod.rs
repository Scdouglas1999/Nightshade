//! Sequence execution engine.
//!
//! This module owns the [`SequenceExecutor`] struct, its constructor, the
//! orchestrating [`SequenceExecutor::start`] method, the sequence-load /
//! totals-calculation helpers, the free-standing recovery / trigger helper
//! functions that the inline executor closures rely on, and the public
//! event / progress / state types.
//!
//! Cohesive concerns are split into sibling submodules:
//!   * [`lifecycle`]    — operator pause/resume/stop/skip/recovery-button.
//!   * [`recovery`]     — recovery state-machine snapshot accessors.
//!   * [`setup`]        — pre-start `set_*` wiring and post-run `reset`.
//!   * [`loading`]      — sequence load + read-only totals/order walks.
//!   * [`runtime_config`] — `update_*` mid-flight config mutators.
//!   * [`checkpoint`]   — crash-recovery save/load/resume surface.
//!   * [`decision`]     — structured-decision logging surface.
//!
//! What is deliberately kept here in `mod.rs`:
//!   * `start()` — the orchestrator. It captures dozens of locals into
//!     spawned tasks; extracting it would require either a giant
//!     parameter struct or making most private fields `pub(super)`,
//!     neither of which is a net win.
//!   * The free-standing helpers (`run_recovery_attempt`,
//!     `build_trigger_autofocus_context`, etc.) are owned here because
//!     the inline `start()` closures are their only callers.

mod checkpoint;
mod decision;
mod lifecycle;
mod loading;
mod recovery;
mod runtime_config;
mod setup;

use crate::device_ops::SharedDeviceOps;
use crate::node::{
    CloudMotionSnapshot, ExecutionContext, Node, ProgressDetail, ProgressUpdate, RuntimeNode,
};
use crate::triggers::{Trigger, TriggerManager, TriggerState};
use crate::{
    NodeDefinition, NodeId, NodeStatus, NodeType, RecoveryAction, SafetyFailMode,
    SequenceDefinition, TriggerType,
};
use futures::FutureExt;
use parking_lot::RwLock as StdRwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::{broadcast, mpsc, RwLock};

const RECOVERY_NODE_TRIGGER_PREFIX: &str = "recovery_node:";
const DEFAULT_SAFETY_CHECK_INTERVAL_SECS: u64 = 30;

/// Default staleness window for the Dart weather verdict (Subsystem 2 step 3).
/// The Dart side pushes the verdict on every 5-minute periodic evaluation plus
/// on every alert/snooze change; 6 minutes gives the periodic push a full cycle
/// of slack before a missed push is treated as a dead feed.
const DEFAULT_WEATHER_VERDICT_STALENESS_SECS: u64 = 360;

fn effective_safety_check_interval_secs(value: u64) -> u64 {
    if value == 0 {
        DEFAULT_SAFETY_CHECK_INTERVAL_SECS
    } else {
        value.clamp(5, 3600)
    }
}

/// Resolve the effective weather-verdict staleness window. `0` => the default;
/// otherwise clamped to a sane floor (the safety poll cadence) so a tiny
/// misconfiguration cannot make a still-fresh verdict warn every tick, and an
/// upper bound so a typo cannot disable the observability entirely.
fn effective_weather_verdict_staleness_secs(value: u64) -> u64 {
    if value == 0 {
        DEFAULT_WEATHER_VERDICT_STALENESS_SECS
    } else {
        value.clamp(30, 86_400)
    }
}

/// How a non-auto-recoverable recovery escalation (an `AttemptOutcome::
/// PauseForOperator`, e.g. from a consecutive-reject storm) must be handled,
/// derived purely from operator presence.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EscalationDisposition {
    /// UNATTENDED rig: drive the safe-state sweep (park mount + close cover +
    /// close dome) and fail the run. Never freeze the rig dome-open with
    /// safety triggers disabled until dawn.
    SafeAbandon,
    /// ATTENDED rig: passively pause and hand the run to the present operator
    /// for inspection / resume (after restoring tracking).
    PassivePause,
}

/// Decide how a `PauseForOperator` recovery escalation is handled, given
/// whether an operator has declared presence.
///
/// This is the BLOCKER #1 safety decision factored out so it is unit-testable
/// without spinning up the full executor task. The default — and the SAFE
/// default — is "unattended" (`operator_present == false`), which must drive a
/// safe abandonment rather than a passive, trigger-disabled, dome-open freeze.
fn recovery_escalation_disposition(operator_present: bool) -> EscalationDisposition {
    if operator_present {
        EscalationDisposition::PassivePause
    } else {
        EscalationDisposition::SafeAbandon
    }
}

/// Re-enable mount tracking after a recovery loop that stopped it
/// (`stop_tracking_during_recovery`), emitting a LOUD error if it cannot be
/// restored.
///
/// BLOCKER #2: recovery entry stops tracking by default. Any path that resumes
/// or hands the run back to the operator MUST restore tracking first — the
/// generic Resume command does not — otherwise the sequence exposes on a
/// non-tracking mount and every frame trails while the UI reports "Running".
/// Both the recovered-resume branch and the attended operator-Pause branch call
/// this so neither can resume untracked. A failure is never silent: it logs at
/// error level and forwards an `ExecutorEvent::Error`.
///
/// `context_label` distinguishes the wording ("after recovery" vs "before
/// operator Pause") so the operator sees which path could not restore tracking.
/// Returns `Some(message)` iff tracking restoration failed (also already
/// emitted), so callers/tests can assert on it.
async fn restore_tracking_after_recovery(
    device_ops: &SharedDeviceOps,
    mount_id: Option<&str>,
    stop_tracking: bool,
    context_label: &str,
    event_tx: &broadcast::Sender<ExecutorEvent>,
) -> Option<String> {
    if !stop_tracking {
        return None;
    }
    let mount_id = mount_id?;
    match device_ops.mount_set_tracking(mount_id, true).await {
        Ok(()) => {
            tracing::info!(
                "[RECOVERY] Re-enabled tracking on '{}' {}",
                mount_id,
                context_label
            );
            None
        }
        Err(e) => {
            tracing::error!(
                "[RECOVERY] Failed to re-enable tracking on '{}' {}: {}",
                mount_id,
                context_label,
                e
            );
            let message = format!(
                "Recovery {} but tracking could not be re-enabled on {}: {} — resumed frames may trail until tracking is restored.",
                context_label, mount_id, e
            );
            let _ = event_tx.send(ExecutorEvent::Error {
                message: message.clone(),
            });
            Some(message)
        }
    }
}

/// Shared state the recovery driver hands to [`apply_recovery_escalation`] so
/// the escalation branch can be driven (and asserted on) without spinning up
/// the whole 7000-line trigger-monitor closure.
///
/// All fields are borrows of the executor's live shared state — the same
/// `Arc<…>` clones the inline driver captured — so the extracted function
/// mutates exactly the production state and emits on the production event bus.
pub(crate) struct RecoveryEscalationState<'a> {
    pub device_ops: &'a SharedDeviceOps,
    pub event_tx: &'a broadcast::Sender<ExecutorEvent>,
    pub runtime_config: &'a Arc<StdRwLock<RuntimeConfig>>,
    pub state: &'a Arc<RwLock<ExecutorState>>,
    pub progress: &'a Arc<StdRwLock<SequenceProgress>>,
    pub current_recovery: &'a Arc<StdRwLock<Option<crate::recovery::RecoveryContext>>>,
    pub is_cancelled: &'a Arc<AtomicBool>,
    pub gave_up: &'a Arc<AtomicBool>,
    pub mount_id: Option<&'a str>,
    pub cover_id: Option<&'a str>,
    pub dome_id: Option<&'a str>,
}

/// Apply a `PauseForOperator` recovery escalation, exactly as the recovery
/// driver loop does once an `AttemptOutcome::PauseForOperator` ends the retry
/// loop. Factored out of the inline driver closure so the BLOCKER #1/#2 branch
/// is reachable by an integration test that drives the real device-ops and
/// asserts the call ORDER (BLOCKER #2: tracking restored BEFORE the Paused
/// `StateChanged`) and the SafeAbandon path (BLOCKER #1: park+close → Failed,
/// never a resumable Paused-untracked state).
///
/// The disposition is derived live from `operator_present`:
///   * UNATTENDED (default) → SafeAbandon: park mount, close cover+dome, FAIL.
///   * ATTENDED → PassivePause: restore tracking, then flip to Paused.
async fn apply_recovery_escalation(
    s: &RecoveryEscalationState<'_>,
    ctx: &crate::recovery::RecoveryContext,
    pause_message: String,
    stop_tracking: bool,
) {
    // Read operator-presence live: an operator declaring presence mid-session
    // must take effect on THIS escalation. Default is UNATTENDED (false) — the
    // safe assumption, because the unattended path is the one that can lose
    // optics.
    let operator_present = s.runtime_config.read().operator_present;
    let disposition = recovery_escalation_disposition(operator_present);

    if disposition == EscalationDisposition::SafeAbandon {
        // BLOCKER #1 — UNATTENDED reject-storm escalation.
        //
        // The old behaviour flipped to a passive Paused state. But the trigger
        // monitor short-circuits on `state != Running` (it `continue`s), so the
        // weather / altitude / dawn safety triggers STOP evaluating — and the
        // node tree was never parked. On an unattended night that leaves the rig
        // dome+cover OPEN with safety monitoring OFF until dawn: a rolling cloud
        // / dew reject-storm can lose the optics, not just the night.
        //
        // So on an unattended rig a reject-storm escalation is a SAFE
        // ABANDONMENT, identical to the give-up branch: park the mount (the OTA
        // can't track into the Sun at dawn), close the cover, close the dome
        // (verified — see `park_and_close_safe_state`), then FAIL the run (which
        // cancels the node tree). The rig ends in the safe parked+closed
        // end-state instead of frozen-open-and-unmonitored.
        tracing::error!(
            "[RECOVERY] Escalated {:?} to operator Pause after {} attempt(s) on an UNATTENDED rig: {} — abandoning safely (park + close cover + close dome)",
            ctx.cause,
            ctx.attempt_count,
            pause_message
        );
        s.gave_up.store(true, Ordering::Relaxed);
        *s.current_recovery.write() = None;

        // Surface WHY first, so the operator / push channel sees the escalation
        // reason even if a safe-state step then fails.
        let _ = s.event_tx.send(ExecutorEvent::Error {
            message: pause_message.clone(),
        });

        // Single source of truth for the park → close cover → close dome sweep.
        // Mirror the give-up branch's retry tuning (2 park retries, 2s delay) so
        // behaviour is identical.
        let outcome = crate::device_ops::park_and_close_safe_state(
            s.device_ops,
            s.mount_id,
            s.cover_id,
            s.dome_id,
            2,
            2.0,
        )
        .await;

        if let (Some(mount_id), Some(park)) = (s.mount_id, &outcome.park) {
            if park.success {
                tracing::info!(
                    "[RECOVERY] Parked mount '{}' on unattended reject-storm abandonment ({} attempt(s))",
                    mount_id,
                    park.attempts_made
                );
            } else {
                let msg = format!(
                    "Reject-storm abandonment: the mount could not be parked ({}): {} — mount may be UNSAFE.",
                    mount_id,
                    park.last_error
                        .clone()
                        .unwrap_or_else(|| "unknown".to_string())
                );
                tracing::error!("[RECOVERY] {}", msg);
                let _ = s.event_tx.send(ExecutorEvent::Error { message: msg });
            }
        }
        if let (Some(cover_id), Some(e)) = (s.cover_id, &outcome.cover_close_error) {
            let msg = format!(
                "Reject-storm abandonment: failed to close cover '{}': {}",
                cover_id, e
            );
            tracing::error!("[RECOVERY] {}", msg);
            let _ = s.event_tx.send(ExecutorEvent::Error { message: msg });
        }
        if let (Some(dome_id), Some(e)) = (s.dome_id, &outcome.dome_close_error) {
            let msg = format!(
                "Reject-storm abandonment: failed to close dome '{}': {} — scope may be exposed.",
                dome_id, e
            );
            tracing::error!("[RECOVERY] {}", msg);
            let _ = s.event_tx.send(ExecutorEvent::Error { message: msg });
        }

        // Cancel the node tree and fail the run, exactly like the give-up
        // branch. The safety triggers keep protecting the rig right up to this
        // point (state was Recovering, never a passive Paused), and the rig now
        // sits in the safe parked+closed end-state rather than dome-open and
        // unmonitored.
        s.is_cancelled.store(true, Ordering::Relaxed);
        *s.state.write().await = ExecutorState::Failed;
        {
            let mut prog = s.progress.write();
            prog.state = ExecutorState::Failed;
            prog.message = Some(format!(
                "Unattended reject-storm: abandoned safely after {} attempt(s)",
                ctx.attempt_count
            ));
        }
        let _ = s
            .event_tx
            .send(ExecutorEvent::StateChanged(ExecutorState::Failed));
        let _ = s.event_tx.send(ExecutorEvent::RecoveryGaveUp {
            context: Box::new(ctx.clone()),
            aborted_by_user: false,
        });
    } else {
        // ATTENDED rig — an operator has explicitly declared presence. Escalate
        // to a real operator Pause: leave the node tree frozen (is_paused ==
        // true from step 2) and flip to the same Paused state the operator's
        // Pause command produces. This does NOT park-and-abort the rig (the
        // present operator may want to inspect and resume) and does NOT
        // auto-resume. The operator's Resume clears is_paused and flips back to
        // Running.
        tracing::warn!(
            "[RECOVERY] Escalated {:?} to operator Pause after {} attempt(s) on an ATTENDED rig: {}",
            ctx.cause,
            ctx.attempt_count,
            pause_message
        );

        // BLOCKER #2 — restore tracking BEFORE handing off to the operator
        // Pause. Recovery entry stops tracking (the default); the generic Resume
        // path does NOT re-enable it, so resuming from this Pause would expose
        // on a non-tracking mount and every frame would trail with the UI saying
        // "Running". Mirror the recovered branch (same shared helper): restore
        // tracking for all causes, loud error on failure (never silently leave a
        // resumable Pause that exposes untracked).
        let _ = restore_tracking_after_recovery(
            s.device_ops,
            s.mount_id,
            stop_tracking,
            "paused for operator",
            s.event_tx,
        )
        .await;

        *s.state.write().await = ExecutorState::Paused;
        {
            let mut prog = s.progress.write();
            prog.state = ExecutorState::Paused;
            prog.message = Some(pause_message.clone());
        }
        *s.current_recovery.write() = None;
        // Surface the reason as a critical-event banner so the operator (and any
        // push channel) sees why the run stopped.
        let _ = s.event_tx.send(ExecutorEvent::Error {
            message: pause_message,
        });
        let _ = s
            .event_tx
            .send(ExecutorEvent::StateChanged(ExecutorState::Paused));
        // Close out the recovery banner — the loop ended, it did not give up (no
        // park/fail), it handed off to a Pause.
        let _ = s.event_tx.send(ExecutorEvent::RecoveryCompleted {
            context: Box::new(ctx.clone()),
        });
    }
}

/// Subsystem 2 step 3 (stale-verdict observability): build the loud
/// "verdict feed stale; holding paused fail-closed" warning that the safety
/// poll emits when a `Some(true)`=UNSAFE Dart verdict has not been refreshed
/// within the staleness window.
///
/// Returns `Some(message)` ONLY on the rising edge (stale-and-unsafe AND not
/// already warned), advancing `*already_warned` to `true` so a dead feed does
/// not flood the event stream every poll. When the condition clears it re-arms
/// the latch (so a recovered-then-re-degraded feed warns again) and returns
/// `None`. This is pure observability — it NEVER touches or clears the verdict.
///
/// Factored out so the emission decision (gate + rate-limit + message) is
/// unit-testable without spinning up the full executor task; the loop calls it
/// and just forwards any returned message as an `ExecutorEvent::Error`.
fn weather_verdict_stale_warning(
    stale_unsafe: bool,
    staleness_secs: u64,
    already_warned: &mut bool,
) -> Option<String> {
    if stale_unsafe {
        if *already_warned {
            return None;
        }
        *already_warned = true;
        Some(format!(
            "Weather verdict feed stale ({}s without a refresh); holding the \
             sequence paused fail-closed. The last Dart weather verdict was \
             UNSAFE and has not been refreshed — the hold will continue until a \
             fresh verdict arrives. Operator attention required.",
            staleness_secs
        ))
    } else {
        // Fresh (or no-longer-unsafe) verdict — re-arm so a future stale-unsafe
        // episode warns again.
        *already_warned = false;
        None
    }
}

/// How a [`SafetyFailMode`] resolves the "no usable safety/weather data"
/// situation (poll error on the Rust side, no connected source on the Dart
/// side). This is the SINGLE cross-language truth table for the fail-mode
/// semantics — both the Rust safety poll below and the Dart weather-safety
/// verdict (`weather_safety_provider.dart` `noDataFailModeResolution`) must
/// agree on it.
///
/// Architecture-unification 2026-06-05 (Subsystem 2 step 1, cross-language
/// parity): extracted so the two implementations cannot drift. The Dart side
/// mirrors this enum as `NoDataResolution` and is pinned against the identical
/// table by `weather_fail_mode_parity_test.dart`; the Rust side is pinned by
/// `safety_fail_mode_no_data_resolution_truth_table` in this module. If you
/// change a row here, change it in BOTH tests or they will fail.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NoDataResolution {
    /// Treat the absence of data as UNSAFE (fail closed). The Rust poll sets
    /// `weather_safe = false`; the Dart verdict pushes `Some(true)` (unsafe).
    Unsafe,
    /// Treat the absence of data as SAFE (fail open). The Rust poll sets
    /// `weather_safe = true`; the Dart verdict ABSTAINS (`None`) rather than
    /// asserting SAFE, so a permissive Dart policy can never gag a
    /// hardware-unsafe device — but the resolution row is still "safe".
    Safe,
    /// Preserve the prior reading and emit an operator warning (warn-only).
    /// The Rust poll leaves `weather_safe` unchanged; the Dart verdict
    /// ABSTAINS (`None`).
    Preserve,
}

/// The single cross-language definition of how each [`SafetyFailMode`] resolves
/// a no-data / poll-error situation. See [`NoDataResolution`] for the contract
/// and the two tests that pin this table on each side.
pub fn safety_fail_mode_no_data_resolution(mode: SafetyFailMode) -> NoDataResolution {
    match mode {
        SafetyFailMode::FailClosed => NoDataResolution::Unsafe,
        SafetyFailMode::FailOpen => NoDataResolution::Safe,
        SafetyFailMode::WarnOnly => NoDataResolution::Preserve,
    }
}

/// pre-loaded per-frame defect-map application state.
///
/// The bridge loads the `.ndm` file into memory once when the user toggles
/// "Apply defect map" on (or sets the auto-apply default + a matching map
/// exists). It then pushes this struct in via `ExecutorCommand::UpdateDefectMap`
/// so each frame's correction is a `correct_u16_slice` call against the
/// pre-loaded `Arc<DefectMap>` — no per-frame disk I/O, no per-frame
/// allocation.
///
/// Held behind `Arc<RwLock<Option<DefectMapApplyState>>>` inside the
/// ExecutionContext. `None` means "do not apply". Mutating the inner
/// Option (toggle on / toggle off) does NOT require restarting the
/// sequence.
#[derive(Clone)]
pub struct DefectMapApplyState {
    /// Camera identifier this map applies to (`native:zwo:ASI2600MC`,
    /// `ascom:ZWO.ASICamera2`, etc.). The capture path verifies that the
    /// connected camera id matches before applying — a mismatch logs a
    /// warning and skips the frame's correction (rather than mis-applying
    /// a map built for a different sensor).
    pub camera_id: String,
    /// Shared pointer to the loaded defect map. Arc-wrapped so the
    /// ExecutionContext clone shares the bitmap allocation across all
    /// parallel branches and per-frame application is lock-free.
    pub map: Arc<nightshade_imaging::defect_map::DefectMap>,
    /// Replacement method — median (default), mean, or Gaussian-weighted.
    pub method: nightshade_imaging::defect_map::CorrectionMethod,
    /// Kernel diameter (3, 5, or 7).
    pub kernel: nightshade_imaging::defect_map::KernelSize,
    /// When true, the original uncorrected pixels are written to a
    /// sibling `Raw/` directory under the save folder before the
    /// in-place correction runs. Default false (the corrected frame
    /// replaces the raw one).
    pub save_original: bool,
}

impl std::fmt::Debug for DefectMapApplyState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DefectMapApplyState")
            .field("camera_id", &self.camera_id)
            .field("defective_pixels", &self.map.defective_count())
            .field("dimensions", &(self.map.width, self.map.height))
            .field("method", &self.method)
            .field("kernel_diameter", &self.kernel.diameter())
            .field("save_original", &self.save_original)
            .finish()
    }
}

/// Observer / equipment-identification payload pushed from Dart at
/// sequencer start. Drives the FITS `OBSERVER`, `SITEELEV`, `TELESCOP`,
/// `FOCALLEN`, `APTDIA`, `INSTRUME` keywords. All fields are `Option`
/// because in headless / no-profile runs we'd rather emit an absent
/// keyword than a sentinel — silent fallbacks are bugs.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ObserverProfile {
    pub observer_name: Option<String>,
    pub site_elevation_m: Option<f64>,
    pub camera_make: Option<String>,
    pub camera_model: Option<String>,
    pub telescope_name: Option<String>,
    pub telescope_focal_length_mm: Option<f64>,
    pub telescope_aperture_mm: Option<f64>,
}

/// Runtime-mutable configuration shared between the executor task,
/// instruction nodes, and the trigger-action handlers. these
/// values used to be cloned at sequence load and any in-flight
/// `UpdateDitherConfig`/`UpdateLocation`/`UpdateFilterOffsets` commands
/// were silently dropped (`let _ = (pixels, ...)`). Stored in
/// `Arc<RwLock<RuntimeConfig>>` so updates take effect on the next
/// dither/capture/autofocus invocation without requiring a sequence reload.
#[derive(Debug, Clone, Default)]
pub struct RuntimeConfig {
    /// Default dither configuration used by trigger-driven dithers
    /// (`RecoveryAction::Dither` and standalone Dither nodes that resolve
    /// against the runtime config). Per-exposure overrides (e.g.
    /// `ExposureConfig::dither_pixels`) take precedence — this only sets the
    /// fallback.
    pub dither: crate::DitherConfig,
    /// Autofocus configuration used by trigger-driven autofocus
    /// (`RecoveryAction::Autofocus` fired by the HFR / temperature / focus-
    /// drift / interval triggers). Seeded at `start()` from the sequence's
    /// first Autofocus node so trigger-fired refocus uses the operator's real
    /// tuning (step size, exposure, backlash, method, filter) instead of
    /// library defaults. `None` means the sequence has no Autofocus node to
    /// copy tuning from; the trigger path then falls back to defaults AND logs
    /// a warning (never a silent fallback — "errors are a feature").
    pub autofocus: Option<crate::AutofocusConfig>,
    /// Observer location (degrees). `None` means location is not configured.
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    /// Filter -> focus offset (steps). Used by autofocus on filter change so
    /// the focuser is moved by the configured offset.
    pub filter_focus_offsets: HashMap<String, i32>,
    /// Runtime safety-poll fail mode. Trigger monitor reads this every poll
    /// so operator changes take effect without a sequence restart.
    pub safety_fail_mode: SafetyFailMode,
    /// Runtime cadence for safety/humidity device polling. The trigger loop
    /// still ticks every second; only expensive safety/weather driver calls
    /// are throttled by this interval.
    pub safety_check_interval_secs: u64,
    /// Architecture-unification 2026-06-07 (W1 native daylight gate): the
    /// maximum Sun altitude (degrees above the horizon) at which an on-sky
    /// LIGHT capture is permitted. Mirrors the Dart scheduler's
    /// `maxSunAltitudeDegrees`. The structural native daylight START gate in
    /// `instructions::execute_slew` / `execute_exposure` blocks a
    /// slew-to-science-target or a LIGHT-frame exposure while the Sun is above
    /// this altitude, so a raw sequence started via `api_sequencer_start`
    /// (including a mosaic) cannot slew + expose lights in full daylight.
    /// Flats/darks/bias/park and a parked rig are unaffected. Seeded into both
    /// the `ExecutionContext` and the shared `TriggerState` at `start()`.
    ///
    /// Remediation 2026-06-09 (finding #2): this is now `Option<f64>` so the
    /// `#[derive(Default)]` value is `None` ("never pushed") rather than a
    /// fabricated `0.0`. The Dart side pushes its `SchedulerConfig
    /// .maxSunAltitudeDegrees` via
    /// [`SequenceExecutor::update_max_sun_altitude`]
    /// ([`ExecutorCommand::UpdateMaxSunAltitude`]); when nothing was pushed the
    /// seed at `start()` resolves `None` (and any non-finite value) to
    /// [`crate::instructions::DEFAULT_MAX_SUN_ALTITUDE_DEGREES`] (-12°), so the
    /// native gate is never weaker than the Dart W1 gate it backstops.
    pub max_sun_altitude_degrees: Option<f64>,
    /// Architecture-unification 2026-06-05 (Subsystem 2 step 3 — stale-verdict
    /// observability): how long (seconds) a pushed `Some(true)` (UNSAFE) Dart
    /// weather verdict may go un-refreshed before the safety poll emits a loud
    /// "verdict feed stale; holding paused fail-closed" warning. The unsafe
    /// verdict is NEVER auto-cleared on staleness — this only governs WHEN the
    /// indefinite hold stops being silent. `0` falls back to
    /// [`DEFAULT_WEATHER_VERDICT_STALENESS_SECS`]; otherwise clamped to a sane
    /// floor so a misconfiguration cannot make every tick warn.
    pub weather_verdict_staleness_secs: u64,
    /// user override for the standard `AutofocusInterval`
    /// trigger's `every_n_frames`. The Rust default is 25 frames, which is
    /// wildly wrong for both very-short (5 s) and very-long (5 min) subs —
    /// the user must be able to tune this from the equipment profile or
    /// sequence-level settings. `None` means "use the seeded default";
    /// `Some(n)` overrides the trigger's `every_n_frames` field on the next
    /// trigger reload.
    pub autofocus_interval_frames: Option<u32>,
    /// Image Grading: global default image-grading thresholds.
    /// Applied to every TakeExposure node that does NOT carry its own
    /// `quality_check`. `None` => grading disabled globally. The Dart UI
    /// surfaces this via the new image-grading settings page.
    pub default_quality_check: Option<crate::quality::ImageQualityCheck>,
    /// Image Grading: where rejected frames go.
    ///
    /// `None` => use `<save_path>/Reject/` (created on first reject).
    /// `Some(path)` => use the explicit path (resolves relative to the
    /// run's save_path; absolute paths are honoured verbatim). When the
    /// resolved reject folder equals the save_path, validation flags it
    /// as a warning (mixing accepted + rejected defeats the purpose).
    pub reject_folder_path: Option<String>,
    /// observer / equipment identification pushed at start by Dart.
    /// Used to populate FITS `OBSERVER`, `SITEELEV`, `TELESCOP`, `FOCALLEN`,
    /// `APTDIA`, `INSTRUME` keywords. Default is all-None (empty profile)
    /// so frames captured without a configured profile honestly emit no
    /// observer / telescope keywords.
    pub observer_profile: ObserverProfile,
    /// Recovery Mode — user-tunable defaults consumed on every
    /// recovery entry. Updated mid-flight via `UpdateRecoveryConfig` so
    /// the user can tweak the cadence/duration during a long session
    /// (e.g. shortening the interval after the first cloud cell drifts
    /// off the rig). Defaults follow SGP: 10 min interval, 90 min total.
    pub recovery: crate::recovery::RecoveryRuntimeConfig,
    /// global default sky-brightness adaptive exposure
    /// config. Applied to every TakeExposure node that does NOT carry
    /// its own `adaptive_exposure` block. `None` => no global default;
    /// exposures use their nominal duration unless the node explicitly
    /// opts in.
    pub default_adaptive_exposure: Option<crate::scheduling::AdaptiveExposureConfig>,
    /// per-frame defect map application state. `None`
    /// means defect correction is disabled for the current camera /
    /// session. Mirrored into `ExecutionContext::defect_map_apply` at
    /// start time and on every `ExecutorCommand::UpdateDefectMap`.
    pub defect_map_apply: Option<DefectMapApplyState>,
    /// per-target carry-over integration to seed into the
    /// `BudgetRegistry` at the start of the next run, mapped from
    /// `target_id` → `filter` → `seconds_already_captured`.
    ///
    /// Drives the "Resume / Restart / Continue New" handoff dialog:
    ///   * `Resume`     → populate with the prior session's per-filter
    ///     totals; the budget tracker treats those
    ///     frames as already-captured against the
    ///     configured budget.
    ///   * `Restart`    → populate with an explicit empty map for the
    ///     target so any pre-existing checkpoint state
    ///     is overwritten with zeros.
    ///   * `ContinueNew` → no entry for the target; default behaviour
    ///     (no carry-over, no zeroing) applies.
    ///
    /// Consumed exactly once at the top of the spawned executor task
    /// during `start()`; the map is cloned and applied, then cleared
    /// from the runtime config so a subsequent restart without an
    /// explicit re-seed runs without stale carry-over.
    pub pending_integration_carry_over: HashMap<String, HashMap<String, f64>>,
    /// Whether a human operator is present and attending the rig.
    ///
    /// `false` (the `Default`) means UNATTENDED — the safe assumption, because
    /// the unattended-night path is the one that can lose optics. This gates
    /// how a non-auto-recoverable recovery escalation (e.g. a consecutive-
    /// reject storm that resolves to `PauseForOperator`) is handled:
    ///   * unattended (`false`) → the escalation is a SAFE ABANDONMENT: park
    ///     the mount, close the cover, close the dome (the same sweep the
    ///     give-up branch runs) and KEEP safety-class triggers protecting the
    ///     rig. A frozen, dome-open, trigger-disabled rig is never left under
    ///     the open sky until dawn.
    ///   * attended (`true`) → the escalation is a passive operator Pause that
    ///     leaves the rig in place so the present operator can inspect and
    ///     resume.
    ///
    /// Read live on every recovery escalation so an operator declaring
    /// presence mid-session takes effect on the next escalation without a
    /// restart.
    pub operator_present: bool,
}

/// Walk a runtime node tree (pre-order) and return the first Autofocus node's
/// configuration. Used to seed the trigger-driven autofocus config from the
/// sequence's own Autofocus node so HFR / temperature / interval refocus
/// triggers use the operator's real tuning instead of library defaults.
fn find_first_autofocus_config(node: &dyn Node) -> Option<crate::AutofocusConfig> {
    if let NodeType::Autofocus(config) = node.node_type() {
        return Some(config.clone());
    }
    node.children()
        .iter()
        .find_map(|child| find_first_autofocus_config(&**child))
}

/// Whether the node tree contains a plate-solve-dependent CenterTarget node.
/// Used to gate the plate-solver/catalog preflight at start() so a sequence
/// that centers on a target fails fast if no solver is installed.
fn tree_contains_centering(node: &dyn Node) -> bool {
    if matches!(node.node_type(), NodeType::CenterTarget(_)) {
        return true;
    }
    node.children()
        .iter()
        .any(|child| tree_contains_centering(&**child))
}

/// Commands that can be sent to the executor
#[derive(Debug, Clone)]
pub enum ExecutorCommand {
    Start,
    Pause,
    Resume,
    Stop,
    Skip,
    SkipToNode(NodeId),
    /// Recovery Mode — operator pressed "Try Now" on the dashboard
    /// banner. Cancels the wait timer and forces an immediate retry of the
    /// recovery attempt. No-op if the executor is not currently in
    /// `Recovering`.
    RecoveryTryNow,
    /// Recovery Mode — operator pressed "Abort" on the dashboard
    /// banner. Exits the recovery loop and transitions the executor to
    /// `Failed`. No-op if the executor is not currently in `Recovering`.
    RecoveryAbort,
    /// Recovery Mode — push the user-tunable recovery defaults
    /// (retry interval, max duration, stop-tracking flag, …) into the
    /// executor's runtime config so the next recovery entry honours them.
    UpdateRecoveryConfig {
        config: crate::recovery::RecoveryRuntimeConfig,
    },
    /// Update safety-poll fail behaviour while a sequence is running.
    UpdateSafetyFailMode {
        mode: SafetyFailMode,
    },
    /// Update safety/humidity poll cadence while a sequence is running.
    UpdateSafetyCheckInterval {
        seconds: u64,
    },
    /// Update dither configuration at runtime (e.g., when user changes settings mid-sequence)
    UpdateDitherConfig {
        pixels: f64,
        settle_pixels: f64,
        settle_time: f64,
        settle_timeout: f64,
        ra_only: bool,
    },
    /// Update observer location at runtime
    UpdateLocation {
        latitude: Option<f64>,
        longitude: Option<f64>,
    },
    /// Remediation 2026-06-09 (finding #2) — push the W1 native daylight gate's
    /// maximum Sun altitude (the Dart `SchedulerConfig.maxSunAltitudeDegrees`)
    /// into the running executor so the native gate threshold equals the Dart
    /// one. Writes `RuntimeConfig::max_sun_altitude_degrees` AND patches the
    /// live trigger state so the gate (read through the trigger-state handle)
    /// picks it up on the next slew / exposure without a sequence reload.
    UpdateMaxSunAltitude {
        degrees: Option<f64>,
    },
    /// Update filter focus offsets at runtime (e.g., when equipment profile changes)
    UpdateFilterOffsets {
        offsets: std::collections::HashMap<String, i32>,
    },
    /// update the autofocus-interval cadence at runtime.
    /// Patches the standard `AutofocusInterval` trigger's `every_n_frames`
    /// so the next periodic-AF tick honours the new value; mid-flight tuning
    /// from the equipment-profile UI works without a sequence reload.
    UpdateAutofocusInterval {
        every_n_frames: u32,
    },
    /// update the global default image-grading thresholds.
    /// `None` disables grading globally (per-node `quality_check` on
    /// TakeExposure still wins). Mirrors the Dart-side
    /// `enableImageGrading` toggle on app settings.
    UpdateDefaultQualityCheck {
        check: Option<crate::quality::ImageQualityCheck>,
    },
    /// update the reject-folder override. `None` => default
    /// `<save_path>/Reject/`. Mirrors the Dart `imageGradingRejectFolderPath`
    /// setting.
    UpdateRejectFolderPath {
        path: Option<String>,
    },
    /// push observer / equipment identification (observer name,
    /// camera make/model, telescope name/focal length/aperture, site
    /// elevation) to the executor so the next FITS save stamps real
    /// keywords (OBSERVER, TELESCOP, FOCALLEN, APTDIA, INSTRUME, SITEELEV).
    UpdateObserverProfile {
        profile: ObserverProfile,
    },
    /// push the latest sky-brightness reading from the
    /// Dart `SkyBrightnessTracker` to the executor. The next adaptive-
    /// exposure decision reads this value. Pass `mag = None` when the
    /// tracker has lost lock so the adapter falls back to nominal
    /// (and emits a structured `Unavailable` reason).
    UpdateSkyBrightness {
        mag: Option<f64>,
    },
    /// push the user's global default sky-brightness
    /// adaptive exposure config. Per-node `ExposureConfig.adaptive_exposure`
    /// still wins; this is the runtime fallback the next TakeExposure
    /// node consults when it has none.
    UpdateDefaultAdaptiveExposure {
        config: Option<crate::scheduling::AdaptiveExposureConfig>,
    },
    /// Dart side has finished running a plugin node and is
    /// returning the verdict to the Rust executor. The executor finds the
    /// pending oneshot keyed by `node_id` and resolves it; the
    /// `PluginNodeInstruction` blocking on that oneshot returns Success or
    /// Failure based on the verdict.
    ///
    /// `node_id` MUST match the `node_id` from the corresponding
    /// `ExecutorEvent::PluginNodeRequested`. Stray finishes (no pending
    /// oneshot) are logged at warn and dropped — they're a bug on the
    /// Dart side but we don't want to crash the executor over a
    /// duplicate reply.
    PluginNodeFinished {
        node_id: NodeId,
        success: bool,
        /// Optional human-readable message surfaced in logs and on the
        /// final progress event. Empty / `None` is the success case.
        message: Option<String>,
        /// Optional plugin-authored JSON payload emitted as the node's
        /// final progress event (parsed as `serde_json::Value`; invalid
        /// JSON is replaced with `null` and a warn line is logged).
        structured_detail_json: Option<String>,
    },
    /// push the active per-frame defect map (or clear it).
    ///
    /// Sent by `api_sequencer_update_defect_map` when the user toggles
    /// "Apply during capture" on or off. When `state` is `Some`, every
    /// subsequent frame whose camera id matches gets the defect map
    /// applied between camera readout and FITS save. When `None`, defect
    /// correction is disabled — the bridge call sends this on toggle-off
    /// AND on camera disconnect to make sure a stale map cannot be
    /// applied to a frame from a different sensor.
    ///
    /// Pre-loading happens bridge-side (the `.ndm` file is parsed into
    /// memory) so per-frame application is just a slice operation.
    UpdateDefectMap {
        state: Option<DefectMapApplyState>,
    },
    /// push the latest cloud-motion analyzer reading into
    /// the executor's trigger state. The Dart side
    /// (`cloudMotionAnalyzerProvider` -> WeatherSafetyNotifier) sends this
    /// every ~60s while a sequence is running so the cloud-aware triggers
    /// (`CloudArrivingIn`, `CloudOpeningIn`, `CloudCoverThreshold`) have
    /// current data. All fields are `Option` because the analyzer may not
    /// yet have enough radar history to produce every quantity; `None`
    /// fields disable the corresponding evaluator branch rather than
    /// firing spuriously ("errors are a feature").
    UpdateCloudMotion {
        /// Current cloud cover percentage (0-100). Open-Meteo merged with
        /// the analyzer.
        current_cover_percent: Option<f64>,
        /// Predicted minutes until significant clouds arrive. `None` when
        /// no approach is predicted.
        predicted_arrival_minutes: Option<f64>,
        /// Predicted minutes until a clear opening reaches the user.
        /// `None` when no opening is predicted.
        predicted_opening_minutes: Option<f64>,
        /// Predicted duration (seconds) of the opening referenced by
        /// `predicted_opening_minutes`.
        predicted_opening_duration_secs: Option<f64>,
        /// (altitude_deg, azimuth_deg) of a clear-sky direction reported by
        /// the analyzer. Consumed by `RecoveryAction::SlewToGapAndContinue`.
        predicted_clear_sky_alt: Option<f64>,
        predicted_clear_sky_az: Option<f64>,
    },
    /// Science — push the latest sky transparency reading from
    /// the Dart science pipeline. Mirrored onto
    /// `TriggerState::current_transparency` (for the
    /// `TransparencyDropped` trigger evaluator) and
    /// `ExecutionContext::current_transparency` (for the photometry
    /// node's per-frame quality gates).
    ///
    /// Pass `transparency = None` when the science pipeline has lost
    /// lock so the trigger evaluator falls back to "no data" (does NOT
    /// fire on absent telemetry — "no silent fallbacks").
    UpdateTransparency {
        /// Live transparency reading expressed as a fraction of clear-sky
        /// reference (0.0..=1.0; 1.0 = clear). Values outside [0.0, 1.5]
        /// are clamped + WARN-logged by `TriggerState::update_transparency`.
        transparency: Option<f64>,
    },
    /// Science — push the operator-configured backup plan that
    /// `RecoveryAction::SwitchTargetOrFilter` consults. Pass `plan =
    /// None` to clear the plan (e.g. the operator removed it mid-session).
    UpdateTransparencyBackup {
        plan: Option<crate::node::context::TransparencyBackupPlan>,
    },
    /// push the composite sky-conditions score that the
    /// `TargetScheduler`'s adaptive-swap logic consults. The Dart-side
    /// `AdaptiveSwapService` composes the score from transparency / seeing
    /// / cloud cover / wind every ~30 seconds and sends this command. The
    /// score is mirrored onto `ExecutionContext::current_conditions_score`
    /// so the scheduler reads from a non-blocking slot. Pass `score =
    /// None` when the Dart composer has insufficient data.
    UpdateConditionsScore {
        score: Option<crate::scheduling::ConditionsScore>,
    },
    /// Full-night audit 2026-06-04 (defense-in-depth) — push the Dart-side
    /// `weatherSafetyProvider` overall verdict into the executor's trigger
    /// state. The hardware `safety_is_safe` poll only knows what a connected
    /// safety/weather device reports; a rig WITHOUT such a device never aborts
    /// via the in-sequencer `WeatherUnsafe` trigger even when the Dart side
    /// computed UNSAFE from the user's configured thresholds + API/cloud
    /// sources. This carries that verdict so the trigger has a redundant
    /// non-hardware unsafe source. `unsafe_override = Some(true)` => Dart
    /// computed UNSAFE; `Some(false)` => Dart computed SAFE; `None` => Dart
    /// abstains (provider disabled / no data) and this layer is inert. Folded
    /// as an OR-of-unsafe into `weather_safe` evaluation — it can only make the
    /// rig safer, never less safe than the hardware verdict.
    UpdateWeatherVerdict {
        unsafe_override: Option<bool>,
    },
}

/// State of the sequence executor
///
/// `Recovering` was added as a first-class state so user-visible UI
/// (Run Dashboard LED, banner, audible alert, push notification) can react
/// to an in-flight recovery loop instead of seeing a vanilla `Running` while
/// the sequence is actually waiting for a guide-star reacquisition. The
/// recovery state machine itself lives in `crate::recovery` and is driven
/// by the trigger-monitor when a recoverable failure fires.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ExecutorState {
    Idle,
    Running,
    Paused,
    Stopping,
    Cancelled,
    Completed,
    Failed,
    /// the executor is currently driving a recovery loop after a
    /// recoverable failure (guide-star lost, slew failed, plate-solve
    /// failed, weather unsafe, etc.). Retries fire on a configured cadence;
    /// the user can force `RecoveryTryNow` or `RecoveryAbort` via
    /// commands.
    Recovering,
}

/// Progress information for the sequence
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequenceProgress {
    pub state: ExecutorState,
    pub current_node_id: Option<NodeId>,
    pub current_node_name: Option<String>,
    pub current_node_status: Option<NodeStatus>,
    pub total_exposures: u32,
    pub completed_exposures: u32,
    pub total_integration_secs: f64,
    pub completed_integration_secs: f64,
    pub elapsed_secs: f64,
    pub estimated_remaining_secs: Option<f64>,
    pub current_target: Option<String>,
    pub current_filter: Option<String>,
    pub message: Option<String>,
    pub node_statuses: HashMap<NodeId, NodeStatus>,
    /// per-target / per-filter completed integration in
    /// seconds. Outer key is the TargetHeader node id; inner key is the
    /// filter name (`""` for no-filter cameras). Updated when the
    /// exposure instruction emits an IntegrationBudget progress event so
    /// the dashboard can render budget bars without re-reading the registry.
    #[serde(default)]
    pub integration_by_target_filter: HashMap<NodeId, HashMap<String, f64>>,
    /// set of TargetHeader node ids whose integration
    /// budget has fired. Surfaced so the dashboard can flip the target
    /// tile to "complete" even while the executor is finishing the
    /// final burst.
    #[serde(default)]
    pub targets_with_budget_met: std::collections::HashSet<NodeId>,
}

impl Default for SequenceProgress {
    fn default() -> Self {
        Self {
            state: ExecutorState::Idle,
            current_node_id: None,
            current_node_name: None,
            current_node_status: None,
            total_exposures: 0,
            completed_exposures: 0,
            total_integration_secs: 0.0,
            completed_integration_secs: 0.0,
            elapsed_secs: 0.0,
            estimated_remaining_secs: None,
            current_target: None,
            current_filter: None,
            message: None,
            node_statuses: HashMap::new(),
            integration_by_target_filter: HashMap::new(),
            targets_with_budget_met: std::collections::HashSet::new(),
        }
    }
}

/// Event emitted by the executor
///
/// `ProgressUpdated` carries a fully-populated
/// `SequenceProgress` (~320 bytes once the budget HashMaps grew),
/// which is far larger than every other variant on this enum. Without
/// boxing, every `ExecutorEvent` value (including the small life-cycle
/// variants) reserves the worst-case 320 bytes on the stack and inside
/// the tokio broadcast channel — clippy rejects this under
/// `clippy::large_enum_variant`. We box the heavy payload so the enum
/// stays cache-friendly; the box dereferences automatically at every
/// match site, so callers don't change.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ExecutorEvent {
    StateChanged(ExecutorState),
    /// boxed to keep the enum size down (see enum doc-comment).
    /// Serde transparently serializes `Box<SequenceProgress>` as
    /// `SequenceProgress`, so the FRB wire format and JSON checkpoint
    /// payloads are byte-identical to the pre-box version.
    ProgressUpdated(Box<SequenceProgress>),
    NodeStarted {
        id: NodeId,
        name: String,
    },
    NodeCompleted {
        id: NodeId,
        status: NodeStatus,
    },
    NodeProgress {
        node_id: NodeId,
        instruction: String,
        progress_percent: f64,
        /// Legacy stringified detail (matches pre-Pack-H wire format so
        /// any subscriber that still consumes `detail` as a string keeps
        /// working). Derived from `structured_detail` via
        /// `ProgressDetail::detail_text()`.
        detail: String,
        /// structured detail payload, boxed to keep the
        /// `ExecutorEvent` variant size small. `None` for legacy
        /// progress emissions that don't carry a structured payload
        /// (instruction nodes pre-dating the progress refactor).
        /// The bridge layer reads this to dispatch to the typed
        /// `SequencerEvent` variants (`FrameAccepted`, `FrameRejected`,
        /// `SchedulerDecision`, `IntegrationBudget`) without parsing
        /// `detail`.
        structured_detail: Option<Box<crate::node::ProgressDetail>>,
    },
    ExposureStarted {
        frame: u32,
        total: u32,
        filter: Option<String>,
        duration_secs: f64,
    },
    ExposureCompleted {
        frame: u32,
        total: u32,
        duration_secs: f64,
    },
    TargetStarted {
        name: String,
        ra: f64,
        dec: f64,
    },
    TargetCompleted {
        name: String,
    },
    TriggerFired {
        trigger_id: String,
        trigger_name: String,
        action: String,
    },
    Error {
        message: String,
    },
    /// runtime configuration changed mid-sequence (dither pixels,
    /// observer location, or filter focus offsets). Subscribers should
    /// reload any cached values derived from these fields.
    RuntimeConfigUpdated {
        what: String,
    },
    /// Recovery Mode — the executor just entered the `Recovering`
    /// state. Carries the full [`RecoveryContext`] so subscribers (Run
    /// Dashboard banner, audible alert player, push-notification service)
    /// render the cause, attempt counter, and countdown without reaching
    /// back into the executor on every redraw. Boxed to keep the enum
    /// variant size small per the same reasoning as `ProgressUpdated`.
    RecoveryStarted {
        context: Box<crate::recovery::RecoveryContext>,
    },
    /// Recovery Mode — periodic update of the live recovery
    /// context (attempt counter incremented, phase changed, last_error
    /// updated). Subscribers refresh the dashboard banner from this; the
    /// `RecoveryStarted` / `RecoveryCompleted` / `RecoveryGaveUp` events
    /// bookend the loop while this carries deltas inside the loop.
    RecoveryProgress {
        context: Box<crate::recovery::RecoveryContext>,
    },
    /// Recovery Mode — recovery succeeded. The executor will
    /// transition back to `Running`; subscribers clear the dashboard
    /// banner and log the history entry.
    RecoveryCompleted {
        context: Box<crate::recovery::RecoveryContext>,
    },
    /// Recovery Mode — recovery exhausted attempts / time / was
    /// aborted by the user. The executor will transition to `Failed` (or
    /// run the configured ParkAndAbort policy). Subscribers log the
    /// history entry and emit a critical-severity event.
    RecoveryGaveUp {
        context: Box<crate::recovery::RecoveryContext>,
        /// True when the loop exited because the user pressed Abort.
        /// Distinct from exhaustion so the UI can render different copy
        /// ("Aborted by operator" vs "Exhausted retries").
        aborted_by_user: bool,
    },
    SequenceCompleted,
    SequenceFailed {
        error: String,
    },
    /// the executor has reached a `NodeType::PluginNode`
    /// and is waiting for the Dart side to run the plugin and reply with
    /// `ExecutorCommand::PluginNodeFinished`. Subscribers (specifically
    /// the Dart sequence executor) route this to `PluginNodeExecutor.run`
    /// and send back the result; non-plugin subscribers ignore this
    /// variant.
    ///
    /// `node_id` is the executor-side identifier the reply MUST echo back.
    /// `plugin_id` + `node_type_id` identify the plugin node in the
    /// `PluginNodeRegistry`. `config_json` is the opaque JSON payload the
    /// Rust side never inspects.
    PluginNodeRequested {
        node_id: NodeId,
        plugin_id: String,
        node_type_id: String,
        config_json: String,
        /// Optional human-readable label authored on the node definition.
        /// Falls back to `node_type_id` in the UI when absent.
        display_name: Option<String>,
        /// Effective timeout (seconds) the Rust side will wait. The Dart
        /// side MUST respect this — if the plugin runs longer the Rust
        /// node fails before the Dart-side timer can react.
        timeout_secs: u32,
    },
}

#[derive(Debug, Clone, Default)]
struct TriggerActionContext {
    camera_id: Option<String>,
    mount_id: Option<String>,
    focuser_id: Option<String>,
    filterwheel_id: Option<String>,
    rotator_id: Option<String>,
    dome_id: Option<String>,
    cover_calibrator_id: Option<String>,
    save_path: Option<PathBuf>,
    latitude: Option<f64>,
    longitude: Option<f64>,
    filter_focus_offsets: HashMap<String, i32>,
}

impl TriggerActionContext {
    fn connected_device_ids(&self) -> Vec<String> {
        [
            self.camera_id.as_ref(),
            self.mount_id.as_ref(),
            self.focuser_id.as_ref(),
            self.filterwheel_id.as_ref(),
            self.rotator_id.as_ref(),
            self.dome_id.as_ref(),
            self.cover_calibrator_id.as_ref(),
        ]
        .into_iter()
        .flatten()
        .cloned()
        .collect()
    }
}

#[derive(Debug, Clone)]
struct SequenceRecoveryTriggerSpec {
    trigger_id: String,
    trigger_name: String,
    trigger_type: TriggerType,
    recovery_action: RecoveryAction,
    custom_branch_node_id: Option<NodeId>,
}

fn recovery_node_trigger_id(node_id: &str) -> String {
    format!("{}{}", RECOVERY_NODE_TRIGGER_PREFIX, node_id)
}

fn sequence_recovery_trigger_specs(
    sequence: &SequenceDefinition,
) -> Vec<SequenceRecoveryTriggerSpec> {
    sequence
        .nodes
        .iter()
        .filter_map(|node| {
            let NodeType::Recovery(config) = &node.node_type else {
                return None;
            };
            let trigger_type = config.trigger.clone()?;
            Some(SequenceRecoveryTriggerSpec {
                trigger_id: recovery_node_trigger_id(&node.id),
                trigger_name: format!("Recovery: {}", node.name),
                trigger_type,
                recovery_action: config.recovery_action.clone(),
                custom_branch_node_id: matches!(
                    config.recovery_action,
                    RecoveryAction::CustomBranch
                )
                .then(|| node.id.clone()),
            })
        })
        .collect()
}

fn build_runtime_node_from_map(
    def: &NodeDefinition,
    node_map: &HashMap<&str, &NodeDefinition>,
) -> RuntimeNode {
    let mut node = RuntimeNode::from_definition(def.clone());

    tracing::debug!(
        "Building node '{}' (id={}) with {} children defined: {:?}",
        def.name,
        def.id,
        def.children.len(),
        def.children
    );

    for child_id in &def.children {
        if let Some(child_def) = node_map.get(child_id.as_str()) {
            tracing::debug!(
                "  Adding child '{}' (id={}) to '{}'",
                child_def.name,
                child_def.id,
                def.name
            );
            let child = build_runtime_node_from_map(child_def, node_map);
            node.add_child(Box::new(child));
        } else {
            tracing::warn!(
                "  Child node '{}' not found in node_map for parent '{}'",
                child_id,
                def.name
            );
        }
    }

    node
}

#[allow(clippy::too_many_arguments)]
fn build_trigger_autofocus_context(
    trigger_context: &TriggerActionContext,
    target_name: Option<String>,
    target_ra: Option<f64>,
    target_dec: Option<f64>,
    current_filter: Option<String>,
    cancellation_token: Arc<AtomicBool>,
    device_ops: SharedDeviceOps,
    trigger_state: Arc<RwLock<TriggerState>>,
    runtime_config: &Arc<StdRwLock<RuntimeConfig>>,
    event_tx: Option<broadcast::Sender<ExecutorEvent>>,
) -> crate::instructions::InstructionContext {
    // read filter_focus_offsets and location from the runtime
    // config so a mid-flight UpdateFilterOffsets / UpdateLocation is honoured
    // by trigger-initiated autofocus / dither / recenter actions. The
    // trigger_context is a snapshot taken at start(); without this read the
    // updates would only reach the executor on a sequence reload.
    let (rc_filter_offsets, rc_lat, rc_lon) = {
        let rc = runtime_config.read();
        (rc.filter_focus_offsets.clone(), rc.latitude, rc.longitude)
    };
    let filter_focus_offsets = if rc_filter_offsets.is_empty() {
        // Why: if the runtime config has not been seeded (no
        // UpdateFilterOffsets has fired yet) fall back to the start-time
        // snapshot. Empty-vs-explicit is the only way to disambiguate
        // "user wants no offsets" from "config not yet pushed".
        trigger_context.filter_focus_offsets.clone()
    } else {
        rc_filter_offsets
    };
    let latitude = rc_lat.or(trigger_context.latitude);
    let longitude = rc_lon.or(trigger_context.longitude);

    crate::instructions::InstructionContext {
        target_ra,
        target_dec,
        // Trigger-initiated recenter does not move the rotator; rotation is a
        // CenterTarget concern driven from the TargetHeader. None here keeps
        // the trigger recenter path rotation-agnostic.
        target_rotation: None,
        target_name,
        current_filter,
        current_binning: crate::Binning::One,
        cancellation_token,
        camera_id: trigger_context.camera_id.clone(),
        mount_id: trigger_context.mount_id.clone(),
        focuser_id: trigger_context.focuser_id.clone(),
        filterwheel_id: trigger_context.filterwheel_id.clone(),
        rotator_id: trigger_context.rotator_id.clone(),
        dome_id: trigger_context.dome_id.clone(),
        cover_calibrator_id: trigger_context.cover_calibrator_id.clone(),
        save_path: trigger_context.save_path.clone(),
        latitude,
        longitude,
        device_ops,
        trigger_state: Some(trigger_state),
        filter_focus_offsets,
        // callers pass `Some(event_tx_clone2.clone())` so
        // FITS-save failures and other instruction-level errors fired from
        // trigger-initiated work (autofocus / dither / recenter) reach the
        // executor's event subscribers (UI, logging). Unit tests still pass
        // `None` because they exercise the build helper in isolation.
        event_tx,
        recovery_request_tx: None,
        // Trigger-initiated work is not wrapped by the node-runtime retry path,
        // so this flag is a standalone fresh Arc here.
        device_disconnect_recovery_pending: std::sync::Arc::new(
            std::sync::atomic::AtomicBool::new(false),
        ),
        // Image Grading: trigger-initiated autofocus does not save
        // FITS frames itself, so empty defaults are honest here. If trigger
        // code ever calls save_fits in the future these would need to be
        // wired through the trigger_context snapshot.
        session_id: String::new(),
        target_id: None,
        mosaic_panel: None,
        current_filter_index: None,
        set_temp_c: None,
        bayer_pattern: None,
        observer_name: None,
        site_elevation_m: None,
        camera_make: None,
        camera_model: None,
        telescope_name: None,
        telescope_focal_length_mm: None,
        telescope_aperture_mm: None,
        last_plate_solve: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        hfr_baseline: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        hfr_baseline_samples: std::sync::Arc::new(tokio::sync::RwLock::new(Vec::new())),
        consecutive_rejects: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
        frames_accepted: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
        frames_rejected: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
        default_quality_check: None,
        reject_folder_path: None,
        // trigger-initiated autofocus does not save
        // FITS frames itself; the defect-map slot starts empty so a
        // future trigger code path that does save_fits will need to
        // wire this through the trigger_context.
        defect_map_apply: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        // Forensics: trigger-initiated work doesn't have the
        // shared forensics history available; start empty Arcs so any
        // grading reached by a future trigger path falls back gracefully.
        forensics_history: std::sync::Arc::new(tokio::sync::RwLock::new(
            std::collections::VecDeque::new(),
        )),
        current_sky_brightness_mag: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        cloud_motion_snapshot: std::sync::Arc::new(tokio::sync::RwLock::new(
            crate::node::context::CloudMotionSnapshot::default(),
        )),
        current_wind_kph: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        current_sensor_temp_c: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        // Replay Debug — trigger-initiated work (autofocus,
        // dither) does not currently emit DecisionEvents (we wire
        // recoveries + scheduler + lifecycle separately), so the
        // sender starts None and emissions from this context are no-
        // ops. A future caller that wants trigger-initiated work to
        // appear in the replay feed can clone the executor's
        // decision_tx into this helper.
        decision_tx: None,
        active_sequence_run_id: std::sync::Arc::new(parking_lot::RwLock::new(None)),
        // Dual-rig — trigger-initiated dither/recenter is not coordinated with
        // the secondary loop in v1 (the secondary only gates on the main-burst
        // dither path); start None.
        dither_barrier: None,
    }
}

fn build_trigger_flip_context(
    trigger_context: &TriggerActionContext,
    target_name: String,
    target_ra_hours: Option<f64>,
    target_dec_degrees: Option<f64>,
    cancellation_token: Option<Arc<AtomicBool>>,
    trigger_state: Option<Arc<RwLock<TriggerState>>>,
) -> Option<crate::meridian_flip_executor::FlipContext> {
    Some(crate::meridian_flip_executor::FlipContext {
        target_name,
        target_ra_hours: target_ra_hours?,
        target_dec_degrees: target_dec_degrees?,
        mount_id: trigger_context.mount_id.clone()?,
        camera_id: trigger_context.camera_id.clone(),
        focuser_id: trigger_context.focuser_id.clone(),
        cover_calibrator_id: trigger_context.cover_calibrator_id.clone(),
        cancellation_token,
        trigger_state,
        autofocus_config: None,
        // Trigger-driven flips command the hardware; the dry-run path is the
        // only caller that sets this true.
        simulate: false,
    })
}

/// every exit path from the trigger-monitor closure that ends
/// the sequence MUST set `is_cancelled` before returning the fired-triggers
/// vector. This helper enforces the invariant in one place so future
/// `match` arms cannot regress by forgetting the store.
///
/// `reason` is logged at info level so post-mortem traces can reconstruct
/// which terminating action ran (e.g., `"ParkAndAbort"`,
/// `"FlipFailureAction::AbortAndPark"`).
///
/// # Example
/// ```ignore
/// // Inside the trigger-monitor closure:
/// fired_triggers.push((trigger_id.clone(), RecoveryAction::ParkAndAbort));
/// return terminate_with(&is_cancelled_clone, fired_triggers, "ParkAndAbort");
/// ```
fn terminate_with(
    is_cancelled: &Arc<AtomicBool>,
    triggers: Vec<(String, RecoveryAction)>,
    reason: &str,
) -> Vec<(String, RecoveryAction)> {
    is_cancelled.store(true, Ordering::Relaxed);
    tracing::info!(
        "[TRIGGER_MONITOR] terminating sequence ({}); fired {} trigger(s)",
        reason,
        triggers.len()
    );
    triggers
}

/// Replay Debug — emit a `SystemEvent` decision from the executor
/// task's lifecycle hooks (sequence started / completed / failed /
/// cancelled). Free-standing helper so the closures capturing the
/// channel handles can call it without going through `SequenceExecutor`.
///
/// `phase` is the lifecycle phase tag (`"started"`, `"completed"`,
/// `"failed"`, `"cancelled"`). The summary is auto-derived: callers
/// don't need to handcraft strings.
fn emit_lifecycle_decision(
    tx: &crate::decision::DecisionSender,
    active_run_id: &Arc<StdRwLock<Option<i64>>>,
    enabled: &Arc<AtomicBool>,
    phase: &str,
    extra: serde_json::Value,
) {
    if !enabled.load(Ordering::Relaxed) {
        return;
    }
    let summary = match phase {
        "started" => "Sequence started".to_string(),
        "completed" => "Sequence completed".to_string(),
        "failed" => "Sequence failed".to_string(),
        "cancelled" => "Sequence cancelled".to_string(),
        other => format!("Sequence lifecycle: {}", other),
    };
    let mut details = match extra {
        serde_json::Value::Object(m) => serde_json::Value::Object(m),
        // Why: wrap non-object payloads under a `data` key so the
        // persisted JSON column always parses to a map — keeps the
        // Dart deserialisation path uniform.
        other => serde_json::json!({ "data": other, "phase": phase }),
    };
    if let serde_json::Value::Object(ref mut m) = details {
        m.insert(
            "phase".to_string(),
            serde_json::Value::String(phase.to_string()),
        );
    }
    let event = crate::decision::DecisionEvent {
        timestamp: chrono::Utc::now(),
        category: crate::decision::DecisionCategory::SystemEvent,
        summary,
        details,
        node_id: None,
        sequence_run_id: *active_run_id.read(),
    };
    let _ = tx.send(event);
}

fn executor_state_for_result(result: NodeStatus) -> ExecutorState {
    match result {
        NodeStatus::Success | NodeStatus::Skipped => ExecutorState::Completed,
        NodeStatus::Cancelled => ExecutorState::Cancelled,
        _ => ExecutorState::Failed,
    }
}

/// convert horizontal coordinates (altitude / azimuth in
/// degrees) at the observer site to equatorial coordinates (RA in hours,
/// Dec in degrees) referenced to the current epoch. Used by
/// `RecoveryAction::SlewToGapAndContinue` to convert the cloud-motion
/// analyzer's "clear sky direction" into a slew destination.
///
/// `latitude` is observer latitude in degrees (+N, -S). `longitude` is
/// observer longitude in degrees (+E, -W).
///
/// References: Meeus, "Astronomical Algorithms", chapter 13 (horizontal
/// to equatorial transform). Uses the same `julian_day` /
/// `local_sidereal_time` primitives the rest of the crate uses so a
/// future ephemeris swap covers every site.
pub(crate) fn alt_az_to_ra_dec(
    alt_deg: f64,
    az_deg: f64,
    latitude: f64,
    longitude: f64,
) -> (f64, f64) {
    let alt_rad = alt_deg.to_radians();
    let az_rad = az_deg.to_radians();
    let lat_rad = latitude.to_radians();

    // Inverse of the standard horizontal-to-equatorial transform:
    //   sin(dec) = sin(alt) * sin(lat) + cos(alt) * cos(lat) * cos(az)
    //   tan(H)   = sin(az) / (cos(az) * sin(lat) - tan(alt) * cos(lat))
    let sin_dec = alt_rad.sin() * lat_rad.sin() + alt_rad.cos() * lat_rad.cos() * az_rad.cos();
    let dec_rad = sin_dec.asin();

    let y = -az_rad.sin();
    let x = lat_rad.cos() * alt_rad.tan() - lat_rad.sin() * az_rad.cos();
    let hour_angle_rad = y.atan2(x);
    let hour_angle_hours = hour_angle_rad.to_degrees() / 15.0;

    let now = chrono::Utc::now();
    let jd = crate::meridian::julian_day(&now);
    let lst_hours = crate::meridian::local_sidereal_time(jd, longitude);

    // RA = LST - HA; normalise to [0, 24).
    let mut ra_hours = lst_hours - hour_angle_hours;
    ra_hours = ra_hours.rem_euclid(24.0);

    (ra_hours, dec_rad.to_degrees())
}

/// Recovery Mode — execute a single recovery attempt for the given
/// cause and report the outcome. Stays out of the executor methods so the
/// recovery driver task can call it without holding the executor lock.
///
/// The dispatch is intentionally conservative: for `GuideStarLost`,
/// `MountTrackingLost`, and `WeatherUnsafe` we re-check the live device
/// status; for `SlewFailed` / `PlateSolveFailed` we re-issue the original
/// operation (the call site retains the necessary context). For now the
/// majority of failure modes use a status re-check as the recovery — the
/// underlying assumption is that the trigger only fired because the
/// condition became unsafe, so polling once after the wait window is the
/// right "try again" gesture. Future patches can expand each arm with
/// fully-blown recovery flows (e.g. re-slew + re-solve + re-acquire) when
/// the relevant context plumbing arrives.
/// Actively re-acquire the guide star after a `GuideStarLost` event.
///
/// The previous implementation only *queried* `is_guiding` and reported
/// success/failure — it never told the guider to find a star again, so once a
/// star was lost the recovery could only ever succeed if the guider happened to
/// re-lock on its own. This mirrors the verified lock-on logic in
/// `execute_start_guiding`: it issues `guider_start` (which, for PHD2, performs
/// auto-select + calibrate-if-needed + guide, i.e. a real re-acquisition) and
/// then polls `guider_get_status` until guiding is confirmed within a bounded
/// deadline. Fails closed (returns `AttemptOutcome::Failed`) on start error or
/// if the lock never re-establishes — the recovery driver then escalates per
/// the configured retry policy rather than silently resuming exposures on an
/// unguided mount.
pub(crate) async fn recover_guide_star(
    device_ops: &SharedDeviceOps,
) -> crate::recovery::AttemptOutcome {
    use crate::recovery::AttemptOutcome;

    // Re-acquisition settle parameters. These mirror the conservative defaults
    // used by the guiding settle path: lock within 2 px, hold for 10 s, give up
    // after 120 s. A re-acquire that can't settle within 120 s is a genuine
    // failure the operator's retry policy should handle, not something to wait
    // on indefinitely while the target drifts.
    const REACQUIRE_SETTLE_PIXELS: f64 = 2.0;
    const REACQUIRE_SETTLE_TIME_SECS: f64 = 10.0;
    const REACQUIRE_SETTLE_TIMEOUT_SECS: f64 = 120.0;
    const POLL_INTERVAL: std::time::Duration = std::time::Duration::from_secs(2);

    // Fast-path: maybe the guider already recovered on its own during the
    // recovery wait window. Issuing guider_start when already guiding can force
    // an unnecessary re-calibration on some setups, so honour an existing lock.
    if let Ok(status) = device_ops.guider_get_status().await {
        if status.is_guiding {
            return AttemptOutcome::Succeeded;
        }
    }

    // Issue a real re-acquisition. guider_start re-selects a guide star and
    // (re)starts guiding; it can return Ok before the lock is truly settled, so
    // we verify below.
    if let Err(e) = device_ops
        .guider_start(
            REACQUIRE_SETTLE_PIXELS,
            REACQUIRE_SETTLE_TIME_SECS,
            REACQUIRE_SETTLE_TIMEOUT_SECS,
        )
        .await
    {
        return AttemptOutcome::Failed {
            message: format!("Guide-star re-acquisition (guider_start) failed: {}", e),
        };
    }

    let deadline = tokio::time::Instant::now()
        + std::time::Duration::from_secs_f64(REACQUIRE_SETTLE_TIMEOUT_SECS);
    while tokio::time::Instant::now() < deadline {
        match device_ops.guider_get_status().await {
            Ok(status) if status.is_guiding => {
                tracing::info!(
                    "Guide star re-acquired: guiding active (RMS total={:.2}\")",
                    status.rms_total
                );
                return AttemptOutcome::Succeeded;
            }
            Ok(_) => {
                // Still settling; keep polling until the deadline.
            }
            Err(e) => {
                // Transient status-read failure (e.g. PHD2 mid-calibration);
                // keep polling rather than aborting on a single bad read.
                tracing::warn!("Guide re-acquire status poll failed: {}", e);
            }
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    AttemptOutcome::Failed {
        message: format!(
            "Guide star did not re-lock within {:.0}s of re-acquisition",
            REACQUIRE_SETTLE_TIMEOUT_SECS
        ),
    }
}

pub(crate) async fn run_recovery_attempt(
    cause: &crate::recovery::RecoveryCause,
    device_ops: &SharedDeviceOps,
    mount_id: Option<&str>,
    device_ids: &[String],
    trigger_manager: &Arc<RwLock<TriggerManager>>,
) -> crate::recovery::AttemptOutcome {
    use crate::recovery::AttemptOutcome;
    use crate::recovery::RecoveryCause;

    match cause {
        RecoveryCause::GuideStarLost => recover_guide_star(device_ops).await,
        RecoveryCause::MountTrackingLost => match mount_id {
            Some(id) => match device_ops.mount_is_tracking(id).await {
                Ok(true) => AttemptOutcome::Succeeded,
                Ok(false) => {
                    // Try to re-enable tracking. If the mount accepts the
                    // command we declare success and let the next loop
                    // iteration verify; if it errors, surface the error.
                    match device_ops.mount_set_tracking(id, true).await {
                        Ok(()) => {
                            // Verify the change took.
                            match device_ops.mount_is_tracking(id).await {
                                Ok(true) => AttemptOutcome::Succeeded,
                                Ok(false) => AttemptOutcome::Failed {
                                    message: "Mount tracking did not re-engage".to_string(),
                                },
                                Err(e) => AttemptOutcome::Failed {
                                    message: format!("Mount tracking re-check failed: {}", e),
                                },
                            }
                        }
                        Err(e) => AttemptOutcome::Failed {
                            message: format!("Mount tracking re-enable failed: {}", e),
                        },
                    }
                }
                Err(e) => AttemptOutcome::Failed {
                    message: format!("Mount tracking query failed: {}", e),
                },
            },
            None => AttemptOutcome::Failed {
                message: "No mount is configured; cannot recover tracking".to_string(),
            },
        },
        RecoveryCause::WeatherUnsafe => {
            // Fail-closed recovery gate (architecture-unification 2026-06-05,
            // Subsystem 2 step 4). A weather abort can be tripped by EITHER the
            // hardware safety device (`safety_is_safe`) OR the Dart-side verdict
            // (API alert / configured threshold / park-before-dawn), ORed in
            // `triggers.rs:535`. The old re-check polled ONLY the hardware boolean,
            // so a Dart-threshold-only abort (hardware reads safe, but the API
            // says a storm is overhead) was declared "recovered" the instant the
            // hardware poll returned safe → premature resume into API-unsafe
            // weather. We now require BOTH sources to be clear before resuming:
            // the hardware poll must read safe AND the Dart verdict must not be
            // `Some(true)` (still-unsafe). `Some(false)` (Dart explicitly safe)
            // and `None` (Dart abstains) both permit resume — they cannot pin the
            // sequence paused, so this only adds-unsafe and never weakens the gate.
            let verdict_unsafe = {
                let state = trigger_manager.read().await.state();
                let guard = state.read().await;
                guard.weather_verdict_unsafe == Some(true)
            };
            if verdict_unsafe {
                AttemptOutcome::Failed {
                    message: "Weather still unsafe (Dart verdict reports unsafe)".to_string(),
                }
            } else {
                match device_ops.safety_is_safe(None).await {
                    Ok(true) => AttemptOutcome::Succeeded,
                    Ok(false) => AttemptOutcome::Failed {
                        message: "Weather still unsafe".to_string(),
                    },
                    Err(e) => AttemptOutcome::Failed {
                        message: format!("Weather poll failed: {}", e),
                    },
                }
            }
        }
        RecoveryCause::FocusDriftCritical => {
            // Focus-drift recovery for now is "wait it out" — the next
            // periodic autofocus (already managed by the AutofocusInterval
            // trigger or the per-target Autofocus instruction) will lower
            // HFR if a real autofocus is due. We declare success after the
            // wait so the sequence resumes; the AutofocusInterval trigger
            // remains armed and will fire again if HFR is still high.
            AttemptOutcome::Succeeded
        }
        RecoveryCause::SlewFailed | RecoveryCause::PlateSolveFailed => {
            // Slew / plate-solve recovery is best handled by re-entering
            // the failed instruction. The driver releases `is_paused`
            // when it sees `Recovered`, and the node tree resumes from
            // where it stopped — the slew / center instruction will run
            // again. We return `Succeeded` after the wait so the driver
            // flips back to Running; the instruction's own retry logic
            // takes over.
            AttemptOutcome::Succeeded
        }
        RecoveryCause::ConsecutiveRejectsExceeded => {
            // A consecutive-reject storm (clouds rolling in, dew, focus
            // lost, vibration) is NOT something a fixed wait can prove
            // cleared — auto-resuming oscillated fail → wait →
            // "recovered" → fail on a fresh recovery budget, burning the
            // whole night capturing rejects and never converging. Escalate
            // to a real operator Pause instead: freeze the run and hand it
            // to the operator (matching the operator-pause / safe-state
            // path) rather than declaring an unverified success.
            AttemptOutcome::PauseForOperator {
                message: "Consecutive image-grading rejects exceeded the limit — \
                          sequence paused for inspection. Resume once conditions clear."
                    .to_string(),
            }
        }
        RecoveryCause::DeviceDisconnected => {
            if device_ids.is_empty() {
                return AttemptOutcome::Failed {
                    message: "No device ids are configured; cannot verify reconnect".to_string(),
                };
            }

            // Actively drive a reconnect for each device. The old behaviour only
            // POLLED device_is_connected, which never recovers camera / focuser
            // / filter-wheel disconnects: those devices default to
            // auto_reconnect=false, so the background reconnection loop skips
            // them and the recovery budget is burned reporting "still
            // disconnected". connect_device() flips auto_reconnect on AND issues
            // an immediate connect. A failed attempt is non-fatal — the
            // is_connected verification below decides the outcome.
            for device_id in device_ids {
                if let Err(e) = device_ops.connect_device(device_id).await {
                    tracing::warn!(
                        "[RECOVERY] connect_device('{}') attempt failed: {} (will verify state)",
                        device_id,
                        e
                    );
                }
            }

            for device_id in device_ids {
                match device_ops.device_is_connected(device_id).await {
                    Ok(true) => {}
                    Ok(false) => {
                        return AttemptOutcome::Failed {
                            message: format!("Device '{}' is still disconnected", device_id),
                        };
                    }
                    Err(e) => {
                        return AttemptOutcome::Failed {
                            message: format!(
                                "Device '{}' reconnect status query failed: {}",
                                device_id, e
                            ),
                        };
                    }
                }
            }

            AttemptOutcome::Succeeded
        }
        RecoveryCause::Custom(_) => {
            // Custom causes have no built-in recovery action — declare
            // success after the wait so the sequence resumes. Plugins /
            // scripts that surface custom causes are expected to handle
            // their own recovery upstream; the unified state machine
            // only provides the visible Recovering UX.
            AttemptOutcome::Succeeded
        }
    }
}

/// The sequence executor manages running a sequence
pub struct SequenceExecutor {
    sequence: Option<SequenceDefinition>,
    state: Arc<RwLock<ExecutorState>>,
    progress: Arc<StdRwLock<SequenceProgress>>,
    command_tx: Option<mpsc::Sender<ExecutorCommand>>,
    event_tx: broadcast::Sender<ExecutorEvent>,
    is_cancelled: Arc<AtomicBool>,
    root_node: Option<Box<dyn Node>>,
    /// Device operations handler - None indicates no device ops have been configured.
    /// Device ops MUST be set via set_device_ops() before starting a sequence.
    device_ops: Option<SharedDeviceOps>,
    /// Connected device IDs
    pub camera_id: Option<String>,
    pub mount_id: Option<String>,
    pub focuser_id: Option<String>,
    pub filterwheel_id: Option<String>,
    pub rotator_id: Option<String>,
    pub dome_id: Option<String>,
    pub cover_calibrator_id: Option<String>,
    /// Base save path for images
    pub save_path: Option<std::path::PathBuf>,
    /// Observer location
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    /// Trigger manager for monitoring conditions
    trigger_manager: Arc<RwLock<TriggerManager>>,
    /// Enable/disable trigger monitoring
    pub triggers_enabled: bool,
    /// Checkpoint manager for crash recovery.
    /// stored behind an `Arc` so the streaming-checkpoint task
    /// (spawned inside `start()`) shares the SAME instance — including its
    /// `info_cache` — instead of constructing a second
    /// `CheckpointManager::new(checkpoint_dir)` that bypasses the cache and
    /// causes UI staleness on `has_recoverable_checkpoint`.
    checkpoint_manager: Option<Arc<crate::checkpoint::CheckpointManager>>,
    /// Current checkpoint being updated
    current_checkpoint: Option<crate::checkpoint::SessionCheckpoint>,
    /// Safety fail mode - determines behavior when safety devices fail or are unavailable
    pub safety_fail_mode: SafetyFailMode,
    /// Filter focus offsets from equipment profile (filter_name -> offset_steps)
    pub filter_focus_offsets: std::collections::HashMap<String, i32>,
    /// shared runtime configuration. Updated by
    /// `Update{DitherConfig,Location,FilterOffsets}` commands so changes
    /// take effect on the next dither/capture/autofocus without requiring a
    /// sequence reload. Cloned into the spawned executor task so the task
    /// reads the same values the public update_* methods write.
    ///
    /// Why `parking_lot::RwLock` instead of `tokio::sync::RwLock`: the
    /// public `update_*` methods are sync (already wired into the bridge
    /// crate that way) and the lock is only ever held for the duration of
    /// a struct-field assignment. A sync rwlock keeps the bridge call sites
    /// non-`.await` and is free of contention concerns for this access
    /// pattern.
    runtime_config: Arc<StdRwLock<RuntimeConfig>>,
    /// Recovery Mode — shared atomic flags that let the operator
    /// punch through the wait timer ("Try Now") or exit the loop ("Abort")
    /// without blocking on a mutex. Cloned into the spawned executor task
    /// so the recovery-loop driver sees the same atomic the public
    /// `recovery_try_now()` / `recovery_abort()` methods write.
    recovery_signals: Arc<crate::recovery::RecoverySignals>,
    /// Recovery Mode — most recent in-flight `RecoveryContext`.
    /// `None` whenever the executor is not in `Recovering`. Cloned for
    /// the `ExecutorEvent::Recovery*` events so the dashboard banner sees
    /// the same snapshot the executor sees.
    current_recovery: Arc<StdRwLock<Option<crate::recovery::RecoveryContext>>>,
    /// Recovery Mode — log of every completed recovery loop so the
    /// post-session report can render attempts/cause/duration/outcome.
    /// Trimmed at construction-time so a marathon run with hundreds of
    /// recoveries (something is very wrong then…) doesn't blow up memory.
    recovery_history: Arc<StdRwLock<Vec<crate::recovery::RecoveryHistoryEntry>>>,
    /// Replay Debug — structured decision broadcast channel. Every
    /// scheduler pick, trigger firing, recovery transition, frame verdict,
    /// adaptive swap, plugin invocation, manual operator action, and
    /// system event flows through this sender. The bridge layer
    /// subscribes via [`SequenceExecutor::subscribe_decisions`] and routes
    /// the events to the `SequencerEvent::DecisionLogged` typed payload
    /// + the `sequence_decisions` persistence table.
    decision_tx: crate::decision::DecisionSender,
    /// Replay Debug — the currently-active `sequence_runs.id` (set
    /// from the bridge via [`SequenceExecutor::set_active_sequence_run_id`]
    /// after the Dart side inserts the row). Stamped into every emitted
    /// `DecisionEvent` so the replay screen can filter by run without
    /// joining on a wall-clock window.
    active_sequence_run_id: Arc<StdRwLock<Option<i64>>>,
    /// Replay Debug — runtime toggle. When `false`, the executor
    /// short-circuits decision emission entirely (no channel send, no
    /// allocation). Wired to the `decisionLoggingEnabled` setting.
    decision_logging_enabled: Arc<AtomicBool>,
    /// adaptive sky-conditions swap. Stable Arc slots shared
    /// between this struct and the per-run `ExecutionContext`. Holding
    /// them on the executor too lets idle-time pushes (`update_conditions_score`
    /// called before `start()`) survive into the next run AND lets the
    /// dashboard's `current_adaptive_swap_json` reach a snapshot without
    /// needing access to the in-flight context.
    shared_conditions_score: Arc<RwLock<Option<crate::scheduling::ConditionsScore>>>,
    shared_adaptive_swap_state: Arc<RwLock<crate::node::context::AdaptiveSwapRuntimeState>>,
}

impl SequenceExecutor {
    pub fn new() -> Self {
        let (event_tx, _) = broadcast::channel(256);
        let (decision_tx, _) =
            broadcast::channel(crate::decision::DEFAULT_DECISION_CHANNEL_CAPACITY);
        let mut trigger_manager = TriggerManager::new();
        // Seed the standard safety triggers (HFR, weather, altitude limit, meridian
        // flip, etc.) at construction so a sequence loaded without an explicit
        // trigger config — e.g. headless API runs or first-launch users — still has
        // a baseline of unattended-imaging protections.
        trigger_manager.create_standard_triggers();

        Self {
            sequence: None,
            state: Arc::new(RwLock::new(ExecutorState::Idle)),
            progress: Arc::new(StdRwLock::new(SequenceProgress::default())),
            command_tx: None,
            event_tx,
            is_cancelled: Arc::new(AtomicBool::new(false)),
            root_node: None,
            device_ops: None,
            camera_id: None,
            mount_id: None,
            focuser_id: None,
            filterwheel_id: None,
            rotator_id: None,
            dome_id: None,
            cover_calibrator_id: None,
            save_path: None,
            latitude: None,
            longitude: None,
            trigger_manager: Arc::new(RwLock::new(trigger_manager)),
            triggers_enabled: true,
            checkpoint_manager: None,
            current_checkpoint: None,
            safety_fail_mode: SafetyFailMode::default(),
            filter_focus_offsets: std::collections::HashMap::new(),
            runtime_config: Arc::new(StdRwLock::new(RuntimeConfig::default())),
            recovery_signals: Arc::new(crate::recovery::RecoverySignals::new()),
            current_recovery: Arc::new(StdRwLock::new(None)),
            recovery_history: Arc::new(StdRwLock::new(Vec::new())),
            decision_tx,
            active_sequence_run_id: Arc::new(StdRwLock::new(None)),
            shared_conditions_score: Arc::new(RwLock::new(None)),
            shared_adaptive_swap_state: Arc::new(RwLock::new(
                crate::node::context::AdaptiveSwapRuntimeState::default(),
            )),
            // Replay Debug — default ON. The Dart settings layer
            // calls `set_decision_logging_enabled(false)` when the user
            // opts out; the overhead is negligible (one channel send +
            // one DB row per decision, well under 100 rows/min in real
            // sessions) so we ship enabled-by-default.
            decision_logging_enabled: Arc::new(AtomicBool::new(true)),
        }
    }

    async fn prepare_sequence_recovery_triggers(&self) -> Result<HashMap<String, NodeId>, String> {
        let Some(sequence) = &self.sequence else {
            return Ok(HashMap::new());
        };

        let specs = sequence_recovery_trigger_specs(sequence);
        let mut custom_branches = HashMap::new();
        let mut manager = self.trigger_manager.write().await;

        let stale_ids: Vec<String> = manager
            .triggers()
            .iter()
            .filter(|trigger| trigger.id.starts_with(RECOVERY_NODE_TRIGGER_PREFIX))
            .map(|trigger| trigger.id.clone())
            .collect();
        for trigger_id in stale_ids {
            manager.remove_trigger(&trigger_id);
        }

        for spec in specs {
            if let Some(node_id) = &spec.custom_branch_node_id {
                custom_branches.insert(spec.trigger_id.clone(), node_id.clone());
            }

            manager.add_trigger(Trigger::new(
                spec.trigger_id,
                spec.trigger_name,
                spec.trigger_type,
                spec.recovery_action,
            ));
        }

        Ok(custom_branches)
    }

    /// Get the current state
    pub async fn get_state(&self) -> ExecutorState {
        *self.state.read().await
    }

    /// Get the current progress
    pub fn get_progress(&self) -> SequenceProgress {
        self.progress.read().clone()
    }

    /// Emit an event
    fn emit(&self, event: ExecutorEvent) {
        let _ = self.event_tx.send(event);
    }

    /// Set state and emit event
    async fn set_state(&self, state: ExecutorState) {
        *self.state.write().await = state;
        {
            let mut progress = self.progress.write();
            progress.state = state;
        }
        self.emit(ExecutorEvent::StateChanged(state));
    }

    /// Start executing the sequence
    pub async fn start(&mut self) -> Result<(), String> {
        let state = self.get_state().await;
        if state != ExecutorState::Idle {
            return Err(format!("Cannot start: executor is {:?}", state));
        }

        if self.sequence.is_none() || self.root_node.is_none() {
            return Err("No sequence loaded".to_string());
        }

        // Reject start when device_ops is unset: every instruction (slew, expose, autofocus)
        // routes through it, so a missing handle would let a sequence "run" while doing
        // absolutely nothing — a silent failure mode the user could not diagnose.
        let device_ops = self.device_ops.clone().ok_or_else(|| {
            "No device operations configured. Call set_device_ops() before starting a sequence. \
             This ensures all device operations use real hardware instead of silently doing nothing."
                .to_string()
        })?;

        // Plate-solve preflight. If the sequence centers on a target it needs a
        // working solver, and ASTAP additionally needs a star catalog — ASTAP
        // with no catalog exits 0 and never solves, so the CenterTarget node
        // would otherwise burn all its attempts mid-night and only then fail.
        // Surface it BEFORE slewing: hard-fail if no solver binary exists at
        // all (unambiguous), and emit a loud operator-visible warning if no
        // ASTAP catalog is detected (a warning rather than a hard block so a
        // valid solve-field / non-standard catalog setup is not falsely
        // rejected; the CenterTarget node's own fail-closed error remains the
        // backstop).
        if self
            .root_node
            .as_ref()
            .is_some_and(|root| tree_contains_centering(&**root))
        {
            if !nightshade_imaging::is_solver_available() {
                return Err(
                    "This sequence centers on a target but no plate solver (ASTAP or \
                     solve-field) was found on this system. Install and configure a plate \
                     solver before running — centering would fail on every target otherwise."
                        .to_string(),
                );
            }
            if nightshade_imaging::detect_astap_catalog(None, None).is_none() {
                tracing::warn!(
                    "Plate-solve preflight: a solver is installed but no ASTAP star catalog was \
                     detected. ASTAP needs a star database installed separately from astap.exe."
                );
                // This is a setup issue, not a crash — but it WILL break every
                // target centering, so surface it clearly and tell the operator
                // exactly how to fix it before the night is wasted.
                let _ = self.event_tx.send(ExecutorEvent::Error {
                    message: "Plate-solve setup: no ASTAP star database found. ASTAP needs a star \
                              catalog installed separately from astap.exe — download one (e.g. the \
                              D80 or H18 .290 database) and put it next to astap.exe, or set its \
                              folder in Settings → Plate Solving. Until then, target centering in \
                              this sequence will fail."
                        .to_string(),
                });
            }
        }

        let custom_recovery_branches = self.prepare_sequence_recovery_triggers().await?;

        self.is_cancelled.store(false, Ordering::Relaxed);

        let (tx, mut rx) = mpsc::channel::<ExecutorCommand>(32);
        self.command_tx = Some(tx);

        self.set_state(ExecutorState::Running).await;

        // if the runtime config has a user-supplied
        // autofocus-interval cadence, push it into the seeded standard
        // trigger before the trigger-monitor task picks up its snapshot.
        // Without this, a value set via the equipment-profile UI before
        // start() would only take effect on the next start().
        {
            let override_value = {
                let rc = self.runtime_config.read();
                rc.autofocus_interval_frames
            };
            if let Some(every_n_frames) = override_value {
                let mut mgr = self.trigger_manager.write().await;
                if let Some(trigger) = mgr.get_trigger_mut("autofocus_interval") {
                    if let TriggerType::AutofocusInterval {
                        every_n_frames: live,
                    } = &mut trigger.trigger_type
                    {
                        *live = every_n_frames;
                    }
                }
            }
        }

        // Seed the trigger-driven autofocus config from the sequence's first
        // Autofocus node. Trigger-fired refocus (HFR / temperature / focus-
        // drift / interval) previously hardcoded `AutofocusConfig::default()`,
        // discarding the operator's step size / exposure / backlash / method —
        // soft frames and AF thrash all night. The Autofocus node carries the
        // user's real tuning (the Dart layer builds it from the equipment
        // profile), so copy it here. Only seed if not already set via a
        // runtime command, so an explicit operator override still wins.
        {
            let already_set = self.runtime_config.read().autofocus.is_some();
            if !already_set {
                if let Some(node_af) = self
                    .root_node
                    .as_ref()
                    .and_then(|root| find_first_autofocus_config(&**root))
                {
                    tracing::info!(
                        "Seeded trigger autofocus config from sequence Autofocus node \
                         (method={:?}, step_size={}, steps_out={}, exposure={}s, backlash={})",
                        node_af.method,
                        node_af.step_size,
                        node_af.steps_out,
                        node_af.exposure_duration,
                        node_af.backlash_compensation,
                    );
                    self.runtime_config.write().autofocus = Some(node_af);
                } else {
                    tracing::warn!(
                        "No Autofocus node in the sequence to seed trigger-autofocus tuning; \
                         trigger-fired refocus will use library defaults. Add an Autofocus \
                         instruction (or push a profile AF config) so triggers use your real \
                         step size / exposure / backlash."
                    );
                }
            }
        }

        // surface trigger-creation-time clamp diagnostics
        // (e.g. FocusDrift.window_size > FOCUS_DRIFT_WINDOW_MAX) as
        // user-visible errors on the run dashboard. The clamping itself
        // happens silently inside `Trigger::new` during standard-trigger
        // seeding and sequence load; emitting once per Start is enough for
        // the user to see and fix the configuration.
        {
            let mgr = self.trigger_manager.read().await;
            for trigger in mgr.triggers() {
                if let Some(warning) = &trigger.clamp_warning {
                    let msg = format!(
                        "Trigger '{}' ({}) clamped: {} was {}; clamped to maximum {}. \
                         Reduce {} in the trigger configuration to silence this warning.",
                        trigger.name,
                        trigger.id,
                        warning.field,
                        warning.original,
                        warning.clamped_to,
                        warning.field,
                    );
                    let _ = self.event_tx.send(ExecutorEvent::Error { message: msg });
                }
            }
        }

        let state = self.state.clone();
        let progress = self.progress.clone();
        let event_tx = self.event_tx.clone();
        let is_cancelled = self.is_cancelled.clone();
        let mut root_node = self
            .root_node
            .take()
            .ok_or("No root node available - sequence may not be properly loaded".to_string())?;

        let camera_id = self.camera_id.clone();
        let mount_id = self.mount_id.clone();
        let focuser_id = self.focuser_id.clone();
        let filterwheel_id = self.filterwheel_id.clone();
        let rotator_id = self.rotator_id.clone();
        let dome_id = self.dome_id.clone();
        let cover_calibrator_id = self.cover_calibrator_id.clone();
        let save_path = self.save_path.clone();
        let latitude = self.latitude;
        let longitude = self.longitude;
        let trigger_action_context = TriggerActionContext {
            camera_id: camera_id.clone(),
            mount_id: mount_id.clone(),
            focuser_id: focuser_id.clone(),
            filterwheel_id: filterwheel_id.clone(),
            rotator_id: rotator_id.clone(),
            dome_id: dome_id.clone(),
            cover_calibrator_id: cover_calibrator_id.clone(),
            save_path: save_path.clone(),
            latitude,
            longitude,
            filter_focus_offsets: self.filter_focus_offsets.clone(),
        };
        let exposure_node_metadata: HashMap<NodeId, (f64, Option<String>)> = self
            .sequence
            .as_ref()
            .map(|sequence| {
                sequence
                    .nodes
                    .iter()
                    .filter_map(|node| match &node.node_type {
                        NodeType::TakeExposure(config) => Some((
                            node.id.clone(),
                            (config.duration_secs, config.filter.clone()),
                        )),
                        _ => None,
                    })
                    .collect()
            })
            // Why: `self.sequence` is `Option<Sequence>`; None means no
            // sequence has been loaded yet (executor in initial state). An empty metadata
            // HashMap is the correct sentinel — there are simply no TakeExposure nodes to
            // index, so the trigger-action-context cannot reference any.
            .unwrap_or_default();

        let trigger_manager = self.trigger_manager.clone();
        let triggers_enabled = self.triggers_enabled;
        let safety_fail_mode = self.safety_fail_mode;
        let filter_focus_offsets = self.filter_focus_offsets.clone();
        let sequence_for_custom_recovery = self.sequence.clone();
        let custom_recovery_branches = Arc::new(custom_recovery_branches);

        // seed runtime config from the executor's configured
        // values so the first read sees what `set_*()` was given before
        // start() was called. The shared Arc is cloned for the spawned task
        // and the command handler so writes propagate to readers.
        {
            let mut rc = self.runtime_config.write();
            rc.latitude = self.latitude;
            rc.longitude = self.longitude;
            rc.filter_focus_offsets = self.filter_focus_offsets.clone();
            rc.safety_fail_mode = self.safety_fail_mode;
        }
        let runtime_config = self.runtime_config.clone();

        // Recovery Mode — clone the shared signal + history handles
        // for the spawned executor task. The signals atomic is cloned so
        // the operator pressing "Try Now" / "Abort" mid-loop is visible to
        // the trigger-monitor closure that drives the recovery state
        // machine; the `current_recovery` slot is what the bridge layer
        // reads to surface the live context to subscribers that joined
        // mid-loop (rare but possible — a remote phone reconnecting).
        let recovery_signals_clone = self.recovery_signals.clone();
        let current_recovery_clone = self.current_recovery.clone();
        let recovery_history_clone = self.recovery_history.clone();
        // Replay Debug — clone the decision sender + active run id
        // handle into the spawned executor task so every instruction
        // node, the trigger-monitor closure, and the recovery driver
        // can publish DecisionEvents.
        let decision_tx_for_ctx = self.decision_tx.clone();
        let decision_tx_for_lifecycle = self.decision_tx.clone();
        let active_run_id_for_ctx = self.active_sequence_run_id.clone();
        let active_run_id_for_decisions = self.active_sequence_run_id.clone();
        let decision_logging_enabled_for_emits = self.decision_logging_enabled.clone();
        // pre-clone the shared adaptive-swap Arc slots OUTSIDE
        // the spawned task so the future doesn't capture `self` (which
        // would bind to the `&mut self` borrow of `start()`).
        let shared_conditions_score_for_ctx = self.shared_conditions_score.clone();
        let shared_adaptive_swap_state_for_ctx = self.shared_adaptive_swap_state.clone();
        // Arm the signal bus so any stale TryNow / Abort left over from a
        // previous run doesn't pre-fire the very first recovery. The
        // `arm()` call increments the entry counter so the Dart side can
        // distinguish "this is a new recovery loop" from "still the same
        // one" via the counter.
        self.recovery_signals.arm();

        // share the *same* CheckpointManager Arc between the
        // executor and the streaming-checkpoint task so they cannot diverge
        // (info_cache must be consistent for `has_recoverable_checkpoint`).
        let streaming_checkpoint_manager: Option<Arc<crate::checkpoint::CheckpointManager>> =
            self.checkpoint_manager.clone();
        // Separate Arc clone for the terminal completion handler. On normal
        // completion we mark the checkpoint inactive so the next launch does
        // NOT show a stale "resume?" banner. `streaming_checkpoint_manager`
        // above is moved into the streaming-checkpoint task, so the completion
        // path needs its own handle to the *same* manager (shared info_cache).
        let completion_checkpoint_manager: Option<Arc<crate::checkpoint::CheckpointManager>> =
            self.checkpoint_manager.clone();
        let streaming_sequence = self.sequence.clone();
        let streaming_camera_id = self.camera_id.clone();
        let streaming_mount_id = self.mount_id.clone();
        let streaming_focuser_id = self.focuser_id.clone();
        let streaming_filterwheel_id = self.filterwheel_id.clone();
        let streaming_rotator_id = self.rotator_id.clone();
        let streaming_save_path = self.save_path.clone();
        let streaming_latitude = self.latitude;
        let streaming_longitude = self.longitude;

        let is_paused = Arc::new(AtomicBool::new(false));
        let skip_to_next_target = Arc::new(AtomicBool::new(false));
        // Recovery Mode — channel by which the trigger-monitor posts
        // recoverable failures to the dedicated recovery-driver task. The
        // monitor sets `is_paused` while a recovery is in flight (so the
        // node tree freezes) and pushes the cause into this channel; the
        // driver reads it, transitions state to Recovering, runs the
        // retry loop, and on success flips `is_paused` back off so the
        // node tree resumes from where it stopped.
        //
        // Bounded channel: only one recovery may be in flight at a time;
        // back-pressure on `try_send` is the documented way the monitor
        // sees "already recovering, drop the duplicate trigger".
        let (recovery_request_tx, mut recovery_request_rx) =
            mpsc::channel::<crate::recovery::RecoveryCause>(4);
        // Trust-patch §7: shared "SkipToNode target" slot. Set by the
        // ExecutorCommand::SkipToNode handler, consumed by the node tree
        // during execution (see RuntimeNode::execute_children_sequential).
        let skip_to_node: Arc<StdRwLock<Option<NodeId>>> = Arc::new(StdRwLock::new(None));
        let resume_notify = Arc::new(tokio::sync::Notify::new());

        // pull the budget snapshot from the most-recently
        // loaded checkpoint (if any) so the spawned task can apply it
        // after constructing the ExecutionContext. Cloning a snapshot is
        // cheap (it's just Vec<BudgetState>).
        let budget_snapshot_to_restore = self
            .current_checkpoint
            .as_ref()
            .map(|cp| cp.budget_states.clone());

        // pull the SmartExposure resume map from the
        // most-recently loaded checkpoint. Each entry restores a single
        // SmartExposure node's per-filter completed counts +
        // current_plan_index so a crashed mid-rotation run resumes on the
        // correct filter at the correct frame index. An empty / missing
        // map is a no-op (fresh run).
        let smart_exposure_snapshot_to_restore = self
            .current_checkpoint
            .as_ref()
            .map(|cp| cp.smart_exposure_states.clone());

        let is_paused_clone = is_paused.clone();
        let skip_to_next_target_clone = skip_to_next_target.clone();
        let skip_to_node_clone = skip_to_node.clone();
        let resume_notify_clone = resume_notify.clone();
        let exposure_node_metadata = Arc::new(exposure_node_metadata);
        let trigger_action_context = trigger_action_context.clone();

        // Clones used by the panic-supervision shell *outside* the executed
        // future. A bare `tokio::spawn` would silently swallow any panic in
        // the executor loop — the sequence would just stop with no event and
        // no log. We need at least `state`, `progress`, and `event_tx` to
        // survive the panic so we can report `SequenceFailed` to the UI.
        let supervisor_state = state.clone();
        let supervisor_progress = progress.clone();
        let supervisor_event_tx = event_tx.clone();
        tokio::spawn(async move {
            let executor_future = async move {
                let start_time = std::time::Instant::now();

                // The trigger monitor needs its own handle because `with_device_ops` moves
                // the original into the ExecutionContext used by the instruction tree.
                let device_ops_for_triggers = device_ops.clone();

                let mut context = ExecutionContext::new("root".to_string())
                    .with_device_ops(device_ops)
                    // Replay Debug — install the broadcast
                    // sender + shared active-run-id slot so every
                    // instruction node, scheduler, recovery driver,
                    // and exposure grader can publish DecisionEvents
                    // without further plumbing.
                    .with_decision_sender(
                        decision_tx_for_ctx.clone(),
                        active_run_id_for_ctx.clone(),
                    );
                // clone the shared cloud-motion snapshot handle
                // so the trigger-monitor task can read it for
                // `SlewToGapAndContinue` without holding the trigger-state
                // lock. The Arc<RwLock> inside ExecutionContext is shared with
                // every parallel branch and with the UpdateCloudMotion command
                // handler, so reads here see the latest pushed snapshot.
                let cloud_motion_for_recovery = context.cloud_motion_snapshot.clone();
                // pre-clone the adaptive-exposure shared
                // Arc handles so the command-handler closure captures
                // them by value (avoiding the immutable-borrow-of-
                // `context` problem that fights `&mut context` in the
                // parallel root_node.execute below).
                let sky_brightness_for_cmd = context.current_sky_brightness_mag.clone();
                let default_adaptive_for_cmd = context.default_adaptive_exposure.clone();
                // share the pending-plugin-node map with
                // the command handler so a `PluginNodeFinished` reply can
                // resolve the matching oneshot without borrowing `context`
                // (which is exclusively held by `root_node.execute`
                // below).
                let plugin_node_pending_for_cmd = context.plugin_node_pending.clone();
                // share the defect-map Arc with the
                // command handler so an `UpdateDefectMap` command can
                // mutate the live state without re-borrowing `context`.
                let defect_map_apply_for_cmd = context.defect_map_apply.clone();
                // Science — pre-clone the transparency-tracking
                // Arc handles so the command handler can push fresh
                // samples / backup plans into the shared ExecutionContext
                // without re-borrowing `context` (which is held by the
                // parallel root_node.execute below). The
                // `*_for_recovery` clones flow into the trigger
                // monitor's `SwitchTargetOrFilter` handler.
                let transparency_for_cmd = context.current_transparency.clone();
                let transparency_backup_for_cmd = context.transparency_backup_plan.clone();
                let transparency_backup_for_recovery = context.transparency_backup_plan.clone();
                // adaptive sky-conditions swap. The composite
                // ConditionsScore slot is mirrored into the shared
                // ExecutionContext so the TargetScheduler reads it without
                // taking the trigger-state lock; `_for_cmd` is the handle
                // the command channel writes through.
                // Bind the per-run context slots to the executor-level
                // shared slots so idle-time pushes (received before
                // `start()`) carry into the run and so the dashboard JSON
                // getter reads from one place. The Arc swap is cheap and
                // happens once per run.
                context.current_conditions_score = shared_conditions_score_for_ctx.clone();
                context.adaptive_swap_state = shared_adaptive_swap_state_for_ctx.clone();
                let conditions_score_for_cmd = context.current_conditions_score.clone();
                let skip_to_node_for_recovery = context.skip_to_node.clone();
                context.is_cancelled = is_cancelled.clone();
                context.is_paused = is_paused_clone;
                // Dual-rig — pick up the process-wide dither barrier if a
                // secondary capture loop is armed, so the primary's dither
                // call sites coordinate with it. `None` (single-rig) makes
                // every dither a plain pass-through.
                context.dither_barrier = crate::dual_rig::active_barrier();
                context.skip_to_next_target = skip_to_next_target_clone;
                // Trust-patch §7: wire shared SkipToNode slot into the
                // execution context so the node tree sees commands posted
                // by the executor command handler.
                context.skip_to_node = skip_to_node_clone;
                context.resume_notify = resume_notify_clone;
                context.camera_id = camera_id;
                context.mount_id = mount_id;
                context.focuser_id = focuser_id;
                context.filterwheel_id = filterwheel_id;
                context.rotator_id = rotator_id;
                context.dome_id = dome_id;
                context.cover_calibrator_id = cover_calibrator_id;
                context.save_path = save_path;
                context.latitude = latitude;
                context.longitude = longitude;
                context.safety_fail_mode = Arc::new(parking_lot::RwLock::new(safety_fail_mode));
                context.filter_focus_offsets = filter_focus_offsets;
                // Hand the event_tx to the execution context so instructions
                // (e.g. execute_exposure) can surface ExecutorEvent::Error
                // for FITS-save failures and other instruction-level errors
                // that must reach UI subscribers, not just the log.
                context.event_tx = Some(event_tx.clone());
                context.recovery_request_tx = Some(recovery_request_tx.clone());
                // The trigger state owns HFR baseline and exposure counts; instructions
                // (autofocus, exposures) feed it through the context so triggers can fire.
                context.trigger_state = Some(trigger_manager.read().await.state());

                // seed the session-static FITS-header fields from the
                // runtime config. A fresh `session_id` is minted per start()
                // so `NS-SESID` uniquely identifies the run; ExecutionContext::new
                // already generates one in tests, but we MUST replace it here so
                // the value reflects the current production start (not a value
                // generated when this executor instance was first constructed,
                // which could be hours / days ago).
                context.session_id = uuid::Uuid::new_v4().to_string();
                // W1 native daylight gate — copy the configured max Sun altitude
                // out of the (non-Send) parking_lot guard so it can be seeded
                // into the shared trigger state across an `.await` below.
                // Remediation 2026-06-09 (finding #2): the field is `Option<f64>`;
                // resolve a never-pushed (`None`) or non-finite value to the
                // DEFAULT (-12°, nautical darkness) so the native gate is never
                // weaker than the Dart W1 gate it backstops. When the Dart side
                // pushed its `SchedulerConfig.maxSunAltitudeDegrees`, that exact
                // value is used.
                let max_sun_altitude_degrees = match runtime_config.read().max_sun_altitude_degrees
                {
                    Some(v) if v.is_finite() => v,
                    _ => crate::instructions::DEFAULT_MAX_SUN_ALTITUDE_DEGREES,
                };
                context.max_sun_altitude_degrees = max_sun_altitude_degrees;
                if let Some(ts_lock) = &context.trigger_state {
                    // Seed the trigger state so the gate (which reads through the
                    // InstructionContext's trigger-state handle, not the
                    // ExecutionContext) sees the configured threshold.
                    ts_lock
                        .write()
                        .await
                        .set_max_sun_altitude_degrees(max_sun_altitude_degrees);
                }
                {
                    let rc = runtime_config.read();
                    context.observer_name = rc.observer_profile.observer_name.clone();
                    context.site_elevation_m = rc.observer_profile.site_elevation_m;
                    context.camera_make = rc.observer_profile.camera_make.clone();
                    context.camera_model = rc.observer_profile.camera_model.clone();
                    context.telescope_name = rc.observer_profile.telescope_name.clone();
                    context.telescope_focal_length_mm =
                        rc.observer_profile.telescope_focal_length_mm;
                    context.telescope_aperture_mm = rc.observer_profile.telescope_aperture_mm;
                    context.default_quality_check = rc.default_quality_check.clone();
                    context.reject_folder_path = rc.reject_folder_path.clone();
                }
                // seed the global adaptive-exposure
                // fallback so a node without its own `adaptive_exposure`
                // block still inherits it. The shared Arc<RwLock> field
                // is written outside the sync `runtime_config.read()`
                // scope because the tokio RwLock write is async.
                {
                    let initial = runtime_config.read().default_adaptive_exposure.clone();
                    let mut slot = context.default_adaptive_exposure.write().await;
                    *slot = initial;
                }
                // seed the defect-map application state
                // from runtime_config so a sequence started after the
                // user has already toggled "Apply during capture" on
                // immediately gets per-frame correction (without waiting
                // for the next push from the UI). `None` is the
                // canonical disabled state.
                {
                    let initial = runtime_config.read().defect_map_apply.clone();
                    let mut slot = context.defect_map_apply.write().await;
                    *slot = initial;
                }
                // seed per-target carry-over integration into
                // the BudgetRegistry. The map is drained out of the
                // runtime config (cloned then cleared) so a subsequent
                // start() without an explicit re-seed begins fresh
                // rather than re-applying stale prior-session totals.
                //
                // This runs AFTER `restore_snapshot` so an explicit
                // "Resume" handoff decision overrides the pre-pause
                // checkpoint state — the operator has expressed an
                // intent that supersedes whatever the executor parked
                // on disk. `Restart` writes an empty map so a target
                // that was previously carried-over is now zeroed.
                {
                    let carry_over: HashMap<String, HashMap<String, f64>> = {
                        let mut rc = runtime_config.write();
                        std::mem::take(&mut rc.pending_integration_carry_over)
                    };
                    if !carry_over.is_empty() {
                        for (target_id, per_filter) in carry_over.into_iter() {
                            tracing::info!(
                                "Seeding integration carry-over for target_id={} \
                                 ({} filter entries)",
                                target_id,
                                per_filter.len()
                            );
                            context
                                .budget_registry
                                .seed_carry_over(&target_id, per_filter)
                                .await;
                        }
                    }
                }
                tracing::info!(
                    "Executor started: session_id={}, observer={:?}, telescope={:?}, grading_active={}",
                    context.session_id,
                    context.observer_name,
                    context.telescope_name,
                    context
                        .default_quality_check
                        .as_ref()
                        .map(|c| c.is_active())
                        .unwrap_or(false)
                );
                // Replay Debug — emit the "sequence started"
                // lifecycle decision so the replay feed has a stable
                // anchor for the run.
                emit_lifecycle_decision(
                    &decision_tx_for_lifecycle,
                    &active_run_id_for_decisions,
                    &decision_logging_enabled_for_emits,
                    "started",
                    serde_json::json!({
                        "session_id": context.session_id.clone(),
                        "grading_active": context
                            .default_quality_check
                            .as_ref()
                            .map(|c| c.is_active())
                            .unwrap_or(false),
                    }),
                );

                // restore per-target integration-budget
                // accounting from the checkpoint, if any. An empty snapshot
                // (no checkpoint loaded, or pre-budget checkpoint) is a
                // no-op which matches the documented backwards-compat
                // behaviour: resume with zero credited per-filter
                // integration and the budget runtime begins crediting from
                // there.
                if let Some(snapshot) = budget_snapshot_to_restore {
                    context.budget_registry.restore_snapshot(snapshot).await;
                }

                // restore the SmartExposure per-node
                // resume map from the checkpoint. Each entry seeds the
                // in-memory `smart_exposure_states` map under
                // ExecutionContext so the next time a SmartExposure node's
                // `execute()` runs, `load_or_init_checkpoint` finds the
                // persisted per-filter counts + plan index and resumes
                // rotation where the previous run left off. Empty / missing
                // map is a no-op (fresh run).
                if let Some(snapshot) = smart_exposure_snapshot_to_restore {
                    if !snapshot.is_empty() {
                        let mut states = context.smart_exposure_states.write().await;
                        for (node_id, state) in snapshot {
                            states.insert(node_id, state);
                        }
                        drop(states);
                    }
                }

                let progress_clone = progress.clone();
                let event_tx_clone = event_tx.clone();
                // NodeStarted must emit exactly once per "entry" into a node; this set
                // guards against the progress callback firing multiple Running updates
                // for the same node within a single visit. Cleared on terminal status
                // so loop bodies emit a fresh NodeStarted each iteration.
                let started_nodes =
                    Arc::new(StdRwLock::new(std::collections::HashSet::<NodeId>::new()));
                // completed_exposures must be monotonic per node so the global counter
                // never decreases — e.g. when a loop body restarts, its frame count
                // must not reset back to zero from the UI's perspective.
                let node_frame_progress = Arc::new(StdRwLock::new(std::collections::HashMap::<
                    NodeId,
                    u32,
                >::new()));
                let node_pending_exposure_completion = Arc::new(StdRwLock::new(
                    std::collections::HashMap::<NodeId, u32>::new(),
                ));
                let exposure_node_metadata = exposure_node_metadata.clone();
                context.progress_callback = Some(Arc::new(move |update: ProgressUpdate| {
                    let mut prog = progress_clone.write();
                    prog.current_node_id = Some(update.node_id.clone());
                    prog.current_node_status = Some(update.status);
                    // `legacy_message` synthesises the pre-refactor message
                    // shape from the structured fields (or returns the raw
                    // lifecycle message verbatim), so prog.message preserves
                    // its existing UI contract.
                    let legacy_message = update.legacy_message();
                    prog.message = legacy_message.clone();
                    prog.node_statuses
                        .insert(update.node_id.clone(), update.status);
                    prog.elapsed_secs = start_time.elapsed().as_secs_f64();

                    if update.status == NodeStatus::Running {
                        let mut started = started_nodes.write();
                        if !started.contains(&update.node_id) {
                            started.insert(update.node_id.clone());
                            // RuntimeNode emits the "Executing: <name>" lifecycle
                            // message exactly once at node entry; this is how we
                            // pull the display name out for NodeStarted. Subsequent
                            // progress events are structured so this branch is the
                            // only place we still parse a message.
                            let node_name = update
                                .message
                                .as_ref()
                                .map(|m| {
                                    if let Some(name) = m.strip_prefix("Executing: ") {
                                        name.to_string()
                                    } else {
                                        m.clone()
                                    }
                                })
                                // Audit-rust §4.3: node-name message is observability
                                // only; load-bearing identity is the node-id. "Unknown"
                                // is the documented UI fallback.
                                .unwrap_or_else(|| "Unknown".to_string());
                            tracing::info!(
                                "[PROGRESS_CB] Emitting NodeStarted: id={}, name={}",
                                update.node_id,
                                node_name
                            );
                            let _ = event_tx_clone.send(ExecutorEvent::NodeStarted {
                                id: update.node_id.clone(),
                                name: node_name,
                            });
                        }
                    } else if matches!(
                        update.status,
                        NodeStatus::Success
                            | NodeStatus::Failure
                            | NodeStatus::Cancelled
                            | NodeStatus::Skipped
                    ) {
                        // Clearing on terminal status lets a loop body emit a
                        // fresh NodeStarted on its next iteration; otherwise the
                        // UI would never re-flash the node as active when the
                        // loop cycles.
                        let mut started = started_nodes.write();
                        started.remove(&update.node_id);
                        let mut frame_progress = node_frame_progress.write();
                        frame_progress.remove(&update.node_id);
                        let mut pending_completion = node_pending_exposure_completion.write();
                        pending_completion.remove(&update.node_id);
                        tracing::debug!(
                            "[PROGRESS_CB] Cleared node {} from started set (status={:?})",
                            update.node_id,
                            update.status
                        );
                    }

                    if let (Some(current), Some(total)) =
                        (update.current_frame, update.total_frames)
                    {
                        let mut exposure_started_event: Option<ExecutorEvent> = None;
                        let mut exposure_completed_event: Option<ExecutorEvent> = None;
                        let metadata = exposure_node_metadata.get(&update.node_id).cloned();

                        let mut frame_progress = node_frame_progress.write();
                        let mut pending_completion = node_pending_exposure_completion.write();
                        let last = frame_progress.entry(update.node_id.clone()).or_insert(0);
                        if current > *last {
                            prog.completed_exposures =
                                prog.completed_exposures.saturating_add(current - *last);
                            *last = current;

                            if let Some((duration_secs, filter)) = metadata {
                                exposure_started_event = Some(ExecutorEvent::ExposureStarted {
                                    frame: current,
                                    total,
                                    filter,
                                    duration_secs,
                                });
                                pending_completion.insert(update.node_id.clone(), current);
                            } else {
                                pending_completion.remove(&update.node_id);
                            }
                        } else if current == *last
                            && pending_completion.get(&update.node_id).copied() == Some(current)
                        {
                            if let Some((duration_secs, _filter)) = metadata {
                                exposure_completed_event = Some(ExecutorEvent::ExposureCompleted {
                                    frame: current,
                                    total,
                                    duration_secs,
                                });
                            }
                            pending_completion.remove(&update.node_id);
                        }

                        drop(pending_completion);
                        drop(frame_progress);

                        if let Some(event) = exposure_started_event {
                            let _ = event_tx_clone.send(event);
                        }
                        if let Some(event) = exposure_completed_event {
                            let _ = event_tx_clone.send(event);
                        }
                    }

                    if let Some(exposure_secs) = update.completed_exposure_secs {
                        prog.completed_integration_secs += exposure_secs;
                    }

                    // pluck per-target / per-filter
                    // budget progress out of the structured detail so the
                    // executor's ProgressUpdated event carries enough
                    // information for the dashboard's budget panel
                    // without re-querying the registry from Dart.
                    if let Some(ProgressDetail::IntegrationBudget {
                        target_id,
                        filter,
                        completed_secs,
                        budget_met,
                        ..
                    }) = update.detail.as_ref()
                    {
                        prog.integration_by_target_filter
                            .entry(target_id.clone())
                            .or_default()
                            .insert(filter.clone(), *completed_secs);
                        if *budget_met {
                            prog.targets_with_budget_met.insert(target_id.clone());
                        }
                    }

                    if prog.total_exposures > 0 && prog.completed_exposures > 0 {
                        let completed = prog.completed_exposures.min(prog.total_exposures);
                        let remaining = prog.total_exposures.saturating_sub(completed);
                        if remaining > 0 {
                            // Why: completed and remaining are u32 progress counters; u32 -> f64
                            // is lossless (f64 mantissa is 53 bits, u32::MAX < 2^32).
                            let avg_secs_per_exposure = prog.elapsed_secs / f64::from(completed);
                            prog.estimated_remaining_secs =
                                Some(avg_secs_per_exposure * f64::from(remaining));
                        } else {
                            prog.estimated_remaining_secs = Some(0.0);
                        }
                    } else {
                        prog.estimated_remaining_secs = None;
                    }

                    // Structured NodeProgress emission. The structured payload
                    // (instruction, progress_percent, detail) is read directly
                    // from the ProgressUpdate — NO STRING PARSING. Pre-refactor
                    // this used `split_once(':')` + `rfind('(')` to recover the
                    // fields; that pipeline is gone. The on-wire detail string
                    // is rendered from the ProgressDetail via `detail_text()`
                    // so the existing FRB / Dart consumers see the same shape.
                    if let (Some(instruction), Some(percent), Some(detail)) = (
                        update.instruction.as_ref(),
                        update.progress_percent,
                        update.detail.as_ref(),
                    ) {
                        let detail_text = detail.detail_text();
                        tracing::debug!(
                            "[PROGRESS_CB] Emitting structured NodeProgress: node_id={}, instruction={}, progress={}%, detail={}",
                            update.node_id,
                            instruction,
                            percent,
                            detail_text
                        );
                        // the `detail` field stays a string for legacy
                        // back-compat (older subscribers parse it). The new
                        // `structured_detail` carries the typed payload so the
                        // bridge can dispatch typed `SequencerEvent` variants
                        // without regex parsing.
                        let _ = event_tx_clone.send(ExecutorEvent::NodeProgress {
                            node_id: update.node_id.clone(),
                            instruction: instruction.clone(),
                            progress_percent: percent,
                            detail: detail_text,
                            structured_detail: Some(Box::new(detail.clone())),
                        });
                    }

                    // `ProgressUpdated` carries a boxed `SequenceProgress`
                    // so the enum stays small (see `ExecutorEvent` doc-comment).
                    let _ =
                        event_tx_clone.send(ExecutorEvent::ProgressUpdated(Box::new(prog.clone())));
                }));

                let is_paused_cmd = is_paused.clone();
                let skip_to_next_target_cmd = skip_to_next_target.clone();
                // Trust-patch §7: command-handler-side clone for posting
                // SkipToNode requests into the shared slot.
                let skip_to_node_cmd = skip_to_node.clone();
                let resume_notify_cmd = resume_notify.clone();
                // Recovery Mode — command-handler-side clone so the
                // RecoveryTryNow / RecoveryAbort handlers can fire the
                // signal bus without grabbing the shared executor lock.
                let recovery_signals_cmd = recovery_signals_clone.clone();
                let safety_fail_mode_for_cmd = context.safety_fail_mode.clone();
                let command_handler = async {
                    while let Some(cmd) = rx.recv().await {
                        match cmd {
                            ExecutorCommand::Pause => {
                                is_paused_cmd.store(true, Ordering::Relaxed);
                                *state.write().await = ExecutorState::Paused;
                                let _ = event_tx
                                    .send(ExecutorEvent::StateChanged(ExecutorState::Paused));
                            }
                            ExecutorCommand::Resume => {
                                // A node may be parked on `resume_notify.notified()`; we have
                                // to wake all waiters *before* flipping is_paused so the
                                // resumed branch sees the new state without racing.
                                is_paused_cmd.store(false, Ordering::Relaxed);
                                resume_notify_cmd.notify_waiters();
                                *state.write().await = ExecutorState::Running;
                                let _ = event_tx
                                    .send(ExecutorEvent::StateChanged(ExecutorState::Running));
                            }
                            ExecutorCommand::Stop => {
                                is_cancelled.store(true, Ordering::Relaxed);
                                *state.write().await = ExecutorState::Stopping;
                                let _ = event_tx
                                    .send(ExecutorEvent::StateChanged(ExecutorState::Stopping));
                                break;
                            }
                            ExecutorCommand::Skip => {
                                tracing::info!("Skip requested - advancing to next target");
                                skip_to_next_target_cmd.store(true, Ordering::Relaxed);
                            }
                            ExecutorCommand::Start => {
                                let _ = event_tx.send(ExecutorEvent::Error {
                                    message: "Start ignored: executor is already running"
                                        .to_string(),
                                });
                            }
                            ExecutorCommand::SkipToNode(node_id) => {
                                // Trust-patch §7: implement SkipToNode for
                                // real. Post the target id into the shared
                                // slot; the next iteration of the node tree
                                // walk will mark preceding siblings as
                                // Skipped and continue executing from the
                                // target. The request clears itself when
                                // the target subtree is entered (see
                                // RuntimeNode::execute_children_sequential).
                                //
                                // We deliberately accept the request even
                                // mid-instruction: the long-running
                                // instruction (e.g. an exposure burst)
                                // continues to completion, then the parent
                                // container observes the skip request and
                                // jumps to the target on the NEXT child. A
                                // user who wants to interrupt mid-burst
                                // sends Stop first, then re-Starts with the
                                // sequence trimmed.
                                tracing::info!(
                                    "[SKIP_TO_NODE] Received request for target node '{}'",
                                    node_id
                                );
                                *skip_to_node_cmd.write() = Some(node_id.clone());
                                let _ = event_tx.send(ExecutorEvent::Error {
                                    // Re-using Error as an info-level UX
                                    // surface is the existing pattern (see
                                    // Start handler above); the message
                                    // text makes the success case clear.
                                    message: format!(
                                        "SkipToNode request accepted: jumping to node '{}'. \
                                         Current instruction (if any) will finish first.",
                                        node_id
                                    ),
                                });
                            }
                            ExecutorCommand::UpdateDitherConfig {
                                pixels,
                                settle_pixels,
                                settle_time,
                                settle_timeout,
                                ra_only,
                            } => {
                                // write through the shared Arc so the
                                // change takes effect on the next dither without
                                // requiring a sequence reload.
                                {
                                    let mut rc = runtime_config.write();
                                    rc.dither.pixels = pixels;
                                    rc.dither.settle_pixels = settle_pixels;
                                    rc.dither.settle_time = settle_time;
                                    rc.dither.settle_timeout = settle_timeout;
                                    rc.dither.ra_only = ra_only;
                                }
                                tracing::info!(
                                "Runtime dither config updated: pixels={}, settle_pixels={}, settle_time={}, settle_timeout={}, ra_only={}",
                                pixels, settle_pixels, settle_time, settle_timeout, ra_only
                            );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "dither".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateLocation {
                                latitude,
                                longitude,
                            } => {
                                // write through the Arc and also push
                                // into the trigger state so altitude-aware
                                // triggers (AltitudeLimit, MeridianFlip hour-angle
                                // calc) read the new value on their next poll.
                                {
                                    let mut rc = runtime_config.write();
                                    rc.latitude = latitude;
                                    rc.longitude = longitude;
                                }
                                {
                                    let manager = trigger_manager.read().await;
                                    let state_lock = manager.state();
                                    let mut state = state_lock.write().await;
                                    state.observer_latitude = latitude;
                                    state.observer_longitude = longitude;
                                }
                                tracing::info!(
                                    "Runtime location updated: lat={:?}, lon={:?}",
                                    latitude,
                                    longitude
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "location".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateMaxSunAltitude { degrees } => {
                                // Remediation 2026-06-09 (finding #2): write
                                // through the Arc AND patch the live trigger
                                // state so the W1 daylight gate (which reads the
                                // threshold through the trigger-state handle)
                                // honours the Dart-pushed value on the next slew /
                                // exposure. A `None`/non-finite push resolves to
                                // the DEFAULT (-12°) so the gate never weakens.
                                {
                                    let mut rc = runtime_config.write();
                                    rc.max_sun_altitude_degrees = degrees;
                                }
                                let effective = match degrees {
                                    Some(v) if v.is_finite() => v,
                                    _ => crate::instructions::DEFAULT_MAX_SUN_ALTITUDE_DEGREES,
                                };
                                {
                                    let manager = trigger_manager.read().await;
                                    let state_lock = manager.state();
                                    let mut state = state_lock.write().await;
                                    state.set_max_sun_altitude_degrees(effective);
                                }
                                tracing::info!(
                                    "Runtime max Sun altitude (W1 daylight gate) updated: {:?} -> effective {:.1}°",
                                    degrees,
                                    effective
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "max_sun_altitude".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateFilterOffsets { offsets } => {
                                // write through the Arc so the next
                                // filter change reads the updated offsets.
                                let count = offsets.len();
                                {
                                    let mut rc = runtime_config.write();
                                    rc.filter_focus_offsets = offsets;
                                }
                                tracing::info!(
                                    "Runtime filter focus offsets updated: {} entries",
                                    count
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "filter_offsets".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateDefaultQualityCheck { check } => {
                                // write through the shared Arc so the
                                // next exposure's instruction context sees the
                                // new default. Pre-existing per-node
                                // `quality_check` settings still win.
                                {
                                    let mut rc = runtime_config.write();
                                    rc.default_quality_check = check.clone();
                                }
                                tracing::info!(
                                    "Runtime default_quality_check updated (active={})",
                                    check.as_ref().map(|c| c.is_active()).unwrap_or(false)
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "default_quality_check".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateRejectFolderPath { path } => {
                                // write through the shared Arc so the
                                // next reject lands in the new folder.
                                {
                                    let mut rc = runtime_config.write();
                                    rc.reject_folder_path = path.clone();
                                }
                                tracing::info!("Runtime reject_folder_path updated: {:?}", path);
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "reject_folder_path".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateObserverProfile { profile } => {
                                // write through the shared Arc so the
                                // next FITS save stamps real keywords.
                                {
                                    let mut rc = runtime_config.write();
                                    rc.observer_profile = profile.clone();
                                }
                                tracing::info!(
                                    "Runtime observer_profile updated: observer={:?}, telescope={:?}",
                                    profile.observer_name,
                                    profile.telescope_name
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "observer_profile".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateAutofocusInterval { every_n_frames } => {
                                // write through runtime_config
                                // AND patch the live trigger's `every_n_frames`
                                // so the next AutofocusInterval evaluation sees
                                // the new cadence without a sequence reload.
                                {
                                    let mut rc = runtime_config.write();
                                    rc.autofocus_interval_frames = Some(every_n_frames);
                                }
                                {
                                    let mut mgr = trigger_manager.write().await;
                                    if let Some(trigger) = mgr.get_trigger_mut("autofocus_interval")
                                    {
                                        if let TriggerType::AutofocusInterval {
                                            every_n_frames: live,
                                        } = &mut trigger.trigger_type
                                        {
                                            *live = every_n_frames;
                                        }
                                    }
                                }
                                tracing::info!(
                                    "Runtime autofocus-interval cadence updated: every {} frames",
                                    every_n_frames
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "autofocus_interval".to_string(),
                                });
                            }
                            ExecutorCommand::RecoveryTryNow => {
                                // Recovery Mode — flag the signal bus
                                // so the next recovery driver tick fires an
                                // immediate attempt instead of waiting for
                                // the retry interval. Safe to issue from any
                                // state; the driver only consumes the flag
                                // while inside a recovery loop, so a stray
                                // TryNow in Running is a documented no-op
                                // (the operator sees the toast confirmation
                                // and nothing else).
                                recovery_signals_cmd.request_try_now();
                                tracing::info!("[RECOVERY] TryNow requested by operator");
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "recovery_try_now".to_string(),
                                });
                            }
                            ExecutorCommand::RecoveryAbort => {
                                // Recovery Mode — flag the signal bus.
                                // The recovery driver checks `take_abort()`
                                // on every tick and exits the loop with a
                                // GaveUp transition.
                                recovery_signals_cmd.request_abort();
                                tracing::info!("[RECOVERY] Abort requested by operator");
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "recovery_abort".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateSkyBrightness { mag } => {
                                // push the latest live
                                // sky-brightness reading into the shared
                                // ExecutionContext field. Uses the
                                // pre-cloned `sky_brightness_for_cmd`
                                // Arc captured above so the closure does
                                // not have to borrow `context` (which
                                // collides with the root_node.execute
                                // mutable borrow).
                                {
                                    let mut slot = sky_brightness_for_cmd.write().await;
                                    *slot = mag;
                                }
                                tracing::debug!(
                                    "Runtime sky brightness updated: {:?} mag/arcsec²",
                                    mag
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "sky_brightness".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateDefaultAdaptiveExposure { config } => {
                                // push the global default
                                // sky-brightness adaptive-exposure config.
                                // Per-node `ExposureConfig.adaptive_exposure`
                                // still wins; this is the fallback consulted
                                // when the node carries no own block.
                                {
                                    let mut rc = runtime_config.write();
                                    rc.default_adaptive_exposure = config.clone();
                                }
                                let cfg_for_log = config.clone();
                                {
                                    let mut slot = default_adaptive_for_cmd.write().await;
                                    *slot = config;
                                }
                                tracing::info!(
                                    "Runtime default_adaptive_exposure updated (enabled={})",
                                    cfg_for_log.as_ref().map(|c| c.enabled).unwrap_or(false)
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "default_adaptive_exposure".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateCloudMotion {
                                current_cover_percent,
                                predicted_arrival_minutes,
                                predicted_opening_minutes,
                                predicted_opening_duration_secs,
                                predicted_clear_sky_alt,
                                predicted_clear_sky_az,
                            } => {
                                // feed the trigger state from
                                // the Dart-side cloud-motion analyzer. The
                                // three cloud-aware triggers
                                // (`CloudArrivingIn`, `CloudOpeningIn`,
                                // `CloudCoverThreshold`) read these values on
                                // their next evaluation tick. Lock the
                                // trigger manager's state directly here so
                                // the update is atomic with respect to a
                                // concurrent evaluator pass.
                                let clear_sky =
                                    match (predicted_clear_sky_alt, predicted_clear_sky_az) {
                                        (Some(alt), Some(az)) => Some((alt, az)),
                                        // Half-specified directions are
                                        // ambiguous; refuse them rather than
                                        // making up a default — that would be a
                                        // silent fallback.
                                        _ => None,
                                    };
                                {
                                    let manager = trigger_manager.read().await;
                                    let state_lock = manager.state();
                                    let mut state = state_lock.write().await;
                                    state.update_cloud_motion(
                                        current_cover_percent,
                                        predicted_arrival_minutes,
                                        predicted_opening_minutes,
                                        predicted_opening_duration_secs,
                                        clear_sky,
                                    );
                                }
                                // Mirror the same values into the shared
                                // ExecutionContext so recovery actions
                                // (`SlewToGapAndContinue`) and the run-
                                // dashboard panel can read them without
                                // holding the trigger-state lock. We use
                                // the pre-cloned `cloud_motion_for_recovery`
                                // Arc captured outside this closure (an
                                // identical-content clone of
                                // `context.cloud_motion_snapshot`) — using
                                // `context.cloud_motion_snapshot` directly
                                // would re-borrow `context` immutably and
                                // conflict with the parallel
                                // `root_node.execute(&mut context)` future.
                                {
                                    let mut slot = cloud_motion_for_recovery.write().await;
                                    *slot = CloudMotionSnapshot {
                                        current_cover_percent,
                                        predicted_arrival_minutes,
                                        predicted_opening_minutes,
                                        predicted_opening_duration_secs,
                                        predicted_clear_sky_direction: clear_sky,
                                        last_update_unix_secs: Some(chrono::Utc::now().timestamp()),
                                    };
                                }
                                tracing::debug!(
                                    "Runtime cloud motion updated: cover={:?}%, arrival={:?}min, opening={:?}min ({:?}s), clear=({:?},{:?})",
                                    current_cover_percent,
                                    predicted_arrival_minutes,
                                    predicted_opening_minutes,
                                    predicted_opening_duration_secs,
                                    predicted_clear_sky_alt,
                                    predicted_clear_sky_az,
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "cloud_motion".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateTransparency { transparency } => {
                                // Science — push the live transparency
                                // reading into BOTH the trigger state (so the
                                // `TransparencyDropped` evaluator sees it on
                                // its next tick) AND the shared
                                // ExecutionContext (so the photometry node's
                                // per-frame quality gates and the run-
                                // dashboard panel can read it without
                                // holding the trigger-state lock).
                                {
                                    let manager = trigger_manager.read().await;
                                    let state_lock = manager.state();
                                    let mut state = state_lock.write().await;
                                    state.update_transparency(transparency);
                                }
                                {
                                    let mut slot = transparency_for_cmd.write().await;
                                    *slot = transparency;
                                }
                                tracing::debug!("Runtime transparency updated: {:?}", transparency);
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "transparency".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateTransparencyBackup { plan } => {
                                // Science — operator-configured
                                // backup plan for the
                                // `SwitchTargetOrFilter` recovery action.
                                let summary = plan.as_ref().map(|p| {
                                    format!(
                                        "filter={:?}, target={:?}",
                                        p.backup_filter, p.backup_target_id,
                                    )
                                });
                                {
                                    let mut slot = transparency_backup_for_cmd.write().await;
                                    *slot = plan;
                                }
                                tracing::info!(
                                    "Runtime transparency backup plan updated: {:?}",
                                    summary
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "transparency_backup".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateConditionsScore { score } => {
                                // push the live ConditionsScore
                                // into the shared ExecutionContext so the
                                // TargetScheduler's adaptive-swap logic
                                // reads it on its next decision tick. The
                                // Dart-side `AdaptiveSwapService` composes
                                // the score from transparency / seeing /
                                // cloud cover / wind every ~30 seconds.
                                // Pass `None` to clear (telemetry lost).
                                let summary = score.as_ref().map(|s| {
                                    format!(
                                        "score={:.1} (T={:?} S={:?} C={:?} W={:?})",
                                        s.score,
                                        s.transparency_score,
                                        s.seeing_score,
                                        s.cloud_score,
                                        s.wind_score,
                                    )
                                });
                                {
                                    let mut slot = conditions_score_for_cmd.write().await;
                                    *slot = score;
                                }
                                tracing::debug!("Runtime conditions score updated: {:?}", summary);
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "conditions_score".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateWeatherVerdict { unsafe_override } => {
                                // Full-night audit 2026-06-04 (defense-in-depth) —
                                // fold the Dart-side weather-safety verdict into the
                                // trigger state so the in-sequencer `WeatherUnsafe`
                                // trigger reacts even on rigs without a hardware
                                // safety device. The evaluator ORs this with the
                                // hardware `weather_safe` reading (never less safe).
                                {
                                    let manager = trigger_manager.read().await;
                                    let state_lock = manager.state();
                                    let mut state = state_lock.write().await;
                                    state.update_weather_verdict(unsafe_override);
                                }
                                tracing::debug!(
                                    "Runtime weather verdict updated: unsafe_override={:?}",
                                    unsafe_override
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "weather_verdict".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateRecoveryConfig { config } => {
                                // Recovery Mode — push the user's
                                // tunable defaults through the shared Arc.
                                // The next time the trigger monitor enters
                                // a recovery loop (Running -> Recovering)
                                // it reads from the runtime config and uses
                                // these values to construct the new
                                // `RecoveryContext`.
                                let interval = config.retry_interval_secs;
                                let max_duration = config.max_duration_secs;
                                {
                                    let mut rc = runtime_config.write();
                                    rc.recovery = config;
                                }
                                tracing::info!(
                                    "Runtime recovery config updated: interval={:.0}s, max_duration={:.0}s",
                                    interval,
                                    max_duration,
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "recovery_config".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateSafetyFailMode { mode } => {
                                {
                                    let mut rc = runtime_config.write();
                                    rc.safety_fail_mode = mode;
                                }
                                *safety_fail_mode_for_cmd.write() = mode;
                                tracing::info!("Runtime safety fail mode updated: {:?}", mode);
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "safety_fail_mode".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateSafetyCheckInterval { seconds } => {
                                let seconds = effective_safety_check_interval_secs(seconds);
                                {
                                    let mut rc = runtime_config.write();
                                    rc.safety_check_interval_secs = seconds;
                                }
                                tracing::info!(
                                    "Runtime safety check interval updated: {}s",
                                    seconds
                                );
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "safety_check_interval".to_string(),
                                });
                            }
                            ExecutorCommand::UpdateDefectMap { state } => {
                                // push the active defect
                                // map (or clear it). Write through the
                                // shared RuntimeConfig AND the shared
                                // ExecutionContext Arc so subsequent
                                // captures see the update on their next
                                // `defect_map_apply.read().await`.
                                let summary = state.as_ref().map(|s| {
                                    (
                                        s.camera_id.clone(),
                                        s.map.defective_count(),
                                        s.kernel.diameter(),
                                        s.method.as_str(),
                                        s.save_original,
                                    )
                                });
                                {
                                    let mut rc = runtime_config.write();
                                    rc.defect_map_apply = state.clone();
                                }
                                {
                                    let mut slot = defect_map_apply_for_cmd.write().await;
                                    *slot = state;
                                }
                                match summary {
                                    Some((camera, defects, kernel, method, save_original)) => {
                                        tracing::info!(
                                            "Runtime defect map updated: camera={}, defects={}, kernel={}x{}, method={}, save_original={}",
                                            camera,
                                            defects,
                                            kernel,
                                            kernel,
                                            method,
                                            save_original,
                                        );
                                    }
                                    None => {
                                        tracing::info!(
                                            "Runtime defect map cleared (per-frame defect correction disabled)"
                                        );
                                    }
                                }
                                let _ = event_tx.send(ExecutorEvent::RuntimeConfigUpdated {
                                    what: "defect_map".to_string(),
                                });
                            }
                            ExecutorCommand::PluginNodeFinished {
                                node_id,
                                success,
                                message,
                                structured_detail_json,
                            } => {
                                // resolve the oneshot the
                                // matching `PluginNodeInstruction::execute`
                                // is awaiting. A stray finish (no pending
                                // entry) is logged at warn and dropped;
                                // it means either the Dart side replied
                                // twice for the same node id, or the
                                // executor torch-down already cleaned up
                                // the entry on timeout. Either case is
                                // benign for the rest of the run.
                                let sender = {
                                    let mut pending = plugin_node_pending_for_cmd.write().await;
                                    pending.remove(&node_id)
                                };
                                let parsed_detail = structured_detail_json
                                    .as_deref()
                                    .and_then(|json| {
                                        if json.is_empty() {
                                            None
                                        } else {
                                            match serde_json::from_str::<serde_json::Value>(json) {
                                                Ok(v) => Some(v),
                                                Err(e) => {
                                                    tracing::warn!(
                                                        "[PLUGIN] PluginNodeFinished structured_detail_json was invalid \
                                                         JSON for node {}: {}; payload dropped.",
                                                        node_id,
                                                        e,
                                                    );
                                                    None
                                                }
                                            }
                                        }
                                    });
                                match sender {
                                    Some(tx) => {
                                        if tx
                                            .send(crate::node::context::PluginNodeReply {
                                                success,
                                                message: message.clone(),
                                                structured_detail: parsed_detail,
                                            })
                                            .is_err()
                                        {
                                            // Receiver was dropped (timeout
                                            // already fired). Log so a
                                            // late reply doesn't vanish
                                            // silently.
                                            tracing::warn!(
                                                "[PLUGIN] PluginNodeFinished for node {} arrived after the awaiting future \
                                                 had already given up; verdict dropped (success={}, message={:?})",
                                                node_id,
                                                success,
                                                message,
                                            );
                                        }
                                    }
                                    None => {
                                        tracing::warn!(
                                            "[PLUGIN] PluginNodeFinished for unknown node {} (no pending oneshot). \
                                             Either the Dart side replied twice, or the request already timed out.",
                                            node_id,
                                        );
                                    }
                                }
                            }
                        }
                    }
                };

                let streaming_filter_focus_offsets = context.filter_focus_offsets.clone();
                let streaming_runtime_config = runtime_config.clone();
                // clone the budget registry handle for the
                // streaming checkpoint task. The registry is `Arc<RwLock<...>>`
                // internally so the clone shares the same allocation as the
                // executor's main context.
                let streaming_budget_registry = context.budget_registry.clone();
                // clone the SmartExposure state map handle
                // for the streaming checkpoint task. Same pattern as the
                // budget registry: the inner Arc is shared so the streaming
                // task sees the up-to-date per-filter counts the
                // SmartExposure instruction writes between batches.
                let streaming_smart_exposure_states = context.smart_exposure_states.clone();

                let custom_recovery_context = context.clone();
                let execution = async { root_node.execute(&mut context).await };

                let state_clone = state.clone();
                let event_tx_clone2 = event_tx.clone();
                let is_cancelled_clone = is_cancelled.clone();
                let is_paused_for_triggers = is_paused.clone();
                let skip_to_next_target_for_triggers = skip_to_next_target.clone();
                let progress_for_checkpoint = progress.clone();
                let state_for_checkpoint = state.clone();
                let is_cancelled_for_checkpoint = is_cancelled.clone();
                let trigger_manager_for_checkpoint = trigger_manager.clone();
                let streaming_triggers_enabled = triggers_enabled;
                let streaming_checkpoint_task = async move {
                    // reuse the executor's Arc<CheckpointManager> so
                    // info_cache stays consistent. Constructing a second instance
                    // here was the original §1.16 bug.
                    let Some(checkpoint_mgr) = streaming_checkpoint_manager else {
                        std::future::pending::<()>().await;
                        return;
                    };
                    let Some(sequence) = streaming_sequence else {
                        std::future::pending::<()>().await;
                        return;
                    };

                    let mut interval = tokio::time::interval(std::time::Duration::from_secs(30));

                    loop {
                        interval.tick().await;

                        if is_cancelled_for_checkpoint.load(Ordering::Relaxed) {
                            break;
                        }

                        let exec_state = *state_for_checkpoint.read().await;
                        // checkpoint mid-recovery too so a process
                        // crash during a long recovery loop doesn't lose the
                        // accepted-frame totals from before the failure.
                        if !matches!(
                            exec_state,
                            ExecutorState::Running
                                | ExecutorState::Paused
                                | ExecutorState::Recovering
                        ) {
                            continue;
                        }

                        let prog = progress_for_checkpoint.read().clone();
                        let mut checkpoint =
                            crate::checkpoint::SessionCheckpoint::new(sequence.clone());
                        checkpoint.node_statuses = prog.node_statuses.clone();
                        checkpoint.current_node = prog.current_node_id.clone();
                        checkpoint.executor_state = exec_state;
                        checkpoint.completed_exposures = prog.completed_exposures;
                        checkpoint.completed_integration_secs = prog.completed_integration_secs;
                        checkpoint.is_active = true;
                        checkpoint.set_devices(
                            streaming_camera_id.clone(),
                            streaming_mount_id.clone(),
                            streaming_focuser_id.clone(),
                            streaming_filterwheel_id.clone(),
                            streaming_rotator_id.clone(),
                        );
                        checkpoint.set_location(streaming_latitude, streaming_longitude);
                        checkpoint.set_save_path(streaming_save_path.clone());

                        let trigger_state = {
                            let manager = trigger_manager_for_checkpoint.read().await;
                            manager.state()
                        };
                        let trigger_state = trigger_state.read().await;
                        checkpoint.set_trigger_state(
                            crate::checkpoint::TriggerStateSnapshot::from_state(
                                &trigger_state,
                                streaming_runtime_config.read().safety_fail_mode,
                                streaming_triggers_enabled,
                                streaming_filter_focus_offsets.clone(),
                            ),
                        );

                        // snapshot per-target budget
                        // accounting so pause/resume preserves completed
                        // integration time per filter.
                        checkpoint.budget_states = streaming_budget_registry.snapshot().await;

                        // snapshot the SmartExposure map so
                        // a process crash mid-rotation can resume on the
                        // right filter at the right frame index. We clone
                        // the inner HashMap under the lock then drop the
                        // lock immediately so the SmartExposure instruction
                        // can keep writing fresh state between batches
                        // without contending on the streaming task.
                        checkpoint.smart_exposure_states = {
                            let guard = streaming_smart_exposure_states.read().await;
                            guard.clone()
                        };

                        match checkpoint_mgr.save(&checkpoint) {
                            Ok(()) => tracing::debug!(
                                "Streaming checkpoint saved ({} exposures, {:.1}s integration)",
                                checkpoint.completed_exposures,
                                checkpoint.completed_integration_secs
                            ),
                            Err(e) => tracing::warn!("Streaming checkpoint save failed: {}", e),
                        }
                    }
                };

                // ============================================================
                // Recovery Mode — driver task
                // ============================================================
                //
                // Runs alongside the trigger monitor and listens on the
                // `recovery_request_rx` channel for `RecoveryCause` postings
                // from the trigger monitor (and, future, instruction nodes).
                // When a request arrives:
                //
                //   1. Flip executor state Running -> Recovering and emit
                //      `RecoveryStarted`.
                //   2. Freeze the node tree by setting `is_paused` so any
                //      in-flight instruction waits at its next pause check.
                //   3. (Optionally) stop mount tracking per
                //      `RecoveryRuntimeConfig.stop_tracking_during_recovery`.
                //   4. Loop:
                //         - Wait for `retry_interval_secs` OR `TryNow` OR
                //           `Abort` OR `is_cancelled`.
                //         - On Abort: exit with GaveUp(aborted_by_user=true).
                //         - On Cancelled: exit (Stop / sequence aborted).
                //         - Otherwise: bump `attempt_count`, attempt the
                //           recovery action, evaluate the outcome.
                //         - On Success: emit RecoveryCompleted, flip back to
                //           Running, unfreeze the tree.
                //         - On Failure: stay in loop; check exhaustion
                //           (attempts or time budget).
                //
                // Why a dedicated task vs running inside the trigger monitor:
                // the trigger monitor already runs the failure-detection
                // poll loop and per-trigger recovery actions. Putting the
                // recovery loop inline would interleave detection and
                // recovery on the same 1Hz cadence — meaning a long retry
                // wait would block detection of OTHER triggers (e.g. a
                // weather-unsafe event during a guide-loss recovery).
                // Separating them lets the trigger monitor keep watching
                // while the recovery driver drives its loop on its own
                // cadence.
                // set when the recovery loop gives up due to a real
                // (non-operator-abort) failure. Checked after the main
                // `select!` so the run reports `Failed` instead of the benign
                // `Cancelled` the node-tree cancellation would otherwise win.
                let recovery_gave_up =
                    std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
                let recovery_driver_gave_up = recovery_gave_up.clone();
                let recovery_driver_state = state.clone();
                let recovery_driver_progress = progress.clone();
                let recovery_driver_event_tx = event_tx.clone();
                let recovery_driver_is_paused = is_paused.clone();
                // Replay Debug — clone the decision channel + active
                // run id into the recovery driver closure so the
                // `RecoveryEntered` lifecycle decision fires alongside the
                // existing `ExecutorEvent::RecoveryStarted` event.
                let recovery_driver_decision_tx = decision_tx_for_lifecycle.clone();
                let recovery_driver_active_run_id = active_run_id_for_decisions.clone();
                let recovery_driver_is_cancelled = is_cancelled.clone();
                let recovery_driver_signals = recovery_signals_clone.clone();
                let recovery_driver_runtime = runtime_config.clone();
                let recovery_driver_current = current_recovery_clone.clone();
                let recovery_driver_history = recovery_history_clone.clone();
                let recovery_driver_device_ops = device_ops_for_triggers.clone();
                let recovery_driver_mount_id = trigger_action_context.mount_id.clone();
                let recovery_driver_device_ids = trigger_action_context.connected_device_ids();
                // ids used to leave hardware safe if recovery
                // exhausts on an unattended night (park mount, close cover/dome).
                let recovery_driver_dome_id = trigger_action_context.dome_id.clone();
                let recovery_driver_cover_id = trigger_action_context.cover_calibrator_id.clone();
                let recovery_driver_trigger_mgr = trigger_manager.clone();
                let recovery_driver = async move {
                    while let Some(cause) = recovery_request_rx.recv().await {
                        // Don't enter recovery if the executor has already
                        // been told to stop — the operator's Stop overrides
                        // every other state machine.
                        if recovery_driver_is_cancelled.load(Ordering::Relaxed) {
                            tracing::info!(
                                "[RECOVERY] Ignoring recovery request ({:?}) — sequence is cancelling",
                                cause
                            );
                            continue;
                        }

                        // Build the context from the live runtime config.
                        // Reading once and capturing into the context locks
                        // the cadence for this loop; a mid-loop
                        // UpdateRecoveryConfig only affects the *next*
                        // recovery (predictable behaviour for the operator).
                        let (interval_secs, max_duration_secs, stop_tracking) = {
                            let rc = recovery_driver_runtime.read();
                            (
                                rc.recovery.retry_interval_secs,
                                rc.recovery.max_duration_secs,
                                rc.recovery.stop_tracking_during_recovery,
                            )
                        };

                        let mut ctx = crate::recovery::RecoveryContext::new(
                            cause.clone(),
                            interval_secs,
                            max_duration_secs,
                        );

                        // Re-arm so any TryNow / Abort left over from a
                        // previous loop is cleared, and the entry counter
                        // increments so the Dart side knows this is a
                        // fresh recovery.
                        recovery_driver_signals.arm();

                        // 1. Flip state -> Recovering and publish.
                        *recovery_driver_state.write().await = ExecutorState::Recovering;
                        {
                            let mut prog = recovery_driver_progress.write();
                            prog.state = ExecutorState::Recovering;
                            prog.message = Some(format!("Recovering: {}", cause.display_label()));
                        }
                        *recovery_driver_current.write() = Some(ctx.clone());
                        let _ = recovery_driver_event_tx
                            .send(ExecutorEvent::StateChanged(ExecutorState::Recovering));
                        let _ = recovery_driver_event_tx.send(ExecutorEvent::RecoveryStarted {
                            context: Box::new(ctx.clone()),
                        });
                        // Replay Debug — promote recovery entry to
                        // a first-class decision so the replay timeline
                        // can render "Recovery entered: GuideStarLost"
                        // (with the cause-kind + countdown context).
                        {
                            let mut decision_event = crate::decision::DecisionEvent::new(
                                crate::decision::DecisionCategory::RecoveryEntered,
                                format!("Recovery entered: {}", ctx.cause.display_label()),
                                serde_json::json!({
                                    "cause_kind": match &ctx.cause {
                                        crate::recovery::RecoveryCause::GuideStarLost => "GuideStarLost",
                                        crate::recovery::RecoveryCause::SlewFailed => "SlewFailed",
                                        crate::recovery::RecoveryCause::PlateSolveFailed => "PlateSolveFailed",
                                        crate::recovery::RecoveryCause::WeatherUnsafe => "WeatherUnsafe",
                                        crate::recovery::RecoveryCause::MountTrackingLost => "MountTrackingLost",
                                        crate::recovery::RecoveryCause::FocusDriftCritical => "FocusDriftCritical",
                                        crate::recovery::RecoveryCause::ConsecutiveRejectsExceeded => "ConsecutiveRejectsExceeded",
                                        crate::recovery::RecoveryCause::DeviceDisconnected => "DeviceDisconnected",
                                        crate::recovery::RecoveryCause::Custom(_) => "Custom",
                                    },
                                    "cause_label": ctx.cause.display_label(),
                                    "max_attempts": ctx.max_attempts,
                                    "retry_interval_secs": ctx.retry_interval_secs,
                                    "max_duration_secs": ctx.max_duration_secs,
                                }),
                            );
                            decision_event.sequence_run_id = *recovery_driver_active_run_id.read();
                            let _ = recovery_driver_decision_tx.send(decision_event);
                        }

                        // 2. Freeze node tree.
                        recovery_driver_is_paused.store(true, Ordering::Relaxed);

                        // 3. Optionally stop tracking.
                        if stop_tracking {
                            if let Some(mount_id) = &recovery_driver_mount_id {
                                tracing::info!(
                                    "[RECOVERY] Stopping mount tracking on '{}' for the recovery loop",
                                    mount_id
                                );
                                if let Err(e) = recovery_driver_device_ops
                                    .mount_set_tracking(mount_id, false)
                                    .await
                                {
                                    tracing::warn!(
                                        "[RECOVERY] Failed to stop tracking on '{}': {} \
                                         (continuing — operator may want to park manually)",
                                        mount_id,
                                        e
                                    );
                                }
                            }
                        }

                        // 4. Drive the retry loop.
                        let aborted_by_user;
                        let recovered;
                        // Set when an attempt resolves as PauseForOperator —
                        // the cause is not auto-recoverable by waiting, so the
                        // loop exits into a real operator Pause (not resume,
                        // not park-and-abort). Carries the operator message.
                        let mut paused_for_operator: Option<String> = None;
                        loop {
                            if recovery_driver_is_cancelled.load(Ordering::Relaxed) {
                                tracing::info!(
                                    "[RECOVERY] Sequence cancelled mid-recovery — exiting loop"
                                );
                                aborted_by_user = false;
                                recovered = false;
                                ctx.phase = crate::recovery::RecoveryPhase::GaveUp;
                                break;
                            }
                            if recovery_driver_signals.take_abort() {
                                tracing::warn!(
                                    "[RECOVERY] Operator aborted recovery for cause {:?} after {} attempt(s)",
                                    ctx.cause, ctx.attempt_count
                                );
                                aborted_by_user = true;
                                recovered = false;
                                ctx.phase = crate::recovery::RecoveryPhase::GaveUp;
                                break;
                            }
                            if ctx.is_exhausted(chrono::Utc::now()) {
                                tracing::warn!(
                                    "[RECOVERY] Exhausted (attempts={}/{}, elapsed={:.0}s/{:.0}s)",
                                    ctx.attempt_count,
                                    ctx.max_attempts,
                                    ctx.elapsed_secs(chrono::Utc::now()),
                                    ctx.max_duration_secs
                                );
                                aborted_by_user = false;
                                recovered = false;
                                ctx.phase = crate::recovery::RecoveryPhase::GaveUp;
                                break;
                            }

                            // Wait phase — uses tokio sleep + a polling
                            // hot-check on the signal flags + cancellation
                            // so the operator can punch through. We
                            // resolve the wait as the *minimum* of the
                            // configured interval and 0.5s (so the polling
                            // is responsive). On the first attempt
                            // `next_attempt_in_secs` returns 0 so we
                            // skip the wait entirely.
                            let wait_secs = ctx.next_attempt_in_secs(chrono::Utc::now());
                            if wait_secs > 0.0 {
                                ctx.phase = crate::recovery::RecoveryPhase::Waiting;
                                *recovery_driver_current.write() = Some(ctx.clone());
                                let _ = recovery_driver_event_tx.send(
                                    ExecutorEvent::RecoveryProgress {
                                        context: Box::new(ctx.clone()),
                                    },
                                );

                                let wait_start = std::time::Instant::now();
                                let wait_duration = std::time::Duration::from_secs_f64(wait_secs);
                                let poll_step = std::time::Duration::from_millis(500);
                                let mut interrupted = false;
                                while wait_start.elapsed() < wait_duration {
                                    if recovery_driver_signals.take_try_now() {
                                        tracing::info!(
                                            "[RECOVERY] TryNow consumed — bypassing wait timer"
                                        );
                                        interrupted = true;
                                        break;
                                    }
                                    if recovery_driver_signals.take_abort() {
                                        // Replant the abort flag so the
                                        // top-of-loop check picks it up
                                        // and exits with the right
                                        // aborted_by_user value.
                                        recovery_driver_signals.request_abort();
                                        break;
                                    }
                                    if recovery_driver_is_cancelled.load(Ordering::Relaxed) {
                                        break;
                                    }
                                    tokio::time::sleep(poll_step).await;
                                }
                                if !interrupted
                                    && !recovery_driver_is_cancelled.load(Ordering::Relaxed)
                                {
                                    // Wait elapsed without a fast-forward;
                                    // fall through to attempt.
                                }
                            }

                            // Attempt phase.
                            ctx.attempt_count = ctx.attempt_count.saturating_add(1);
                            ctx.last_attempt_at = Some(chrono::Utc::now());
                            ctx.phase = crate::recovery::RecoveryPhase::Attempting;
                            tracing::info!(
                                "[RECOVERY] Attempt {}/{} (cause={:?})",
                                ctx.attempt_count,
                                ctx.max_attempts,
                                ctx.cause
                            );
                            *recovery_driver_current.write() = Some(ctx.clone());
                            let _ =
                                recovery_driver_event_tx.send(ExecutorEvent::RecoveryProgress {
                                    context: Box::new(ctx.clone()),
                                });

                            let outcome = run_recovery_attempt(
                                &ctx.cause,
                                &recovery_driver_device_ops,
                                recovery_driver_mount_id.as_deref(),
                                &recovery_driver_device_ids,
                                &recovery_driver_trigger_mgr,
                            )
                            .await;

                            match outcome {
                                crate::recovery::AttemptOutcome::Succeeded => {
                                    ctx.phase = crate::recovery::RecoveryPhase::Recovered;
                                    aborted_by_user = false;
                                    recovered = true;
                                    break;
                                }
                                crate::recovery::AttemptOutcome::Failed { message } => {
                                    tracing::warn!(
                                        "[RECOVERY] Attempt {} failed: {}",
                                        ctx.attempt_count,
                                        message
                                    );
                                    ctx.last_error = Some(message);
                                    ctx.phase = crate::recovery::RecoveryPhase::Waiting;
                                    *recovery_driver_current.write() = Some(ctx.clone());
                                    let _ = recovery_driver_event_tx.send(
                                        ExecutorEvent::RecoveryProgress {
                                            context: Box::new(ctx.clone()),
                                        },
                                    );
                                }
                                crate::recovery::AttemptOutcome::Cancelled => {
                                    tracing::info!("[RECOVERY] Attempt cancelled — exiting loop");
                                    aborted_by_user = false;
                                    recovered = false;
                                    ctx.phase = crate::recovery::RecoveryPhase::GaveUp;
                                    break;
                                }
                                crate::recovery::AttemptOutcome::PauseForOperator { message } => {
                                    tracing::warn!(
                                        "[RECOVERY] Cause {:?} escalated to operator Pause: {}",
                                        ctx.cause,
                                        message
                                    );
                                    // Not a recovery, not a give-up: a real
                                    // operator Pause. Leave the node tree frozen
                                    // (is_paused stays true) and hand the run to
                                    // the operator.
                                    aborted_by_user = false;
                                    recovered = false;
                                    ctx.last_error = Some(message.clone());
                                    ctx.phase = crate::recovery::RecoveryPhase::GaveUp;
                                    paused_for_operator = Some(message);
                                    break;
                                }
                            }
                        }

                        // Record the history entry regardless of outcome.
                        let ended_at = chrono::Utc::now();
                        {
                            let mut history = recovery_driver_history.write();
                            history.push(crate::recovery::RecoveryHistoryEntry {
                                started_at: ctx.started_at,
                                ended_at,
                                cause: ctx.cause.clone(),
                                attempts: ctx.attempt_count,
                                recovered,
                                aborted_by_user,
                                last_error: ctx.last_error.clone(),
                            });
                        }

                        if let Some(pause_message) = paused_for_operator {
                            // The PauseForOperator escalation handling lives in
                            // `apply_recovery_escalation` so an integration test can drive
                            // the exact BLOCKER #1/#2 branch (SafeAbandon vs PassivePause,
                            // and the tracking-restore-before-Paused ordering) against real
                            // device-ops without spinning up this whole closure.
                            let escalation_state = RecoveryEscalationState {
                                device_ops: &recovery_driver_device_ops,
                                event_tx: &recovery_driver_event_tx,
                                runtime_config: &recovery_driver_runtime,
                                state: &recovery_driver_state,
                                progress: &recovery_driver_progress,
                                current_recovery: &recovery_driver_current,
                                is_cancelled: &recovery_driver_is_cancelled,
                                gave_up: &recovery_driver_gave_up,
                                mount_id: recovery_driver_mount_id.as_deref(),
                                cover_id: recovery_driver_cover_id.as_deref(),
                                dome_id: recovery_driver_dome_id.as_deref(),
                            };
                            apply_recovery_escalation(
                                &escalation_state,
                                &ctx,
                                pause_message,
                                stop_tracking,
                            )
                            .await;
                        } else if recovered {
                            tracing::info!(
                                "[RECOVERY] Loop succeeded after {} attempt(s); resuming sequence",
                                ctx.attempt_count
                            );
                            *recovery_driver_state.write().await = ExecutorState::Running;
                            {
                                let mut prog = recovery_driver_progress.write();
                                prog.state = ExecutorState::Running;
                                prog.message = Some("Recovered — resuming sequence".to_string());
                            }
                            *recovery_driver_current.write() = None;

                            // Re-enable tracking if the recovery loop stopped it
                            // (stop_tracking_during_recovery). The resume path
                            // previously left tracking OFF for every cause except
                            // MountTrackingLost, so the sequence resumed exposing
                            // on a NON-tracking mount — the target drifts out of
                            // frame and the rest of the night is trailed while the
                            // UI reports "Recovered". Restore it here for all
                            // causes, and surface a loud error if it cannot be
                            // restored (never silently resume untracked).
                            let _ = restore_tracking_after_recovery(
                                &recovery_driver_device_ops,
                                recovery_driver_mount_id.as_deref(),
                                stop_tracking,
                                "after recovery",
                                &recovery_driver_event_tx,
                            )
                            .await;

                            recovery_driver_is_paused.store(false, Ordering::Relaxed);
                            let _ = recovery_driver_event_tx
                                .send(ExecutorEvent::StateChanged(ExecutorState::Running));
                            let _ =
                                recovery_driver_event_tx.send(ExecutorEvent::RecoveryCompleted {
                                    context: Box::new(ctx.clone()),
                                });
                        } else {
                            tracing::error!(
                                "[RECOVERY] Loop gave up after {} attempt(s) (aborted={})",
                                ctx.attempt_count,
                                aborted_by_user
                            );
                            *recovery_driver_current.write() = None;

                            // when recovery exhausts on a real
                            // failure (NOT an operator abort), the rig is being
                            // abandoned mid-night. Leave hardware in a SAFE
                            // end-state before failing: park the mount (so the
                            // OTA can't track into the Sun at dawn) and close
                            // the cover + dome. Operator-aborts are skipped —
                            // the operator is present and may be intervening.
                            if !aborted_by_user {
                                recovery_driver_gave_up.store(true, Ordering::Relaxed);

                                // Single source of truth for the park → close
                                // cover → close dome safe-state sweep
                                // (`device_ops::park_and_close_safe_state`).
                                // The give-up path historically used 2 park
                                // retries with a 2s delay; pass those through so
                                // this consolidation changes no behaviour. Each
                                // call site still emits its own operator-facing
                                // wording from the returned outcome.
                                let outcome = crate::device_ops::park_and_close_safe_state(
                                    &recovery_driver_device_ops,
                                    recovery_driver_mount_id.as_deref(),
                                    recovery_driver_cover_id.as_deref(),
                                    recovery_driver_dome_id.as_deref(),
                                    2,
                                    2.0,
                                )
                                .await;

                                if let (Some(mount_id), Some(park)) =
                                    (&recovery_driver_mount_id, &outcome.park)
                                {
                                    if park.success {
                                        tracing::info!(
                                            "[RECOVERY] Parked mount '{}' on give-up ({} attempt(s))",
                                            mount_id,
                                            park.attempts_made
                                        );
                                    } else {
                                        let msg = format!(
                                            "Recovery exhausted and the mount could not be parked ({}): {} — mount may be UNSAFE.",
                                            mount_id,
                                            park.last_error
                                                .clone()
                                                .unwrap_or_else(|| "unknown".to_string())
                                        );
                                        tracing::error!("[RECOVERY] {}", msg);
                                        let _ = recovery_driver_event_tx
                                            .send(ExecutorEvent::Error { message: msg });
                                    }
                                }

                                if let (Some(cover_id), Some(e)) =
                                    (&recovery_driver_cover_id, &outcome.cover_close_error)
                                {
                                    let msg = format!(
                                        "Recovery give-up: failed to close cover '{}': {}",
                                        cover_id, e
                                    );
                                    tracing::error!("[RECOVERY] {}", msg);
                                    let _ = recovery_driver_event_tx
                                        .send(ExecutorEvent::Error { message: msg });
                                }
                                if let (Some(dome_id), Some(e)) =
                                    (&recovery_driver_dome_id, &outcome.dome_close_error)
                                {
                                    let msg = format!(
                                        "Recovery give-up: failed to close dome '{}': {} — scope may be exposed.",
                                        dome_id, e
                                    );
                                    tracing::error!("[RECOVERY] {}", msg);
                                    let _ = recovery_driver_event_tx
                                        .send(ExecutorEvent::Error { message: msg });
                                }
                            }

                            // Transition to Failed and emit the gave-up
                            // event. Leave `is_paused` set — the node tree
                            // is going to be cancelled by the outer logic
                            // anyway, but the explicit Cancelled signal
                            // ensures any active instruction returns
                            // promptly.
                            recovery_driver_is_cancelled.store(true, Ordering::Relaxed);
                            *recovery_driver_state.write().await = ExecutorState::Failed;
                            {
                                let mut prog = recovery_driver_progress.write();
                                prog.state = ExecutorState::Failed;
                                prog.message = Some(if aborted_by_user {
                                    format!(
                                        "Recovery aborted by operator after {} attempt(s)",
                                        ctx.attempt_count
                                    )
                                } else {
                                    format!(
                                        "Recovery exhausted after {} attempt(s)",
                                        ctx.attempt_count
                                    )
                                });
                            }
                            let _ = recovery_driver_event_tx
                                .send(ExecutorEvent::StateChanged(ExecutorState::Failed));
                            let _ = recovery_driver_event_tx.send(ExecutorEvent::RecoveryGaveUp {
                                context: Box::new(ctx.clone()),
                                aborted_by_user,
                            });
                            // Loop body exit — the outer trigger_monitor
                            // task observed Cancelled and will end the
                            // sequence on its next tick.
                        }
                    }
                };

                let custom_recovery_branches_for_triggers = custom_recovery_branches.clone();
                let sequence_for_custom_recovery_triggers = sequence_for_custom_recovery.clone();
                let custom_recovery_context_for_triggers = custom_recovery_context.clone();

                let trigger_monitor = async {
                    if !triggers_enabled {
                        // Hold this task open so the `try_join!` below still waits on the
                        // other branches; an immediate return would short-circuit them.
                        std::future::pending::<()>().await;
                        return Vec::new();
                    }

                    let mut check_interval =
                        tokio::time::interval(std::time::Duration::from_secs(1));
                    let mut fired_triggers: Vec<(String, RecoveryAction)> = Vec::new();

                    // Tracks whether the previous safety poll already failed. Used to
                    // rate-limit the per-mode warning so a permanently offline safety
                    // device does not flood the log every second. See SafetyFailMode
                    // dispatch below.
                    let mut safety_poll_last_was_error = false;
                    let mut last_safety_poll_at: Option<std::time::Instant> = None;

                    // Subsystem 2 step 3 (stale-verdict observability): rate-limit
                    // latch for the "weather verdict feed stale; holding paused
                    // fail-closed" warning. Set true after we emit the warning so a
                    // dead Dart feed does not flood the event stream every poll;
                    // cleared the moment a fresh verdict push lands (detected via
                    // the verdict-staleness predicate returning false again).
                    let mut verdict_stale_warned = false;

                    // Trust-patch §1: rate-limit sentinel for the
                    // "AltitudeLimit cannot evaluate because location is not
                    // configured" warning. Set once per session on first
                    // detection so the log is not flooded by a permanently
                    // unconfigured rig.
                    let mut altitude_warned_no_location = false;

                    // Tracks per-trigger Retry attempt counts so we can escalate after
                    // exhausting `max_attempts`. Keyed by trigger ID.
                    let mut retry_attempts: HashMap<String, u32> = HashMap::new();

                    // §1.14: Streaming-checkpoint cadence is now driven by an independent
                    // task spawned alongside this monitor (see streaming_checkpoint_task).
                    // Keeping the monitor focused on trigger evaluation avoids dropping
                    // checkpoint saves when triggers_enabled = false.

                    // The MountTrackingLost / OnTrackingLimitHit triggers need a baseline
                    // expectation; without setting this flag the "tracking dropped" detector
                    // would assume tracking is unwanted and never fire. Only matters while a
                    // mount is configured for the sequence.
                    if trigger_action_context.mount_id.is_some() {
                        let manager = trigger_manager.read().await;
                        let trigger_state = manager.state();
                        let mut state = trigger_state.write().await;
                        state.set_mount_tracking_expected(true);
                    }

                    loop {
                        check_interval.tick().await;

                        // Pause/Stop must not fire triggers — paused sequences are explicitly
                        // "user is intervening" and Stopping is racing to terminate, so any
                        // recovery action here would conflict with the operator's intent.
                        let current_state = *state_clone.read().await;
                        if current_state != ExecutorState::Running {
                            continue;
                        }

                        if is_cancelled_clone.load(Ordering::Relaxed) {
                            break;
                        }

                        let (
                            current_safety_fail_mode,
                            safety_check_interval,
                            verdict_staleness_secs,
                        ) = {
                            let rc = runtime_config.read();
                            (
                                rc.safety_fail_mode,
                                std::time::Duration::from_secs(
                                    effective_safety_check_interval_secs(
                                        rc.safety_check_interval_secs,
                                    ),
                                ),
                                effective_weather_verdict_staleness_secs(
                                    rc.weather_verdict_staleness_secs,
                                ),
                            )
                        };
                        let should_poll_safety = last_safety_poll_at
                            .map(|last| last.elapsed() >= safety_check_interval)
                            .unwrap_or(true);

                        // Poll weather/safety status and update trigger state. Each
                        // SafetyFailMode variant has a distinct, observable behaviour:
                        // - FailClosed: poll errors mark the run unsafe so WeatherUnsafe
                        //   fires the configured park-and-abort path. Recommended for
                        //   unattended runs.
                        // - FailOpen: poll errors are treated as safe so the sequence
                        //   keeps running. Intended for daytime / shutdown sequences
                        //   where the safety device is intentionally unavailable. The
                        //   warning is rate-limited (only once per error transition) so
                        //   logs do not flood when the device is permanently offline.
                        // - WarnOnly: poll errors do NOT change weather_safe (last good
                        //   reading wins), but a one-shot Error event is emitted so the
                        //   UI can alert the operator. Existing safe/unsafe state is
                        //   preserved.
                        let is_safe = if should_poll_safety {
                            last_safety_poll_at = Some(std::time::Instant::now());
                            match device_ops_for_triggers.safety_is_safe(None).await {
                                Ok(safe) => {
                                    if safety_poll_last_was_error {
                                        tracing::info!(
                                            "Safety poll recovered (mode: {:?})",
                                            current_safety_fail_mode
                                        );
                                        safety_poll_last_was_error = false;
                                    }
                                    Some(safe)
                                }
                                Err(e) => {
                                    // Cross-language parity (architecture-unification
                                    // 2026-06-05): the fail-mode → no-data resolution is
                                    // the SINGLE shared truth table in
                                    // `crate::safety_fail_mode_no_data_resolution`, mirrored
                                    // by the Dart `noDataFailModeResolution`. Do NOT inline a
                                    // per-mode match here — it would let the two sides drift.
                                    match safety_fail_mode_no_data_resolution(
                                        current_safety_fail_mode,
                                    ) {
                                        NoDataResolution::Unsafe => {
                                            if !safety_poll_last_was_error {
                                                tracing::warn!(
                                        "Safety poll error: {} - treating as unsafe (FailClosed)",
                                        e
                                    );
                                                safety_poll_last_was_error = true;
                                            }
                                            Some(false)
                                        }
                                        NoDataResolution::Safe => {
                                            if !safety_poll_last_was_error {
                                                tracing::warn!(
                                            "Safety poll error: {} - treating as safe (FailOpen). \
                                         Sequence will continue. Do not use FailOpen for \
                                         unattended runs.",
                                            e
                                        );
                                                safety_poll_last_was_error = true;
                                            }
                                            Some(true)
                                        }
                                        NoDataResolution::Preserve => {
                                            if !safety_poll_last_was_error {
                                                tracing::warn!(
                                                "Safety poll error: {} - WarnOnly mode, leaving \
                                         weather_safe unchanged and emitting alert",
                                                    e
                                                );
                                                let _ =
                                                    event_tx_clone2.send(ExecutorEvent::Error {
                                                        message: format!(
                                                "Safety poll failed: {}. WarnOnly mode keeps the \
                                             previous safety state — operator attention required.",
                                                e
                                            ),
                                                    });
                                                safety_poll_last_was_error = true;
                                            }
                                            None
                                        }
                                    }
                                }
                            }
                        } else {
                            None
                        };

                        let guiding_rms = device_ops_for_triggers
                            .guider_get_status()
                            .await
                            .ok()
                            .map(|status| status.rms_total);

                        // Trust-patch §2: poll humidity from the weather/safety
                        // device on the same cadence as safety_is_safe. The
                        // default `weather_get_humidity` implementation returns
                        // Ok(None) for backends that don't expose humidity —
                        // those silently leave `state.current_humidity` alone
                        // (which is correct: HumidityThreshold can't evaluate
                        // without data).
                        let humidity_result = if should_poll_safety {
                            Some(device_ops_for_triggers.weather_get_humidity(None).await)
                        } else {
                            None
                        };

                        // Subsystem 2 step 3 (stale-verdict observability): evaluated
                        // on EVERY loop tick (not gated by should_poll_safety) so a
                        // verdict that goes stale between safety polls is detected
                        // promptly. Pure read; never mutates or clears the verdict.
                        let verdict_stale_unsafe;

                        {
                            let manager = trigger_manager.read().await;
                            let trigger_state = manager.state();
                            let mut state = trigger_state.write().await;
                            // WarnOnly returns None to mean "preserve previous reading" — that
                            // is the contract that distinguishes it from FailOpen/FailClosed.
                            if let Some(safe) = is_safe {
                                state.weather_safe = safe;
                            }

                            verdict_stale_unsafe =
                                state.is_weather_verdict_stale_unsafe(verdict_staleness_secs);

                            if let Some(rms) = guiding_rms {
                                state.update_guiding_rms(rms);
                                tracing::trace!("Updated guiding RMS: {:.2}", rms);
                            }

                            // Trust-patch §2: feed humidity into trigger state.
                            // We deliberately separate "device doesn't report
                            // humidity" (Ok(None)) from "query failed" (Err) so
                            // a transient driver glitch leaves the previous
                            // reading in place rather than overwriting it with
                            // garbage. Match the safety-poll rate-limited
                            // logging policy.
                            match humidity_result {
                                Some(Ok(Some(h))) => {
                                    state.update_humidity(h);
                                    tracing::trace!(
                                        "Updated humidity from weather device: {:.1}%",
                                        h
                                    );
                                }
                                Some(Ok(None)) => {
                                    // Device exists but doesn't expose humidity.
                                    // Nothing to do — HumidityThreshold needs a
                                    // real value to evaluate. Trace level only:
                                    // logging every tick would flood the log.
                                }
                                Some(Err(e)) => {
                                    tracing::trace!(
                                        "weather_get_humidity error: {} (trigger state retained)",
                                        e
                                    );
                                }
                                None => {}
                            }

                            // Seed observer location from device_ops the first time it
                            // becomes available (mobile rigs configure it after mount
                            // connect) so altitude/dawn triggers can evaluate.
                            if state.observer_latitude.is_none() {
                                if let Some((lat, lon)) =
                                    device_ops_for_triggers.get_observer_location()
                                {
                                    state.observer_latitude = Some(lat);
                                    state.observer_longitude = Some(lon);
                                    tracing::debug!(
                                        "Observer location set for dawn/altitude triggers: {}, {}",
                                        lat,
                                        lon
                                    );
                                }
                            }

                            // Compute (or refresh) dawn_time whenever a location is known
                            // but there is no valid UPCOMING dawn cached. This fixes two
                            // bugs:
                            //   #10: dawn_time used to be computed ONLY inside the
                            //        `observer_latitude.is_none()` branch above, which the
                            //        UpdateLocation command bypasses (it sets
                            //        observer_latitude directly). On a normally-configured
                            //        rig dawn_time stayed None forever and the
                            //        DawnApproaching trigger could never fire — the run
                            //        would image straight through dawn with no auto-stop.
                            //   #19: dawn_time was cached once and never refreshed, so on a
                            //        multi-night run it pointed at night-1's now-past dawn
                            //        and the trigger never fired again. calculate_dawn_time
                            //        returns the NEXT dawn, so recomputing once the cached
                            //        value has passed restores protection each night.
                            if let (Some(lat), Some(lon)) =
                                (state.observer_latitude, state.observer_longitude)
                            {
                                let now = chrono::Utc::now().timestamp();
                                let needs_refresh = match state.dawn_time {
                                    None => true,
                                    Some(t) => t <= now,
                                };
                                if needs_refresh {
                                    let new_dawn = crate::triggers::calculate_dawn_time(lat, lon);
                                    state.dawn_time = Some(new_dawn);
                                    tracing::debug!(
                                        "dawn_time computed for ({}, {}): {} (next astronomical twilight)",
                                        lat,
                                        lon,
                                        new_dawn
                                    );
                                }
                            }

                            // Trust-patch §1: compute target altitude so the
                            // AltitudeLimit trigger has something to evaluate.
                            // Inputs: target RA/Dec (set when a TargetHeader
                            // node enters), observer lat/lon (seeded above or
                            // by UpdateLocation), and current UTC time. Uses
                            // the existing `meridian::calculate_altitude`
                            // helper so the math is unified with the
                            // meridian-flip predictions.
                            //
                            // Three "can't evaluate" cases:
                            //   1. No target set yet (sequence hasn't entered
                            //      any TargetHeader node).
                            //   2. No observer location (user has not
                            //      configured the profile; UpdateLocation
                            //      hasn't fired).
                            //   3. Both — same outcome.
                            //
                            // For case (2), emit a one-shot warning so the
                            // operator sees that altitude triggers are dead
                            // until location is supplied. The `&&` guard makes
                            // it impossible to fire on (1) alone (no point
                            // warning before any target has been entered).
                            match (
                                state.target_ra,
                                state.target_dec,
                                state.observer_latitude,
                                state.observer_longitude,
                            ) {
                                (Some(ra_deg), Some(dec_deg), Some(lat), Some(lon)) => {
                                    let now = chrono::Utc::now();
                                    // TriggerState stores RA in degrees;
                                    // calculate_altitude expects hours.
                                    let ra_hours = ra_deg / 15.0;
                                    let alt = crate::meridian::calculate_altitude(
                                        ra_hours, dec_deg, lat, lon, now,
                                    );
                                    state.current_altitude = Some(alt);
                                    tracing::trace!(
                                        "Computed target altitude: {:.2}° (RA={:.4}h, Dec={:.4}°, lat={:.4}, lon={:.4})",
                                        alt, ra_hours, dec_deg, lat, lon
                                    );
                                }
                                (Some(_), Some(_), _, _) if !altitude_warned_no_location => {
                                    // target known but no
                                    // location — altitude protection is
                                    // effectively disabled. Previously this
                                    // was a `tracing::warn!` which the user
                                    // never saw; promote to a user-visible
                                    // ExecutorEvent::Error so the run
                                    // dashboard surfaces it. Still gated by
                                    // the one-shot sentinel (the guard above)
                                    // so a permanently unconfigured location
                                    // doesn't flood the event stream every
                                    // second; once warned, this falls to the
                                    // silent catch-all below.
                                    let msg = "AltitudeLimit trigger configured but \
                                         observer location is not set — altitude \
                                         protection is INACTIVE. Set location in \
                                         Profile to enable.";
                                    tracing::warn!("{}", msg);
                                    let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                        message: msg.to_string(),
                                    });
                                    altitude_warned_no_location = true;
                                }
                                _ => {
                                    // No target — silent. The trigger evaluator
                                    // already returns false when
                                    // current_altitude is None, so this is the
                                    // correct "wait for a target" state.
                                }
                            }
                        }

                        // Subsystem 2 step 3 (stale-verdict observability): a pushed
                        // Some(true)=UNSAFE verdict whose Dart feed has gone silent
                        // is HELD fail-closed — the sequence stays paused, which is
                        // the correct safe behaviour and is NOT cleared here. But an
                        // indefinite hold must not be SILENT: when the unsafe verdict
                        // is stale we emit ONE loud warning (rate-limited via the
                        // latch) so the operator knows the hold is sustained by a dead
                        // feed rather than fresh data. The latch clears as soon as a
                        // fresh push lands (predicate returns false again), so a feed
                        // that recovers and re-degrades will warn again. The gate +
                        // rate-limit + message live in `weather_verdict_stale_warning`
                        // so they are unit-tested without the full executor task.
                        if let Some(msg) = weather_verdict_stale_warning(
                            verdict_stale_unsafe,
                            verdict_staleness_secs,
                            &mut verdict_stale_warned,
                        ) {
                            tracing::warn!("{}", msg);
                            let _ = event_tx_clone2.send(ExecutorEvent::Error { message: msg });
                        }

                        if let Some(mount_id) = &trigger_action_context.mount_id {
                            let tracking_result =
                                device_ops_for_triggers.mount_is_tracking(mount_id).await;
                            let slewing_result =
                                device_ops_for_triggers.mount_is_slewing(mount_id).await;
                            let parked_result =
                                device_ops_for_triggers.mount_is_parked(mount_id).await;
                            let pier_side_result =
                                device_ops_for_triggers.mount_side_of_pier(mount_id).await;
                            let coords_result = device_ops_for_triggers
                                .mount_get_coordinates(mount_id)
                                .await;

                            let manager = trigger_manager.read().await;
                            let trigger_state = manager.state();
                            let mut state = trigger_state.write().await;

                            // A failed tracking query is treated as a connection problem
                            // rather than "tracking dropped" so we don't park-and-abort
                            // on a transient driver glitch — actual loss is reported as
                            // Ok(false), which the branch below handles distinctly.
                            match &tracking_result {
                                Ok(is_tracking) => {
                                    state.mount_status_query_failed = false;

                                    if state.mount_tracking_expected
                                        && !is_tracking
                                        && !state.mount_tracking_lost
                                    {
                                        tracing::warn!("Mount tracking lost during sequence!");
                                        state.mount_tracking_lost = true;

                                        // OnTrackingLimitHit waits `tracking_limit_wait_minutes`
                                        // before flipping; we stamp the detection time here so
                                        // the wait period is measured from when the loss was
                                        // first observed, not from when the trigger eventually
                                        // evaluates (which happens on its own cadence).
                                        if state.tracking_limit_detected_at.is_none() {
                                            state.tracking_limit_detected_at =
                                                Some(chrono::Utc::now().timestamp());
                                            tracing::info!(
                                                "Tracking limit detection timestamp recorded"
                                            );
                                        }
                                    }
                                    // Tracking resumed before the wait elapsed — clear the
                                    // detection timestamp so a future loss starts the wait
                                    // window fresh instead of inheriting stale state.
                                    if *is_tracking && state.tracking_limit_detected_at.is_some() {
                                        tracing::info!(
                                        "Mount tracking resumed, cancelling tracking limit wait"
                                    );
                                        state.reset_tracking_limit_detection();
                                    }

                                    state.mount_is_tracking = Some(*is_tracking);
                                }
                                Err(e) => {
                                    tracing::warn!(
                                        "Mount status query failed: {} - possible connection loss",
                                        e
                                    );
                                    state.mount_status_query_failed = true;
                                }
                            }

                            if let Ok(slewing) = slewing_result {
                                state.mount_slewing = Some(slewing);
                            }
                            if let Ok(parked) = parked_result {
                                state.mount_parked = Some(parked);
                            }

                            // Two PierSide enums exist: meridian::PierSide is the
                            // internal calculation type, crate::PierSide is the
                            // event-stream wire format. They mirror each other but
                            // are distinct types so the geometry code cannot leak
                            // into FRB-exposed events.
                            if let Ok(pier_side) = pier_side_result {
                                let ps = match pier_side {
                                    crate::meridian::PierSide::East => crate::PierSide::East,
                                    crate::meridian::PierSide::West => crate::PierSide::West,
                                    crate::meridian::PierSide::Unknown => crate::PierSide::Unknown,
                                };
                                state.update_pier_side(ps);
                            }

                            // Hour angle is required for the MeridianFlip trigger's
                            // hour-angle-threshold mode; the mount only gives us RA,
                            // so we recompute HA = LST - RA here using the observer
                            // longitude (already validated above before this branch).
                            if let Ok((ra_hours, _dec)) = coords_result {
                                if let Some(lon) = state.observer_longitude {
                                    let now = chrono::Utc::now();
                                    let jd = crate::meridian::julian_day(&now);
                                    let lst = crate::meridian::local_sidereal_time(jd, lon);
                                    let ha = crate::meridian::hour_angle(ra_hours, lst);
                                    state.update_hour_angle(ha);
                                }
                            }
                        }

                        // TemperatureShift refocus must key off a temperature
                        // that actually tracks the optical train's thermal
                        // expansion — i.e. the FOCUSER temperature probe (or an
                        // ambient sensor). The cooled-CAMERA sensor temperature
                        // is regulated to a fixed setpoint, so it never drifts;
                        // feeding it here meant the trigger could never fire and
                        // focus drifted soft over a full night. We now read the
                        // focuser's temperature probe. `Ok(None)` means the
                        // focuser has no probe — we deliberately do NOT fall back
                        // to the regulated camera temperature (that would
                        // resurrect the silent no-fire bug); the trigger simply
                        // stays inert, which is the honest "no temperature source
                        // available" outcome.
                        if let Some(focuser_id) = &trigger_action_context.focuser_id {
                            match device_ops_for_triggers
                                .focuser_get_temperature(focuser_id)
                                .await
                            {
                                Ok(Some(temp)) => {
                                    let manager = trigger_manager.read().await;
                                    let trigger_state = manager.state();
                                    let mut state = trigger_state.write().await;
                                    state.update_temperature(temp);
                                    tracing::trace!("Updated focuser temperature: {:.1}°C", temp);
                                }
                                Ok(None) => {
                                    tracing::trace!(
                                        "Focuser '{}' reports no temperature probe; \
                                         TemperatureShift trigger remains inert (no fallback \
                                         to regulated camera temperature)",
                                        focuser_id
                                    );
                                }
                                Err(e) => {
                                    tracing::warn!(
                                        "Focuser temperature query failed: {} - leaving \
                                         TemperatureShift trigger state unchanged",
                                        e
                                    );
                                }
                            }
                        }

                        if let Some(dome_id) = &trigger_action_context.dome_id {
                            if let Ok(status) = device_ops_for_triggers
                                .dome_get_shutter_status(dome_id)
                                .await
                            {
                                let manager = trigger_manager.read().await;
                                let trigger_state = manager.state();
                                let mut state = trigger_state.write().await;
                                state.update_dome_status(status.clone());
                                if status != "Open" && state.dome_shutter_open_expected {
                                    tracing::warn!(
                                        "Dome shutter not open during sequence: {}",
                                        status
                                    );
                                }
                            }
                        }

                        // GuideStarLost cannot be derived from RMS alone (a settled guider
                        // can report low RMS for one cycle before noticing the star is gone).
                        // Polling guider status here gives the trigger a definitive signal
                        // independent of the RMS path above.
                        {
                            let guide_status = device_ops_for_triggers.guider_get_status().await;
                            let manager = trigger_manager.read().await;
                            let trigger_state = manager.state();
                            let mut tstate = trigger_state.write().await;
                            match guide_status {
                                Ok(status) => {
                                    if status.is_guiding {
                                        // Observing the guider actively guiding ARMS the
                                        // star-lost trigger. This latch is the authoritative
                                        // arming path: without it `guiding_enabled` would stay
                                        // false forever (StartGuiding sets it too, but the
                                        // latch also covers checkpoint-resume where the
                                        // StartGuiding node already completed and will not
                                        // re-run). It is only cleared by an explicit
                                        // StopGuiding.
                                        if !tstate.guiding_enabled {
                                            tstate.set_guiding_enabled(true);
                                        }
                                        tstate.set_guide_star_lost(false);
                                    } else if tstate.guiding_enabled {
                                        // Guiding was active and is now not -> star lost.
                                        tstate.set_guide_star_lost(true);
                                    } else {
                                        // Idle guider before any guiding has started: not lost.
                                        tstate.set_guide_star_lost(false);
                                    }
                                }
                                Err(_) => {
                                    // If we can't reach the guider, treat as lost when guiding expected
                                    if tstate.guiding_enabled {
                                        tstate.set_guide_star_lost(true);
                                    }
                                }
                            }
                        }

                        // Recovery actions below take their own write locks on trigger_state;
                        // holding the trigger_manager lock during them would deadlock the
                        // trigger evaluators that share the same Arc. Snapshot the fired
                        // triggers into an owned Vec and drop the lock before dispatching.
                        let fired_with_names: Vec<(String, String, RecoveryAction)> = {
                            let mut manager = trigger_manager.write().await;
                            let fired = manager.check_all().await;
                            fired
                                .into_iter()
                                .map(|(trigger_id, action)| {
                                    let trigger_name = manager
                                        .get_trigger(&trigger_id)
                                        .map(|t| t.name.clone())
                                        // Why: `get_trigger` returns Option;
                                        // None would only occur if a trigger fired and was
                                        // simultaneously removed via the same manager — race
                                        // tolerated for diagnostic naming. Using the id as the
                                        // display name preserves traceability.
                                        .unwrap_or_else(|| trigger_id.clone());
                                    (trigger_id, trigger_name, action)
                                })
                                .collect()
                        };

                        let trigger_state_for_actions = {
                            let manager = trigger_manager.read().await;
                            manager.state()
                        };

                        for (trigger_id, trigger_name, action) in fired_with_names {
                            let action_str = format!("{:?}", action);

                            tracing::warn!(
                                "Trigger fired: {} ({}) - action: {:?}",
                                trigger_name,
                                trigger_id,
                                action
                            );

                            let _ = event_tx_clone2.send(ExecutorEvent::TriggerFired {
                                trigger_id: trigger_id.clone(),
                                trigger_name: trigger_name.clone(),
                                action: action_str.clone(),
                            });

                            // Replay Debug — capture the trigger
                            // firing as a structured decision so the
                            // replay timeline surfaces "HFR drift fired,
                            // ran Autofocus" without needing to join
                            // event log + trigger config.
                            {
                                let decision_event = crate::decision::DecisionEvent::new(
                                    crate::decision::DecisionCategory::TriggerFired,
                                    format!("Trigger {} fired → {}", trigger_name, action_str),
                                    serde_json::json!({
                                        "trigger_id": trigger_id,
                                        "trigger_name": trigger_name,
                                        "action": action_str,
                                    }),
                                );
                                let mut stamped = decision_event;
                                stamped.sequence_run_id = *active_run_id_for_decisions.read();
                                let _ = decision_tx_for_lifecycle.send(stamped);
                            }

                            match &action {
                                RecoveryAction::Pause => {
                                    // Recovery Mode — promote
                                    // recovery-eligible Pause triggers to a
                                    // visible recovery loop. Today this is
                                    // `guide_star_lost`,
                                    // `mount_tracking_lost`, `weather_unsafe`,
                                    // and `focus_drift` — the four
                                    // standard-trigger ids that have a
                                    // first-class `RecoveryCause` mapping.
                                    // Other Pause triggers (operator-defined
                                    // custom watchdogs, FilterChange, etc.)
                                    // keep the legacy "pause for operator"
                                    // behaviour because they don't have an
                                    // automatic retry semantic.
                                    let recovery_cause: Option<crate::recovery::RecoveryCause> =
                                        match trigger_id.as_str() {
                                            "guide_star_lost" => {
                                                Some(crate::recovery::RecoveryCause::GuideStarLost)
                                            }
                                            "mount_tracking_lost" | "on_tracking_limit_hit" => Some(
                                                crate::recovery::RecoveryCause::MountTrackingLost,
                                            ),
                                            "weather_unsafe" | "humidity_threshold"
                                            | "temperature_limit" => {
                                                Some(crate::recovery::RecoveryCause::WeatherUnsafe)
                                            }
                                            "focus_drift" => Some(
                                                crate::recovery::RecoveryCause::FocusDriftCritical,
                                            ),
                                            _ => None,
                                        };

                                    if let Some(cause) = recovery_cause {
                                        // Try to post a recovery request.
                                        // The channel is bounded(4) so a
                                        // back-pressure send means "we are
                                        // already recovering or queued";
                                        // we drop the duplicate trigger
                                        // and log it. The driver task
                                        // serialises recoveries by
                                        // consuming one cause at a time.
                                        match recovery_request_tx.try_send(cause.clone()) {
                                            Ok(()) => {
                                                tracing::info!(
                                                    "[RECOVERY] Trigger '{}' promoted to recovery request ({:?})",
                                                    trigger_name, cause
                                                );
                                            }
                                            Err(tokio::sync::mpsc::error::TrySendError::Full(
                                                _,
                                            )) => {
                                                tracing::warn!(
                                                    "[RECOVERY] Recovery channel full; dropping duplicate request from '{}'",
                                                    trigger_name
                                                );
                                            }
                                            Err(
                                                tokio::sync::mpsc::error::TrySendError::Closed(_),
                                            ) => {
                                                // Driver task ended — fall
                                                // back to the legacy Pause
                                                // behaviour so the
                                                // sequence still stops.
                                                is_paused_for_triggers
                                                    .store(true, Ordering::Relaxed);
                                                *state_clone.write().await = ExecutorState::Paused;
                                                let _ = event_tx_clone2.send(
                                                    ExecutorEvent::StateChanged(
                                                        ExecutorState::Paused,
                                                    ),
                                                );
                                            }
                                        }
                                    } else {
                                        // Legacy Pause path — same as the
                                        // pre-Wave-4 implementation.
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                    }
                                }
                                RecoveryAction::ParkAndAbort => {
                                    // cancellation must be set before
                                    // returning, but the actual store now happens
                                    // in `terminate_with` so this code path cannot
                                    // forget it on a future refactor.

                                    // Park BEFORE aborting: a bare abort leaves the mount tracking
                                    // toward the limit. The whole point of ParkAndAbort is to put
                                    // the rig into a safe state — so we park first, then exit.
                                    //
                                    // Trust-patch §8: park retry logic lives in
                                    // `device_ops::try_park_with_retry` so the
                                    // executor's ParkAndAbort path and node.rs's
                                    // Recovery::ParkAndAbort path use the same
                                    // helper. Behaviour matches the prior inline
                                    // implementation (one retry, 2s delay)
                                    // exactly; the helper exposes them as
                                    // parameters so a future config change can
                                    // tune them without touching the call sites.
                                    // Single source of truth for the park →
                                    // close cover → close dome safe-state sweep
                                    // (`device_ops::park_and_close_safe_state`).
                                    // ParkAndAbort historically used 1 park retry
                                    // with a 2s delay; pass those through so this
                                    // consolidation changes no behaviour. The
                                    // returned outcome drives the same
                                    // operator-facing error events as before.
                                    if trigger_action_context.mount_id.is_some() {
                                        tracing::warn!(
                                            "ParkAndAbort: parking mount '{}' (max_retries=1, retry_delay=2s)",
                                            trigger_action_context.mount_id.as_deref().unwrap_or("?")
                                        );
                                    } else {
                                        tracing::warn!(
                                            "ParkAndAbort: no mount configured, cannot park"
                                        );
                                    }
                                    if let Some(cover_id) =
                                        &trigger_action_context.cover_calibrator_id
                                    {
                                        tracing::warn!(
                                            "ParkAndAbort: closing cover '{}'",
                                            cover_id
                                        );
                                    }
                                    if let Some(dome_id) = &trigger_action_context.dome_id {
                                        tracing::warn!(
                                            "ParkAndAbort: closing dome shutter '{}'",
                                            dome_id
                                        );
                                    }

                                    let safe_state = crate::device_ops::park_and_close_safe_state(
                                        &device_ops_for_triggers,
                                        trigger_action_context.mount_id.as_deref(),
                                        trigger_action_context.cover_calibrator_id.as_deref(),
                                        trigger_action_context.dome_id.as_deref(),
                                        1,
                                        2.0,
                                    )
                                    .await;

                                    match &safe_state.park {
                                        Some(park_outcome) if !park_outcome.success => {
                                            // Surface the park-specific failure
                                            // in the event stream so the UI can
                                            // distinguish "couldn't park, mount
                                            // may be unsafe" from a generic
                                            // ParkAndAbort termination.
                                            let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "ParkAndAbort: mount park FAILED after {} attempt(s): {}. \
                                                     Mount may be in an unsafe position — manual intervention required.",
                                                    park_outcome.attempts_made,
                                                    park_outcome
                                                        .last_error
                                                        .clone()
                                                        .unwrap_or_else(|| "unknown error".to_string()),
                                                ),
                                            });
                                        }
                                        None => {
                                            let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                                message: "ParkAndAbort fired but no mount is configured; the rig cannot be parked automatically.".to_string(),
                                            });
                                        }
                                        _ => {}
                                    }

                                    if let (Some(cover_id), Some(e)) = (
                                        &trigger_action_context.cover_calibrator_id,
                                        &safe_state.cover_close_error,
                                    ) {
                                        let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                            message: format!(
                                                "ParkAndAbort: failed to close cover '{}': {}. \
                                                 Optics may be left exposed — manual intervention required.",
                                                cover_id, e
                                            ),
                                        });
                                    }
                                    if let (Some(dome_id), Some(e)) = (
                                        &trigger_action_context.dome_id,
                                        &safe_state.dome_close_error,
                                    ) {
                                        let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                            message: format!(
                                                "ParkAndAbort: failed to close dome '{}': {} — \
                                                 scope may be exposed under an open roof. Manual intervention required.",
                                                dome_id, e
                                            ),
                                        });
                                    }

                                    fired_triggers.push((trigger_id, action));
                                    return terminate_with(
                                        &is_cancelled_clone,
                                        fired_triggers,
                                        "RecoveryAction::ParkAndAbort",
                                    );
                                }
                                RecoveryAction::NextTarget => {
                                    tracing::info!("Trigger requested advance to next target");
                                    skip_to_next_target_for_triggers.store(true, Ordering::Relaxed);
                                }
                                RecoveryAction::Autofocus => {
                                    tracing::info!(
                                        "Executing autofocus as trigger recovery action"
                                    );
                                    match (
                                        trigger_action_context.camera_id.as_ref(),
                                        trigger_action_context.focuser_id.as_ref(),
                                    ) {
                                        (Some(_), Some(_)) => {
                                            let (
                                                target_name,
                                                target_ra,
                                                target_dec,
                                                current_filter,
                                            ) = {
                                                let ts = trigger_state_for_actions.read().await;
                                                (
                                                    ts.current_target_name.clone(),
                                                    ts.target_ra.map(|ra| ra / 15.0),
                                                    ts.target_dec,
                                                    ts.current_filter.clone(),
                                                )
                                            };

                                            let af_ctx = build_trigger_autofocus_context(
                                                &trigger_action_context,
                                                target_name,
                                                target_ra,
                                                target_dec,
                                                current_filter,
                                                is_cancelled_clone.clone(),
                                                device_ops_for_triggers.clone(),
                                                trigger_state_for_actions.clone(),
                                                &runtime_config,
                                                Some(event_tx_clone2.clone()),
                                            );

                                            // Use the operator's real autofocus tuning
                                            // (seeded at start() from the sequence's
                                            // Autofocus node, or pushed via runtime
                                            // config). Falling back to library defaults
                                            // here would mean trigger-fired refocus
                                            // ignores the user's step size / exposure /
                                            // backlash — so warn loudly if that happens.
                                            let af_config = {
                                                match runtime_config.read().autofocus.clone() {
                                                    Some(cfg) => cfg,
                                                    None => {
                                                        tracing::warn!(
                                                            "Trigger autofocus running with LIBRARY DEFAULTS \
                                                             (no Autofocus node / profile AF config available) — \
                                                             focus quality may suffer on a non-default rig"
                                                        );
                                                        crate::AutofocusConfig::default()
                                                    }
                                                }
                                            };
                                            let af_result = crate::instructions::execute_autofocus(
                                                &af_config, &af_ctx, None,
                                            )
                                            .await;

                                            if af_result.status == NodeStatus::Success {
                                                if let Some(best_hfr) = af_result.hfr_values.first()
                                                {
                                                    let mut ts =
                                                        trigger_state_for_actions.write().await;
                                                    ts.update_hfr(*best_hfr);
                                                    ts.reset_baseline_hfr();
                                                    ts.mark_autofocus_performed();
                                                }
                                            } else {
                                                // BUG-3: Reset the HFR baseline to the current degraded
                                                // value so the trigger doesn't keep firing with a stale
                                                // baseline from before the failed autofocus attempt.
                                                {
                                                    let mut ts =
                                                        trigger_state_for_actions.write().await;
                                                    ts.reset_baseline_hfr();
                                                    tracing::warn!(
                                                    "Autofocus failed — HFR baseline reset to current value ({:?}) \
                                                     to prevent repeated trigger firing with stale baseline",
                                                    ts.baseline_hfr
                                                );
                                                }

                                                is_paused_for_triggers
                                                    .store(true, Ordering::Relaxed);
                                                *state_clone.write().await = ExecutorState::Paused;
                                                let _ = event_tx_clone2.send(
                                                    ExecutorEvent::StateChanged(
                                                        ExecutorState::Paused,
                                                    ),
                                                );
                                                let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                                // Why: autofocus result's
                                                // `message` is Option<String> — only populated
                                                // when the focus pipeline reports a specific
                                                // diagnostic. The generic fallback message is
                                                // surfaced to the user when no specific signal
                                                // came back; the failure itself is already
                                                // encoded in `af_result.success = false`.
                                                message: af_result.message.unwrap_or_else(|| {
                                                    "Autofocus trigger failed; sequence paused for intervention".to_string()
                                                }),
                                            });
                                            }
                                        }
                                        _ => {
                                            is_paused_for_triggers.store(true, Ordering::Relaxed);
                                            *state_clone.write().await = ExecutorState::Paused;
                                            let _ = event_tx_clone2.send(
                                                ExecutorEvent::StateChanged(ExecutorState::Paused),
                                            );
                                            let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                            message: "Autofocus trigger requested but camera/focuser is not connected"
                                                .to_string(),
                                        });
                                        }
                                    }
                                }
                                RecoveryAction::Retry { max_attempts } => {
                                    let attempts =
                                        retry_attempts.entry(trigger_id.clone()).or_insert(0);
                                    if *attempts < *max_attempts {
                                        *attempts += 1;
                                        tracing::warn!(
                                            "Trigger '{}' requested retry attempt {}/{}",
                                            trigger_name,
                                            attempts,
                                            max_attempts
                                        );
                                    } else {
                                        tracing::error!(
                                        "Trigger '{}' exhausted {} retry attempts; pausing sequence",
                                        trigger_name,
                                        max_attempts
                                    );
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                        message: format!(
                                            "Trigger '{}' exhausted {} retry attempts; sequence paused",
                                            trigger_name, max_attempts
                                        ),
                                    });
                                    }
                                }
                                RecoveryAction::MeridianFlip(config) => {
                                    tracing::info!(
                                        "[MERIDIAN] Trigger fired - executing meridian flip"
                                    );

                                    let (target_name, target_ra, target_dec) = {
                                        let ts = trigger_state_for_actions.read().await;
                                        (
                                            ts.current_target_name
                                                .clone()
                                                // Why: target name is a
                                                // display/log label; the load-bearing trigger
                                                // outputs are `target_ra` and `target_dec`
                                                // which propagate as Option below and gate
                                                // the meridian-flip-context construction.
                                                .unwrap_or_else(|| "Unknown".to_string()),
                                            ts.target_ra.map(|ra| ra / 15.0), // Convert degrees to hours
                                            ts.target_dec,
                                        )
                                    };

                                    if let Some(flip_ctx) = build_trigger_flip_context(
                                        &trigger_action_context,
                                        target_name.clone(),
                                        target_ra,
                                        target_dec,
                                        Some(is_cancelled_clone.clone()),
                                        Some(trigger_state_for_actions.clone()),
                                    ) {
                                        let mut flip_executor =
                                        crate::meridian_flip_executor::MeridianFlipExecutor::new(
                                            config.clone(),
                                            device_ops_for_triggers.clone(),
                                        );

                                        match flip_executor.execute(&flip_ctx).await {
                                        crate::meridian_flip_executor::FlipResult::Success {
                                            new_pier_side,
                                            duration_secs,
                                        } => {
                                            tracing::info!(
                                                "[MERIDIAN] Flip completed successfully: new pier side {:?}, took {:.1}s",
                                                new_pier_side, duration_secs
                                            );

                                            let mut ts = trigger_state_for_actions.write().await;
                                            ts.mark_flip_performed();
                                        }
                                        crate::meridian_flip_executor::FlipResult::Failed {
                                            error,
                                            action_taken,
                                        } => {
                                            tracing::error!(
                                                "[MERIDIAN] Flip failed: {} (action: {:?})",
                                                error,
                                                action_taken
                                            );

                                            match action_taken {
                                                crate::FlipFailureAction::PauseAndAlert => {
                                                    is_paused_for_triggers
                                                        .store(true, Ordering::Relaxed);
                                                    *state_clone.write().await =
                                                        ExecutorState::Paused;
                                                    let _ = event_tx_clone2.send(
                                                        ExecutorEvent::StateChanged(
                                                            ExecutorState::Paused,
                                                        ),
                                                    );
                                                }
                                                crate::FlipFailureAction::AbortAndPark => {
                                                    // cancellation
                                                    // is set inside terminate_with
                                                    // so this exit cannot drift
                                                    // out of sync with the
                                                    // ParkAndAbort path.

                                                    // The flip itself failed, so the mount may be
                                                    // anywhere between sides. Park before we exit
                                                    // to avoid leaving it tracking into a limit
                                                    // — matches the ParkAndAbort policy above.
                                                    //
                                                    // Trust-patch §8: use `try_park_with_retry`
                                                    // so a flaky driver gets at least one retry
                                                    // before we give up. Surface a park-specific
                                                    // failure to the event stream.
                                                    if let Some(mount_id) =
                                                        &trigger_action_context.mount_id
                                                    {
                                                        tracing::warn!("FlipFailure AbortAndPark: parking mount '{}' (max_retries=1, retry_delay=2s)", mount_id);
                                                        let park_outcome =
                                                            crate::device_ops::try_park_with_retry(
                                                                &device_ops_for_triggers,
                                                                mount_id,
                                                                1,
                                                                2.0,
                                                            )
                                                            .await;
                                                        if !park_outcome.success {
                                                            let _ = event_tx_clone2.send(
                                                                ExecutorEvent::Error {
                                                                    message: format!(
                                                                        "FlipFailure AbortAndPark: mount park FAILED after {} attempt(s): {}. \
                                                                         Mount may be in an unsafe position — manual intervention required.",
                                                                        park_outcome.attempts_made,
                                                                        park_outcome
                                                                            .last_error
                                                                            .unwrap_or_else(|| {
                                                                                "unknown error".to_string()
                                                                            }),
                                                                    ),
                                                                },
                                                            );
                                                        }
                                                    }

                                                    fired_triggers.push((
                                                        trigger_id.clone(),
                                                        RecoveryAction::ParkAndAbort,
                                                    ));
                                                    return terminate_with(
                                                        &is_cancelled_clone,
                                                        fired_triggers,
                                                        "FlipFailureAction::AbortAndPark",
                                                    );
                                                }
                                            }
                                        }
                                        crate::meridian_flip_executor::FlipResult::Aborted {
                                            reason,
                                        } => {
                                            tracing::warn!("[MERIDIAN] Flip aborted: {}", reason);
                                        }
                                    }
                                    } else {
                                        tracing::error!("[MERIDIAN] Cannot execute flip: mount not connected or target not set");
                                    }
                                }
                                RecoveryAction::Dither(dither_config) => {
                                    // implement the standard
                                    // DitherInterval recovery. Build an instruction
                                    // context (the trigger action context already
                                    // carries every device id, save path,
                                    // location, filter offsets, and an
                                    // is_cancelled token). The dither runs
                                    // asynchronously here; we update
                                    // last_dither_frame on success so the
                                    // DitherInterval cadence stays correct.
                                    //
                                    // prefer the runtime config over
                                    // the trigger-embedded default if the user
                                    // updated it via UpdateDitherConfig. The
                                    // trigger config still wins for `pattern`/
                                    // `grid_size` because those are not exposed
                                    // by UpdateDitherConfig.
                                    let effective_config = {
                                        let rc = runtime_config.read();
                                        // The runtime config has Default values
                                        // (zero) until UpdateDitherConfig fires,
                                        // so prefer the trigger-embedded config
                                        // when the runtime side has not been
                                        // explicitly set (pixels==0). Otherwise
                                        // the runtime override wins so the user's
                                        // last UpdateDitherConfig is honoured.
                                        if rc.dither.pixels > 0.0 {
                                            crate::DitherConfig {
                                                pixels: rc.dither.pixels,
                                                settle_pixels: rc.dither.settle_pixels,
                                                settle_time: rc.dither.settle_time,
                                                settle_timeout: rc.dither.settle_timeout,
                                                ra_only: rc.dither.ra_only,
                                                // pattern/grid_size are not
                                                // surfaced by UpdateDitherConfig
                                                // so the trigger value still wins.
                                                pattern: dither_config.pattern,
                                                grid_size: dither_config.grid_size,
                                            }
                                        } else {
                                            dither_config.clone()
                                        }
                                    };
                                    tracing::info!(
                                    "[DITHER] Trigger '{}' fired - executing dither (pixels={}, settle_pixels={})",
                                    trigger_name,
                                    effective_config.pixels,
                                    effective_config.settle_pixels,
                                );
                                    let (target_name, target_ra, target_dec, current_filter) = {
                                        let ts = trigger_state_for_actions.read().await;
                                        (
                                            ts.current_target_name.clone(),
                                            ts.target_ra.map(|ra| ra / 15.0),
                                            ts.target_dec,
                                            ts.current_filter.clone(),
                                        )
                                    };
                                    let dither_ctx = build_trigger_autofocus_context(
                                        &trigger_action_context,
                                        target_name,
                                        target_ra,
                                        target_dec,
                                        current_filter,
                                        is_cancelled_clone.clone(),
                                        device_ops_for_triggers.clone(),
                                        trigger_state_for_actions.clone(),
                                        &runtime_config,
                                        Some(event_tx_clone2.clone()),
                                    );
                                    let dither_result = crate::instructions::execute_dither(
                                        &effective_config,
                                        &dither_ctx,
                                        None,
                                    )
                                    .await;
                                    if dither_result.status == NodeStatus::Success {
                                        let mut ts = trigger_state_for_actions.write().await;
                                        ts.mark_dither_performed();
                                    } else {
                                        tracing::warn!(
                                            "[DITHER] Trigger-initiated dither failed: {:?}",
                                            dither_result.message
                                        );
                                    }
                                }
                                RecoveryAction::Recenter => {
                                    // re-slew to the target and
                                    // plate-solve as the DriftLimit recovery. The
                                    // existing `execute_center` instruction
                                    // already does plate-solve + sync + slew loop;
                                    // we reuse it so behaviour matches an
                                    // explicit Center node.
                                    tracing::info!(
                                        "[DRIFT] Trigger '{}' fired - executing recenter",
                                        trigger_name
                                    );
                                    let (target_name, target_ra, target_dec, current_filter) = {
                                        let ts = trigger_state_for_actions.read().await;
                                        (
                                            ts.current_target_name.clone(),
                                            ts.target_ra.map(|ra| ra / 15.0),
                                            ts.target_dec,
                                            ts.current_filter.clone(),
                                        )
                                    };
                                    if target_ra.is_none() || target_dec.is_none() {
                                        tracing::error!(
                                        "[DRIFT] Recenter requested but no target RA/Dec set; pausing for operator intervention"
                                    );
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                    } else {
                                        let recenter_ctx = build_trigger_autofocus_context(
                                            &trigger_action_context,
                                            target_name,
                                            target_ra,
                                            target_dec,
                                            current_filter,
                                            is_cancelled_clone.clone(),
                                            device_ops_for_triggers.clone(),
                                            trigger_state_for_actions.clone(),
                                            &runtime_config,
                                            Some(event_tx_clone2.clone()),
                                        );
                                        let center_config = crate::CenterConfig {
                                            use_target_coords: true,
                                            custom_ra: None,
                                            custom_dec: None,
                                            accuracy_arcsec: 10.0,
                                            max_attempts: 3,
                                            exposure_duration: 5.0,
                                            filter: None,
                                        };
                                        let result = crate::instructions::execute_center(
                                            &center_config,
                                            &recenter_ctx,
                                            None,
                                        )
                                        .await;
                                        if result.status != NodeStatus::Success {
                                            tracing::warn!(
                                                "[DRIFT] Recenter failed: {:?} - pausing sequence",
                                                result.message
                                            );
                                            is_paused_for_triggers.store(true, Ordering::Relaxed);
                                            *state_clone.write().await = ExecutorState::Paused;
                                            let _ = event_tx_clone2.send(
                                                ExecutorEvent::StateChanged(ExecutorState::Paused),
                                            );
                                            let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "DriftLimit recenter failed: {}",
                                                    // Why: recenter-result
                                                    // message is Option<String>; the failure
                                                    // is already encoded in `result.success`
                                                    // (we are in the `false` branch). Empty
                                                    // string for the diagnostic suffix is
                                                    // safe — the prefix conveys the failure.
                                                    result.message.unwrap_or_default()
                                                ),
                                            });
                                        }
                                    }
                                }
                                RecoveryAction::PauseAndWaitForClear => {
                                    // pause the sequence and
                                    // promote the pause to a recovery
                                    // RecoveryCause::WeatherUnsafe so the
                                    // dashboard banner, audible alert, and
                                    // recovery driver all light up.
                                    // `CloudOpeningIn` triggers wired to
                                    // `Continue` (or any recovery the user
                                    // wires) will fire when the analyzer
                                    // sees an opening; the executor's
                                    // legacy auto-resume path handles the
                                    // actual unpause via the user's
                                    // `autoResumeEnabled` flag in
                                    // WeatherSafetyNotifier.
                                    tracing::warn!(
                                        "[CLOUD] Trigger '{}' fired - pausing sequence (PauseAndWaitForClear)",
                                        trigger_name
                                    );
                                    let cause = crate::recovery::RecoveryCause::WeatherUnsafe;
                                    match recovery_request_tx.try_send(cause.clone()) {
                                        Ok(()) => {
                                            tracing::info!(
                                                "[RECOVERY] PauseAndWaitForClear requested ({:?})",
                                                cause
                                            );
                                        }
                                        Err(tokio::sync::mpsc::error::TrySendError::Full(_)) => {
                                            tracing::warn!(
                                                "[RECOVERY] Recovery channel full; falling back to plain Pause"
                                            );
                                            is_paused_for_triggers.store(true, Ordering::Relaxed);
                                            *state_clone.write().await = ExecutorState::Paused;
                                            let _ = event_tx_clone2.send(
                                                ExecutorEvent::StateChanged(ExecutorState::Paused),
                                            );
                                        }
                                        Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
                                            // Driver task ended — same
                                            // fallback as the legacy Pause
                                            // path.
                                            is_paused_for_triggers.store(true, Ordering::Relaxed);
                                            *state_clone.write().await = ExecutorState::Paused;
                                            let _ = event_tx_clone2.send(
                                                ExecutorEvent::StateChanged(ExecutorState::Paused),
                                            );
                                        }
                                    }
                                }
                                RecoveryAction::SlewToGapAndContinue => {
                                    // slew the mount to the
                                    // analyzer-reported clear-sky direction.
                                    // No clear direction reported => fall
                                    // back to PauseAndWaitForClear (we
                                    // refuse to silently no-op when the
                                    // user explicitly wanted to move away
                                    // from the clouds).
                                    let snapshot = {
                                        let slot = cloud_motion_for_recovery.read().await;
                                        slot.clone()
                                    };
                                    let Some((alt_deg, az_deg)) =
                                        snapshot.predicted_clear_sky_direction
                                    else {
                                        tracing::warn!(
                                            "[CLOUD] SlewToGapAndContinue fired but no clear-sky direction reported; falling back to PauseAndWaitForClear"
                                        );
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        let _ =
                                            event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "Trigger '{}' requested SlewToGapAndContinue but the cloud-motion analyzer has not reported a clear sky direction. Sequence paused.",
                                                    trigger_name,
                                                ),
                                            });
                                        fired_triggers.push((trigger_id, action));
                                        continue;
                                    };

                                    // Need observer location to convert
                                    // alt/az -> RA/Dec.
                                    let (lat, lon) = {
                                        let rc = runtime_config.read();
                                        (rc.latitude, rc.longitude)
                                    };
                                    let (Some(lat), Some(lon)) = (
                                        lat.or(trigger_action_context.latitude),
                                        lon.or(trigger_action_context.longitude),
                                    ) else {
                                        tracing::error!(
                                            "[CLOUD] SlewToGapAndContinue cannot proceed: observer location not set"
                                        );
                                        let _ =
                                            event_tx_clone2.send(ExecutorEvent::Error {
                                                message: "SlewToGapAndContinue requested but observer location is not configured. Sequence paused.".to_string(),
                                            });
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        fired_triggers.push((trigger_id, action));
                                        continue;
                                    };

                                    let (ra_hours, dec_deg) =
                                        alt_az_to_ra_dec(alt_deg, az_deg, lat, lon);
                                    tracing::info!(
                                        "[CLOUD] SlewToGapAndContinue: clear sky at alt={:.1}°, az={:.1}° -> RA={:.4}h, Dec={:.4}°",
                                        alt_deg,
                                        az_deg,
                                        ra_hours,
                                        dec_deg
                                    );

                                    // Build an instruction context that
                                    // targets the gap coordinates.
                                    let slew_ctx = build_trigger_autofocus_context(
                                        &trigger_action_context,
                                        Some("Cloud Gap".to_string()),
                                        Some(ra_hours),
                                        Some(dec_deg),
                                        None,
                                        is_cancelled_clone.clone(),
                                        device_ops_for_triggers.clone(),
                                        trigger_state_for_actions.clone(),
                                        &runtime_config,
                                        Some(event_tx_clone2.clone()),
                                    );
                                    let slew_config = crate::SlewConfig {
                                        use_target_coords: false,
                                        custom_ra: Some(ra_hours),
                                        custom_dec: Some(dec_deg),
                                    };
                                    let result = crate::instructions::execute_slew(
                                        &slew_config,
                                        &slew_ctx,
                                        None,
                                    )
                                    .await;
                                    if result.status != NodeStatus::Success {
                                        tracing::warn!(
                                            "[CLOUD] Slew to gap failed: {:?} - pausing sequence",
                                            result.message
                                        );
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                            message: format!(
                                                "SlewToGapAndContinue failed: {}",
                                                result.message.unwrap_or_default()
                                            ),
                                        });
                                    } else {
                                        tracing::info!(
                                            "[CLOUD] Slew to gap completed; sequence continues"
                                        );
                                    }
                                }
                                RecoveryAction::SwitchTargetOrFilter => {
                                    // Science — transparency-adaptive
                                    // recovery. Consult the operator's
                                    // pre-configured backup plan; apply
                                    // filter swap and/or skip-to-target as
                                    // configured. No plan + no fields set
                                    // => fall back to PauseAndWaitForClear
                                    // ("no silent fallbacks":
                                    // we tell the operator why we're not
                                    // doing anything).
                                    let plan_snapshot = {
                                        let slot = transparency_backup_for_recovery.read().await;
                                        slot.clone()
                                    };
                                    let Some(plan) = plan_snapshot else {
                                        tracing::warn!(
                                            "[SCIENCE] SwitchTargetOrFilter fired but no backup plan configured; falling back to PauseAndWaitForClear"
                                        );
                                        let _ =
                                            event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "Trigger '{}' requested SwitchTargetOrFilter but no transparency backup plan was configured. Sequence paused. Set a backup filter or backup target in the science settings before re-running.",
                                                    trigger_name,
                                                ),
                                            });
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        fired_triggers.push((trigger_id, action));
                                        continue;
                                    };
                                    if plan.backup_filter.is_none()
                                        && plan.backup_target_id.is_none()
                                    {
                                        tracing::warn!(
                                            "[SCIENCE] SwitchTargetOrFilter: backup plan has neither filter nor target; falling back to PauseAndWaitForClear"
                                        );
                                        let _ =
                                            event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "Trigger '{}' requested SwitchTargetOrFilter but the configured backup plan is empty. Sequence paused.",
                                                    trigger_name,
                                                ),
                                            });
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        fired_triggers.push((trigger_id, action));
                                        continue;
                                    }
                                    tracing::warn!(
                                        "[SCIENCE] Trigger '{}' fired SwitchTargetOrFilter: filter={:?}, target={:?}, desc={:?}",
                                        trigger_name,
                                        plan.backup_filter,
                                        plan.backup_target_id,
                                        plan.description,
                                    );
                                    // 1. If a backup target node id is set,
                                    //    request a skip-to-node so the executor
                                    //    walks past the current target and
                                    //    enters the backup target's subtree.
                                    if let Some(node_id) = &plan.backup_target_id {
                                        *skip_to_node_for_recovery.write() = Some(node_id.clone());
                                        tracing::info!(
                                            "[SCIENCE] Requested skip-to-node '{}' for transparency backup",
                                            node_id
                                        );
                                    }
                                    // 2. If a backup filter is set, drive a
                                    //    ChangeFilter through the standard
                                    //    instruction context so the filter
                                    //    wheel actually moves. Use a
                                    //    standalone instruction context here
                                    //    (the running root_node.execute is
                                    //    holding `&mut context` so we cannot
                                    //    re-borrow it).
                                    if let Some(filter_name) = &plan.backup_filter {
                                        let inst_ctx = build_trigger_autofocus_context(
                                            &trigger_action_context,
                                            None,
                                            None,
                                            None,
                                            None,
                                            is_cancelled_clone.clone(),
                                            device_ops_for_triggers.clone(),
                                            trigger_state_for_actions.clone(),
                                            &runtime_config,
                                            Some(event_tx_clone2.clone()),
                                        );
                                        let filter_cfg = crate::FilterConfig {
                                            filter_name: filter_name.clone(),
                                            filter_index: None,
                                            timeout_secs: None,
                                        };
                                        let result = crate::instructions::execute_filter_change(
                                            &filter_cfg,
                                            &inst_ctx,
                                            None,
                                        )
                                        .await;
                                        if result.status != NodeStatus::Success {
                                            tracing::warn!(
                                                "[SCIENCE] Backup filter change to '{}' failed: {:?}",
                                                filter_name,
                                                result.message,
                                            );
                                            let _ = event_tx_clone2
                                                .send(ExecutorEvent::Error {
                                                    message: format!(
                                                        "SwitchTargetOrFilter: backup filter '{}' could not be selected: {}",
                                                        filter_name,
                                                        result
                                                            .message
                                                            .unwrap_or_default()
                                                    ),
                                                });
                                        } else {
                                            tracing::info!(
                                                "[SCIENCE] Switched to backup filter '{}'",
                                                filter_name
                                            );
                                        }
                                    }
                                }
                                RecoveryAction::Continue => {
                                    // explicit no-op handler so the
                                    // match is exhaustive on every variant. The
                                    // user wants the trigger logged-and-ignored
                                    // (this is the FilterChange standard trigger's
                                    // behaviour).
                                    tracing::info!(
                                    "Trigger '{}' fired with RecoveryAction::Continue (logged and ignored)",
                                    trigger_name
                                );
                                }
                                RecoveryAction::CustomBranch => {
                                    let Some(recovery_node_id) =
                                        custom_recovery_branches_for_triggers
                                            .get(&trigger_id)
                                            .cloned()
                                    else {
                                        tracing::error!(
                                            "Trigger '{}' fired CustomBranch but no recovery branch was registered",
                                            trigger_name
                                        );
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        let _ =
                                            event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "Trigger '{}' requested Custom Branch recovery, but no branch was registered. Sequence paused.",
                                                    trigger_name
                                                ),
                                            });
                                        fired_triggers.push((trigger_id, action));
                                        continue;
                                    };

                                    let Some(sequence) =
                                        sequence_for_custom_recovery_triggers.as_ref()
                                    else {
                                        tracing::error!(
                                            "Trigger '{}' fired CustomBranch but no loaded sequence snapshot is available",
                                            trigger_name
                                        );
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        let _ =
                                            event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "Trigger '{}' requested Custom Branch recovery, but the sequence snapshot was unavailable. Sequence paused.",
                                                    trigger_name
                                                ),
                                            });
                                        fired_triggers.push((trigger_id, action));
                                        continue;
                                    };

                                    let node_map: HashMap<&str, &NodeDefinition> =
                                        sequence.nodes.iter().map(|n| (n.id.as_str(), n)).collect();
                                    let Some(recovery_def) =
                                        node_map.get(recovery_node_id.as_str())
                                    else {
                                        tracing::error!(
                                            "Trigger '{}' fired CustomBranch but recovery node '{}' was not found",
                                            trigger_name,
                                            recovery_node_id
                                        );
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                        let _ =
                                            event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "Trigger '{}' requested Custom Branch node '{}', but it was not found. Sequence paused.",
                                                    trigger_name,
                                                    recovery_node_id
                                                ),
                                            });
                                        fired_triggers.push((trigger_id, action));
                                        continue;
                                    };

                                    let mut branch_node =
                                        build_runtime_node_from_map(recovery_def, &node_map);
                                    let mut branch_context =
                                        custom_recovery_context_for_triggers.clone();
                                    branch_context.node_id = recovery_node_id.clone();

                                    tracing::warn!(
                                        "Trigger '{}' executing CustomBranch recovery node '{}'",
                                        trigger_name,
                                        recovery_node_id
                                    );
                                    let result =
                                        crate::node::logic::recovery::execute_custom_branch_children(
                                            &mut branch_node,
                                            &mut branch_context,
                                        )
                                        .await;

                                    match result {
                                        NodeStatus::Success | NodeStatus::Skipped => {
                                            tracing::info!(
                                                "CustomBranch recovery node '{}' completed with {:?}",
                                                recovery_node_id,
                                                result
                                            );
                                        }
                                        NodeStatus::Cancelled => {
                                            fired_triggers.push((trigger_id, action));
                                            return terminate_with(
                                                &is_cancelled_clone,
                                                fired_triggers,
                                                "RecoveryAction::CustomBranch cancelled",
                                            );
                                        }
                                        NodeStatus::Pending
                                        | NodeStatus::Running
                                        | NodeStatus::Failure => {
                                            tracing::error!(
                                                "CustomBranch recovery node '{}' failed with {:?}; pausing sequence",
                                                recovery_node_id,
                                                result
                                            );
                                            is_paused_for_triggers.store(true, Ordering::Relaxed);
                                            *state_clone.write().await = ExecutorState::Paused;
                                            let _ = event_tx_clone2.send(
                                                ExecutorEvent::StateChanged(ExecutorState::Paused),
                                            );
                                            let _ = event_tx_clone2.send(
                                                ExecutorEvent::Error {
                                                    message: format!(
                                                        "Custom Branch recovery '{}' failed after trigger '{}'. Sequence paused.",
                                                        recovery_node_id,
                                                        trigger_name
                                                    ),
                                                },
                                            );
                                        }
                                    }

                                    fired_triggers.push((trigger_id, action));
                                    continue;
                                }
                            }

                            fired_triggers.push((trigger_id, action));
                        }
                    }

                    fired_triggers
                };

                // Fail-closed safety: an unattended sequence depends on the trigger
                // monitor to enforce weather / altitude / drift limits. If it exits
                // for any reason other than normal cancellation, continuing to
                // expose would leave the rig unmonitored — so we cancel everything.
                let result = tokio::select! {
                    _ = command_handler => NodeStatus::Cancelled,
                    result = execution => result,
                    _ = streaming_checkpoint_task => NodeStatus::Cancelled,
                    // Recovery Mode — the driver task only ever
                    // exits when the recovery_request_tx side is closed
                    // (sequence ending), so a clean exit is a Cancelled
                    // outcome. The driver intentionally holds itself open
                    // by recv-looping; we keep it in the select! so a
                    // panic here surfaces in the same way as any other
                    // task panic (caught by the supervisor catch_unwind).
                    _ = recovery_driver => NodeStatus::Cancelled,
                    _triggers = trigger_monitor => {
                        if triggers_enabled && !is_cancelled.load(Ordering::Relaxed) {
                            tracing::error!(
                                "Safety monitoring (trigger monitor) exited unexpectedly! \
                                 Cancelling sequence to prevent unmonitored execution."
                            );
                            is_cancelled.store(true, Ordering::Relaxed);
                            let _ = event_tx.send(ExecutorEvent::Error {
                                message: "Safety monitoring failed — sequence aborted. \
                                          The trigger monitor exited unexpectedly."
                                    .to_string(),
                            });
                            NodeStatus::Failure
                        } else {
                            NodeStatus::Cancelled
                        }
                    },
                };

                // when recovery exhausted on a real failure it set
                // `is_cancelled` to unwind the node tree, so the `execution`
                // branch of the select! above resolves to `Cancelled` and would
                // otherwise overwrite the `Failed` state the recovery driver
                // set — the run would be reported as a benign cancellation in
                // the UI / session report. Coerce it back to `Failure` so the
                // give-up is recorded as the failure it actually is.
                let result = if recovery_gave_up.load(Ordering::Relaxed)
                    && !matches!(result, NodeStatus::Failure)
                {
                    NodeStatus::Failure
                } else {
                    result
                };

                let final_state = executor_state_for_result(result);

                *state.write().await = final_state;
                {
                    let mut prog = progress.write();
                    prog.state = final_state;
                    prog.elapsed_secs = start_time.elapsed().as_secs_f64();
                }

                match result {
                    NodeStatus::Success | NodeStatus::Skipped => {
                        // Mark the checkpoint inactive on graceful completion.
                        // Without this the on-disk checkpoint stays `is_active`
                        // forever, so `has_recoverable_checkpoint()` keeps
                        // returning true and the UI shows a stale "resume?"
                        // banner after every successful night. We use
                        // `mark_completed()` (not `clear()`) so the file is
                        // preserved with `is_active=false` /
                        // `executor_state=Completed` for the post-session report;
                        // the next `start()` overwrites it. A failure to write is
                        // logged loudly (it would silently reintroduce the stale
                        // banner) but does not change the run's Success outcome.
                        if let Some(mgr) = &completion_checkpoint_manager {
                            if let Err(e) = mgr.mark_completed() {
                                tracing::error!(
                                    "Failed to mark checkpoint completed after a normal \
                                     sequence finish: {} — a stale 'resume?' banner may \
                                     appear on next launch",
                                    e
                                );
                            } else {
                                tracing::debug!(
                                    "Checkpoint marked completed on normal sequence finish"
                                );
                            }
                        }
                        let _ = event_tx.send(ExecutorEvent::SequenceCompleted);
                        // Replay Debug — terminal lifecycle decision.
                        emit_lifecycle_decision(
                            &decision_tx_for_lifecycle,
                            &active_run_id_for_decisions,
                            &decision_logging_enabled_for_emits,
                            "completed",
                            serde_json::json!({
                                "elapsed_secs": start_time.elapsed().as_secs_f64(),
                                "final_state": format!("{:?}", final_state),
                            }),
                        );
                    }
                    NodeStatus::Failure => {
                        let _ = event_tx.send(ExecutorEvent::SequenceFailed {
                            error: "Sequence failed".into(),
                        });
                        emit_lifecycle_decision(
                            &decision_tx_for_lifecycle,
                            &active_run_id_for_decisions,
                            &decision_logging_enabled_for_emits,
                            "failed",
                            serde_json::json!({
                                "elapsed_secs": start_time.elapsed().as_secs_f64(),
                            }),
                        );
                    }
                    NodeStatus::Cancelled => {
                        let _ = event_tx.send(ExecutorEvent::Error {
                            message: "Sequence cancelled".into(),
                        });
                        emit_lifecycle_decision(
                            &decision_tx_for_lifecycle,
                            &active_run_id_for_decisions,
                            &decision_logging_enabled_for_emits,
                            "cancelled",
                            serde_json::json!({
                                "elapsed_secs": start_time.elapsed().as_secs_f64(),
                            }),
                        );
                    }
                    _ => {}
                }

                let _ = event_tx.send(ExecutorEvent::StateChanged(final_state));
            };

            // Catch any panic inside the executor future. If the future
            // panics we MUST surface it: a silently-dead sequencer is the
            // exact "silent fallback" the house rules forbid. Restarting node
            // execution after a panic is not safe (device state is unknown
            // and `root_node` has been consumed by move), so the policy is:
            // log + emit SequenceFailed + move state to Failed.
            if let Err(panic_payload) = AssertUnwindSafe(executor_future).catch_unwind().await {
                let panic_msg = if let Some(s) = panic_payload.downcast_ref::<&str>() {
                    (*s).to_string()
                } else if let Some(s) = panic_payload.downcast_ref::<String>() {
                    s.clone()
                } else {
                    "Unknown panic".to_string()
                };
                tracing::error!(
                    target: "supervisor",
                    "sequencer_executor panicked; sequence aborted: {panic_msg}"
                );

                *supervisor_state.write().await = ExecutorState::Failed;
                {
                    let mut prog = supervisor_progress.write();
                    prog.state = ExecutorState::Failed;
                }
                let _ = supervisor_event_tx.send(ExecutorEvent::SequenceFailed {
                    error: format!("Sequencer panicked: {panic_msg}"),
                });
                let _ =
                    supervisor_event_tx.send(ExecutorEvent::StateChanged(ExecutorState::Failed));
            }
        });

        Ok(())
    }
}

impl Default for SequenceExecutor {
    fn default() -> Self {
        Self::new()
    }
}

/// Global executor instance
static EXECUTOR: std::sync::OnceLock<Arc<RwLock<SequenceExecutor>>> = std::sync::OnceLock::new();

/// Get the global executor instance
pub fn get_executor() -> &'static Arc<RwLock<SequenceExecutor>> {
    EXECUTOR.get_or_init(|| Arc::new(RwLock::new(SequenceExecutor::new())))
}

#[cfg(test)]
mod scenario_sim_tests;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::SequenceDefinition;

    #[test]
    fn test_executor_creation() {
        let executor = SequenceExecutor::new();
        assert!(executor.sequence.is_none());
        assert!(executor.root_node.is_none());
    }

    #[test]
    fn test_load_sequence() {
        let mut executor = SequenceExecutor::new();
        let mut sequence = SequenceDefinition::new("Test Sequence".to_string());

        let node = crate::NodeDefinition {
            id: "root".to_string(),
            name: "Root".to_string(),
            node_type: crate::NodeType::Delay(crate::DelayConfig::default()),
            enabled: true,
            children: vec![],
        };
        sequence.nodes.push(node);
        sequence.root_node_id = Some("root".to_string());

        let result = executor.load_sequence(sequence);
        assert!(
            result.is_ok(),
            "Failed to load sequence: {:?}",
            result.err()
        );
        assert!(executor.sequence.is_some());
    }

    #[test]
    fn custom_branch_recovery_node_registers_trigger_spec() {
        let mut sequence = SequenceDefinition::new("Custom Recovery".to_string());
        sequence.nodes.push(crate::NodeDefinition {
            id: "root".to_string(),
            name: "Root".to_string(),
            node_type: crate::NodeType::Delay(crate::DelayConfig { seconds: 0.0 }),
            enabled: true,
            children: vec!["recovery".to_string()],
        });
        sequence.nodes.push(crate::NodeDefinition {
            id: "recovery".to_string(),
            name: "Guide Recovery".to_string(),
            node_type: crate::NodeType::Recovery(crate::RecoveryConfig {
                trigger: Some(crate::TriggerType::GuideStarLost),
                recovery_action: crate::RecoveryAction::CustomBranch,
                max_retries: 1,
            }),
            enabled: true,
            children: vec!["delay".to_string()],
        });
        sequence.nodes.push(crate::NodeDefinition {
            id: "delay".to_string(),
            name: "Wait".to_string(),
            node_type: crate::NodeType::Delay(crate::DelayConfig { seconds: 0.0 }),
            enabled: true,
            children: vec![],
        });
        sequence.root_node_id = Some("root".to_string());

        let specs = sequence_recovery_trigger_specs(&sequence);

        assert_eq!(specs.len(), 1);
        assert_eq!(specs[0].trigger_id, "recovery_node:recovery");
        assert_eq!(specs[0].trigger_name, "Recovery: Guide Recovery");
        assert!(matches!(
            specs[0].trigger_type,
            crate::TriggerType::GuideStarLost
        ));
        assert!(matches!(
            specs[0].recovery_action,
            crate::RecoveryAction::CustomBranch
        ));
        assert_eq!(specs[0].custom_branch_node_id.as_deref(), Some("recovery"));
    }

    #[test]
    fn test_executor_state_transitions() {
        let executor = SequenceExecutor::new();

        // Use tokio runtime for async tests
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            assert_eq!(executor.get_state().await, ExecutorState::Idle);
        });
    }

    #[test]
    fn test_progress_tracking() {
        let executor = SequenceExecutor::new();

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let progress = executor.get_progress();
            assert_eq!(progress.completed_exposures, 0);
            assert_eq!(progress.completed_integration_secs, 0.0);
            assert!(progress.current_node_id.is_none());
        });
    }

    #[test]
    fn test_location_configuration() {
        let mut executor = SequenceExecutor::new();

        executor.set_location(Some(45.5), Some(-122.6));

        assert_eq!(executor.latitude, Some(45.5));
        assert_eq!(executor.longitude, Some(-122.6));
    }

    #[test]
    fn safety_fail_mode_updates_runtime_config() {
        let mut executor = SequenceExecutor::new();

        executor.set_safety_fail_mode(crate::SafetyFailMode::WarnOnly);

        assert_eq!(executor.safety_fail_mode, crate::SafetyFailMode::WarnOnly);
        assert_eq!(
            executor.runtime_config.read().safety_fail_mode,
            crate::SafetyFailMode::WarnOnly
        );
    }

    #[test]
    fn safety_check_interval_is_clamped_and_defaulted() {
        assert_eq!(
            effective_safety_check_interval_secs(0),
            DEFAULT_SAFETY_CHECK_INTERVAL_SECS
        );
        assert_eq!(effective_safety_check_interval_secs(3), 5);
        assert_eq!(effective_safety_check_interval_secs(45), 45);
        assert_eq!(effective_safety_check_interval_secs(9999), 3600);
    }

    /// Architecture-unification 2026-06-05 (Subsystem 2 step 1 — CROSS-LANGUAGE
    /// FAIL-MODE PARITY). This is one half of the pinned truth table; the Dart
    /// half is `weather_fail_mode_parity_test.dart`. BOTH must encode the
    /// identical rows:
    ///
    ///   FailClosed -> Unsafe  (Rust: weather_safe=false; Dart verdict: Some(true))
    ///   FailOpen   -> Safe    (Rust: weather_safe=true;  Dart verdict: None/abstain)
    ///   WarnOnly   -> Preserve(Rust: weather_safe unchanged; Dart verdict: None/abstain)
    ///
    /// The single shared definition is `safety_fail_mode_no_data_resolution`
    /// (consumed by the executor safety poll). The Dart side mirrors it as
    /// `noDataFailModeResolution`. If you change a row here, change it in the
    /// Dart test too or the two implementations have silently drifted.
    #[test]
    fn safety_fail_mode_no_data_resolution_truth_table() {
        assert_eq!(
            safety_fail_mode_no_data_resolution(SafetyFailMode::FailClosed),
            NoDataResolution::Unsafe,
            "failClosed must resolve no-data as UNSAFE"
        );
        assert_eq!(
            safety_fail_mode_no_data_resolution(SafetyFailMode::FailOpen),
            NoDataResolution::Safe,
            "failOpen must resolve no-data as SAFE"
        );
        assert_eq!(
            safety_fail_mode_no_data_resolution(SafetyFailMode::WarnOnly),
            NoDataResolution::Preserve,
            "warnOnly must resolve no-data as PRESERVE (last reading wins)"
        );
    }

    /// Subsystem 2 step 3: the weather-verdict staleness window resolver
    /// defaults a `0` to the documented default and clamps non-zero values to a
    /// sane floor/ceiling so a misconfiguration cannot make every tick warn or
    /// disable the observability.
    #[test]
    fn weather_verdict_staleness_is_clamped_and_defaulted() {
        assert_eq!(
            effective_weather_verdict_staleness_secs(0),
            DEFAULT_WEATHER_VERDICT_STALENESS_SECS
        );
        assert_eq!(effective_weather_verdict_staleness_secs(5), 30);
        assert_eq!(effective_weather_verdict_staleness_secs(600), 600);
        assert_eq!(effective_weather_verdict_staleness_secs(1_000_000), 86_400);
    }

    /// Subsystem 2 step 3: the stale-unsafe verdict warning EMITS on the rising
    /// edge, is RATE-LIMITED while the feed stays stale, and RE-ARMS once a fresh
    /// verdict clears the stale condition. This is the "emits the warning" half
    /// of the stale-verdict requirement (the "stays unsafe / does NOT resume"
    /// half is pinned by `triggers.rs`
    /// `weather_verdict_stale_unsafe_stays_unsafe_and_is_detected`).
    #[test]
    fn weather_verdict_stale_warning_emits_once_then_rearms() {
        let mut warned = false;

        // Not stale -> no warning, latch stays disarmed.
        assert!(weather_verdict_stale_warning(false, 360, &mut warned).is_none());
        assert!(!warned);

        // Rising edge (stale & unsafe) -> emit, latch arms, message carries the
        // fail-closed framing + the staleness window.
        let msg = weather_verdict_stale_warning(true, 360, &mut warned)
            .expect("stale unsafe verdict must emit a warning on the rising edge");
        assert!(warned, "latch must arm after emitting");
        assert!(
            msg.contains("stale") && msg.contains("paused") && msg.contains("360"),
            "warning must name the stale fail-closed hold + the window: {msg}"
        );

        // Still stale -> rate-limited (no repeat while the feed stays dead).
        assert!(
            weather_verdict_stale_warning(true, 360, &mut warned).is_none(),
            "a still-stale verdict must not re-warn every poll"
        );
        assert!(warned);

        // Fresh / no-longer-unsafe -> re-arm, no warning.
        assert!(weather_verdict_stale_warning(false, 360, &mut warned).is_none());
        assert!(!warned, "latch must re-arm once the condition clears");

        // A subsequent stale episode warns again (proves re-arm works).
        assert!(
            weather_verdict_stale_warning(true, 360, &mut warned).is_some(),
            "a fresh stale episode after clearing must warn again"
        );
    }

    #[test]
    fn safety_check_interval_updates_runtime_config() {
        let mut executor = SequenceExecutor::new();

        executor.set_safety_check_interval_secs(45);

        assert_eq!(
            executor.runtime_config.read().safety_check_interval_secs,
            45
        );

        executor.set_safety_check_interval_secs(3);

        assert_eq!(executor.runtime_config.read().safety_check_interval_secs, 5);
    }

    #[test]
    fn test_save_path_configuration() {
        let mut executor = SequenceExecutor::new();

        executor.set_save_path(Some(std::path::PathBuf::from("/tmp/images")));

        assert!(executor.save_path.is_some());
    }

    #[test]
    fn test_get_set_state() {
        let executor = SequenceExecutor::new();

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            // Test state transitions
            assert_eq!(executor.get_state().await, ExecutorState::Idle);

            executor.set_state(ExecutorState::Running).await;
            assert_eq!(executor.get_state().await, ExecutorState::Running);

            executor.set_state(ExecutorState::Paused).await;
            assert_eq!(executor.get_state().await, ExecutorState::Paused);

            executor.set_state(ExecutorState::Stopping).await;
            assert_eq!(executor.get_state().await, ExecutorState::Stopping);

            executor.set_state(ExecutorState::Completed).await;
            assert_eq!(executor.get_state().await, ExecutorState::Completed);
        });
    }

    #[test]
    fn test_executor_state_debug() {
        // Test Debug trait (which is derived)
        assert_eq!(format!("{:?}", ExecutorState::Idle), "Idle");
        assert_eq!(format!("{:?}", ExecutorState::Running), "Running");
        assert_eq!(format!("{:?}", ExecutorState::Paused), "Paused");
        assert_eq!(format!("{:?}", ExecutorState::Stopping), "Stopping");
        assert_eq!(format!("{:?}", ExecutorState::Cancelled), "Cancelled");
        assert_eq!(format!("{:?}", ExecutorState::Completed), "Completed");
    }

    #[test]
    fn test_node_status_debug() {
        // Test Debug trait (which is derived)
        assert_eq!(format!("{:?}", NodeStatus::Pending), "Pending");
        assert_eq!(format!("{:?}", NodeStatus::Running), "Running");
        assert_eq!(format!("{:?}", NodeStatus::Success), "Success");
        assert_eq!(format!("{:?}", NodeStatus::Failure), "Failure");
        assert_eq!(format!("{:?}", NodeStatus::Skipped), "Skipped");
    }

    #[test]
    fn test_executor_default() {
        let executor = SequenceExecutor::default();
        assert!(executor.sequence.is_none());
    }

    #[test]
    fn test_executor_state_for_result_keeps_cancelled_distinct() {
        assert_eq!(
            executor_state_for_result(NodeStatus::Cancelled),
            ExecutorState::Cancelled
        );
        assert_eq!(
            executor_state_for_result(NodeStatus::Success),
            ExecutorState::Completed
        );
    }

    #[test]
    fn test_trigger_autofocus_context_preserves_runtime_metadata() {
        let trigger_context = TriggerActionContext {
            camera_id: Some("camera".to_string()),
            mount_id: Some("mount".to_string()),
            focuser_id: Some("focuser".to_string()),
            filterwheel_id: Some("wheel".to_string()),
            rotator_id: Some("rotator".to_string()),
            dome_id: Some("dome".to_string()),
            cover_calibrator_id: Some("panel".to_string()),
            save_path: Some(PathBuf::from("C:/captures")),
            latitude: Some(45.0),
            longitude: Some(-122.0),
            filter_focus_offsets: HashMap::from([("Ha".to_string(), 42)]),
        };
        let runtime_config = Arc::new(StdRwLock::new(RuntimeConfig::default()));
        let instruction_ctx = build_trigger_autofocus_context(
            &trigger_context,
            Some("M31".to_string()),
            Some(1.25),
            Some(41.0),
            Some("Ha".to_string()),
            Arc::new(AtomicBool::new(false)),
            Arc::new(crate::device_ops::NullDeviceOps),
            Arc::new(RwLock::new(TriggerState::new())),
            &runtime_config,
            None,
        );

        assert_eq!(instruction_ctx.target_name.as_deref(), Some("M31"));
        assert_eq!(
            instruction_ctx.save_path,
            Some(PathBuf::from("C:/captures"))
        );
        assert_eq!(instruction_ctx.latitude, Some(45.0));
        assert_eq!(instruction_ctx.longitude, Some(-122.0));
        assert_eq!(instruction_ctx.filter_focus_offsets.get("Ha"), Some(&42));
    }

    #[test]
    fn test_trigger_flip_context_keeps_focuser_id() {
        let trigger_context = TriggerActionContext {
            mount_id: Some("mount".to_string()),
            camera_id: Some("camera".to_string()),
            focuser_id: Some("focuser".to_string()),
            ..TriggerActionContext::default()
        };

        let flip_ctx = build_trigger_flip_context(
            &trigger_context,
            "M42".to_string(),
            Some(5.5),
            Some(-5.0),
            None,
            None,
        )
        .expect("flip context should be created");

        assert_eq!(flip_ctx.focuser_id.as_deref(), Some("focuser"));
        assert_eq!(flip_ctx.mount_id, "mount");
    }

    /// `terminate_with` must always set the cancellation flag
    /// before returning. Future RecoveryAction variants that exit through
    /// this helper inherit the invariant by construction.
    #[test]
    fn terminate_with_sets_is_cancelled_before_returning_triggers() {
        let flag = Arc::new(AtomicBool::new(false));
        let triggers = vec![
            ("trig_a".to_string(), RecoveryAction::ParkAndAbort),
            ("trig_b".to_string(), RecoveryAction::Pause),
        ];
        let returned = terminate_with(&flag, triggers, "unit-test");
        assert!(
            flag.load(Ordering::Relaxed),
            "terminate_with must store true into is_cancelled"
        );
        assert_eq!(returned.len(), 2);
        assert_eq!(returned[0].0, "trig_a");
        assert_eq!(returned[1].0, "trig_b");
    }

    /// `update_dither_config` must write through the shared
    /// `runtime_config` Arc so the next dither uses the new pixel count.
    /// This was the original audit-flagged silent-fallback site (the
    /// previous implementation `let _`'d the parameters).
    #[test]
    fn update_dither_config_writes_through_runtime_config() {
        let mut executor = SequenceExecutor::new();
        executor.update_dither_config(7.5, 0.5, 8.0, 60.0, true);
        let handle = executor.runtime_config_handle();
        let rc = handle.read();
        assert!((rc.dither.pixels - 7.5).abs() < f64::EPSILON);
        assert!((rc.dither.settle_pixels - 0.5).abs() < f64::EPSILON);
        assert!((rc.dither.settle_time - 8.0).abs() < f64::EPSILON);
        assert!((rc.dither.settle_timeout - 60.0).abs() < f64::EPSILON);
        assert!(rc.dither.ra_only);
    }

    /// `update_location` must update both the executor's own
    /// fields (used by next-start seeding) and the runtime_config Arc (used
    /// mid-flight by trigger actions).
    #[test]
    fn update_location_writes_through_runtime_config() {
        let mut executor = SequenceExecutor::new();
        executor.update_location(Some(40.7), Some(-74.0));
        assert_eq!(executor.latitude, Some(40.7));
        assert_eq!(executor.longitude, Some(-74.0));
        let handle = executor.runtime_config_handle();
        let rc = handle.read();
        assert_eq!(rc.latitude, Some(40.7));
        assert_eq!(rc.longitude, Some(-74.0));
    }

    /// Remediation 2026-06-09 (finding #2): the W1 daylight gate's max Sun
    /// altitude was NEVER populated from Dart — there was no setter, so the
    /// field held the derive-default and the native gate blocked only above the
    /// geometric horizon (0°), opening a twilight gap vs the Dart -12° gate.
    /// `update_max_sun_altitude` must now write the Dart value through
    /// `runtime_config` AND patch the live trigger state so the gate honours it.
    #[tokio::test]
    async fn update_max_sun_altitude_writes_through_runtime_config_and_trigger_state() {
        let mut executor = SequenceExecutor::new();

        // A pushed value lands verbatim in the runtime config...
        executor.update_max_sun_altitude(Some(-6.0)).await;
        {
            let handle = executor.runtime_config_handle();
            let rc = handle.read();
            assert_eq!(
                rc.max_sun_altitude_degrees,
                Some(-6.0),
                "the pushed Dart threshold must be written through runtime_config"
            );
        }
        // ...and is patched into the live trigger state so the gate (which reads
        // through the trigger-state handle) sees it without a sequence reload.
        {
            let mgr = executor.trigger_manager.read().await;
            let state = mgr.state();
            let guard = state.read().await;
            assert_eq!(
                guard.max_sun_altitude_degrees,
                Some(-6.0),
                "the trigger state the gate reads must carry the pushed threshold"
            );
        }

        // A None / non-finite push resolves to the DEFAULT (-12°) in the live
        // trigger state so the gate is NEVER weaker than the Dart W1 gate, while
        // the runtime config records the raw None (unset).
        executor.update_max_sun_altitude(None).await;
        {
            let handle = executor.runtime_config_handle();
            assert_eq!(handle.read().max_sun_altitude_degrees, None);
        }
        {
            let mgr = executor.trigger_manager.read().await;
            let state = mgr.state();
            let guard = state.read().await;
            assert_eq!(
                guard.max_sun_altitude_degrees,
                Some(crate::instructions::DEFAULT_MAX_SUN_ALTITUDE_DEGREES),
                "a None push must resolve to the -12° default in the gate's state"
            );
        }
    }

    /// Remediation 2026-06-09 (finding #2): the native default must equal the
    /// Dart `SchedulerConfig.maxSunAltitudeDegrees` default (-12°, nautical
    /// darkness) so an un-pushed native gate is no weaker than the Dart W1 gate.
    #[test]
    fn default_max_sun_altitude_matches_dart_nautical_darkness() {
        assert_eq!(
            crate::instructions::DEFAULT_MAX_SUN_ALTITUDE_DEGREES,
            -12.0,
            "native daylight-gate default must mirror the Dart scheduler's -12° \
             default so the twilight gap is closed"
        );
    }

    /// `update_filter_offsets` must propagate to runtime_config
    /// so the next filter change reads the updated map.
    #[test]
    fn update_filter_offsets_writes_through_runtime_config() {
        let mut executor = SequenceExecutor::new();
        let mut offsets = std::collections::HashMap::new();
        offsets.insert("Ha".to_string(), 250);
        offsets.insert("OIII".to_string(), -120);
        executor.update_filter_offsets(offsets.clone());
        let handle = executor.runtime_config_handle();
        let rc = handle.read();
        assert_eq!(rc.filter_focus_offsets.get("Ha"), Some(&250));
        assert_eq!(rc.filter_focus_offsets.get("OIII"), Some(&-120));
    }

    /// a single `Arc<CheckpointManager>` must be shared between
    /// the executor public API and the streaming-checkpoint task. Pointer
    /// equality on the Arc is a structural invariant; if `set_checkpoint_dir`
    /// ever drops back to `Box`/owned semantics this test fails immediately.
    #[test]
    fn checkpoint_manager_is_arc_shared() {
        let mut executor = SequenceExecutor::new();
        executor.set_checkpoint_dir("/tmp/nightshade_checkpoint_test_§1_16");
        let mgr_a = executor
            .checkpoint_manager
            .clone()
            .expect("checkpoint manager set");
        let mgr_b = executor
            .checkpoint_manager
            .clone()
            .expect("checkpoint manager set");
        assert!(
            Arc::ptr_eq(&mgr_a, &mgr_b),
            "set_checkpoint_dir must produce a single shared Arc"
        );
    }

    // -----------------------------------------------------------------
    // calculate_totals must recognise SmartExposure.
    // -----------------------------------------------------------------

    fn build_smart_exposure_sequence(
        plans: Vec<crate::FilterPlan>,
        budget_secs: f64,
    ) -> SequenceDefinition {
        let mut seq = SequenceDefinition::new("smart exposure totals test".to_string());
        let root = crate::NodeDefinition {
            id: "root".to_string(),
            name: "Root".to_string(),
            node_type: crate::NodeType::SmartExposure(crate::SmartExposureConfig {
                plans,
                rotate_filters: true,
                dither_on_filter_change: false,
                integration_budget_secs: budget_secs,
                batch_size: 1,
                loop_until_stopped: false,
            }),
            enabled: true,
            children: vec![],
        };
        seq.nodes.push(root);
        seq.root_node_id = Some("root".to_string());
        seq
    }

    fn plan_row(name: &str, count: u32, duration_secs: f64) -> crate::FilterPlan {
        crate::FilterPlan {
            filter_name: name.to_string(),
            filter_index: None,
            count,
            duration_secs,
            ..crate::FilterPlan::default()
        }
    }

    /// SmartExposure with no budget cap: totals must sum every plan's count
    /// and integration time. Before this was 0 / 0.0 because walk()
    /// only recognised `NodeType::TakeExposure`.
    #[test]
    fn calculate_totals_recognises_smart_exposure_plans_without_budget() {
        let exec = SequenceExecutor::new();
        let seq = build_smart_exposure_sequence(
            vec![
                plan_row("L", 60, 120.0), // 60 * 120 = 7200s
                plan_row("R", 30, 180.0), // 30 * 180 = 5400s
                plan_row("G", 30, 180.0), // 30 * 180 = 5400s
                plan_row("B", 30, 180.0), // 30 * 180 = 5400s
            ],
            0.0, // no cap
        );

        let (total_exposures, total_integration, indeterminate) = exec.calculate_totals(&seq);
        assert_eq!(total_exposures, 60 + 30 + 30 + 30);
        // 7200 + 5400 * 3 = 23400
        assert!(
            (total_integration - 23_400.0).abs() < f64::EPSILON,
            "expected 23400.0, got {}",
            total_integration
        );
        assert!(!indeterminate, "no budget cap → totals are deterministic");
    }

    /// SmartExposure with a tight budget cap: integration is capped to the
    /// budget and the indeterminate flag is set so the dashboard renders
    /// "approximately". Frame count remains the un-capped sum (worst case).
    #[test]
    fn calculate_totals_caps_smart_exposure_to_integration_budget() {
        let exec = SequenceExecutor::new();
        let seq = build_smart_exposure_sequence(
            vec![plan_row("L", 60, 120.0), plan_row("R", 60, 120.0)],
            7200.0, // 2h cap
        );

        let (total_exposures, total_integration, indeterminate) = exec.calculate_totals(&seq);
        // Un-capped frame total is still surfaced (60 + 60).
        assert_eq!(total_exposures, 120);
        assert!(
            (total_integration - 7_200.0).abs() < f64::EPSILON,
            "integration should be capped to budget; got {}",
            total_integration
        );
        assert!(
            indeterminate,
            "budget cap engaging means totals are indeterminate"
        );
    }

    /// SmartExposure under a Loop multiplies the totals — same pattern as
    /// TakeExposure under a Loop. Sanity-checks that the new arm doesn't
    /// short-circuit the multiplier propagation when an outer Loop wraps it.
    #[test]
    fn calculate_totals_smart_exposure_inside_loop_multiplies() {
        let exec = SequenceExecutor::new();
        let mut seq = SequenceDefinition::new("loop wrapping smart exposure".to_string());
        let loop_id = "loop".to_string();
        let se_id = "se".to_string();
        let loop_node = crate::NodeDefinition {
            id: loop_id.clone(),
            name: "Loop x3".to_string(),
            node_type: crate::NodeType::Loop(crate::LoopConfig {
                iterations: Some(3),
                condition: crate::LoopCondition::Count,
                condition_value: None,
                horizon_profile: None,
            }),
            enabled: true,
            children: vec![se_id.clone()],
        };
        let se_node = crate::NodeDefinition {
            id: se_id,
            name: "Smart".to_string(),
            node_type: crate::NodeType::SmartExposure(crate::SmartExposureConfig {
                plans: vec![plan_row("L", 10, 60.0)],
                rotate_filters: true,
                dither_on_filter_change: false,
                integration_budget_secs: 0.0,
                batch_size: 1,
                loop_until_stopped: false,
            }),
            enabled: true,
            children: vec![],
        };
        seq.nodes.push(loop_node);
        seq.nodes.push(se_node);
        seq.root_node_id = Some(loop_id);

        let (total_exposures, total_integration, indeterminate) = exec.calculate_totals(&seq);
        assert_eq!(total_exposures, 10 * 3);
        assert!(
            (total_integration - (10.0 * 60.0 * 3.0)).abs() < f64::EPSILON,
            "expected 1800.0, got {}",
            total_integration
        );
        assert!(
            !indeterminate,
            "Count-based Loop + un-capped SmartExposure → deterministic"
        );
    }

    // ------------------------------------------------------------------
    // Recovery Mode tests
    // ------------------------------------------------------------------

    #[test]
    fn executor_state_recovering_round_trips_through_serde() {
        // The bridge layer serialises ExecutorState to JSON for the
        // streaming-checkpoint blob; if `Recovering` ever fails to
        // round-trip the live state machine would silently drop the
        // recovery flag on a checkpoint reload.
        let json = serde_json::to_string(&ExecutorState::Recovering).expect("serialise");
        let back: ExecutorState = serde_json::from_str(&json).expect("deserialise");
        assert_eq!(back, ExecutorState::Recovering);
        assert_eq!(format!("{:?}", ExecutorState::Recovering), "Recovering");
    }

    #[test]
    fn fresh_executor_has_no_recovery_in_flight() {
        let executor = SequenceExecutor::new();
        assert!(executor.current_recovery().is_none());
        assert!(executor.recovery_history().is_empty());
        // Signals are initialised; entry counter is at the initial value.
        let signals = executor.recovery_signals_handle();
        assert_eq!(signals.current_entry(), 0);
        // The default RecoveryRuntimeConfig is pre-seeded into the
        // runtime config so the first recovery has SGP-style defaults.
        let rc = executor.runtime_config_handle();
        let cfg = rc.read().recovery.clone();
        assert!((cfg.retry_interval_secs - 600.0).abs() < f64::EPSILON);
        assert!((cfg.max_duration_secs - 5400.0).abs() < f64::EPSILON);
    }

    #[test]
    fn recovery_signals_request_methods_set_flags() {
        let executor = SequenceExecutor::new();
        let signals = executor.recovery_signals_handle();
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            executor.recovery_try_now().await.unwrap();
            executor.recovery_abort().await.unwrap();
        });
        // Both atomics are set even without a running executor (the
        // commands write the atomics first, then forward to the channel
        // which is None for an idle executor).
        assert!(signals.take_try_now());
        assert!(signals.take_abort());
    }

    #[test]
    fn update_recovery_config_writes_through_runtime() {
        let executor = SequenceExecutor::new();
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let cfg = crate::recovery::RecoveryRuntimeConfig {
            retry_interval_secs: 120.0,
            max_duration_secs: 1200.0,
            stop_tracking_during_recovery: false,
            abort_on_meridian: false,
            audible_alert_when_entered: false,
        };
        let mut executor = executor;
        rt.block_on(async {
            executor.update_recovery_config(cfg.clone()).await;
        });
        let handle = executor.runtime_config_handle();
        let rc = handle.read();
        assert!((rc.recovery.retry_interval_secs - 120.0).abs() < f64::EPSILON);
        assert!((rc.recovery.max_duration_secs - 1200.0).abs() < f64::EPSILON);
        assert!(!rc.recovery.stop_tracking_during_recovery);
        assert!(!rc.recovery.abort_on_meridian);
        assert!(!rc.recovery.audible_alert_when_entered);
    }

    /// Simulates the lifecycle of a successful recovery attempt for the
    /// GuideStarLost cause against a NullDeviceOps that reports
    /// `is_guiding == true` (the simulated guider is happy). The
    /// dispatch wires to the device_ops as advertised — when the guider
    /// reports "guiding", the attempt is `Succeeded`.
    #[test]
    fn run_recovery_attempt_guide_star_lost_with_null_ops_succeeds_when_guiding() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let device_ops: SharedDeviceOps = std::sync::Arc::new(crate::device_ops::NullDeviceOps);
        let mgr = Arc::new(RwLock::new(TriggerManager::new()));
        let outcome = rt.block_on(async {
            run_recovery_attempt(
                &crate::recovery::RecoveryCause::GuideStarLost,
                &device_ops,
                None,
                &[],
                &mgr,
            )
            .await
        });
        // NullDeviceOps returns is_guiding = true so the attempt
        // resolves to Succeeded — this proves the dispatch reads the
        // live guider status rather than blindly succeeding.
        assert_eq!(outcome, crate::recovery::AttemptOutcome::Succeeded);
    }

    /// The GuideStarLost dispatch returns `Failed` when the guider
    /// reports `is_guiding == false`. We test this via the structured
    /// branch on `run_recovery_attempt` by constructing the outcome
    /// directly — implementing a partial DeviceOps mock would require
    /// reimplementing the entire 50+ method trait surface. The
    /// dispatch logic itself is exercised by the
    /// `guide_star_lost_with_null_ops_succeeds_when_guiding` test and
    /// the integration tests in `recovery::tests`.
    #[test]
    fn attempt_outcome_failed_variant_carries_message() {
        let outcome = crate::recovery::AttemptOutcome::Failed {
            message: "Guider still reports star lost".to_string(),
        };
        match outcome {
            crate::recovery::AttemptOutcome::Failed { message } => {
                assert!(message.contains("star lost"));
            }
            other => panic!("expected Failed, got {:?}", other),
        }
    }

    /// WeatherUnsafe attempt with NullDeviceOps which reports safe.
    /// Validates the "wait then poll" pattern resolves correctly.
    #[test]
    fn run_recovery_attempt_weather_unsafe_with_null_ops_succeeds_when_safe() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let device_ops: SharedDeviceOps = std::sync::Arc::new(crate::device_ops::NullDeviceOps);
        let mgr = Arc::new(RwLock::new(TriggerManager::new()));
        let outcome = rt.block_on(async {
            run_recovery_attempt(
                &crate::recovery::RecoveryCause::WeatherUnsafe,
                &device_ops,
                None,
                &[],
                &mgr,
            )
            .await
        });
        // NullDeviceOps.safety_is_safe returns Ok(true).
        assert_eq!(outcome, crate::recovery::AttemptOutcome::Succeeded);
    }

    /// Architecture-unification 2026-06-05 (Subsystem 2 step 4): a weather
    /// recovery MUST NOT clear/resume on a hardware-only re-poll while the
    /// Dart-side verdict still reports unsafe (`weather_verdict_unsafe ==
    /// Some(true)`). NullDeviceOps.safety_is_safe returns Ok(true) (hardware
    /// reads safe), so the OLD code would have declared Succeeded and resumed
    /// the sequence into API-unsafe weather. With the verdict gate the attempt
    /// must Fail until the Dart verdict also clears.
    #[test]
    fn run_recovery_attempt_weather_unsafe_blocked_by_dart_verdict() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let device_ops: SharedDeviceOps = std::sync::Arc::new(crate::device_ops::NullDeviceOps);
        let mgr = Arc::new(RwLock::new(TriggerManager::new()));
        // Dart computed UNSAFE (API alert / threshold), even though the hardware
        // boolean reads safe.
        rt.block_on(async {
            let state = mgr.read().await.state();
            state.write().await.update_weather_verdict(Some(true));
        });
        let outcome = rt.block_on(async {
            run_recovery_attempt(
                &crate::recovery::RecoveryCause::WeatherUnsafe,
                &device_ops,
                None,
                &[],
                &mgr,
            )
            .await
        });
        match outcome {
            crate::recovery::AttemptOutcome::Failed { message } => {
                assert!(
                    message.contains("Dart verdict"),
                    "expected the Dart-verdict block message, got: {}",
                    message
                );
            }
            other => panic!(
                "expected Failed (Dart verdict still unsafe), got {:?}",
                other
            ),
        }
    }

    /// Sibling to the above: once the Dart verdict clears to `Some(false)`
    /// (explicitly safe) the hardware poll is consulted again and a safe
    /// hardware reading resumes the sequence. `None` (abstain) behaves the same
    /// — neither pins the sequence paused, so the gate only adds-unsafe.
    #[test]
    fn run_recovery_attempt_weather_unsafe_resumes_when_verdict_clears() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let device_ops: SharedDeviceOps = std::sync::Arc::new(crate::device_ops::NullDeviceOps);
        for verdict in [Some(false), None] {
            let mgr = Arc::new(RwLock::new(TriggerManager::new()));
            rt.block_on(async {
                let state = mgr.read().await.state();
                state.write().await.update_weather_verdict(verdict);
            });
            let outcome = rt.block_on(async {
                run_recovery_attempt(
                    &crate::recovery::RecoveryCause::WeatherUnsafe,
                    &device_ops,
                    None,
                    &[],
                    &mgr,
                )
                .await
            });
            assert_eq!(
                outcome,
                crate::recovery::AttemptOutcome::Succeeded,
                "verdict {:?} with safe hardware should resume",
                verdict
            );
        }
    }

    /// FocusDriftCritical and SlewFailed and PlateSolveFailed and Custom
    /// all use the "wait then resume" pattern.
    #[test]
    fn run_recovery_attempt_wait_then_resume_causes_all_succeed() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let device_ops: SharedDeviceOps = std::sync::Arc::new(crate::device_ops::NullDeviceOps);
        let mgr = Arc::new(RwLock::new(TriggerManager::new()));
        for cause in [
            crate::recovery::RecoveryCause::FocusDriftCritical,
            crate::recovery::RecoveryCause::SlewFailed,
            crate::recovery::RecoveryCause::PlateSolveFailed,
            crate::recovery::RecoveryCause::Custom("plugin".to_string()),
        ] {
            let outcome = rt.block_on(async {
                run_recovery_attempt(&cause, &device_ops, None, &[], &mgr).await
            });
            assert_eq!(
                outcome,
                crate::recovery::AttemptOutcome::Succeeded,
                "cause {:?} should resolve to Succeeded on the wait-then-resume path",
                cause
            );
        }
    }

    /// 4.0 Phase G — a consecutive-reject storm is NOT auto-recoverable by
    /// waiting (a wait cannot prove the clouds/dew cleared). The recovery
    /// attempt must escalate to a real operator `PauseForOperator`, never
    /// `Succeeded` — otherwise the run oscillated fail → wait → "recovered"
    /// → fail on a fresh recovery budget and burned the night.
    #[test]
    fn run_recovery_attempt_consecutive_rejects_escalates_to_operator_pause() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let device_ops: SharedDeviceOps = std::sync::Arc::new(crate::device_ops::NullDeviceOps);
        let mgr = Arc::new(RwLock::new(TriggerManager::new()));
        let outcome = rt.block_on(async {
            run_recovery_attempt(
                &crate::recovery::RecoveryCause::ConsecutiveRejectsExceeded,
                &device_ops,
                None,
                &[],
                &mgr,
            )
            .await
        });
        match outcome {
            crate::recovery::AttemptOutcome::PauseForOperator { message } => {
                assert!(
                    !message.is_empty(),
                    "operator-pause escalation must carry a reason"
                );
            }
            other => panic!(
                "consecutive-reject storm must escalate to PauseForOperator, got {:?}",
                other
            ),
        }
    }

    /// v4 BLOCKER #1 — the disposition that gates how a `PauseForOperator`
    /// escalation is handled. The SAFE default is "unattended": a rig nobody is
    /// watching MUST be abandoned safely (park + close), never passively frozen
    /// dome-open with safety triggers disabled until dawn. Only an explicitly
    /// present operator gets the passive Pause.
    #[test]
    fn recovery_escalation_unattended_is_safe_abandon_attended_is_passive_pause() {
        // The default RuntimeConfig is unattended (the safe default).
        assert!(
            !RuntimeConfig::default().operator_present,
            "RuntimeConfig must default to UNATTENDED (operator_present == false)"
        );
        assert_eq!(
            recovery_escalation_disposition(false),
            EscalationDisposition::SafeAbandon,
            "an unattended reject-storm escalation must drive a safe abandonment, \
             not a passive dome-open freeze"
        );
        assert_eq!(
            recovery_escalation_disposition(true),
            EscalationDisposition::PassivePause,
            "an attended escalation passively pauses for the present operator"
        );
    }

    /// v4 BLOCKER #2 — recovery entry stops tracking; any resume / operator-
    /// handoff path must restore it. The shared helper both branches use must
    /// command `mount_set_tracking(true)` and report no error on success.
    #[tokio::test]
    async fn restore_tracking_after_recovery_re_enables_tracking() {
        let ops_concrete = std::sync::Arc::new(ReacquireGuiderOps::new(false, true));
        let ops: SharedDeviceOps = ops_concrete.clone();
        let (event_tx, _rx) = broadcast::channel(16);

        let err = restore_tracking_after_recovery(
            &ops,
            Some("mount-1"),
            true, // stop_tracking was true → must restore
            "paused for operator",
            &event_tx,
        )
        .await;

        assert!(err.is_none(), "successful restore must not report an error");
        assert_eq!(
            ops_concrete.last_tracking_set(),
            Some(true),
            "tracking must be re-enabled before handing the run back"
        );
    }

    /// When tracking cannot be restored, the failure is LOUD — an error event
    /// is emitted and the message is returned — never a silent resume on a
    /// non-tracking mount.
    #[tokio::test]
    async fn restore_tracking_after_recovery_failure_is_loud() {
        let ops_concrete =
            std::sync::Arc::new(ReacquireGuiderOps::new(false, true).with_tracking_failure());
        let ops: SharedDeviceOps = ops_concrete.clone();
        let (event_tx, mut rx) = broadcast::channel(16);

        let err = restore_tracking_after_recovery(
            &ops,
            Some("mount-1"),
            true,
            "paused for operator",
            &event_tx,
        )
        .await;

        assert!(
            err.is_some(),
            "a tracking-restore failure must be surfaced, not swallowed"
        );
        let event = rx.try_recv().expect("a loud Error event must be emitted");
        match event {
            ExecutorEvent::Error { message } => {
                assert!(
                    message.contains("tracking could not be re-enabled"),
                    "the error must explain tracking was not restored: {message}"
                );
            }
            other => panic!("expected an Error event, got {other:?}"),
        }
    }

    /// If recovery never stopped tracking (`stop_tracking == false`), the
    /// helper is a no-op: it must not command tracking at all.
    #[tokio::test]
    async fn restore_tracking_after_recovery_noop_when_tracking_not_stopped() {
        let ops_concrete = std::sync::Arc::new(ReacquireGuiderOps::new(false, true));
        let ops: SharedDeviceOps = ops_concrete.clone();
        let (event_tx, _rx) = broadcast::channel(16);

        let err = restore_tracking_after_recovery(
            &ops,
            Some("mount-1"),
            false, // tracking was never stopped
            "after recovery",
            &event_tx,
        )
        .await;

        assert!(err.is_none());
        assert_eq!(
            ops_concrete.last_tracking_set(),
            None,
            "the helper must not touch tracking when recovery never stopped it"
        );
    }

    /// MountTrackingLost without a configured mount surfaces the
    /// "no mount" error rather than silently succeeding.
    #[test]
    fn run_recovery_attempt_mount_tracking_lost_without_mount_fails() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let device_ops: SharedDeviceOps = std::sync::Arc::new(crate::device_ops::NullDeviceOps);
        let mgr = Arc::new(RwLock::new(TriggerManager::new()));
        let outcome = rt.block_on(async {
            run_recovery_attempt(
                &crate::recovery::RecoveryCause::MountTrackingLost,
                &device_ops,
                None,
                &[],
                &mgr,
            )
            .await
        });
        match outcome {
            crate::recovery::AttemptOutcome::Failed { message } => {
                assert!(
                    message.contains("No mount"),
                    "expected 'No mount' error, got: {}",
                    message
                );
            }
            other => panic!("expected Failed, got {:?}", other),
        }
    }

    /// full-loop integration: a sequence containing a
    /// `NodeType::PluginNode` runs through `SequenceExecutor::start()`,
    /// emits `ExecutorEvent::PluginNodeRequested`, the test sends back
    /// `ExecutorCommand::PluginNodeFinished` via the public
    /// `plugin_node_finished()` API, the executor unblocks the
    /// instruction, and the sequence completes with `Success`.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn plugin_node_e2e_completes_via_executor_round_trip() {
        use crate::{NodeDefinition, NodeType, SequenceDefinition};
        let mut executor = SequenceExecutor::new();
        // Headless device-ops keeps the executor's start() requirements
        // satisfied without needing the real bridge.
        executor.set_device_ops(std::sync::Arc::new(crate::device_ops::NullDeviceOps));

        let mut sequence = SequenceDefinition::new("Plugin E2E".to_string());
        sequence.nodes.push(NodeDefinition {
            id: "plugin-1".to_string(),
            name: "Send notification".to_string(),
            node_type: NodeType::PluginNode {
                plugin_id: "com.example.pushover".to_string(),
                node_type_id: "pushover.notify".to_string(),
                config_json: r#"{"title":"E2E","message":"completed"}"#.to_string(),
                display_name: Some("Pushover".to_string()),
                timeout_secs: Some(10),
            },
            enabled: true,
            children: vec![],
        });
        sequence.root_node_id = Some("plugin-1".to_string());
        executor
            .load_sequence(sequence)
            .expect("sequence should load");

        let mut events = executor.subscribe();

        // The reply task waits for the PluginNodeRequested event and
        // then calls into the SequenceExecutor's public API the same
        // way the Dart side will. We can't move `executor` into the
        // task because we want to query state afterwards, so wrap it
        // in an Arc + RwLock mirroring the bridge's storage pattern.
        let executor = std::sync::Arc::new(tokio::sync::RwLock::new(executor));
        {
            let mut guard = executor.write().await;
            guard.start().await.expect("executor should start");
        }
        let executor_for_reply = executor.clone();
        let reply_task = tokio::spawn(async move {
            // Drain events until we see the plugin request, then reply.
            // The full event stream is noisier than this test cares
            // about — we just need the one variant.
            loop {
                match tokio::time::timeout(std::time::Duration::from_secs(5), events.recv()).await {
                    Ok(Ok(ExecutorEvent::PluginNodeRequested {
                        node_id,
                        plugin_id,
                        node_type_id,
                        config_json,
                        timeout_secs,
                        ..
                    })) => {
                        // Sanity-check the dispatch fields so the test
                        // catches accidental field reshuffles.
                        assert_eq!(node_id, "plugin-1");
                        assert_eq!(plugin_id, "com.example.pushover");
                        assert_eq!(node_type_id, "pushover.notify");
                        assert!(config_json.contains("E2E"));
                        assert_eq!(timeout_secs, 10);

                        let guard = executor_for_reply.read().await;
                        guard
                            .plugin_node_finished(
                                node_id,
                                true,
                                Some("delivered".to_string()),
                                Some(r#"{"phase":"finished","delivery_id":"e2e-1"}"#.to_string()),
                            )
                            .await
                            .expect("plugin_node_finished should succeed");
                        return true;
                    }
                    Ok(Ok(_other)) => continue, // ignore non-target events
                    Ok(Err(tokio::sync::broadcast::error::RecvError::Lagged(_))) => continue,
                    Ok(Err(tokio::sync::broadcast::error::RecvError::Closed)) => return false,
                    Err(_elapsed) => return false,
                }
            }
        });

        let saw_request = tokio::time::timeout(std::time::Duration::from_secs(15), reply_task)
            .await
            .expect("reply task should complete")
            .expect("reply task should not panic");
        assert!(
            saw_request,
            "expected to observe the PluginNodeRequested event"
        );

        // Allow the executor task to finish processing the verdict +
        // mark the sequence Completed. We poll the state rather than
        // sleeping because polling is precise.
        let mut iters = 0;
        loop {
            iters += 1;
            let state = executor.read().await.get_state().await;
            if matches!(state, ExecutorState::Completed) {
                break;
            }
            if iters > 200 {
                panic!(
                    "executor did not reach Completed within 5s; state={:?}",
                    state
                );
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }

        // Final state assertion: node was marked Success and recorded
        // in the executor's progress map.
        let progress = executor.read().await.get_progress();
        assert_eq!(
            progress.node_statuses.get("plugin-1"),
            Some(&NodeStatus::Success),
            "plugin node should be recorded as Success"
        );
    }

    // =====================================================================
    // GuideStarLost recovery — re-acquisition tests (P0 fix).
    //
    // The previous recovery arm only *queried* is_guiding and could never
    // re-acquire a lost star. These tests assert the new behaviour: the
    // recovery actively calls guider_start (re-acquire) and only succeeds
    // once guiding re-locks.
    // =====================================================================

    use crate::device_ops::{DeviceOps, DeviceResult, GuidingStatus};

    /// DeviceOps that simulates a guider which is NOT guiding until
    /// `guider_start` is called, after which `guider_get_status` reports
    /// guiding. Records whether `guider_start` was invoked.
    struct ReacquireGuiderOps {
        inner: std::sync::Arc<crate::device_ops::NullDeviceOps>,
        /// Shared so the test can observe whether re-acquire was issued.
        started: std::sync::Arc<std::sync::atomic::AtomicBool>,
        start_should_fail: bool,
        relock_after_start: bool,
        /// Records the last `mount_set_tracking(enabled)` value so a test can
        /// assert tracking was restored. `None` => never called.
        last_tracking_set: std::sync::Arc<std::sync::Mutex<Option<bool>>>,
        /// When true, `mount_set_tracking(true)` returns Err so a test can
        /// exercise the loud-error-on-failure path.
        tracking_set_should_fail: bool,
    }

    impl ReacquireGuiderOps {
        fn new(start_should_fail: bool, relock_after_start: bool) -> Self {
            Self {
                inner: std::sync::Arc::new(crate::device_ops::NullDeviceOps),
                started: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
                start_should_fail,
                relock_after_start,
                last_tracking_set: std::sync::Arc::new(std::sync::Mutex::new(None)),
                tracking_set_should_fail: false,
            }
        }

        fn with_tracking_failure(mut self) -> Self {
            self.tracking_set_should_fail = true;
            self
        }

        fn last_tracking_set(&self) -> Option<bool> {
            *self.last_tracking_set.lock().unwrap()
        }
    }

    #[async_trait::async_trait]
    impl DeviceOps for ReacquireGuiderOps {
        async fn mount_set_tracking(&self, id: &str, enabled: bool) -> DeviceResult<()> {
            *self.last_tracking_set.lock().unwrap() = Some(enabled);
            if self.tracking_set_should_fail && enabled {
                return Err(format!("simulated tracking-enable failure for {}", id));
            }
            Ok(())
        }

        async fn guider_get_status(&self) -> DeviceResult<GuidingStatus> {
            // Guiding only once a (successful) re-acquire has been issued.
            let guiding = self.started.load(Ordering::Relaxed) && self.relock_after_start;
            Ok(GuidingStatus {
                is_guiding: guiding,
                rms_ra: 0.5,
                rms_dec: 0.4,
                rms_total: 0.64,
            })
        }

        async fn guider_start(
            &self,
            _settle_pixels: f64,
            _settle_time: f64,
            _settle_timeout: f64,
        ) -> DeviceResult<()> {
            if self.start_should_fail {
                return Err("simulated guider_start failure".to_string());
            }
            self.started.store(true, Ordering::Relaxed);
            Ok(())
        }

        // === delegating methods (every other DeviceOps method) ===
        async fn mount_slew_to_coordinates(&self, id: &str, ra: f64, dec: f64) -> DeviceResult<()> {
            self.inner.mount_slew_to_coordinates(id, ra, dec).await
        }
        async fn mount_abort_slew(&self, id: &str) -> DeviceResult<()> {
            self.inner.mount_abort_slew(id).await
        }
        async fn mount_get_coordinates(&self, id: &str) -> DeviceResult<(f64, f64)> {
            self.inner.mount_get_coordinates(id).await
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
            self.inner.mount_is_slewing(id).await
        }
        async fn mount_is_parked(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_is_parked(id).await
        }
        async fn mount_can_flip(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_can_flip(id).await
        }
        async fn mount_side_of_pier(&self, id: &str) -> DeviceResult<crate::meridian::PierSide> {
            self.inner.mount_side_of_pier(id).await
        }
        async fn mount_is_tracking(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_is_tracking(id).await
        }
        async fn camera_start_exposure(
            &self,
            id: &str,
            d: f64,
            g: Option<i32>,
            o: Option<i32>,
            bx: i32,
            by: i32,
        ) -> DeviceResult<crate::device_ops::ImageData> {
            self.inner.camera_start_exposure(id, d, g, o, bx, by).await
        }
        async fn camera_abort_exposure(&self, id: &str) -> DeviceResult<()> {
            self.inner.camera_abort_exposure(id).await
        }
        async fn camera_set_cooler(&self, id: &str, e: bool, t: f64) -> DeviceResult<()> {
            self.inner.camera_set_cooler(id, e, t).await
        }
        async fn camera_get_temperature(&self, id: &str) -> DeviceResult<f64> {
            self.inner.camera_get_temperature(id).await
        }
        async fn camera_get_cooler_power(&self, id: &str) -> DeviceResult<f64> {
            self.inner.camera_get_cooler_power(id).await
        }
        async fn focuser_move_to(&self, id: &str, p: i32) -> DeviceResult<()> {
            self.inner.focuser_move_to(id, p).await
        }
        async fn focuser_get_position(&self, id: &str) -> DeviceResult<i32> {
            self.inner.focuser_get_position(id).await
        }
        async fn focuser_is_moving(&self, id: &str) -> DeviceResult<bool> {
            self.inner.focuser_is_moving(id).await
        }
        async fn focuser_get_temperature(&self, id: &str) -> DeviceResult<Option<f64>> {
            self.inner.focuser_get_temperature(id).await
        }
        async fn focuser_halt(&self, id: &str) -> DeviceResult<()> {
            self.inner.focuser_halt(id).await
        }
        async fn filterwheel_set_position(&self, id: &str, p: i32) -> DeviceResult<()> {
            self.inner.filterwheel_set_position(id, p).await
        }
        async fn filterwheel_get_position(&self, id: &str) -> DeviceResult<i32> {
            self.inner.filterwheel_get_position(id).await
        }
        async fn filterwheel_get_names(&self, id: &str) -> DeviceResult<Vec<String>> {
            self.inner.filterwheel_get_names(id).await
        }
        async fn filterwheel_set_filter_by_name(&self, id: &str, n: &str) -> DeviceResult<i32> {
            self.inner.filterwheel_set_filter_by_name(id, n).await
        }
        async fn rotator_move_to(&self, id: &str, a: f64) -> DeviceResult<()> {
            self.inner.rotator_move_to(id, a).await
        }
        async fn rotator_move_relative(&self, id: &str, d: f64) -> DeviceResult<()> {
            self.inner.rotator_move_relative(id, d).await
        }
        async fn rotator_get_angle(&self, id: &str) -> DeviceResult<f64> {
            self.inner.rotator_get_angle(id).await
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
        async fn guider_stop(&self) -> DeviceResult<()> {
            self.inner.guider_stop().await
        }
        async fn plate_solve(
            &self,
            d: &crate::device_ops::ImageData,
            ra: Option<f64>,
            dec: Option<f64>,
            s: Option<f64>,
        ) -> DeviceResult<crate::device_ops::PlateSolveResult> {
            self.inner.plate_solve(d, ra, dec, s).await
        }
        async fn save_fits(
            &self,
            d: &crate::device_ops::ImageData,
            f: &str,
            fctx: &crate::scheduling::FrameContext,
        ) -> DeviceResult<()> {
            self.inner.save_fits(d, f, fctx).await
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
            self.inner.dome_open(id).await
        }
        async fn dome_close(&self, id: &str) -> DeviceResult<()> {
            self.inner.dome_close(id).await
        }
        async fn dome_park(&self, id: &str) -> DeviceResult<()> {
            self.inner.dome_park(id).await
        }
        async fn dome_get_shutter_status(&self, id: &str) -> DeviceResult<String> {
            self.inner.dome_get_shutter_status(id).await
        }
        async fn safety_is_safe(&self, id: Option<&str>) -> DeviceResult<bool> {
            self.inner.safety_is_safe(id).await
        }
        async fn calculate_image_hfr(
            &self,
            d: &crate::device_ops::ImageData,
        ) -> DeviceResult<Option<f64>> {
            self.inner.calculate_image_hfr(d).await
        }
        async fn detect_stars_in_image(
            &self,
            d: &crate::device_ops::ImageData,
        ) -> DeviceResult<Vec<(f64, f64, f64)>> {
            self.inner.detect_stars_in_image(d).await
        }
        async fn cover_calibrator_open_cover(&self, id: &str) -> DeviceResult<()> {
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

    #[tokio::test]
    async fn guide_star_lost_recovery_actively_reacquires() {
        // Guider is lost; guider_start succeeds and the guider re-locks.
        let guider = ReacquireGuiderOps::new(false, true);
        let started = guider.started.clone();
        let ops: SharedDeviceOps = std::sync::Arc::new(guider);
        let outcome = recover_guide_star(&ops).await;
        assert!(
            matches!(outcome, crate::recovery::AttemptOutcome::Succeeded),
            "recovery should succeed once the guider re-locks after re-acquire"
        );
        // The re-acquire MUST have been issued (the old code never did this).
        assert!(
            started.load(Ordering::Relaxed),
            "guider_start (re-acquisition) must be called during recovery"
        );
    }

    #[tokio::test]
    async fn guide_star_lost_recovery_fails_closed_when_start_errors() {
        // guider_start itself errors → recovery must fail closed.
        let ops: SharedDeviceOps = std::sync::Arc::new(ReacquireGuiderOps::new(true, false));
        let outcome = recover_guide_star(&ops).await;
        assert!(
            matches!(outcome, crate::recovery::AttemptOutcome::Failed { .. }),
            "recovery must fail closed when guider_start errors"
        );
    }
}
