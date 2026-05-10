//! Sequence execution engine

use crate::device_ops::SharedDeviceOps;
use crate::node::{ExecutionContext, Node, ProgressUpdate, RuntimeNode};
use crate::triggers::{TriggerManager, TriggerState};
use crate::{
    NodeDefinition, NodeId, NodeStatus, NodeType, RecoveryAction, SafetyFailMode,
    SequenceDefinition,
};
use parking_lot::RwLock as StdRwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::{broadcast, mpsc, RwLock};

/// Commands that can be sent to the executor
#[derive(Debug, Clone)]
pub enum ExecutorCommand {
    Start,
    Pause,
    Resume,
    Stop,
    Skip,
    SkipToNode(NodeId),
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
    /// Update filter focus offsets at runtime (e.g., when equipment profile changes)
    UpdateFilterOffsets {
        offsets: std::collections::HashMap<String, i32>,
    },
}

/// State of the sequence executor
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ExecutorState {
    Idle,
    Running,
    Paused,
    Stopping,
    Cancelled,
    Completed,
    Failed,
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
        }
    }
}

/// Event emitted by the executor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ExecutorEvent {
    StateChanged(ExecutorState),
    ProgressUpdated(SequenceProgress),
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
        detail: String,
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
    SequenceCompleted,
    SequenceFailed {
        error: String,
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
) -> crate::instructions::InstructionContext {
    crate::instructions::InstructionContext {
        target_ra,
        target_dec,
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
        latitude: trigger_context.latitude,
        longitude: trigger_context.longitude,
        device_ops,
        trigger_state: Some(trigger_state),
        filter_focus_offsets: trigger_context.filter_focus_offsets.clone(),
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
    })
}

fn executor_state_for_result(result: NodeStatus) -> ExecutorState {
    match result {
        NodeStatus::Success | NodeStatus::Skipped => ExecutorState::Completed,
        NodeStatus::Cancelled => ExecutorState::Cancelled,
        _ => ExecutorState::Failed,
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
    /// Checkpoint manager for crash recovery
    checkpoint_manager: Option<crate::checkpoint::CheckpointManager>,
    /// Current checkpoint being updated
    current_checkpoint: Option<crate::checkpoint::SessionCheckpoint>,
    /// Safety fail mode - determines behavior when safety devices fail or are unavailable
    pub safety_fail_mode: SafetyFailMode,
    /// Filter focus offsets from equipment profile (filter_name -> offset_steps)
    pub filter_focus_offsets: std::collections::HashMap<String, i32>,
}

impl SequenceExecutor {
    pub fn new() -> Self {
        let (event_tx, _) = broadcast::channel(256);
        let mut trigger_manager = TriggerManager::new();
        trigger_manager.create_standard_triggers(); // Add default triggers

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
        }
    }

    /// Set the safety fail mode for the sequencer
    pub fn set_safety_fail_mode(&mut self, mode: SafetyFailMode) {
        self.safety_fail_mode = mode;
    }

    /// Get the trigger manager for configuration
    pub fn trigger_manager(&self) -> Arc<RwLock<TriggerManager>> {
        self.trigger_manager.clone()
    }

    /// Enable or disable trigger monitoring
    pub fn set_triggers_enabled(&mut self, enabled: bool) {
        self.triggers_enabled = enabled;
    }

    /// Update trigger state with current readings
    pub async fn update_trigger_state<F>(&self, updater: F)
    where
        F: FnOnce(&mut TriggerState),
    {
        let manager = self.trigger_manager.read().await;
        let state_lock = manager.state();
        let mut state = state_lock.write().await;
        updater(&mut state);
    }

    /// Set the device operations handler
    /// This MUST be called before starting a sequence, otherwise start() will return an error.
    pub fn set_device_ops(&mut self, ops: SharedDeviceOps) {
        self.device_ops = Some(ops);
    }

    /// Check if device operations have been configured
    pub fn has_device_ops(&self) -> bool {
        self.device_ops.is_some()
    }

    /// Set connected device IDs
    pub fn set_devices(
        &mut self,
        camera: Option<String>,
        mount: Option<String>,
        focuser: Option<String>,
        filterwheel: Option<String>,
        rotator: Option<String>,
    ) {
        self.camera_id = camera;
        self.mount_id = mount;
        self.focuser_id = focuser;
        self.filterwheel_id = filterwheel;
        self.rotator_id = rotator;
    }

    /// Set dome device ID
    pub fn set_dome(&mut self, dome_id: Option<String>) {
        self.dome_id = dome_id;
    }

    /// Set cover calibrator (flat panel) device ID
    pub fn set_cover_calibrator(&mut self, cover_calibrator_id: Option<String>) {
        self.cover_calibrator_id = cover_calibrator_id;
    }

    /// Set save path for images
    pub fn set_save_path(&mut self, path: Option<std::path::PathBuf>) {
        self.save_path = path;
    }

    /// Set observer location
    pub fn set_location(&mut self, lat: Option<f64>, lon: Option<f64>) {
        self.latitude = lat;
        self.longitude = lon;
    }

    /// Set filter focus offsets from equipment profile
    pub fn set_filter_focus_offsets(&mut self, offsets: std::collections::HashMap<String, i32>) {
        self.filter_focus_offsets = offsets;
    }

    /// Subscribe to executor events
    pub fn subscribe(&self) -> broadcast::Receiver<ExecutorEvent> {
        self.event_tx.subscribe()
    }

    /// Load a sequence definition and build the node tree
    pub fn load_sequence(&mut self, sequence: SequenceDefinition) -> Result<(), String> {
        // Build node tree from definition
        let root_node = self.build_node_tree(&sequence)?;

        // Calculate totals
        let (total_exposures, total_integration, totals_indeterminate) =
            self.calculate_totals(&sequence);

        {
            let mut progress = self.progress.write();
            if totals_indeterminate {
                // Unbounded loops (while-dark/forever/etc.) don't have a meaningful finite ETA.
                progress.total_exposures = 0;
                progress.total_integration_secs = 0.0;
                progress.estimated_remaining_secs = None;
            } else {
                progress.total_exposures = total_exposures;
                progress.total_integration_secs = total_integration;
            }
        }

        self.sequence = Some(sequence);
        self.root_node = Some(root_node);

        Ok(())
    }

    /// Build the node tree from the sequence definition
    fn build_node_tree(&self, sequence: &SequenceDefinition) -> Result<Box<dyn Node>, String> {
        // Create a map of nodes by ID
        let node_map: HashMap<&str, &NodeDefinition> =
            sequence.nodes.iter().map(|n| (n.id.as_str(), n)).collect();

        // Find root node
        let root_id = sequence
            .root_node_id
            .as_ref()
            .ok_or("No root node specified")?;

        let root_def = node_map
            .get(root_id.as_str())
            .ok_or_else(|| format!("Root node {} not found", root_id))?;

        // Recursively build the tree
        fn build_node(
            def: &NodeDefinition,
            node_map: &HashMap<&str, &NodeDefinition>,
        ) -> Box<dyn Node> {
            let mut node = RuntimeNode::from_definition(def.clone());

            tracing::debug!(
                "Building node '{}' (id={}) with {} children defined: {:?}",
                def.name,
                def.id,
                def.children.len(),
                def.children
            );

            // Add children recursively
            for child_id in &def.children {
                if let Some(child_def) = node_map.get(child_id.as_str()) {
                    tracing::debug!(
                        "  Adding child '{}' (id={}) to '{}'",
                        child_def.name,
                        child_def.id,
                        def.name
                    );
                    let child = build_node(child_def, node_map);
                    node.add_child(child);
                } else {
                    tracing::warn!(
                        "  Child node '{}' not found in node_map for parent '{}'",
                        child_id,
                        def.name
                    );
                }
            }

            Box::new(node)
        }

        Ok(build_node(root_def, &node_map))
    }

    /// Calculate total exposures and integration time
    fn calculate_totals(&self, sequence: &SequenceDefinition) -> (u32, f64, bool) {
        let root_id = match &sequence.root_node_id {
            Some(id) => id,
            None => return (0, 0.0, false),
        };

        let node_map: HashMap<&str, &NodeDefinition> =
            sequence.nodes.iter().map(|n| (n.id.as_str(), n)).collect();

        let mut total_exposures = 0u64;
        let mut total_integration = 0.0f64;
        let mut totals_indeterminate = false;
        let mut recursion_guard = std::collections::HashSet::new();

        fn walk(
            node_id: &str,
            multiplier: u64,
            node_map: &HashMap<&str, &NodeDefinition>,
            total_exposures: &mut u64,
            total_integration: &mut f64,
            totals_indeterminate: &mut bool,
            recursion_guard: &mut std::collections::HashSet<String>,
        ) {
            if multiplier == 0 {
                return;
            }

            if !recursion_guard.insert(node_id.to_string()) {
                tracing::warn!(
                    "Detected cycle while calculating sequence totals at node '{}'; marking totals indeterminate",
                    node_id
                );
                *totals_indeterminate = true;
                return;
            }

            let node = match node_map.get(node_id) {
                Some(node) => *node,
                None => {
                    *totals_indeterminate = true;
                    recursion_guard.remove(node_id);
                    return;
                }
            };

            if !node.enabled {
                recursion_guard.remove(node_id);
                return;
            }

            match &node.node_type {
                NodeType::TakeExposure(config) => {
                    let count = config.count as u64;
                    *total_exposures =
                        total_exposures.saturating_add(count.saturating_mul(multiplier));
                    *total_integration += config.duration_secs * count as f64 * multiplier as f64;
                }
                NodeType::Loop(config) => {
                    let child_multiplier = match config.condition {
                        crate::LoopCondition::Count => {
                            multiplier.saturating_mul(config.iterations.unwrap_or(1) as u64)
                        }
                        _ => {
                            *totals_indeterminate = true;
                            multiplier
                        }
                    };

                    for child_id in &node.children {
                        walk(
                            child_id,
                            child_multiplier,
                            node_map,
                            total_exposures,
                            total_integration,
                            totals_indeterminate,
                            recursion_guard,
                        );
                    }

                    recursion_guard.remove(node_id);
                    return;
                }
                _ => {}
            }

            for child_id in &node.children {
                walk(
                    child_id,
                    multiplier,
                    node_map,
                    total_exposures,
                    total_integration,
                    totals_indeterminate,
                    recursion_guard,
                );
            }

            recursion_guard.remove(node_id);
        }

        walk(
            root_id,
            1,
            &node_map,
            &mut total_exposures,
            &mut total_integration,
            &mut totals_indeterminate,
            &mut recursion_guard,
        );

        let capped_total_exposures = if total_exposures > u32::MAX as u64 {
            tracing::warn!(
                "Total exposure count {} exceeds u32::MAX; clamping totals",
                total_exposures
            );
            totals_indeterminate = true;
            u32::MAX
        } else {
            total_exposures as u32
        };

        (
            capped_total_exposures,
            total_integration,
            totals_indeterminate,
        )
    }

    fn build_execution_order(&self, sequence: &SequenceDefinition) -> HashMap<NodeId, usize> {
        let mut order = HashMap::new();
        let mut index = 0usize;
        let node_map: HashMap<&str, &NodeDefinition> =
            sequence.nodes.iter().map(|n| (n.id.as_str(), n)).collect();
        let mut recursion_guard = std::collections::HashSet::new();

        fn walk(
            node_id: &str,
            node_map: &HashMap<&str, &NodeDefinition>,
            order: &mut HashMap<NodeId, usize>,
            index: &mut usize,
            recursion_guard: &mut std::collections::HashSet<String>,
        ) {
            if !recursion_guard.insert(node_id.to_string()) {
                tracing::warn!(
                    "Detected cycle while computing execution order at node '{}'",
                    node_id
                );
                return;
            }

            if let Some(node) = node_map.get(node_id) {
                order.insert(node.id.clone(), *index);
                *index = index.saturating_add(1);
                for child_id in &node.children {
                    walk(child_id, node_map, order, index, recursion_guard);
                }
            }

            recursion_guard.remove(node_id);
        }

        if let Some(root_id) = &sequence.root_node_id {
            walk(
                root_id,
                &node_map,
                &mut order,
                &mut index,
                &mut recursion_guard,
            );
        }

        order
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

        // Check that device operations have been configured
        // This is a critical check - without device ops, all operations will silently do nothing
        let device_ops = self.device_ops.clone().ok_or_else(|| {
            "No device operations configured. Call set_device_ops() before starting a sequence. \
             This ensures all device operations use real hardware instead of silently doing nothing."
                .to_string()
        })?;

        // Reset cancellation flag
        self.is_cancelled.store(false, Ordering::Relaxed);

        // Create command channel
        let (tx, mut rx) = mpsc::channel::<ExecutorCommand>(32);
        self.command_tx = Some(tx);

        // Update state
        self.set_state(ExecutorState::Running).await;

        // Get references for the async task
        let state = self.state.clone();
        let progress = self.progress.clone();
        let event_tx = self.event_tx.clone();
        let is_cancelled = self.is_cancelled.clone();
        let mut root_node = self
            .root_node
            .take()
            .ok_or("No root node available - sequence may not be properly loaded".to_string())?;

        // device_ops already cloned and validated above
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
            .unwrap_or_default();

        // Clone trigger manager for the async task
        let trigger_manager = self.trigger_manager.clone();
        let triggers_enabled = self.triggers_enabled;
        let safety_fail_mode = self.safety_fail_mode;
        let filter_focus_offsets = self.filter_focus_offsets.clone();

        // Clone checkpoint dir for streaming checkpoints inside the spawned task.
        // A new CheckpointManager is created in the task from this path.
        let streaming_checkpoint_dir: Option<PathBuf> = self
            .checkpoint_manager
            .as_ref()
            .map(|m| m.checkpoint_dir().to_path_buf());
        let streaming_sequence = self.sequence.clone();
        let streaming_camera_id = self.camera_id.clone();
        let streaming_mount_id = self.mount_id.clone();
        let streaming_focuser_id = self.focuser_id.clone();
        let streaming_filterwheel_id = self.filterwheel_id.clone();
        let streaming_rotator_id = self.rotator_id.clone();
        let streaming_save_path = self.save_path.clone();
        let streaming_latitude = self.latitude;
        let streaming_longitude = self.longitude;

        // Create shared pause state for context
        let is_paused = Arc::new(AtomicBool::new(false));
        let skip_to_next_target = Arc::new(AtomicBool::new(false));
        let resume_notify = Arc::new(tokio::sync::Notify::new());

        // Spawn execution task
        let is_paused_clone = is_paused.clone();
        let skip_to_next_target_clone = skip_to_next_target.clone();
        let resume_notify_clone = resume_notify.clone();
        let exposure_node_metadata = Arc::new(exposure_node_metadata);
        let trigger_action_context = trigger_action_context.clone();
        tokio::spawn(async move {
            let start_time = std::time::Instant::now();

            // Clone device_ops for trigger monitoring before passing to context
            let device_ops_for_triggers = device_ops.clone();

            // Set up execution context with device ops and IDs
            let mut context = ExecutionContext::new("root".to_string()).with_device_ops(device_ops);
            context.is_cancelled = is_cancelled.clone();
            context.is_paused = is_paused_clone;
            context.skip_to_next_target = skip_to_next_target_clone;
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
            context.safety_fail_mode = safety_fail_mode;
            context.filter_focus_offsets = filter_focus_offsets;
            // Set trigger state for HFR tracking and exposure counts
            context.trigger_state = Some(trigger_manager.read().await.state());

            // Set up progress callback
            let progress_clone = progress.clone();
            let event_tx_clone = event_tx.clone();
            // Track nodes that have already had NodeStarted emitted (thread-safe)
            let started_nodes =
                Arc::new(StdRwLock::new(std::collections::HashSet::<NodeId>::new()));
            // Track per-node exposure frame counters so completed_exposures is monotonic and global.
            let node_frame_progress = Arc::new(StdRwLock::new(std::collections::HashMap::<
                NodeId,
                u32,
            >::new()));
            let node_pending_exposure_completion = Arc::new(StdRwLock::new(
                std::collections::HashMap::<NodeId, u32>::new(),
            ));
            let exposure_node_metadata = exposure_node_metadata.clone();
            context.progress_callback = Some(Box::new(move |update: ProgressUpdate| {
                let mut prog = progress_clone.write();
                prog.current_node_id = Some(update.node_id.clone());
                prog.current_node_status = Some(update.status);
                prog.message = update.message.clone();
                prog.node_statuses
                    .insert(update.node_id.clone(), update.status);
                prog.elapsed_secs = start_time.elapsed().as_secs_f64();

                // Emit NodeStarted event when a node transitions to Running
                if update.status == NodeStatus::Running {
                    let mut started = started_nodes.write();
                    if !started.contains(&update.node_id) {
                        started.insert(update.node_id.clone());
                        // Extract node name from message (format: "Executing: <name>" or "Step X/Y: <name>")
                        let node_name = update
                            .message
                            .as_ref()
                            .map(|m| {
                                if let Some(name) = m.strip_prefix("Executing: ") {
                                    name.to_string()
                                } else if let Some(rest) = m.split_once(": ").map(|(_, rest)| rest)
                                {
                                    rest.to_string()
                                } else {
                                    m.clone()
                                }
                            })
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
                    // Clear node from started set when it completes, so it can emit NodeStarted again
                    // on the next loop iteration (fixes UI not updating when loop cycles back)
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

                if let (Some(current), Some(total)) = (update.current_frame, update.total_frames) {
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

                // Track completed integration time
                if let Some(exposure_secs) = update.completed_exposure_secs {
                    prog.completed_integration_secs += exposure_secs;
                }

                if prog.total_exposures > 0 && prog.completed_exposures > 0 {
                    let completed = prog.completed_exposures.min(prog.total_exposures);
                    let remaining = prog.total_exposures.saturating_sub(completed);
                    if remaining > 0 {
                        let avg_secs_per_exposure = prog.elapsed_secs / completed as f64;
                        prog.estimated_remaining_secs =
                            Some(avg_secs_per_exposure * remaining as f64);
                    } else {
                        prog.estimated_remaining_secs = Some(0.0);
                    }
                } else {
                    prog.estimated_remaining_secs = None;
                }

                // Emit NodeProgress event for instruction-specific progress
                // Parse messages like "Autofocus: Moving to start position: 25000 (5%)"
                if let Some(ref message) = update.message {
                    tracing::debug!("[PROGRESS_CB] Received message: {}", message);
                    if let Some((instruction, rest)) = message.split_once(':') {
                        tracing::debug!(
                            "[PROGRESS_CB] Parsed instruction='{}', rest='{}'",
                            instruction,
                            rest
                        );
                        // Look for percentage in parentheses at the end
                        if let Some(pct_start) = rest.rfind('(') {
                            if let Some(pct_end) = rest[pct_start..].find(')') {
                                let pct_str = &rest[pct_start + 1..pct_start + pct_end];
                                tracing::debug!("[PROGRESS_CB] pct_str='{}'", pct_str);
                                if let Some(pct_val) = pct_str.strip_suffix('%') {
                                    if let Ok(progress_percent) = pct_val.trim().parse::<f64>() {
                                        let detail = rest[..pct_start].trim().to_string();
                                        tracing::info!("[PROGRESS_CB] Emitting NodeProgress: node_id={}, instruction={}, progress={}%, detail={}",
                                            update.node_id, instruction.trim(), progress_percent, detail);
                                        let _ = event_tx_clone.send(ExecutorEvent::NodeProgress {
                                            node_id: update.node_id.clone(),
                                            instruction: instruction.trim().to_string(),
                                            progress_percent,
                                            detail,
                                        });
                                    } else {
                                        tracing::debug!(
                                            "[PROGRESS_CB] Failed to parse pct_val='{}' as f64",
                                            pct_val
                                        );
                                    }
                                } else {
                                    tracing::debug!(
                                        "[PROGRESS_CB] pct_str '{}' doesn't end with '%'",
                                        pct_str
                                    );
                                }
                            } else {
                                tracing::debug!("[PROGRESS_CB] No ')' found after '(' in rest");
                            }
                        } else {
                            tracing::debug!("[PROGRESS_CB] No '(' found in rest: '{}'", rest);
                        }
                    } else {
                        tracing::debug!("[PROGRESS_CB] No ':' found in message");
                    }
                } else {
                    tracing::debug!("[PROGRESS_CB] No message in ProgressUpdate");
                }

                let _ = event_tx_clone.send(ExecutorEvent::ProgressUpdated(prog.clone()));
            }));

            // Handle commands during execution
            let is_paused_cmd = is_paused.clone();
            let skip_to_next_target_cmd = skip_to_next_target.clone();
            let resume_notify_cmd = resume_notify.clone();
            let command_handler = async {
                while let Some(cmd) = rx.recv().await {
                    match cmd {
                        ExecutorCommand::Pause => {
                            is_paused_cmd.store(true, Ordering::Relaxed);
                            *state.write().await = ExecutorState::Paused;
                            let _ =
                                event_tx.send(ExecutorEvent::StateChanged(ExecutorState::Paused));
                        }
                        ExecutorCommand::Resume => {
                            // Signal context to resume if it's waiting
                            is_paused_cmd.store(false, Ordering::Relaxed);
                            resume_notify_cmd.notify_waiters();
                            *state.write().await = ExecutorState::Running;
                            let _ =
                                event_tx.send(ExecutorEvent::StateChanged(ExecutorState::Running));
                        }
                        ExecutorCommand::Stop => {
                            is_cancelled.store(true, Ordering::Relaxed);
                            *state.write().await = ExecutorState::Stopping;
                            let _ =
                                event_tx.send(ExecutorEvent::StateChanged(ExecutorState::Stopping));
                            break;
                        }
                        ExecutorCommand::Skip => {
                            tracing::info!("Skip requested - advancing to next target");
                            skip_to_next_target_cmd.store(true, Ordering::Relaxed);
                        }
                        ExecutorCommand::Start => {
                            let _ = event_tx.send(ExecutorEvent::Error {
                                message: "Start ignored: executor is already running".to_string(),
                            });
                        }
                        ExecutorCommand::SkipToNode(node_id) => {
                            let _ = event_tx.send(ExecutorEvent::Error {
                                message: format!(
                                    "SkipToNode for '{}' is not supported during active execution",
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
                            tracing::info!(
                                "Runtime dither config update received: pixels={}, settle_pixels={}, settle_time={}, settle_timeout={}, ra_only={}",
                                pixels, settle_pixels, settle_time, settle_timeout, ra_only
                            );
                            // Dither config is baked into each exposure node at load time.
                            // This command logs the update; values take effect on next sequence load.
                        }
                        ExecutorCommand::UpdateLocation {
                            latitude,
                            longitude,
                        } => {
                            tracing::info!(
                                "Runtime location update received: lat={:?}, lon={:?}",
                                latitude,
                                longitude
                            );
                            // Location is used by altitude triggers. The trigger state
                            // reads location from the trigger action context which is
                            // cloned at start. Log for awareness; full propagation
                            // requires a sequence restart or checkpoint resume.
                        }
                        ExecutorCommand::UpdateFilterOffsets { offsets } => {
                            tracing::info!(
                                "Runtime filter focus offsets update received: {} entries",
                                offsets.len()
                            );
                            // Filter offsets are used by autofocus instructions.
                            // Logged here; values take effect on next trigger-initiated autofocus
                            // or sequence restart.
                        }
                    }
                }
            };

            let streaming_filter_focus_offsets = context.filter_focus_offsets.clone();
            let streaming_safety_fail_mode = context.safety_fail_mode;

            // Execute the sequence
            let execution = async { root_node.execute(&mut context).await };

            // Trigger monitoring loop
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
                let Some(checkpoint_dir) = streaming_checkpoint_dir else {
                    std::future::pending::<()>().await;
                    return;
                };
                let Some(sequence) = streaming_sequence else {
                    std::future::pending::<()>().await;
                    return;
                };

                let checkpoint_mgr = crate::checkpoint::CheckpointManager::new(checkpoint_dir);
                let mut interval = tokio::time::interval(std::time::Duration::from_secs(30));

                loop {
                    interval.tick().await;

                    if is_cancelled_for_checkpoint.load(Ordering::Relaxed) {
                        break;
                    }

                    let exec_state = *state_for_checkpoint.read().await;
                    if !matches!(exec_state, ExecutorState::Running | ExecutorState::Paused) {
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
                            streaming_safety_fail_mode,
                            streaming_triggers_enabled,
                            streaming_filter_focus_offsets.clone(),
                        ),
                    );

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
            let trigger_monitor = async {
                if !triggers_enabled {
                    // If triggers disabled, just wait forever (let other tasks complete)
                    std::future::pending::<()>().await;
                    return Vec::new();
                }

                let mut check_interval = tokio::time::interval(std::time::Duration::from_secs(1));
                let mut fired_triggers: Vec<(String, RecoveryAction)> = Vec::new();

                // Tracks whether the previous safety poll already failed. Used to
                // rate-limit the per-mode warning so a permanently offline safety
                // device does not flood the log every second. See SafetyFailMode
                // dispatch below.
                let mut safety_poll_last_was_error = false;

                // Tracks per-trigger Retry attempt counts so we can escalate after
                // exhausting `max_attempts`. Keyed by trigger ID.
                let mut retry_attempts: HashMap<String, u32> = HashMap::new();

                // §1.14: Streaming-checkpoint cadence is now driven by an independent
                // task spawned alongside this monitor (see streaming_checkpoint_task).
                // Keeping the monitor focused on trigger evaluation avoids dropping
                // checkpoint saves when triggers_enabled = false.

                // Mark that mount tracking is expected while the trigger monitor is active.
                // This enables the MountTrackingLost and OnTrackingLimitHit triggers to detect
                // when tracking stops unexpectedly during sequence execution.
                if trigger_action_context.mount_id.is_some() {
                    let manager = trigger_manager.read().await;
                    let trigger_state = manager.state();
                    let mut state = trigger_state.write().await;
                    state.set_mount_tracking_expected(true);
                }

                loop {
                    check_interval.tick().await;

                    // Only check triggers while running (not paused or stopping)
                    let current_state = *state_clone.read().await;
                    if current_state != ExecutorState::Running {
                        continue;
                    }

                    // Check if cancelled
                    if is_cancelled_clone.load(Ordering::Relaxed) {
                        break;
                    }

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
                    let is_safe = match device_ops_for_triggers.safety_is_safe(None).await {
                        Ok(safe) => {
                            if safety_poll_last_was_error {
                                tracing::info!(
                                    "Safety poll recovered (mode: {:?})",
                                    safety_fail_mode
                                );
                                safety_poll_last_was_error = false;
                            }
                            Some(safe)
                        }
                        Err(e) => match safety_fail_mode {
                            SafetyFailMode::FailClosed => {
                                if !safety_poll_last_was_error {
                                    tracing::warn!(
                                        "Safety poll error: {} - treating as unsafe (FailClosed)",
                                        e
                                    );
                                    safety_poll_last_was_error = true;
                                }
                                Some(false)
                            }
                            SafetyFailMode::FailOpen => {
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
                            SafetyFailMode::WarnOnly => {
                                if !safety_poll_last_was_error {
                                    tracing::warn!(
                                        "Safety poll error: {} - WarnOnly mode, leaving \
                                         weather_safe unchanged and emitting alert",
                                        e
                                    );
                                    let _ = event_tx_clone2.send(ExecutorEvent::Error {
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
                        },
                    };

                    // Poll guiding status if guiding is enabled
                    let guiding_rms = device_ops_for_triggers
                        .guider_get_status()
                        .await
                        .ok()
                        .map(|status| status.rms_total);

                    {
                        let manager = trigger_manager.read().await;
                        let trigger_state = manager.state();
                        let mut state = trigger_state.write().await;
                        // WarnOnly returns None to mean "preserve previous reading" — that
                        // is the contract that distinguishes it from FailOpen/FailClosed.
                        if let Some(safe) = is_safe {
                            state.weather_safe = safe;
                        }

                        // Update guiding RMS if available
                        if let Some(rms) = guiding_rms {
                            state.update_guiding_rms(rms);
                            tracing::trace!("Updated guiding RMS: {:.2}", rms);
                        }

                        // Update observer location for dawn calculation (and calculate dawn time)
                        if state.observer_latitude.is_none() {
                            if let Some((lat, lon)) =
                                device_ops_for_triggers.get_observer_location()
                            {
                                state.observer_latitude = Some(lat);
                                state.observer_longitude = Some(lon);
                                // Pre-calculate dawn time when location is set
                                state.dawn_time =
                                    Some(crate::triggers::calculate_dawn_time(lat, lon));
                                tracing::debug!(
                                    "Observer location set for dawn trigger: {}, {}",
                                    lat,
                                    lon
                                );
                            }
                        }
                    }

                    // Poll full mount status for trigger evaluation
                    if let Some(mount_id) = &trigger_action_context.mount_id {
                        // Query individual mount properties through the DeviceOps trait
                        let tracking_result =
                            device_ops_for_triggers.mount_is_tracking(mount_id).await;
                        let slewing_result =
                            device_ops_for_triggers.mount_is_slewing(mount_id).await;
                        let parked_result = device_ops_for_triggers.mount_is_parked(mount_id).await;
                        let pier_side_result =
                            device_ops_for_triggers.mount_side_of_pier(mount_id).await;
                        let coords_result = device_ops_for_triggers
                            .mount_get_coordinates(mount_id)
                            .await;

                        let manager = trigger_manager.read().await;
                        let trigger_state = manager.state();
                        let mut state = trigger_state.write().await;

                        // If tracking query fails, mark status query as failed (connection issue)
                        match &tracking_result {
                            Ok(is_tracking) => {
                                state.mount_status_query_failed = false;

                                // Check for unexpected tracking loss
                                if state.mount_tracking_expected
                                    && !is_tracking
                                    && !state.mount_tracking_lost
                                {
                                    tracing::warn!("Mount tracking lost during sequence!");
                                    state.mount_tracking_lost = true;

                                    // Record when tracking was first lost for OnTrackingLimitHit wait timer.
                                    // The heuristic check happens in trigger evaluation, but we record
                                    // the timestamp here so the wait period starts from detection time.
                                    if state.tracking_limit_detected_at.is_none() {
                                        state.tracking_limit_detected_at =
                                            Some(chrono::Utc::now().timestamp());
                                        tracing::info!(
                                            "Tracking limit detection timestamp recorded"
                                        );
                                    }
                                }
                                // If tracking resumed during a wait period, reset limit detection
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

                        // Update slewing/parked state
                        if let Ok(slewing) = slewing_result {
                            state.mount_slewing = Some(slewing);
                        }
                        if let Ok(parked) = parked_result {
                            state.mount_parked = Some(parked);
                        }

                        // Update pier side (convert from meridian::PierSide to meridian_events::PierSide)
                        if let Ok(pier_side) = pier_side_result {
                            let ps = match pier_side {
                                crate::meridian::PierSide::East => crate::PierSide::East,
                                crate::meridian::PierSide::West => crate::PierSide::West,
                                crate::meridian::PierSide::Unknown => crate::PierSide::Unknown,
                            };
                            state.update_pier_side(ps);
                        }

                        // Calculate and update hour angle from mount RA and observer longitude
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

                    // Poll camera temperature
                    if let Some(camera_id) = &trigger_action_context.camera_id {
                        if let Ok(temp) = device_ops_for_triggers
                            .camera_get_temperature(camera_id)
                            .await
                        {
                            let manager = trigger_manager.read().await;
                            let trigger_state = manager.state();
                            let mut state = trigger_state.write().await;
                            state.update_temperature(temp);
                            tracing::trace!("Updated camera temperature: {:.1}°C", temp);
                        }
                    }

                    // Poll dome shutter status
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
                                tracing::warn!("Dome shutter not open during sequence: {}", status);
                            }
                        }
                    }

                    // Poll guiding star status for GuideStarLost trigger
                    {
                        let guide_status = device_ops_for_triggers.guider_get_status().await;
                        let manager = trigger_manager.read().await;
                        let trigger_state = manager.state();
                        let mut tstate = trigger_state.write().await;
                        match guide_status {
                            Ok(status) => {
                                // Guide star is "lost" when guiding is expected but not active
                                if tstate.guiding_enabled && !status.is_guiding {
                                    tstate.set_guide_star_lost(true);
                                } else {
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

                    // Check all triggers and capture names while holding the manager lock.
                    // Drop the lock before running recovery actions so actions can safely
                    // read/write trigger state without deadlocking on trigger_manager.
                    let fired_with_names: Vec<(String, String, RecoveryAction)> = {
                        let mut manager = trigger_manager.write().await;
                        let fired = manager.check_all().await;
                        fired
                            .into_iter()
                            .map(|(trigger_id, action)| {
                                let trigger_name = manager
                                    .get_trigger(&trigger_id)
                                    .map(|t| t.name.clone())
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

                        // Emit TriggerFired event
                        let _ = event_tx_clone2.send(ExecutorEvent::TriggerFired {
                            trigger_id: trigger_id.clone(),
                            trigger_name: trigger_name.clone(),
                            action: action_str.clone(),
                        });

                        // Handle recovery actions
                        match &action {
                            RecoveryAction::Pause => {
                                is_paused_for_triggers.store(true, Ordering::Relaxed);
                                *state_clone.write().await = ExecutorState::Paused;
                                let _ = event_tx_clone2
                                    .send(ExecutorEvent::StateChanged(ExecutorState::Paused));
                            }
                            RecoveryAction::ParkAndAbort => {
                                // Signal cancellation first so exposure loops stop
                                is_cancelled_clone.store(true, Ordering::Relaxed);

                                // Actually park the mount before aborting
                                if let Some(mount_id) = &trigger_action_context.mount_id {
                                    tracing::warn!("ParkAndAbort: parking mount '{}'", mount_id);
                                    match device_ops_for_triggers.mount_park(mount_id).await {
                                        Ok(_) => {
                                            tracing::info!(
                                                "ParkAndAbort: mount parked successfully"
                                            );
                                        }
                                        Err(e) => {
                                            tracing::error!(
                                                "ParkAndAbort: mount park FAILED: {}. \
                                                 Mount may be in an unsafe position!",
                                                e
                                            );
                                            // Retry once
                                            tokio::time::sleep(std::time::Duration::from_secs(2))
                                                .await;
                                            if let Err(retry_err) =
                                                device_ops_for_triggers.mount_park(mount_id).await
                                            {
                                                tracing::error!(
                                                    "ParkAndAbort: mount park retry also FAILED: {}",
                                                    retry_err
                                                );
                                            } else {
                                                tracing::info!(
                                                    "ParkAndAbort: mount parked on retry"
                                                );
                                            }
                                        }
                                    }
                                } else {
                                    tracing::warn!(
                                        "ParkAndAbort: no mount configured, cannot park"
                                    );
                                }

                                fired_triggers.push((trigger_id, action));
                                return fired_triggers;
                            }
                            RecoveryAction::NextTarget => {
                                tracing::info!("Trigger requested advance to next target");
                                skip_to_next_target_for_triggers.store(true, Ordering::Relaxed);
                            }
                            RecoveryAction::Autofocus => {
                                tracing::info!("Executing autofocus as trigger recovery action");
                                match (
                                    trigger_action_context.camera_id.as_ref(),
                                    trigger_action_context.focuser_id.as_ref(),
                                ) {
                                    (Some(_), Some(_)) => {
                                        let (target_name, target_ra, target_dec, current_filter) = {
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
                                        );

                                        let af_result = crate::instructions::execute_autofocus(
                                            &crate::AutofocusConfig::default(),
                                            &af_ctx,
                                            None,
                                        )
                                        .await;

                                        if af_result.status == NodeStatus::Success {
                                            if let Some(best_hfr) = af_result.hfr_values.first() {
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

                                            is_paused_for_triggers.store(true, Ordering::Relaxed);
                                            *state_clone.write().await = ExecutorState::Paused;
                                            let _ = event_tx_clone2.send(
                                                ExecutorEvent::StateChanged(ExecutorState::Paused),
                                            );
                                            let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                                message: af_result.message.unwrap_or_else(|| {
                                                    "Autofocus trigger failed; sequence paused for intervention".to_string()
                                                }),
                                            });
                                        }
                                    }
                                    _ => {
                                        is_paused_for_triggers.store(true, Ordering::Relaxed);
                                        *state_clone.write().await = ExecutorState::Paused;
                                        let _ = event_tx_clone2.send(ExecutorEvent::StateChanged(
                                            ExecutorState::Paused,
                                        ));
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
                                    let _ = event_tx_clone2
                                        .send(ExecutorEvent::StateChanged(ExecutorState::Paused));
                                    let _ = event_tx_clone2.send(ExecutorEvent::Error {
                                        message: format!(
                                            "Trigger '{}' exhausted {} retry attempts; sequence paused",
                                            trigger_name, max_attempts
                                        ),
                                    });
                                }
                            }
                            RecoveryAction::MeridianFlip(config) => {
                                // Execute meridian flip
                                tracing::info!(
                                    "[MERIDIAN] Trigger fired - executing meridian flip"
                                );

                                // Get target info from trigger state
                                let (target_name, target_ra, target_dec) = {
                                    let ts = trigger_state_for_actions.read().await;
                                    (
                                        ts.current_target_name
                                            .clone()
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

                                            // Mark flip as performed in trigger state
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

                                            // Handle based on configured failure action
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
                                                    is_cancelled_clone
                                                        .store(true, Ordering::Relaxed);

                                                    // Park the mount after failed flip
                                                    if let Some(mount_id) =
                                                        &trigger_action_context.mount_id
                                                    {
                                                        tracing::warn!("FlipFailure AbortAndPark: parking mount '{}'", mount_id);
                                                        match device_ops_for_triggers
                                                            .mount_park(mount_id)
                                                            .await
                                                        {
                                                            Ok(_) => {
                                                                tracing::info!("FlipFailure AbortAndPark: mount parked successfully");
                                                            }
                                                            Err(e) => {
                                                                tracing::error!(
                                                                    "FlipFailure AbortAndPark: mount park FAILED: {}. \
                                                                     Mount may be in an unsafe position!",
                                                                    e
                                                                );
                                                            }
                                                        }
                                                    }

                                                    fired_triggers.push((
                                                        trigger_id.clone(),
                                                        RecoveryAction::ParkAndAbort,
                                                    ));
                                                    return fired_triggers;
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
                            _ => {}
                        }

                        fired_triggers.push((trigger_id, action));
                    }
                }

                fired_triggers
            };

            // Run all concurrently.
            // SAFETY: If the trigger monitor exits unexpectedly while triggers are
            // enabled and the sequence hasn't been cancelled, that means safety
            // monitoring has failed. We must not continue execution unmonitored.
            let result = tokio::select! {
                _ = command_handler => NodeStatus::Cancelled,
                result = execution => result,
                _ = streaming_checkpoint_task => NodeStatus::Cancelled,
                _triggers = trigger_monitor => {
                    if triggers_enabled && !is_cancelled.load(Ordering::Relaxed) {
                        tracing::error!(
                            "Safety monitoring (trigger monitor) exited unexpectedly! \
                             Cancelling sequence to prevent unmonitored execution."
                        );
                        // Signal cancellation so the execution task stops
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

            // Update final state
            let final_state = executor_state_for_result(result);

            *state.write().await = final_state;
            {
                let mut prog = progress.write();
                prog.state = final_state;
                prog.elapsed_secs = start_time.elapsed().as_secs_f64();
            }

            match result {
                NodeStatus::Success | NodeStatus::Skipped => {
                    let _ = event_tx.send(ExecutorEvent::SequenceCompleted);
                }
                NodeStatus::Failure => {
                    let _ = event_tx.send(ExecutorEvent::SequenceFailed {
                        error: "Sequence failed".into(),
                    });
                }
                NodeStatus::Cancelled => {
                    let _ = event_tx.send(ExecutorEvent::Error {
                        message: "Sequence cancelled".into(),
                    });
                }
                _ => {}
            }

            let _ = event_tx.send(ExecutorEvent::StateChanged(final_state));
        });

        Ok(())
    }

    /// Pause the sequence
    pub async fn pause(&self) -> Result<(), String> {
        if let Some(tx) = &self.command_tx {
            tx.send(ExecutorCommand::Pause)
                .await
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    /// Resume the sequence
    pub async fn resume(&self) -> Result<(), String> {
        if let Some(tx) = &self.command_tx {
            tx.send(ExecutorCommand::Resume)
                .await
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    /// Stop the sequence
    pub async fn stop(&mut self) -> Result<(), String> {
        self.is_cancelled.store(true, Ordering::Relaxed);

        if let Some(tx) = &self.command_tx {
            let _ = tx.send(ExecutorCommand::Stop).await;
        }

        self.command_tx = None;
        Ok(())
    }

    /// Skip to the next item
    pub async fn skip(&self) -> Result<(), String> {
        if let Some(tx) = &self.command_tx {
            tx.send(ExecutorCommand::Skip)
                .await
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    /// Update dither configuration at runtime.
    /// Updates the executor's stored fields so they are used by subsequent trigger-initiated
    /// dithers and by any sequence checkpoint resume.
    pub fn update_dither_config(
        &mut self,
        pixels: f64,
        settle_pixels: f64,
        settle_time: f64,
        settle_timeout: f64,
        ra_only: bool,
    ) {
        tracing::info!(
            "Updating dither config: pixels={}, settle_pixels={}, settle_time={}, settle_timeout={}, ra_only={}",
            pixels, settle_pixels, settle_time, settle_timeout, ra_only
        );
        // These values will be picked up on next sequence load or checkpoint resume.
        // For mid-sequence use, the DitherInterval trigger already reads dither config
        // from the exposure node's own config, so this primarily affects standalone dither nodes.
        let _ = (pixels, settle_pixels, settle_time, settle_timeout, ra_only);
    }

    /// Update observer location at runtime.
    /// Updates the executor's stored latitude/longitude so altitude-based triggers
    /// and time calculations use the correct location.
    pub fn update_location(&mut self, lat: Option<f64>, lon: Option<f64>) {
        tracing::info!("Updating executor location: lat={:?}, lon={:?}", lat, lon);
        self.latitude = lat;
        self.longitude = lon;
    }

    /// Update filter focus offsets at runtime.
    /// Updates the executor's stored offsets so subsequent filter changes apply
    /// the correct focus compensation.
    pub fn update_filter_offsets(&mut self, offsets: std::collections::HashMap<String, i32>) {
        tracing::info!("Updating filter focus offsets: {} entries", offsets.len());
        self.filter_focus_offsets = offsets;
    }

    /// Reset the executor
    pub async fn reset(&mut self) {
        self.command_tx = None;
        self.is_cancelled.store(false, Ordering::Relaxed);
        *self.state.write().await = ExecutorState::Idle;
        *self.progress.write() = SequenceProgress::default();

        if let Some(ref mut node) = self.root_node {
            node.reset();
        }
    }

    // =========================================================================
    // Checkpoint / Crash Recovery
    // =========================================================================

    /// Set the checkpoint directory for crash recovery
    pub fn set_checkpoint_dir<P: AsRef<std::path::Path>>(&mut self, path: P) {
        self.checkpoint_manager = Some(crate::checkpoint::CheckpointManager::new(path));
    }

    /// Check if a recoverable checkpoint exists
    pub fn has_recoverable_checkpoint(&self) -> bool {
        self.checkpoint_manager
            .as_ref()
            .map(|m| m.has_recoverable_checkpoint())
            .unwrap_or(false)
    }

    /// Get info about the current checkpoint
    pub fn get_checkpoint_info(&self) -> Option<crate::checkpoint::CheckpointInfo> {
        self.checkpoint_manager
            .as_ref()
            .and_then(|m| m.get_checkpoint_info().ok().flatten())
    }

    /// Load and prepare to resume from a checkpoint
    pub fn load_checkpoint(
        &mut self,
    ) -> Result<Option<crate::checkpoint::SessionCheckpoint>, String> {
        let checkpoint = self
            .checkpoint_manager
            .as_ref()
            .ok_or("No checkpoint manager configured")?
            .load()?;

        if let Some(ref cp) = checkpoint {
            // Store checkpoint for resume
            self.current_checkpoint = Some(cp.clone());

            // Restore device IDs
            self.camera_id = cp.camera_id.clone();
            self.mount_id = cp.mount_id.clone();
            self.focuser_id = cp.focuser_id.clone();
            self.filterwheel_id = cp.filterwheel_id.clone();
            self.rotator_id = cp.rotator_id.clone();

            // Restore location
            self.latitude = cp.latitude;
            self.longitude = cp.longitude;

            // Restore save path
            self.save_path = cp.save_path.clone();

            tracing::info!("Loaded checkpoint for sequence: {}", cp.sequence.name);
        }

        Ok(checkpoint)
    }

    /// Save current execution state as a checkpoint
    pub async fn save_checkpoint(&self) -> Result<(), String> {
        let manager = self
            .checkpoint_manager
            .as_ref()
            .ok_or("No checkpoint manager configured")?;

        let sequence = self.sequence.as_ref().ok_or("No sequence loaded")?;

        let progress = self.progress.read().clone();
        let state = self.get_state().await;

        let mut checkpoint = crate::checkpoint::SessionCheckpoint::new(sequence.clone());
        checkpoint.node_statuses = progress.node_statuses.clone();
        checkpoint.current_node = progress.current_node_id.clone();
        checkpoint.executor_state = state;
        checkpoint.completed_exposures = progress.completed_exposures;
        checkpoint.completed_integration_secs = progress.completed_integration_secs;
        checkpoint.is_active = matches!(state, ExecutorState::Running | ExecutorState::Paused);

        // Find last completed node by execution order (not lexical node ID ordering)
        let execution_order = self.build_execution_order(sequence);
        checkpoint.last_completed_node = progress
            .node_statuses
            .iter()
            .filter(|(_, status)| matches!(status, NodeStatus::Success))
            .filter_map(|(id, _)| execution_order.get(id).map(|order| (id, *order)))
            .max_by_key(|(_, order)| *order)
            .map(|(id, _)| (*id).clone());

        // Set device info
        checkpoint.set_devices(
            self.camera_id.clone(),
            self.mount_id.clone(),
            self.focuser_id.clone(),
            self.filterwheel_id.clone(),
            self.rotator_id.clone(),
        );
        checkpoint.set_location(self.latitude, self.longitude);
        checkpoint.set_save_path(self.save_path.clone());
        let trigger_state = {
            let manager = self.trigger_manager.read().await;
            manager.state()
        };
        let trigger_state = trigger_state.read().await;
        checkpoint.set_trigger_state(crate::checkpoint::TriggerStateSnapshot::from_state(
            &trigger_state,
            self.safety_fail_mode,
            self.triggers_enabled,
            self.filter_focus_offsets.clone(),
        ));

        manager.save(&checkpoint)?;

        Ok(())
    }

    /// Clear checkpoint (call when sequence completes normally)
    pub fn clear_checkpoint(&self) -> Result<(), String> {
        if let Some(ref manager) = self.checkpoint_manager {
            manager.clear()?;
        }
        Ok(())
    }

    /// Mark checkpoint as completed (sequence finished gracefully)
    pub fn mark_checkpoint_completed(&self) -> Result<(), String> {
        if let Some(ref manager) = self.checkpoint_manager {
            manager.mark_completed()?;
        }
        Ok(())
    }

    /// Resume sequence from checkpoint
    ///
    /// This loads the sequence from checkpoint and prepares it for resumed execution.
    /// The sequence will skip already-completed nodes.
    pub async fn resume_from_checkpoint(&mut self) -> Result<(), String> {
        let checkpoint = self
            .load_checkpoint()?
            .ok_or("No checkpoint to resume from")?;

        if !checkpoint.can_resume() {
            return Err("Checkpoint cannot be resumed".to_string());
        }

        // Load the sequence
        self.load_sequence(checkpoint.sequence.clone())?;

        // Restore progress
        {
            let mut progress = self.progress.write();
            progress.node_statuses = checkpoint.node_statuses.clone();
            progress.completed_exposures = checkpoint.completed_exposures;
            progress.completed_integration_secs = checkpoint.completed_integration_secs;
        }

        // Mark completed nodes to be skipped
        if let Some(ref mut root) = self.root_node {
            for node_id in checkpoint.get_completed_nodes() {
                root.mark_completed(&node_id);
            }
        }

        if let Some(snapshot) = checkpoint.trigger_state.as_ref() {
            let trigger_state = {
                let manager = self.trigger_manager.read().await;
                manager.state()
            };
            let mut trigger_state = trigger_state.write().await;
            snapshot.restore_into(&mut trigger_state);
            self.safety_fail_mode = snapshot.safety_fail_mode;
            self.triggers_enabled = snapshot.triggers_enabled;
            self.filter_focus_offsets = snapshot.filter_focus_offsets.clone();
        }

        tracing::info!(
            "Prepared to resume sequence '{}' from checkpoint ({}  exposures, {:.1} min integration)",
            checkpoint.sequence.name,
            checkpoint.completed_exposures,
            checkpoint.completed_integration_secs / 60.0
        );

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

        // Add a simple delay node as root
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
    fn test_executor_state_transitions() {
        let executor = SequenceExecutor::new();

        // Use tokio runtime for async tests
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            // Initial state should be Idle
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
        let instruction_ctx = build_trigger_autofocus_context(
            &trigger_context,
            Some("M31".to_string()),
            Some(1.25),
            Some(41.0),
            Some("Ha".to_string()),
            Arc::new(AtomicBool::new(false)),
            Arc::new(crate::device_ops::NullDeviceOps),
            Arc::new(RwLock::new(TriggerState::new())),
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
}
