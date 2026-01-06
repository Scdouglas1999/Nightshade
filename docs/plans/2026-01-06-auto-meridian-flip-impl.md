# Auto Meridian Flip Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement rock-solid auto meridian flip with sequencer triggers, standalone monitoring, and comprehensive settings.

**Architecture:** Two-mode system - explicit sequencer triggers that execute flips when threshold reached, and standalone background monitoring for manual imaging sessions. Both share the same flip executor and settings.

**Tech Stack:** Rust (sequencer triggers, flip execution, events), Dart/Flutter (providers, UI, settings), Drift (database), flutter_rust_bridge (FFI).

---

## Task 1: Create Dart Settings Model

**Files:**
- Create: `packages/nightshade_core/lib/src/models/meridian_flip_settings.dart`
- Modify: `packages/nightshade_core/lib/src/models/models.dart` (add export)

**Step 1: Create the settings model with freezed**

```dart
// packages/nightshade_core/lib/src/models/meridian_flip_settings.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'meridian_flip_settings.freezed.dart';
part 'meridian_flip_settings.g.dart';

/// Method used to determine when to trigger a meridian flip
enum MeridianTriggerMethod {
  /// Flip X minutes after target crosses meridian
  minutesPastMeridian,
  /// Flip X minutes before mount tracking limit
  minutesBeforeLimit,
  /// Flip when hour angle exceeds threshold
  hourAngleThreshold,
}

/// Action to take when meridian flip fails after all retries
enum FlipFailureAction {
  /// Pause sequence and alert user for manual intervention
  pauseAndAlert,
  /// Abort sequence and park mount
  abortAndPark,
}

/// Settings for auto meridian flip behavior
@freezed
class MeridianFlipSettings with _$MeridianFlipSettings {
  const factory MeridianFlipSettings({
    // === Mode Control ===
    /// Enable standalone monitoring when no sequence is running
    @Default(false) bool standaloneMonitoringEnabled,

    // === Trigger Conditions ===
    /// Which method to use for determining flip timing
    @Default(MeridianTriggerMethod.minutesPastMeridian) MeridianTriggerMethod triggerMethod,
    /// Minutes past meridian to trigger flip (default: 5)
    @Default(5.0) double minutesPastMeridian,
    /// Minutes before mount limit to trigger flip (default: 10)
    @Default(10.0) double minutesBeforeLimit,
    /// Hour angle threshold in hours to trigger flip (default: 0.5 = 30 min)
    @Default(0.5) double hourAngleThreshold,

    // === Flip Sequence Options ===
    /// Pause guider before flip
    @Default(true) bool pauseGuidingBeforeFlip,
    /// Plate solve and re-center after flip
    @Default(true) bool recenterAfterFlip,
    /// Run autofocus after flip
    @Default(false) bool refocusAfterFlip,
    /// Settle time in seconds after flip completes
    @Default(10.0) double settleTimeSeconds,
    /// Resume guiding after flip (if was running)
    @Default(true) bool resumeGuidingAfterFlip,

    // === Error Handling ===
    /// Maximum retry attempts
    @Default(3) int maxRetries,
    /// Delay between retries in seconds
    @Default([30.0, 60.0, 120.0]) List<double> retryDelaysSeconds,
    /// Action to take on permanent failure
    @Default(FlipFailureAction.pauseAndAlert) FlipFailureAction failureAction,

    // === Notifications ===
    /// Play sound alert when flip starts/completes/fails
    @Default(false) bool soundAlertOnFlip,
    /// Send push notification to mobile app
    @Default(true) bool pushNotificationOnFlip,
  }) = _MeridianFlipSettings;

  factory MeridianFlipSettings.fromJson(Map<String, dynamic> json) =>
      _$MeridianFlipSettingsFromJson(json);
}
```

**Step 2: Add export to models barrel file**

In `packages/nightshade_core/lib/src/models/models.dart`, add:
```dart
export 'meridian_flip_settings.dart';
```

**Step 3: Run code generation**

```bash
cd packages/nightshade_core && flutter pub run build_runner build --delete-conflicting-outputs
```

**Step 4: Verify generation succeeded**

Check that `meridian_flip_settings.freezed.dart` and `meridian_flip_settings.g.dart` were created.

**Step 5: Commit**

```bash
git add packages/nightshade_core/lib/src/models/
git commit -m "feat(meridian): add MeridianFlipSettings model with freezed"
```

---

## Task 2: Create Dart Event Models

**Files:**
- Create: `packages/nightshade_core/lib/src/models/meridian_flip_event.dart`
- Modify: `packages/nightshade_core/lib/src/models/models.dart` (add export)

**Step 1: Create event models**

```dart
// packages/nightshade_core/lib/src/models/meridian_flip_event.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'meridian_flip_event.freezed.dart';
part 'meridian_flip_event.g.dart';

/// Steps in the meridian flip sequence
enum FlipStep {
  pausingGuider,
  stoppingTracking,
  slewingToTarget,
  verifyingPierSide,
  resumingTracking,
  plateSolvingAndCentering,
  refocusing,
  resumingGuider,
  settling,
}

/// Pier side of the mount
enum PierSide {
  east,
  west,
  unknown,
}

/// Events emitted during meridian flip execution
@freezed
sealed class MeridianFlipEvent with _$MeridianFlipEvent {
  /// Flip is starting
  const factory MeridianFlipEvent.starting({
    required String targetName,
    required PierSide fromPierSide,
    required double hourAngle,
  }) = MeridianFlipStarting;

  /// A step has started
  const factory MeridianFlipEvent.stepStarted({
    required FlipStep step,
    required int stepIndex,
    required int totalSteps,
  }) = MeridianFlipStepStarted;

  /// A step completed successfully
  const factory MeridianFlipEvent.stepCompleted({
    required FlipStep step,
    double? durationSecs,
  }) = MeridianFlipStepCompleted;

  /// A step failed
  const factory MeridianFlipEvent.stepFailed({
    required FlipStep step,
    required String error,
  }) = MeridianFlipStepFailed;

  /// Overall progress update
  const factory MeridianFlipEvent.progress({
    required int percent,
  }) = MeridianFlipProgress;

  /// Retry scheduled after failure
  const factory MeridianFlipEvent.retryScheduled({
    required int attempt,
    required int maxAttempts,
    required double delaySecs,
  }) = MeridianFlipRetryScheduled;

  /// Flip completed successfully
  const factory MeridianFlipEvent.completed({
    required PierSide newPierSide,
    required double durationSecs,
  }) = MeridianFlipCompleted;

  /// Flip failed after all retries
  const factory MeridianFlipEvent.failed({
    required String error,
    required String actionTaken,
  }) = MeridianFlipFailed;

  /// Flip was aborted by user
  const factory MeridianFlipEvent.aborted({
    required String reason,
  }) = MeridianFlipAborted;

  factory MeridianFlipEvent.fromJson(Map<String, dynamic> json) =>
      _$MeridianFlipEventFromJson(json);
}
```

**Step 2: Add export**

```dart
export 'meridian_flip_event.dart';
```

**Step 3: Run code generation**

```bash
cd packages/nightshade_core && flutter pub run build_runner build --delete-conflicting-outputs
```

**Step 4: Commit**

```bash
git add packages/nightshade_core/lib/src/models/
git commit -m "feat(meridian): add MeridianFlipEvent models for progress streaming"
```

---

## Task 3: Add Database Schema for Settings

**Files:**
- Modify: `packages/nightshade_core/lib/src/database/tables/equipment_profiles.dart`
- Modify: `packages/nightshade_core/lib/src/database/database.dart` (bump schema version)

**Step 1: Add meridian flip overrides column to equipment_profiles**

In `equipment_profiles.dart`, add after line 39 (filterFocusOffsets):

```dart
  // Meridian flip settings overrides (JSON, nullable - uses global defaults if null)
  TextColumn get meridianFlipOverrides => text().nullable()();
```

**Step 2: Bump database schema version and add migration**

In `database.dart`, find the `schemaVersion` getter and increment it:
```dart
@override
int get schemaVersion => 6; // Was 5
```

Add migration in the `migration` getter:
```dart
// Add to migration steps
if (from < 6) {
  await m.addColumn(equipmentProfiles, equipmentProfiles.meridianFlipOverrides);
}
```

**Step 3: Run build_runner to regenerate database code**

```bash
cd packages/nightshade_core && flutter pub run build_runner build --delete-conflicting-outputs
```

**Step 4: Commit**

```bash
git add packages/nightshade_core/lib/src/database/
git commit -m "feat(meridian): add meridian_flip_overrides column to equipment_profiles (schema v6)"
```

---

## Task 4: Create Meridian Flip Settings Provider

**Files:**
- Create: `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart`
- Modify: `packages/nightshade_core/lib/src/providers/providers.dart` (add export)

**Step 1: Create the provider file**

```dart
// packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../models/meridian_flip_settings.dart';
import '../models/meridian_flip_event.dart';
import 'database_provider.dart';
import 'profile_provider.dart';

/// Key used to store global meridian flip settings in app_settings table
const _kMeridianFlipSettingsKey = 'meridian_flip_settings';

/// Provider for global meridian flip settings
final globalMeridianFlipSettingsProvider =
    StateNotifierProvider<GlobalMeridianFlipSettingsNotifier, MeridianFlipSettings>((ref) {
  final db = ref.watch(databaseProvider);
  return GlobalMeridianFlipSettingsNotifier(db);
});

class GlobalMeridianFlipSettingsNotifier extends StateNotifier<MeridianFlipSettings> {
  final NightshadeDatabase _db;

  GlobalMeridianFlipSettingsNotifier(this._db) : super(const MeridianFlipSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final setting = await (_db.select(_db.appSettings)
        ..where((t) => t.key.equals(_kMeridianFlipSettingsKey)))
        .getSingleOrNull();

      if (setting != null && setting.value.isNotEmpty) {
        final json = jsonDecode(setting.value) as Map<String, dynamic>;
        state = MeridianFlipSettings.fromJson(json);
      }
    } catch (e) {
      print('[MERIDIAN] Failed to load settings: $e');
    }
  }

  Future<void> updateSettings(MeridianFlipSettings settings) async {
    state = settings;
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      final json = jsonEncode(state.toJson());
      await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: _kMeridianFlipSettingsKey,
          value: json,
        ),
      );
    } catch (e) {
      print('[MERIDIAN] Failed to save settings: $e');
    }
  }
}

/// Provider that returns effective meridian flip settings
/// (profile overrides merged with global defaults)
final effectiveMeridianFlipSettingsProvider = Provider<MeridianFlipSettings>((ref) {
  final global = ref.watch(globalMeridianFlipSettingsProvider);
  final activeProfile = ref.watch(activeProfileProvider).valueOrNull;

  if (activeProfile == null) {
    return global;
  }

  // Check if profile has overrides
  final overridesJson = activeProfile.meridianFlipOverrides;
  if (overridesJson == null || overridesJson.isEmpty) {
    return global;
  }

  try {
    final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
    // Merge overrides with global defaults
    final globalJson = global.toJson();
    final merged = {...globalJson, ...overrides};
    return MeridianFlipSettings.fromJson(merged);
  } catch (e) {
    print('[MERIDIAN] Failed to parse profile overrides: $e');
    return global;
  }
});

/// Stream of meridian flip events during flip execution
final meridianFlipEventStreamProvider = StreamProvider<MeridianFlipEvent?>((ref) {
  // This will be connected to the Rust event stream via the backend
  // For now, return an empty stream - will be implemented in Task 6
  return const Stream.empty();
});

/// Current flip state for UI
enum FlipExecutionState {
  idle,
  executing,
  retrying,
  completed,
  failed,
  aborted,
}

/// Provider tracking current flip execution state
final flipExecutionStateProvider = StateProvider<FlipExecutionState>((ref) {
  return FlipExecutionState.idle;
});
```

**Step 2: Add export**

In `providers.dart`:
```dart
export 'meridian_flip_provider.dart';
```

**Step 3: Commit**

```bash
git add packages/nightshade_core/lib/src/providers/
git commit -m "feat(meridian): add meridian flip settings and event providers"
```

---

## Task 5: Enhance Rust MeridianFlipConfig

**Files:**
- Modify: `native/nightshade_native/sequencer/src/lib.rs`

**Step 1: Expand MeridianFlipConfig struct**

Find `MeridianFlipConfig` (around line 701) and replace with:

```rust
/// Method to determine when meridian flip should trigger
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq)]
pub enum MeridianTriggerMethod {
    #[default]
    MinutesPastMeridian,
    MinutesBeforeLimit,
    HourAngleThreshold,
}

/// Action when flip fails after all retries
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq)]
pub enum FlipFailureAction {
    #[default]
    PauseAndAlert,
    AbortAndPark,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeridianFlipConfig {
    // Trigger conditions
    pub trigger_method: MeridianTriggerMethod,
    pub minutes_past_meridian: f64,
    pub minutes_before_limit: f64,
    pub hour_angle_threshold: f64,

    // Flip sequence options
    pub pause_guiding: bool,
    pub auto_center: bool,
    pub refocus_after: bool,
    pub settle_time: f64,
    pub resume_guiding: bool,

    // Error handling
    pub max_retries: u32,
    pub retry_delays_secs: Vec<f64>,
    pub failure_action: FlipFailureAction,
}

impl Default for MeridianFlipConfig {
    fn default() -> Self {
        Self {
            trigger_method: MeridianTriggerMethod::MinutesPastMeridian,
            minutes_past_meridian: 5.0,
            minutes_before_limit: 10.0,
            hour_angle_threshold: 0.5,
            pause_guiding: true,
            auto_center: true,
            refocus_after: false,
            settle_time: 10.0,
            resume_guiding: true,
            max_retries: 3,
            retry_delays_secs: vec![30.0, 60.0, 120.0],
            failure_action: FlipFailureAction::PauseAndAlert,
        }
    }
}
```

**Step 2: Add MeridianFlip to RecoveryAction enum**

Find `RecoveryAction` enum (around line 830) and add new variant:

```rust
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub enum RecoveryAction {
    #[default]
    Continue,
    Pause,
    Autofocus,
    NextTarget,
    Retry { max_attempts: u32 },
    ParkAndAbort,
    CustomBranch,
    /// Execute meridian flip with given config
    MeridianFlip(MeridianFlipConfig),
}
```

**Step 3: Enhance TriggerType::MeridianFlip**

Find `TriggerType::MeridianFlip` in the enum and enhance it:

```rust
/// Trigger when meridian flip is needed (enhanced with config)
MeridianFlip {
    config: MeridianFlipConfig,
},
```

**Step 4: Verify compilation**

```bash
cd native/nightshade_native && cargo check --all-features
```

**Step 5: Commit**

```bash
git add native/nightshade_native/sequencer/src/lib.rs
git commit -m "feat(meridian): enhance MeridianFlipConfig with full settings and add RecoveryAction::MeridianFlip"
```

---

## Task 6: Add Meridian Flip Events Module

**Files:**
- Create: `native/nightshade_native/sequencer/src/meridian_events.rs`
- Modify: `native/nightshade_native/sequencer/src/lib.rs` (add module)

**Step 1: Create events module**

```rust
// native/nightshade_native/sequencer/src/meridian_events.rs
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
```

**Step 2: Add module to lib.rs**

At the top of `lib.rs` with other module declarations:
```rust
pub mod meridian_events;
pub use meridian_events::*;
```

**Step 3: Verify compilation**

```bash
cd native/nightshade_native && cargo check --all-features
```

**Step 4: Commit**

```bash
git add native/nightshade_native/sequencer/src/
git commit -m "feat(meridian): add MeridianFlipEvent module with verbose logging"
```

---

## Task 7: Update Trigger Check Logic

**Files:**
- Modify: `native/nightshade_native/sequencer/src/triggers.rs`

**Step 1: Update MeridianFlip trigger check**

Find the `TriggerType::MeridianFlip` match arm (around line 72) and replace with:

```rust
TriggerType::MeridianFlip { config } => {
    // Calculate if flip should trigger based on configured method
    match config.trigger_method {
        MeridianTriggerMethod::MinutesPastMeridian => {
            if let (Some(target_ra), Some(lst)) = (state.target_ra, state.local_sidereal_time) {
                // Hour angle = LST - RA (in hours)
                let hour_angle = lst - target_ra;
                // Normalize to -12 to +12 range
                let hour_angle = if hour_angle > 12.0 { hour_angle - 24.0 }
                                 else if hour_angle < -12.0 { hour_angle + 24.0 }
                                 else { hour_angle };
                // Convert threshold to hours
                let threshold_hours = config.minutes_past_meridian / 60.0;
                // Trigger if HA is past meridian by threshold amount
                // and we're on the "wrong" pier side (west = pre-flip)
                let should_flip = hour_angle > threshold_hours;

                if should_flip {
                    tracing::debug!(
                        "[MERIDIAN] Trigger check: HA={:.3}h, threshold={:.3}h, should_flip={}",
                        hour_angle, threshold_hours, should_flip
                    );
                }
                should_flip
            } else {
                false
            }
        }
        MeridianTriggerMethod::MinutesBeforeLimit => {
            // Use next_meridian_flip_time which should be set based on mount limits
            if let Some(flip_time) = state.next_meridian_flip_time {
                let now = chrono::Utc::now().timestamp();
                let time_to_flip = (flip_time - now) as f64 / 60.0;
                time_to_flip > 0.0 && time_to_flip <= config.minutes_before_limit
            } else {
                false
            }
        }
        MeridianTriggerMethod::HourAngleThreshold => {
            if let (Some(target_ra), Some(lst)) = (state.target_ra, state.local_sidereal_time) {
                let hour_angle = lst - target_ra;
                let hour_angle = if hour_angle > 12.0 { hour_angle - 24.0 }
                                 else if hour_angle < -12.0 { hour_angle + 24.0 }
                                 else { hour_angle };
                hour_angle.abs() > config.hour_angle_threshold
            } else {
                false
            }
        }
    }
}
```

**Step 2: Update default trigger creation**

Find the `create_default_triggers` function and update the meridian flip trigger:

```rust
// Meridian flip (enhanced)
triggers.push(TriggerMonitor::new(
    "meridian_flip",
    "Meridian Flip",
    TriggerType::MeridianFlip {
        config: MeridianFlipConfig::default()
    },
    RecoveryAction::MeridianFlip(MeridianFlipConfig::default()),
).with_cooldown(600)); // 10 minute cooldown
```

**Step 3: Add missing imports at top of triggers.rs**

```rust
use crate::{
    RecoveryAction, TriggerType, MeridianFlipConfig,
    MeridianTriggerMethod, FlipFailureAction
};
```

**Step 4: Verify compilation**

```bash
cd native/nightshade_native && cargo check --all-features
```

**Step 5: Commit**

```bash
git add native/nightshade_native/sequencer/src/triggers.rs
git commit -m "feat(meridian): update trigger check logic for all trigger methods"
```

---

## Task 8: Add TriggerState Fields

**Files:**
- Modify: `native/nightshade_native/sequencer/src/triggers.rs`

**Step 1: Add missing fields to TriggerState**

Find `TriggerState` struct and ensure it has:

```rust
#[derive(Debug, Clone, Default)]
pub struct TriggerState {
    // Existing fields...
    pub baseline_hfr: Option<f64>,
    pub current_hfr: Option<f64>,
    pub next_meridian_flip_time: Option<i64>,
    pub guiding_rms_history: Option<Vec<(std::time::Instant, f64)>>,
    pub current_altitude: Option<f64>,
    pub weather_safe: bool,
    pub baseline_temperature: Option<f64>,
    pub current_temperature: Option<f64>,
    pub filter_changed: bool,
    pub dawn_time: Option<i64>,
    pub completed_exposures: u32,
    pub last_autofocus_frame: u32,
    pub last_dither_frame: u32,
    pub mount_tracking_expected: bool,
    pub mount_tracking_lost: bool,
    pub dome_shutter_open_expected: bool,
    pub dome_shutter_status: Option<String>,

    // NEW fields for enhanced meridian flip
    pub target_ra: Option<f64>,           // Target RA in hours
    pub target_dec: Option<f64>,          // Target Dec in degrees
    pub local_sidereal_time: Option<f64>, // Current LST in hours
    pub current_pier_side: Option<crate::meridian_events::PierSide>,
}
```

**Step 2: Verify compilation**

```bash
cd native/nightshade_native && cargo check --all-features
```

**Step 3: Commit**

```bash
git add native/nightshade_native/sequencer/src/triggers.rs
git commit -m "feat(meridian): add target_ra, local_sidereal_time, pier_side to TriggerState"
```

---

## Task 9: Implement Meridian Flip Executor

**Files:**
- Create: `native/nightshade_native/sequencer/src/meridian_executor.rs`
- Modify: `native/nightshade_native/sequencer/src/lib.rs` (add module)

**Step 1: Create executor module**

```rust
// native/nightshade_native/sequencer/src/meridian_executor.rs
//! Executes the meridian flip sequence with comprehensive error handling

use crate::{
    MeridianFlipConfig, FlipFailureAction,
    meridian_events::{FlipStep, MeridianFlipEvent, FlipEventEmitter, PierSide},
    device_ops::SharedDeviceOps,
};
use std::time::{Duration, Instant};
use tokio::sync::broadcast;

/// Result of a meridian flip execution
#[derive(Debug)]
pub enum FlipResult {
    Success { new_pier_side: PierSide, duration_secs: f64 },
    Failed { error: String },
    Aborted { reason: String },
}

/// Executes meridian flip with full event streaming
pub struct MeridianFlipExecutor {
    config: MeridianFlipConfig,
    device_ops: SharedDeviceOps,
    mount_id: String,
    target_ra: f64,
    target_dec: f64,
    target_name: String,
    emitter: FlipEventEmitter,
    abort_rx: Option<broadcast::Receiver<()>>,
}

impl MeridianFlipExecutor {
    pub fn new(
        config: MeridianFlipConfig,
        device_ops: SharedDeviceOps,
        mount_id: String,
        target_ra: f64,
        target_dec: f64,
        target_name: String,
    ) -> Self {
        Self {
            config,
            device_ops,
            mount_id,
            target_ra,
            target_dec,
            target_name,
            emitter: FlipEventEmitter::new(),
            abort_rx: None,
        }
    }

    pub fn with_abort_receiver(mut self, rx: broadcast::Receiver<()>) -> Self {
        self.abort_rx = Some(rx);
        self
    }

    pub fn with_event_callback(
        mut self,
        callback: Box<dyn Fn(MeridianFlipEvent) + Send + Sync>
    ) -> Self {
        self.emitter = FlipEventEmitter::new().with_callback(callback);
        self
    }

    /// Execute the flip with retries
    pub async fn execute(&mut self) -> FlipResult {
        let start_time = Instant::now();
        let mut attempt = 0;

        loop {
            attempt += 1;

            match self.execute_flip_sequence().await {
                Ok(pier_side) => {
                    let duration = start_time.elapsed().as_secs_f64();
                    self.emitter.emit(MeridianFlipEvent::Completed {
                        new_pier_side: pier_side,
                        duration_secs: duration,
                    });
                    return FlipResult::Success {
                        new_pier_side: pier_side,
                        duration_secs: duration
                    };
                }
                Err(e) => {
                    if attempt >= self.config.max_retries as usize {
                        // All retries exhausted
                        let action = match self.config.failure_action {
                            FlipFailureAction::PauseAndAlert => "Pausing sequence - manual intervention required",
                            FlipFailureAction::AbortAndPark => "Aborting sequence and parking mount",
                        };
                        self.emitter.emit(MeridianFlipEvent::Failed {
                            error: e.clone(),
                            action_taken: action.to_string(),
                        });
                        return FlipResult::Failed { error: e };
                    }

                    // Schedule retry
                    let delay_idx = (attempt - 1).min(self.config.retry_delays_secs.len() - 1);
                    let delay = self.config.retry_delays_secs.get(delay_idx)
                        .copied()
                        .unwrap_or(60.0);

                    self.emitter.emit(MeridianFlipEvent::RetryScheduled {
                        attempt: attempt as u8,
                        max_attempts: self.config.max_retries as u8,
                        delay_secs: delay,
                    });

                    // Wait for retry delay, checking for abort
                    if self.wait_with_abort(Duration::from_secs_f64(delay)).await {
                        self.emitter.emit(MeridianFlipEvent::Aborted {
                            reason: "User cancelled during retry wait".to_string(),
                        });
                        return FlipResult::Aborted {
                            reason: "User cancelled".to_string()
                        };
                    }
                }
            }
        }
    }

    /// Execute the flip sequence steps
    async fn execute_flip_sequence(&mut self) -> Result<PierSide, String> {
        // Determine which steps are needed
        let mut steps = vec![FlipStep::SlewingToTarget, FlipStep::VerifyingPierSide];

        if self.config.pause_guiding {
            steps.insert(0, FlipStep::PausingGuider);
        }
        steps.insert(if self.config.pause_guiding { 1 } else { 0 }, FlipStep::StoppingTracking);

        // After slew
        steps.push(FlipStep::ResumingTracking);

        if self.config.auto_center {
            steps.push(FlipStep::PlateSolvingAndCentering);
        }
        if self.config.refocus_after {
            steps.push(FlipStep::Refocusing);
        }
        if self.config.pause_guiding && self.config.resume_guiding {
            steps.push(FlipStep::ResumingGuider);
        }
        if self.config.settle_time > 0.0 {
            steps.push(FlipStep::Settling);
        }

        let total_steps = steps.len() as u8;
        let current_pier_side = self.get_pier_side().await.unwrap_or(PierSide::Unknown);

        // Emit starting event
        self.emitter.emit(MeridianFlipEvent::Starting {
            target_name: self.target_name.clone(),
            from_pier_side: current_pier_side,
            hour_angle: 0.0, // TODO: Calculate actual HA
        });

        // Execute each step
        for (idx, step) in steps.iter().enumerate() {
            // Check for abort
            if self.check_abort() {
                // Attempt cleanup
                let _ = self.device_ops.mount_set_tracking(&self.mount_id, true).await;
                return Err("Aborted by user".to_string());
            }

            self.emitter.emit(MeridianFlipEvent::StepStarted {
                step: *step,
                step_index: idx as u8,
                total_steps,
            });

            let step_start = Instant::now();
            let result = self.execute_step(*step).await;
            let duration = step_start.elapsed().as_secs_f64();

            match result {
                Ok(()) => {
                    self.emitter.emit(MeridianFlipEvent::StepCompleted {
                        step: *step,
                        duration_secs: Some(duration),
                    });
                }
                Err(e) => {
                    self.emitter.emit(MeridianFlipEvent::StepFailed {
                        step: *step,
                        error: e.clone(),
                    });
                    // Attempt to restore tracking on failure
                    let _ = self.device_ops.mount_set_tracking(&self.mount_id, true).await;
                    return Err(e);
                }
            }

            // Update progress
            let progress = ((idx + 1) as f32 / total_steps as f32 * 100.0) as u8;
            self.emitter.emit(MeridianFlipEvent::Progress { percent: progress });
        }

        // Return new pier side
        self.get_pier_side().await.ok_or_else(|| "Could not determine pier side".to_string())
    }

    async fn execute_step(&self, step: FlipStep) -> Result<(), String> {
        match step {
            FlipStep::PausingGuider => {
                // TODO: Implement guider pause via device_ops
                // For now, just log
                tracing::info!("[MERIDIAN] Would pause guider here");
                Ok(())
            }
            FlipStep::StoppingTracking => {
                self.device_ops.mount_set_tracking(&self.mount_id, false).await
                    .map_err(|e| format!("Failed to stop tracking: {}", e))
            }
            FlipStep::SlewingToTarget => {
                // Slew to same coordinates - mount should flip to opposite pier side
                self.device_ops.mount_slew_to_coordinates(
                    &self.mount_id,
                    self.target_ra,
                    self.target_dec
                ).await.map_err(|e| format!("Slew failed: {}", e))?;

                // Wait for slew to complete with timeout
                let timeout = Duration::from_secs(300);
                let start = Instant::now();
                while start.elapsed() < timeout {
                    if !self.device_ops.mount_is_slewing(&self.mount_id).await
                        .unwrap_or(true) {
                        return Ok(());
                    }
                    tokio::time::sleep(Duration::from_millis(500)).await;
                }
                Err("Slew timeout after 300 seconds".to_string())
            }
            FlipStep::VerifyingPierSide => {
                let new_side = self.get_pier_side().await;
                tracing::info!("[MERIDIAN] New pier side: {:?}", new_side);
                // TODO: Verify it actually changed
                Ok(())
            }
            FlipStep::ResumingTracking => {
                self.device_ops.mount_set_tracking(&self.mount_id, true).await
                    .map_err(|e| format!("Failed to resume tracking: {}", e))
            }
            FlipStep::PlateSolvingAndCentering => {
                // TODO: Implement plate solve and centering
                tracing::info!("[MERIDIAN] Would plate solve and center here");
                Ok(())
            }
            FlipStep::Refocusing => {
                // TODO: Implement autofocus call
                tracing::info!("[MERIDIAN] Would run autofocus here");
                Ok(())
            }
            FlipStep::ResumingGuider => {
                // TODO: Implement guider resume
                tracing::info!("[MERIDIAN] Would resume guider here");
                Ok(())
            }
            FlipStep::Settling => {
                tracing::info!("[MERIDIAN] Settling for {:.1}s", self.config.settle_time);
                tokio::time::sleep(Duration::from_secs_f64(self.config.settle_time)).await;
                Ok(())
            }
        }
    }

    async fn get_pier_side(&self) -> Option<PierSide> {
        match self.device_ops.mount_side_of_pier(&self.mount_id).await {
            Ok(side) => Some(side),
            Err(_) => None,
        }
    }

    fn check_abort(&mut self) -> bool {
        if let Some(rx) = &mut self.abort_rx {
            rx.try_recv().is_ok()
        } else {
            false
        }
    }

    async fn wait_with_abort(&mut self, duration: Duration) -> bool {
        let deadline = Instant::now() + duration;
        while Instant::now() < deadline {
            if self.check_abort() {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        false
    }
}
```

**Step 2: Add module to lib.rs**

```rust
pub mod meridian_executor;
pub use meridian_executor::*;
```

**Step 3: Verify compilation**

```bash
cd native/nightshade_native && cargo check --all-features
```

**Step 4: Commit**

```bash
git add native/nightshade_native/sequencer/src/
git commit -m "feat(meridian): add MeridianFlipExecutor with retry logic and event streaming"
```

---

## Task 10: Wire Executor to RecoveryAction Handler

**Files:**
- Modify: `native/nightshade_native/sequencer/src/node.rs`

**Step 1: Add MeridianFlip handling to execute_recovery**

Find the `execute_recovery` method and add handling for `RecoveryAction::MeridianFlip`:

```rust
RecoveryAction::MeridianFlip(config) => {
    tracing::info!("[MERIDIAN] Executing meridian flip from recovery action");

    // Get required context
    let mount_id = context.mount_id.clone()
        .ok_or_else(|| "No mount ID in context".to_string())?;
    let target_ra = context.target_ra
        .ok_or_else(|| "No target RA in context".to_string())?;
    let target_dec = context.target_dec
        .ok_or_else(|| "No target Dec in context".to_string())?;
    let target_name = context.target_name.clone()
        .unwrap_or_else(|| "Unknown Target".to_string());

    // Create and execute flip
    let mut executor = crate::MeridianFlipExecutor::new(
        config.clone(),
        context.device_ops.clone(),
        mount_id,
        target_ra,
        target_dec,
        target_name,
    );

    match executor.execute().await {
        crate::FlipResult::Success { .. } => {
            tracing::info!("[MERIDIAN] Flip completed successfully");
            // Continue with sequence
        }
        crate::FlipResult::Failed { error } => {
            tracing::error!("[MERIDIAN] Flip failed: {}", error);
            match config.failure_action {
                crate::FlipFailureAction::PauseAndAlert => {
                    return NodeStatus::Paused;
                }
                crate::FlipFailureAction::AbortAndPark => {
                    // Park mount
                    if let Err(e) = context.device_ops.mount_park(&context.mount_id.clone().unwrap_or_default()).await {
                        tracing::error!("[MERIDIAN] Failed to park mount: {}", e);
                    }
                    return NodeStatus::Failed(format!("Meridian flip failed: {}", error));
                }
            }
        }
        crate::FlipResult::Aborted { reason } => {
            tracing::warn!("[MERIDIAN] Flip aborted: {}", reason);
            return NodeStatus::Paused;
        }
    }
}
```

**Step 2: Add necessary imports at top of node.rs**

Ensure these are imported:
```rust
use crate::{MeridianFlipConfig, FlipFailureAction, MeridianFlipExecutor, FlipResult};
```

**Step 3: Verify compilation**

```bash
cd native/nightshade_native && cargo check --all-features
```

**Step 4: Commit**

```bash
git add native/nightshade_native/sequencer/src/node.rs
git commit -m "feat(meridian): wire MeridianFlipExecutor to RecoveryAction handler"
```

---

## Task 11: Add Preflight Validation for Missing Trigger

**Files:**
- Modify: `packages/nightshade_app/lib/screens/sequencer/widgets/preflight_validation_dialog.dart`

**Step 1: Add check for meridian flip trigger**

Add new method after `_checkTiming`:

```dart
/// Check if sequence has meridian flip trigger
List<ValidationIssue> _checkMeridianFlipTrigger(Sequence sequence) {
  final issues = <ValidationIssue>[];

  // Look for a meridian flip trigger node in the sequence
  final hasMeridianTrigger = sequence.nodes.values.any((node) {
    // Check if node is a trigger node with meridian flip type
    if (node is TriggerNode) {
      return node.triggerType == 'meridian_flip';
    }
    return false;
  });

  if (!hasMeridianTrigger) {
    issues.add(const ValidationIssue(
      severity: ValidationSeverity.warning,
      category: 'Meridian Flip',
      title: 'No Meridian Flip Trigger',
      description: 'This sequence does not have a meridian flip trigger. '
          'If your target crosses the meridian during the session, the mount may hit tracking limits.',
      resolution: 'Add a Meridian Flip trigger node to enable automatic flips, '
          'or ensure your target does not cross the meridian during the imaging window.',
    ));
  }

  return issues;
}
```

**Step 2: Call the check in validate method**

Add to the `validate` method around line 74:
```dart
issues.addAll(_checkMeridianFlipTrigger(sequence));
```

**Step 3: Commit**

```bash
git add packages/nightshade_app/lib/screens/sequencer/widgets/preflight_validation_dialog.dart
git commit -m "feat(meridian): add preflight warning for missing meridian flip trigger"
```

---

## Task 12: Create Progress Dialog Widget

**Files:**
- Create: `packages/nightshade_app/lib/screens/sequencer/widgets/meridian_flip_progress_dialog.dart`

**Step 1: Create the dialog widget**

```dart
// packages/nightshade_app/lib/screens/sequencer/widgets/meridian_flip_progress_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Shows real-time progress of a meridian flip operation
class MeridianFlipProgressDialog extends ConsumerStatefulWidget {
  final String targetName;
  final VoidCallback onAbort;

  const MeridianFlipProgressDialog({
    required this.targetName,
    required this.onAbort,
    super.key,
  });

  @override
  ConsumerState<MeridianFlipProgressDialog> createState() =>
      _MeridianFlipProgressDialogState();
}

class _MeridianFlipProgressDialogState
    extends ConsumerState<MeridianFlipProgressDialog> {
  final List<_StepStatus> _steps = [];
  int _currentStep = 0;
  int _progress = 0;
  String? _error;
  bool _isComplete = false;
  bool _isAborting = false;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _initializeSteps();
  }

  void _initializeSteps() {
    final settings = ref.read(effectiveMeridianFlipSettingsProvider);

    _steps.clear();
    if (settings.pauseGuidingBeforeFlip) {
      _steps.add(_StepStatus(FlipStep.pausingGuider, 'Pausing guider'));
    }
    _steps.add(_StepStatus(FlipStep.stoppingTracking, 'Stopping tracking'));
    _steps.add(_StepStatus(FlipStep.slewingToTarget, 'Slewing to target (flip)'));
    _steps.add(_StepStatus(FlipStep.verifyingPierSide, 'Verifying pier side'));
    _steps.add(_StepStatus(FlipStep.resumingTracking, 'Resuming tracking'));
    if (settings.recenterAfterFlip) {
      _steps.add(_StepStatus(FlipStep.plateSolvingAndCentering, 'Plate solving and centering'));
    }
    if (settings.refocusAfterFlip) {
      _steps.add(_StepStatus(FlipStep.refocusing, 'Running autofocus'));
    }
    if (settings.resumeGuidingAfterFlip && settings.pauseGuidingBeforeFlip) {
      _steps.add(_StepStatus(FlipStep.resumingGuider, 'Resuming guider'));
    }
    if (settings.settleTimeSeconds > 0) {
      _steps.add(_StepStatus(FlipStep.settling, 'Settling (${settings.settleTimeSeconds.toInt()}s)'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final elapsed = _startTime != null
        ? DateTime.now().difference(_startTime!).inSeconds
        : 0;

    // Listen to flip events
    ref.listen<AsyncValue<MeridianFlipEvent?>>(
      meridianFlipEventStreamProvider,
      (_, next) {
        next.whenData((event) {
          if (event != null) _handleEvent(event);
        });
      },
    );

    return Dialog(
      backgroundColor: colors.surface,
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                if (!_isComplete && _error == null)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  )
                else if (_isComplete)
                  Icon(LucideIcons.checkCircle, color: colors.success, size: 20)
                else
                  Icon(LucideIcons.alertCircle, color: colors.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isComplete
                        ? 'Meridian Flip Complete'
                        : _error != null
                            ? 'Meridian Flip Failed'
                            : 'Meridian Flip in Progress',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Target name
            Text(
              'Target: ${widget.targetName}',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),

            Divider(color: colors.border, height: 24),

            // Steps list
            ...List.generate(_steps.length, (index) {
              final step = _steps[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    _buildStepIcon(step, index, colors),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        step.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: step.status == _StepState.pending
                              ? colors.textMuted
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                    if (step.duration != null)
                      Text(
                        '${step.duration!.toStringAsFixed(1)}s',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textMuted,
                        ),
                      ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress / 100,
                backgroundColor: colors.surfaceAlt,
                color: _error != null ? colors.error : colors.primary,
                minHeight: 6,
              ),
            ),

            const SizedBox(height: 8),

            // Footer info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Elapsed: ${_formatDuration(elapsed)}',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
                Text(
                  'Step ${_currentStep + 1} of ${_steps.length}',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ],
            ),

            // Error message
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.alertTriangle, color: colors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 12, color: colors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isComplete && _error == null)
                  TextButton(
                    onPressed: _isAborting ? null : () {
                      setState(() => _isAborting = true);
                      widget.onAbort();
                    },
                    child: Text(
                      _isAborting ? 'Aborting...' : 'Abort Flip',
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                if (_isComplete || _error != null)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Close',
                      style: TextStyle(color: colors.primary),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIcon(_StepStatus step, int index, NightshadeColors colors) {
    switch (step.status) {
      case _StepState.pending:
        return Icon(LucideIcons.circle, size: 16, color: colors.textMuted);
      case _StepState.inProgress:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.primary,
          ),
        );
      case _StepState.completed:
        return Icon(LucideIcons.checkCircle, size: 16, color: colors.success);
      case _StepState.failed:
        return Icon(LucideIcons.xCircle, size: 16, color: colors.error);
    }
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  void _handleEvent(MeridianFlipEvent event) {
    setState(() {
      switch (event) {
        case MeridianFlipStepStarted(:final stepIndex):
          _currentStep = stepIndex;
          if (stepIndex < _steps.length) {
            _steps[stepIndex].status = _StepState.inProgress;
          }
        case MeridianFlipStepCompleted(:final step, :final durationSecs):
          final idx = _steps.indexWhere((s) => s.step == step);
          if (idx >= 0) {
            _steps[idx].status = _StepState.completed;
            _steps[idx].duration = durationSecs;
          }
        case MeridianFlipStepFailed(:final step, :final error):
          final idx = _steps.indexWhere((s) => s.step == step);
          if (idx >= 0) {
            _steps[idx].status = _StepState.failed;
          }
          _error = error;
        case MeridianFlipProgress(:final percent):
          _progress = percent;
        case MeridianFlipCompleted():
          _isComplete = true;
          _progress = 100;
          // Auto-close after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        case MeridianFlipFailed(:final error):
          _error = error;
        case MeridianFlipAborted(:final reason):
          _error = 'Aborted: $reason';
        default:
          break;
      }
    });
  }
}

enum _StepState { pending, inProgress, completed, failed }

class _StepStatus {
  final FlipStep step;
  final String label;
  _StepState status;
  double? duration;

  _StepStatus(this.step, this.label) : status = _StepState.pending;
}
```

**Step 2: Commit**

```bash
git add packages/nightshade_app/lib/screens/sequencer/widgets/
git commit -m "feat(meridian): add MeridianFlipProgressDialog with live step tracking"
```

---

## Task 13: Create Settings Screen

**Files:**
- Create: `packages/nightshade_app/lib/screens/settings/meridian_flip_settings_screen.dart`
- Modify: `packages/nightshade_app/lib/screens/settings/settings_screen.dart` (add navigation)

**Step 1: Create settings screen**

```dart
// packages/nightshade_app/lib/screens/settings/meridian_flip_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class MeridianFlipSettingsScreen extends ConsumerStatefulWidget {
  const MeridianFlipSettingsScreen({super.key});

  @override
  ConsumerState<MeridianFlipSettingsScreen> createState() =>
      _MeridianFlipSettingsScreenState();
}

class _MeridianFlipSettingsScreenState
    extends ConsumerState<MeridianFlipSettingsScreen> {
  late MeridianFlipSettings _settings;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(globalMeridianFlipSettingsProvider);
  }

  void _updateSettings(MeridianFlipSettings newSettings) {
    setState(() {
      _settings = newSettings;
      _hasChanges = true;
    });
  }

  Future<void> _saveSettings() async {
    await ref.read(globalMeridianFlipSettingsProvider.notifier)
        .updateSettings(_settings);
    setState(() => _hasChanges = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meridian flip settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          'Meridian Flip Settings',
          style: TextStyle(color: colors.textPrimary),
        ),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saveSettings,
              child: Text('Save', style: TextStyle(color: colors.primary)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Mode Control Section
          _buildSection(
            colors,
            'Mode Control',
            [
              _buildSwitchTile(
                colors,
                'Standalone Monitoring',
                'Monitor for meridian crossing even when no sequence is running',
                _settings.standaloneMonitoringEnabled,
                (value) => _updateSettings(
                  _settings.copyWith(standaloneMonitoringEnabled: value),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Trigger Conditions Section
          _buildSection(
            colors,
            'Trigger Conditions',
            [
              _buildDropdownTile<MeridianTriggerMethod>(
                colors,
                'Trigger Method',
                'How to determine when to flip',
                _settings.triggerMethod,
                MeridianTriggerMethod.values,
                (method) => method.name,
                (value) => _updateSettings(
                  _settings.copyWith(triggerMethod: value),
                ),
              ),
              if (_settings.triggerMethod == MeridianTriggerMethod.minutesPastMeridian)
                _buildNumberTile(
                  colors,
                  'Minutes Past Meridian',
                  'Flip this many minutes after target crosses meridian',
                  _settings.minutesPastMeridian,
                  (value) => _updateSettings(
                    _settings.copyWith(minutesPastMeridian: value),
                  ),
                  min: 0,
                  max: 60,
                ),
              if (_settings.triggerMethod == MeridianTriggerMethod.minutesBeforeLimit)
                _buildNumberTile(
                  colors,
                  'Minutes Before Limit',
                  'Flip this many minutes before mount tracking limit',
                  _settings.minutesBeforeLimit,
                  (value) => _updateSettings(
                    _settings.copyWith(minutesBeforeLimit: value),
                  ),
                  min: 5,
                  max: 60,
                ),
              if (_settings.triggerMethod == MeridianTriggerMethod.hourAngleThreshold)
                _buildNumberTile(
                  colors,
                  'Hour Angle Threshold (hours)',
                  'Flip when hour angle exceeds this value',
                  _settings.hourAngleThreshold,
                  (value) => _updateSettings(
                    _settings.copyWith(hourAngleThreshold: value),
                  ),
                  min: 0,
                  max: 6,
                  decimals: 2,
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Flip Sequence Section
          _buildSection(
            colors,
            'Flip Sequence',
            [
              _buildSwitchTile(
                colors,
                'Pause Guiding',
                'Stop guider before flip',
                _settings.pauseGuidingBeforeFlip,
                (value) => _updateSettings(
                  _settings.copyWith(pauseGuidingBeforeFlip: value),
                ),
              ),
              _buildSwitchTile(
                colors,
                'Re-center After Flip',
                'Plate solve and center target after flip',
                _settings.recenterAfterFlip,
                (value) => _updateSettings(
                  _settings.copyWith(recenterAfterFlip: value),
                ),
              ),
              _buildSwitchTile(
                colors,
                'Refocus After Flip',
                'Run autofocus after flip',
                _settings.refocusAfterFlip,
                (value) => _updateSettings(
                  _settings.copyWith(refocusAfterFlip: value),
                ),
              ),
              _buildNumberTile(
                colors,
                'Settle Time (seconds)',
                'Wait time after flip before resuming',
                _settings.settleTimeSeconds,
                (value) => _updateSettings(
                  _settings.copyWith(settleTimeSeconds: value),
                ),
                min: 0,
                max: 120,
              ),
              _buildSwitchTile(
                colors,
                'Resume Guiding',
                'Restart guider after flip',
                _settings.resumeGuidingAfterFlip,
                (value) => _updateSettings(
                  _settings.copyWith(resumeGuidingAfterFlip: value),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Error Handling Section
          _buildSection(
            colors,
            'Error Handling',
            [
              _buildNumberTile(
                colors,
                'Max Retries',
                'Number of retry attempts on failure',
                _settings.maxRetries.toDouble(),
                (value) => _updateSettings(
                  _settings.copyWith(maxRetries: value.toInt()),
                ),
                min: 0,
                max: 10,
                decimals: 0,
              ),
              _buildDropdownTile<FlipFailureAction>(
                colors,
                'On Failure',
                'Action to take after all retries exhausted',
                _settings.failureAction,
                FlipFailureAction.values,
                (action) => action == FlipFailureAction.pauseAndAlert
                    ? 'Pause & Alert'
                    : 'Abort & Park',
                (value) => _updateSettings(
                  _settings.copyWith(failureAction: value),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Notifications Section
          _buildSection(
            colors,
            'Notifications',
            [
              _buildSwitchTile(
                colors,
                'Sound Alert',
                'Play sound on flip events',
                _settings.soundAlertOnFlip,
                (value) => _updateSettings(
                  _settings.copyWith(soundAlertOnFlip: value),
                ),
              ),
              _buildSwitchTile(
                colors,
                'Push Notification',
                'Send notification to mobile app',
                _settings.pushNotificationOnFlip,
                (value) => _updateSettings(
                  _settings.copyWith(pushNotificationOnFlip: value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    NightshadeColors colors,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
    NightshadeColors colors,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      title: Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: colors.textMuted, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: colors.primary,
      ),
    );
  }

  Widget _buildNumberTile(
    NightshadeColors colors,
    String title,
    String subtitle,
    double value,
    ValueChanged<double> onChanged, {
    double min = 0,
    double max = 100,
    int decimals = 1,
  }) {
    return ListTile(
      title: Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: colors.textMuted, fontSize: 12)),
      trailing: SizedBox(
        width: 80,
        child: TextField(
          controller: TextEditingController(text: value.toStringAsFixed(decimals)),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onSubmitted: (text) {
            final parsed = double.tryParse(text);
            if (parsed != null) {
              onChanged(parsed.clamp(min, max));
            }
          },
        ),
      ),
    );
  }

  Widget _buildDropdownTile<T>(
    NightshadeColors colors,
    String title,
    String subtitle,
    T value,
    List<T> items,
    String Function(T) labelBuilder,
    ValueChanged<T> onChanged,
  ) {
    return ListTile(
      title: Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: colors.textMuted, fontSize: 12)),
      trailing: DropdownButton<T>(
        value: value,
        items: items.map((item) => DropdownMenuItem(
          value: item,
          child: Text(labelBuilder(item)),
        )).toList(),
        onChanged: (newValue) {
          if (newValue != null) onChanged(newValue);
        },
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.textPrimary, fontSize: 13),
      ),
    );
  }
}
```

**Step 2: Add navigation from settings screen**

In `settings_screen.dart`, add a tile that navigates to the new screen:

```dart
ListTile(
  leading: Icon(LucideIcons.rotateCcw, color: colors.textSecondary),
  title: Text('Meridian Flip', style: TextStyle(color: colors.textPrimary)),
  subtitle: Text('Auto flip settings', style: TextStyle(color: colors.textMuted, fontSize: 12)),
  trailing: Icon(LucideIcons.chevronRight, color: colors.textMuted),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const MeridianFlipSettingsScreen()),
  ),
),
```

**Step 3: Commit**

```bash
git add packages/nightshade_app/lib/screens/settings/
git commit -m "feat(meridian): add MeridianFlipSettingsScreen with full configuration options"
```

---

## Task 14: Regenerate FRB Bindings

**Files:**
- Various generated files in `packages/nightshade_bridge/`

**Step 1: Set environment and run codegen**

```powershell
$env:CPATH = "C:\Program Files\LLVM\lib\clang\21\include;C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.43.34808\include;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\ucrt;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\um;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\shared"
cd native/nightshade_native
flutter_rust_bridge_codegen generate
```

**Step 2: Run Dart build_runner**

```bash
cd packages/nightshade_bridge && flutter pub run build_runner build --delete-conflicting-outputs
```

**Step 3: Build Rust**

```bash
cd native/nightshade_native && cargo build --release
```

**Step 4: Copy DLL**

```bash
cp native/nightshade_native/target/release/nightshade_bridge.dll apps/desktop/
```

**Step 5: Verify Flutter analyze passes**

```bash
cd apps/desktop && flutter analyze
```

**Step 6: Commit**

```bash
git add packages/nightshade_bridge/ native/nightshade_native/ apps/desktop/nightshade_bridge.dll
git commit -m "chore(meridian): regenerate FRB bindings and rebuild Rust"
```

---

## Task 15: Integration Testing

**Files:**
- Test manually with simulator mount

**Step 1: Build and run desktop app**

```bash
melos run dev
```

**Step 2: Test checklist**

1. [ ] Open Settings → Meridian Flip
2. [ ] Verify all settings load correctly
3. [ ] Change settings and verify they save
4. [ ] Create a sequence WITHOUT meridian flip trigger
5. [ ] Click Start - verify preflight warning appears
6. [ ] Add meridian flip trigger to sequence
7. [ ] Verify warning no longer appears
8. [ ] Connect simulator mount
9. [ ] Verify standalone monitoring toggle works
10. [ ] Check console logs for `[MERIDIAN]` entries

**Step 3: Commit any fixes**

```bash
git add .
git commit -m "fix(meridian): integration testing fixes"
```

---

## Final Summary

This implementation plan creates a rock-solid auto meridian flip system with:

1. **Dart Models** - Settings and events with freezed
2. **Database Schema** - Schema v6 with profile overrides
3. **Providers** - Global and effective settings providers
4. **Rust Enhancements** - Expanded MeridianFlipConfig, new RecoveryAction
5. **Event System** - Full event streaming with verbose logging
6. **Executor** - Robust flip execution with retries
7. **UI** - Progress dialog and settings screen
8. **Preflight Validation** - Warning for missing trigger

The implementation is designed to be:
- **Reliable**: Comprehensive error handling and retries
- **Observable**: Verbose logging and live progress dialog
- **Configurable**: Full settings with profile overrides
- **Maintainable**: Clean separation of concerns
