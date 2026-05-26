//! Global Event Bus for cross-component communication
//!
//! Events are published by various components and can be subscribed to
//! by the Dart side to update UI and trigger reactions.
//!
//! # Features
//!
//! - **Sequence Numbers**: Each event has a unique, monotonically increasing ID
//! - **Causality Tracking**: Events can reference the event that caused them
//! - **Category-based Filtering**: Subscribe to specific event categories
//! - **Overflow Handling**: Graceful handling when event buffer is full with diagnostics
//!
//! # Buffer Size
//!
//! The default buffer size is 4096 events (`DEFAULT_EVENT_BUFFER_SIZE`). This is sized
//! to handle burst scenarios like rapid autofocus loops or high-frequency guiding updates
//! without dropping events. If the buffer fills up (slow consumer), events are logged
//! and counted for diagnostics.
//!
//! # Example
//!
//! ```rust
//! let bus = EventBus::new(DEFAULT_EVENT_BUFFER_SIZE);
//!
//! // Publish an event
//! let event_id = bus.publish_with_tracking(
//!     EventSeverity::Info,
//!     EventCategory::Equipment,
//!     EventPayload::Equipment(EquipmentEvent::Connected { .. }),
//!     None, // No causal parent
//! );
//!
//! // Publish a follow-up event with causality
//! bus.publish_with_tracking(
//!     EventSeverity::Info,
//!     EventCategory::Imaging,
//!     EventPayload::Imaging(ImagingEvent::ExposureStarted { .. }),
//!     Some(event_id), // This was caused by the connection event
//! );
//! ```

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;

/// Default event buffer size.
///
/// This is sized to handle burst scenarios like:
/// - Rapid autofocus loops (100+ events in seconds)
/// - High-frequency guiding corrections (10+ per second)
/// - Multiple simultaneous device state changes
///
/// The buffer uses a broadcast channel, so if any receiver falls behind by more than
/// this many events, it will receive a `Lagged` error and skip to the latest events.
/// Increasing this value uses more memory but reduces the chance of dropping events
/// when the Dart side is slow to consume them.
pub const DEFAULT_EVENT_BUFFER_SIZE: usize = 4096;

/// Event severity levels
#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EventSeverity {
    Info,
    Warning,
    Error,
    Critical,
}

/// Categories of events
#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum EventCategory {
    Equipment,
    Imaging,
    Guiding,
    Sequencer,
    Safety,
    System,
    PolarAlignment,
}

/// Heartbeat status for device health monitoring
#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum HeartbeatStatus {
    /// Device is responding normally
    Healthy,
    /// Device has failed some health checks but not yet marked disconnected
    Degraded,
    /// Device is not responding and marked as disconnected
    Disconnected,
    /// Attempting to reconnect to the device
    Reconnecting,
    /// Successfully reconnected after failures
    Reconnected,
}

/// Equipment-specific events
///
/// Wave 6B (P2-1) follow-up — TODO: promote the wave-6b hot-plug events to
/// first-class variants (`DeviceDiscovered { device_class, driver, id,
/// name, unique_id }` and `DeviceLost { device_class, driver, id }`) once
/// FRB bindings are regenerated. The current hot-plug task in
/// `crate::hotplug` rides on `PropertyChanged { property:
/// "device_discovered" | "device_lost", value: <json> }` because adding
/// new variants here requires `melos run generate` to regen the Dart FFI
/// bindings — see `crate::hotplug` for the full rationale. To land the
/// typed variants:
///   1. Add `DeviceDiscovered { device_class: String, driver: String, id:
///      String, name: String, unique_id: Option<String> }` and
///      `DeviceLost { device_class: String, driver: String, id: String }`
///      below.
///   2. After editing: run `melos run generate` to regenerate FRB bindings.
///   3. Update `crate::hotplug::poll_once` to emit the typed variants
///      instead of `PropertyChanged`.
///   4. Update the Dart `bridge_event_mapper.dart` to map the new variants.
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EquipmentEvent {
    // Generic device events
    Connecting {
        device_type: String,
        device_id: String,
    },
    Connected {
        device_type: String,
        device_id: String,
    },
    Disconnected {
        device_type: String,
        device_id: String,
    },
    PropertyChanged {
        device_type: String,
        device_id: String,
        property: String,
        value: String,
    },
    Error {
        device_type: String,
        device_id: String,
        message: String,
    },

    // Mount events
    MountSlewStarted {
        ra: f64,
        dec: f64,
    },
    MountSlewCompleted {
        ra: f64,
        dec: f64,
    },
    MountTrackingStarted,
    MountTrackingStopped,
    MountParkStarted,
    MountParkCompleted,
    MountUnparked,

    // Focuser events
    FocuserMoveStarted {
        target_position: i32,
    },
    FocuserMoveCompleted {
        position: i32,
    },
    FocuserTemperatureChanged {
        temperature: f64,
    },

    // Filter wheel events
    FilterChanging {
        from_position: i32,
        to_position: i32,
        filter_name: Option<String>,
    },
    FilterChanged {
        position: i32,
        filter_name: Option<String>,
    },

    // Rotator events
    RotatorMoveStarted {
        target_angle: f64,
    },
    RotatorMoveCompleted {
        angle: f64,
    },

    // Camera events
    CameraCoolingStarted {
        target_temp: f64,
    },
    CameraCoolingReached {
        temperature: f64,
    },
    CameraWarmingStarted,
    CameraWarmingCompleted,

    // Heartbeat monitoring events
    HeartbeatStarted {
        device_type: String,
        device_id: String,
        interval_secs: u64,
    },
    HeartbeatStopped {
        device_type: String,
        device_id: String,
    },
    HeartbeatStatusChanged {
        device_type: String,
        device_id: String,
        status: HeartbeatStatus,
        consecutive_failures: u32,
        last_rtt_ms: Option<u64>,
    },
    HeartbeatReconnecting {
        device_type: String,
        device_id: String,
        attempt: u32,
        max_attempts: u32,
    },
    HeartbeatReconnected {
        device_type: String,
        device_id: String,
        after_attempts: u32,
    },
}

/// Polar alignment error data
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolarAlignmentEvent {
    pub azimuth_error: f64,
    pub altitude_error: f64,
    pub total_error: f64,
    pub current_ra: f64,
    pub current_dec: f64,
    pub target_ra: f64,
    pub target_dec: f64,
}

/// Polar alignment status update
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolarAlignmentStatus {
    pub status: String,
    pub phase: String,
    pub point: i32,
}

/// Polar alignment image data for UI display
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolarAlignmentImageEvent {
    /// JPEG-encoded image bytes for display
    pub image_data: Vec<u8>,
    /// Image width
    pub width: u32,
    /// Image height
    pub height: u32,
    /// Plate solve result (if available)
    pub solved_ra: Option<f64>,
    pub solved_dec: Option<f64>,
    /// Current measurement point (1-3) or 0 for adjustment phase
    pub point: i32,
    /// Phase: "measuring" or "adjusting"
    pub phase: String,
}

/// Imaging-specific events
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ImagingEvent {
    // Basic exposure events
    ExposureStarted {
        duration_secs: f64,
        frame_type: crate::device::FrameType,
    },
    ExposureStartedWithFrame {
        duration_secs: f64,
        frame_type: crate::device::FrameType,
        frame_number: u32,
        total_frames: Option<u32>,
    },
    ExposureProgress {
        progress: f64,
        remaining_secs: f64,
    },
    ExposureCompleted {
        file_path: Option<String>,
        hfr: f64,
        stars_detected: u32,
    },
    ExposureCompletedWithFrame {
        frame_number: u32,
        total_frames: Option<u32>,
        hfr: f64,
        stars_detected: u32,
    },
    ExposureFailed {
        error: String,
    },
    ExposureCancelled,

    // Download events
    DownloadStarted,
    DownloadCompleted,

    // Image events
    ImageReady {
        width: u32,
        height: u32,
    },
    ImageSaved {
        file_path: String,
    },

    // Temperature events
    TemperatureChanged {
        temp_celsius: f64,
        cooler_power: f64,
    },

    // Deprecated (for backwards compatibility)
    #[serde(rename = "ExposureComplete")]
    ExposureComplete {
        success: bool,
    },
    #[serde(rename = "ExposureFailed_Old")]
    ExposureFailedOld {
        reason: String,
    },
}

/// Guiding-specific events
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GuidingEvent {
    Connected,
    Disconnected,
    GuidingStarted,
    GuidingStopped,
    Paused,
    Resumed,
    Settled {
        rms: f64,
    },
    LostStar,
    DitherStarted {
        pixels: f64,
    },
    DitherCompleted,
    Correction {
        ra: f64,
        dec: f64,
        ra_raw: f64,
        dec_raw: f64,
    },
    /// Looping exposures without guiding
    Looping,
    /// Settling after dither or guide start
    Settling,
    /// Calibration in progress
    Calibrating,
    /// Calibration completed successfully
    CalibrationComplete,
    /// Guide star selected at position
    StarSelected {
        x: f64,
        y: f64,
    },
    /// PHD2 app state change (for states not covered by other events)
    AppState {
        state: String,
    },
    /// SNR and star mass update from guide step
    GuideStats {
        snr: f64,
        star_mass: f64,
    },
}

/// Sequencer-specific events
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SequencerEvent {
    Started {
        sequence_name: String,
    },
    Paused,
    Resumed,
    Stopped,
    Completed,
    NodeStarted {
        node_id: String,
        node_type: String,
    },
    NodeCompleted {
        node_id: String,
        /// Completion status: "success", "failed", "cancelled", or "skipped"
        status: String,
    },
    Progress {
        current: u32,
        total: u32,
    },
    TargetChanged {
        target_name: String,
        /// Right Ascension in hours (0-24), if available from the target header
        ra: Option<f64>,
        /// Declination in degrees (-90 to +90), if available from the target header
        dec: Option<f64>,
    },
    TargetCompleted {
        target_name: String,
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
    Error {
        message: String,
    },
    /// A trigger watchdog fired during sequence execution
    TriggerFired {
        /// Unique trigger identifier
        trigger_id: String,
        /// Human-readable trigger name
        trigger_name: String,
        /// Action taken (e.g., "Autofocus", "Dither", "PauseSequence")
        action: String,
    },
    /// Progress update for long-running instructions (cooling, autofocus, slewing)
    InstructionProgress {
        /// Node ID for mapping progress to the correct tree node
        node_id: String,
        /// Name of the instruction (e.g., "Cool Camera", "Autofocus")
        instruction: String,
        /// Progress percentage (0.0 to 100.0)
        progress_percent: f64,
        /// Detailed status message
        detail: String,
    },
    /// Structured progress update for long-running instructions. This is
    /// emitted alongside `InstructionProgress` so legacy consumers keep their
    /// string detail while newer UI panels can bind to explicit fields.
    InstructionProgressStructured {
        /// Node ID for mapping progress to the correct tree node
        node_id: String,
        /// Name of the instruction (e.g., "Cool Camera", "Autofocus")
        instruction: String,
        /// Progress percentage (0.0 to 100.0)
        progress_percent: f64,
        /// `ProgressDetail` variant name (e.g. `Exposure`, `Autofocus`)
        detail_kind: String,
        /// JSON-stringified inner payload for the variant.
        detail_json: String,
    },

    // ===== Pack H: typed Wave-3 progress payloads =====
    //
    // Pre-Pack-H, the Wave 3 image-grading + target-scheduler progress
    // payloads (`ProgressDetail::FrameAccepted/FrameRejected/Scheduler/
    // IntegrationBudget`) were stringified through `ProgressDetail::detail_text()`
    // and shipped on `InstructionProgress.detail`. The Dart side parsed
    // those strings with regex (`FrameGradeEvent.tryParseDetail`) — fragile,
    // lossy, and silently dropped fields that didn't fit the format string.
    //
    // Pack H promotes the four high-value variants to first-class typed
    // `SequencerEvent` variants. The bridge's `run_sequencer_event_loop`
    // matches on the structured `ProgressDetail` directly and emits the
    // typed variant; the legacy `InstructionProgress` is still emitted in
    // parallel so any subscriber that hasn't migrated yet keeps working
    // (back-compat: the typed variants are *additional*, not replacements).
    /// Pack H — Wave 3 Image Grading: a frame passed every configured
    /// quality threshold and was saved to the normal output folder.
    /// Mirrors `ProgressDetail::FrameAccepted`.
    FrameAccepted {
        node_id: String,
        /// 1-based frame index within the current TakeExposure burst.
        frame: u32,
        total: u32,
        hfr: Option<f64>,
        eccentricity: Option<f64>,
        star_count: Option<u32>,
        /// Running count of accepted frames for the whole run.
        accepted_total: u32,
        /// Running count of rejected frames for the whole run.
        rejected_total: u32,
        /// Wave 6 Pack P — on-disk save path of the accepted frame, so
        /// the Wave 6 thumbnail strip can render an inline preview of
        /// accepted frames the same way it already does for rejected
        /// frames via `FrameRejected.reject_path`. `None` for legacy /
        /// non-grading emit sites that did not thread the path through.
        save_path: Option<String>,
    },
    /// Pack H — Wave 3 Image Grading: a frame failed at least one
    /// quality threshold and was routed to the reject folder. Mirrors
    /// `ProgressDetail::FrameRejected`. The consecutive-reject pause
    /// behaviour is unchanged; this event surfaces the metrics so the
    /// dashboard can render them without parsing.
    FrameRejected {
        node_id: String,
        frame: u32,
        total: u32,
        reason: String,
        hfr: Option<f64>,
        eccentricity: Option<f64>,
        star_count: Option<u32>,
        reject_path: String,
        /// Running consecutive-rejects counter. When this reaches the
        /// configured `max_consecutive_rejects`, the executor pauses
        /// the sequence and emits an additional `Error` event.
        consecutive_rejects: u32,
        accepted_total: u32,
        rejected_total: u32,
        // Wave 8 — Frame-Failure Forensics ----------------------------
        /// Classified cause label (wire-stable snake_case string from
        /// `LikelyCause::label()`). `None` when the classifier was not
        /// consulted or could not pick a single best guess. Dart maps
        /// this back to its `LikelyCause` enum via
        /// `LikelyCauseExt.fromLabel`.
        likely_cause_label: Option<String>,
        /// Human-readable evidence bullets the dashboard surfaces in
        /// the Forensics panel and Frame Detail dialog. Empty list
        /// when no telemetry was available.
        evidence: Vec<String>,
        /// Sky brightness reading at capture time (mag/arcsec²).
        sky_brightness_at_capture: Option<f64>,
        /// Cloud cover percentage (0-100) at capture time.
        cloud_cover_at_capture: Option<f64>,
        /// Wind speed at capture time (km/h). `None` when no weather
        /// feed is wired through to the sequencer.
        wind_at_capture: Option<f64>,
        /// Guide RMS (arc-seconds) sampled at capture time.
        guide_rms_at_capture: Option<f64>,
        /// Sensor temperature (°C) at capture time.
        sensor_temp_at_capture: Option<f64>,
    },
    /// Pack H — Wave 3 Agent 1: TargetScheduler decision. Mirrors
    /// `ProgressDetail::Scheduler`. The score table is exposed as a
    /// flat `Vec<SchedulerScoreEntry>` so FRB doesn't have to bridge
    /// the internal `SchedulerScoreSummary` type.
    SchedulerDecision {
        node_id: String,
        /// 1-based decision counter for this scheduler instance.
        decision_counter: u32,
        /// `None` when no target cleared `min_score_to_run`.
        picked_target_id: Option<String>,
        picked_target_name: Option<String>,
        /// Picked target's total score (0..=100). `None` when nothing
        /// was picked.
        picked_score: Option<f64>,
        /// Flat score table (runnable first, then by descending total).
        scores: Vec<SchedulerScoreEntry>,
    },
    /// Pack H — Wave 3 Agent 3: per-target integration budget tick.
    /// Mirrors `ProgressDetail::IntegrationBudget`.
    IntegrationBudget {
        /// The TargetHeader node id this budget belongs to.
        target_id: String,
        /// Filter the credit was applied to (`""` for no-filter cameras).
        filter: String,
        completed_secs: f64,
        budget_secs: f64,
        fraction: f64,
        budget_met: bool,
    },
    /// Wave 5 Agent 2 — sky-brightness adaptive exposure decision.
    /// Mirrors `ProgressDetail::ExposureAdjusted`. Emitted before every
    /// exposure burst whenever the adapter was consulted (regardless of
    /// whether the duration actually changed), so the Run Dashboard can
    /// surface live sky brightness + the most recent nominal/adapted
    /// pair and the user understands why the camera is running longer
    /// (or shorter) than configured.
    ExposureAdjusted {
        node_id: String,
        /// Adapted (effective) exposure duration in seconds.
        adapted_secs: f64,
        /// User-configured nominal duration in seconds.
        nominal_secs: f64,
        /// Live sky brightness used in the decision (mag/arcsec²). `None`
        /// when the adapter fell back due to missing telemetry.
        sky_brightness_mag: Option<f64>,
        /// Filter being captured through. `None` for monochrome / no
        /// filter wheel rigs.
        filter: Option<String>,
        /// Lowercase tag: `adapted`, `clamped_min`, `clamped_max`,
        /// `unavailable`, `disabled`, `out_of_nominal_bounds`.
        reason: String,
    },

    // ===== Wave 4 Recovery Mode — typed entry / progress / exit events =====
    //
    // Pre-Wave-4.5, the Rust executor's `ExecutorEvent::Recovery*` events
    // were routed through the legacy `InstructionProgress` channel with
    // `node_id == "_recovery"` and a JSON-encoded context blob shoved in
    // `detail`. The Dart side string-prefix-matched on `instruction` and
    // jsonDecoded `detail` — fragile, lossy, and silently dropped fields
    // that didn't fit. Wave 4.5 promotes the four variants to first-class
    // typed payloads. All `context_*` fields are denormalised flat
    // primitives so FRB doesn't need to bridge the chrono-dependent
    // `RecoveryContext` struct. The Dart side rebuilds a `RecoveryStatus`
    // from these flat fields in `_recoveryStatusFromTypedEvent`.
    //
    // `cause_kind` is the Rust enum variant name (`GuideStarLost`,
    // `SlewFailed`, etc.) so the Dart side can map directly to
    // `RecoveryCause.<factory>`. `cause_custom_label` carries the inner
    // string for the `Custom(String)` variant — non-empty only when
    // `cause_kind == "Custom"`.
    //
    // `phase` mirrors `RecoveryPhase` (`Waiting`, `Attempting`,
    // `Recovered`, `GaveUp`) so the dashboard banner knows which row
    // to render.
    /// Wave 4 Recovery Mode: the executor just entered the `Recovering`
    /// state. Subscribers (dashboard banner, audible alert player,
    /// push-notification service) render the cause / attempt counter
    /// / countdown without reaching back into the executor.
    RecoveryStarted {
        started_at_iso: String,
        cause_kind: String,
        cause_custom_label: Option<String>,
        last_attempt_at_iso: Option<String>,
        attempt_count: u32,
        max_attempts: u32,
        retry_interval_secs: f64,
        max_duration_secs: f64,
        phase: String,
        last_error: Option<String>,
    },
    /// Wave 4 Recovery Mode: periodic update of the live recovery context
    /// (attempt counter incremented, phase changed, last_error updated).
    /// Subscribers refresh the dashboard banner from this; the
    /// `RecoveryStarted` / `RecoveryCompleted` / `RecoveryGaveUp` events
    /// bookend the loop while this carries deltas inside the loop.
    RecoveryProgress {
        started_at_iso: String,
        cause_kind: String,
        cause_custom_label: Option<String>,
        last_attempt_at_iso: Option<String>,
        attempt_count: u32,
        max_attempts: u32,
        retry_interval_secs: f64,
        max_duration_secs: f64,
        phase: String,
        last_error: Option<String>,
    },
    /// Wave 4 Recovery Mode: recovery succeeded. The executor will
    /// transition back to `Running`; subscribers clear the dashboard
    /// banner and append to the history list.
    RecoveryCompleted {
        started_at_iso: String,
        cause_kind: String,
        cause_custom_label: Option<String>,
        last_attempt_at_iso: Option<String>,
        attempt_count: u32,
        max_attempts: u32,
        retry_interval_secs: f64,
        max_duration_secs: f64,
        phase: String,
        last_error: Option<String>,
    },
    /// Wave 4 Recovery Mode: recovery exhausted attempts / time / was
    /// aborted by the user. The executor will transition to `Failed` (or
    /// run the configured ParkAndAbort policy). Subscribers append the
    /// history entry and emit a critical-severity event.
    RecoveryGaveUp {
        started_at_iso: String,
        cause_kind: String,
        cause_custom_label: Option<String>,
        last_attempt_at_iso: Option<String>,
        attempt_count: u32,
        max_attempts: u32,
        retry_interval_secs: f64,
        max_duration_secs: f64,
        phase: String,
        last_error: Option<String>,
        /// True when the loop exited because the user pressed Abort.
        /// Distinct from exhaustion so the UI can render different copy
        /// ("Aborted by operator" vs "Exhausted retries").
        aborted_by_user: bool,
    },

    // ===== Wave 6 Pack P — plugin sequence nodes (Rust dispatch) =====
    //
    // The Rust executor reaches a `NodeType::PluginNode`, registers a
    // pending oneshot for the node id, and emits PluginNodeRequested.
    // The Dart `SequenceExecutor` consumes this event, dispatches to
    // `PluginNodeExecutor.run`, then calls `api_sequencer_plugin_node_finished`
    // to push the verdict back into Rust via
    // `ExecutorCommand::PluginNodeFinished`. The Rust instruction node
    // unblocks with Success or Failure.
    /// Wave 6 Pack P — the executor is waiting for the Dart side to
    /// dispatch a plugin node and reply with the verdict.
    PluginNodeRequested {
        /// Executor-side node identifier. The reply MUST echo this.
        node_id: String,
        /// Stable plugin identifier (e.g. `com.example.pushover`).
        plugin_id: String,
        /// Stable per-plugin node type identifier (e.g. `pushover.notify`).
        node_type_id: String,
        /// Opaque JSON payload the plugin author authored on the Dart
        /// side. Rust forwards verbatim.
        config_json: String,
        /// Optional human-readable label. `None` => UI uses
        /// `node_type_id`.
        display_name: Option<String>,
        /// Effective timeout (seconds) the Rust side will wait. Dart
        /// MUST honour this; a longer run on the Dart side will be
        /// timed out by Rust first and surfaced as a failure.
        timeout_secs: u32,
    },
    /// Wave 6 Pack P — live plugin-node progress payload. Mirrors
    /// `ProgressDetail::PluginNode`. The JSON detail is serialised as a
    /// string at the bridge boundary because FRB does not transport
    /// `serde_json::Value` directly; Dart parses it with
    /// `jsonDecode(detail_json)`.
    PluginNodeProgress {
        node_id: String,
        plugin_id: String,
        node_type_id: String,
        /// Stringified plugin-authored payload. Empty string when the
        /// plugin emitted no payload.
        detail_json: String,
    },

    // ===== Wave 8 — Replay Debug: typed decision payload =====
    /// Wave 8 Replay Debug — a structured decision emitted by the
    /// sequencer (scheduler pick, trigger fire, recovery transition,
    /// frame verdict, adaptive swap, plugin invocation, manual operator
    /// action, or system event). Subscribers persist these to the
    /// `sequence_decisions` Drift table and the Replay screen scrubs
    /// chronologically through them.
    ///
    /// `details_json` is the JSON-stringified payload — FRB does not
    /// bridge `serde_json::Value` directly, so the Dart side does
    /// `jsonDecode(details_json)` to recover the structured map.
    ///
    /// `category` is the stable wire key (`scheduler_pick`,
    /// `trigger_fired`, etc.) — see
    /// `nightshade_sequencer::DecisionCategory::wire_key`.
    DecisionLogged {
        /// ISO-8601 UTC timestamp when the decision was made.
        timestamp_iso: String,
        /// Stable wire key for the underlying DecisionCategory variant.
        category: String,
        /// One-line human-readable summary.
        summary: String,
        /// JSON-stringified opaque details payload.
        details_json: String,
        /// Optional associated node id (scheduler / target / exposure
        /// node).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        node_id: Option<String>,
        /// `sequence_runs.id` this decision belongs to, if the executor
        /// has been stamped with one.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        sequence_run_id: Option<i64>,
    },
}

/// Pack H — flat scheduler score row exposed across FRB. Mirrors
/// `nightshade_sequencer::node::logic::target_scheduler::SchedulerScoreSummary`
/// but lives in the bridge crate so we don't have to expose the sequencer
/// type to FRB. The Dart side consumes this directly in the run-dashboard
/// scheduler panel.
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SchedulerScoreEntry {
    pub target_id: String,
    pub target_name: String,
    /// Total score (0..=100) the scheduler computed.
    pub total_score: f64,
    /// True when the target was eligible to run (cleared
    /// `min_score_to_run` and any altitude / window gates).
    pub runnable: bool,
    /// Human-readable reason, populated when `runnable == false`
    /// (e.g. "below altitude limit", "before start window").
    pub reason: Option<String>,
}

/// Safety-specific events
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SafetyEvent {
    WeatherUnsafe { reason: String },
    WeatherSafe,
    EmergencyStop { reason: String },
    ParkInitiated { reason: String },
    ParkCompleted,
}

/// System-level events
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SystemEvent {
    Initialized,
    ShuttingDown,
    Error {
        message: String,
    },
    DiskSpaceLow {
        available_gb: f64,
    },
    Notification {
        title: String,
        message: String,
        level: String,
        /// Wave 5.5 Pack M follow-up — per-NotificationNode override list of
        /// NotificationTransportKind names (Dart enum, serialised as strings).
        /// The Dart NotificationRouter consumes this field to bypass the
        /// matrix's `custom` rule and dispatch to the user-picked transports
        /// directly. `None` or empty = use matrix routing.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        explicit_transports: Option<Vec<String>>,
    },
    /// Notification that events were dropped due to slow consumer
    /// This is sent after the stream recovers to inform the Dart side
    EventsDropped {
        /// Number of events that were dropped/skipped
        dropped_count: u64,
        /// Total number of events dropped since app start
        total_dropped: u64,
    },
}

/// A unified event that can be any category
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NightshadeEvent {
    /// Unique event ID (monotonically increasing sequence number)
    pub event_id: u64,
    /// Timestamp when the event was created (milliseconds since Unix epoch)
    pub timestamp: i64,
    /// Severity level of the event
    pub severity: EventSeverity,
    /// Category of the event
    pub category: EventCategory,
    /// The actual event data
    pub payload: EventPayload,
    /// Event ID that caused this event (for causality tracking)
    /// None if this is a root event (no causal parent)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caused_by: Option<u64>,
    /// Correlation ID for grouping related events (e.g., all events from one exposure)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub correlation_id: Option<String>,
    /// Device ID if this event is device-related
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_id: Option<String>,
}

/// Event payload - one of the specific event types
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventPayload {
    Equipment(EquipmentEvent),
    Imaging(ImagingEvent),
    Guiding(GuidingEvent),
    Sequencer(SequencerEvent),
    Safety(SafetyEvent),
    System(SystemEvent),
    PolarAlignment(PolarAlignmentEvent),
    PolarAlignmentStatus(PolarAlignmentStatus),
    PolarAlignmentImage(PolarAlignmentImageEvent),
}

/// Statistics about the event bus
#[derive(Debug, Clone, Default)]
pub struct EventBusStats {
    /// Total events published
    pub events_published: u64,
    /// Events dropped due to slow receivers
    pub events_dropped: u64,
    /// Current number of subscribers
    pub subscriber_count: usize,
    /// Events by category (for the last N events)
    pub events_by_category: HashMap<EventCategory, u64>,
}

/// Global event bus for publishing and subscribing to events
pub struct EventBus {
    /// Main event channel
    sender: broadcast::Sender<NightshadeEvent>,
    /// Sequence number generator
    sequence: AtomicU64,
    /// Events published counter
    events_published: AtomicU64,
    /// Events dropped counter
    events_dropped: AtomicU64,
    /// Total events published by category
    events_by_category: Mutex<HashMap<EventCategory, u64>>,
    /// Channel capacity
    capacity: usize,
}

impl EventBus {
    /// Create a new event bus with the specified channel capacity
    pub fn new(capacity: usize) -> Self {
        let (sender, _) = broadcast::channel(capacity);
        Self {
            sender,
            sequence: AtomicU64::new(1),
            events_published: AtomicU64::new(0),
            events_dropped: AtomicU64::new(0),
            events_by_category: Mutex::new(HashMap::new()),
            capacity,
        }
    }

    /// Get the next sequence number
    fn next_sequence(&self) -> u64 {
        self.sequence.fetch_add(1, Ordering::SeqCst)
    }

    /// Publish an event to all subscribers
    /// Returns the event ID assigned to the published event
    pub fn publish(&self, event: NightshadeEvent) -> u64 {
        let event_id = event.event_id;
        let category = event.category;
        self.events_published.fetch_add(1, Ordering::Relaxed);
        {
            let mut counts = self
                .events_by_category
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            *counts.entry(category).or_insert(0) += 1;
        }

        let would_evict_for_lagging_receiver =
            self.sender.receiver_count() > 0 && self.sender.len() >= self.capacity;

        match self.sender.send(event) {
            Ok(_) => {
                if would_evict_for_lagging_receiver {
                    self.events_dropped.fetch_add(1, Ordering::Relaxed);
                }
            }
            Err(_) => {
                // No receivers - this is fine
            }
        }

        event_id
    }

    /// Publish an event with full tracking support
    ///
    /// # Arguments
    /// * `severity` - Event severity level
    /// * `category` - Event category
    /// * `payload` - The event data
    /// * `caused_by` - Optional parent event ID for causality tracking
    ///
    /// # Returns
    /// The event ID of the published event
    pub fn publish_with_tracking(
        &self,
        severity: EventSeverity,
        category: EventCategory,
        payload: EventPayload,
        caused_by: Option<u64>,
    ) -> u64 {
        let event_id = self.next_sequence();
        let event = NightshadeEvent {
            event_id,
            timestamp: chrono::Utc::now().timestamp_millis(),
            severity,
            category,
            payload,
            caused_by,
            correlation_id: None,
            device_id: None,
        };

        self.publish(event)
    }

    /// Publish an event with device context
    pub fn publish_device_event(
        &self,
        severity: EventSeverity,
        category: EventCategory,
        payload: EventPayload,
        device_id: &str,
        caused_by: Option<u64>,
    ) -> u64 {
        let event_id = self.next_sequence();
        let event = NightshadeEvent {
            event_id,
            timestamp: chrono::Utc::now().timestamp_millis(),
            severity,
            category,
            payload,
            caused_by,
            correlation_id: None,
            device_id: Some(device_id.to_string()),
        };

        self.publish(event)
    }

    /// Publish an event with correlation ID for grouping related events
    pub fn publish_correlated(
        &self,
        severity: EventSeverity,
        category: EventCategory,
        payload: EventPayload,
        correlation_id: &str,
        caused_by: Option<u64>,
    ) -> u64 {
        let event_id = self.next_sequence();
        let event = NightshadeEvent {
            event_id,
            timestamp: chrono::Utc::now().timestamp_millis(),
            severity,
            category,
            payload,
            caused_by,
            correlation_id: Some(correlation_id.to_string()),
            device_id: None,
        };

        self.publish(event)
    }

    /// Subscribe to receive events
    pub fn subscribe(&self) -> broadcast::Receiver<NightshadeEvent> {
        self.sender.subscribe()
    }

    /// Get the number of active subscribers
    pub fn subscriber_count(&self) -> usize {
        self.sender.receiver_count()
    }

    /// Get the current sequence number (useful for debugging)
    pub fn current_sequence(&self) -> u64 {
        self.sequence.load(Ordering::SeqCst)
    }

    /// Get statistics about the event bus
    pub fn stats(&self) -> EventBusStats {
        let events_by_category = self
            .events_by_category
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone();
        EventBusStats {
            events_published: self.events_published.load(Ordering::Relaxed),
            events_dropped: self.events_dropped.load(Ordering::Relaxed),
            subscriber_count: self.sender.receiver_count(),
            events_by_category,
        }
    }

    /// Check if there's capacity for more events
    pub fn has_capacity(&self) -> bool {
        // Broadcast channels don't have a way to check capacity directly
        // We rely on the lagged error handling
        true
    }

    /// Get the configured capacity
    pub fn capacity(&self) -> usize {
        self.capacity
    }
}

impl Default for EventBus {
    fn default() -> Self {
        Self::new(DEFAULT_EVENT_BUFFER_SIZE)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stats_track_events_by_category() {
        let bus = EventBus::new(8);

        bus.publish_with_tracking(
            EventSeverity::Info,
            EventCategory::Equipment,
            EventPayload::System(SystemEvent::Initialized),
            None,
        );
        bus.publish_with_tracking(
            EventSeverity::Info,
            EventCategory::Imaging,
            EventPayload::System(SystemEvent::Initialized),
            None,
        );

        let stats = bus.stats();
        assert_eq!(stats.events_published, 2);
        assert_eq!(stats.events_by_category[&EventCategory::Equipment], 1);
        assert_eq!(stats.events_by_category[&EventCategory::Imaging], 1);
    }

    #[test]
    fn stats_count_broadcast_evictions_for_lagging_receivers() {
        let bus = EventBus::new(1);
        let _receiver = bus.subscribe();

        for index in 0..2 {
            bus.publish_with_tracking(
                EventSeverity::Info,
                EventCategory::System,
                EventPayload::System(SystemEvent::Notification {
                    title: "test".to_string(),
                    message: format!("event {}", index),
                    level: "info".to_string(),
                }),
                None,
            );
        }

        assert_eq!(bus.stats().events_dropped, 1);
    }
}

/// Global sequence counter for events created outside of the EventBus.
/// This is used by `create_event_auto_id` for ad-hoc event creation.
static GLOBAL_EVENT_SEQUENCE: AtomicU64 = AtomicU64::new(1_000_000);

/// Create an event with the current timestamp and a specified event ID
pub fn create_event(
    event_id: u64,
    severity: EventSeverity,
    category: EventCategory,
    payload: EventPayload,
) -> NightshadeEvent {
    NightshadeEvent {
        event_id,
        timestamp: chrono::Utc::now().timestamp_millis(),
        severity,
        category,
        payload,
        caused_by: None,
        correlation_id: None,
        device_id: None,
    }
}

/// Create an event with an auto-generated event ID.
/// Useful for ad-hoc events created outside of the main EventBus.
/// Note: IDs start at 1,000,000 to avoid collisions with EventBus IDs which start at 1.
pub fn create_event_auto_id(
    severity: EventSeverity,
    category: EventCategory,
    payload: EventPayload,
) -> NightshadeEvent {
    let event_id = GLOBAL_EVENT_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    create_event(event_id, severity, category, payload)
}

/// Create an event with causality tracking
pub fn create_event_with_cause(
    event_id: u64,
    severity: EventSeverity,
    category: EventCategory,
    payload: EventPayload,
    caused_by: u64,
) -> NightshadeEvent {
    NightshadeEvent {
        event_id,
        timestamp: chrono::Utc::now().timestamp_millis(),
        severity,
        category,
        payload,
        caused_by: Some(caused_by),
        correlation_id: None,
        device_id: None,
    }
}

/// Thread-safe shared event bus
pub type SharedEventBus = Arc<EventBus>;

// =========================================================================
// Event Context for Tracking Causality
// =========================================================================

/// Context for tracking event causality
///
/// Pass this through operations to automatically track which events
/// caused other events.
#[derive(Debug, Clone)]
pub struct EventContext {
    /// The event ID that started this chain
    pub root_event_id: u64,
    /// The immediate parent event ID
    pub parent_event_id: u64,
    /// Correlation ID for grouping
    pub correlation_id: Option<String>,
    /// Device ID if this context is device-specific
    pub device_id: Option<String>,
}

impl EventContext {
    /// Create a new root event context
    pub fn new(event_id: u64) -> Self {
        Self {
            root_event_id: event_id,
            parent_event_id: event_id,
            correlation_id: None,
            device_id: None,
        }
    }

    /// Create a child context from this context
    pub fn child(&self, event_id: u64) -> Self {
        Self {
            root_event_id: self.root_event_id,
            parent_event_id: event_id,
            correlation_id: self.correlation_id.clone(),
            device_id: self.device_id.clone(),
        }
    }

    /// Set the correlation ID
    pub fn with_correlation(mut self, correlation_id: &str) -> Self {
        self.correlation_id = Some(correlation_id.to_string());
        self
    }

    /// Set the device ID
    pub fn with_device(mut self, device_id: &str) -> Self {
        self.device_id = Some(device_id.to_string());
        self
    }
}

// =========================================================================
// Correlation ID Generator
// =========================================================================

/// Generate a unique correlation ID
///
/// # `unwrap_or` policy (audit-rust §4.3)
///
/// `duration_since(UNIX_EPOCH).unwrap_or_default()` — only fails if the
/// system clock is set before 1970-01-01. A zero `Duration` then produces
/// the same correlation-ID format `corr-0-XXXXX`; the suffix is still
/// derived from `timestamp.wrapping_mul`, so collisions are unlikely
/// over a short pre-1970-clock interval. The ID is for log correlation
/// only — uniqueness is best-effort, not load-bearing for correctness.
pub fn generate_correlation_id() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros();

    // Simple format: timestamp-random (no external deps)
    let random = timestamp.wrapping_mul(6364136223846793005) % 100000;
    format!("corr-{}-{:05}", timestamp, random)
}
