//! [`SequenceExecutor::start`] — the run supervisor: preflight, the spawned
//! executor future, the command handler, the checkpoint streamer, the
//! recovery driver, the trigger monitor, and the join/finalize tail. Moved
//! verbatim out of `executor/mod.rs`; the body is unchanged.

use super::*;

impl SequenceExecutor {
    /// Start executing the sequence
    ///
    /// A run that has ended leaves the executor parked in a terminal state, and
    /// nothing else ever put it back to `Idle` — so the SECOND sequence of a
    /// night was refused with "Cannot start: executor is Completed" and the app
    /// had to be restarted (losing every device connection) to run anything
    /// else. Worse, the desktop Start button surfaced nothing at all: pre-flight
    /// passed, "Start Anyway" was accepted, and no run began.
    ///
    /// An explicit start request from a terminal state unambiguously means "run
    /// it again", so recycle the executor here rather than failing. Non-terminal
    /// busy states (`Running`, `Paused`, `Stopping`, `Recovering`) are still
    /// refused: those are genuine conflicts where silently resetting would
    /// abandon a live run.
    pub async fn start(&mut self) -> Result<(), String> {
        let state = self.get_state().await;
        if matches!(
            state,
            ExecutorState::Completed | ExecutorState::Failed | ExecutorState::Cancelled
        ) {
            tracing::info!(
                "Start requested while executor was {:?}; recycling to Idle for a fresh run",
                state
            );
            self.reset().await;

            // `reset()` wipes SequenceProgress back to default, which zeroes the
            // totals that `load_sequence()` seeded moments earlier — the caller
            // loads the sequence and THEN starts it, so on every run after the
            // first the recycle threw the denominator away.
            //
            // Observed on the live rig across four consecutive runs in one app
            // launch: run 1 (from a fresh `Idle`) reported
            // `completedExposures 3 / totalExposures 3, progressPercent 1.0`,
            // while runs after a terminal state reported
            // `completedExposures 3 / totalExposures 0, progressPercent 0.0` —
            // a finished, fully successful run rendering as a 0% progress bar
            // on both the Run Dashboard and the mobile cockpit.
            //
            // Re-seed from the retained sequence (reset deliberately keeps
            // `self.sequence` so the same tree can be re-run).
            if let Some(sequence) = self.sequence.as_ref() {
                let (total_exposures, total_integration, indeterminate) =
                    self.calculate_totals(sequence);
                let mut progress = self.progress.write();
                if indeterminate {
                    progress.total_exposures = 0;
                    progress.total_integration_secs = 0.0;
                    progress.estimated_remaining_secs = None;
                } else {
                    progress.total_exposures = total_exposures;
                    progress.total_integration_secs = total_integration;
                }
            }
        }

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

        // Save-path preflight. A capture sequence with nowhere to write is not a
        // run, it is a night thrown away — refuse it here rather than letting
        // every frame reach the "captured but NOT SAVED" branch.
        if self
            .root_node
            .as_ref()
            .is_some_and(|root| tree_needs_base_save_path(&**root))
        {
            validate_capture_save_path(self.save_path.as_deref())?;
        }

        // Device preflight. A sequence that declares hardware the executor
        // cannot resolve is not a run either: the instruction fails
        // "No <device> connected", the disconnect classifier promotes that to a
        // DeviceDisconnected recovery, and the run burns its whole recovery
        // budget waiting for a device that was never configured. Refuse here,
        // beside the save-path check, so every start path (desktop, mobile,
        // headless load->start) gets the same answer — and so the operator
        // reads it before going to bed rather than finding "Failed" at dawn.
        {
            let mut required = std::collections::BTreeMap::new();
            if let Some(root) = self.root_node.as_ref() {
                collect_required_devices(&**root, &mut required);
            }
            validate_required_devices(&required, |role| match role {
                RequiredDevice::Camera => self.camera_id.clone(),
                RequiredDevice::Mount => self.mount_id.clone(),
                RequiredDevice::FilterWheel => self.filterwheel_id.clone(),
                RequiredDevice::Focuser => self.focuser_id.clone(),
                RequiredDevice::Rotator => self.rotator_id.clone(),
            })?;
        }

        // Unreachable-instruction preflight. Detected before the mount moves so
        // the operator learns the sequence is mis-shaped at Start instead of
        // reading `completed` over a run that skipped most of its work.
        let unreachable_instruction_names = {
            let mut names = Vec::new();
            if let Some(root) = self.root_node.as_ref() {
                unreachable_instructions(&**root, &mut names);
            }
            names
        };
        if !unreachable_instruction_names.is_empty() {
            let message = unreachable_instructions_message(&unreachable_instruction_names);
            tracing::error!("{}", message);
            let _ = self.event_tx.send(ExecutorEvent::Error { message });
        }

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
        let (run_completion_tx, run_completion_rx) = oneshot::channel();
        self.run_completion_rx = Some(run_completion_rx);

        self.set_state(ExecutorState::Running).await;

        // Per-run trigger hygiene. `TriggerManager` (and its `TriggerState`) are
        // built once in `SequenceExecutor::new()` and live for the whole process,
        // so without this every latch set by run N is still set when run N+1
        // starts. Observed on the live rig: run 1 selected "Filter 2" and left
        // `autofocus_invalidated` set; run 2 — a different sequence selecting
        // "Filter 4" — force-fired the HFR trigger one second after start with
        // the reason `filter changed to Filter 2`.
        //
        // Then disarm the standard autofocus-action triggers when this run has
        // no focuser. A filter or target change invalidates the autofocus state,
        // which makes the HFR trigger fire unconditionally on the next tick;
        // with no focuser the executor's Autofocus arm cannot act, and it used
        // to answer by pausing the run indefinitely (`Execution paused at
        // boundary, waiting for resume...`) while `/api/sequencer/status` kept
        // reporting `running`. Reproduced end to end: a two-node sequence
        // (change filter, then expose) hung forever on the filter node, with no
        // frames and no terminal event, on a rig whose focuser was simply not
        // connected.
        {
            let manager = self.trigger_manager.write().await;
            manager.state().write().await.reset_for_new_run();
        }
        if self.focuser_id.is_none() {
            let disarmed = {
                let mut manager = self.trigger_manager.write().await;
                manager.disarm_autofocus_triggers()
            };
            if !disarmed.is_empty() {
                tracing::warn!(
                    "No focuser is configured for this run; disarming autofocus-action \
                     triggers [{}]. Focus drift will NOT be corrected automatically — \
                     connect a focuser to re-enable trigger-driven refocus.",
                    disarmed.join(", ")
                );
            }
        }

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
                } else if let Some(pushed) = self.runtime_config.read().autofocus.clone() {
                    // No node, but the operator's settings were pushed via
                    // `update_autofocus_config`. Use those rather than library
                    // defaults — a sequence with no Autofocus node is exactly
                    // the one whose interval trigger fires unattended, so this
                    // is the case where getting the tuning wrong costs a night.
                    tracing::info!(
                        "No Autofocus node in the sequence; trigger-fired refocus will use the \
                         operator's autofocus settings (attempts={}, failure tolerance={}x, \
                         failure action={:?})",
                        pushed.number_of_attempts,
                        pushed.failure_hfr_tolerance_ratio,
                        pushed.failure_action
                    );
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

        // Which node ids are targets, and what target they name. Read once at
        // start from the same `SequenceDefinition` the tree was built from, so
        // the identity that reaches subscribers is the node id — never a
        // display name.
        //
        // `ExecutorEvent::TargetStarted` existed and the bridge already mapped
        // it to `SequencerEvent::TargetChanged`, but NOTHING in this crate ever
        // constructed it: the variant had zero producers, so Dart's
        // `currentTarget` stayed null for every run ever executed. Everything
        // keyed off it then silently fell through to its fallback — most
        // visibly `sequence_runs.stats_json.targetBreakdown`, which bucketed a
        // whole night under the SEQUENCE's name ("New Sequence") while the
        // frames on disk and the FITS `OBJECT` card said the target's ("New
        // Target"). The run record disagreed with the files it had written.
        let target_node_metadata: HashMap<NodeId, (String, f64, f64)> = self
            .sequence
            .as_ref()
            .map(|sequence| {
                sequence
                    .nodes
                    .iter()
                    .filter_map(|node| match &node.node_type {
                        NodeType::TargetHeader(config) | NodeType::TargetGroup(config) => {
                            // An unnamed target is deliberately NOT indexed. The
                            // save-path resolver labels those frames
                            // "untargeted"; inventing a name here (the node's
                            // display label, say) would put a third spelling on
                            // the wire, which is the defect this fixes.
                            if config.target_name.trim().is_empty() {
                                None
                            } else {
                                Some((
                                    node.id.clone(),
                                    (
                                        config.target_name.clone(),
                                        config.ra_hours,
                                        config.dec_degrees,
                                    ),
                                ))
                            }
                        }
                        _ => None,
                    })
                    .collect()
            })
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
        // Shared with the recovery driver (incremented when a cycle completes)
        // and with the node tree, so an instruction can tell "recovery already
        // finished" from "no driver ever engaged". See
        // `ExecutionContext::recovery_generation`.
        let recovery_generation = Arc::new(std::sync::atomic::AtomicU64::new(0));
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
        let recovery_generation_clone = recovery_generation.clone();
        let recovery_driver_generation = recovery_generation.clone();
        let skip_to_next_target_clone = skip_to_next_target.clone();
        let skip_to_node_clone = skip_to_node.clone();
        let resume_notify_clone = resume_notify.clone();
        let exposure_node_metadata = Arc::new(exposure_node_metadata);
        let target_node_metadata = Arc::new(target_node_metadata);
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
                context.recovery_generation = recovery_generation_clone;
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
                // Display name per node id, learned from the one-shot
                // "Executing: <name>" entry message.
                //
                // `current_node_id` is rewritten by EVERY progress update but
                // `current_node_name` was only written on a node's first
                // Running transition, so the two fields drifted apart and
                // together named a node that does not exist. Seen on the live
                // rig: `GET /api/sequencer/status` answered
                // `"currentNodeId":"391bd28d-…"` (the ROOT container) with
                // `"currentNodeName":"Expose 2x2s light"` (a leaf) once the run
                // ended, because the root's own terminal update moved the id and
                // left the name behind. A client that highlights
                // `currentNodeId` on its canvas highlights the wrong node. The
                // pair is identity; keep it atomic.
                let node_names = Arc::new(StdRwLock::new(std::collections::HashMap::<
                    NodeId,
                    String,
                >::new()));
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
                // Integration already credited per FRAME for each node, so the
                // burst's closing one-shot can add only what is left over.
                //
                // Why this exists: integration used to be added in a single lump
                // when an exposure node finished successfully, so a run
                // interrupted part-way through a node recorded ZERO seconds. A
                // real unattended night is one long exposure node per filter, so
                // a crash at 04:00 after six hours of imaging offered the
                // operator a resume dialog reading "0m integration". Measured on
                // 2026-08-10: paused a ten-frame node after three frames and the
                // on-disk checkpoint held `completed_exposures = 3` beside
                // `completed_integration_secs = 0.0`.
                //
                // Crediting per frame instead of removing the one-shot outright,
                // because `exposure_node_metadata` only carries TakeExposure
                // nodes — a producer with no per-frame duration (smart exposure)
                // still needs its whole burst counted at the end.
                let node_integration_credited = Arc::new(StdRwLock::new(
                    std::collections::HashMap::<NodeId, f64>::new(),
                ));
                let exposure_node_metadata = exposure_node_metadata.clone();
                let target_node_metadata = target_node_metadata.clone();
                context.progress_callback = Some(Arc::new(move |update: ProgressUpdate| {
                    let mut prog = progress_clone.write();
                    prog.current_node_id = Some(update.node_id.clone());
                    // Move the name with the id (see `node_names` above). Unknown
                    // until the node's entry message has been seen, in which case
                    // we publish None rather than the PREVIOUS node's name — a
                    // missing name is honest, a stale one is not.
                    prog.current_node_name = node_names.read().get(&update.node_id).cloned();
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
                            node_names
                                .write()
                                .insert(update.node_id.clone(), node_name.clone());
                            prog.current_node_name = Some(node_name.clone());
                            tracing::info!(
                                "[PROGRESS_CB] Emitting NodeStarted: id={}, name={}",
                                update.node_id,
                                node_name
                            );
                            let _ = event_tx_clone.send(ExecutorEvent::NodeStarted {
                                id: update.node_id.clone(),
                                name: node_name,
                            });
                            // Entering a target's subtree IS the target change.
                            // Emitted from the same one-shot entry branch as
                            // NodeStarted so a Loop that re-enters the target
                            // re-announces it, and so the announcement can
                            // never precede the node actually running.
                            if let Some((target_name, ra, dec)) =
                                target_node_metadata.get(&update.node_id)
                            {
                                let _ = event_tx_clone.send(ExecutorEvent::TargetStarted {
                                    name: target_name.clone(),
                                    ra: *ra,
                                    dec: *dec,
                                });
                            }
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
                        //
                        // The per-node FRAME counters are deliberately NOT reset
                        // here: an exposure burst's final update carries both a
                        // terminal status AND `current_frame`/`total_frames` (see
                        // `expose.rs`, which repeats the last frame number to
                        // publish `completed_exposure_secs`). Resetting the
                        // counter first made the frame block below see last=0 and
                        // re-advance 0 -> N for a burst it had already counted
                        // frame-by-frame, so `completed_exposures` counted every
                        // burst TWICE (verified on the rig: a 3-frame burst
                        // emitted frames 1,2,3 and then 1,2,3 again). That figure
                        // is checkpointed, so a resumed run believed it had
                        // already taken twice the frames it had. The reset now
                        // happens after the frame block.
                        let mut started = started_nodes.write();
                        started.remove(&update.node_id);
                        // Only Success closes a target. A target node that
                        // failed, was cancelled or was skipped did not
                        // "complete" it, and `SequencerEvent::TargetCompleted`
                        // is rendered to the operator as "Completed target: X".
                        if update.status == NodeStatus::Success {
                            if let Some((target_name, _, _)) =
                                target_node_metadata.get(&update.node_id)
                            {
                                let _ = event_tx_clone.send(ExecutorEvent::TargetCompleted {
                                    name: target_name.clone(),
                                });
                            }
                        }
                        tracing::debug!(
                            "[PROGRESS_CB] Cleared node {} from started set (status={:?})",
                            update.node_id,
                            update.status
                        );
                    }

                    let node_reached_terminal_status = matches!(
                        update.status,
                        NodeStatus::Success
                            | NodeStatus::Failure
                            | NodeStatus::Cancelled
                            | NodeStatus::Skipped
                    );

                    if let (Some(current), Some(total)) =
                        (update.current_frame, update.total_frames)
                    {
                        let mut exposure_started_event: Option<ExecutorEvent> = None;
                        // One ExposureCompleted per frame that finished. A burst
                        // can advance by more than one frame at a time (smart
                        // exposure reports per BATCH), and Dart adds one frame +
                        // one exposure-duration to the run vitals per event, so
                        // a batch of N must produce N events to be counted.
                        let mut exposure_completed_events: Vec<ExecutorEvent> = Vec::new();
                        let metadata = exposure_node_metadata.get(&update.node_id).cloned();

                        let mut frame_progress = node_frame_progress.write();
                        let mut pending_completion = node_pending_exposure_completion.write();
                        let last = frame_progress.entry(update.node_id.clone()).or_insert(0);
                        if current > *last {
                            let previous = *last;
                            prog.completed_exposures =
                                prog.completed_exposures.saturating_add(current - *last);
                            *last = current;

                            // Credit the frames that just landed, on the same
                            // monotonic sighting that advances the frame counter.
                            // That guard is what makes `completed_exposures`
                            // exactly-once under retries and batched bursts, so
                            // the integration riding on it is exactly-once too.
                            if let Some((duration_secs, _)) = metadata.as_ref() {
                                let credited = f64::from(current - previous) * *duration_secs;
                                prog.completed_integration_secs += credited;
                                *node_integration_credited
                                    .write()
                                    .entry(update.node_id.clone())
                                    .or_insert(0.0) += credited;
                            }

                            if let Some((duration_secs, filter)) = metadata {
                                exposure_started_event = Some(ExecutorEvent::ExposureStarted {
                                    frame: current,
                                    total,
                                    filter,
                                    duration_secs,
                                });
                                // Completion is synthesized from the SAME sighting
                                // that advances the counter, because every producer
                                // reports a frame only AFTER it finished
                                // (`instructions.rs` calls the per-frame callback
                                // right after `completed_exposures += 1`;
                                // smart-exposure emits after `frames_just_taken`).
                                //
                                // This used to wait for a second sighting of the
                                // same frame number (`pending_completion`), which no
                                // producer ever sends: the next per-frame callback
                                // ADVANCES the number, and the one duplicate that
                                // does exist — the burst's final lifecycle update —
                                // carries a terminal status, so the terminal-status
                                // cleanup a few lines above wipes the pending marker
                                // before this block runs. The result was that
                                // ExposureCompleted was NEVER emitted, so the run
                                // vitals reported framesCaptured=0 and
                                // integrationSecs=0.0 for runs that really did
                                // capture and save frames (reproduced on the rig: 3
                                // FITS files written, vitals still zero).
                                //
                                // `completed_exposures` is deliberately left on this
                                // branch: it feeds checkpoint/resume, which must
                                // only ever count frames that actually completed.
                                for frame in (previous + 1)..=current {
                                    exposure_completed_events.push(
                                        ExecutorEvent::ExposureCompleted {
                                            frame,
                                            total,
                                            duration_secs,
                                        },
                                    );
                                }
                            }
                            // No pending marker is recorded any more, so the
                            // duplicate final sighting cannot double-count.
                            pending_completion.remove(&update.node_id);
                        }

                        drop(pending_completion);
                        drop(frame_progress);

                        if let Some(event) = exposure_started_event {
                            let _ = event_tx_clone.send(event);
                        }
                        for event in exposure_completed_events {
                            let _ = event_tx_clone.send(event);
                        }
                    }

                    // Reset the per-node frame counters only AFTER this update's
                    // frame numbers have been accounted for, so a burst's final
                    // (terminal + frame-bearing) update cannot re-advance from
                    // zero. The next loop iteration still starts from a clean
                    // counter, which is what the reset is for.
                    if node_reached_terminal_status {
                        node_frame_progress.write().remove(&update.node_id);
                        node_pending_exposure_completion
                            .write()
                            .remove(&update.node_id);
                    }

                    if let Some(exposure_secs) = update.completed_exposure_secs {
                        // The burst's closing total, minus whatever its frames
                        // already contributed above. For a TakeExposure node
                        // that ran to completion this is zero; for a producer
                        // with no per-frame duration it is the whole burst.
                        // Never negative: a node that reported more per-frame
                        // than its own total must not claw integration back.
                        let already = node_integration_credited
                            .write()
                            .remove(&update.node_id)
                            .unwrap_or(0.0);
                        prog.completed_integration_secs += (exposure_secs - already).max(0.0);
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

                // ParkAndAbort runs inside the trigger monitor while node
                // execution and the command/checkpoint futures are polled in
                // parallel. Keep cancellation-aware peers alive until the
                // safe-state sweep completes; otherwise the outer select!
                // could drop the trigger monitor after node cleanup but before
                // park/close.
                let park_and_abort_in_progress = Arc::new(AtomicBool::new(false));
                let (execution_quiesced_tx, execution_quiesced_rx) = watch::channel(false);
                let (park_and_abort_done_tx, park_and_abort_done_rx) = watch::channel(false);

                let is_paused_cmd = is_paused.clone();
                let skip_to_next_target_cmd = skip_to_next_target.clone();
                // Trust-patch §7: command-handler-side clone for posting
                // SkipToNode requests into the shared slot.
                let skip_to_node_cmd = skip_to_node.clone();
                let resume_notify_cmd = resume_notify.clone();
                // The status API reads the progress snapshot, so every command
                // that changes the executor's state has to stamp it there too.
                let progress_for_commands = progress.clone();
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
                                // `SequencerState` is built from the progress
                                // snapshot (`api/sequencer.rs`,
                                // `From<SequenceProgress>`), NOT from the lock
                                // above. Stamping only the lock is why
                                // `POST /api/sequencer/pause` answered
                                // `{"status":"paused"}` and the very next
                                // `GET /api/sequencer/status` said
                                // `"state":"running"` — reproduced on the Linux
                                // appliance 2026-08-09. A remote operator, or an
                                // unattended rig's watchdog, sees a healthy run
                                // while the node tree is parked.
                                progress_for_commands.write().state = ExecutorState::Paused;
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
                                // Symmetric with Pause above: without this the
                                // snapshot would stay `Paused` forever and a
                                // resumed run would report as paused — swapping
                                // one untruth for its mirror image.
                                progress_for_commands.write().state = ExecutorState::Running;
                                let _ = event_tx
                                    .send(ExecutorEvent::StateChanged(ExecutorState::Running));
                            }
                            ExecutorCommand::Stop => {
                                is_cancelled.store(true, Ordering::Relaxed);
                                *state.write().await = ExecutorState::Stopping;
                                let _ = event_tx
                                    .send(ExecutorEvent::StateChanged(ExecutorState::Stopping));
                                // Keep the command future alive. Breaking here
                                // lets this select! branch win and drops the
                                // node-execution future before its hardware
                                // cancellation cleanup can abort an exposure.
                                // The shared cancellation flag makes execution
                                // finish; that branch owns termination.
                            }
                            ExecutorCommand::Skip => {
                                tracing::info!("Skip requested - advancing to next target");
                                skip_to_next_target_cmd.store(true, Ordering::Relaxed);
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
                                let _ = event_tx.send(skip_to_node_accepted_event(node_id));
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
                                    state.set_observer_location(latitude, longitude);
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
                // ParkAndAbort is driven by the trigger-monitor future while
                // the node tree executes in parallel. The two watch channels
                // form a handshake:
                //
                //   cancel -> node cleanup/abort -> quiesced -> park/close -> done
                //
                // The execution future remains pending after node cleanup while
                // a ParkAndAbort sweep is active. This prevents the outer
                // select! from choosing completed execution and dropping the
                // trigger monitor halfway through the hardware-safe-state work.
                // Subscribed BEFORE the tree runs so every
                // `InstructionFailed` a failing run emits is still in the
                // broadcast buffer when the terminal handler drains it below.
                // A drain (rather than a listener task) is what makes it
                // race-free: the event is sent before `execute()` returns, so
                // it is queued by the time we look.
                let mut instruction_failure_rx = event_tx.subscribe();
                let park_and_abort_for_execution = park_and_abort_in_progress.clone();
                let mut park_and_abort_done_rx = park_and_abort_done_rx;
                let mut park_and_abort_done_for_checkpoint = park_and_abort_done_rx.clone();
                let execution = async {
                    let result = root_node.execute(&mut context).await;
                    let _ = execution_quiesced_tx.send(true);
                    if park_and_abort_for_execution.load(Ordering::Acquire) {
                        let _ = park_and_abort_done_rx.wait_for(|done| *done).await;
                    }
                    result
                };

                let state_clone = state.clone();
                let event_tx_clone2 = event_tx.clone();
                let is_cancelled_clone = is_cancelled.clone();
                let park_and_abort_for_triggers = park_and_abort_in_progress.clone();
                let mut execution_quiesced_for_triggers = execution_quiesced_rx;
                let park_and_abort_done_for_triggers = park_and_abort_done_tx;
                let is_paused_for_triggers = is_paused.clone();
                let skip_to_next_target_for_triggers = skip_to_next_target.clone();
                // The trigger monitor needs the progress snapshot so a
                // trigger-driven pause updates the value
                // `sequencer_get_status()` actually reads (`progress.state`),
                // not only the internal executor state.
                let progress_for_triggers = progress.clone();
                // Set for the duration of a trigger recovery action (meridian
                // flip, dither, autofocus, …) so the run cannot resolve while
                // one is still in flight. Without it the node tree finishing
                // dropped the whole `trigger_monitor` future mid-await,
                // silently orphaning an in-progress flip retry ladder.
                let trigger_action_in_flight = Arc::new(AtomicBool::new(false));
                let trigger_action_in_flight_for_triggers = trigger_action_in_flight.clone();
                let trigger_action_in_flight_for_watchdog = trigger_action_in_flight.clone();
                // One beat per completed monitor iteration. See
                // `trigger_monitor_stall_watchdog`.
                let (heartbeat_tx, heartbeat_rx) = watch::channel(0_u64);
                let event_tx_for_watchdog = event_tx.clone();
                // Latched when a meridian flip failed outright, so the run's
                // terminal verdict is a Failure rather than a silent success.
                let meridian_flip_failed = Arc::new(AtomicBool::new(false));
                let meridian_flip_failed_for_triggers = meridian_flip_failed.clone();
                let progress_for_checkpoint = progress.clone();
                let state_for_checkpoint = state.clone();
                let is_cancelled_for_checkpoint = is_cancelled.clone();
                let trigger_manager_for_checkpoint = trigger_manager.clone();
                let streaming_triggers_enabled = triggers_enabled;
                let park_and_abort_for_checkpoint = park_and_abort_in_progress.clone();
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

                        if is_cancelled_for_checkpoint.load(Ordering::Acquire) {
                            if park_and_abort_for_checkpoint.load(Ordering::Acquire) {
                                let _ = park_and_abort_done_for_checkpoint
                                    .wait_for(|done| *done)
                                    .await;
                            }
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
                                crate::recovery::AttemptOutcome::Unrecoverable { message } => {
                                    tracing::error!(
                                        "[RECOVERY] Cause {:?} is not retryable: {} — ending the \
                                         loop after {} attempt(s) instead of burning the budget",
                                        ctx.cause,
                                        message,
                                        ctx.attempt_count
                                    );
                                    // Take the ordinary give-up path (park, close
                                    // cover/dome, fail) rather than sleeping the
                                    // retry interval for an answer that cannot change.
                                    aborted_by_user = false;
                                    recovered = false;
                                    ctx.last_error = Some(message);
                                    ctx.phase = crate::recovery::RecoveryPhase::GaveUp;
                                    *recovery_driver_current.write() = Some(ctx.clone());
                                    let _ = recovery_driver_event_tx.send(
                                        ExecutorEvent::RecoveryProgress {
                                            context: Box::new(ctx.clone()),
                                        },
                                    );
                                    break;
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

                            // Publish completion BEFORE clearing the pause, so an
                            // instruction that observes the cleared pause can always
                            // also observe the advanced generation (no window where
                            // it sees "not paused" with a stale generation).
                            recovery_driver_generation.fetch_add(1, Ordering::AcqRel);
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

                let trigger_monitor_poll_loop = async {
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
                    let mount_poll_interval =
                        std::time::Duration::from_secs(MOUNT_POLL_INTERVAL_SECS);
                    let mut last_mount_poll_at: Option<std::time::Instant> = None;
                    let mut heartbeat: u64 = 0;

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

                    // The MountTrackingLost / OnTrackingLimitHit baseline
                    // (`mount_tracking_expected`) is armed lazily in the poll block
                    // below — only once the mount is OBSERVED tracking — rather than
                    // assumed here at startup, so a not-yet-tracking mount cannot
                    // self-cancel the sequence (B19). See mount_tracking_poll_verdict.

                    loop {
                        check_interval.tick().await;

                        // Proof of life for the stall watchdog. Beat before the
                        // state gate so a paused run still reports a live monitor.
                        heartbeat = heartbeat.wrapping_add(1);
                        let _ = heartbeat_tx.send(heartbeat);

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
                            match bounded_poll(
                                "safety_is_safe",
                                device_ops_for_triggers.safety_is_safe(None),
                            )
                            .await
                            {
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

                        // One guider poll per tick serves both consumers: the RMS
                        // the GuidingFailed trigger evaluates, and the is_guiding
                        // latch GuideStarLost keys off. They used to be two
                        // separate round-trips to the same driver in the same tick
                        // — and, worse, two contradictory error policies for the
                        // same failure: one swallowed it, the other read it as a
                        // lost star. One poll means one policy, and the fail-closed
                        // one wins (see the guide-star block below).
                        let guide_status = bounded_poll(
                            "guider_get_status",
                            device_ops_for_triggers.guider_get_status(),
                        )
                        .await;
                        let guiding_rms = guide_status.as_ref().ok().map(|status| status.rms_total);

                        // Trust-patch §2: poll humidity from the weather/safety
                        // device on the same cadence as safety_is_safe. The
                        // default `weather_get_humidity` implementation returns
                        // Ok(None) for backends that don't expose humidity —
                        // those silently leave `state.current_humidity` alone
                        // (which is correct: HumidityThreshold can't evaluate
                        // without data).
                        let humidity_result = if should_poll_safety {
                            Some(
                                bounded_poll(
                                    "weather_get_humidity",
                                    device_ops_for_triggers.weather_get_humidity(None),
                                )
                                .await,
                            )
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

                        let should_poll_mount = last_mount_poll_at
                            .map(|last| last.elapsed() >= mount_poll_interval)
                            .unwrap_or(true);

                        if let (Some(mount_id), true) =
                            (&trigger_action_context.mount_id, should_poll_mount)
                        {
                            last_mount_poll_at = Some(std::time::Instant::now());
                            let tracking_result = bounded_poll(
                                "mount_is_tracking",
                                device_ops_for_triggers.mount_is_tracking(mount_id),
                            )
                            .await;
                            let slewing_result = bounded_poll(
                                "mount_is_slewing",
                                device_ops_for_triggers.mount_is_slewing(mount_id),
                            )
                            .await;
                            let parked_result = bounded_poll(
                                "mount_is_parked",
                                device_ops_for_triggers.mount_is_parked(mount_id),
                            )
                            .await;
                            let pier_side_result = bounded_poll(
                                "mount_side_of_pier",
                                device_ops_for_triggers.mount_side_of_pier(mount_id),
                            )
                            .await;
                            let coords_result = bounded_poll(
                                "mount_get_coordinates",
                                device_ops_for_triggers.mount_get_coordinates(mount_id),
                            )
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

                                    // Lazily arm the "tracking expected" baseline on the
                                    // first observed Ok(true) and edge-detect a genuine
                                    // true → false loss against it (B19). `state.mount_is_tracking`
                                    // still holds the PREVIOUS poll's reading here — it is
                                    // updated below, after this check.
                                    let (mount_tracking_expected, tracking_just_lost) =
                                        mount_tracking_poll_verdict(
                                            state.mount_tracking_expected,
                                            *is_tracking,
                                            state.mount_is_tracking,
                                            state.mount_tracking_lost,
                                        );
                                    state.set_mount_tracking_expected(mount_tracking_expected);
                                    if tracking_just_lost {
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
                        //
                        // Polled on the safety cadence rather than every tick: the
                        // optical train's temperature moves on minute timescales and
                        // the TemperatureShift threshold is in whole degrees, so a
                        // 1 Hz probe read bought nothing and cost a driver round-trip
                        // a second.
                        if let (Some(focuser_id), true) =
                            (&trigger_action_context.focuser_id, should_poll_safety)
                        {
                            match bounded_poll(
                                "focuser_get_temperature",
                                device_ops_for_triggers.focuser_get_temperature(focuser_id),
                            )
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

                        // The shutter shares the safety cadence, which is the cadence
                        // every other "is the rig still safe to expose" question is
                        // asked on.
                        if let (Some(dome_id), true) =
                            (&trigger_action_context.dome_id, should_poll_safety)
                        {
                            if let Ok(status) = bounded_poll(
                                "dome_get_shutter_status",
                                device_ops_for_triggers.dome_get_shutter_status(dome_id),
                            )
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
                        // can report low RMS for one cycle before noticing the star is gone),
                        // so the same poll's `is_guiding` gives the trigger a definitive
                        // signal independent of the RMS path above.
                        {
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

                            // Mark the whole action dispatch as in-flight. The
                            // guard clears on drop so the many `return
                            // terminate_with(...)` early exits below cannot
                            // leak the flag. See
                            // `TriggerActionInFlightGuard` for why this
                            // exists: the run used to resolve while a meridian
                            // flip retry ladder was still sleeping, dropping
                            // the trigger-monitor future and orphaning the
                            // recovery mid-flight.
                            let _action_in_flight = TriggerActionInFlightGuard::new(
                                &trigger_action_in_flight_for_triggers,
                            );

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
                                                // The status API is built from the progress snapshot, not from
                                                // this lock. Stamping only the lock is what let a paused run
                                                // keep reporting `running` — see mirror_paused_into_progress.
                                                progress_for_triggers.write().state =
                                                    ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
                                    }
                                }
                                RecoveryAction::ParkAndAbort => {
                                    // Stop node execution BEFORE moving or
                                    // closing hardware. In particular, an
                                    // exposure instruction observes the shared
                                    // cancellation flag, aborts the camera
                                    // integration, and only then lets the
                                    // execution future report quiescence.
                                    park_and_abort_for_triggers.store(true, Ordering::Release);
                                    cancel_and_wait_for_execution(
                                        &is_cancelled_clone,
                                        &mut execution_quiesced_for_triggers,
                                    )
                                    .await;

                                    // Guiding is independent device state, not
                                    // owned by the exposure future. Quiesce it
                                    // explicitly before parking the mount.
                                    if let Err(error) = device_ops_for_triggers.guider_stop().await
                                    {
                                        // An unguided rig has nothing to stop, so
                                        // that is not a failure to report. Emitting
                                        // it raised a CRITICAL "failed to stop
                                        // guiding" toast next to the real abort
                                        // reason on every unguided ParkAndAbort —
                                        // observed live on a weather abort — which
                                        // buries the cause the operator needs.
                                        if crate::device_ops::is_no_guider_configured(&error) {
                                            tracing::debug!(
                                                "ParkAndAbort: no guider to stop ({})",
                                                error
                                            );
                                        } else {
                                            let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "ParkAndAbort: failed to stop guiding before \
                                                     parking: {}",
                                                    error
                                                ),
                                            });
                                        }
                                    }

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

                                    let _ = park_and_abort_done_for_triggers.send(true);
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
                                    // Autofocus drives the camera itself, so it
                                    // must not start on top of a frame the
                                    // capture loop is already exposing. It did:
                                    // the autofocus began its own exposures
                                    // 0.35 s after a 10 s light started, and the
                                    // capture loop's download then failed with
                                    // "No exposure is available to download",
                                    // failing the exposure node and — through
                                    // the sequential parent — the whole run, at
                                    // frame 25 of every run.
                                    claim_camera_for_trigger_action(
                                        &trigger_state_for_actions,
                                        &is_cancelled_clone,
                                        "autofocus",
                                    )
                                    .await;
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
                                            let progress_context =
                                                custom_recovery_context_for_triggers.clone();
                                            let progress_node_id =
                                                format!("trigger:{trigger_id}:autofocus");
                                            // Same synthetic id the progress
                                            // closure below publishes under, so
                                            // the terminal event names the node
                                            // the sweep reported against.
                                            let completed_node_id = progress_node_id.clone();
                                            let total_steps = af_config
                                                .steps_out
                                                .saturating_mul(2)
                                                .saturating_add(1);
                                            let progress_fn =
                                                move |progress: f64, detail_str: String| {
                                                    let (step, hfr) =
                                                        parse_autofocus_detail(&detail_str);
                                                    progress_context.send_progress(
                                                        ProgressUpdate::instruction_progress(
                                                            progress_node_id.clone(),
                                                            "Autofocus",
                                                            progress,
                                                            ProgressDetail::Autofocus {
                                                                step: step.unwrap_or(0),
                                                                total_steps,
                                                                current_hfr: hfr,
                                                            },
                                                        ),
                                                    );
                                                };
                                            let af_result = crate::instructions::execute_autofocus(
                                                &af_config,
                                                &af_ctx,
                                                Some(&progress_fn),
                                            )
                                            .await;

                                            // Hand the camera back the moment the sweep
                                            // is done — success or failure — so the
                                            // capture loop resumes on its next frame
                                            // instead of waiting out the claim's
                                            // ten-minute expiry.
                                            trigger_state_for_actions
                                                .write()
                                                .await
                                                .clear_camera_busy();

                                            // Publish the sweep's verdict.
                                            //
                                            // A trigger-fired refocus streamed
                                            // Autofocus progress under the
                                            // synthetic node id above and then
                                            // simply stopped: subscribers saw a
                                            // sweep begin and never learned
                                            // whether it worked, so a night of
                                            // periodic refocusing left the run
                                            // record showing none at all. The
                                            // status is the sweep's own, so a
                                            // cancelled sweep reports cancelled
                                            // rather than being flattened to a
                                            // failure.
                                            let _ = event_tx_clone2.send(
                                                ExecutorEvent::NodeCompleted {
                                                    id: completed_node_id,
                                                    status: af_result.status,
                                                },
                                            );

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
                                                // A failed autofocus is not automatically a
                                                // ruined night. Judge the frames it would keep
                                                // producing, not the fact that the sweep failed:
                                                // slightly-soft frames stack and deconvolve
                                                // fine, donuts are wasted disk. The reference
                                                // must be read BEFORE `reset_baseline_hfr`
                                                // overwrites it with the degraded value.
                                                let verdict = {
                                                    let ts = trigger_state_for_actions.read().await;
                                                    autofocus_failure_verdict(
                                                        ts.baseline_hfr,
                                                        ts.current_hfr,
                                                        af_config.failure_hfr_tolerance_ratio,
                                                    )
                                                };

                                                // Reset the HFR baseline to the current degraded
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

                                                if let AutofocusOutcome::KeepImaging {
                                                    current_hfr,
                                                    limit,
                                                } = verdict
                                                {
                                                    let message = format!(
                                                        "Autofocus failed after {} attempt(s), but HFR {:.2} is \
                                                         within the {:.2} tolerance limit — continuing to image. \
                                                         Frames will be slightly soft; focus will be retried on \
                                                         the next interval.",
                                                        af_config.number_of_attempts.max(1),
                                                        current_hfr,
                                                        limit
                                                    );
                                                    tracing::warn!("{}", message);
                                                    let _ = event_tx_clone2
                                                        .send(ExecutorEvent::Error { message });
                                                    fired_triggers.push((trigger_id, action));
                                                    continue;
                                                }

                                                if af_config.failure_action
                                                    == crate::AutofocusFailureAction::AbortAndPark
                                                {
                                                    let message = format!(
                                                        "Autofocus failed after {} attempt(s) and {} — ending the \
                                                         sequence and parking. Further frames would not be worth \
                                                         keeping.",
                                                        af_config.number_of_attempts.max(1),
                                                        verdict.describe()
                                                    );
                                                    tracing::error!("{}", message);
                                                    let _ = event_tx_clone2
                                                        .send(ExecutorEvent::Error { message });

                                                    let safe_state =
                                                        crate::device_ops::park_and_close_safe_state(
                                                            &device_ops_for_triggers,
                                                            trigger_action_context
                                                                .mount_id
                                                                .as_deref(),
                                                            trigger_action_context
                                                                .cover_calibrator_id
                                                                .as_deref(),
                                                            trigger_action_context
                                                                .dome_id
                                                                .as_deref(),
                                                            1,
                                                            2.0,
                                                        )
                                                        .await;
                                                    if let Some(park) = &safe_state.park {
                                                        if !park.success {
                                                            let _ = event_tx_clone2.send(
                                                                ExecutorEvent::Error {
                                                                    message: format!(
                                                                        "Autofocus abort: parking the mount failed \
                                                                         ({}). The mount may still be tracking — \
                                                                         check it.",
                                                                        park.last_error
                                                                            .clone()
                                                                            .unwrap_or_else(|| {
                                                                                "no detail".into()
                                                                            })
                                                                    ),
                                                                },
                                                            );
                                                        }
                                                    }

                                                    fired_triggers.push((trigger_id, action));
                                                    return terminate_with(
                                                        &is_cancelled_clone,
                                                        fired_triggers,
                                                        "AutofocusFailureAction::AbortAndPark",
                                                    );
                                                }

                                                is_paused_for_triggers
                                                    .store(true, Ordering::Relaxed);
                                                *state_clone.write().await = ExecutorState::Paused;
                                                // The status API is built from the progress snapshot, not from
                                                // this lock. Stamping only the lock is what let a paused run
                                                // keep reporting `running` — see mirror_paused_into_progress.
                                                progress_for_triggers.write().state =
                                                    ExecutorState::Paused;
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
                                            // No camera and/or no focuser: the autofocus
                                            // action is not merely failing, it is
                                            // IMPOSSIBLE, and nothing an operator does at
                                            // the keyboard tonight will make it possible.
                                            //
                                            // This arm used to pause the executor
                                            // indefinitely. Reproduced on the live rig: a
                                            // two-node sequence (change filter -> expose)
                                            // on a rig with the camera + wheel connected
                                            // and no focuser hung on the FILTER node for
                                            // as long as it was left alone. The filter
                                            // change invalidated the autofocus state, the
                                            // always-armed HFR trigger force-fired one
                                            // second later, this arm latched
                                            // `is_paused_for_triggers`, and the next node
                                            // boundary blocked in
                                            // `node::context` ("Execution paused at
                                            // boundary, waiting for resume...").
                                            // `/api/sequencer/status` reported `running`
                                            // and `progress 0.0` the whole time: no
                                            // frames, no terminal event, no way for an
                                            // unattended run to ever notice.
                                            //
                                            // A run cannot be held hostage by a recovery
                                            // it can never perform. Report the real
                                            // missing device, drop the stale-focus latch
                                            // so the trigger stops re-forcing on every
                                            // evaluation tick, and let imaging continue.
                                            // `start()` disarms these triggers up front
                                            // when there is no focuser; this arm is the
                                            // backstop for a device that disappears
                                            // mid-run.
                                            let missing = match (
                                                trigger_action_context.camera_id.as_ref(),
                                                trigger_action_context.focuser_id.as_ref(),
                                            ) {
                                                (None, None) => "no camera and no focuser are",
                                                (None, Some(_)) => "no camera is",
                                                _ => "no focuser is",
                                            };
                                            tracing::warn!(
                                                "Autofocus trigger '{}' fired but {} configured; \
                                                 skipping the refocus and continuing the run",
                                                trigger_name,
                                                missing
                                            );
                                            {
                                                let mut ts =
                                                    trigger_state_for_actions.write().await;
                                                ts.clear_autofocus_invalidation();
                                            }
                                            let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                                message: format!(
                                                    "Trigger '{trigger_name}' asked for an autofocus but {missing} \
                                                     configured for this run. The refocus was skipped and imaging \
                                                     continues — focus is not being corrected automatically."
                                                ),
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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

                                    let (target_name, target_ra, target_dec, current_filter) = {
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
                                            ts.current_filter.clone(),
                                        )
                                    };
                                    let autofocus_config = runtime_config.read().autofocus.clone();

                                    if let Some(flip_ctx) = build_trigger_flip_context(
                                        &trigger_action_context,
                                        TriggerFlipTarget {
                                            name: target_name.clone(),
                                            ra_hours: target_ra,
                                            dec_degrees: target_dec,
                                        },
                                        Some(is_cancelled_clone.clone()),
                                        Some(trigger_state_for_actions.clone()),
                                        autofocus_config,
                                        current_filter,
                                    ) {
                                        let mut flip_executor =
                                        crate::meridian_flip_executor::MeridianFlipExecutor::new(
                                            config.clone(),
                                            device_ops_for_triggers.clone(),
                                        )
                                        // The executor emits the
                                        // MeridianFlipOutcome verdict itself, so
                                        // it needs the run's event stream.
                                        .with_executor_event_tx(event_tx_clone2.clone());

                                        let flip_result = flip_executor.execute(&flip_ctx).await;
                                        // Snapshot the attempt count before the
                                        // match consumes the result — a flip that
                                        // only succeeded on retry #3 is DEGRADED
                                        // and the operator must be told.
                                        let flip_attempts = flip_executor.attempts_made();
                                        match flip_result {
                                        crate::meridian_flip_executor::FlipResult::Success {
                                            new_pier_side,
                                            duration_secs,
                                        } => {
                                            tracing::info!(
                                                "[MERIDIAN] Flip completed successfully: new pier side {:?}, took {:.1}s",
                                                new_pier_side, duration_secs
                                            );

                                            // The verdict that reaches the Dart run
                                            // vitals is emitted by
                                            // MeridianFlipExecutor::execute, so the
                                            // node-driven path reports flips too.
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

                                            // Latch the failure so the run's
                                            // terminal verdict cannot be a silent
                                            // `completed` (mirrors how
                                            // `recovery_gave_up` coerces the
                                            // result to Failure).
                                            meridian_flip_failed_for_triggers
                                                .store(true, Ordering::Release);

                                            match action_taken {
                                                crate::FlipFailureAction::PauseAndAlert => {
                                                    // "Pause & Alert" must be
                                                    // OBSERVABLE. Setting only the
                                                    // executor state left
                                                    // `sequencer_get_status()` —
                                                    // which reads `progress.state`
                                                    // — reporting "running" long
                                                    // after the flip had failed and
                                                    // the run had been paused.
                                                    // Mirror the operator-pause
                                                    // path: state + progress +
                                                    // a reason banner.
                                                    let pause_message = format!(
                                                        "Meridian flip for '{}' FAILED after {} \
                                                         attempt(s): {}. Sequence paused — the \
                                                         mount may be on the wrong side of the \
                                                         pier; verify framing before resuming.",
                                                        target_name, flip_attempts, error
                                                    );
                                                    is_paused_for_triggers
                                                        .store(true, Ordering::Relaxed);
                                                    *state_clone.write().await = ExecutorState::Paused;
                                                    // The status API is built from the progress snapshot, not from
                                                    // this lock. Stamping only the lock is what let a paused run
                                                    // keep reporting `running` — see mirror_paused_into_progress.
                                                    progress_for_triggers.write().state = ExecutorState::Paused;
                                                    {
                                                        let mut prog =
                                                            progress_for_triggers.write();
                                                        prog.state = ExecutorState::Paused;
                                                        prog.message = Some(pause_message);
                                                    }
                                                    // No separate `Error` event:
                                                    // the Critical-severity
                                                    // `MeridianFlipOutcome` emitted
                                                    // above IS the verdict, and
                                                    // emitting both would record the
                                                    // same failure twice in the run's
                                                    // errorMessages.
                                                    let _ = event_tx_clone2.send(
                                                        ExecutorEvent::StateChanged(
                                                            ExecutorState::Paused,
                                                        ),
                                                    );
                                                }
                                                crate::FlipFailureAction::AbortAndPark => {
                                                    // The flip itself failed, so the mount may be
                                                    // anywhere between sides. Park before we exit
                                                    // to avoid leaving it tracking into a limit
                                                    // — matches the ParkAndAbort policy above.
                                                    // First cancel and drain
                                                    // the concurrently-running
                                                    // node tree so a camera
                                                    // integration cannot remain
                                                    // active while we park.
                                                    park_and_abort_for_triggers
                                                        .store(true, Ordering::Release);
                                                    cancel_and_wait_for_execution(
                                                        &is_cancelled_clone,
                                                        &mut execution_quiesced_for_triggers,
                                                    )
                                                    .await;
                                                    if let Err(error) =
                                                        device_ops_for_triggers.guider_stop().await
                                                    {
                                                        let _ = event_tx_clone2.send(
                                                            ExecutorEvent::Error {
                                                                message: format!(
                                                                    "FlipFailure AbortAndPark: \
                                                                     failed to stop guiding before \
                                                                     parking: {}",
                                                                    error
                                                                ),
                                                            },
                                                        );
                                                    }
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

                                                    let _ =
                                                        park_and_abort_done_for_triggers.send(true);
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
                                            // The verdict itself comes from
                                            // MeridianFlipExecutor::execute.
                                            tracing::warn!("[MERIDIAN] Flip aborted: {}", reason);
                                        }
                                    }
                                    } else {
                                        // A flip trigger that fires and then
                                        // cannot run is a safety event, not a
                                        // log line: the mount is past the
                                        // meridian and nothing is going to move
                                        // it. Surface it so the run records
                                        // WHY no flip happened.
                                        let message = format!(
                                            "Meridian flip trigger fired for '{}' but the flip \
                                             could not be executed: mount not connected or \
                                             target coordinates not set. The mount is past the \
                                             meridian and was NOT flipped.",
                                            target_name
                                        );
                                        tracing::error!("[MERIDIAN] {}", message);
                                        meridian_flip_failed_for_triggers
                                            .store(true, Ordering::Release);
                                        let _ =
                                            event_tx_clone2.send(ExecutorEvent::Error { message });
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
                                    match classify_dither_result(
                                        dither_result.status,
                                        dither_result.message.as_deref(),
                                    ) {
                                        DitherTriggerOutcome::Performed => {
                                            let mut ts = trigger_state_for_actions.write().await;
                                            ts.mark_dither_performed();
                                        }
                                        DitherTriggerOutcome::SkippedNoGuider => {
                                            // An unguided rig cannot dither, and that is not a
                                            // failure — the same skippable-no-op treatment the
                                            // dither NODE, ParkAndAbort and the meridian
                                            // pause/resume already give this marker.
                                            //
                                            // Marking it performed matters as much as the log
                                            // level: the interval only resets here, so leaving
                                            // it unmarked kept the trigger permanently due and
                                            // it re-fired on EVERY exposure. Measured on an
                                            // unguided dark run, 12 frames produced 12
                                            // identical WARNs for a condition that cannot
                                            // change mid-run.
                                            let mut ts = trigger_state_for_actions.write().await;
                                            ts.mark_dither_performed();
                                            tracing::debug!(
                                                "[DITHER] Trigger '{}' skipped - no guider configured",
                                                trigger_name
                                            );
                                        }
                                        DitherTriggerOutcome::Failed => {
                                            tracing::warn!(
                                                "[DITHER] Trigger-initiated dither failed: {:?}",
                                                dither_result.message
                                            );
                                        }
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                            // The status API is built from the progress snapshot, not from
                                            // this lock. Stamping only the lock is what let a paused run
                                            // keep reporting `running` — see mirror_paused_into_progress.
                                            progress_for_triggers.write().state =
                                                ExecutorState::Paused;
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
                                            // The status API is built from the progress snapshot, not from
                                            // this lock. Stamping only the lock is what let a paused run
                                            // keep reporting `running` — see mirror_paused_into_progress.
                                            progress_for_triggers.write().state =
                                                ExecutorState::Paused;
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
                                            // The status API is built from the progress snapshot, not from
                                            // this lock. Stamping only the lock is what let a paused run
                                            // keep reporting `running` — see mirror_paused_into_progress.
                                            progress_for_triggers.write().state =
                                                ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                        // The status API is built from the progress snapshot, not from
                                        // this lock. Stamping only the lock is what let a paused run
                                        // keep reporting `running` — see mirror_paused_into_progress.
                                        progress_for_triggers.write().state = ExecutorState::Paused;
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
                                            // The status API is built from the progress snapshot, not from
                                            // this lock. Stamping only the lock is what let a paused run
                                            // keep reporting `running` — see mirror_paused_into_progress.
                                            progress_for_triggers.write().state =
                                                ExecutorState::Paused;
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

                // A hung poll is indistinguishable from a healthy monitor to the
                // join below, so the watchdog turns "stalled" into "exited" — the
                // one shape the fail-closed handler downstream can act on.
                let trigger_monitor = async {
                    tokio::pin!(trigger_monitor_poll_loop);
                    tokio::select! {
                        fired = &mut trigger_monitor_poll_loop => fired,
                        () = trigger_monitor_stall_watchdog(
                            heartbeat_rx,
                            trigger_action_in_flight_for_watchdog,
                            std::time::Duration::from_secs(TRIGGER_MONITOR_STALL_TIMEOUT_SECS),
                        ) => {
                            let message = format!(
                                "Safety monitoring stalled: the trigger monitor has not \
                                 completed a poll cycle in {TRIGGER_MONITOR_STALL_TIMEOUT_SECS}s, \
                                 so weather, altitude, drift, tracking-loss, dome and meridian \
                                 protection are no longer being enforced. A device driver is \
                                 most likely not returning."
                            );
                            tracing::error!("{}", message);
                            let _ = event_tx_for_watchdog.send(ExecutorEvent::Error { message });
                            Vec::new()
                        }
                    }
                };

                // Fail-closed safety: an unattended sequence depends on the trigger
                // monitor to enforce weather / altitude / drift limits. If it exits
                // for any reason other than normal cancellation, continuing to
                // expose would leave the rig unmonitored — so we cancel everything.
                //
                // Every non-execution branch first cancels and then DRAINS the
                // execution future. Dropping it here used to bypass the active
                // instruction's cancellation branch, allowing a camera exposure
                // to keep integrating after Stop had already been reported as
                // confirmed.
                tokio::pin!(execution);
                // Pinned (not consumed by value) so the quiesce loop below can
                // keep driving the monitor after this select! resolves. See
                // `TriggerActionInFlightGuard`.
                tokio::pin!(trigger_monitor);
                let result = tokio::select! {
                    _ = command_handler => {
                        is_cancelled.store(true, Ordering::Release);
                        (&mut execution).await
                    },
                    result = &mut execution => result,
                    _ = streaming_checkpoint_task => {
                        is_cancelled.store(true, Ordering::Release);
                        (&mut execution).await
                    },
                    // Recovery Mode — the driver task only ever
                    // exits when the recovery_request_tx side is closed
                    // (sequence ending), so a clean exit is a Cancelled
                    // outcome. The driver intentionally holds itself open
                    // by recv-looping; we keep it in the select! so a
                    // panic here surfaces in the same way as any other
                    // task panic (caught by the supervisor catch_unwind).
                    _ = recovery_driver => {
                        is_cancelled.store(true, Ordering::Release);
                        (&mut execution).await
                    },
                    _triggers = &mut trigger_monitor => {
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
                            let _ = (&mut execution).await;
                            NodeStatus::Failure
                        } else {
                            (&mut execution).await
                        }
                    },
                };

                // A trigger recovery action may still be running: the node tree
                // finishing does NOT mean the rig is settled. The canonical
                // case is a meridian flip whose retry ladder is mid-sleep —
                // dropping `trigger_monitor` here abandoned the flip with the
                // mount parked between pier sides and let the run report a
                // clean `completed`. Keep driving the monitor until the action
                // resolves so its outcome (success / degraded / failed, plus
                // any AbortAndPark safing) is actually applied.
                //
                // On a cancel/stop the flip polls the same `is_cancelled` token
                // and unwinds within a couple of hundred milliseconds, so this
                // wait does not delay an operator Stop.
                if trigger_action_in_flight.load(Ordering::Acquire) {
                    tracing::warn!(
                        "Node tree finished while a trigger recovery action is still \
                         running; waiting up to {}s for it to complete before ending the run",
                        TRIGGER_ACTION_QUIESCE_MAX_SECS
                    );
                    let deadline = tokio::time::Instant::now()
                        + std::time::Duration::from_secs(TRIGGER_ACTION_QUIESCE_MAX_SECS);
                    while trigger_action_in_flight.load(Ordering::Acquire) {
                        tokio::select! {
                            _ = &mut trigger_monitor => break,
                            _ = tokio::time::sleep_until(deadline) => {
                                let message = format!(
                                    "A trigger recovery action was still running {}s after the \
                                     sequence finished and was abandoned. The mount may not be \
                                     in the state the sequence expected — verify it manually.",
                                    TRIGGER_ACTION_QUIESCE_MAX_SECS
                                );
                                tracing::error!("{}", message);
                                let _ = event_tx.send(ExecutorEvent::Error { message });
                                break;
                            }
                            _ = tokio::time::sleep(std::time::Duration::from_millis(100)) => {}
                        }
                    }
                    tracing::info!("In-flight trigger recovery action quiesced; ending run");
                }

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

                // Same reasoning for a meridian flip that failed outright. The
                // mount did not end up where the sequence assumed, so every
                // frame taken after the failed flip is suspect. Reporting
                // `completed` there is the silent-data-loss case this whole
                // path exists to prevent — a flip that exhausted its retries
                // makes the RUN a failure even if the node tree walked to the
                // end. A flip that merely retried and then succeeded is NOT
                // coerced; it is recorded as a degraded-but-successful flip.
                let result = if meridian_flip_failed.load(Ordering::Acquire)
                    && !matches!(result, NodeStatus::Failure)
                {
                    tracing::error!(
                        "Sequence finished with {:?} but a meridian flip FAILED during the \
                         run; recording the run as a failure",
                        result
                    );
                    NodeStatus::Failure
                } else {
                    result
                };

                // A tree that walked to the end but contains instructions the
                // executor structurally cannot reach did NOT do what the
                // sequence says it does. Reporting `completed` there is the
                // same silent-data-loss class as the failed-flip coercion
                // above: the operator sees a green Completed badge over a run
                // that skipped most of its work.
                let mut unreachable_failure_reason: Option<String> = None;
                let result = if !unreachable_instruction_names.is_empty()
                    && matches!(result, NodeStatus::Success | NodeStatus::Skipped)
                {
                    let message = unreachable_instructions_message(&unreachable_instruction_names);
                    tracing::error!(
                        "Sequence finished with {:?} but never executed part of its tree; \
                         recording the run as a failure. {}",
                        result,
                        message
                    );
                    let _ = event_tx.send(ExecutorEvent::Error {
                        message: message.clone(),
                    });
                    unreachable_failure_reason = Some(message);
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
                        // "Sequence failed" told the operator nothing: the run
                        // that died on the daylight gate carried the real
                        // reason in its log while the toast, the Session
                        // Report and the persisted `errorMessages` all showed
                        // the placeholder. Prefer the structural reason, then
                        // the last instruction that actually reported one.
                        let error = unreachable_failure_reason
                            .or_else(|| last_instruction_failure(&mut instruction_failure_rx))
                            .unwrap_or_else(|| "Sequence failed".to_string());
                        let _ = event_tx.send(ExecutorEvent::SequenceFailed {
                            error: error.clone(),
                        });
                        emit_lifecycle_decision(
                            &decision_tx_for_lifecycle,
                            &active_run_id_for_decisions,
                            &decision_logging_enabled_for_emits,
                            "failed",
                            serde_json::json!({
                                "elapsed_secs": start_time.elapsed().as_secs_f64(),
                                "error": error,
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
            let _ = run_completion_tx.send(());
        });

        Ok(())
    }
}
