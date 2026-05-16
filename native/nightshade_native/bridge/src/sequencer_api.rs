//! Sequencer API exposed to Dart

use crate::error::NightshadeError;
use nightshade_sequencer::{get_executor, ExecutorState, SafetyFailMode, SequenceDefinition};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequencerStatus {
    pub state: String, // "Idle", "Running", etc.
    pub current_node_id: Option<String>,
    pub current_node_name: Option<String>,
    pub progress: f64, // 0.0 to 1.0
    pub message: Option<String>,
}

/// Load a sequence plan from JSON
pub async fn sequencer_load_plan(plan_json: String) -> Result<(), NightshadeError> {
    let sequence: SequenceDefinition = serde_json::from_str(&plan_json)
        .map_err(|e| NightshadeError::OperationFailed(format!("Invalid plan JSON: {}", e)))?;

    let executor = get_executor();
    let mut exec = executor.write().await;

    // Set up device ops
    exec.set_device_ops(crate::sequencer_ops::create_device_ops());

    // Load sequence
    exec.load_sequence(sequence)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Start the sequence
pub async fn sequencer_start() -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;

    exec.start()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Stop the sequence
pub async fn sequencer_stop() -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;

    exec.stop()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Pause the sequence
pub async fn sequencer_pause() -> Result<(), NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;

    exec.pause()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Resume the sequence
pub async fn sequencer_resume() -> Result<(), NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;

    exec.resume()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get sequencer status
pub async fn sequencer_get_status() -> Result<SequencerStatus, NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;
    let progress = exec.get_progress();

    let state_str = match progress.state {
        ExecutorState::Idle => "Idle",
        ExecutorState::Running => "Running",
        ExecutorState::Paused => "Paused",
        ExecutorState::Stopping => "Stopping",
        ExecutorState::Cancelled => "Cancelled",
        ExecutorState::Completed => "Completed",
        ExecutorState::Failed => "Failed",
    }
    .to_string();

    // Why (audit-rust §1.4): exposure counters are u32; u32 → f64 widening
    // is exact. The resulting fraction is a UI progress value in [0, 1].
    let progress_val = if progress.total_exposures > 0 {
        f64::from(progress.completed_exposures) / f64::from(progress.total_exposures)
    } else {
        0.0
    };

    Ok(SequencerStatus {
        state: state_str,
        current_node_id: progress.current_node_id,
        current_node_name: progress.current_node_name,
        progress: progress_val,
        message: progress.message,
    })
}

/// Set connected devices for the sequencer
pub async fn sequencer_set_devices(
    camera_id: Option<String>,
    mount_id: Option<String>,
    focuser_id: Option<String>,
    filterwheel_id: Option<String>,
    rotator_id: Option<String>,
) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;

    exec.set_devices(camera_id, mount_id, focuser_id, filterwheel_id, rotator_id);
    Ok(())
}

/// Set simulation mode (use mock devices instead of real hardware)
pub async fn sequencer_set_simulation_mode(enabled: bool) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;

    // Production/release artifacts must not execute simulated hardware paths.
    if enabled && !cfg!(debug_assertions) {
        return Err(NightshadeError::NotSupported {
            device_id: "sequencer".to_string(),
            operation: "set_simulation_mode(true)".to_string(),
        });
    }

    if enabled {
        // Use NullDeviceOps for simulation
        exec.set_device_ops(std::sync::Arc::new(nightshade_sequencer::NullDeviceOps));
        // Set fake device IDs so instructions don't fail with "No camera connected"
        exec.set_devices(
            Some("sim_camera".to_string()),
            Some("sim_mount".to_string()),
            Some("sim_focuser".to_string()),
            Some("sim_filterwheel".to_string()),
            Some("sim_rotator".to_string()),
        );
        tracing::info!("Sequencer simulation mode enabled with simulated devices");
    } else {
        // Use real device ops
        exec.set_device_ops(crate::sequencer_ops::create_device_ops());
        tracing::info!("Sequencer simulation mode disabled");
    }

    Ok(())
}

/// Set the safety fail mode for the sequencer.
/// This determines behavior when safety devices fail or are unavailable:
/// - "fail_closed": Treat unavailable safety data as unsafe (enforced)
/// - "fail_open"/"warn_only": accepted for backward compatibility and coerced to fail_closed
pub async fn sequencer_set_safety_fail_mode(mode: String) -> Result<(), NightshadeError> {
    let mode_lower = mode.to_lowercase();
    let fail_mode = match mode_lower.as_str() {
        "fail_closed" | "failclosed" => SafetyFailMode::FailClosed,
        "fail_open" | "failopen" | "warn_only" | "warnonly" => {
            tracing::warn!(
                "Safety fail mode '{}' requested, but strict fail-closed is enforced; using fail_closed",
                mode
            );
            SafetyFailMode::FailClosed
        }
        _ => {
            return Err(NightshadeError::InvalidParameter(format!(
                "Invalid safety fail mode: '{}'. Must be 'fail_closed' (legacy aliases: 'fail_open', 'warn_only').",
                mode
            )));
        }
    };

    let executor = get_executor();
    let mut exec = executor.write().await;
    exec.set_safety_fail_mode(fail_mode);
    tracing::info!("Sequencer safety fail mode set to: {:?}", fail_mode);

    Ok(())
}

// ============================================================================
// Checkpoint / Crash Recovery API
// ============================================================================

/// Checkpoint info returned to Dart
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckpointInfo {
    pub sequence_name: String,
    pub timestamp: String,
    pub completed_exposures: u32,
    pub completed_integration_secs: f64,
    pub can_resume: bool,
    pub age_seconds: i64,
}

impl From<nightshade_sequencer::CheckpointInfo> for CheckpointInfo {
    fn from(info: nightshade_sequencer::CheckpointInfo) -> Self {
        Self {
            sequence_name: info.sequence_name,
            timestamp: info.timestamp.to_rfc3339(),
            completed_exposures: info.completed_exposures,
            completed_integration_secs: info.completed_integration_secs,
            can_resume: info.can_resume,
            age_seconds: info.age_seconds,
        }
    }
}

/// Set the checkpoint directory for crash recovery
pub async fn sequencer_set_checkpoint_dir(path: String) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;
    exec.set_checkpoint_dir(path);
    Ok(())
}

/// Check if a recoverable checkpoint exists
#[flutter_rust_bridge::frb(sync)]
pub fn sequencer_has_recoverable_checkpoint() -> bool {
    let executor = get_executor();
    // Use try_read to avoid blocking if executor is busy
    if let Ok(exec) = executor.try_read() {
        exec.has_recoverable_checkpoint()
    } else {
        false
    }
}

/// Get info about the current checkpoint
#[flutter_rust_bridge::frb(sync)]
pub fn sequencer_get_checkpoint_info() -> Option<CheckpointInfo> {
    let executor = get_executor();
    if let Ok(exec) = executor.try_read() {
        exec.get_checkpoint_info().map(|i| i.into())
    } else {
        None
    }
}

/// Resume sequence from checkpoint
pub async fn sequencer_resume_from_checkpoint() -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;

    // Set up device ops before resume
    exec.set_device_ops(crate::sequencer_ops::create_device_ops());

    exec.resume_from_checkpoint()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Save current execution state as checkpoint
pub async fn sequencer_save_checkpoint() -> Result<(), NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;

    exec.save_checkpoint()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Clear checkpoint (call when sequence completes normally)
#[flutter_rust_bridge::frb(sync)]
pub fn sequencer_clear_checkpoint() -> Result<(), NightshadeError> {
    let executor = get_executor();
    if let Ok(exec) = executor.try_read() {
        exec.clear_checkpoint()
            .map_err(|e| NightshadeError::OperationFailed(e))
    } else {
        Err(NightshadeError::OperationFailed(
            "Failed to clear checkpoint because the sequencer executor is busy".to_string(),
        ))
    }
}

// ============================================================================
// Trigger Management API
// ============================================================================

/// Enable or disable a specific trigger by ID
pub async fn sequencer_set_trigger_enabled(
    trigger_id: String,
    enabled: bool,
) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;
    let trigger_manager = exec.trigger_manager();
    let mut manager = trigger_manager.write().await;
    manager.set_trigger_enabled(&trigger_id, enabled);
    tracing::info!(
        "Trigger '{}' {}",
        trigger_id,
        if enabled { "enabled" } else { "disabled" }
    );
    Ok(())
}

/// Enable or disable all triggers
pub async fn sequencer_set_all_triggers_enabled(enabled: bool) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;
    exec.set_triggers_enabled(enabled);
    tracing::info!(
        "All triggers {}",
        if enabled { "enabled" } else { "disabled" }
    );
    Ok(())
}

/// Get list of all configured triggers
pub async fn sequencer_get_triggers() -> Result<Vec<TriggerInfo>, NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;
    let trigger_manager = exec.trigger_manager();
    let manager = trigger_manager.read().await;

    let triggers = manager
        .triggers()
        .iter()
        .map(|t| TriggerInfo {
            id: t.id.clone(),
            name: t.name.clone(),
            enabled: t.enabled,
            trigger_type: format!("{:?}", t.trigger_type),
            recovery_action: format!("{:?}", t.recovery_action),
            cooldown_secs: t.cooldown_secs,
        })
        .collect();

    Ok(triggers)
}

/// Trigger information for Dart
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriggerInfo {
    pub id: String,
    pub name: String,
    pub enabled: bool,
    pub trigger_type: String,
    pub recovery_action: String,
    pub cooldown_secs: Option<u64>,
}

/// Update guiding RMS manually (for external guiding software integration)
pub async fn sequencer_update_guiding_rms(rms: f64) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;

    exec.update_trigger_state(|state| {
        state.update_guiding_rms(rms);
    })
    .await;

    Ok(())
}

/// Update HFR manually (for external image analysis integration)
pub async fn sequencer_update_hfr(hfr: f64) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;

    exec.update_trigger_state(|state| {
        state.update_hfr(hfr);
    })
    .await;

    Ok(())
}

// ============================================================================
// Runtime Settings Propagation API
// ============================================================================

/// Update dither configuration at runtime.
/// Updates the executor's stored dither parameters. Values are used by subsequent
/// trigger-initiated dithers and by any sequence checkpoint resume.
pub async fn sequencer_update_dither_config(
    pixels: f64,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
    ra_only: bool,
) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;
    exec.update_dither_config(pixels, settle_pixels, settle_time, settle_timeout, ra_only);
    Ok(())
}

/// Update observer location at runtime.
/// Updates the executor's stored latitude/longitude so altitude-based triggers
/// and time calculations use the correct location on next use.
pub async fn sequencer_update_location(
    latitude: Option<f64>,
    longitude: Option<f64>,
) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;
    exec.update_location(latitude, longitude);
    Ok(())
}

/// Update filter focus offsets at runtime.
/// Updates the executor's stored offsets so subsequent filter changes apply
/// the correct focus compensation on next trigger-initiated autofocus or sequence restart.
pub async fn sequencer_update_filter_offsets(
    offsets: std::collections::HashMap<String, i32>,
) -> Result<(), NightshadeError> {
    let executor = get_executor();
    let mut exec = executor.write().await;
    exec.update_filter_offsets(offsets);
    Ok(())
}

/// Reset HFR baseline (after successful autofocus or manual intervention)
pub async fn sequencer_reset_hfr_baseline() -> Result<(), NightshadeError> {
    let executor = get_executor();
    let exec = executor.read().await;

    exec.update_trigger_state(|state| {
        state.reset_baseline_hfr();
    })
    .await;

    Ok(())
}
