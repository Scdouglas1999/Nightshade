//! Sequence execution engine.
//!
//! This module owns the [`SequenceExecutor`] struct, its constructor, the
//! orchestrating [`SequenceExecutor::start`] method, the sequence-load /
//! totals-calculation helpers, the free-standing recovery / trigger helper
//! functions that the inline executor closures rely on, and the public
//! event / progress / state types.
//!
//! Cohesive concerns are split into sibling submodules:
//!   * [`lifecycle`]    — operator pause/resume/stop/skip/recovery-button.
//!   * [`recovery`]     — recovery state-machine snapshot accessors.
//!   * [`setup`]        — pre-start `set_*` wiring and post-run `reset`.
//!   * [`loading`]      — sequence load + read-only totals/order walks.
//!   * [`runtime_config`] — `update_*` mid-flight config mutators.
//!   * [`checkpoint`]   — crash-recovery save/load/resume surface.
//!   * [`decision`]     — structured-decision logging surface.
//!
//! What is deliberately kept here in `mod.rs`:
//!   * `start()` — the orchestrator. It captures dozens of locals into
//!     spawned tasks; extracting it would require either a giant
//!     parameter struct or making most private fields `pub(super)`,
//!     neither of which is a net win.
//!   * The free-standing helpers (`run_recovery_attempt`,
//!     `build_trigger_autofocus_context`, etc.) are owned here because
//!     the inline `start()` closures are their only callers.

mod checkpoint;
mod decision;
mod lifecycle;
mod loading;
mod recovery;
mod runtime_config;
mod setup;

use crate::device_ops::SharedDeviceOps;
use crate::node::instructions::autofocus::parse_autofocus_detail;
use crate::node::{
    CloudMotionSnapshot, ExecutionContext, Node, ProgressDetail, ProgressUpdate, RuntimeNode,
};
use crate::triggers::{Trigger, TriggerManager, TriggerState};
use crate::{
    NodeDefinition, NodeId, NodeStatus, NodeType, RecoveryAction, SafetyFailMode,
    SequenceDefinition, TriggerType,
};
use futures::FutureExt;
use parking_lot::RwLock as StdRwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::{broadcast, mpsc, oneshot, watch, RwLock};

pub(crate) const RECOVERY_NODE_TRIGGER_PREFIX: &str = "recovery_node:";
const DEFAULT_SAFETY_CHECK_INTERVAL_SECS: u64 = 30;

/// Default staleness window for the Dart weather verdict (Subsystem 2 step 3).
/// The Dart side pushes the verdict on every 5-minute periodic evaluation plus
/// on every alert/snooze change; 6 minutes gives the periodic push a full cycle
/// of slack before a missed push is treated as a dead feed.
const DEFAULT_WEATHER_VERDICT_STALENESS_SECS: u64 = 360;

mod monitoring;
mod preflight;
mod recovery_ops;
mod start;
mod trigger_context;
mod types;

pub use monitoring::*;
pub(crate) use preflight::*;
pub(crate) use recovery_ops::*;
use trigger_context::*;
pub use types::*;

/// The sequence executor manages running a sequence
pub struct SequenceExecutor {
    sequence: Option<SequenceDefinition>,
    state: Arc<RwLock<ExecutorState>>,
    progress: Arc<StdRwLock<SequenceProgress>>,
    command_tx: Option<mpsc::Sender<ExecutorCommand>>,
    /// Completion acknowledgment for the currently spawned executor task.
    /// `stop()` takes and awaits this receiver so native termination is not
    /// reported until instruction cancellation cleanup (including camera
    /// exposure abort) and terminal event emission have finished.
    run_completion_rx: Option<oneshot::Receiver<()>>,
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
    /// Checkpoint manager for crash recovery.
    /// stored behind an `Arc` so the streaming-checkpoint task
    /// (spawned inside `start()`) shares the SAME instance — including its
    /// `info_cache` — instead of constructing a second
    /// `CheckpointManager::new(checkpoint_dir)` that bypasses the cache and
    /// causes UI staleness on `has_recoverable_checkpoint`.
    checkpoint_manager: Option<Arc<crate::checkpoint::CheckpointManager>>,
    /// Current checkpoint being updated
    current_checkpoint: Option<crate::checkpoint::SessionCheckpoint>,
    /// Safety fail mode - determines behavior when safety devices fail or are unavailable
    pub safety_fail_mode: SafetyFailMode,
    /// Filter focus offsets from equipment profile (filter_name -> offset_steps)
    pub filter_focus_offsets: std::collections::HashMap<String, i32>,
    /// shared runtime configuration. Updated by
    /// `Update{DitherConfig,Location,FilterOffsets}` commands so changes
    /// take effect on the next dither/capture/autofocus without requiring a
    /// sequence reload. Cloned into the spawned executor task so the task
    /// reads the same values the public update_* methods write.
    ///
    /// Why `parking_lot::RwLock` instead of `tokio::sync::RwLock`: the
    /// public `update_*` methods are sync (already wired into the bridge
    /// crate that way) and the lock is only ever held for the duration of
    /// a struct-field assignment. A sync rwlock keeps the bridge call sites
    /// non-`.await` and is free of contention concerns for this access
    /// pattern.
    runtime_config: Arc<StdRwLock<RuntimeConfig>>,
    /// Recovery Mode — shared atomic flags that let the operator
    /// punch through the wait timer ("Try Now") or exit the loop ("Abort")
    /// without blocking on a mutex. Cloned into the spawned executor task
    /// so the recovery-loop driver sees the same atomic the public
    /// `recovery_try_now()` / `recovery_abort()` methods write.
    recovery_signals: Arc<crate::recovery::RecoverySignals>,
    /// Recovery Mode — most recent in-flight `RecoveryContext`.
    /// `None` whenever the executor is not in `Recovering`. Cloned for
    /// the `ExecutorEvent::Recovery*` events so the dashboard banner sees
    /// the same snapshot the executor sees.
    current_recovery: Arc<StdRwLock<Option<crate::recovery::RecoveryContext>>>,
    /// Recovery Mode — log of every completed recovery loop so the
    /// post-session report can render attempts/cause/duration/outcome.
    /// Trimmed at construction-time so a marathon run with hundreds of
    /// recoveries (something is very wrong then…) doesn't blow up memory.
    recovery_history: Arc<StdRwLock<Vec<crate::recovery::RecoveryHistoryEntry>>>,
    /// Replay Debug — structured decision broadcast channel. Every
    /// scheduler pick, trigger firing, recovery transition, frame verdict,
    /// adaptive swap, plugin invocation, manual operator action, and
    /// system event flows through this sender. The bridge layer
    /// subscribes via [`SequenceExecutor::subscribe_decisions`] and routes
    /// the events to the `SequencerEvent::DecisionLogged` typed payload
    /// + the `sequence_decisions` persistence table.
    decision_tx: crate::decision::DecisionSender,
    /// Replay Debug — the currently-active `sequence_runs.id` (set
    /// from the bridge via [`SequenceExecutor::set_active_sequence_run_id`]
    /// after the Dart side inserts the row). Stamped into every emitted
    /// `DecisionEvent` so the replay screen can filter by run without
    /// joining on a wall-clock window.
    active_sequence_run_id: Arc<StdRwLock<Option<i64>>>,
    /// Replay Debug — runtime toggle. When `false`, the executor
    /// short-circuits decision emission entirely (no channel send, no
    /// allocation). Wired to the `decisionLoggingEnabled` setting.
    decision_logging_enabled: Arc<AtomicBool>,
    /// adaptive sky-conditions swap. Stable Arc slots shared
    /// between this struct and the per-run `ExecutionContext`. Holding
    /// them on the executor too lets idle-time pushes (`update_conditions_score`
    /// called before `start()`) survive into the next run AND lets the
    /// dashboard's `current_adaptive_swap_json` reach a snapshot without
    /// needing access to the in-flight context.
    shared_conditions_score: Arc<RwLock<Option<crate::scheduling::ConditionsScore>>>,
    shared_adaptive_swap_state: Arc<RwLock<crate::node::context::AdaptiveSwapRuntimeState>>,
}

impl SequenceExecutor {
    pub fn new() -> Self {
        let (event_tx, _) = broadcast::channel(256);
        let (decision_tx, _) =
            broadcast::channel(crate::decision::DEFAULT_DECISION_CHANNEL_CAPACITY);
        let mut trigger_manager = TriggerManager::new();
        // Seed the standard safety triggers (HFR, weather, altitude limit, meridian
        // flip, etc.) at construction so a sequence loaded without an explicit
        // trigger config — e.g. headless API runs or first-launch users — still has
        // a baseline of unattended-imaging protections.
        trigger_manager.create_standard_triggers();

        Self {
            sequence: None,
            state: Arc::new(RwLock::new(ExecutorState::Idle)),
            progress: Arc::new(StdRwLock::new(SequenceProgress::default())),
            command_tx: None,
            run_completion_rx: None,
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
            runtime_config: Arc::new(StdRwLock::new(RuntimeConfig::default())),
            recovery_signals: Arc::new(crate::recovery::RecoverySignals::new()),
            current_recovery: Arc::new(StdRwLock::new(None)),
            recovery_history: Arc::new(StdRwLock::new(Vec::new())),
            decision_tx,
            active_sequence_run_id: Arc::new(StdRwLock::new(None)),
            shared_conditions_score: Arc::new(RwLock::new(None)),
            shared_adaptive_swap_state: Arc::new(RwLock::new(
                crate::node::context::AdaptiveSwapRuntimeState::default(),
            )),
            // Replay Debug — default ON. The Dart settings layer
            // calls `set_decision_logging_enabled(false)` when the user
            // opts out; the overhead is negligible (one channel send +
            // one DB row per decision, well under 100 rows/min in real
            // sessions) so we ship enabled-by-default.
            decision_logging_enabled: Arc::new(AtomicBool::new(true)),
        }
    }

    async fn prepare_sequence_recovery_triggers(&self) -> Result<HashMap<String, NodeId>, String> {
        let Some(sequence) = &self.sequence else {
            return Ok(HashMap::new());
        };

        let specs = sequence_recovery_trigger_specs(sequence);
        let mut custom_branches = HashMap::new();
        let mut manager = self.trigger_manager.write().await;

        let stale_ids: Vec<String> = manager
            .triggers()
            .iter()
            .filter(|trigger| trigger.id.starts_with(RECOVERY_NODE_TRIGGER_PREFIX))
            .map(|trigger| trigger.id.clone())
            .collect();
        for trigger_id in stale_ids {
            manager.remove_trigger(&trigger_id);
        }

        for spec in specs {
            if let Some(node_id) = &spec.custom_branch_node_id {
                custom_branches.insert(spec.trigger_id.clone(), node_id.clone());
            }

            manager.add_trigger(Trigger::new(
                spec.trigger_id,
                spec.trigger_name,
                spec.trigger_type,
                spec.recovery_action,
            ));
        }

        Ok(custom_branches)
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

/// What a trigger-initiated dither attempt should be recorded as.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DitherTriggerOutcome {
    /// Dither happened; reset the interval.
    Performed,
    /// The rig has no guider, so there is nothing to dither. Reset the interval
    /// anyway — the condition cannot change mid-run, and leaving it unmarked made
    /// the trigger re-fire on every single exposure.
    SkippedNoGuider,
    /// A genuine failure (guide star lost, settle timeout). Keep the interval due
    /// so the next exposure retries, and warn.
    Failed,
}

/// Classify a dither result. Split out from the trigger loop so the three cases
/// are testable without standing up an executor.
pub(crate) fn classify_dither_result(
    status: NodeStatus,
    message: Option<&str>,
) -> DitherTriggerOutcome {
    if status == NodeStatus::Success {
        return DitherTriggerOutcome::Performed;
    }
    if message.is_some_and(crate::device_ops::is_no_guider_configured) {
        return DitherTriggerOutcome::SkippedNoGuider;
    }
    DitherTriggerOutcome::Failed
}

#[cfg(test)]
mod scenario_sim_tests;

#[cfg(test)]
mod tests;
