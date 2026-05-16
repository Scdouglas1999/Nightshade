// CQ-W3-API-RS: split from monolithic api.rs (audit-rust §9 / audit-arch §1.2)
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs (audit-rust §9).
use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
use crate::filter_matching::find_filter_match;
use crate::state::*;
use crate::storage::{AppSettings, ObserverLocation};
use crate::unified_device_ops::create_unified_device_ops;
use nightshade_imaging::{
    calculate_airmass, validate_fits_header, validate_image, write_fits, BayerPattern,
    DebayerAlgorithm, FitsHeader, ImageData,
};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::sync::RwLock;
// Sibling-module items via the parent's pub use re-exports.
use super::*;

// =============================================================================
// SEQUENCER API
// =============================================================================

use nightshade_sequencer::{
    mosaic::calculate_mosaic_panels, mosaic::MosaicPanel, AutofocusConfig, AutofocusMethod,
    Binning, CenterConfig, CoolConfig, DelayConfig, DitherConfig, DitherPattern, ExecutorEvent,
    ExecutorState, ExposureConfig, FilterConfig, LoopCondition, LoopConfig, MosaicConfig,
    NodeDefinition, NodeStatus, NodeType, NotificationConfig, NotificationLevel, RotatorConfig,
    ScriptConfig, SequenceDefinition, SequenceProgress, SlewConfig, TargetGroupConfig,
    TargetHeaderConfig, TwilightType, WaitTimeConfig, WarmConfig,
};

/// Get the global sequence executor instance
pub(crate) fn get_sequence_executor(
) -> &'static std::sync::Arc<tokio::sync::RwLock<nightshade_sequencer::SequenceExecutor>> {
    nightshade_sequencer::get_executor()
}

/// Sequencer state for Flutter
#[derive(Debug, Clone)]
pub struct SequencerState {
    pub state: String,
    pub current_node_id: Option<String>,
    pub current_node_name: Option<String>,
    pub total_exposures: u32,
    pub completed_exposures: u32,
    pub total_integration_secs: f64,
    pub elapsed_secs: f64,
    pub estimated_remaining_secs: Option<f64>,
    pub current_target: Option<String>,
    pub current_filter: Option<String>,
    pub message: Option<String>,
}

impl From<SequenceProgress> for SequencerState {
    fn from(p: SequenceProgress) -> Self {
        let state_str = match p.state {
            ExecutorState::Idle => "idle",
            ExecutorState::Running => "running",
            ExecutorState::Paused => "paused",
            ExecutorState::Stopping => "stopping",
            ExecutorState::Cancelled => "cancelled",
            ExecutorState::Completed => "completed",
            ExecutorState::Failed => "failed",
        };
        Self {
            state: state_str.to_string(),
            current_node_id: p.current_node_id,
            current_node_name: p.current_node_name,
            total_exposures: p.total_exposures,
            completed_exposures: p.completed_exposures,
            total_integration_secs: p.total_integration_secs,
            elapsed_secs: p.elapsed_secs,
            estimated_remaining_secs: p.estimated_remaining_secs,
            current_target: p.current_target,
            current_filter: p.current_filter,
            message: p.message,
        }
    }
}

/// Sequence definition for Flutter
#[derive(Debug, Clone)]
pub struct SequenceDefinitionApi {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub nodes: Vec<NodeDefinitionApi>,
    pub root_node_id: Option<String>,
}

/// Node definition for Flutter
#[derive(Debug, Clone)]
pub struct NodeDefinitionApi {
    pub id: String,
    pub name: String,
    pub node_type: String,
    pub enabled: bool,
    pub children: Vec<String>,
    pub config_json: String,
}

impl From<&NodeDefinition> for NodeDefinitionApi {
    fn from(n: &NodeDefinition) -> Self {
        let node_type = match &n.node_type {
            NodeType::TargetGroup(_) => "target_group",
            NodeType::TargetHeader(_) => "target_header",
            NodeType::Loop(_) => "loop",
            NodeType::Parallel(_) => "parallel",
            NodeType::Conditional(_) => "conditional",
            NodeType::Recovery(_) => "recovery",
            NodeType::SlewToTarget(_) => "slew",
            NodeType::CenterTarget(_) => "center",
            NodeType::TakeExposure(_) => "exposure",
            NodeType::Autofocus(_) => "autofocus",
            NodeType::Dither(_) => "dither",
            NodeType::ChangeFilter(_) => "filter_change",
            NodeType::CoolCamera(_) => "cool_camera",
            NodeType::WarmCamera(_) => "warm_camera",
            NodeType::PolarAlignment(_) => "polar_alignment",
            NodeType::MoveRotator(_) => "rotator",
            NodeType::Park => "park",
            NodeType::Unpark => "unpark",
            NodeType::WaitForTime(_) => "wait_time",
            NodeType::Delay(_) => "delay",
            NodeType::Notification(_) => "notification",
            NodeType::RunScript(_) => "script",
            NodeType::MeridianFlip(_) => "meridian_flip",
            NodeType::OpenDome(_) => "open_dome",
            NodeType::CloseDome(_) => "close_dome",
            NodeType::ParkDome(_) => "park_dome",
            NodeType::StartGuiding(_) => "start_guiding",
            NodeType::StopGuiding => "stop_guiding",
            NodeType::TemperatureCompensation(_) => "temperature_compensation",
            NodeType::Mosaic(_) => "mosaic",
            NodeType::FlatWizard(_) => "flat_wizard",
            NodeType::OpenCover(_) => "open_cover",
            NodeType::CloseCover(_) => "close_cover",
            NodeType::CalibratorOn(_) => "calibrator_on",
            NodeType::CalibratorOff(_) => "calibrator_off",
        };

        let config_json = match serde_json::to_string(&n.node_type) {
            Ok(json) => json,
            Err(e) => {
                tracing::error!("Failed to serialize node type for node '{}': {}", n.id, e);
                format!("{{\"error\":\"serialization failed: {}\"}}", e)
            }
        };

        Self {
            id: n.id.clone(),
            name: n.name.clone(),
            node_type: node_type.to_string(),
            enabled: n.enabled,
            children: n.children.clone(),
            config_json,
        }
    }
}

/// Load a sequence from JSON
pub async fn api_sequencer_load_json(json: String) -> Result<(), NightshadeError> {
    tracing::info!("Loading sequence from JSON");

    let definition: SequenceDefinition = serde_json::from_str(&json).map_err(|e| {
        NightshadeError::InvalidInput(format!("Failed to parse sequence JSON: {}", e))
    })?;

    let mut executor = get_sequence_executor().write().await;
    executor
        .load_sequence(definition)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to load sequence: {}", e)))?;

    tracing::info!("Sequence loaded successfully");
    Ok(())
}

/// Load a sequence from a definition struct
pub async fn api_sequencer_load(definition: SequenceDefinitionApi) -> Result<(), NightshadeError> {
    tracing::info!("Loading sequence: {}", definition.name);

    // Convert API nodes to internal nodes
    let nodes: Result<Vec<NodeDefinition>, NightshadeError> = definition
        .nodes
        .iter()
        .map(|n| {
            let node_type: NodeType = serde_json::from_str(&n.config_json).map_err(|e| {
                NightshadeError::InvalidInput(format!("Invalid node config: {}", e))
            })?;

            Ok(NodeDefinition {
                id: n.id.clone(),
                name: n.name.clone(),
                node_type,
                enabled: n.enabled,
                children: n.children.clone(),
            })
        })
        .collect();

    let internal_definition = SequenceDefinition {
        id: definition.id,
        name: definition.name,
        description: definition.description,
        nodes: nodes?,
        root_node_id: definition.root_node_id,
        metadata: std::collections::HashMap::new(),
    };

    let mut executor = get_sequence_executor().write().await;
    executor
        .load_sequence(internal_definition)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to load sequence: {}", e)))?;

    Ok(())
}

/// Start the sequence executor
pub async fn api_sequencer_start() -> Result<(), NightshadeError> {
    tracing::info!("Starting sequence execution");

    let mut executor = get_sequence_executor().write().await;
    executor.start().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to start sequence: {}", e))
    })?;

    // Publish event
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Started {
            sequence_name: "Sequence".to_string(),
        }),
    ));

    Ok(())
}

/// Pause the sequence executor
pub async fn api_sequencer_pause() -> Result<(), NightshadeError> {
    tracing::info!("Pausing sequence execution");

    let executor = get_sequence_executor().read().await;
    executor.pause().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to pause sequence: {}", e))
    })?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Paused),
    ));

    Ok(())
}

/// Resume the sequence executor
pub async fn api_sequencer_resume() -> Result<(), NightshadeError> {
    tracing::info!("Resuming sequence execution");

    let executor = get_sequence_executor().read().await;
    executor.resume().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to resume sequence: {}", e))
    })?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Resumed),
    ));

    Ok(())
}

/// Stop the sequence executor
pub async fn api_sequencer_stop() -> Result<(), NightshadeError> {
    tracing::info!("Stopping sequence execution");

    let mut executor = get_sequence_executor().write().await;
    executor
        .stop()
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to stop sequence: {}", e)))?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Stopped),
    ));

    Ok(())
}

/// Skip to the next instruction
pub async fn api_sequencer_skip() -> Result<(), NightshadeError> {
    tracing::info!("Skipping current instruction");

    let executor = get_sequence_executor().read().await;
    executor
        .skip()
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to skip: {}", e)))?;

    Ok(())
}

/// Reset the sequence executor
pub async fn api_sequencer_reset() -> Result<(), NightshadeError> {
    tracing::info!("Resetting sequence executor");

    let mut executor = get_sequence_executor().write().await;
    executor.reset().await;

    Ok(())
}

/// Get the current sequencer state
pub async fn api_sequencer_get_state() -> SequencerState {
    let executor = get_sequence_executor().read().await;
    let progress = executor.get_progress();
    SequencerState::from(progress)
}

/// Subscribe to sequencer events and forward them to the main event stream
pub async fn api_sequencer_subscribe_events() -> Result<(), NightshadeError> {
    // Validate the executor is reachable before spawning the supervisor so a
    // bad caller still gets an error synchronously. Drop the lock immediately
    // — the supervisor takes a fresh one on every restart.
    {
        let _executor = get_sequence_executor().read().await;
    }
    let state = get_state().clone();

    tracing::info!("[EVENT_SUB] Sequencer event subscription started");

    // The event bridge MUST stay alive for the lifetime of the UI; losing
    // it silently means the user sees zero sequencer updates with no error.
    // Supervise with restart-on-panic and exponential backoff.
    crate::util::supervisor::spawn_supervised_restart(
        "sequencer_event_bridge",
        crate::util::supervisor::RestartPolicy::DEFAULT,
        move || {
            let state = state.clone();
            async move {
                let mut rx = {
                    let executor = get_sequence_executor().read().await;
                    executor.subscribe()
                };
                tracing::info!("[EVENT_SUB] Event listener task spawned");
                run_sequencer_event_loop(&mut rx, &state).await;
            }
        },
        Some(|msg: &str| {
            tracing::error!(
                target: "supervisor",
                "sequencer_event_bridge exhausted restart budget; UI will stop receiving sequencer events. Last panic: {msg}"
            );
        }),
    );

    Ok(())
}

/// Inner event-loop body for [`api_sequencer_subscribe_events`].
/// Pulled out so the supervisor factory can call it on every restart.
pub(crate) async fn run_sequencer_event_loop(
    rx: &mut tokio::sync::broadcast::Receiver<ExecutorEvent>,
    state: &SharedAppState,
) {
    loop {
        let event = match rx.recv().await {
            Ok(ev) => ev,
            Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                tracing::warn!(
                    "[EVENT_SUB] Lagged behind sequencer; skipped {} events",
                    skipped
                );
                continue;
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                tracing::info!("[EVENT_SUB] Sequencer event channel closed; bridge exiting");
                return;
            }
        };
        {
            tracing::debug!(
                "[EVENT_SUB] Received event: {:?}",
                std::mem::discriminant(&event)
            );
            let nightshade_event = match &event {
                ExecutorEvent::StateChanged(s) => {
                    let _state_str = match s {
                        ExecutorState::Running => "running",
                        ExecutorState::Paused => "paused",
                        ExecutorState::Cancelled => "cancelled",
                        ExecutorState::Completed => "completed",
                        _ => continue,
                    };
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(match s {
                            ExecutorState::Paused => SequencerEvent::Paused,
                            ExecutorState::Cancelled => SequencerEvent::Stopped,
                            ExecutorState::Completed => SequencerEvent::Completed,
                            _ => continue,
                        }),
                    ))
                }
                ExecutorEvent::NodeStarted { id, name } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::NodeStarted {
                        node_id: id.clone(),
                        node_type: name.clone(),
                    }),
                )),
                ExecutorEvent::NodeCompleted { id, status } => {
                    let status_str = match status {
                        NodeStatus::Success => "success",
                        NodeStatus::Failure => "failed",
                        NodeStatus::Skipped => "skipped",
                        _ => "failed",
                    };
                    let severity = match status {
                        NodeStatus::Failure => EventSeverity::Warning,
                        _ => EventSeverity::Info,
                    };
                    Some(create_event_auto_id(
                        severity,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::NodeCompleted {
                            node_id: id.clone(),
                            status: status_str.to_string(),
                        }),
                    ))
                }
                ExecutorEvent::ProgressUpdated(progress) => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Progress {
                        current: progress.completed_exposures,
                        total: progress.total_exposures,
                    }),
                )),
                ExecutorEvent::SequenceCompleted => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Completed),
                )),
                ExecutorEvent::SequenceFailed { error } => Some(create_event_auto_id(
                    EventSeverity::Error,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Error {
                        message: error.clone(),
                    }),
                )),
                ExecutorEvent::ExposureStarted {
                    frame,
                    total,
                    filter,
                    duration_secs,
                } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::ExposureStarted {
                        frame: *frame,
                        total: *total,
                        filter: filter.clone(),
                        duration_secs: *duration_secs,
                    }),
                )),
                ExecutorEvent::ExposureCompleted {
                    frame,
                    total,
                    duration_secs,
                } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::ExposureCompleted {
                        frame: *frame,
                        total: *total,
                        duration_secs: *duration_secs,
                    }),
                )),
                ExecutorEvent::TargetStarted { name, ra, dec } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::TargetChanged {
                        target_name: name.clone(),
                        ra: Some(*ra),
                        dec: Some(*dec),
                    }),
                )),
                ExecutorEvent::TargetCompleted { name } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::TargetCompleted {
                        target_name: name.clone(),
                    }),
                )),
                ExecutorEvent::NodeProgress {
                    node_id,
                    instruction,
                    progress_percent,
                    detail,
                } => {
                    tracing::info!(
                        "[EVENT_SUB] NodeProgress received: node={}, instruction={}, progress={}%",
                        node_id,
                        instruction,
                        progress_percent
                    );
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::InstructionProgress {
                            node_id: node_id.clone(),
                            instruction: instruction.clone(),
                            progress_percent: *progress_percent,
                            detail: detail.clone(),
                        }),
                    ))
                }
                ExecutorEvent::Error { message } => Some(create_event_auto_id(
                    EventSeverity::Error,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Error {
                        message: message.clone(),
                    }),
                )),
                ExecutorEvent::TriggerFired {
                    trigger_id,
                    trigger_name,
                    action,
                } => {
                    tracing::info!(
                        "Trigger fired: {} ({}) - {}",
                        trigger_name,
                        trigger_id,
                        action
                    );
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::TriggerFired {
                            trigger_id: trigger_id.clone(),
                            trigger_name: trigger_name.clone(),
                            action: action.clone(),
                        }),
                    ))
                }
                ExecutorEvent::RuntimeConfigUpdated { what } => {
                    // Audit §1.8: surface runtime-config updates as a generic
                    // sequencer Error event with informational severity so the
                    // existing UI subscriber sees the change without needing
                    // a new typed payload (a typed payload would require an
                    // FRB regen).
                    tracing::info!("[EVENT_SUB] Runtime config updated: {}", what);
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::Error {
                            message: format!("Runtime config updated: {}", what),
                        }),
                    ))
                }
            };

            if let Some(e) = nightshade_event {
                state.publish_event(e);
            }
        }
    }
}

/// Stream of sequencer events (separate from main event stream for real-time progress)
#[flutter_rust_bridge::frb(ignore)]
pub fn api_sequencer_event_stream() -> impl futures::Stream<Item = String> {
    let rx = {
        let executor = get_sequence_executor().blocking_read();
        executor.subscribe()
    };

    async_stream::stream! {
        let mut rx = rx;
        loop {
            match rx.recv().await {
                Ok(event) => {
                    if let Ok(json) = serde_json::to_string(&event) {
                        yield json;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    // Update the global dropped event counter
                    let previous_total = TOTAL_DROPPED_EVENTS.fetch_add(n, Ordering::Relaxed);
                    let new_total = previous_total + n;

                    tracing::warn!(
                        "[SEQUENCER_EVENT_STREAM] Event stream lagged! Skipped {} events (total dropped: {}). \
                        Consider increasing buffer size or optimizing event handling.",
                        n, new_total
                    );
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    break;
                }
            }
        }
    }
}

// =============================================================================
// SEQUENCER CHECKPOINT / CRASH RECOVERY
// =============================================================================

/// Checkpoint info returned to Dart
#[derive(Debug, Clone)]
pub struct CheckpointInfoApi {
    pub sequence_name: String,
    pub timestamp: String,
    pub completed_exposures: u32,
    pub completed_integration_secs: f64,
    pub can_resume: bool,
    pub age_seconds: i64,
}

/// Set the checkpoint directory for crash recovery
pub async fn api_sequencer_set_checkpoint_dir(path: String) -> Result<(), NightshadeError> {
    tracing::info!("Setting checkpoint directory to: {}", path);
    let mut executor = get_sequence_executor().write().await;
    executor.set_checkpoint_dir(path);
    Ok(())
}

/// Check if a recoverable checkpoint exists
pub fn api_sequencer_has_checkpoint() -> bool {
    let executor = get_sequence_executor().blocking_read();
    executor.has_recoverable_checkpoint()
}

/// Get info about the current checkpoint
pub fn api_sequencer_get_checkpoint_info() -> Option<CheckpointInfoApi> {
    let executor = get_sequence_executor().blocking_read();
    executor
        .get_checkpoint_info()
        .map(|info| CheckpointInfoApi {
            sequence_name: info.sequence_name,
            timestamp: info.timestamp.to_rfc3339(),
            completed_exposures: info.completed_exposures,
            completed_integration_secs: info.completed_integration_secs,
            can_resume: info.can_resume,
            age_seconds: info.age_seconds,
        })
}

/// Resume sequence from checkpoint
pub async fn api_sequencer_resume_from_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Resuming sequence from checkpoint");
    let mut executor = get_sequence_executor().write().await;

    // Set up device ops before resume - use UnifiedDeviceOps which routes through DeviceManager
    let ops = create_unified_device_ops();
    executor.set_device_ops(ops);

    executor
        .resume_from_checkpoint()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Save current execution state as checkpoint
pub async fn api_sequencer_save_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Saving checkpoint");
    let executor = get_sequence_executor().read().await;
    executor
        .save_checkpoint()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Clear/discard checkpoint (call when sequence completes normally or user discards)
pub fn api_sequencer_clear_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Clearing checkpoint");
    let executor = get_sequence_executor().blocking_read();
    executor
        .clear_checkpoint()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set simulation mode (use mock devices instead of real hardware)
pub async fn api_sequencer_set_simulation_mode(enabled: bool) -> Result<(), NightshadeError> {
    tracing::info!("Setting sequencer simulation mode: {}", enabled);
    let mut executor = get_sequence_executor().write().await;

    // Production/release artifacts must not execute simulated hardware paths.
    if enabled && !cfg!(debug_assertions) {
        return Err(NightshadeError::NotSupported {
            device_id: "sequencer".to_string(),
            operation: "set_simulation_mode(true)".to_string(),
        });
    }

    if enabled {
        // Use NullDeviceOps for simulation
        executor.set_device_ops(std::sync::Arc::new(nightshade_sequencer::NullDeviceOps));
    } else {
        // Use UnifiedDeviceOps which routes through DeviceManager for real hardware
        let ops = create_unified_device_ops();
        executor.set_device_ops(ops);
    }

    Ok(())
}

/// Set connected devices for the sequencer
pub async fn api_sequencer_set_devices(
    camera_id: Option<String>,
    mount_id: Option<String>,
    focuser_id: Option<String>,
    filterwheel_id: Option<String>,
    rotator_id: Option<String>,
    filter_names: Option<Vec<String>>,
    filter_focus_offsets: Option<std::collections::HashMap<String, i32>>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Setting sequencer devices: camera={:?}, mount={:?}, focuser={:?}, filterwheel={:?}, rotator={:?}, filter_names={:?}, filter_focus_offsets={:?}",
        camera_id, mount_id, focuser_id, filterwheel_id, rotator_id, filter_names, filter_focus_offsets
    );
    let filterwheel_for_names = filterwheel_id.clone();
    {
        let mut executor = get_sequence_executor().write().await;
        executor.set_devices(camera_id, mount_id, focuser_id, filterwheel_id, rotator_id);
        if let Some(offsets) = filter_focus_offsets {
            executor.set_filter_focus_offsets(offsets);
        }
    }

    if let Some(names) = filter_names {
        if names.is_empty() {
            return Err(NightshadeError::InvalidParameter(
                "filter_names was provided but empty; provide at least one name or pass null."
                    .to_string(),
            ));
        }

        let filterwheel_id = filterwheel_for_names.ok_or_else(|| {
            NightshadeError::InvalidParameter(
                "filter_names was provided but filterwheel_id is null. Provide a filter wheel ID before setting filter names."
                    .to_string(),
            )
        })?;

        let mgr = get_device_manager();
        mgr.filter_wheel_set_filter_names(&filterwheel_id, names)
            .await
            .map_err(|e| {
                NightshadeError::OperationFailed(format!(
                    "Failed to apply filter names to '{}': {}",
                    filterwheel_id, e
                ))
            })?;
    }

    Ok(())
}

/// Set the safety fail mode for the sequencer.
/// This determines behavior when safety devices fail or are unavailable:
/// - "fail_closed": Treat unavailable safety data as unsafe (enforced)
/// - "fail_open"/"warn_only": accepted for backward compatibility and coerced to fail_closed
pub async fn api_sequencer_set_safety_fail_mode(mode: String) -> Result<(), NightshadeError> {
    use nightshade_sequencer::SafetyFailMode;

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

    tracing::info!("Setting sequencer safety fail mode: {:?}", fail_mode);
    let mut executor = get_sequence_executor().write().await;
    executor.set_safety_fail_mode(fail_mode);

    Ok(())
}

/// Set the save path for sequencer images.
/// This is the base directory where captured images will be saved.
/// If not set (or set to None), images will NOT be saved to disk.
pub async fn api_sequencer_set_save_path(path: Option<String>) -> Result<(), NightshadeError> {
    let path_display = path.as_deref().unwrap_or("<none>");
    tracing::info!("Setting sequencer save path: {}", path_display);

    let mut executor = get_sequence_executor().write().await;
    executor.set_save_path(path.map(std::path::PathBuf::from));

    Ok(())
}

// =============================================================================
// SEQUENCER RUNTIME SETTINGS PROPAGATION
// =============================================================================

/// Update dither configuration at runtime while a sequence is running or paused.
/// The updated values are stored on the executor and will be used by subsequent
/// trigger-initiated dithers and checkpoint resumes.
pub async fn api_sequencer_update_dither_config(
    pixels: f64,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
    ra_only: bool,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer dither config: pixels={}, settle_pixels={}, settle_time={}, settle_timeout={}, ra_only={}",
        pixels, settle_pixels, settle_time, settle_timeout, ra_only
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_dither_config(pixels, settle_pixels, settle_time, settle_timeout, ra_only);
    Ok(())
}

/// Update observer location at runtime while a sequence is running or paused.
/// Updates the executor's stored latitude/longitude so altitude-based triggers
/// use the correct location on their next evaluation.
pub async fn api_sequencer_update_location(
    latitude: Option<f64>,
    longitude: Option<f64>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer location: lat={:?}, lon={:?}",
        latitude,
        longitude
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_location(latitude, longitude);
    Ok(())
}

/// Update filter focus offsets at runtime while a sequence is running or paused.
/// Updates the executor's stored offsets so subsequent filter changes apply
/// the correct focus compensation.
pub async fn api_sequencer_update_filter_offsets(
    offsets: std::collections::HashMap<String, i32>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer filter focus offsets: {} entries",
        offsets.len()
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_filter_offsets(offsets);
    Ok(())
}

// =============================================================================
// SEQUENCER NODE FACTORY - Create nodes programmatically
// =============================================================================

pub(crate) fn serialize_node_definition(node: &NodeDefinition) -> Result<String, NightshadeError> {
    serde_json::to_string(node).map_err(|e| {
        NightshadeError::SerializationError(format!(
            "Failed to serialize node '{}' ({}): {}",
            node.name, node.id, e
        ))
    })
}

pub(crate) fn serialize_sequence_definition(
    definition: &SequenceDefinition,
) -> Result<String, NightshadeError> {
    serde_json::to_string(definition).map_err(|e| {
        NightshadeError::SerializationError(format!(
            "Failed to serialize sequence '{}' ({}): {}",
            definition.name, definition.id, e
        ))
    })
}

/// Create an exposure node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_exposure_node(
    id: String,
    name: String,
    duration_secs: f64,
    count: u32,
    filter: Option<String>,
    filter_index: Option<i32>,
    gain: Option<i32>,
    offset: Option<i32>,
    binning: i32,
    dither_every: Option<u32>,
) -> Result<String, NightshadeError> {
    let binning_enum = match binning {
        1 => Binning::One,
        2 => Binning::Two,
        3 => Binning::Three,
        4 => Binning::Four,
        _ => Binning::One,
    };

    let config = ExposureConfig {
        duration_secs,
        count,
        filter,
        filter_index,
        gain,
        offset,
        binning: binning_enum,
        dither_every,
        dither_pixels: 5.0,
        dither_settle_pixels: 1.5,
        dither_settle_time: 30.0,
        dither_settle_timeout: 120.0,
        dither_ra_only: false,
        save_to: None,
        triggers: Vec::new(),
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TakeExposure(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a slew node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_slew_node(
    id: String,
    name: String,
    use_target_coords: u8,
    custom_ra: Option<f64>,
    custom_dec: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = SlewConfig {
        use_target_coords: use_target_coords != 0,
        custom_ra,
        custom_dec,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::SlewToTarget(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a center node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_center_node(
    id: String,
    name: String,
    use_target_coords: u8,
    accuracy_arcsec: f64,
    max_attempts: u32,
    exposure_duration: f64,
) -> Result<String, NightshadeError> {
    let config = CenterConfig {
        use_target_coords: use_target_coords != 0,
        custom_ra: None,
        custom_dec: None,
        accuracy_arcsec,
        max_attempts,
        exposure_duration,
        filter: None,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::CenterTarget(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create an autofocus node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_autofocus_node(
    id: String,
    name: String,
    step_size: i32,
    steps_out: u32,
    exposure_duration: f64,
    method: String,
) -> Result<String, NightshadeError> {
    let method_enum = match method.as_str() {
        "vcurve" => AutofocusMethod::VCurve,
        "quadratic" => AutofocusMethod::Quadratic,
        "hyperbolic" => AutofocusMethod::Hyperbolic,
        _ => AutofocusMethod::VCurve,
    };

    let config = AutofocusConfig {
        method: method_enum,
        step_size,
        steps_out,
        exposure_duration,
        filter: None,
        binning: Binning::One,
        max_duration_secs: 600.0,
        ..AutofocusConfig::default()
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Autofocus(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a filter change node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_filter_node(
    id: String,
    name: String,
    filter_name: String,
) -> Result<String, NightshadeError> {
    let config = FilterConfig {
        filter_name,
        filter_index: None,
        timeout_secs: None, // Use default timeout
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::ChangeFilter(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a target group node configuration (legacy - use target_header instead)
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_target_group_node(
    id: String,
    name: String,
    target_name: String,
    ra_hours: f64,
    dec_degrees: f64,
    rotation: Option<f64>,
    min_altitude: Option<f64>,
    max_altitude: Option<f64>,
    priority: i32,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let config = TargetGroupConfig {
        target_name,
        ra_hours,
        dec_degrees,
        rotation,
        min_altitude,
        max_altitude,
        priority,
        ..Default::default()
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TargetGroup(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a target header node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_target_header_node(
    id: String,
    name: String,
    target_name: String,
    ra_hours: f64,
    dec_degrees: f64,
    rotation: Option<f64>,
    min_altitude: Option<f64>,
    max_altitude: Option<f64>,
    priority: i32,
    start_after: Option<i64>,
    end_before: Option<i64>,
    mosaic_panel_json: Option<String>,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let mosaic_panel = mosaic_panel_json
        .map(|json| {
            serde_json::from_str(&json).map_err(|e| {
                NightshadeError::SerializationError(format!(
                    "Invalid target header mosaic panel JSON: {}",
                    e
                ))
            })
        })
        .transpose()?;

    let config = TargetHeaderConfig {
        target_name,
        ra_hours,
        dec_degrees,
        rotation,
        min_altitude,
        max_altitude,
        priority,
        start_after,
        end_before,
        mosaic_panel,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TargetHeader(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a loop node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_loop_node(
    id: String,
    name: String,
    iterations: Option<u32>,
    condition: String,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let condition_enum = match condition.as_str() {
        "count" => LoopCondition::Count,
        "until_time" => LoopCondition::UntilTime,
        "altitude_below" => LoopCondition::AltitudeBelow,
        "altitude_above" => LoopCondition::AltitudeAbove,
        "integration_time" => LoopCondition::IntegrationTime,
        _ => LoopCondition::Count,
    };

    let config = LoopConfig {
        iterations,
        condition: condition_enum,
        condition_value: None,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Loop(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a delay node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_delay_node(
    id: String,
    name: String,
    seconds: f64,
) -> Result<String, NightshadeError> {
    let config = DelayConfig { seconds };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Delay(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a park node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_park_node(id: String, name: String) -> Result<String, NightshadeError> {
    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Park,
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create an unpark node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_unpark_node(id: String, name: String) -> Result<String, NightshadeError> {
    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Unpark,
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a cool camera node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_cool_camera_node(
    id: String,
    name: String,
    target_temp: f64,
    duration_mins: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = CoolConfig {
        target_temp,
        duration_mins,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::CoolCamera(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a warm camera node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_warm_camera_node(
    id: String,
    name: String,
    rate_per_min: f64,
    target_temp: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = WarmConfig {
        rate_per_min,
        target_temp,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::WarmCamera(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a dither node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_dither_node(
    id: String,
    name: String,
    pixels: f64,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
    ra_only: u8,
) -> Result<String, NightshadeError> {
    let config = DitherConfig {
        pixels,
        settle_pixels,
        settle_time,
        settle_timeout,
        ra_only: ra_only != 0,
        pattern: DitherPattern::default(),
        grid_size: 3,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Dither(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a wait time node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_wait_time_node(
    id: String,
    name: String,
    wait_until: Option<i64>,
    twilight_type: Option<String>,
) -> Result<String, NightshadeError> {
    let twilight = twilight_type.and_then(|t| match t.as_str() {
        "civil" => Some(TwilightType::Civil),
        "nautical" => Some(TwilightType::Nautical),
        "astronomical" => Some(TwilightType::Astronomical),
        _ => None,
    });

    let config = WaitTimeConfig {
        wait_until,
        wait_for_twilight: twilight,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::WaitForTime(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a notification node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_notification_node(
    id: String,
    name: String,
    title: String,
    message: String,
    level: String,
) -> Result<String, NightshadeError> {
    let level_enum = match level.as_str() {
        "info" => NotificationLevel::Info,
        "warning" => NotificationLevel::Warning,
        "error" => NotificationLevel::Error,
        "success" => NotificationLevel::Success,
        _ => NotificationLevel::Info,
    };

    let config = NotificationConfig {
        title,
        message,
        level: level_enum,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Notification(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a script node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_script_node(
    id: String,
    name: String,
    script_path: String,
    arguments: Vec<String>,
    timeout_secs: Option<u32>,
) -> Result<String, NightshadeError> {
    let config = ScriptConfig {
        script_path,
        arguments,
        timeout_secs,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::RunScript(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a rotator node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_rotator_node(
    id: String,
    name: String,
    target_angle: f64,
    relative: u8,
) -> Result<String, NightshadeError> {
    let config = RotatorConfig {
        target_angle,
        relative: relative != 0,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::MoveRotator(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Build a complete sequence definition from nodes
#[flutter_rust_bridge::frb(sync)]
pub fn api_build_sequence(
    id: String,
    name: String,
    description: Option<String>,
    node_jsons: Vec<String>,
    root_node_id: Option<String>,
) -> Result<String, NightshadeError> {
    let nodes: Result<Vec<NodeDefinition>, NightshadeError> = node_jsons
        .iter()
        .enumerate()
        .map(|(index, json)| {
            serde_json::from_str(json).map_err(|e| {
                NightshadeError::SerializationError(format!(
                    "Failed to deserialize node_jsons[{}]: {}",
                    index, e
                ))
            })
        })
        .collect();

    let definition = SequenceDefinition {
        id,
        name,
        description,
        nodes: nodes?,
        root_node_id,
        metadata: std::collections::HashMap::new(),
    };

    serialize_sequence_definition(&definition)
}

#[cfg(test)]
mod sequencer_node_factory_tests {
    use super::{
        api_build_sequence, api_create_filter_node, api_create_target_header_node, NodeDefinition,
        SequenceDefinition,
    };

    #[test]
    fn build_sequence_returns_error_for_invalid_node_json() {
        let err = api_build_sequence(
            "seq-1".to_string(),
            "Test".to_string(),
            None,
            vec!["{not-json}".to_string()],
            None,
        )
        .expect_err("invalid node JSON should be rejected");

        assert!(err
            .to_string()
            .contains("Failed to deserialize node_jsons[0]"));
    }

    #[test]
    fn target_header_rejects_invalid_mosaic_panel_json() {
        let err = api_create_target_header_node(
            "node-1".to_string(),
            "Target".to_string(),
            "M31".to_string(),
            0.5,
            41.0,
            None,
            None,
            None,
            1,
            None,
            None,
            Some("{invalid}".to_string()),
            vec![],
        )
        .expect_err("invalid mosaic JSON should be rejected");

        assert!(err
            .to_string()
            .contains("Invalid target header mosaic panel JSON"));
    }

    #[test]
    fn build_sequence_preserves_valid_nodes() {
        let filter_json =
            api_create_filter_node("node-1".to_string(), "Filter".to_string(), "L".to_string())
                .expect("filter node should serialize");

        let sequence_json = api_build_sequence(
            "seq-1".to_string(),
            "Test".to_string(),
            None,
            vec![filter_json],
            Some("node-1".to_string()),
        )
        .expect("valid sequence should serialize");

        let sequence: SequenceDefinition =
            serde_json::from_str(&sequence_json).expect("sequence JSON should deserialize");
        assert_eq!(sequence.nodes.len(), 1);

        let node: &NodeDefinition = &sequence.nodes[0];
        assert_eq!(node.id, "node-1");
    }
}

// =============================================================================
// Mosaic Calculation
// =============================================================================

/// Result structure for mosaic panel calculations (FFI-safe)
#[derive(Debug, Clone)]
pub struct MosaicPanelResult {
    pub ra_hours: f64,
    pub dec_degrees: f64,
    pub panel_index: u32,
    pub row: u32,
    pub col: u32,
}

impl From<MosaicPanel> for MosaicPanelResult {
    fn from(panel: MosaicPanel) -> Self {
        Self {
            ra_hours: panel.ra_hours,
            dec_degrees: panel.dec_degrees,
            panel_index: panel.panel_index,
            row: panel.row,
            col: panel.col,
        }
    }
}

/// Calculate mosaic panel positions given center coordinates and configuration
///
/// # Arguments
/// * `center_ra` - Center RA in hours (0-24)
/// * `center_dec` - Center Dec in degrees (-90 to +90)
/// * `panel_width_arcmin` - Panel width in arcminutes
/// * `panel_height_arcmin` - Panel height in arcminutes
/// * `overlap_percent` - Overlap percentage (0-50)
/// * `rotation` - Rotation angle in degrees
/// * `panels_horizontal` - Number of horizontal panels
/// * `panels_vertical` - Number of vertical panels
///
/// # Returns
/// Vector of MosaicPanelResult with calculated RA/Dec for each panel
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_mosaic_panels(
    center_ra: f64,
    center_dec: f64,
    panel_width_arcmin: f64,
    panel_height_arcmin: f64,
    overlap_percent: f64,
    rotation: f64,
    panels_horizontal: u32,
    panels_vertical: u32,
) -> Vec<MosaicPanelResult> {
    let config = MosaicConfig {
        center_ra,
        center_dec,
        panel_width_arcmin,
        panel_height_arcmin,
        overlap_percent,
        rotation,
        panels_horizontal,
        panels_vertical,
        ..MosaicConfig::default()
    };

    calculate_mosaic_panels(&config)
        .into_iter()
        .map(MosaicPanelResult::from)
        .collect()
}

/// Calculate total mosaic coverage area in square degrees
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_mosaic_area(
    panel_width_arcmin: f64,
    panel_height_arcmin: f64,
    panels_horizontal: u32,
    panels_vertical: u32,
) -> f64 {
    // Why (audit-rust §1.4): u32 → f64 widening, exact (f64 mantissa covers
    // all u32 values).
    let total_width_arcmin = panel_width_arcmin * f64::from(panels_horizontal);
    let total_height_arcmin = panel_height_arcmin * f64::from(panels_vertical);
    // Return in square degrees
    (total_width_arcmin / 60.0) * (total_height_arcmin / 60.0)
}

/// Estimate total imaging time for mosaic in seconds
///
/// # Arguments
/// * `total_panels` - Total number of panels
/// * `exposure_secs` - Exposure time per frame
/// * `exposures_per_panel` - Number of exposures per panel
/// * `overhead_per_panel_secs` - Overhead per panel (slew, center, settle) - defaults to 60s if 0
#[flutter_rust_bridge::frb(sync)]
pub fn api_estimate_mosaic_time(
    total_panels: u32,
    exposure_secs: f64,
    exposures_per_panel: u32,
    overhead_per_panel_secs: f64,
) -> f64 {
    let overhead = if overhead_per_panel_secs <= 0.0 {
        60.0
    } else {
        overhead_per_panel_secs
    };
    // Why (audit-rust §1.4): u32 → f64 widening, exact.
    let time_per_panel = exposure_secs * f64::from(exposures_per_panel) + overhead;
    f64::from(total_panels) * time_per_panel
}

/// Calculate altitude for a target at a specific time and observer location
///
/// # Arguments
/// * `ra_hours` - Right Ascension in hours (0-24)
/// * `dec_degrees` - Declination in degrees (-90 to +90)
/// * `latitude` - Observer's latitude in degrees (-90 to +90, positive is north)
/// * `longitude` - Observer's longitude in degrees (-180 to +180, positive is east)
/// * `time_unix_millis` - UTC time as Unix timestamp in milliseconds
///
/// # Returns
/// Altitude in degrees above the horizon (-90 to +90)
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_altitude(
    ra_hours: f64,
    dec_degrees: f64,
    latitude: f64,
    longitude: f64,
    time_unix_millis: i64,
) -> f64 {
    use chrono::{TimeZone, Utc};

    // Convert Unix milliseconds to DateTime<Utc>
    let time = Utc
        .timestamp_millis_opt(time_unix_millis)
        .single()
        .unwrap_or_else(|| Utc::now());

    nightshade_sequencer::meridian::calculate_altitude(
        ra_hours,
        dec_degrees,
        latitude,
        longitude,
        time,
    )
}