//! Events emitted during meridian flip execution for progress tracking

use serde::{Deserialize, Serialize};

/// Pier side of the mount
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum PierSide {
    East,
    West,
    Unknown,
}

/// Steps in the meridian flip sequence
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum FlipStep {
    PausingGuider,
    StoppingTracking,
    SlewingToTarget,
    VerifyingPierSide,
    ResumingTracking,
    PlateSolvingAndCentering,
    Refocusing,
    ResumingGuider,
    Settling,
}

impl FlipStep {
    pub fn description(&self) -> &'static str {
        match self {
            FlipStep::PausingGuider => "Pausing guider",
            FlipStep::StoppingTracking => "Stopping tracking",
            FlipStep::SlewingToTarget => "Slewing to target (flip)",
            FlipStep::VerifyingPierSide => "Verifying pier side",
            FlipStep::ResumingTracking => "Resuming tracking",
            FlipStep::PlateSolvingAndCentering => "Plate solving and centering",
            FlipStep::Refocusing => "Running autofocus",
            FlipStep::ResumingGuider => "Resuming guider",
            FlipStep::Settling => "Settling",
        }
    }
}

/// Events emitted during meridian flip execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MeridianFlipEvent {
    /// Flip is starting
    Starting {
        target_name: String,
        from_pier_side: PierSide,
        hour_angle: f64,
    },
    /// A step has started
    StepStarted {
        step: FlipStep,
        step_index: u8,
        total_steps: u8,
    },
    /// A step completed successfully
    StepCompleted {
        step: FlipStep,
        duration_secs: Option<f64>,
    },
    /// A step failed
    StepFailed {
        step: FlipStep,
        error: String,
    },
    /// Overall progress update (0-100)
    Progress {
        percent: u8,
    },
    /// Retry scheduled after failure
    RetryScheduled {
        attempt: u8,
        max_attempts: u8,
        delay_secs: f64,
    },
    /// Flip completed successfully
    Completed {
        new_pier_side: PierSide,
        duration_secs: f64,
    },
    /// Flip failed after all retries
    Failed {
        error: String,
        action_taken: String,
    },
    /// Flip was aborted by user
    Aborted {
        reason: String,
    },
}

/// Callback type for receiving flip events
pub type FlipEventCallback = Box<dyn Fn(MeridianFlipEvent) + Send + Sync>;

/// Builder for creating flip event sequences with logging
pub struct FlipEventEmitter {
    callback: Option<FlipEventCallback>,
    log_prefix: String,
}

impl FlipEventEmitter {
    pub fn new() -> Self {
        Self {
            callback: None,
            log_prefix: "[MERIDIAN]".to_string(),
        }
    }

    pub fn with_callback(mut self, callback: FlipEventCallback) -> Self {
        self.callback = Some(callback);
        self
    }

    pub fn emit(&self, event: MeridianFlipEvent) {
        // Always log
        self.log_event(&event);

        // Call callback if set
        if let Some(cb) = &self.callback {
            cb(event);
        }
    }

    fn log_event(&self, event: &MeridianFlipEvent) {
        match event {
            MeridianFlipEvent::Starting { target_name, from_pier_side, hour_angle } => {
                tracing::info!(
                    "{} ══════════════════════════════════════════════════════════",
                    self.log_prefix
                );
                tracing::info!("{} FLIP TRIGGER ACTIVATED", self.log_prefix);
                tracing::info!("{}   Target: {}", self.log_prefix, target_name);
                tracing::info!("{}   Hour Angle: {:.2}h ({:.1} minutes past meridian)",
                    self.log_prefix, hour_angle, hour_angle * 60.0);
                tracing::info!("{}   Current Pier Side: {:?}", self.log_prefix, from_pier_side);
                tracing::info!(
                    "{} ──────────────────────────────────────────────────────────",
                    self.log_prefix
                );
            }
            MeridianFlipEvent::StepStarted { step, step_index, total_steps } => {
                tracing::info!(
                    "{} Step {}/{}: {}...",
                    self.log_prefix,
                    step_index + 1,
                    total_steps,
                    step.description()
                );
            }
            MeridianFlipEvent::StepCompleted { step, duration_secs } => {
                if let Some(duration) = duration_secs {
                    tracing::info!(
                        "{}   ✓ {} (took {:.1}s)",
                        self.log_prefix,
                        step.description(),
                        duration
                    );
                } else {
                    tracing::info!("{}   ✓ {}", self.log_prefix, step.description());
                }
            }
            MeridianFlipEvent::StepFailed { step, error } => {
                tracing::error!(
                    "{}   ✗ {} FAILED: {}",
                    self.log_prefix,
                    step.description(),
                    error
                );
            }
            MeridianFlipEvent::Progress { percent } => {
                tracing::debug!("{} Progress: {}%", self.log_prefix, percent);
            }
            MeridianFlipEvent::RetryScheduled { attempt, max_attempts, delay_secs } => {
                tracing::warn!(
                    "{} Retry {}/{} scheduled in {:.0} seconds...",
                    self.log_prefix,
                    attempt,
                    max_attempts,
                    delay_secs
                );
            }
            MeridianFlipEvent::Completed { new_pier_side, duration_secs } => {
                tracing::info!(
                    "{} ══════════════════════════════════════════════════════════",
                    self.log_prefix
                );
                tracing::info!("{} FLIP COMPLETED SUCCESSFULLY", self.log_prefix);
                tracing::info!("{}   Total duration: {:.1} seconds", self.log_prefix, duration_secs);
                tracing::info!("{}   New pier side: {:?}", self.log_prefix, new_pier_side);
                tracing::info!("{}   Resuming sequence...", self.log_prefix);
                tracing::info!(
                    "{} ══════════════════════════════════════════════════════════",
                    self.log_prefix
                );
            }
            MeridianFlipEvent::Failed { error, action_taken } => {
                tracing::error!(
                    "{} ══════════════════════════════════════════════════════════",
                    self.log_prefix
                );
                tracing::error!("{} FLIP FAILED", self.log_prefix);
                tracing::error!("{}   Error: {}", self.log_prefix, error);
                tracing::error!("{}   Action: {}", self.log_prefix, action_taken);
                tracing::error!(
                    "{} ══════════════════════════════════════════════════════════",
                    self.log_prefix
                );
            }
            MeridianFlipEvent::Aborted { reason } => {
                tracing::warn!("{} FLIP ABORTED: {}", self.log_prefix, reason);
            }
        }
    }
}

impl Default for FlipEventEmitter {
    fn default() -> Self {
        Self::new()
    }
}
