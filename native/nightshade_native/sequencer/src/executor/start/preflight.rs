//! Start-time preflight: recycle a terminal executor, then refuse the run
//! outright for the conditions a sequence cannot recover from once it is
//! under way — no device handle, no save path, a device the sequence needs
//! that is not configured, and a missing plate solver.

use super::*;

/// What preflight hands the run supervisor once every check has passed.
pub(super) struct PreflightOutcome {
    /// The device handle every instruction in the run routes through.
    pub device_ops: SharedDeviceOps,
    /// Instructions the tree can never reach, reported at the end of the run
    /// so the outcome names the mis-shaped sequence.
    pub unreachable_instruction_names: Vec<String>,
}

impl SequenceExecutor {
    pub(super) async fn preflight_start(&mut self) -> Result<PreflightOutcome, String> {
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

        Ok(PreflightOutcome {
            device_ops,
            unreachable_instruction_names,
        })
    }
}
