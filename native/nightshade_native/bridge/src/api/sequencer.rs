// split from monolithic api.rs
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs.
use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
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
            // Recovery Mode — new first-class state. The string
            // mirror is kept stable so any subscriber that switches on
            // `state.state == "recovering"` can render the Run Dashboard
            // LED without a typed enum import.
            ExecutorState::Recovering => "recovering",
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
            // TargetScheduler — dynamic target picker container.
            NodeType::TargetScheduler(_) => "target_scheduler",
            // SmartExposure — multi-filter container instruction.
            NodeType::SmartExposure(_) => "smart_exposure",
            // PluginNode — plugin-dispatched instruction.
            NodeType::PluginNode { .. } => "plugin_node",
            // LiveStacking — broadcast / EAA node.
            NodeType::LiveStacking(_) => "live_stacking",
            // Science: SciencePhotometry — cadence-enforced
            // photometric capture for variable-star / exoplanet
            // timing.
            NodeType::SciencePhotometry(_) => "science_photometry",
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

/// Seed the executor's observing site from app settings when nothing has
/// pushed one yet.
///
/// The executor's `latitude`/`longitude` is what every frame's `OBJCTALT` /
/// `AIRMASS` cards AND the `captured_images.mount_altitude` column are derived
/// from, and until now the only writer was Dart's `sequencerUpdateLocation`.
/// A run started before that push landed produced frames whose FITS header had
/// AIRMASS — the writer has its own fallback to app settings, see
/// `sequencer_ops::context_altitude_pointing` — while the database row for the
/// same frame had a NULL altitude, because the row is stamped from the
/// sequencer's context and nothing folds the writer's fallback back into it.
/// The AAVSO exporter reads the row, so it submitted `na` in the AMASS column
/// for frames whose own header knew the answer.
///
/// Fills in rather than overwrites: a location explicitly pushed for this run
/// stays authoritative.
async fn seed_executor_site_from_settings(executor: &mut nightshade_sequencer::SequenceExecutor) {
    if executor.latitude.is_some() && executor.longitude.is_some() {
        return;
    }
    if let Ok(Some(site)) = get_state().get_observer_location() {
        executor
            .update_location(Some(site.latitude), Some(site.longitude))
            .await;
    }
}

/// Start the sequence executor
pub async fn api_sequencer_start() -> Result<(), NightshadeError> {
    tracing::info!("Starting sequence execution");

    let mut executor = get_sequence_executor().write().await;
    seed_executor_site_from_settings(&mut executor).await;
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

    // tear down any active LiveStacking broadcast so a
    // stopped sequence does not leave a stale `/broadcast` page
    // advertising itself as live. Same lifecycle the rest of the
    // sequencer-singleton state (TriggerState, BudgetRegistry, …)
    // already follows on stop.
    if nightshade_sequencer::broadcast::deactivate().is_some() {
        tracing::info!("LiveStacking broadcast deactivated on sequence stop");
    }

    // Dual-rig — stop any piggybacking secondary capture loop so a stopped
    // primary sequence doesn't leave the secondary camera exposing forever.
    if let Err(e) = crate::api::secondary_rig::api_secondary_rig_stop().await {
        tracing::warn!("Failed to stop secondary rig on sequence stop: {}", e);
    }

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

/// trust-patch §7: jump execution to a specific node id,
/// marking preceding siblings as Skipped. Honoured on the next container's
/// tree-walk step; the currently-running instruction (e.g. an exposure burst)
/// completes before the jump takes effect. Returns an error if the executor
/// is not running (caller should gate the UI button on execution state).
pub async fn api_sequencer_skip_to_node(node_id: String) -> Result<(), NightshadeError> {
    tracing::info!("Skipping execution to node: {}", node_id);

    let executor = get_sequence_executor().read().await;
    executor
        .skip_to_node(node_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to skip to node: {}", e)))?;

    Ok(())
}

/// Reset the sequence executor
pub async fn api_sequencer_reset() -> Result<(), NightshadeError> {
    tracing::info!("Resetting sequence executor");

    let mut executor = get_sequence_executor().write().await;
    executor.reset().await;

    Ok(())
}

/// Dart side reports the verdict of a plugin-dispatched
/// node back to the Rust executor. Routes to
/// `ExecutorCommand::PluginNodeFinished`. The Rust instruction node
/// awaiting on the matching pending oneshot unblocks with Success or
/// Failure based on `success`.
///
/// `structured_detail_json` is an optional opaque JSON payload the plugin
/// author emits as the node's final progress event. Invalid JSON is
/// logged at warn and dropped (the verdict still applies).
///
/// Returns an error if the executor is not currently running — the
/// caller should treat that as a stale reply (the run was cancelled
/// between dispatch and reply) and drop the result.
pub async fn api_sequencer_plugin_node_finished(
    node_id: String,
    success: bool,
    message: Option<String>,
    structured_detail_json: Option<String>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "[PLUGIN] api_sequencer_plugin_node_finished: node={}, success={}, message={:?}",
        node_id,
        success,
        message,
    );
    let executor = get_sequence_executor().read().await;
    executor
        .plugin_node_finished(node_id, success, message, structured_detail_json)
        .await
        .map_err(|e| {
            NightshadeError::OperationFailed(format!(
                "Failed to deliver plugin node verdict: {}",
                e
            ))
        })?;
    Ok(())
}

/// Get the current sequencer state
pub async fn api_sequencer_get_state() -> SequencerState {
    let executor = get_sequence_executor().read().await;
    let progress = executor.get_progress();
    SequencerState::from(progress)
}

/// Set once the two event bridges below are running, so a second call cannot
/// stand up a second copy of them.
///
/// Every caller treats this as "make sure events are flowing" and calls it
/// unconditionally — the Dart bridge does it at the top of `sequencerStart()`,
/// and the headless and remote entry points reach the same place. Each call used
/// to spawn two fresh supervised tasks, each holding its own receiver on the
/// executor's broadcast channel and republishing everything it saw. Two runs in
/// one app launch therefore meant every sequencer event reached the UI twice:
/// two identical Critical toasts and two Session Report lines per node failure,
/// two frame events per frame. `spawn_supervised_restart` is a bare
/// `tokio::spawn` with no registry, so the task NAME does not dedupe.
///
/// Latching for the process lifetime is safe because the executor is a
/// `OnceLock` singleton whose broadcast sender is created in
/// `SequenceExecutor::new()` and never replaced — the loops can only see
/// `Closed` at process teardown, and the supervisor's restart-on-panic keeps
/// them alive through anything short of that.
static SEQUENCER_EVENT_BRIDGES_STARTED: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// Subscribe to sequencer events and forward them to the main event stream
pub async fn api_sequencer_subscribe_events() -> Result<(), NightshadeError> {
    // Validate the executor is reachable before spawning the supervisor so a
    // bad caller still gets an error synchronously. Drop the lock immediately
    // — the supervisor takes a fresh one on every restart.
    {
        let _executor = get_sequence_executor().read().await;
    }

    if SEQUENCER_EVENT_BRIDGES_STARTED
        .compare_exchange(
            false,
            true,
            std::sync::atomic::Ordering::SeqCst,
            std::sync::atomic::Ordering::SeqCst,
        )
        .is_err()
    {
        tracing::debug!("[EVENT_SUB] Sequencer event bridges already running; no-op");
        return Ok(());
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

    // Replay Debug — parallel supervisor that pumps the
    // executor's structured-decision broadcast channel onto the
    // unified NightshadeEvent stream as `SequencerEvent::DecisionLogged`.
    // Runs as a sibling task to the main event loop because the two
    // channels live on independent broadcast::channel instances on the
    // executor — joining them in one select! would couple their lag
    // policies. We supervise restart so a panic on the decision side
    // does not bring the main loop down.
    let decision_state = get_state().clone();
    crate::util::supervisor::spawn_supervised_restart(
        "sequencer_decision_bridge",
        crate::util::supervisor::RestartPolicy::DEFAULT,
        move || {
            let state = decision_state.clone();
            async move {
                let mut rx = {
                    let executor = get_sequence_executor().read().await;
                    executor.subscribe_decisions()
                };
                tracing::info!("[DECISION_SUB] Decision listener task spawned");
                run_decision_event_loop(&mut rx, &state).await;
            }
        },
        Some(|msg: &str| {
            tracing::error!(
                target: "supervisor",
                "sequencer_decision_bridge exhausted restart budget; replay log will stop populating. Last panic: {msg}"
            );
        }),
    );

    Ok(())
}

/// Replay Debug — bridge loop that publishes every
/// `DecisionEvent` from the executor onto the unified
/// `NightshadeEvent` stream as `SequencerEvent::DecisionLogged`.
/// Pulled out so the supervisor restart factory can call it on every
/// restart.
pub(crate) async fn run_decision_event_loop(
    rx: &mut tokio::sync::broadcast::Receiver<nightshade_sequencer::DecisionEvent>,
    state: &SharedAppState,
) {
    loop {
        let decision = match rx.recv().await {
            Ok(ev) => ev,
            Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                tracing::warn!(
                    "[DECISION_SUB] Lagged behind sequencer decisions; skipped {} events",
                    skipped
                );
                continue;
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                tracing::info!("[DECISION_SUB] Decision channel closed; bridge exiting");
                return;
            }
        };
        let details_json = serde_json::to_string(&decision.details).unwrap_or_else(|err| {
            tracing::warn!(
                "[DECISION_SUB] Failed to serialise decision details to JSON: {}",
                err
            );
            "{}".to_string()
        });
        let payload = SequencerEvent::DecisionLogged {
            timestamp_iso: decision.timestamp.to_rfc3339(),
            category: decision.category.wire_key().to_string(),
            summary: decision.summary,
            details_json,
            node_id: decision.node_id,
            sequence_run_id: decision.sequence_run_id,
        };
        state.publish_event(create_event_auto_id(
            EventSeverity::Info,
            EventCategory::Sequencer,
            EventPayload::Sequencer(payload),
        ));
    }
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
                // Must be the TERMINAL `Failed` payload, not the generic
                // `Error` one: the Dart executor treats `Error` as a
                // recoverable mid-run condition, so flattening onto it left
                // the run un-finalized forever (status stuck at 'running',
                // stale active session blocking the next start).
                ExecutorEvent::SequenceFailed { error } => Some(create_event_auto_id(
                    EventSeverity::Error,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Failed {
                        error: error.clone(),
                    }),
                )),
                // Mid-run reason, so it takes the recoverable `Error` payload
                // rather than the terminal `Failed` one. Without it the real
                // cause of a failure (daylight gate, missing device, refused
                // slew) never left the Rust log.
                ExecutorEvent::InstructionFailed { node_name, message } => {
                    Some(create_event_auto_id(
                        EventSeverity::Error,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::Error {
                            message: format!("{}: {}", node_name, message),
                        }),
                    ))
                }
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
                    structured_detail,
                } => {
                    tracing::info!(
                        "[EVENT_SUB] NodeProgress received: node={}, instruction={}, progress={}%",
                        node_id,
                        instruction,
                        progress_percent
                    );

                    // when the executor sent a structured payload
                    // (image grading + scheduler + budget paths do
                    // this), publish the typed `SequencerEvent` variant
                    // FIRST so the dashboard panels can consume it
                    // directly. Then fall through to also emit the legacy
                    // `InstructionProgress` for back-compat with subscribers
                    // that haven't migrated.
                    if let Some(detail_box) = structured_detail.as_deref() {
                        if let Some((detail_kind, detail_json)) =
                            structured_progress_payload_from_progress_detail(detail_box)
                        {
                            state.publish_event(create_event_auto_id(
                                EventSeverity::Info,
                                EventCategory::Sequencer,
                                EventPayload::Sequencer(
                                    SequencerEvent::InstructionProgressStructured {
                                        node_id: node_id.clone(),
                                        instruction: instruction.clone(),
                                        progress_percent: *progress_percent,
                                        detail_kind,
                                        detail_json,
                                    },
                                ),
                            ));
                        }

                        if let Some(typed) =
                            typed_sequencer_event_from_progress_detail(node_id, detail_box)
                        {
                            state.publish_event(create_event_auto_id(
                                EventSeverity::Info,
                                EventCategory::Sequencer,
                                EventPayload::Sequencer(typed),
                            ));
                        }
                    }

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
                ExecutorEvent::MeridianFlipOutcome {
                    outcome,
                    target_name,
                    new_pier_side,
                    duration_secs,
                    attempts,
                    failed_steps,
                    error,
                    action_taken,
                } => {
                    // Severity drives the operator-facing escalation paths
                    // (audible alert / push). A failed flip is Critical: the
                    // mount may be on the wrong side of the pier and every
                    // subsequent frame is suspect. A flip that only succeeded
                    // after retries is a Warning — it worked, but the recenter
                    // wobbled and the operator should look at the framing.
                    let severity = match outcome.as_str() {
                        "success" if failed_steps.is_empty() => EventSeverity::Info,
                        "success" => EventSeverity::Warning,
                        "aborted" => EventSeverity::Warning,
                        _ => EventSeverity::Critical,
                    };
                    tracing::info!(
                        "[EVENT_SUB] Meridian flip outcome: {} for '{}' after {} attempt(s) \
                         ({} failed step(s))",
                        outcome,
                        target_name,
                        attempts,
                        failed_steps.len()
                    );
                    Some(create_event_auto_id(
                        severity,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::MeridianFlipOutcome {
                            outcome: outcome.clone(),
                            target_name: target_name.clone(),
                            new_pier_side: new_pier_side.clone(),
                            duration_secs: *duration_secs,
                            attempts: *attempts,
                            failed_steps: failed_steps.clone(),
                            error: error.clone(),
                            action_taken: action_taken.clone(),
                        }),
                    ))
                }
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
                    // Internal housekeeping — logged, NOT surfaced to the
                    // operator's event feed.
                    //
                    // This used to be emitted as a `SequencerEvent::Error`
                    // carrying Info severity, on the reasoning that "the existing
                    // UI subscriber sees the change without needing a new typed
                    // payload (a typed payload would require an FRB regen)".
                    // Observed live on a completely healthy 10-frame run: the top
                    // row of Recent Events read
                    //   [!] Sequencer  Sequencer error  x2  13:26:45
                    //       Runtime config updated: conditions_score
                    // because the Dart display layer derives an event's title and
                    // criticality from its PAYLOAD type, so an Error payload reads
                    // as an error however benign its severity claims to be.
                    //
                    // No Dart code consumes this event — grep for
                    // "Runtime config updated" outside comments finds nothing. It
                    // fires roughly every 30s, so its only measurable effect was
                    // filling a five-row panel with false errors and evicting the
                    // events that mattered. The tracing line below is the correct
                    // channel for it.
                    tracing::info!("[EVENT_SUB] Runtime config updated: {}", what);
                    None
                }
                // Recovery Mode — dispatch to first-class typed
                // SequencerEvent variants. Pre-Wave-4.5 these tunneled
                // through `InstructionProgress` with a `_recovery` sentinel
                // node_id and JSON-encoded detail; the Dart side did
                // string-prefix matching on `instruction` and
                // `jsonDecode(detail)`. the FRB regen promotes these
                // to typed payloads (see `SequencerEvent::Recovery{Started,
                // Progress,Completed,GaveUp}` in `crate::event`). Severity
                // is Critical on entry / GaveUp so the existing
                // critical-event escalation paths (audible alert, push
                // notification) keep firing without extra wiring.
                ExecutorEvent::RecoveryStarted { context } => Some(create_event_auto_id(
                    EventSeverity::Critical,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(recovery_event_started(context.as_ref())),
                )),
                ExecutorEvent::RecoveryProgress { context } => Some(create_event_auto_id(
                    EventSeverity::Warning,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(recovery_event_progress(context.as_ref())),
                )),
                ExecutorEvent::RecoveryCompleted { context } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(recovery_event_completed(context.as_ref())),
                )),
                ExecutorEvent::RecoveryGaveUp {
                    context,
                    aborted_by_user,
                } => Some(create_event_auto_id(
                    EventSeverity::Critical,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(recovery_event_gave_up(
                        context.as_ref(),
                        *aborted_by_user,
                    )),
                )),
                // translate the Rust executor's plugin-
                // node request into the typed sequencer event Dart
                // subscribes to. The Dart `SequenceExecutor` consumes
                // this, dispatches to `PluginNodeExecutor.run`, and
                // calls `api_sequencer_plugin_node_finished` to reply.
                ExecutorEvent::PluginNodeRequested {
                    node_id,
                    plugin_id,
                    node_type_id,
                    config_json,
                    display_name,
                    timeout_secs,
                } => {
                    tracing::info!(
                        "[EVENT_SUB] PluginNodeRequested received: node={} ({}/{})",
                        node_id,
                        plugin_id,
                        node_type_id,
                    );
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::PluginNodeRequested {
                            node_id: node_id.clone(),
                            plugin_id: plugin_id.clone(),
                            node_type_id: node_type_id.clone(),
                            config_json: config_json.clone(),
                            display_name: display_name.clone(),
                            timeout_secs: *timeout_secs,
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

/// dispatch a structured `ProgressDetail` to a typed `SequencerEvent`
/// variant. Returns `None` when the variant has no first-class typed bridge
/// payload (the legacy `InstructionProgress` string variant covers those).
///
/// This is the single source of truth for the structured → typed
/// bridge mapping. The Dart dashboard panels consume the typed variants;
/// the legacy `InstructionProgress` stream is still published in parallel
/// so any subscriber that hasn't migrated keeps working (trigger
/// feed, telemetry exporters, etc.).
#[flutter_rust_bridge::frb(ignore)]
fn typed_sequencer_event_from_progress_detail(
    node_id: &str,
    detail: &nightshade_sequencer::ProgressDetail,
) -> Option<SequencerEvent> {
    use nightshade_sequencer::ProgressDetail as PD;
    // Import the bridge-side `SchedulerScoreEntry` so the FRB-public mapping
    // doesn't reach back into the sequencer crate's internal summary type.
    use crate::event::SchedulerScoreEntry;
    match detail {
        PD::FrameAccepted {
            frame,
            total,
            hfr,
            eccentricity,
            star_count,
            accepted_total,
            rejected_total,
            save_path,
            capture,
        } => Some(SequencerEvent::FrameAccepted {
            node_id: node_id.to_string(),
            frame: *frame,
            total: *total,
            hfr: *hfr,
            eccentricity: *eccentricity,
            star_count: *star_count,
            accepted_total: *accepted_total,
            rejected_total: *rejected_total,
            // surface the on-disk save path to Dart so
            // the thumbnail strip can render an inline preview of the
            // accepted frame (mirrors the existing reject_path flow).
            save_path: save_path.clone(),
            // Forwarded verbatim: this is the FITS header's own source, and
            // rewriting or re-deriving any of it here would recreate the
            // second source of truth the payload exists to remove.
            capture: capture.into(),
        }),
        PD::FrameRejected {
            frame,
            total,
            reason,
            hfr,
            eccentricity,
            star_count,
            reject_path,
            consecutive_rejects,
            accepted_total,
            rejected_total,
            // forensics fields — passed through verbatim so the
            // Dart `ForensicsService` can persist them in the
            // `frame_forensics` table.
            likely_cause,
            evidence,
            sky_brightness_at_capture,
            cloud_cover_at_capture,
            wind_at_capture,
            guide_rms_at_capture,
            sensor_temp_at_capture,
            capture,
        } => Some(SequencerEvent::FrameRejected {
            node_id: node_id.to_string(),
            frame: *frame,
            total: *total,
            reason: reason.clone(),
            hfr: *hfr,
            eccentricity: *eccentricity,
            star_count: *star_count,
            reject_path: reject_path.clone(),
            consecutive_rejects: *consecutive_rejects,
            accepted_total: *accepted_total,
            rejected_total: *rejected_total,
            // forensics — the `LikelyCause` enum's wire-stable
            // `label()` is converted to a String so the FRB schema does
            // not need to mirror the enum on the Dart side. The Dart
            // `ForensicsService` matches against these labels via the
            // `LikelyCauseExt.fromLabel` helper.
            likely_cause_label: likely_cause.map(|c| c.label().to_string()),
            evidence: evidence.clone(),
            sky_brightness_at_capture: *sky_brightness_at_capture,
            cloud_cover_at_capture: *cloud_cover_at_capture,
            wind_at_capture: *wind_at_capture,
            guide_rms_at_capture: *guide_rms_at_capture,
            sensor_temp_at_capture: *sensor_temp_at_capture,
            // Same one-source stamping as the accepted path: a rejected frame
            // is still on disk and still gets a `captured_images` row.
            capture: capture.into(),
        }),
        PD::Scheduler {
            decision_counter,
            picked_target_id,
            picked_target_name,
            picked_score,
            scores,
        } => {
            // Map the internal `SchedulerScoreSummary` to the FRB-facing
            // `SchedulerScoreEntry`. We deliberately collapse to the
            // dashboard-relevant fields (target_id, name, total_score,
            // runnable, skip_reason). Altitude / azimuth / airmass /
            // moon-distance / priority are available via the per-target
            // tooltip elsewhere; surfacing them on every scheduler
            // event would balloon the FRB payload for marginal benefit.
            let entries: Vec<SchedulerScoreEntry> = scores
                .iter()
                .map(|s| SchedulerScoreEntry {
                    target_id: s.target_id.clone(),
                    target_name: s.target_name.clone(),
                    total_score: s.total_score,
                    runnable: s.runnable,
                    reason: s.skip_reason.clone(),
                })
                .collect();
            Some(SequencerEvent::SchedulerDecision {
                node_id: node_id.to_string(),
                decision_counter: *decision_counter,
                picked_target_id: picked_target_id.clone(),
                picked_target_name: picked_target_name.clone(),
                picked_score: *picked_score,
                scores: entries,
            })
        }
        PD::IntegrationBudget {
            target_id,
            filter,
            completed_secs,
            budget_secs,
            fraction,
            budget_met,
        } => Some(SequencerEvent::IntegrationBudget {
            target_id: target_id.clone(),
            filter: filter.clone(),
            completed_secs: *completed_secs,
            budget_secs: *budget_secs,
            fraction: *fraction,
            budget_met: *budget_met,
        }),
        // sky-brightness adaptive exposure.
        PD::ExposureAdjusted {
            adapted_secs,
            nominal_secs,
            sky_brightness_mag,
            filter,
            reason,
        } => Some(SequencerEvent::ExposureAdjusted {
            node_id: node_id.to_string(),
            adapted_secs: *adapted_secs,
            nominal_secs: *nominal_secs,
            sky_brightness_mag: *sky_brightness_mag,
            filter: filter.clone(),
            reason: reason.clone(),
        }),
        // plugin-node progress payload. FRB doesn't
        // bridge `serde_json::Value`, so we stringify the detail for
        // the wire. Dart parses with `jsonDecode`.
        PD::PluginNode {
            plugin_id,
            node_type_id,
            detail,
        } => {
            // `to_string` cannot fail for a valid Value; the
            // `unwrap_or` is purely defensive against future
            // serde_json changes.
            let detail_json = serde_json::to_string(detail).unwrap_or_else(|_| "null".to_string());
            Some(SequencerEvent::PluginNodeProgress {
                node_id: node_id.to_string(),
                plugin_id: plugin_id.clone(),
                node_type_id: node_type_id.clone(),
                detail_json,
            })
        }
        // Science / photometry payloads. Mirror the corresponding
        // `ProgressDetail` field shapes verbatim so the Dart light-curve panel
        // binds to explicit fields instead of re-parsing the legacy string
        // `detail`. Emitted alongside `InstructionProgress` (additional, not a
        // replacement) following the Wave-3 precedent above.
        PD::PhotometryFrame {
            target_designation,
            reference_stars,
            frame,
            total,
            filter,
            exposure_secs,
            airmass,
            fwhm_arcsec,
            snr,
            mjd_obs,
            frame_start_unix,
            accepted,
            reject_reason,
            reduce_live,
            apply_differential,
        } => Some(SequencerEvent::PhotometryFrame {
            node_id: node_id.to_string(),
            target_designation: target_designation.clone(),
            reference_stars: reference_stars.clone(),
            frame: *frame,
            total: *total,
            filter: filter.clone(),
            exposure_secs: *exposure_secs,
            airmass: *airmass,
            fwhm_arcsec: *fwhm_arcsec,
            snr: *snr,
            mjd_obs: *mjd_obs,
            frame_start_unix: *frame_start_unix,
            accepted: *accepted,
            reject_reason: reject_reason.clone(),
            reduce_live: *reduce_live,
            apply_differential: *apply_differential,
        }),
        PD::PhotometryCadenceBroken {
            frame,
            total,
            gap_secs,
            max_gap_secs,
            cadence_breaks,
        } => Some(SequencerEvent::PhotometryCadenceBroken {
            node_id: node_id.to_string(),
            frame: *frame,
            total: *total,
            gap_secs: *gap_secs,
            max_gap_secs: *max_gap_secs,
            cadence_breaks: *cadence_breaks,
        }),
        PD::PhotometrySummary {
            target_designation,
            filter,
            frames_captured,
            cadence_breaks,
            last_reject_reason,
        } => Some(SequencerEvent::PhotometrySummary {
            node_id: node_id.to_string(),
            target_designation: target_designation.clone(),
            filter: filter.clone(),
            frames_captured: *frames_captured,
            cadence_breaks: *cadence_breaks,
            last_reject_reason: last_reject_reason.clone(),
        }),
        // Every other variant (Exposure, Filter, Slew, Center, Autofocus,
        // …) is well-served by the legacy `InstructionProgress` string
        // channel — adding typed variants for them is future work, not
        // 's scope.
        _ => None,
    }
}

#[flutter_rust_bridge::frb(ignore)]
fn structured_progress_payload_from_progress_detail(
    detail: &nightshade_sequencer::ProgressDetail,
) -> Option<(String, String)> {
    let value = serde_json::to_value(detail).ok()?;
    match value {
        serde_json::Value::Object(tagged) if tagged.len() == 1 => {
            let (kind, payload) = tagged.into_iter().next()?;
            Some((kind, payload.to_string()))
        }
        other => Some(("Unknown".to_string(), other.to_string())),
    }
}

// =============================================================================
// typed Recovery event builders
// =============================================================================
//
// These helpers flatten the chrono-bearing `RecoveryContext` Rust struct into
// the FRB-friendly primitive payload exposed via `SequencerEvent::Recovery{
// Started, Progress, Completed, GaveUp}`. Centralised here so any future
// recovery-event channel uses the same wire shape.

/// Split a `RecoveryCause` into the `cause_kind` discriminant string + the
/// optional custom payload. The discriminant matches the Rust enum variant
/// name verbatim so the Dart side's `RecoveryCause.fromJson` factory maps
/// without a translation table.
#[flutter_rust_bridge::frb(ignore)]
fn recovery_cause_fields(
    cause: &nightshade_sequencer::recovery::RecoveryCause,
) -> (String, Option<String>) {
    use nightshade_sequencer::recovery::RecoveryCause as RC;
    match cause {
        RC::GuideStarLost => ("GuideStarLost".to_string(), None),
        RC::SlewFailed => ("SlewFailed".to_string(), None),
        RC::PlateSolveFailed => ("PlateSolveFailed".to_string(), None),
        RC::WeatherUnsafe => ("WeatherUnsafe".to_string(), None),
        RC::MountTrackingLost => ("MountTrackingLost".to_string(), None),
        RC::FocusDriftCritical => ("FocusDriftCritical".to_string(), None),
        RC::ConsecutiveRejectsExceeded => ("ConsecutiveRejectsExceeded".to_string(), None),
        RC::DeviceDisconnected => ("DeviceDisconnected".to_string(), None),
        RC::Custom(label) => ("Custom".to_string(), Some(label.clone())),
    }
}

/// Phase enum → stable Debug-format string. Matches the JSON wire shape
/// `serde` produces for the Rust `RecoveryPhase` unit-variant enum so the
/// Dart `_phaseFromWire` parser keeps working.
#[flutter_rust_bridge::frb(ignore)]
fn recovery_phase_str(phase: nightshade_sequencer::recovery::RecoveryPhase) -> String {
    use nightshade_sequencer::recovery::RecoveryPhase as RP;
    match phase {
        RP::Waiting => "Waiting",
        RP::Attempting => "Attempting",
        RP::Recovered => "Recovered",
        RP::GaveUp => "GaveUp",
    }
    .to_string()
}

#[flutter_rust_bridge::frb(ignore)]
fn recovery_event_started(ctx: &nightshade_sequencer::recovery::RecoveryContext) -> SequencerEvent {
    let (cause_kind, cause_custom_label) = recovery_cause_fields(&ctx.cause);
    SequencerEvent::RecoveryStarted {
        started_at_iso: ctx.started_at.to_rfc3339(),
        cause_kind,
        cause_custom_label,
        last_attempt_at_iso: ctx.last_attempt_at.map(|t| t.to_rfc3339()),
        attempt_count: ctx.attempt_count,
        max_attempts: ctx.max_attempts,
        retry_interval_secs: ctx.retry_interval_secs,
        max_duration_secs: ctx.max_duration_secs,
        phase: recovery_phase_str(ctx.phase),
        last_error: ctx.last_error.clone(),
    }
}

#[flutter_rust_bridge::frb(ignore)]
fn recovery_event_progress(
    ctx: &nightshade_sequencer::recovery::RecoveryContext,
) -> SequencerEvent {
    let (cause_kind, cause_custom_label) = recovery_cause_fields(&ctx.cause);
    SequencerEvent::RecoveryProgress {
        started_at_iso: ctx.started_at.to_rfc3339(),
        cause_kind,
        cause_custom_label,
        last_attempt_at_iso: ctx.last_attempt_at.map(|t| t.to_rfc3339()),
        attempt_count: ctx.attempt_count,
        max_attempts: ctx.max_attempts,
        retry_interval_secs: ctx.retry_interval_secs,
        max_duration_secs: ctx.max_duration_secs,
        phase: recovery_phase_str(ctx.phase),
        last_error: ctx.last_error.clone(),
    }
}

#[flutter_rust_bridge::frb(ignore)]
fn recovery_event_completed(
    ctx: &nightshade_sequencer::recovery::RecoveryContext,
) -> SequencerEvent {
    let (cause_kind, cause_custom_label) = recovery_cause_fields(&ctx.cause);
    SequencerEvent::RecoveryCompleted {
        started_at_iso: ctx.started_at.to_rfc3339(),
        cause_kind,
        cause_custom_label,
        last_attempt_at_iso: ctx.last_attempt_at.map(|t| t.to_rfc3339()),
        attempt_count: ctx.attempt_count,
        max_attempts: ctx.max_attempts,
        retry_interval_secs: ctx.retry_interval_secs,
        max_duration_secs: ctx.max_duration_secs,
        phase: recovery_phase_str(ctx.phase),
        last_error: ctx.last_error.clone(),
    }
}

#[flutter_rust_bridge::frb(ignore)]
fn recovery_event_gave_up(
    ctx: &nightshade_sequencer::recovery::RecoveryContext,
    aborted_by_user: bool,
) -> SequencerEvent {
    let (cause_kind, cause_custom_label) = recovery_cause_fields(&ctx.cause);
    SequencerEvent::RecoveryGaveUp {
        started_at_iso: ctx.started_at.to_rfc3339(),
        cause_kind,
        cause_custom_label,
        last_attempt_at_iso: ctx.last_attempt_at.map(|t| t.to_rfc3339()),
        attempt_count: ctx.attempt_count,
        max_attempts: ctx.max_attempts,
        retry_interval_secs: ctx.retry_interval_secs,
        max_duration_secs: ctx.max_duration_secs,
        phase: recovery_phase_str(ctx.phase),
        last_error: ctx.last_error.clone(),
        aborted_by_user,
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

/// Standalone meridian flip — runs the canonical [`MeridianFlipExecutor`]
/// OUTSIDE any running sequence.
///
/// Why this exists: the Dart-side standalone meridian monitor previously
/// could only alert (the flip engine was reachable solely through the
/// sequencer's trigger path), so an attended non-sequencer session got a
/// notification while the mount tracked into the pier. This API gives that
/// monitor a real flip with the exact same engine, timeouts, altitude
/// check, re-center and refocus semantics as the in-sequence path.
///
/// Refuses while the sequence executor is Running/Paused/Stopping/
/// Recovering — two engines commanding one mount is how pier crashes
/// happen; the in-sequence trigger owns flips there.
#[allow(clippy::too_many_arguments)]
pub async fn api_perform_meridian_flip(
    mount_id: String,
    camera_id: Option<String>,
    focuser_id: Option<String>,
    cover_calibrator_id: Option<String>,
    target_name: String,
    target_ra_hours: f64,
    target_dec_degrees: f64,
    pause_guiding: bool,
    auto_center: bool,
    refocus_after: bool,
    resume_guiding: bool,
    settle_time_secs: f64,
) -> Result<(), NightshadeError> {
    {
        let executor = get_sequence_executor().read().await;
        let state = executor.get_state().await;
        match state {
            ExecutorState::Idle
            | ExecutorState::Completed
            | ExecutorState::Failed
            | ExecutorState::Cancelled => {}
            ExecutorState::Running
            | ExecutorState::Paused
            | ExecutorState::Stopping
            | ExecutorState::Recovering => {
                return Err(NightshadeError::OperationFailed(format!(
                    "Cannot run a standalone meridian flip while the sequencer is {:?} — \
                     the in-sequence meridian trigger owns flips during a sequence.",
                    state
                )));
            }
        }
    }

    tracing::info!(
        "[MERIDIAN] Standalone flip requested for '{}' (RA {:.4}h, Dec {:.4}°, mount {})",
        target_name,
        target_ra_hours,
        target_dec_degrees,
        mount_id
    );

    let config = nightshade_sequencer::MeridianFlipConfig {
        pause_guiding,
        auto_center,
        refocus_after,
        resume_guiding,
        settle_time: settle_time_secs,
        ..Default::default()
    };

    let ctx = nightshade_sequencer::FlipContext {
        target_name: target_name.clone(),
        target_ra_hours,
        target_dec_degrees,
        mount_id,
        camera_id,
        focuser_id,
        cover_calibrator_id,
        cancellation_token: None,
        trigger_state: None,
        autofocus_config: None,
        simulate: false,
    };

    let ops = create_unified_device_ops();
    let mut flip_executor = nightshade_sequencer::MeridianFlipExecutor::new(config, ops);
    match flip_executor.execute(&ctx).await {
        nightshade_sequencer::FlipResult::Success {
            new_pier_side,
            duration_secs,
        } => {
            tracing::info!(
                "[MERIDIAN] Standalone flip for '{}' completed: pier {:?}, {:.1}s",
                target_name,
                new_pier_side,
                duration_secs
            );
            Ok(())
        }
        nightshade_sequencer::FlipResult::Failed {
            error,
            action_taken,
        } => Err(NightshadeError::OperationFailed(format!(
            "Meridian flip failed: {} (configured failure action: {:?})",
            error, action_taken
        ))),
        nightshade_sequencer::FlipResult::Aborted { reason } => Err(
            NightshadeError::OperationFailed(format!("Meridian flip aborted: {}", reason)),
        ),
    }
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
/// - "fail_closed": Treat unavailable safety data as unsafe
/// - "fail_open": Treat unavailable safety data as safe
/// - "warn_only": Preserve the previous safety state and emit a warning event
pub async fn api_sequencer_set_safety_fail_mode(mode: String) -> Result<(), NightshadeError> {
    use nightshade_sequencer::SafetyFailMode;

    let mode_lower = mode.to_lowercase();
    let fail_mode = match mode_lower.as_str() {
        "fail_closed" | "failclosed" => SafetyFailMode::FailClosed,
        "fail_open" | "failopen" => SafetyFailMode::FailOpen,
        "warn_only" | "warnonly" => SafetyFailMode::WarnOnly,
        _ => {
            return Err(NightshadeError::InvalidParameter(format!(
                "Invalid safety fail mode: '{}'. Must be 'fail_closed', 'fail_open', or 'warn_only'.",
                mode
            )));
        }
    };

    tracing::info!("Setting sequencer safety fail mode: {:?}", fail_mode);
    let mut executor = get_sequence_executor().write().await;
    executor.set_safety_fail_mode(fail_mode);

    Ok(())
}

/// Set the safety/humidity polling interval for the sequencer.
/// Must be between 5 seconds and 3600 seconds. The executor applies the
/// update live without restarting the current sequence.
pub async fn api_sequencer_set_safety_check_interval_seconds(
    seconds: u32,
) -> Result<(), NightshadeError> {
    if !(5..=3600).contains(&seconds) {
        return Err(NightshadeError::InvalidParameter(format!(
            "Invalid safety check interval: {}. Must be between 5 and 3600 seconds.",
            seconds
        )));
    }

    tracing::info!(
        "Setting sequencer safety check interval: {} seconds",
        seconds
    );
    let mut executor = get_sequence_executor().write().await;
    executor.set_safety_check_interval_secs(u64::from(seconds));

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
    executor
        .update_dither_config(pixels, settle_pixels, settle_time, settle_timeout, ra_only)
        .await;
    Ok(())
}

/// Push the operator's meridian-flip settings onto the standard
/// `meridian_flip` trigger.
///
/// `config_json` is a serialised `MeridianFlipConfig` — the SAME shape the Dart
/// side already builds for a `MeridianFlipNode`, so there is exactly one
/// wire format for meridian settings and one place to keep in sync.
///
/// Why JSON rather than a typed FRB struct: `MeridianFlipConfig` has 21 fields
/// including a `Vec<f64>` retry ladder and two enums, and every one of them is
/// already covered by the serde contract the sequence JSON uses. Mirroring it
/// as an FRB struct would duplicate that contract and give it two places to
/// drift.
///
/// Without this call the trigger keeps `MeridianFlipConfig::default()` for the
/// whole run and the user's Settings → Meridian Flip panel is inert on the
/// trigger path.
pub async fn api_sequencer_update_meridian_flip_config(
    config_json: String,
) -> Result<(), NightshadeError> {
    let config: nightshade_sequencer::MeridianFlipConfig = serde_json::from_str(&config_json)
        .map_err(|e| {
            NightshadeError::InvalidParameter(format!("Invalid meridian-flip config JSON: {}", e))
        })?;
    if config.max_retries > 0 && config.retry_delays_secs.is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "meridian-flip config sets max_retries > 0 but no retry delays; the flip \
             would refuse to retry"
                .to_string(),
        ));
    }
    tracing::info!(
        "[API] Updating meridian-flip trigger config from user settings (auto_center={}, \
         minutes_past={:.1}, max_retries={})",
        config.auto_center,
        config.minutes_past_meridian,
        config.max_retries
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_meridian_flip_config(config).await;
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
    executor.update_location(latitude, longitude).await;
    Ok(())
}

/// stage per-target / per-filter carry-over integration so the
/// next `sequencerStart()` seeds the IntegrationBudget tracker with frames
/// already captured in prior sessions. The Dart `SequenceExecutor.start()`
/// calls this once per target after reading `sessionHandoffDecisionProvider`:
///
///   * `Resume`      → supply the prior per-filter totals.
///   * `Restart`     → supply an empty inner map (zeroes the carry-over).
///   * `ContinueNew` → omit the target from the call (default behaviour).
///
/// `carry_over` shape: `target_id` -> { `filter_name` -> `seconds` }.
/// The Rust side merges entries (last-write-wins per target_id), then drains
/// the staged map on the next `start()`.
pub async fn api_sequencer_update_pending_integration_carry_over(
    carry_over: std::collections::HashMap<String, std::collections::HashMap<String, f64>>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer integration carry-over: {} target entries",
        carry_over.len()
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_pending_integration_carry_over(carry_over);
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
    executor.update_filter_offsets(offsets).await;
    Ok(())
}

/// update the autofocus-interval trigger cadence at runtime.
/// The default in `default_autofocus_interval_frames()` is 25 frames; this
/// is wrong for both very-short (5 s) and very-long (5 min) subs, so the UI
/// must let the user override it. `every_n_frames == 0` is rejected because
/// the trigger evaluator disables the periodic AF when the cadence is zero,
/// which would silently turn AF off ("errors are a feature").
pub async fn api_sequencer_update_autofocus_interval(
    every_n_frames: u32,
) -> Result<(), NightshadeError> {
    if every_n_frames == 0 {
        return Err(NightshadeError::InvalidParameter(
            "autofocus_interval_frames must be > 0. Pass a positive frame cadence; \
             use the trigger 'enabled' toggle in the trigger list to disable periodic AF."
                .to_string(),
        ));
    }
    tracing::info!(
        "Updating sequencer autofocus-interval cadence: every {} frames",
        every_n_frames
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_autofocus_interval(every_n_frames).await;
    Ok(())
}

/// Push the operator's autofocus settings so trigger-fired refocus uses them.
///
/// The only source of trigger-autofocus tuning used to be an Autofocus node
/// inside the sequence. A sequence without one — which is exactly the sequence
/// whose interval trigger fires unattended — therefore ran every refocus on
/// library defaults, ignoring the operator's step size, exposure, backlash,
/// failure tolerance and failure action. An Autofocus node still wins at
/// `start()`: a node is a per-sequence decision, this is a global one.
///
/// Takes the same JSON shape the sequence's Autofocus node carries, so the
/// Dart side has exactly one serializer to keep correct.
pub async fn api_sequencer_update_autofocus_config(
    config_json: String,
) -> Result<(), NightshadeError> {
    let config: nightshade_sequencer::AutofocusConfig = serde_json::from_str(&config_json)
        .map_err(|e| {
            NightshadeError::InvalidParameter(format!(
                "autofocus config JSON could not be parsed: {e}. Trigger-fired refocus would \
                 have silently fallen back to library defaults."
            ))
        })?;
    let mut executor = get_sequence_executor().write().await;
    executor.update_autofocus_config(config).await;
    Ok(())
}

/// update the global default image-grading thresholds at runtime.
///
/// All fields are optional; when `enabled` is `false` an `ImageQualityCheck`
/// is NOT constructed (grading disabled globally — per-node `quality_check`
/// on TakeExposure still wins). The Dart `enableImageGrading` toggle on
/// app settings drives this directly.
pub async fn api_sequencer_update_default_quality_check(
    hfr_threshold: Option<f64>,
    hfr_baseline_percent: Option<f64>,
    eccentricity_threshold: Option<f64>,
    star_count_min: Option<u32>,
    max_consecutive_rejects: u32,
    enabled: bool,
) -> Result<(), NightshadeError> {
    use nightshade_sequencer::quality::ImageQualityCheck;
    let check = if enabled {
        Some(ImageQualityCheck {
            hfr_threshold,
            hfr_baseline_percent,
            eccentricity_threshold,
            star_count_min,
            max_consecutive_rejects,
        })
    } else {
        None
    };
    tracing::info!(
        "Updating sequencer default_quality_check: enabled={}, hfr={:?}, hfr_baseline={:?}, ecc={:?}, stars={:?}, max_rejects={}",
        enabled,
        hfr_threshold,
        hfr_baseline_percent,
        eccentricity_threshold,
        star_count_min,
        max_consecutive_rejects,
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_default_quality_check(check).await;
    Ok(())
}

/// update the reject-folder override at runtime. Empty string =>
/// None (i.e. fall back to `<save_path>/Reject/`).
pub async fn api_sequencer_update_reject_folder_path(
    path: Option<String>,
) -> Result<(), NightshadeError> {
    // Normalise empty / whitespace-only to None so the user can clear the
    // override by deleting the text field without us treating "" as a
    // path-relative-to-cwd.
    let normalised = path.and_then(|p| {
        let trimmed = p.trim().to_string();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    });
    tracing::info!("Updating sequencer reject_folder_path: {:?}", normalised);
    let mut executor = get_sequence_executor().write().await;
    executor.update_reject_folder_path(normalised).await;
    Ok(())
}

/// push observer / equipment identification to the executor so
/// the next FITS save stamps real keywords (OBSERVER, TELESCOP, FOCALLEN,
/// APTDIA, INSTRUME, SITEELEV). Every field is optional because in
/// headless / no-profile runs we'd rather omit the keyword than emit a
/// sentinel — silent fallbacks are bugs.
pub async fn api_sequencer_update_observer_profile(
    observer_name: Option<String>,
    site_elevation_m: Option<f64>,
    camera_make: Option<String>,
    camera_model: Option<String>,
    telescope_name: Option<String>,
    telescope_focal_length_mm: Option<f64>,
    telescope_aperture_mm: Option<f64>,
) -> Result<(), NightshadeError> {
    use nightshade_sequencer::ObserverProfile;
    let trim_opt = |s: Option<String>| -> Option<String> {
        s.and_then(|v| {
            let t = v.trim().to_string();
            if t.is_empty() {
                None
            } else {
                Some(t)
            }
        })
    };
    let profile = ObserverProfile {
        observer_name: trim_opt(observer_name),
        site_elevation_m,
        camera_make: trim_opt(camera_make),
        camera_model: trim_opt(camera_model),
        telescope_name: trim_opt(telescope_name),
        telescope_focal_length_mm,
        telescope_aperture_mm,
    };
    tracing::info!(
        "Updating sequencer observer_profile: observer={:?}, telescope={:?}, camera_make={:?}, camera_model={:?}",
        profile.observer_name,
        profile.telescope_name,
        profile.camera_make,
        profile.camera_model,
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_observer_profile(profile).await;
    Ok(())
}

// =============================================================================
// Cloud-motion-aware triggers
// =============================================================================
//
// Push the live `cloudMotionAnalyzerProvider` output from Dart into the
// executor's trigger state on a ~60s cadence (see WeatherSafetyNotifier).
// Drives the `CloudArrivingIn`, `CloudOpeningIn`, and `CloudCoverThreshold`
// triggers added in `nightshade_sequencer::TriggerType`.

/// Push the latest cloud-motion analyzer reading into the executor.
///
/// All fields are optional because the Dart analyzer may not yet have
/// enough radar history to produce every quantity. `None` values disable
/// the corresponding evaluator branch rather than firing on a default —
/// silently picking a sentinel would mask analyzer failures.
///
/// `predicted_clear_sky_alt` / `predicted_clear_sky_az` must be either
/// both `Some` or both `None`; a half-specified direction is logged at
/// WARN and treated as no-direction.
pub async fn api_sequencer_update_cloud_motion(
    current_cover_percent: Option<f64>,
    predicted_arrival_minutes: Option<f64>,
    predicted_opening_minutes: Option<f64>,
    predicted_opening_duration_secs: Option<f64>,
    predicted_clear_sky_alt: Option<f64>,
    predicted_clear_sky_az: Option<f64>,
) -> Result<(), NightshadeError> {
    if predicted_clear_sky_alt.is_some() != predicted_clear_sky_az.is_some() {
        tracing::warn!(
            "[API] update_cloud_motion: half-specified clear-sky direction ignored (alt={:?}, az={:?})",
            predicted_clear_sky_alt,
            predicted_clear_sky_az,
        );
    }
    tracing::debug!(
        "[API] update_cloud_motion: cover={:?}%, arrival={:?}min, opening={:?}min ({:?}s), clear=({:?},{:?})",
        current_cover_percent,
        predicted_arrival_minutes,
        predicted_opening_minutes,
        predicted_opening_duration_secs,
        predicted_clear_sky_alt,
        predicted_clear_sky_az,
    );
    let executor = get_sequence_executor().read().await;
    executor
        .update_cloud_motion(
            current_cover_percent,
            predicted_arrival_minutes,
            predicted_opening_minutes,
            predicted_opening_duration_secs,
            predicted_clear_sky_alt,
            predicted_clear_sky_az,
        )
        .await;
    Ok(())
}

/// Full-night audit 2026-06-04 (defense-in-depth) — push the Dart-side
/// weather-safety verdict into the executor.
///
/// The in-sequencer `WeatherUnsafe` trigger keys off the hardware
/// `safety_is_safe` poll only; a rig WITHOUT a hardware safety device never
/// aborts via that trigger even when `weatherSafetyProvider` computed UNSAFE
/// from the user's configured thresholds + API/cloud sources. This carries
/// that verdict as an additional unsafe source folded (OR-of-unsafe) into the
/// trigger evaluation — it can only make the rig safer, never less safe than
/// the hardware reading.
///
/// `unsafe_override = Some(true)` => Dart computed UNSAFE; `Some(false)` =>
/// Dart computed SAFE; `None` => Dart abstains (provider disabled / no data)
/// and this layer is inert.
pub async fn api_sequencer_update_weather_verdict(
    unsafe_override: Option<bool>,
) -> Result<(), NightshadeError> {
    tracing::debug!(
        "[API] update_weather_verdict: unsafe_override={:?}",
        unsafe_override
    );
    let executor = get_sequence_executor().read().await;
    executor.update_weather_verdict(unsafe_override).await;
    Ok(())
}

/// JSON-serialised cloud-motion snapshot for the run
/// dashboard. Returns `Ok(None)` when no data has been pushed yet.
pub async fn api_sequencer_get_cloud_motion_json() -> Result<Option<String>, NightshadeError> {
    let executor = get_sequence_executor().read().await;
    Ok(executor.current_cloud_motion_json())
}

// =============================================================================
// Sky-brightness adaptive exposures
// =============================================================================
//
// The Dart `SkyBrightnessTracker` produces a continuous mag/arcsec² reading
// during execution. We push that reading to the sequencer executor whenever
// it changes; the next `TakeExposure` burst consults it and may scale the
// per-frame duration to keep SNR roughly constant across changing sky
// conditions. The global default `AdaptiveExposureConfig` is pushed via a
// separate API so the user's app-settings UI can configure once and have
// it apply to every exposure node that doesn't carry its own override.

/// Push the latest live sky-brightness reading to the executor.
///
/// `mag` is the sky brightness in mag/arcsec² (bigger = darker). Pass
/// `None` when the tracker has lost lock — the adapter then falls back to
/// the nominal duration and emits a structured `Unavailable` event.
pub async fn api_sequencer_update_sky_brightness(mag: Option<f64>) -> Result<(), NightshadeError> {
    if let Some(m) = mag {
        if !m.is_finite() || m <= 0.0 {
            tracing::warn!(
                "[API] update_sky_brightness: non-finite or non-positive value {:?} — treating as None",
                m
            );
        }
    }
    tracing::debug!("[API] update_sky_brightness: {:?} mag/arcsec²", mag);
    let executor = get_sequence_executor().read().await;
    executor.update_sky_brightness(mag).await;
    Ok(())
}

/// Push the global default sky-brightness adaptive-exposure config to the
/// executor. Per-node `ExposureConfig.adaptive_exposure` still wins; this
/// is the runtime fallback applied to TakeExposure nodes that have no
/// own block.
///
/// Pass `enabled = false` to disable the feature globally. The per-filter
/// maps are flattened into parallel arrays because FRB cannot bridge
/// `HashMap<String, T>` directly — Dart serialises its own filter map to
/// the (`*_filters`, `*_values`) pair shape.
#[allow(clippy::too_many_arguments)]
pub async fn api_sequencer_update_default_adaptive_exposure(
    enabled: bool,
    target_snr: f64,
    reference_sky_brightness_mag: f64,
    min_exposure_secs: f64,
    max_exposure_secs: f64,
    per_filter_enabled_keys: Vec<String>,
    per_filter_enabled_values: Vec<bool>,
    per_filter_min_keys: Vec<String>,
    per_filter_min_values: Vec<f64>,
    per_filter_max_keys: Vec<String>,
    per_filter_max_values: Vec<f64>,
) -> Result<(), NightshadeError> {
    use nightshade_sequencer::scheduling::AdaptiveExposureConfig;

    if per_filter_enabled_keys.len() != per_filter_enabled_values.len() {
        return Err(NightshadeError::InvalidParameter(
            "per_filter_enabled_keys and per_filter_enabled_values lengths differ".to_string(),
        ));
    }
    if per_filter_min_keys.len() != per_filter_min_values.len() {
        return Err(NightshadeError::InvalidParameter(
            "per_filter_min_keys and per_filter_min_values lengths differ".to_string(),
        ));
    }
    if per_filter_max_keys.len() != per_filter_max_values.len() {
        return Err(NightshadeError::InvalidParameter(
            "per_filter_max_keys and per_filter_max_values lengths differ".to_string(),
        ));
    }

    let per_filter_enabled = per_filter_enabled_keys
        .into_iter()
        .zip(per_filter_enabled_values)
        .collect::<std::collections::HashMap<_, _>>();
    let per_filter_min_secs = per_filter_min_keys
        .into_iter()
        .zip(per_filter_min_values)
        .collect::<std::collections::HashMap<_, _>>();
    let per_filter_max_secs = per_filter_max_keys
        .into_iter()
        .zip(per_filter_max_values)
        .collect::<std::collections::HashMap<_, _>>();

    let config = AdaptiveExposureConfig {
        enabled,
        target_snr,
        reference_sky_brightness_mag,
        min_exposure_secs,
        max_exposure_secs,
        per_filter_enabled,
        per_filter_min_secs,
        per_filter_max_secs,
    };
    tracing::info!(
        "[API] update_default_adaptive_exposure: enabled={}, ref={} mag/arcsec², min={}s, max={}s, per_filter_enabled={}, per_filter_min={}, per_filter_max={}",
        enabled,
        reference_sky_brightness_mag,
        min_exposure_secs,
        max_exposure_secs,
        config.per_filter_enabled.len(),
        config.per_filter_min_secs.len(),
        config.per_filter_max_secs.len(),
    );
    let mut executor = get_sequence_executor().write().await;
    executor
        .update_default_adaptive_exposure(Some(config))
        .await;
    Ok(())
}

/// disable the global default adaptive-exposure config
/// (push `None`). Convenience entry-point so the Dart side doesn't have
/// to pass a sentinel struct just to disable.
pub async fn api_sequencer_clear_default_adaptive_exposure() -> Result<(), NightshadeError> {
    tracing::info!("[API] clear_default_adaptive_exposure: disabling global default");
    let mut executor = get_sequence_executor().write().await;
    executor.update_default_adaptive_exposure(None).await;
    Ok(())
}

// =============================================================================
// Recovery Mode — FRB-exposed control surface
// =============================================================================
//
// added these to `bridge/src/sequencer_api.rs` but that module
// is OUTSIDE `crate::api`, which is FRB's scan root (see
// `flutter_rust_bridge.yaml > rust_input`). The functions never crossed the
// FRB boundary, so the Dart side fell back to `dynamic` dispatch with
// `NoSuchMethodError` placeholders. Re-homing them here closes that gap.

/// User-tunable recovery defaults pushed from the Settings > Recovery Mode
/// page. Field-for-field mirror of
/// `nightshade_sequencer::recovery::RecoveryRuntimeConfig` so the FRB wire
/// shape stays stable across regen cycles.
#[derive(Debug, Clone)]
pub struct RecoveryConfigUpdate {
    pub retry_interval_secs: f64,
    pub max_duration_secs: f64,
    pub stop_tracking_during_recovery: bool,
    pub abort_on_meridian: bool,
    pub audible_alert_when_entered: bool,
}

/// Operator pressed "Try Now" on the Run Dashboard banner — punch through
/// the wait timer and force the next recovery attempt immediately. No-op
/// when the executor is not currently in `Recovering`.
pub async fn api_sequencer_recovery_try_now() -> Result<(), NightshadeError> {
    tracing::info!("[API] Recovery: Try Now requested");
    let executor = get_sequence_executor().read().await;
    executor
        .recovery_try_now()
        .await
        .map_err(NightshadeError::OperationFailed)
}

/// Operator pressed "Abort" on the Run Dashboard banner — exits the recovery
/// loop and transitions the executor to `Failed`. No-op when not in
/// `Recovering`.
pub async fn api_sequencer_recovery_abort() -> Result<(), NightshadeError> {
    tracing::info!("[API] Recovery: Abort requested");
    let executor = get_sequence_executor().read().await;
    executor
        .recovery_abort()
        .await
        .map_err(NightshadeError::OperationFailed)
}

/// Push updated recovery defaults into the executor's runtime config. The
/// next recovery entry uses these values; an in-flight loop continues with
/// the values that were live when it entered.
///
/// Validation here matches the gate the Rust sequencer applies internally:
/// both `retry_interval_secs` and `max_duration_secs` must be > 0. We
/// surface a structured InvalidParameter error so the Dart settings page
/// can render a precise validation message instead of "unknown error".
pub async fn api_sequencer_update_recovery_config(
    update: RecoveryConfigUpdate,
) -> Result<(), NightshadeError> {
    if update.retry_interval_secs <= 0.0 {
        return Err(NightshadeError::InvalidParameter(format!(
            "retry_interval_secs must be > 0 (was {})",
            update.retry_interval_secs
        )));
    }
    if update.max_duration_secs <= 0.0 {
        return Err(NightshadeError::InvalidParameter(format!(
            "max_duration_secs must be > 0 (was {})",
            update.max_duration_secs
        )));
    }
    tracing::info!(
        "[API] Recovery: update config interval={:.0}s, max_duration={:.0}s, stop_track={}, abort_meridian={}, audible={}",
        update.retry_interval_secs,
        update.max_duration_secs,
        update.stop_tracking_during_recovery,
        update.abort_on_meridian,
        update.audible_alert_when_entered,
    );
    let config = nightshade_sequencer::recovery::RecoveryRuntimeConfig {
        retry_interval_secs: update.retry_interval_secs,
        max_duration_secs: update.max_duration_secs,
        stop_tracking_during_recovery: update.stop_tracking_during_recovery,
        abort_on_meridian: update.abort_on_meridian,
        audible_alert_when_entered: update.audible_alert_when_entered,
    };
    let mut executor = get_sequence_executor().write().await;
    executor.update_recovery_config(config).await;
    Ok(())
}

/// JSON-serialised snapshot of the current in-flight `RecoveryContext`.
/// Returns `None` when the executor is not currently in `Recovering`.
///
/// JSON-string-over-bridge is intentional: the Dart side already owns a
/// hand-written `RecoveryStatus.fromJson` mirror (see
/// `nightshade_core/lib/src/models/sequencer/recovery_status.dart`) so
/// piping serde JSON across is cheaper than asking FRB to bridge the
/// chrono-dependent `RecoveryContext` Rust struct.
pub async fn api_sequencer_get_current_recovery_json() -> Result<Option<String>, NightshadeError> {
    let executor = get_sequence_executor().read().await;
    let ctx = executor.current_recovery();
    match ctx {
        None => Ok(None),
        Some(c) => {
            let json = serde_json::to_string(&c).map_err(|e| {
                NightshadeError::SerializationError(format!("Recovery context serialise: {}", e))
            })?;
            Ok(Some(json))
        }
    }
}

/// JSON-serialised dump of every completed recovery loop since the executor
/// was constructed. Surfaced for the post-session report dialog. Returns an
/// empty JSON array `"[]"` when no recoveries have completed yet.
pub async fn api_sequencer_get_recovery_history_json() -> Result<String, NightshadeError> {
    let executor = get_sequence_executor().read().await;
    let history = executor.recovery_history();
    serde_json::to_string(&history).map_err(|e| {
        NightshadeError::SerializationError(format!("Recovery history serialise: {}", e))
    })
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
        // Image Grading: new TakeExposure nodes default to "use
        // global grading settings"; the per-node override is set via a
        // separate UI knob.
        quality_check: None,
        // new TakeExposure nodes default to "use
        // global adaptive-exposure settings"; the per-node override is
        // set via a separate UI knob.
        adaptive_exposure: None,
        // Factory nodes are light frames; the editor's frame-type
        // dropdown rewrites this through the sequence serializer.
        frame_type: "Light".to_string(),
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
///
/// `integration_budget_json` (optional) is a JSON-encoded
/// [`nightshade_sequencer::IntegrationBudget`] payload mirroring the
/// Dart-side `IntegrationBudget` model. Passing `None` leaves the
/// target without a budget (current behaviour); passing a valid JSON
/// string installs the budget on the TargetHeader.
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
    integration_budget_json: Option<String>,
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

    // deserialize the optional budget payload. An
    // explicit Err is surfaced (rather than silently dropping the
    // budget) so a Dart-side schema bug fails loudly.
    let integration_budget = integration_budget_json
        .map(|json| {
            serde_json::from_str(&json).map_err(|e| {
                NightshadeError::SerializationError(format!(
                    "Invalid integration_budget JSON: {}",
                    e
                ))
            })
        })
        .transpose()?;

    // added `start_when` / `end_when` /
    // `trigger_poll_interval_secs` to `TargetHeaderConfig`. This entry
    // point predates those fields, so the bridge falls back to the
    // struct's `Default` values (legacy `start_after`/`end_before` /
    // `min_altitude` / `max_altitude` paths still synthesise effective
    // triggers via `scheduling::legacy_to_triggers`). Dart should call
    // `api_set_target_header_triggers` (or the equivalent) to install
    // explicit Wave-4 trigger expressions.
    let defaults = TargetHeaderConfig::default();
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
        integration_budget,
        start_when: defaults.start_when,
        end_when: defaults.end_when,
        trigger_poll_interval_secs: defaults.trigger_poll_interval_secs,
        // adaptive sky-conditions swap: leave the tier hint
        // unset (None => Medium by default) so legacy bridge entries
        // don't accidentally pin targets to Bright or Faint.
        brightness_tier_hint: defaults.brightness_tier_hint,
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
        // Per-azimuth local-horizon mask is authored on the Dart side and
        // round-trips through the node-definition JSON (deserialized into
        // `LoopConfig` at runtime). It is `None` for nodes created through
        // this constructor; the `#[serde(default)]` on the field means
        // sequence JSON that omits it still loads.
        horizon_profile: None,
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
        explicit_transports: None,
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
        api_build_sequence, api_create_filter_node, api_create_target_header_node,
        structured_progress_payload_from_progress_detail, NodeDefinition, SequenceDefinition,
    };
    use nightshade_sequencer::ProgressDetail;

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
            None,
            vec![],
        )
        .expect_err("invalid mosaic JSON should be rejected");

        assert!(err
            .to_string()
            .contains("Invalid target header mosaic panel JSON"));
    }

    /// invalid integration_budget JSON must surface a
    /// clean error message rather than silently dropping the budget.
    /// See `NightshadeError::SerializationError` message contract.
    #[test]
    fn target_header_rejects_invalid_integration_budget_json() {
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
            None,
            Some("{not-valid-json}".to_string()),
            vec![],
        )
        .expect_err("invalid integration_budget JSON should be rejected");

        assert!(err.to_string().contains("Invalid integration_budget JSON"));
    }

    /// a structurally valid integration_budget round-trips
    /// through serde into the serialized NodeDefinition.
    #[test]
    fn target_header_accepts_valid_integration_budget_json() {
        let budget = serde_json::json!({
            "total_secs": 28800.0,
            "per_filter": {
                "L": { "kind": "Ratio", "value": 4.0 },
                "R": { "kind": "Ratio", "value": 1.0 },
                "G": { "kind": "Ratio", "value": 1.0 },
                "B": { "kind": "Ratio", "value": 1.0 }
            },
            "stop_on_budget_met": true
        });
        let node_json = api_create_target_header_node(
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
            None,
            Some(budget.to_string()),
            vec![],
        )
        .expect("budget JSON should deserialize");
        let parsed: NodeDefinition =
            serde_json::from_str(&node_json).expect("node should re-deserialize");
        match parsed.node_type {
            nightshade_sequencer::NodeType::TargetHeader(cfg) => {
                let b = cfg
                    .integration_budget
                    .as_ref()
                    .expect("integration_budget must be populated");
                assert!((b.total_secs - 28_800.0).abs() < f64::EPSILON);
                assert_eq!(b.per_filter.len(), 4);
                assert!(b.stop_on_budget_met);
            }
            other => panic!("expected TargetHeader, got {:?}", other),
        }
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

    #[test]
    fn structured_progress_payload_uses_inner_variant_fields() {
        let detail = ProgressDetail::Exposure {
            frame: 2,
            total: 5,
            duration_secs: 180.0,
        };

        let payload = structured_progress_payload_from_progress_detail(&detail)
            .expect("exposure progress should produce a structured payload");

        assert_eq!(payload.0, "Exposure");
        let parsed: serde_json::Value =
            serde_json::from_str(&payload.1).expect("payload JSON should parse");
        assert_eq!(parsed["frame"], 2);
        assert_eq!(parsed["total"], 5);
        assert_eq!(parsed["duration_secs"], 180.0);
        assert!(parsed.get("Exposure").is_none());
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
    // Why: u32 → f64 widening, exact (f64 mantissa covers
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
    // Why: u32 → f64 widening, exact.
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

// =============================================================================
// LiveStacking broadcast API
// =============================================================================

/// Mirror of the active broadcast session exposed to Dart. Fields are
/// flattened so FRB does not have to bridge the Rust `BroadcastSession`
/// struct directly (the `chrono::DateTime` field would not bridge
/// cleanly).
#[derive(Debug, Clone)]
pub struct LiveStackingBroadcastSnapshot {
    /// Node id of the LiveStacking node that armed the broadcast.
    pub node_id: String,
    /// `broadcast_only` or `record_and_broadcast`.
    pub mode: String,
    /// `average`, `median_rej`, or `sigma`.
    pub stack_method: String,
    pub broadcast_enabled: bool,
    pub broadcast_port: u16,
    pub broadcast_path: String,
    /// Empty string when public (no token required). Non-empty when
    /// `?token=…` is required on every broadcast endpoint.
    pub auth_token: String,
    /// Empty string when no watermark configured. The Dart side does the
    /// variable-interpolation render against the live `${target}` /
    /// `${integration.hms}` context — Rust only carries the raw template.
    pub watermark_template: String,
    pub thumbnail_width: u32,
    pub thumbnail_height: u32,
    pub max_frames_to_stack: u32,
    /// Unix epoch milliseconds the broadcast was armed at.
    pub activated_at_unix_millis: i64,
}

impl From<&nightshade_sequencer::broadcast::BroadcastSession> for LiveStackingBroadcastSnapshot {
    fn from(s: &nightshade_sequencer::broadcast::BroadcastSession) -> Self {
        Self {
            node_id: s.node_id.clone(),
            mode: s.config.mode.as_str().to_string(),
            stack_method: s.config.stack_method.as_str().to_string(),
            broadcast_enabled: s.config.broadcast_enabled,
            broadcast_port: s.config.broadcast_port,
            broadcast_path: s.config.broadcast_path.clone(),
            auth_token: s.config.auth_token.clone().unwrap_or_default(),
            watermark_template: s.config.watermark_text.clone().unwrap_or_default(),
            thumbnail_width: s.config.thumbnail_width,
            thumbnail_height: s.config.thumbnail_height,
            max_frames_to_stack: s.config.max_frames_to_stack,
            activated_at_unix_millis: s.activated_at.timestamp_millis(),
        }
    }
}

/// Returns the currently-active LiveStacking broadcast session, or
/// `None` when no LiveStacking node has been executed in the current
/// sequence run.
///
/// consumed by the Dart `BroadcastService` to decide
/// whether `/api/broadcast/*` endpoints should answer 200 or 404.
#[flutter_rust_bridge::frb(sync)]
pub fn api_broadcast_get_active() -> Option<LiveStackingBroadcastSnapshot> {
    nightshade_sequencer::broadcast::current()
        .as_ref()
        .map(LiveStackingBroadcastSnapshot::from)
}

/// Force-deactivate the active broadcast session. Called by the Dart
/// side when the user toggles broadcast off mid-sequence, or by tests
/// that want a deterministic baseline. A no-op if no session is active.
#[flutter_rust_bridge::frb(sync)]
pub fn api_broadcast_deactivate() {
    if let Some(prev) = nightshade_sequencer::broadcast::deactivate() {
        tracing::info!(
            "LiveStacking broadcast force-deactivated (was node '{}', port {})",
            prev.node_id,
            prev.config.broadcast_port
        );
    }
}

// ============================================================================
// Replay Debug
// ============================================================================

/// Replay Debug — stamp the active `sequence_runs.id` onto the
/// executor so every subsequent emitted DecisionEvent carries it as
/// `sequence_run_id`. Called by the Dart side immediately after the
/// `sequence_runs` row is inserted.
///
/// Pass `None` (Dart `null`) to clear the slot — useful at run end /
/// reset.
pub async fn api_sequencer_set_active_sequence_run_id(
    sequence_run_id: Option<i64>,
) -> Result<(), NightshadeError> {
    let executor = get_sequence_executor().read().await;
    executor.set_active_sequence_run_id(sequence_run_id);
    Ok(())
}

/// Replay Debug — read back the currently-stamped
/// `sequence_runs.id`. Used by tests and as a sanity check from the
/// Dart side.
pub async fn api_sequencer_get_active_sequence_run_id() -> Result<Option<i64>, NightshadeError> {
    let executor = get_sequence_executor().read().await;
    Ok(executor.active_sequence_run_id())
}

/// Replay Debug — runtime toggle for decision emission. When
/// `enabled = false`, the executor short-circuits all decision sends
/// (no channel publish, no allocation) so power users who don't want
/// the replay log can opt out. Defaults to ON.
pub async fn api_sequencer_set_decision_logging_enabled(
    enabled: bool,
) -> Result<(), NightshadeError> {
    let executor = get_sequence_executor().read().await;
    executor.set_decision_logging_enabled(enabled);
    tracing::info!(
        "[REPLAY_DEBUG] decision logging {} (runtime toggle)",
        if enabled { "ENABLED" } else { "DISABLED" }
    );
    Ok(())
}

/// Replay Debug — readback for the runtime toggle.
pub async fn api_sequencer_get_decision_logging_enabled() -> Result<bool, NightshadeError> {
    let executor = get_sequence_executor().read().await;
    Ok(executor.decision_logging_enabled())
}

// =============================================================================
// Adaptive sky-conditions target swap
// =============================================================================
//
// The Dart `AdaptiveSwapService` composes the live ConditionsScore from
// transparency / seeing / cloud cover / wind every ~30s and pushes it
// here. The `TargetScheduler` consults the score on every decision tick
// when `swap_on_conditions_below` is configured. The dashboard reads
// the live state via `api_sequencer_get_adaptive_swap_json` to render
// the "Adaptive Conditions" panel.

/// Push the latest composite sky-conditions score to the executor. All
/// fields are optional because the Dart composer may not have every axis
/// (e.g. no weather station => `wind_score = None`); the score itself
/// is computed by Dart from the available axes using
/// [`ConditionsScoreWeights`].
///
/// Pass `score = None` to clear the slot (telemetry lost — the
/// scheduler then falls back to the ordinary ranking).
#[allow(clippy::too_many_arguments)]
pub async fn api_sequencer_update_conditions_score(
    score: Option<f64>,
    transparency_score: Option<f64>,
    seeing_score: Option<f64>,
    cloud_score: Option<f64>,
    wind_score: Option<f64>,
    transparency_weight: f64,
    seeing_weight: f64,
    cloud_weight: f64,
    wind_weight: f64,
    generated_unix_secs: i64,
) -> Result<(), NightshadeError> {
    use nightshade_sequencer::scheduling::{ConditionsScore, ConditionsScoreWeights};
    let payload = score.map(|s| ConditionsScore {
        score: s,
        transparency_score,
        seeing_score,
        cloud_score,
        wind_score,
        weights: ConditionsScoreWeights {
            transparency_weight,
            seeing_weight,
            cloud_weight,
            wind_weight,
        },
        generated_unix_secs,
    });
    tracing::debug!(
        "[API] update_conditions_score: {:?}",
        payload.as_ref().map(|p| p.score)
    );
    let executor = get_sequence_executor().read().await;
    executor.update_conditions_score(payload).await;
    Ok(())
}

/// JSON-serialised snapshot of the live conditions score + adaptive
/// swap accounting (last swap timestamp, current tier, hysteresis
/// countdown info) for the Run Dashboard "Adaptive Conditions" panel.
/// Returns `Ok(None)` when no telemetry has been pushed since startup.
pub async fn api_sequencer_get_adaptive_swap_json() -> Result<Option<String>, NightshadeError> {
    let executor = get_sequence_executor().read().await;
    Ok(executor.current_adaptive_swap_json().await)
}

#[cfg(test)]
mod executor_site_tests {
    use super::{api_sequencer_start, get_sequence_executor};
    use crate::api::get_state;
    use crate::storage::ObserverLocation;

    /// A run must not be able to start without the site the app already knows.
    ///
    /// The executor's latitude/longitude is the ONLY input to the altitude
    /// stamped on every frame's `captured_images` row, and until this seeding
    /// existed the only writer was Dart's `sequencerUpdateLocation`. A run
    /// started before that push produced files with AIRMASS (the FITS writer
    /// has its own fallback to app settings) and rows without it — and the
    /// AAVSO exporter reads the row, so it submitted `na` for frames whose own
    /// header knew the answer.
    #[tokio::test]
    async fn starting_a_run_seeds_the_site_from_app_settings() {
        let _serialized = crate::api::devices::simulation::sim_singleton_test_lock()
            .lock()
            .await;
        {
            // The gap under test: nothing has pushed a location for this run.
            get_sequence_executor()
                .write()
                .await
                .update_location(None, None)
                .await;
        }
        get_state()
            .set_observer_location(Some(ObserverLocation {
                latitude: 41.5,
                longitude: -71.25,
                elevation: 30.0,
            }))
            .expect("test site should be settable");

        // No sequence is loaded, so the start itself fails. That is fine and is
        // the point: the site has to be in place BEFORE the run can begin, so
        // the seeding must not be conditional on the start succeeding.
        let _ = api_sequencer_start().await;

        let executor = get_sequence_executor().read().await;
        assert_eq!(
            (executor.latitude, executor.longitude),
            (Some(41.5), Some(-71.25)),
            "the run started with no observing site even though app settings had one"
        );
    }
}

#[cfg(test)]
mod frame_event_capture_tests {
    use super::typed_sequencer_event_from_progress_detail;
    use crate::event::SequencerEvent;
    use nightshade_sequencer::scheduling::FrameCaptureMetadata;
    use nightshade_sequencer::ProgressDetail;

    /// One populated capture payload. Deliberately all-distinct and non-default
    /// so a `Default::default()` in the mapping cannot pass for the real thing.
    fn populated_capture() -> FrameCaptureMetadata {
        FrameCaptureMetadata {
            gain: Some(139),
            offset: Some(21),
            sensor_temp_c: Some(-9.5),
            cooler_power_percent: Some(63.5),
            mount_ra_hours: Some(5.5),
            mount_dec_degrees: Some(-5.25),
            mount_altitude_deg: Some(48.5),
            mount_azimuth_deg: Some(171.25),
            pier_side: Some("West".to_string()),
            focuser_position: Some(31_705),
            focuser_temperature_c: Some(4.25),
            rotator_angle_deg: Some(212.5),
            exposure_secs: 120.0,
            bin_x: 2,
            bin_y: 2,
            frame_type: "Dark".to_string(),
            target_id: Some("tgt-evt".to_string()),
        }
    }

    /// The hop out of the sequencer's own progress payload and onto the typed
    /// FRB event Dart receives.
    ///
    /// A verifier replaced both arms' `capture: capture.into()` with
    /// `Default::default()` and all 1159 bridge tests stayed green — the whole
    /// per-frame metadata path is dead from here on, and `captured_images` goes
    /// back to NULL gain / offset / temperature / pointing, with the FITS file
    /// on disk still carrying every one of them. Nothing else crosses this
    /// boundary, so nothing else can catch it.
    #[test]
    fn accepted_frame_event_forwards_the_capture_payload() {
        let capture = populated_capture();
        let detail = ProgressDetail::FrameAccepted {
            frame: 7,
            total: 10,
            hfr: Some(2.4),
            eccentricity: Some(0.31),
            star_count: Some(412),
            accepted_total: 7,
            rejected_total: 0,
            save_path: Some("/captures/evt_0007.fits".to_string()),
            capture: capture.clone(),
        };

        let event = typed_sequencer_event_from_progress_detail("node-7", &detail)
            .expect("FrameAccepted has a typed bridge variant");

        match event {
            SequencerEvent::FrameAccepted {
                capture: forwarded, ..
            } => assert_eq!(forwarded, (&capture).into()),
            other => panic!("expected FrameAccepted, got {:?}", other),
        }
    }

    #[test]
    fn rejected_frame_event_forwards_the_capture_payload() {
        // A rejected frame is still on disk and still gets a row, so this arm
        // carries exactly the same obligation as the accepted one — and drifted
        // apart from it precisely because nothing held the two together.
        let capture = populated_capture();
        let detail = ProgressDetail::FrameRejected {
            frame: 8,
            total: 10,
            reason: "HFR 4.9 above threshold 3.5".to_string(),
            hfr: Some(4.9),
            eccentricity: Some(0.62),
            star_count: Some(88),
            reject_path: "/captures/Reject/evt_0008.fits".to_string(),
            consecutive_rejects: 1,
            accepted_total: 7,
            rejected_total: 1,
            likely_cause: None,
            evidence: Vec::new(),
            sky_brightness_at_capture: None,
            cloud_cover_at_capture: None,
            wind_at_capture: None,
            guide_rms_at_capture: None,
            sensor_temp_at_capture: None,
            capture: capture.clone(),
        };

        let event = typed_sequencer_event_from_progress_detail("node-7", &detail)
            .expect("FrameRejected has a typed bridge variant");

        match event {
            SequencerEvent::FrameRejected {
                capture: forwarded, ..
            } => assert_eq!(forwarded, (&capture).into()),
            other => panic!("expected FrameRejected, got {:?}", other),
        }
    }
}

#[cfg(test)]
mod event_bridge_idempotence_tests {
    use super::{api_sequencer_subscribe_events, get_sequence_executor};

    /// Wait for the executor's event-broadcast receiver count to stop changing,
    /// so the assertion is not racing the supervised task's first `subscribe()`.
    async fn settled_subscriber_count() -> usize {
        let mut last = usize::MAX;
        for _ in 0..40 {
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
            let count = get_sequence_executor()
                .read()
                .await
                .event_subscriber_count();
            if count == last {
                return count;
            }
            last = count;
        }
        last
    }

    /// The Dart bridge calls `sequencerSubscribeEvents()` at the top of EVERY
    /// `sequencerStart()`, and the headless API reaches the same entry point, so
    /// a second run in one app launch called this a second time. Each call
    /// spawned two fresh supervised tasks, each with its own receiver on the
    /// executor's broadcast channel and each republishing everything onto the
    /// unified event stream — which is why one failed node produced two
    /// identical Critical toasts and two Session Report lines.
    ///
    /// Asserts the RECEIVER count on the executor, not a call counter: the
    /// defect is a second live listener, and only that number can tell whether
    /// events are being duplicated.
    #[tokio::test]
    async fn subscribing_again_does_not_add_a_second_event_listener() {
        api_sequencer_subscribe_events()
            .await
            .expect("first subscribe should succeed");
        let after_first = settled_subscriber_count().await;
        assert_eq!(
            after_first, 1,
            "the bridge should hold exactly one listener after the first subscribe"
        );

        // What a second sequence run in the same app launch does.
        api_sequencer_subscribe_events()
            .await
            .expect("second subscribe should still succeed");
        api_sequencer_subscribe_events()
            .await
            .expect("third subscribe should still succeed");

        assert_eq!(
            settled_subscriber_count().await,
            1,
            "re-subscribing must not stand up another listener; a second one \
             duplicates every sequencer event on the way to the UI"
        );
    }
}
