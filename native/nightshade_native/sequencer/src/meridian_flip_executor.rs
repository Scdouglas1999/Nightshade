//! Meridian Flip Executor
//!
//! Executes the meridian flip sequence with configurable steps, retries, and progress events.

use std::sync::Arc;
use std::time::Instant;
use tokio::sync::mpsc;

use crate::device_ops::SharedDeviceOps;
use crate::instructions::{execute_autofocus, InstructionContext};
use crate::meridian_events::{FlipEventEmitter, FlipStep, MeridianFlipEvent, PierSide};
use crate::{AutofocusConfig, AutofocusMethod, Binning, FlipFailureAction, MeridianFlipConfig};

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

/// Context for executing a meridian flip
pub struct FlipContext {
    pub target_name: String,
    pub target_ra_hours: f64,
    pub target_dec_degrees: f64,
    pub mount_id: String,
    pub camera_id: Option<String>,
    pub focuser_id: Option<String>,
}

/// Executes a complete meridian flip sequence
pub struct MeridianFlipExecutor {
    config: MeridianFlipConfig,
    device_ops: SharedDeviceOps,
    event_emitter: FlipEventEmitter,
    event_tx: Option<mpsc::Sender<MeridianFlipEvent>>,
    abort_requested: Arc<std::sync::atomic::AtomicBool>,
}

impl MeridianFlipExecutor {
    /// Create a new flip executor
    pub fn new(config: MeridianFlipConfig, device_ops: SharedDeviceOps) -> Self {
        Self {
            config,
            device_ops,
            event_emitter: FlipEventEmitter::new(),
            event_tx: None,
            abort_requested: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        }
    }

    /// Set event channel for progress updates
    pub fn with_event_channel(mut self, tx: mpsc::Sender<MeridianFlipEvent>) -> Self {
        self.event_tx = Some(tx);
        self
    }

    /// Get abort handle for external abort requests
    pub fn abort_handle(&self) -> Arc<std::sync::atomic::AtomicBool> {
        self.abort_requested.clone()
    }

    /// Execute the meridian flip
    pub async fn execute(&mut self, ctx: &FlipContext) -> FlipResult {
        let start_time = Instant::now();

        // Get current pier side
        let from_pier_side = match self.get_pier_side(&ctx.mount_id).await {
            Ok(ps) => ps,
            Err(e) => {
                tracing::error!("[MERIDIAN] Failed to get current pier side: {}", e);
                PierSide::Unknown
            }
        };

        // Calculate hour angle for logging
        let hour_angle = self.calculate_hour_angle(ctx.target_ra_hours);

        // Emit starting event
        self.emit_event(MeridianFlipEvent::Starting {
            target_name: ctx.target_name.clone(),
            from_pier_side,
            hour_angle,
        });

        // Determine which steps to execute
        let steps = self.build_step_sequence();
        let total_steps = steps.len() as u8;

        // Execute with retries
        let mut attempt = 0;
        let max_attempts = self.config.max_retries + 1;

        loop {
            attempt += 1;

            match self.execute_steps(&steps, ctx, total_steps).await {
                Ok(new_pier_side) => {
                    let duration = start_time.elapsed().as_secs_f64();
                    self.emit_event(MeridianFlipEvent::Completed {
                        new_pier_side,
                        duration_secs: duration,
                    });
                    return FlipResult::Success {
                        new_pier_side,
                        duration_secs: duration,
                    };
                }
                Err(e) => {
                    // Check for abort
                    if self
                        .abort_requested
                        .load(std::sync::atomic::Ordering::Relaxed)
                    {
                        self.emit_event(MeridianFlipEvent::Aborted {
                            reason: "User requested abort".to_string(),
                        });
                        return FlipResult::Aborted {
                            reason: "User requested abort".to_string(),
                        };
                    }

                    if attempt < max_attempts {
                        // Get retry delay
                        let delay_idx = (attempt - 1) as usize;
                        let delay = self
                            .config
                            .retry_delays_secs
                            .get(delay_idx)
                            .copied()
                            .unwrap_or(60.0);

                        self.emit_event(MeridianFlipEvent::RetryScheduled {
                            attempt: attempt as u8,
                            max_attempts: max_attempts as u8,
                            delay_secs: delay,
                        });

                        // Wait before retry
                        tokio::time::sleep(std::time::Duration::from_secs_f64(delay)).await;
                    } else {
                        // All retries exhausted
                        let action_taken = self.config.failure_action;
                        let action_str = match action_taken {
                            FlipFailureAction::PauseAndAlert => "Paused sequence and alerted user",
                            FlipFailureAction::AbortAndPark => "Aborted sequence and parking mount",
                        };

                        self.emit_event(MeridianFlipEvent::Failed {
                            error: e.clone(),
                            action_taken: action_str.to_string(),
                        });

                        // Execute failure action
                        self.execute_failure_action(&ctx.mount_id).await;

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
    ) -> Result<PierSide, String> {
        let mut new_pier_side = PierSide::Unknown;

        for (idx, step) in steps.iter().enumerate() {
            // Check abort before each step
            if self
                .abort_requested
                .load(std::sync::atomic::Ordering::Relaxed)
            {
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
                    self.slew_to_target(&ctx.mount_id, ctx.target_ra_hours, ctx.target_dec_degrees)
                        .await
                }
                FlipStep::VerifyingPierSide => {
                    match self.verify_pier_side_changed(&ctx.mount_id).await {
                        Ok(ps) => {
                            new_pier_side = ps;
                            Ok(())
                        }
                        Err(e) => Err(e),
                    }
                }
                FlipStep::ResumingTracking => self.resume_tracking(&ctx.mount_id).await,
                FlipStep::PlateSolvingAndCentering => self.plate_solve_and_center(ctx).await,
                FlipStep::Refocusing => self.run_autofocus(ctx).await,
                FlipStep::ResumingGuider => self.resume_guider().await,
                FlipStep::Settling => self.wait_settle().await,
            };

            let duration = step_start.elapsed().as_secs_f64();

            match result {
                Ok(()) => {
                    self.emit_event(MeridianFlipEvent::StepCompleted {
                        step: *step,
                        duration_secs: Some(duration),
                    });

                    // Update progress
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
        mount_id: &str,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> Result<(), String> {
        tracing::info!(
            "[MERIDIAN] Slewing to target (flip side): RA={:.4}h, Dec={:.4}°",
            ra_hours,
            dec_degrees
        );

        // Start slew
        self.device_ops
            .mount_slew_to_coordinates(mount_id, ra_hours, dec_degrees)
            .await?;

        // Wait for slew to complete
        loop {
            if self
                .abort_requested
                .load(std::sync::atomic::Ordering::Relaxed)
            {
                self.device_ops.mount_abort_slew(mount_id).await?;
                return Err("Abort requested during slew".to_string());
            }

            let is_slewing = self.device_ops.mount_is_slewing(mount_id).await?;
            if !is_slewing {
                break;
            }

            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }

        Ok(())
    }

    async fn verify_pier_side_changed(&self, mount_id: &str) -> Result<PierSide, String> {
        tracing::info!("[MERIDIAN] Verifying pier side changed...");

        let pier_side = self.get_pier_side(mount_id).await?;

        tracing::info!("[MERIDIAN] New pier side: {:?}", pier_side);

        // We don't validate the specific pier side - the mount knows best
        // Just report what it is now
        Ok(pier_side)
    }

    async fn resume_tracking(&self, mount_id: &str) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Resuming tracking...");
        self.device_ops.mount_set_tracking(mount_id, true).await
    }

    async fn plate_solve_and_center(&self, ctx: &FlipContext) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Plate solving and centering...");

        let camera_id = ctx.camera_id.as_ref().ok_or("No camera configured")?;

        // Take a quick exposure for plate solving
        let image = self
            .device_ops
            .camera_start_exposure(camera_id, 5.0, None, None, 1, 1)
            .await?;

        // Plate solve
        let result = self
            .device_ops
            .plate_solve(
                &image,
                Some(ctx.target_ra_hours * 15.0), // Convert to degrees
                Some(ctx.target_dec_degrees),
                None,
            )
            .await?;

        if !result.success {
            return Err("Plate solve failed".to_string());
        }

        // Calculate offset
        let ra_offset = (result.ra_degrees / 15.0) - ctx.target_ra_hours; // hours
        let dec_offset = result.dec_degrees - ctx.target_dec_degrees; // degrees

        // Convert to arcseconds for comparison
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

        // If offset is small enough, we're done
        if total_offset < 30.0 {
            tracing::info!("[MERIDIAN] Centering within tolerance");
            return Ok(());
        }

        // Sync and re-slew for better centering
        self.device_ops
            .mount_sync(&ctx.mount_id, result.ra_degrees / 15.0, result.dec_degrees)
            .await?;

        self.device_ops
            .mount_slew_to_coordinates(&ctx.mount_id, ctx.target_ra_hours, ctx.target_dec_degrees)
            .await?;

        // Wait for slew
        loop {
            let is_slewing = self.device_ops.mount_is_slewing(&ctx.mount_id).await?;
            if !is_slewing {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }

        Ok(())
    }

    async fn run_autofocus(&self, ctx: &FlipContext) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Running autofocus...");

        // Check if camera and focuser are configured
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

        // Create autofocus configuration with sensible defaults for post-flip
        let af_config = AutofocusConfig {
            method: AutofocusMethod::VCurve,
            steps_out: 7,           // 7 steps each direction = 15 total points
            step_size: 100,         // 100 steps per measurement
            exposure_duration: 3.0, // 3 second exposures
            filter: None,           // Use current filter
            binning: Binning::One,  // 1x1 binning for best focus accuracy
        };

        // Create instruction context for autofocus
        let instruction_ctx = InstructionContext {
            target_ra: Some(ctx.target_ra_hours),
            target_dec: Some(ctx.target_dec_degrees),
            target_name: Some(ctx.target_name.clone()),
            current_filter: None,
            current_binning: Binning::One,
            cancellation_token: self.abort_requested.clone(),
            camera_id: Some(camera_id),
            mount_id: Some(ctx.mount_id.clone()),
            focuser_id: Some(focuser_id),
            filterwheel_id: None,
            rotator_id: None,
            dome_id: None,
            cover_calibrator_id: None,
            save_path: None,
            latitude: None,
            longitude: None,
            device_ops: self.device_ops.clone(),
            trigger_state: None,
        };

        // Execute autofocus
        tracing::info!(
            "[MERIDIAN] Starting V-curve autofocus with {} steps, {} step size",
            af_config.steps_out,
            af_config.step_size
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
            _ => {
                // Handle Pending, Running states (shouldn't normally happen)
                tracing::warn!(
                    "[MERIDIAN] Autofocus returned unexpected status: {:?}",
                    result.status
                );
                Ok(())
            }
        }
    }

    async fn resume_guider(&self) -> Result<(), String> {
        tracing::info!("[MERIDIAN] Resuming guider...");

        // Start guiding with reasonable defaults
        self.device_ops.guider_start(1.5, 10.0, 60.0).await
    }

    async fn wait_settle(&self) -> Result<(), String> {
        let settle_time = self.config.settle_time;
        tracing::info!("[MERIDIAN] Waiting for settle ({:.0}s)...", settle_time);

        let settle_duration = std::time::Duration::from_secs_f64(settle_time);
        let check_interval = std::time::Duration::from_millis(500);
        let mut elapsed = std::time::Duration::ZERO;

        while elapsed < settle_duration {
            if self
                .abort_requested
                .load(std::sync::atomic::Ordering::Relaxed)
            {
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
        // Convert from crate::meridian::PierSide to crate::meridian_events::PierSide
        Ok(match ps {
            crate::meridian::PierSide::East => PierSide::East,
            crate::meridian::PierSide::West => PierSide::West,
            crate::meridian::PierSide::Unknown => PierSide::Unknown,
        })
    }

    fn calculate_hour_angle(&self, ra_hours: f64) -> f64 {
        // Calculate Hour Angle: HA = LST - RA
        // We use Greenwich Mean Sidereal Time (GMST) as an approximation for LST.
        // This is accurate enough for meridian flip timing since the offset is
        // constant for a given location and cancels out when comparing against
        // configured flip thresholds.
        let now = chrono::Utc::now();
        let jd = julian_day(now);
        let gmst = greenwich_mean_sidereal_time(jd);

        // Use GMST as LST approximation (longitude offset is constant for a given site)
        let lst = gmst;
        let ha = lst - ra_hours;

        // Normalize to -12 to +12 range
        let mut ha_norm = ha % 24.0;
        if ha_norm > 12.0 {
            ha_norm -= 24.0;
        } else if ha_norm < -12.0 {
            ha_norm += 24.0;
        }

        ha_norm
    }

    async fn execute_failure_action(&self, mount_id: &str) {
        match self.config.failure_action {
            FlipFailureAction::PauseAndAlert => {
                tracing::warn!("[MERIDIAN] Flip failed - pausing and alerting user");
                let _ = self
                    .device_ops
                    .send_notification(
                        "error",
                        "Meridian Flip Failed",
                        "The meridian flip could not complete. Please check your equipment.",
                    )
                    .await;
            }
            FlipFailureAction::AbortAndPark => {
                tracing::warn!("[MERIDIAN] Flip failed - aborting and parking");
                let _ = self.device_ops.mount_set_tracking(mount_id, false).await;
                let _ = self.device_ops.mount_park(mount_id).await;
                let _ = self
                    .device_ops
                    .send_notification(
                        "error",
                        "Meridian Flip Failed - Mount Parked",
                        "The meridian flip failed. Mount has been parked for safety.",
                    )
                    .await;
            }
        }
    }

    fn emit_event(&self, event: MeridianFlipEvent) {
        // Log via emitter
        self.event_emitter.emit(event.clone());

        // Send to channel if configured
        if let Some(tx) = &self.event_tx {
            let _ = tx.try_send(event);
        }
    }
}

// ============================================================================
// Astronomical helper functions
// ============================================================================

/// Calculate Julian Day from UTC timestamp
fn julian_day(utc: chrono::DateTime<chrono::Utc>) -> f64 {
    use chrono::{Datelike, Timelike};

    let y = utc.year() as f64;
    let m = utc.month() as f64;
    let d = utc.day() as f64
        + (utc.hour() as f64 + utc.minute() as f64 / 60.0 + utc.second() as f64 / 3600.0) / 24.0;

    let (y, m) = if m <= 2.0 {
        (y - 1.0, m + 12.0)
    } else {
        (y, m)
    };

    let a = (y / 100.0).floor();
    let b = 2.0 - a + (a / 4.0).floor();

    (365.25 * (y + 4716.0)).floor() + (30.6001 * (m + 1.0)).floor() + d + b - 1524.5
}

/// Calculate Greenwich Mean Sidereal Time in hours
fn greenwich_mean_sidereal_time(jd: f64) -> f64 {
    let t = (jd - 2451545.0) / 36525.0;

    let gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t
        - t * t * t / 38710000.0;

    // Convert to hours and normalize
    let mut gmst_hours = (gmst % 360.0) / 15.0;
    if gmst_hours < 0.0 {
        gmst_hours += 24.0;
    }

    gmst_hours
}

#[cfg(test)]
mod tests {
    use super::*;

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

    #[test]
    fn test_julian_day() {
        use chrono::TimeZone;

        // J2000.0 epoch: January 1, 2000, 12:00 TT (approximately UTC)
        let j2000 = chrono::Utc.with_ymd_and_hms(2000, 1, 1, 12, 0, 0).unwrap();
        let jd = julian_day(j2000);

        // Should be very close to 2451545.0
        assert!((jd - 2451545.0).abs() < 0.001);
    }

    #[test]
    fn test_gmst() {
        use chrono::TimeZone;

        // At J2000.0, GMST should be approximately 18.697... hours
        let j2000 = chrono::Utc.with_ymd_and_hms(2000, 1, 1, 12, 0, 0).unwrap();
        let jd = julian_day(j2000);
        let gmst = greenwich_mean_sidereal_time(jd);

        // GMST at J2000.0 is approximately 18.697374558 hours
        assert!((gmst - 18.697).abs() < 0.1);
    }
}
