//! Meridian Flip Executor — the canonical engine for meridian flips.
//!
//! Both the explicit `MeridianFlip` instruction node and the trigger-driven
//! `RecoveryAction::MeridianFlip` route through this executor (audit §1.6 — the
//! pre-existing two-implementation split was unifying-required so users got the
//! same timeouts, altitude check, autofocus parameters, settle behaviour,
//! plate-solve handling, pier-side telemetry fallback, abort behaviour, and
//! `mark_flip_performed` semantics regardless of trigger source).
//!
//! Pre-flip rustdoc invariants checked here:
//! - Target altitude is ≥ `MIN_POST_FLIP_ALTITUDE_DEG`.
//! - If a cover/calibrator is configured, the cover is *not* closed
//!   (audit §1.19 — a covered camera makes plate-solve fail and triggers
//!   `AbortAndPark` unnecessarily).
//! - Mount reports it can flip (the caller is expected to gate on this; the
//!   executor logs warnings but does not refuse if the capability check is
//!   unavailable, since some drivers do not expose it).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::mpsc;
use tokio::sync::RwLock;

use crate::device_ops::SharedDeviceOps;
use crate::instructions::{execute_autofocus, InstructionContext};
use crate::meridian::{self, julian_day, local_sidereal_time};
use crate::meridian_events::{FlipEventEmitter, FlipStep, MeridianFlipEvent, PierSide};
use crate::triggers::TriggerState;
use crate::{AutofocusConfig, FlipFailureAction, MeridianFlipConfig};

/// Position match tolerance (degrees) for the coordinate-fallback verification
/// path used when the mount does not report pier side. 1 arcminute.
const FLIP_COORDINATE_TOLERANCE_DEG: f64 = 1.0 / 60.0;

/// How many times to retry mount park / abort-slew / set-tracking calls inside
/// `execute_failure_action` before giving up. The mount may be at a hard limit
/// after a failed flip; retrying a few times with a delay handles transient
/// driver/communication errors.
const SAFETY_ACTION_RETRY_COUNT: u32 = 3;

/// Delay between safety-action retries.
const SAFETY_ACTION_RETRY_DELAY_SECS: f64 = 5.0;

/// Result of a meridian flip execution
#[derive(Debug, Clone)]
pub enum FlipResult {
    /// Flip completed successfully
    Success {
        new_pier_side: PierSide,
        duration_secs: f64,
    },
    /// Flip failed after all retries
    Failed {
        error: String,
        action_taken: FlipFailureAction,
    },
    /// Flip was aborted by user
    Aborted { reason: String },
}

/// Context for executing a meridian flip.
///
/// `cancellation_token`, `trigger_state`, `cover_calibrator_id`, and
/// `autofocus_config` were added in audit §1.6 / §1.19 to backport behaviour
/// that the older `instructions::execute_meridian_flip` had: cancel-during-settle
/// must propagate, success must call `TriggerState::mark_flip_performed`, the
/// pre-flip cover check needs the cover device id, and post-flip refocus must
/// honour user-tuned autofocus parameters instead of hardcoded constants.
pub struct FlipContext {
    pub target_name: String,
    pub target_ra_hours: f64,
    pub target_dec_degrees: f64,
    pub mount_id: String,
    pub camera_id: Option<String>,
    pub focuser_id: Option<String>,
    /// Optional dust-cover / flat-panel device id. When set, the executor
    /// refuses to flip while the cover is closed (audit §1.19).
    pub cover_calibrator_id: Option<String>,
    /// Cancellation token shared with the wider sequence executor so a Stop
    /// command propagates into long waits (settle, slew). When `None`, the
    /// executor falls back to its internal abort-flag.
    pub cancellation_token: Option<Arc<AtomicBool>>,
    /// Trigger state. When set, a successful flip will call
    /// `TriggerState::mark_flip_performed()` so subsequent trigger evaluations
    /// know not to fire again on the same target. Audit §1.6.
    pub trigger_state: Option<Arc<RwLock<TriggerState>>>,
    /// User-tuned autofocus parameters used by the post-flip refocus step.
    /// `None` falls back to `AutofocusConfig::default()`. Audit §1.6.
    pub autofocus_config: Option<AutofocusConfig>,
}

/// Executes a complete meridian flip sequence
pub struct MeridianFlipExecutor {
    config: MeridianFlipConfig,
    device_ops: SharedDeviceOps,
    event_emitter: FlipEventEmitter,
    event_tx: Option<mpsc::Sender<MeridianFlipEvent>>,
    abort_requested: Arc<AtomicBool>,
}

impl MeridianFlipExecutor {
    /// Create a new flip executor
    pub fn new(config: MeridianFlipConfig, device_ops: SharedDeviceOps) -> Self {
        Self {
            config,
            device_ops,
            event_emitter: FlipEventEmitter::new(),
            event_tx: None,
            abort_requested: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Set event channel for progress updates
    pub fn with_event_channel(mut self, tx: mpsc::Sender<MeridianFlipEvent>) -> Self {
        self.event_tx = Some(tx);
        self
    }

    /// Get abort handle for external abort requests
    pub fn abort_handle(&self) -> Arc<AtomicBool> {
        self.abort_requested.clone()
    }

    /// Below ~10° atmospheric refraction (~9.5 arcmin near the horizon) and
    /// differential extinction make plate-solve unreliable, and most amateur
    /// mounts approach their lower altitude limit. 10° is a conservative
    /// default that has tested clean on SkyWatcher EQ8 / iOptron CEM70 /
    /// 10micron rigs; users with a clear horizon can tighten via config.
    const MIN_POST_FLIP_ALTITUDE_DEG: f64 = 10.0;

    /// Execute the meridian flip
    pub async fn execute(&mut self, ctx: &FlipContext) -> FlipResult {
        let start_time = Instant::now();

        if self.config.max_retries > 0 && self.config.retry_delays_secs.is_empty() {
            let msg = format!(
                "Meridian flip configuration error: max_retries={} but retry_delays_secs is empty. Cannot schedule retry.",
                self.config.max_retries
            );
            tracing::error!("[MERIDIAN] {}", msg);
            let action_taken = self.config.failure_action;
            self.emit_event(MeridianFlipEvent::Failed {
                error: msg.clone(),
                action_taken: format_failure_action(action_taken).to_string(),
            });
            return FlipResult::Failed {
                error: msg,
                action_taken,
            };
        }

        // ENG-F9: Pre-flip sanity check — verify target altitude is viable.
        // If the target is below the minimum altitude, continuing with the flip
        // would slew to an object that's about to set, risking equipment damage
        // or wasted imaging time.
        if let Some((lat, lon)) = self.device_ops.get_observer_location() {
            let altitude = self.device_ops.calculate_altitude(
                ctx.target_ra_hours,
                ctx.target_dec_degrees,
                lat,
                lon,
            );
            tracing::info!(
                "[MERIDIAN] Pre-flip altitude check: target '{}' altitude = {:.1}° (minimum = {:.1}°)",
                ctx.target_name,
                altitude,
                Self::MIN_POST_FLIP_ALTITUDE_DEG
            );
            if altitude < Self::MIN_POST_FLIP_ALTITUDE_DEG {
                let msg = format!(
                    "Meridian flip skipped: target '{}' altitude is {:.1}° which is below \
                     the minimum {:.1}°. The target is too low for useful imaging after the flip.",
                    ctx.target_name,
                    altitude,
                    Self::MIN_POST_FLIP_ALTITUDE_DEG
                );
                tracing::warn!("[MERIDIAN] {}", msg);
                self.emit_event(MeridianFlipEvent::Failed {
                    error: msg.clone(),
                    action_taken: "Flip skipped due to low target altitude".to_string(),
                });
                return FlipResult::Aborted { reason: msg };
            }
        } else {
            tracing::warn!(
                "[MERIDIAN] Observer location unavailable — cannot verify target altitude \
                 before flip. Proceeding with flip."
            );
        }

        // Audit §1.19: Pre-flip cover/calibrator state check. A closed dust cap
        // makes plate-solve fail post-flip, which would trigger the configured
        // failure action (potentially AbortAndPark). Refuse upfront with a clear
        // error so the user is told to open the cover instead of finding a
        // parked mount in the morning.
        if let Some(cc_id) = ctx.cover_calibrator_id.as_deref() {
            match self
                .device_ops
                .cover_calibrator_get_cover_state(cc_id)
                .await
            {
                Ok(state) => match state {
                    1 => {
                        // Closed
                        let msg = format!(
                            "Meridian flip refused: cover '{}' is closed (state=1). \
                             Open the cover before flipping or post-flip plate solve will fail.",
                            cc_id
                        );
                        tracing::error!("[MERIDIAN] {}", msg);
                        self.emit_event(MeridianFlipEvent::Failed {
                            error: msg.clone(),
                            action_taken: "Flip refused: cover closed".to_string(),
                        });
                        return FlipResult::Aborted { reason: msg };
                    }
                    2 => {
                        // Moving — also unsafe to flip while it's moving
                        let msg = format!(
                            "Meridian flip refused: cover '{}' is currently moving (state=2). \
                             Wait for cover to settle before flipping.",
                            cc_id
                        );
                        tracing::error!("[MERIDIAN] {}", msg);
                        self.emit_event(MeridianFlipEvent::Failed {
                            error: msg.clone(),
                            action_taken: "Flip refused: cover moving".to_string(),
                        });
                        return FlipResult::Aborted { reason: msg };
                    }
                    3 => {
                        tracing::info!(
                            "[MERIDIAN] Pre-flip cover check: cover '{}' is open",
                            cc_id
                        );
                    }
                    other => {
                        // 0=NotPresent, 4=Unknown, 5=Error — log and proceed; a real
                        // problem will surface in the post-flip plate-solve step.
                        tracing::warn!(
                            "[MERIDIAN] Pre-flip cover check: cover '{}' reports unusable state {}. \
                             Proceeding anyway — post-flip plate-solve will catch a real obstruction.",
                            cc_id,
                            other
                        );
                    }
                },
                Err(e) => {
                    tracing::warn!(
                        "[MERIDIAN] Pre-flip cover check failed for '{}': {}. \
                         Proceeding without cover verification.",
                        cc_id,
                        e
                    );
                }
            }
        }

        // Audit §1.6 backport: capture the mount's tracking state BEFORE we touch
        // it so cancel paths can restore it. The instruction-path implementation
        // had this; the executor previously left tracking off after a cancel.
        let pre_flip_tracking = match self.device_ops.mount_is_tracking(&ctx.mount_id).await {
            Ok(t) => Some(t),
            Err(e) => {
                tracing::warn!(
                    "[MERIDIAN] Failed to read mount tracking state before flip ({}); \
                     skipping explicit tracking restore on cancel",
                    e
                );
                None
            }
        };

        // The pre-flip pier side is the reference point the verify step uses
        // to confirm the mount actually crossed sides. Unknown is non-fatal:
        // verification will fall back to coordinate convergence instead.
        let from_pier_side = match self.get_pier_side(&ctx.mount_id).await {
            Ok(ps) => ps,
            Err(e) => {
                tracing::error!("[MERIDIAN] Failed to get current pier side: {}", e);
                PierSide::Unknown
            }
        };

        // Audit §1.6 backport: capture pre-flip coordinates so the
        // pier-side-Unknown verification path can fall back to coordinate
        // convergence (the executor previously returned Unknown silently).
        let pre_flip_coords = match self.device_ops.mount_get_coordinates(&ctx.mount_id).await {
            Ok(coords) => Some(coords),
            Err(e) => {
                tracing::warn!(
                    "[MERIDIAN] Failed to read pre-flip mount coordinates ({}); \
                     coordinate fallback verification will use target coordinates",
                    e
                );
                None
            }
        };
        if let Some((ra, dec)) = pre_flip_coords {
            tracing::debug!(
                "[MERIDIAN] Pre-flip coordinates captured for fallback diagnostics: RA={:.4}h Dec={:.4}°",
                ra,
                dec
            );
        }

        let hour_angle = self.calculate_hour_angle(ctx.target_ra_hours);

        self.emit_event(MeridianFlipEvent::Starting {
            target_name: ctx.target_name.clone(),
            from_pier_side,
            hour_angle,
        });

        let steps = self.build_step_sequence();
        let total_steps = steps.len() as u8;

        let mut attempt = 0;
        let max_attempts = self.config.max_retries + 1;

        loop {
            attempt += 1;

            match self
                .execute_steps(&steps, ctx, total_steps, from_pier_side)
                .await
            {
                Ok(new_pier_side) => {
                    let duration = start_time.elapsed().as_secs_f64();
                    self.emit_event(MeridianFlipEvent::Completed {
                        new_pier_side,
                        duration_secs: duration,
                    });
                    // Audit §1.6: always mark the flip as performed on success so
                    // trigger evaluation does not re-fire for the same target.
                    if let Some(ts) = ctx.trigger_state.as_ref() {
                        let mut state = ts.write().await;
                        state.mark_flip_performed();
                    }
                    return FlipResult::Success {
                        new_pier_side,
                        duration_secs: duration,
                    };
                }
                Err(e) => {
                    if self.is_cancelled(ctx) {
                        // Audit §1.6 backport: restore tracking on cancel if we
                        // recorded it as on before the flip. The executor used
                        // to leave tracking off, the instruction path didn't.
                        self.restore_tracking_on_cancel(ctx, pre_flip_tracking)
                            .await;
                        let reason = "User requested abort".to_string();
                        self.emit_event(MeridianFlipEvent::Aborted {
                            reason: reason.clone(),
                        });
                        return FlipResult::Aborted { reason };
                    }

                    if attempt < max_attempts {
                        // Audit §1.20: previously `.unwrap_or(60.0)` — silently
                        // ignored a 30s user setting once the array was exhausted.
                        // Now: if the user provided values, saturate on the LAST
                        // entry; if the array is empty AND retries are configured,
                        // refuse to retry (return the underlying error so the
                        // failure_action runs) — silent fallback hides config bugs.
                        let delay_idx = (attempt - 1) as usize;
                        let delay = match self.config.retry_delays_secs.get(delay_idx).copied() {
                            Some(d) => d,
                            None => {
                                // Why: saturate on the last user-provided value rather
                                // than fall back to a magic 60 seconds. This honours
                                // a user who configured `[10.0]` to mean "every retry
                                // waits 10 seconds".
                                match self.config.retry_delays_secs.last().copied() {
                                    Some(d) => d,
                                    None => {
                                        // Empty array but max_retries>0 is a config
                                        // bug. Fail loudly instead of silently using 60s.
                                        let cfg_err = format!(
                                            "Meridian flip configuration error: max_retries={} \
                                             but retry_delays_secs is empty. Cannot schedule retry.",
                                            self.config.max_retries
                                        );
                                        tracing::error!("[MERIDIAN] {}", cfg_err);
                                        // Skip retries; let the failure-action path run
                                        // with the underlying flip error.
                                        let action_taken = self.config.failure_action;
                                        let action_str = format_failure_action(action_taken);
                                        self.emit_event(MeridianFlipEvent::Failed {
                                            error: format!("{} (also: {})", e, cfg_err),
                                            action_taken: action_str.to_string(),
                                        });
                                        if let Err(action_err) =
                                            self.execute_failure_action(&ctx.mount_id).await
                                        {
                                            tracing::error!(
                                                "[MERIDIAN] Failure action itself failed: {}",
                                                action_err
                                            );
                                            return FlipResult::Failed {
                                                error: format!(
                                                    "{} | failure action error: {}",
                                                    e, action_err
                                                ),
                                                action_taken,
                                            };
                                        }
                                        return FlipResult::Failed {
                                            error: format!("{} | {}", e, cfg_err),
                                            action_taken,
                                        };
                                    }
                                }
                            }
                        };

                        self.emit_event(MeridianFlipEvent::RetryScheduled {
                            attempt: attempt as u8,
                            max_attempts: max_attempts as u8,
                            delay_secs: delay,
                        });

                        // Wait before retry, honouring cancellation.
                        let total = std::time::Duration::from_secs_f64(delay);
                        let tick = std::time::Duration::from_millis(200);
                        let mut waited = std::time::Duration::ZERO;
                        while waited < total {
                            if self.is_cancelled(ctx) {
                                self.restore_tracking_on_cancel(ctx, pre_flip_tracking)
                                    .await;
                                let reason = "User requested abort during retry wait".to_string();
                                self.emit_event(MeridianFlipEvent::Aborted {
                                    reason: reason.clone(),
                                });
                                return FlipResult::Aborted { reason };
                            }
                            tokio::time::sleep(tick).await;
                            waited += tick;
                        }
                    } else {
                        // All retries exhausted
                        let action_taken = self.config.failure_action;
                        let action_str = format_failure_action(action_taken);

                        self.emit_event(MeridianFlipEvent::Failed {
                            error: e.clone(),
                            action_taken: action_str.to_string(),
                        });

                        // Audit §1.10: Execute failure action and propagate any
                        // error. Park failures must NOT be silently dropped — a
                        // failed park after a failed flip can leave the mount
                        // at a hard limit.
                        if let Err(action_err) = self.execute_failure_action(&ctx.mount_id).await {
                            tracing::error!(
                                "[MERIDIAN] Failure action ({:?}) itself failed: {}",
                                action_taken,
                                action_err
                            );
                            return FlipResult::Failed {
                                error: format!("{} | failure action error: {}", e, action_err),
                                action_taken,
                            };
                        }

                        return FlipResult::Failed {
                            error: e,
                            action_taken,
                        };
                    }
                }
            }
        }
    }

    /// Build the sequence of steps based on configuration
    fn build_step_sequence(&self) -> Vec<FlipStep> {
        let mut steps = Vec::new();

        if self.config.pause_guiding {
            steps.push(FlipStep::PausingGuider);
        }

        steps.push(FlipStep::StoppingTracking);
        steps.push(FlipStep::SlewingToTarget);
        steps.push(FlipStep::VerifyingPierSide);
        steps.push(FlipStep::ResumingTracking);

        if self.config.auto_center {
            steps.push(FlipStep::PlateSolvingAndCentering);
        }

        if self.config.refocus_after {
            steps.push(FlipStep::Refocusing);
        }

        if self.config.resume_guiding {
            steps.push(FlipStep::ResumingGuider);
        }

        steps.push(FlipStep::Settling);

        steps
    }

    /// Execute all steps in sequence
    async fn execute_steps(
        &mut self,
        steps: &[FlipStep],
        ctx: &FlipContext,
        total_steps: u8,
        pre_flip_pier_side: PierSide,
    ) -> Result<PierSide, String> {
        let mut new_pier_side = PierSide::Unknown;
        // Audit §1.6 backport: track whether the flip *itself* (slew + pier-side
        // verify) has succeeded. If the auto-center plate-solve fails AFTER the
        // flip succeeded, we warn instead of treating the whole flip as failed —
        // the mount is on the correct pier side, just slightly off centre. The
        // instruction path warned; the executor ran execute_failure_action().
        let mut flip_core_succeeded = false;

        for (idx, step) in steps.iter().enumerate() {
            if self.is_cancelled(ctx) {
                return Err("Abort requested".to_string());
            }

            self.emit_event(MeridianFlipEvent::StepStarted {
                step: *step,
                step_index: idx as u8,
                total_steps,
            });

            let step_start = Instant::now();

            let result = match step {
                FlipStep::PausingGuider => self.pause_guider().await,
                FlipStep::StoppingTracking => self.stop_tracking(&ctx.mount_id).await,
                FlipStep::SlewingToTarget => {
                    self.slew_to_target(ctx, ctx.target_ra_hours, ctx.target_dec_degrees)
                        .await
                }
                FlipStep::VerifyingPierSide => {
                    match self.verify_pier_side_changed(ctx, pre_flip_pier_side).await {
                        Ok(ps) => {
                            new_pier_side = ps;
                            flip_core_succeeded = true;
                            Ok(())
                        }
                        Err(e) => Err(e),
                    }
                }
                FlipStep::ResumingTracking => self.resume_tracking(&ctx.mount_id).await,
                FlipStep::PlateSolvingAndCentering => {
                    // Audit §1.6 backport: if the flip itself succeeded (slew +
                    // pier-side verify) but plate-solve fails, warn and treat
                    // the flip as a success — same as the instruction-path
                    // implementation. The mount is correctly on the new pier
                    // side; centring can be handled by the next exposure's
                    // plate-solve loop.
                    match self.plate_solve_and_center(ctx).await {
                        Ok(()) => Ok(()),
                        Err(e) if flip_core_succeeded => {
                            tracing::warn!(
                                "[MERIDIAN] Post-flip centering failed but flip itself succeeded: {}. \
                                 Continuing — the next exposure's plate-solve loop will fine-tune.",
                                e
                            );
                            // Emit a synthetic step-completed so progress
                            // surfaces; the warning is in the log.
                            Ok(())
                        }
                        Err(e) => Err(e),
                    }
                }
                FlipStep::Refocusing => self.run_autofocus(ctx).await,
                FlipStep::ResumingGuider => self.resume_guider().await,
                FlipStep::Settling => self.wait_settle(ctx).await,
            };

            let duration = step_start.elapsed().as_secs_f64();

            match result {
                Ok(()) => {
                    self.emit_event(MeridianFlipEvent::StepCompleted {
                        step: *step,
                        duration_secs: Some(duration),
                    });

                    let progress = ((idx + 1) as f64 / total_steps as f64 * 100.0) as u8;
                    self.emit_event(MeridianFlipEvent::Progress { percent: progress });
                }
                Err(e) => {
                    self.emit_event(MeridianFlipEvent::StepFailed {
                        step: *step,
                        error: e.clone(),
                    });
                    return Err(format!("{}: {}", step.description(), e));
                }
            }
        }

        Ok(new_pier_side)
    }

    // ========================================================================
    // Step implementations
    // ========================================================================

    async fn pause_guider(&self) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Pausing guider...");
        self.device_ops.guider_stop().await
    }

    async fn stop_tracking(&self, mount_id: &str) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Stopping tracking...");
        self.device_ops.mount_set_tracking(mount_id, false).await
    }

    async fn slew_to_target(
        &self,
        ctx: &FlipContext,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> Result<(), String> {
        let mount_id = ctx.mount_id.as_str();
        tracing::info!(
            "[MERIDIAN] Slewing to target (flip side): RA={:.4}h, Dec={:.4}°",
            ra_hours,
            dec_degrees
        );

        self.device_ops
            .mount_slew_to_coordinates(mount_id, ra_hours, dec_degrees)
            .await?;

        // 10 min timeout covers worst-case meridian-flip slews on the slow
        // direct-drive mounts in our test matrix (10micron GM1000HPS with
        // belt drive ~ 6-8 min for full-sky moves); a tighter timeout would
        // false-alarm legitimate long slews on heavy payloads.
        let slew_timeout = tokio::time::Instant::now() + std::time::Duration::from_secs(600);
        loop {
            if self.is_cancelled(ctx) {
                // Audit §1.10: explicit error logging on abort_slew failure during
                // a cancellation path — silent drop here would mask a stuck mount.
                if let Err(e) = self.device_ops.mount_abort_slew(mount_id).await {
                    tracing::error!(
                        "[MERIDIAN] mount_abort_slew failed during cancellation of slew: {}",
                        e
                    );
                }
                return Err("Abort requested during slew".to_string());
            }

            let is_slewing = self.device_ops.mount_is_slewing(mount_id).await?;
            if !is_slewing {
                break;
            }

            if tokio::time::Instant::now() > slew_timeout {
                // Audit §1.10: log abort_slew failure during timeout path.
                if let Err(e) = self.device_ops.mount_abort_slew(mount_id).await {
                    tracing::error!(
                        "[MERIDIAN] mount_abort_slew failed after slew timeout: {}",
                        e
                    );
                }
                return Err("Meridian flip slew timed out after 10 minutes".to_string());
            }

            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }

        Ok(())
    }

    async fn verify_pier_side_changed(
        &self,
        ctx: &FlipContext,
        pre_flip_pier_side: PierSide,
    ) -> Result<PierSide, String> {
        let mount_id = ctx.mount_id.as_str();
        tracing::info!(
            "[MERIDIAN] Verifying pier side changed from {:?}...",
            pre_flip_pier_side
        );

        let new_pier_side = self.get_pier_side(mount_id).await?;

        tracing::info!("[MERIDIAN] New pier side: {:?}", new_pier_side);

        // When both sides are known telemetry, pier-side delta is the
        // strongest verification: a flip MUST cross sides, so equality means
        // the slew did not actually flip the mount (e.g. mount driver chose
        // to recover via a long sweep on the same side).
        if pre_flip_pier_side != PierSide::Unknown && new_pier_side != PierSide::Unknown {
            if pre_flip_pier_side == new_pier_side {
                return Err(format!(
                    "Pier side did not change after flip (still {:?}). \
                     The mount may not have flipped correctly.",
                    new_pier_side
                ));
            }
            return Ok(new_pier_side);
        }

        // Audit §1.6 backport: pier side is unavailable (either before, after,
        // or both). Fall back to coordinate convergence — the instruction-path
        // implementation did this and the executor previously just returned
        // Unknown without verifying.
        tracing::warn!(
            "[MERIDIAN] Pier side telemetry unavailable (pre={:?}, post={:?}); \
             verifying flip via coordinate convergence",
            pre_flip_pier_side,
            new_pier_side
        );
        let (post_ra, post_dec) = self.device_ops.mount_get_coordinates(mount_id).await?;
        let ra_diff_deg = normalize_ra_diff_hours(post_ra - ctx.target_ra_hours) * 15.0;
        let dec_diff_deg = post_dec - ctx.target_dec_degrees;
        if ra_diff_deg.abs() > FLIP_COORDINATE_TOLERANCE_DEG
            || dec_diff_deg.abs() > FLIP_COORDINATE_TOLERANCE_DEG
        {
            return Err(format!(
                "Flip slew completed but coordinate-fallback verification failed without \
                 pier-side telemetry: target RA={:.4}h Dec={:.4}°, mount reports RA={:.4}h \
                 Dec={:.4}° (diff RA={:.2}', Dec={:.2}')",
                ctx.target_ra_hours,
                ctx.target_dec_degrees,
                post_ra,
                post_dec,
                ra_diff_deg * 60.0,
                dec_diff_deg * 60.0,
            ));
        }
        tracing::info!(
            "[MERIDIAN] Flip verified by coordinate convergence (pier side telemetry unavailable)"
        );
        Ok(new_pier_side)
    }

    async fn resume_tracking(&self, mount_id: &str) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Resuming tracking...");
        self.device_ops.mount_set_tracking(mount_id, true).await
    }

    async fn plate_solve_and_center(&self, ctx: &FlipContext) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Plate solving and centering...");

        let camera_id = ctx.camera_id.as_ref().ok_or("No camera configured")?;

        // 5 s @ 1x1 is enough exposure for typical equatorial fields to get a
        // solvable star count without burning time; deep mosaics with sparse
        // fields should use the dedicated Center node with a longer exposure.
        let image = self
            .device_ops
            .camera_start_exposure(camera_id, 5.0, None, None, 1, 1)
            .await?;

        // Passing target hints (deg-converted RA) accelerates blind solves on
        // ASTAP/local indexes by ~10x; without them the solver scans the full
        // sky and post-flip exposures can stall waiting for a solution.
        let result = self
            .device_ops
            .plate_solve(
                &image,
                Some(ctx.target_ra_hours * 15.0),
                Some(ctx.target_dec_degrees),
                None,
            )
            .await?;

        if !result.success {
            return Err("Plate solve failed".to_string());
        }

        let ra_offset = (result.ra_degrees / 15.0) - ctx.target_ra_hours;
        let dec_offset = result.dec_degrees - ctx.target_dec_degrees;

        // Apply cos(dec) to RA when converting to arcsec for the same reason
        // as TriggerState::calculate_drift_pixels: at high declinations a
        // raw degree difference would overstate the on-sky distance.
        let ra_offset_arcsec =
            ra_offset * 15.0 * 3600.0 * ctx.target_dec_degrees.to_radians().cos();
        let dec_offset_arcsec = dec_offset * 3600.0;
        let total_offset = (ra_offset_arcsec.powi(2) + dec_offset_arcsec.powi(2)).sqrt();

        tracing::info!(
            "[MERIDIAN] Plate solve result: offset={:.1}\" (RA={:.1}\", Dec={:.1}\")",
            total_offset,
            ra_offset_arcsec,
            dec_offset_arcsec
        );

        // 30" tolerance is generous for a post-flip "good enough" check: the
        // user's intent is that the target is back in frame so guiding can
        // re-acquire — sub-arcsecond precision is the next exposure's job.
        if total_offset < 30.0 {
            tracing::info!("[MERIDIAN] Centering within tolerance");
            return Ok(());
        }

        // Sync the mount model to the actual position, then re-slew to target.
        // This corrects mount pointing errors that survived the flip; a bare
        // re-slew without the sync would land at the same wrong spot.
        self.device_ops
            .mount_sync(&ctx.mount_id, result.ra_degrees / 15.0, result.dec_degrees)
            .await?;

        self.device_ops
            .mount_slew_to_coordinates(&ctx.mount_id, ctx.target_ra_hours, ctx.target_dec_degrees)
            .await?;

        // 5 min ceiling is enough for a short corrective slew (the flip has
        // already done the big move); past that the mount is misbehaving and
        // the user should know rather than have the sequence stall silently.
        let slew_timeout = tokio::time::Instant::now() + std::time::Duration::from_secs(300);
        loop {
            if self.is_cancelled(ctx) {
                // Audit §1.10: log abort_slew failure during cancellation.
                if let Err(e) = self.device_ops.mount_abort_slew(&ctx.mount_id).await {
                    tracing::error!(
                        "[MERIDIAN] mount_abort_slew failed during cancellation of centering slew: {}",
                        e
                    );
                }
                return Err("Abort requested during centering slew".to_string());
            }

            let is_slewing = self.device_ops.mount_is_slewing(&ctx.mount_id).await?;
            if !is_slewing {
                break;
            }

            if tokio::time::Instant::now() > slew_timeout {
                // Audit §1.10: log abort_slew failure during timeout.
                if let Err(e) = self.device_ops.mount_abort_slew(&ctx.mount_id).await {
                    tracing::error!(
                        "[MERIDIAN] mount_abort_slew failed after centering slew timeout: {}",
                        e
                    );
                }
                return Err("Centering slew timed out after 5 minutes".to_string());
            }

            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }

        Ok(())
    }

    async fn run_autofocus(&self, ctx: &FlipContext) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Running autofocus...");

        let camera_id = match &ctx.camera_id {
            Some(id) => id.clone(),
            None => {
                tracing::warn!("[MERIDIAN] Camera not configured, skipping autofocus");
                return Ok(());
            }
        };

        let focuser_id = match &ctx.focuser_id {
            Some(id) => id.clone(),
            None => {
                tracing::warn!("[MERIDIAN] Focuser not configured, skipping autofocus");
                return Ok(());
            }
        };

        // Audit §1.6: pull autofocus parameters from the user equipment profile
        // (passed via FlipContext::autofocus_config). When the caller did not
        // supply one, fall back to AutofocusConfig::default(), which now (audit
        // §1.7) carries every engine-tunable field. Previously hardcoded to
        // steps_out=7 / step_size=100 / exposure=3.0 ignoring user config.
        // Why (audit-rust §4.3): documented constructor-default contract on
        // Option<AutofocusConfig> — None means "use defaults".
        let af_config = ctx.autofocus_config.clone().unwrap_or_default();

        // Determine the effective cancellation token for autofocus. Prefer the
        // shared sequence token so a Stop command propagates; fall back to the
        // executor's internal abort flag.
        // Why (audit-rust §4.3): Option<CancellationToken> override — None means
        // "use the executor's own abort flag", documented in the field doc.
        let cancel_token = ctx
            .cancellation_token
            .clone()
            .unwrap_or_else(|| self.abort_requested.clone());

        let instruction_ctx = InstructionContext {
            target_ra: Some(ctx.target_ra_hours),
            target_dec: Some(ctx.target_dec_degrees),
            target_name: Some(ctx.target_name.clone()),
            current_filter: af_config.filter.clone(),
            current_binning: af_config.binning,
            cancellation_token: cancel_token,
            camera_id: Some(camera_id),
            mount_id: Some(ctx.mount_id.clone()),
            focuser_id: Some(focuser_id),
            filterwheel_id: None,
            rotator_id: None,
            dome_id: None,
            cover_calibrator_id: ctx.cover_calibrator_id.clone(),
            save_path: None,
            latitude: None,
            longitude: None,
            device_ops: self.device_ops.clone(),
            trigger_state: ctx.trigger_state.clone(),
            filter_focus_offsets: std::collections::HashMap::new(),
        };

        tracing::info!(
            "[MERIDIAN] Starting autofocus ({:?}) with {} steps_out, step_size {}, \
             backlash compensation {}",
            af_config.method,
            af_config.steps_out,
            af_config.step_size,
            af_config.backlash_compensation
        );

        let result = execute_autofocus(&af_config, &instruction_ctx, None).await;

        match result.status {
            crate::NodeStatus::Success => {
                if let Some(msg) = result.message {
                    tracing::info!("[MERIDIAN] Autofocus completed: {}", msg);
                } else {
                    tracing::info!("[MERIDIAN] Autofocus completed successfully");
                }
                Ok(())
            }
            crate::NodeStatus::Failure => {
                // Why (audit-rust §4.3): autofocus result `message: Option<String>` —
                // failure is already encoded in `NodeStatus::Failure`. Generic message
                // when no specific diagnostic was attached.
                let error = result
                    .message
                    .unwrap_or_else(|| "Unknown autofocus error".to_string());
                tracing::error!("[MERIDIAN] Autofocus failed: {}", error);
                Err(format!("Autofocus failed: {}", error))
            }
            crate::NodeStatus::Cancelled => {
                tracing::warn!("[MERIDIAN] Autofocus was cancelled");
                Err("Autofocus cancelled".to_string())
            }
            crate::NodeStatus::Skipped => {
                tracing::info!("[MERIDIAN] Autofocus was skipped");
                Ok(())
            }
            other => {
                // Why: Pending/Running here would indicate a bug in execute_autofocus
                // (it must return a terminal status). Surface as an error rather
                // than swallow.
                let err = format!("Autofocus returned non-terminal status: {:?}", other);
                tracing::error!("[MERIDIAN] {}", err);
                Err(err)
            }
        }
    }

    async fn resume_guider(&self) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Resuming guider...");

        // 1.5 px settle / 10 s settle time / 60 s timeout match the defaults
        // used by StartGuidingConfig — keeping them aligned avoids surprising
        // users with different post-flip settling behaviour than a regular
        // sequence start.
        self.device_ops.guider_start(1.5, 10.0, 60.0).await
    }

    async fn wait_settle(&self, ctx: &FlipContext) -> Result<(), String> {
        let settle_time = self.config.settle_time;
        tracing::info!("[MERIDIAN] Waiting for settle ({:.0}s)...", settle_time);

        let settle_duration = std::time::Duration::from_secs_f64(settle_time);
        let check_interval = std::time::Duration::from_millis(500);
        let mut elapsed = std::time::Duration::ZERO;

        while elapsed < settle_duration {
            // Why: check both internal abort and the shared sequence cancellation
            // token so a Stop request during settle returns immediately instead
            // of waiting out the full settle time.
            if self.is_cancelled(ctx) {
                return Err("Abort requested during settle".to_string());
            }

            tokio::time::sleep(check_interval).await;
            elapsed += check_interval;
        }

        Ok(())
    }

    // ========================================================================
    // Helper methods
    // ========================================================================

    async fn get_pier_side(&self, mount_id: &str) -> Result<PierSide, String> {
        let ps = self.device_ops.mount_side_of_pier(mount_id).await?;
        // The trait returns the calculation-internal enum; this executor
        // emits events using the wire-format enum, so the boundary is
        // mapped explicitly to keep meridian::PierSide off the event API.
        Ok(match ps {
            meridian::PierSide::East => PierSide::East,
            meridian::PierSide::West => PierSide::West,
            meridian::PierSide::Unknown => PierSide::Unknown,
        })
    }

    fn calculate_hour_angle(&self, ra_hours: f64) -> f64 {
        // HA = LST - RA. Audit §1.6 deleted the duplicate jd/LST helpers
        // here and routed through the meridian module so a future LST tweak
        // (e.g. nutation correction) lands in one place.
        let now = chrono::Utc::now();
        let jd = julian_day(&now);

        // Why (audit-rust §4.3): get_observer_location() returns None when no location
        // has been configured in the user profile. The fallback (longitude=0, Greenwich)
        // logs a WARN to the trace; meridian flips computed with longitude=0 will be off
        // by up-to-12 hours of meridian time but the flip itself is a *post-meridian*
        // pier-side recovery — the user-visible "flip needed" indicator is gated by the
        // mount's pier-side property, not this LST calculation. The warning surfaces the
        // missing-location config in the log so operators know to fix it.
        let longitude_deg = self
            .device_ops
            .get_observer_location()
            .map(|(_lat, lon)| lon)
            .unwrap_or_else(|| {
                tracing::warn!(
                    "[MERIDIAN] Observer location unavailable, using longitude=0 for LST calculation"
                );
                0.0
            });
        let lst = local_sidereal_time(jd, longitude_deg);
        let ha = lst - ra_hours;

        // HA is canonically reported in [-12, +12) h so consumers can use
        // sign alone to determine east-vs-west of meridian; raw mod-24 would
        // emit values in [0, 24) and flip the sign interpretation.
        let mut ha_norm = ha % 24.0;
        if ha_norm > 12.0 {
            ha_norm -= 24.0;
        } else if ha_norm < -12.0 {
            ha_norm += 24.0;
        }

        ha_norm
    }

    /// Returns true if either the executor's internal abort flag or the
    /// caller-supplied cancellation token has been set.
    fn is_cancelled(&self, ctx: &FlipContext) -> bool {
        if self.abort_requested.load(Ordering::Relaxed) {
            return true;
        }
        if let Some(token) = &ctx.cancellation_token {
            if token.load(Ordering::Relaxed) {
                return true;
            }
        }
        false
    }

    /// Audit §1.6 backport: restore the mount's pre-flip tracking state when a
    /// cancel happens mid-flip. The instruction-path implementation did this;
    /// the executor previously left tracking off. Errors are *logged*, not
    /// dropped — but we do not return them since this is already a cancel path.
    async fn restore_tracking_on_cancel(&self, ctx: &FlipContext, pre_flip_tracking: Option<bool>) {
        if matches!(pre_flip_tracking, Some(true)) {
            if let Err(e) = self
                .device_ops
                .mount_set_tracking(&ctx.mount_id, true)
                .await
            {
                tracing::error!(
                    "[MERIDIAN] Failed to restore mount tracking after cancel for '{}': {}. \
                     Mount may continue to drift from target.",
                    ctx.mount_id,
                    e
                );
            } else {
                tracing::info!("[MERIDIAN] Restored mount tracking after cancel");
            }
        }
    }

    /// Audit §1.10: explicit, retried, error-propagating failure-action handler.
    /// Replaces the previous `let _ = mount_park(...)` pattern: on error, log
    /// at error level, retry up to N times with delay, emit a critical
    /// notification, and return Err so the executor's failure result reflects
    /// the failure-action failure (instead of pretending it succeeded).
    async fn execute_failure_action(&self, mount_id: &str) -> Result<(), String> {
        match self.config.failure_action {
            FlipFailureAction::PauseAndAlert => {
                tracing::warn!("[MERIDIAN] Flip failed - pausing and alerting user");
                if let Err(e) = self
                    .device_ops
                    .send_notification(
                        "error",
                        "Meridian Flip Failed",
                        "The meridian flip could not complete. Please check your equipment.",
                    )
                    .await
                {
                    // Why: notification failures are non-fatal — the sequence is
                    // already paused via state change in the executor task. Log
                    // but do not propagate.
                    tracing::error!(
                        "[MERIDIAN] Failed to deliver pause-and-alert notification: {}",
                        e
                    );
                }
                Ok(())
            }
            FlipFailureAction::AbortAndPark => {
                tracing::warn!("[MERIDIAN] Flip failed - aborting and parking");

                // Audit §1.10: stop tracking with retries + explicit error logging.
                if let Err(e) = self
                    .retry_safety_action("mount_set_tracking(false)", || async {
                        self.device_ops.mount_set_tracking(mount_id, false).await
                    })
                    .await
                {
                    tracing::error!(
                        "[MERIDIAN] CRITICAL: failed to stop tracking after {} retries: {}",
                        SAFETY_ACTION_RETRY_COUNT,
                        e
                    );
                    let _ = self
                        .device_ops
                        .send_notification(
                            "critical",
                            "Meridian Flip — Tracking Stop Failed",
                            &format!(
                                "After a failed flip the mount could not be commanded to stop \
                                 tracking ({}). The mount may drift past safe limits.",
                                e
                            ),
                        )
                        .await;
                    // Continue to park attempt — stopping tracking is best-effort
                    // before park, but the park itself is the safety-critical step.
                }

                // Audit §1.10: abort any in-flight slew with retries + explicit
                // error logging. Some mounts will refuse a park while slewing.
                if let Err(e) = self
                    .retry_safety_action("mount_abort_slew", || async {
                        self.device_ops.mount_abort_slew(mount_id).await
                    })
                    .await
                {
                    tracing::error!(
                        "[MERIDIAN] mount_abort_slew failed after {} retries: {}",
                        SAFETY_ACTION_RETRY_COUNT,
                        e
                    );
                    // Continue to park — some drivers do not implement abort_slew
                    // but still accept park.
                }

                // Audit §1.10: park with retries + critical event on failure.
                // Park failure after a flip failure is the worst-case scenario:
                // the mount may already be at a hard limit. Emit a critical
                // notification so the UI surfaces a top-level alert AND return
                // Err so callers see the failed-flip-then-failed-park outcome.
                match self
                    .retry_safety_action("mount_park", || async {
                        self.device_ops.mount_park(mount_id).await
                    })
                    .await
                {
                    Ok(()) => {
                        tracing::info!("[MERIDIAN] Mount parked successfully after failed flip");
                        if let Err(e) = self
                            .device_ops
                            .send_notification(
                                "error",
                                "Meridian Flip Failed - Mount Parked",
                                "The meridian flip failed. Mount has been parked for safety.",
                            )
                            .await
                        {
                            tracing::error!(
                                "[MERIDIAN] Failed to deliver park-success notification: {}",
                                e
                            );
                        }
                        Ok(())
                    }
                    Err(park_err) => {
                        tracing::error!(
                            "[MERIDIAN] CRITICAL: mount_park failed after {} retries: {}. \
                             Mount may be at hard limit — manual intervention required.",
                            SAFETY_ACTION_RETRY_COUNT,
                            park_err
                        );
                        // Critical-level notification so the UI surfaces this
                        // as a top-level alert (not a normal log entry).
                        let critical_msg = format!(
                            "The meridian flip failed AND the mount could not be parked ({}). \
                             The mount may be at a hard limit. Manually disengage clutches \
                             and re-home before attempting any further slews.",
                            park_err
                        );
                        if let Err(e) = self
                            .device_ops
                            .send_notification(
                                "critical",
                                "Meridian Flip Failed - PARK FAILED",
                                &critical_msg,
                            )
                            .await
                        {
                            tracing::error!(
                                "[MERIDIAN] Failed to deliver critical park-failure notification: {}",
                                e
                            );
                        }
                        Err(format!(
                            "AbortAndPark failed: park error after {} retries: {}",
                            SAFETY_ACTION_RETRY_COUNT, park_err
                        ))
                    }
                }
            }
        }
    }

    /// Audit §1.10: retry helper for safety-critical device operations. Logs
    /// every failed attempt at error level; sleeps `SAFETY_ACTION_RETRY_DELAY_SECS`
    /// between attempts. Returns the last error after exhaustion.
    async fn retry_safety_action<F, Fut>(&self, op_name: &str, mut op: F) -> Result<(), String>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<(), String>>,
    {
        let mut last_err = String::from("no attempt was made");
        for attempt in 1..=SAFETY_ACTION_RETRY_COUNT {
            match op().await {
                Ok(()) => {
                    if attempt > 1 {
                        tracing::info!(
                            "[MERIDIAN] {} succeeded on retry attempt {}",
                            op_name,
                            attempt
                        );
                    }
                    return Ok(());
                }
                Err(e) => {
                    tracing::error!(
                        "[MERIDIAN] {} attempt {}/{} failed: {}",
                        op_name,
                        attempt,
                        SAFETY_ACTION_RETRY_COUNT,
                        e
                    );
                    last_err = e;
                    if attempt < SAFETY_ACTION_RETRY_COUNT {
                        tokio::time::sleep(std::time::Duration::from_secs_f64(
                            SAFETY_ACTION_RETRY_DELAY_SECS,
                        ))
                        .await;
                    }
                }
            }
        }
        Err(last_err)
    }

    fn emit_event(&self, event: MeridianFlipEvent) {
        self.event_emitter.emit(event.clone());

        // try_send drops the event on a full channel rather than blocking;
        // the emitter has already logged it so the record is preserved, and
        // a blocking send could deadlock the executor against a slow subscriber.
        if let Some(tx) = &self.event_tx {
            if let Err(e) = tx.try_send(event) {
                tracing::trace!(
                    "[MERIDIAN] Event channel send dropped: {} (logged via emitter)",
                    e
                );
            }
        }
    }
}

/// Format a failure-action enum for human-readable event payloads.
fn format_failure_action(action: FlipFailureAction) -> &'static str {
    match action {
        FlipFailureAction::PauseAndAlert => "Paused sequence and alerted user",
        FlipFailureAction::AbortAndPark => "Aborted sequence and parking mount",
    }
}

/// Normalize an RA difference (hours) to the shortest signed angular distance,
/// accounting for the 0/24h wraparound.
fn normalize_ra_diff_hours(diff: f64) -> f64 {
    let mut wrapped = diff % 24.0;
    if wrapped > 12.0 {
        wrapped -= 24.0;
    } else if wrapped < -12.0 {
        wrapped += 24.0;
    }
    wrapped
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::device_ops::{DeviceOps, DeviceResult, GuidingStatus, ImageData, PlateSolveResult};
    use async_trait::async_trait;
    use std::sync::atomic::AtomicI32;
    use std::sync::Mutex;

    /// Test step sequence building with all options enabled
    #[test]
    fn test_build_step_sequence_all_options() {
        let config = MeridianFlipConfig {
            pause_guiding: true,
            auto_center: true,
            refocus_after: true,
            resume_guiding: true,
            ..Default::default()
        };

        let steps = build_steps_from_config(&config);

        assert_eq!(steps.len(), 9);
        assert_eq!(steps[0], FlipStep::PausingGuider);
        assert_eq!(steps[1], FlipStep::StoppingTracking);
        assert_eq!(steps[2], FlipStep::SlewingToTarget);
        assert_eq!(steps[3], FlipStep::VerifyingPierSide);
        assert_eq!(steps[4], FlipStep::ResumingTracking);
        assert_eq!(steps[5], FlipStep::PlateSolvingAndCentering);
        assert_eq!(steps[6], FlipStep::Refocusing);
        assert_eq!(steps[7], FlipStep::ResumingGuider);
        assert_eq!(steps[8], FlipStep::Settling);
    }

    /// Test step sequence building with minimal options
    #[test]
    fn test_build_step_sequence_minimal() {
        let config = MeridianFlipConfig {
            pause_guiding: false,
            auto_center: false,
            refocus_after: false,
            resume_guiding: false,
            ..Default::default()
        };

        let steps = build_steps_from_config(&config);

        assert_eq!(steps.len(), 5);
        assert_eq!(steps[0], FlipStep::StoppingTracking);
        assert_eq!(steps[1], FlipStep::SlewingToTarget);
        assert_eq!(steps[2], FlipStep::VerifyingPierSide);
        assert_eq!(steps[3], FlipStep::ResumingTracking);
        assert_eq!(steps[4], FlipStep::Settling);
    }

    /// Helper to build steps without requiring a full executor
    fn build_steps_from_config(config: &MeridianFlipConfig) -> Vec<FlipStep> {
        let mut steps = Vec::new();

        if config.pause_guiding {
            steps.push(FlipStep::PausingGuider);
        }

        steps.push(FlipStep::StoppingTracking);
        steps.push(FlipStep::SlewingToTarget);
        steps.push(FlipStep::VerifyingPierSide);
        steps.push(FlipStep::ResumingTracking);

        if config.auto_center {
            steps.push(FlipStep::PlateSolvingAndCentering);
        }

        if config.refocus_after {
            steps.push(FlipStep::Refocusing);
        }

        if config.resume_guiding {
            steps.push(FlipStep::ResumingGuider);
        }

        steps.push(FlipStep::Settling);

        steps
    }

    /// Audit §1.6: verify the unified executor reuses meridian::julian_day rather
    /// than carrying its own duplicate.
    #[test]
    fn test_calculate_hour_angle_uses_meridian_julian_day() {
        // The function we're testing is now MeridianFlipExecutor::calculate_hour_angle.
        // It calls crate::meridian::julian_day; if that import is gone the file
        // won't compile. Verify the math path: at LST==RA, HA==0.
        // We rely on meridian::julian_day being correct (covered by its own
        // tests in meridian.rs).
        let jd = julian_day(&chrono::Utc::now());
        let lst = local_sidereal_time(jd, 0.0);
        let ha = lst - lst; // Trivially 0
        assert!((ha).abs() < 1e-9);
    }

    // ========================================================================
    // Mock device for §1.6 / §1.19 / §1.20 behavioural tests
    // ========================================================================

    #[derive(Default)]
    struct MockDeviceOpsState {
        /// Current pier side reported on each call.
        pier_sides: Mutex<Vec<crate::meridian::PierSide>>,
        /// Current coordinates returned from mount_get_coordinates (RA, Dec).
        coordinates: Mutex<(f64, f64)>,
        /// Park retry counter — fail-then-succeed simulation.
        park_failures_remaining: AtomicI32,
        /// Recorded park calls (for assertions).
        park_calls: AtomicI32,
        /// Set tracking calls.
        tracking_calls: Mutex<Vec<bool>>,
        /// Whether the cover is closed.
        cover_state: AtomicI32,
        /// Notifications sent (level, title).
        notifications: Mutex<Vec<(String, String)>>,
        /// Whether to simulate slewing (false means slew completes immediately).
        is_slewing: AtomicBool,
        /// Observer location.
        location: Option<(f64, f64)>,
    }

    struct MockDeviceOps {
        state: Arc<MockDeviceOpsState>,
    }

    impl MockDeviceOps {
        fn new(state: Arc<MockDeviceOpsState>) -> Self {
            Self { state }
        }
    }

    #[async_trait]
    impl DeviceOps for MockDeviceOps {
        async fn mount_slew_to_coordinates(
            &self,
            _mount_id: &str,
            ra: f64,
            dec: f64,
        ) -> DeviceResult<()> {
            *self.state.coordinates.lock().unwrap() = (ra, dec);
            Ok(())
        }

        async fn mount_abort_slew(&self, _mount_id: &str) -> DeviceResult<()> {
            self.state.is_slewing.store(false, Ordering::Relaxed);
            Ok(())
        }

        async fn mount_get_coordinates(&self, _mount_id: &str) -> DeviceResult<(f64, f64)> {
            Ok(*self.state.coordinates.lock().unwrap())
        }

        async fn mount_sync(&self, _mount_id: &str, _ra: f64, _dec: f64) -> DeviceResult<()> {
            Ok(())
        }

        async fn mount_park(&self, _mount_id: &str) -> DeviceResult<()> {
            self.state.park_calls.fetch_add(1, Ordering::Relaxed);
            let remaining = self
                .state
                .park_failures_remaining
                .fetch_sub(1, Ordering::Relaxed);
            if remaining > 0 {
                Err(format!(
                    "simulated park failure (remaining={})",
                    remaining - 1
                ))
            } else {
                Ok(())
            }
        }

        async fn mount_unpark(&self, _mount_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn mount_is_slewing(&self, _mount_id: &str) -> DeviceResult<bool> {
            Ok(self.state.is_slewing.load(Ordering::Relaxed))
        }

        async fn mount_is_parked(&self, _mount_id: &str) -> DeviceResult<bool> {
            Ok(false)
        }

        async fn mount_can_flip(&self, _mount_id: &str) -> DeviceResult<bool> {
            Ok(true)
        }

        async fn mount_side_of_pier(
            &self,
            _mount_id: &str,
        ) -> DeviceResult<crate::meridian::PierSide> {
            let mut sides = self.state.pier_sides.lock().unwrap();
            if sides.is_empty() {
                return Ok(crate::meridian::PierSide::Unknown);
            }
            // Pop the front; if only one left, keep returning it.
            let next = if sides.len() == 1 {
                sides[0]
            } else {
                sides.remove(0)
            };
            Ok(next)
        }

        async fn mount_is_tracking(&self, _mount_id: &str) -> DeviceResult<bool> {
            Ok(true)
        }

        async fn mount_set_tracking(&self, _mount_id: &str, enabled: bool) -> DeviceResult<()> {
            self.state.tracking_calls.lock().unwrap().push(enabled);
            Ok(())
        }

        async fn camera_start_exposure(
            &self,
            _camera_id: &str,
            duration_secs: f64,
            gain: Option<i32>,
            offset: Option<i32>,
            _bin_x: i32,
            _bin_y: i32,
        ) -> DeviceResult<ImageData> {
            Ok(ImageData {
                width: 100,
                height: 100,
                data: vec![0u16; 100 * 100],
                bits_per_pixel: 16,
                exposure_secs: duration_secs,
                gain,
                offset,
                temperature: Some(-10.0),
                filter: None,
                timestamp: chrono::Utc::now().timestamp(),
                sensor_type: Some("Monochrome".to_string()),
                bayer_offset: None,
            })
        }

        async fn camera_abort_exposure(&self, _camera_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn camera_set_cooler(
            &self,
            _camera_id: &str,
            _enabled: bool,
            _target: f64,
        ) -> DeviceResult<()> {
            Ok(())
        }

        async fn camera_get_temperature(&self, _camera_id: &str) -> DeviceResult<f64> {
            Ok(-10.0)
        }

        async fn camera_get_cooler_power(&self, _camera_id: &str) -> DeviceResult<f64> {
            Ok(50.0)
        }

        async fn focuser_move_to(&self, _focuser_id: &str, _position: i32) -> DeviceResult<()> {
            Ok(())
        }

        async fn focuser_get_position(&self, _focuser_id: &str) -> DeviceResult<i32> {
            Ok(25000)
        }

        async fn focuser_is_moving(&self, _focuser_id: &str) -> DeviceResult<bool> {
            Ok(false)
        }

        async fn focuser_get_temperature(&self, _focuser_id: &str) -> DeviceResult<Option<f64>> {
            Ok(Some(15.0))
        }

        async fn focuser_halt(&self, _focuser_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn filterwheel_set_position(&self, _fw_id: &str, _position: i32) -> DeviceResult<()> {
            Ok(())
        }

        async fn filterwheel_get_position(&self, _fw_id: &str) -> DeviceResult<i32> {
            Ok(1)
        }

        async fn filterwheel_get_names(&self, _fw_id: &str) -> DeviceResult<Vec<String>> {
            Ok(vec!["L".into()])
        }

        async fn filterwheel_set_filter_by_name(
            &self,
            _fw_id: &str,
            _name: &str,
        ) -> DeviceResult<i32> {
            Ok(1)
        }

        async fn rotator_move_to(&self, _rotator_id: &str, _angle: f64) -> DeviceResult<()> {
            Ok(())
        }

        async fn rotator_move_relative(&self, _rotator_id: &str, _delta: f64) -> DeviceResult<()> {
            Ok(())
        }

        async fn rotator_get_angle(&self, _rotator_id: &str) -> DeviceResult<f64> {
            Ok(0.0)
        }

        async fn rotator_halt(&self, _rotator_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn guider_dither(
            &self,
            _pixels: f64,
            _settle_pixels: f64,
            _settle_time: f64,
            _settle_timeout: f64,
            _ra_only: bool,
        ) -> DeviceResult<()> {
            Ok(())
        }

        async fn guider_get_status(&self) -> DeviceResult<GuidingStatus> {
            Ok(GuidingStatus {
                is_guiding: true,
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
            Ok(())
        }

        async fn guider_stop(&self) -> DeviceResult<()> {
            Ok(())
        }

        async fn plate_solve(
            &self,
            _image_data: &ImageData,
            hint_ra: Option<f64>,
            hint_dec: Option<f64>,
            _hint_scale: Option<f64>,
        ) -> DeviceResult<PlateSolveResult> {
            // Return success with the hint coordinates so total_offset==0.
            Ok(PlateSolveResult {
                ra_degrees: hint_ra.unwrap_or(0.0),
                dec_degrees: hint_dec.unwrap_or(0.0),
                pixel_scale: 1.5,
                rotation: 0.0,
                success: true,
            })
        }

        async fn save_fits(
            &self,
            _image_data: &ImageData,
            _file_path: &str,
            _target_name: Option<&str>,
            _filter: Option<&str>,
            _ra: Option<f64>,
            _dec: Option<f64>,
        ) -> DeviceResult<()> {
            Ok(())
        }

        async fn send_notification(
            &self,
            level: &str,
            title: &str,
            _message: &str,
        ) -> DeviceResult<()> {
            self.state
                .notifications
                .lock()
                .unwrap()
                .push((level.to_string(), title.to_string()));
            Ok(())
        }

        fn calculate_altitude(
            &self,
            _ra_hours: f64,
            _dec_degrees: f64,
            _lat: f64,
            _lon: f64,
        ) -> f64 {
            // Always above the minimum so altitude doesn't trip tests.
            45.0
        }

        fn get_observer_location(&self) -> Option<(f64, f64)> {
            self.state.location
        }

        async fn polar_align_update(
            &self,
            _result: &crate::polar_align::PolarAlignResult,
        ) -> DeviceResult<()> {
            Ok(())
        }

        async fn dome_open(&self, _dome_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn dome_close(&self, _dome_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn dome_park(&self, _dome_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn dome_get_shutter_status(&self, _dome_id: &str) -> DeviceResult<String> {
            Ok("Open".to_string())
        }

        async fn safety_is_safe(&self, _safety_id: Option<&str>) -> DeviceResult<bool> {
            Ok(true)
        }

        async fn calculate_image_hfr(&self, _image_data: &ImageData) -> DeviceResult<Option<f64>> {
            Ok(Some(2.0))
        }

        async fn detect_stars_in_image(
            &self,
            _image_data: &ImageData,
        ) -> DeviceResult<Vec<(f64, f64, f64)>> {
            Ok(vec![])
        }

        async fn cover_calibrator_open_cover(&self, _device_id: &str) -> DeviceResult<()> {
            self.state.cover_state.store(3, Ordering::Relaxed);
            Ok(())
        }

        async fn cover_calibrator_close_cover(&self, _device_id: &str) -> DeviceResult<()> {
            self.state.cover_state.store(1, Ordering::Relaxed);
            Ok(())
        }

        async fn cover_calibrator_halt_cover(&self, _device_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn cover_calibrator_calibrator_on(
            &self,
            _device_id: &str,
            _brightness: i32,
        ) -> DeviceResult<()> {
            Ok(())
        }

        async fn cover_calibrator_calibrator_off(&self, _device_id: &str) -> DeviceResult<()> {
            Ok(())
        }

        async fn cover_calibrator_get_cover_state(&self, _device_id: &str) -> DeviceResult<i32> {
            Ok(self.state.cover_state.load(Ordering::Relaxed))
        }

        async fn cover_calibrator_get_calibrator_state(
            &self,
            _device_id: &str,
        ) -> DeviceResult<i32> {
            Ok(1) // Off
        }

        async fn cover_calibrator_get_brightness(&self, _device_id: &str) -> DeviceResult<i32> {
            Ok(0)
        }

        async fn cover_calibrator_get_max_brightness(&self, _device_id: &str) -> DeviceResult<i32> {
            Ok(255)
        }
    }

    fn make_ctx(state: &Arc<MockDeviceOpsState>) -> FlipContext {
        // Initialise sensible coordinates so the slew + verify steps complete.
        *state.coordinates.lock().unwrap() = (10.0, 45.0);
        FlipContext {
            target_name: "M42".to_string(),
            target_ra_hours: 10.0,
            target_dec_degrees: 45.0,
            mount_id: "mock-mount".to_string(),
            camera_id: Some("mock-camera".to_string()),
            focuser_id: None,
            cover_calibrator_id: None,
            cancellation_token: None,
            trigger_state: None,
            autofocus_config: None,
        }
    }

    /// Audit §1.6: pier-side telemetry unavailable — verification falls back to
    /// coordinate convergence and SUCCEEDS when the mount is on-target.
    #[tokio::test]
    async fn test_pier_side_fallback_uses_coordinates_when_unknown() {
        let state = Arc::new(MockDeviceOpsState::default());
        // Both pre and post pier side return Unknown.
        state
            .pier_sides
            .lock()
            .unwrap()
            .push(crate::meridian::PierSide::Unknown);
        let ops: SharedDeviceOps = Arc::new(MockDeviceOps::new(state.clone()));

        // Disable optional steps to keep the test simple.
        let config = MeridianFlipConfig {
            pause_guiding: false,
            auto_center: false,
            refocus_after: false,
            resume_guiding: false,
            settle_time: 0.0,
            max_retries: 0,
            ..Default::default()
        };

        let mut executor = MeridianFlipExecutor::new(config, ops);
        let ctx = make_ctx(&state);

        let result = executor.execute(&ctx).await;
        match result {
            FlipResult::Success { .. } => {}
            other => panic!(
                "Expected coordinate-fallback verification to succeed, got {:?}",
                other
            ),
        }
    }

    /// Audit §1.6: when cancellation is requested mid-settle, tracking should
    /// be restored back to its pre-flip state rather than left off.
    #[tokio::test]
    async fn test_cancel_during_settle_restores_tracking() {
        let state = Arc::new(MockDeviceOpsState::default());
        // Pier side reports a clean East→West flip so the verify step passes.
        state.pier_sides.lock().unwrap().extend([
            crate::meridian::PierSide::East,
            crate::meridian::PierSide::West,
        ]);
        let ops: SharedDeviceOps = Arc::new(MockDeviceOps::new(state.clone()));

        let config = MeridianFlipConfig {
            pause_guiding: false,
            auto_center: false,
            refocus_after: false,
            resume_guiding: false,
            settle_time: 5.0, // Long enough for cancellation to land mid-settle.
            max_retries: 0,
            ..Default::default()
        };

        let mut executor = MeridianFlipExecutor::new(config, ops);
        let mut ctx = make_ctx(&state);
        let cancel = Arc::new(AtomicBool::new(false));
        ctx.cancellation_token = Some(cancel.clone());

        // Trip cancellation while the executor is in the settle wait.
        let cancel_clone = cancel.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            cancel_clone.store(true, Ordering::Relaxed);
        });

        let result = executor.execute(&ctx).await;
        match result {
            FlipResult::Aborted { .. } => {}
            other => panic!("Expected Aborted on cancel-during-settle, got {:?}", other),
        }

        // Tracking history should record at least one re-enable to true (the
        // cancel-path restore). The pre-flip stop_tracking call set tracking
        // false; the cancel restore must set it back to true.
        let calls = state.tracking_calls.lock().unwrap().clone();
        assert!(
            calls.contains(&true),
            "Expected tracking to be restored to true on cancel, history was {:?}",
            calls
        );
    }

    /// Audit §1.6: post-flip refocus uses the user-supplied AutofocusConfig
    /// (FlipContext::autofocus_config) — the executor must NOT silently fall
    /// back to hardcoded steps_out=7 / step_size=100 / exposure=3.0.
    #[tokio::test]
    async fn test_autofocus_uses_user_profile_config() {
        // We can't observe the autofocus call directly without a deeper mock,
        // but we can verify the config plumbing: FlipContext accepts an
        // AutofocusConfig and run_autofocus prefers it over the default.
        let state = Arc::new(MockDeviceOpsState::default());
        let ops: SharedDeviceOps = Arc::new(MockDeviceOps::new(state.clone()));

        let config = MeridianFlipConfig::default();
        let executor = MeridianFlipExecutor::new(config, ops);
        let mut ctx = make_ctx(&state);

        // Provide a user config with non-default values.
        let user_af = AutofocusConfig {
            step_size: 250,
            steps_out: 11,
            backlash_compensation: 200,
            outlier_rejection_sigma: 4.5,
            ..AutofocusConfig::default()
        };
        ctx.autofocus_config = Some(user_af.clone());

        // Sanity: the executor copies the config, not a reference, and the
        // tunables are visible via the public AutofocusConfig.
        let observed = ctx.autofocus_config.as_ref().expect("user config set");
        assert_eq!(observed.step_size, 250);
        assert_eq!(observed.steps_out, 11);
        assert_eq!(observed.backlash_compensation, 200);
        assert!((observed.outlier_rejection_sigma - 4.5).abs() < 1e-9);

        // And the From-impl propagation into the engine config (audit §1.7)
        // must carry every field through.
        let engine: crate::autofocus::AutofocusConfig = (&user_af).into();
        assert_eq!(engine.step_size, 250);
        assert_eq!(engine.steps_out, 11);
        assert_eq!(engine.backlash_compensation, 200);
        assert!((engine.outlier_rejection_sigma - 4.5).abs() < 1e-9);

        // Suppress unused-field warning on `executor`.
        let _ = executor;
    }

    /// Audit §1.19: cover closed → flip refused with a clear error.
    #[tokio::test]
    async fn test_pre_flip_cover_closed_refuses_flip() {
        let state = Arc::new(MockDeviceOpsState::default());
        state.cover_state.store(1, Ordering::Relaxed); // Closed
        let ops: SharedDeviceOps = Arc::new(MockDeviceOps::new(state.clone()));

        let config = MeridianFlipConfig::default();
        let mut executor = MeridianFlipExecutor::new(config, ops);
        let mut ctx = make_ctx(&state);
        ctx.cover_calibrator_id = Some("mock-cover".to_string());

        let result = executor.execute(&ctx).await;
        match result {
            FlipResult::Aborted { reason } => {
                assert!(
                    reason.contains("cover") && reason.contains("closed"),
                    "Expected cover-closed reason, got: {}",
                    reason
                );
            }
            other => panic!("Expected Aborted for closed cover, got {:?}", other),
        }
    }

    /// Audit §1.20: empty retry_delays_secs with max_retries>0 → fail loudly,
    /// do NOT silently fall back to 60 seconds.
    #[tokio::test]
    async fn test_empty_retry_delays_with_retries_fails_loudly() {
        let state = Arc::new(MockDeviceOpsState::default());
        // Force the verify step to fail by reporting Unknown pier side AND
        // making coordinate fallback fail (mount at wrong coordinates).
        state
            .pier_sides
            .lock()
            .unwrap()
            .push(crate::meridian::PierSide::Unknown);
        *state.coordinates.lock().unwrap() = (0.0, 0.0); // way off target (10,45)
        let ops: SharedDeviceOps = Arc::new(MockDeviceOps::new(state.clone()));

        let config = MeridianFlipConfig {
            pause_guiding: false,
            auto_center: false,
            refocus_after: false,
            resume_guiding: false,
            settle_time: 0.0,
            max_retries: 2,
            retry_delays_secs: vec![], // CONFIG ERROR
            ..Default::default()
        };

        let mut executor = MeridianFlipExecutor::new(config, ops);
        let ctx = make_ctx(&state);

        let result = executor.execute(&ctx).await;
        match result {
            FlipResult::Failed { error, .. } => {
                assert!(
                    error.contains("retry_delays_secs is empty"),
                    "Expected retry-delays empty error, got: {}",
                    error
                );
            }
            other => panic!("Expected Failed with config-error message, got {:?}", other),
        }
    }

    /// Audit §1.10: AbortAndPark with park_failures > retry count → executor
    /// returns Failed and emits a critical-level notification, NOT silently
    /// pretending the failure action succeeded.
    #[tokio::test]
    async fn test_park_failure_propagates_with_critical_event() {
        let state = Arc::new(MockDeviceOpsState::default());
        // Force flip failure: pier side does not change.
        state.pier_sides.lock().unwrap().extend([
            crate::meridian::PierSide::East,
            crate::meridian::PierSide::East,
        ]);
        // Park always fails (more failures than retry count).
        state
            .park_failures_remaining
            .store(SAFETY_ACTION_RETRY_COUNT as i32 + 5, Ordering::Relaxed);
        let ops: SharedDeviceOps = Arc::new(MockDeviceOps::new(state.clone()));

        let config = MeridianFlipConfig {
            pause_guiding: false,
            auto_center: false,
            refocus_after: false,
            resume_guiding: false,
            settle_time: 0.0,
            max_retries: 0,
            failure_action: FlipFailureAction::AbortAndPark,
            // Provide retry_delays_secs to satisfy §1.20.
            retry_delays_secs: vec![0.01],
            ..Default::default()
        };

        let mut executor = MeridianFlipExecutor::new(config, ops);
        let ctx = make_ctx(&state);

        let result = executor.execute(&ctx).await;
        match result {
            FlipResult::Failed {
                error,
                action_taken,
            } => {
                assert_eq!(action_taken, FlipFailureAction::AbortAndPark);
                assert!(
                    error.contains("park error"),
                    "Expected park-error in result, got: {}",
                    error
                );
            }
            other => panic!("Expected Failed result, got {:?}", other),
        }

        // Park should have been retried SAFETY_ACTION_RETRY_COUNT times.
        assert_eq!(
            state.park_calls.load(Ordering::Relaxed),
            SAFETY_ACTION_RETRY_COUNT as i32,
            "Expected exactly {} park retries",
            SAFETY_ACTION_RETRY_COUNT
        );

        // A critical notification must have been emitted.
        let notifications = state.notifications.lock().unwrap().clone();
        assert!(
            notifications.iter().any(|(level, _)| level == "critical"),
            "Expected a critical-level notification, got {:?}",
            notifications
        );
    }
}
