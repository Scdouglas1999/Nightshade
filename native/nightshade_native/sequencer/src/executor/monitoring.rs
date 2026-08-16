//! Free-standing monitoring helpers the executor's trigger monitor and
//! recovery driver call: poll bounding, the stall watchdog, mount-tracking
//! edge detection, recovery escalation, and the weather-verdict staleness
//! rules. Moved verbatim out of `executor/mod.rs`.

use super::*;

pub(super) fn effective_safety_check_interval_secs(value: u64) -> u64 {
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
pub(super) fn effective_weather_verdict_staleness_secs(value: u64) -> u64 {
    if value == 0 {
        DEFAULT_WEATHER_VERDICT_STALENESS_SECS
    } else {
        value.clamp(30, 86_400)
    }
}

/// How long any one trigger-monitor device poll may take before it is treated
/// as failed.
///
/// The monitor is the only thing enforcing weather, altitude, drift,
/// tracking-loss, dome and meridian protection while the execution branch
/// exposes. A driver call that never returns — a documented hazard on this
/// project's ASCOM path — parks the monitor's loop forever: it never reaches
/// its next tick, and the `select!` that joins it only handles the monitor
/// *exiting*, not hanging. Every poll is therefore bounded, and a poll that
/// runs out of time is reported as the poll *failure* it is, which the
/// `SafetyFailMode` ladder and each caller's `Err` arm already know how to
/// handle. Ten seconds is far longer than any healthy driver round-trip and
/// far shorter than an exposure.
pub(super) const TRIGGER_POLL_TIMEOUT_SECS: u64 = 10;

/// How long the monitor may go without completing a loop iteration before the
/// watchdog declares it dead.
///
/// A pathological iteration in which every bounded poll times out still
/// finishes well inside this window, so only a stall the per-call timeouts
/// cannot see (a blocking driver call that never yields to the runtime, a
/// deadlocked lock) reaches it.
pub(super) const TRIGGER_MONITOR_STALL_TIMEOUT_SECS: u64 = 180;

/// How often the mount is polled for tracking / slewing / parked / pier side /
/// coordinates.
///
/// Running these five calls on the monitor's 1 Hz tick is five serial
/// round-trips per second, which is expensive on ASCOM (single-threaded
/// apartment, per-call COM marshalling) and on INDI. Nothing downstream needs
/// second-resolution — tracking loss is edge-detected and then waits minutes
/// before acting, and the meridian hour angle moves 15° per hour.
pub(super) const MOUNT_POLL_INTERVAL_SECS: u64 = 5;

/// Bound one trigger-monitor device poll. See [`TRIGGER_POLL_TIMEOUT_SECS`].
pub(super) async fn bounded_poll<T>(
    what: &str,
    poll: impl std::future::Future<Output = crate::device_ops::DeviceResult<T>>,
) -> crate::device_ops::DeviceResult<T> {
    let limit = std::time::Duration::from_secs(TRIGGER_POLL_TIMEOUT_SECS);
    match tokio::time::timeout(limit, poll).await {
        Ok(result) => result,
        Err(_) => Err(format!(
            "{what} did not answer within {TRIGGER_POLL_TIMEOUT_SECS}s (treated as a poll failure)"
        )),
    }
}

/// Resolves once the trigger monitor has gone `stall_after` without completing
/// a loop iteration.
///
/// The `select!` that joins the monitor handles it exiting; it cannot see it
/// hanging, and a hung monitor looks exactly like a healthy one from the
/// outside while every protection it enforces is silently gone. This is the
/// detector for that case.
///
/// A trigger recovery action legitimately holds the loop for minutes (a
/// meridian-flip retry ladder sleeps between attempts), so the watchdog holds
/// off while one is in flight — it watches the poll phase, not the action.
pub(super) async fn trigger_monitor_stall_watchdog(
    mut heartbeat: watch::Receiver<u64>,
    action_in_flight: Arc<AtomicBool>,
    stall_after: std::time::Duration,
) {
    loop {
        match tokio::time::timeout(stall_after, heartbeat.changed()).await {
            // A fresh beat: the monitor completed another iteration.
            Ok(Ok(())) => {}
            // The monitor future was dropped, so it is already resolved and
            // whoever dropped it owns the outcome. Never win the join.
            Ok(Err(_)) => std::future::pending::<()>().await,
            Err(_) if action_in_flight.load(Ordering::Acquire) => {}
            Err(_) => return,
        }
    }
}

/// Decide whether a mount tracking poll represents a genuine *loss* of tracking
/// (an ON → OFF transition) rather than tracking simply not having started yet.
///
/// "Lost" means tracking was observed ON and then went OFF, so the PREVIOUS
/// reading (`previously_tracking`) must have been `Some(true)`. A first poll
/// (`None`) or a mount that has not yet started tracking never trips it — a
/// level-triggered `expected && !tracking` test fires `MountTrackingLost` on
/// the very first poll of a still-parked mount and self-cancels the sequence
/// seconds after start, and `safety_fail_mode = FailOpen` cannot suppress a
/// mount trigger. A genuine mid-sequence drop (`Some(true)` → `false`) still
/// trips it.
pub(super) fn mount_tracking_just_lost(
    tracking_expected: bool,
    currently_tracking: bool,
    previously_tracking: Option<bool>,
    already_flagged_lost: bool,
) -> bool {
    tracking_expected
        && !currently_tracking
        && !already_flagged_lost
        && previously_tracking == Some(true)
}

/// One mount-tracking poll's verdict for the trigger monitor's device-
/// readiness gate. `currently_tracking` is the fresh `mount_is_tracking`
/// reading; the other arguments are the baseline carried in `TriggerState`.
///
/// Returns `(expected, just_lost)`:
///   * `expected` is the new `mount_tracking_expected` baseline. It is armed
///     LAZILY — set to `true` only once the mount has been OBSERVED actually
///     tracking, never assumed at monitor start. Until the first `Ok(true)`
///     reading a not-yet-tracking / still-parked / headless mount keeps it
///     `false`, so the loss detector stays disarmed and a loaded sequence
///     cannot self-cancel at startup. The baseline only ever latches up, so a
///     value restored from a mid-session checkpoint is preserved.
///   * `just_lost` is whether this poll is a genuine ON → OFF loss, evaluated
///     against the (possibly freshly armed) `expected` baseline.
pub(super) fn mount_tracking_poll_verdict(
    expected_before: bool,
    currently_tracking: bool,
    previously_tracking: Option<bool>,
    already_flagged_lost: bool,
) -> (bool, bool) {
    let expected = expected_before || currently_tracking;
    let just_lost = mount_tracking_just_lost(
        expected,
        currently_tracking,
        previously_tracking,
        already_flagged_lost,
    );
    (expected, just_lost)
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
/// Factored out of the executor task so the safety decision is unit-testable
/// on its own. The default — and the SAFE default — is "unattended"
/// (`operator_present == false`), which must drive a safe abandonment rather
/// than a passive, trigger-disabled, dome-open freeze.
pub(super) fn recovery_escalation_disposition(operator_present: bool) -> EscalationDisposition {
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
/// Recovery entry stops tracking by default, and the generic Resume command
/// does not restore it, so any path that resumes or hands the run back to the
/// operator must call this first — otherwise the sequence exposes on a
/// non-tracking mount and every frame trails while the UI reports "Running".
/// Both the recovered-resume branch and the attended operator-Pause branch go
/// through here. A failure is never silent: it logs at error level and
/// forwards an `ExecutorEvent::Error`.
///
/// `context_label` distinguishes the wording ("after recovery" vs "before
/// operator Pause") so the operator sees which path could not restore tracking.
/// Returns `Some(message)` iff tracking restoration failed (also already
/// emitted), so callers/tests can assert on it.
pub(super) async fn restore_tracking_after_recovery(
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

    // Never command tracking on a PARKED mount.
    //
    // Observed on the live rig: a MoveRotator failure on a rig with no rotator
    // drove the recovery ladder, and this resume path then issued
    // `set tracking = true` on a parked Pegasus NYX-101 — unprompted motion
    // intent on stowed hardware, from a failure that had nothing to do with the
    // mount. It was refused (0x80020009) only because the driver happened to
    // reject it while parked; a mount that accepted would have started sidereal
    // motion against its park latch.
    //
    // A park is also a deliberate safe state — the operator, the weather rule,
    // or the dawn shutdown put it there — and automatic recovery must not take
    // a rig out of a safe state on its own initiative.
    //
    // Reporting matters as much as the command: the generic failure branch
    // below shouts "resumed frames may trail until tracking is restored",
    // which is untrue of a parked mount that is not imaging at all. Say what is
    // actually the case instead.
    match device_ops.mount_is_parked(mount_id).await {
        Ok(true) => {
            tracing::warn!(
                "[RECOVERY] Not re-enabling tracking on '{}' {}: the mount is \
                 parked. Recovery does not un-park a mount on its own.",
                mount_id,
                context_label
            );
            let message = format!(
                "Recovery {} but tracking was not re-enabled on {}: the mount \
                 is parked. Un-park it before resuming imaging.",
                context_label, mount_id
            );
            let _ = event_tx.send(ExecutorEvent::Error {
                message: message.clone(),
            });
            return Some(message);
        }
        Ok(false) => {}
        // Unknown park state: proceed. Refusing to restore tracking because the
        // park flag could not be read would strand a genuinely tracking-capable
        // mount untracked, which is the failure this whole function exists to
        // prevent. The set below reports its own outcome truthfully either way.
        Err(e) => {
            tracing::warn!(
                "[RECOVERY] Could not read park state of '{}' {} ({}); \
                 attempting to restore tracking anyway.",
                mount_id,
                context_label,
                e
            );
        }
    }

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
/// loop. A free function rather than inline driver code so an integration test
/// can drive the real device-ops and assert the call ORDER (tracking restored
/// BEFORE the Paused `StateChanged`) and the SafeAbandon path (park+close →
/// Failed, never a resumable Paused-untracked state).
///
/// The disposition is derived live from `operator_present`:
///   * UNATTENDED (default) → SafeAbandon: park mount, close cover+dome, FAIL.
///   * ATTENDED → PassivePause: restore tracking, then flip to Paused.
pub(super) async fn apply_recovery_escalation(
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
        // UNATTENDED reject-storm escalation is a SAFE ABANDONMENT, identical to
        // the give-up branch: park the mount (the OTA can't track into the Sun at
        // dawn), close the cover, close the dome (verified — see
        // `park_and_close_safe_state`), then FAIL the run, which cancels the node
        // tree.
        //
        // A passive Paused state is not an option here: the trigger monitor
        // short-circuits on `state != Running` (it `continue`s), so the weather /
        // altitude / dawn triggers stop evaluating while the node tree is never
        // parked — leaving the rig dome+cover OPEN with safety monitoring OFF until
        // dawn, where a rolling cloud / dew reject-storm can lose the optics.
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

        // Restore tracking BEFORE handing off to the operator
        // Pause. Recovery entry stops tracking (the default); the generic Resume
        // path does NOT re-enable it, so resuming from this Pause would expose
        // on a non-tracking mount and every frame would trail with the UI saying
        // "Running". Mirror the recovered branch (same shared helper): restore
        // tracking for all causes, loud error on failure (never silently leave a
        // resumable Pause that exposes untracked).
        let tracking_warning = restore_tracking_after_recovery(
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
            // The status API (`sequencer_get_status`) reads this snapshot, not
            // the event stream. Dropping the restore verdict here left the
            // pause reason alone on screen while the mount sat untracked, so
            // the operator's Resume exposed on a drifting mount. Carry the
            // helper's verdict into the message the poller actually reads.
            prog.message = Some(match &tracking_warning {
                Some(warning) => format!("{pause_message} — {warning}"),
                None => pause_message.clone(),
            });
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
pub(super) fn weather_verdict_stale_warning(
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
/// The Dart side mirrors this enum as `NoDataResolution` and is pinned against
/// the identical table by `weather_fail_mode_parity_test.dart`; the Rust side
/// is pinned by `safety_fail_mode_no_data_resolution_truth_table` in this
/// module. A row changed here must be changed in BOTH tests.
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
