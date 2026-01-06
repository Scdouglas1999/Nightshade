# Auto Meridian Flip System Design

**Date:** 2026-01-06
**Status:** Approved
**Priority:** Critical (essential for unattended imaging sessions)

## Overview

Implement a robust auto meridian flip system that prevents mount tracking limits from being reached during imaging sessions. The system operates in two modes: sequencer-integrated triggers and standalone monitoring for manual imaging.

## Requirements

### Functional Requirements

1. **Two Operating Modes:**
   - **Sequencer Mode:** Explicit MeridianFlipTrigger node placed in sequences
   - **Standalone Mode:** Background monitoring during manual imaging (disabled when sequence running)
   - Default: Sequencer-only (standalone OFF by default)

2. **Trigger Methods** (user selects preferred):
   - Minutes past meridian (default: 5 minutes)
   - Minutes before mount limit (default: 10 minutes, if mount reports limits)
   - Hour angle threshold (default: 0.5 hours)

3. **Flip Sequence Steps** (configurable):
   - Pause guiding before flip (default: ON)
   - Re-center after flip via plate solve (default: ON)
   - Refocus after flip (default: OFF)
   - Settle time wait (default: 10 seconds)
   - Resume guiding after flip (default: ON)

4. **Error Handling:**
   - Retry with increasing delays: 30s, 60s, 120s (3 retries max)
   - On permanent failure: Pause sequence and alert user
   - Both configurable

5. **Notifications:**
   - In-app: Always ON
   - Sound alerts: Configurable, OFF by default
   - Push notifications: ON if mobile connected
   - Logging: Verbose by default

6. **Settings Storage:**
   - Global defaults in `app_settings`
   - Per-profile overrides in `equipment_profiles`
   - Profile inherits global unless explicitly overridden

7. **Preflight Validation:**
   - Warn if sequence lacks MeridianFlipTrigger (non-blocking warning)

8. **Live Progress Dialog:**
   - Modal popup showing real-time flip progress
   - Step-by-step status with timing
   - Abort button for emergency stop

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    AUTO MERIDIAN FLIP SYSTEM                     │
├─────────────────────────────┬───────────────────────────────────┤
│   SEQUENCER MODE            │   STANDALONE MONITORING MODE      │
│   (Explicit Trigger)        │   (Manual Imaging Protection)     │
├─────────────────────────────┼───────────────────────────────────┤
│ • MeridianFlipTrigger node  │ • MeridianMonitorService          │
│   placed in sequence tree   │   (Dart, runs in background)      │
│ • Executes via Rust         │ • Active only when:               │
│   sequencer engine          │   - No sequence running           │
│ • Coordinates with other    │   - Mount connected               │
│   sequence nodes            │   - Target coords known           │
│ • Preflight warns if        │   - Mode enabled in settings      │
│   trigger missing           │ • Calls same flip logic           │
└─────────────────────────────┴───────────────────────────────────┘
```

### Shared Components

- **MeridianFlipSettings** - Configuration model (Dart + Rust)
- **MeridianFlipExecutor** - Core flip logic (Rust, 10-step sequence)
- **MeridianCalculator** - Hour angle, crossing time calculations (Rust, exists)
- **MeridianFlipEvent** - Progress events streamed to Dart

## Data Models

### MeridianFlipSettings (Dart)

```dart
@freezed
class MeridianFlipSettings with _$MeridianFlipSettings {
  const factory MeridianFlipSettings({
    // Mode control
    @Default(false) bool standaloneMonitoringEnabled,

    // Trigger conditions
    @Default(MeridianTriggerMethod.minutesPastMeridian) MeridianTriggerMethod triggerMethod,
    @Default(5.0) double minutesPastMeridian,
    @Default(10.0) double minutesBeforeLimit,
    @Default(0.5) double hourAngleThreshold,

    // Flip sequence options
    @Default(true) bool pauseGuidingBeforeFlip,
    @Default(true) bool recenterAfterFlip,
    @Default(false) bool refocusAfterFlip,
    @Default(10.0) double settleTimeSeconds,
    @Default(true) bool resumeGuidingAfterFlip,

    // Error handling
    @Default(3) int maxRetries,
    @Default([30.0, 60.0, 120.0]) List<double> retryDelaysSeconds,
    @Default(FlipFailureAction.pauseAndAlert) FlipFailureAction failureAction,

    // Notifications
    @Default(false) bool soundAlertOnFlip,
    @Default(true) bool pushNotificationOnFlip,
  }) = _MeridianFlipSettings;
}

enum MeridianTriggerMethod {
  minutesPastMeridian,
  minutesBeforeLimit,
  hourAngleThreshold,
}

enum FlipFailureAction {
  pauseAndAlert,
  abortAndPark,
}
```

### MeridianFlipTriggerConfig (Rust)

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeridianFlipTriggerConfig {
    pub trigger_method: MeridianTriggerMethod,
    pub minutes_past_meridian: f64,
    pub minutes_before_limit: f64,
    pub hour_angle_threshold: f64,

    pub pause_guiding: bool,
    pub recenter_after: bool,
    pub refocus_after: bool,
    pub settle_time_secs: f64,

    pub max_retries: u32,
    pub retry_delays_secs: Vec<f64>,
    pub failure_action: FlipFailureAction,
}
```

### MeridianFlipEvent (Rust → Dart)

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MeridianFlipEvent {
    Starting {
        target_name: String,
        from_pier_side: PierSide,
        hour_angle: f64,
    },
    StepStarted {
        step: FlipStep,
        step_index: u8,
        total_steps: u8,
    },
    StepCompleted {
        step: FlipStep,
    },
    StepFailed {
        step: FlipStep,
        error: String,
    },
    Progress {
        percent: u8,
    },
    RetryScheduled {
        attempt: u8,
        delay_secs: f64,
    },
    Completed {
        new_pier_side: PierSide,
        duration_secs: f64,
    },
    Failed {
        error: String,
        action_taken: FlipFailureAction,
    },
    Aborted {
        reason: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
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
```

## UI Components

### Meridian Flip Progress Dialog

Modal dialog showing real-time flip progress:

```
┌─────────────────────────────────────────────────────────────┐
│  ◐  Meridian Flip in Progress                          [X] │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Target: NGC 7000 (North America Nebula)                    │
│  ─────────────────────────────────────────────────────────  │
│                                                             │
│  ✓ Pausing guider                              [completed]  │
│  ✓ Stopping tracking                           [completed]  │
│  ● Slewing to target (flip side)...           [in progress] │
│    ├─ From: West side, HA: +0:32                            │
│    └─ To:   East side                                       │
│  ○ Verifying pier side                            [pending] │
│  ○ Resuming tracking                              [pending] │
│  ○ Plate solving and centering                    [pending] │
│  ○ Resuming guider                                [pending] │
│  ○ Waiting for settle (10s)                       [pending] │
│                                                             │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  45%     │
│                                                             │
│  Elapsed: 0:42  │  Step 3 of 8                              │
│                                                             │
│                                    [ Abort Flip ]           │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:**
- Modal, cannot be dismissed (only aborted)
- Real-time step updates via event stream
- Shows pier side transition and hour angle
- Abort triggers safe cleanup
- Auto-dismisses on success after 2 seconds
- Stays open on failure showing error and options

### Settings Screen

Located at Settings → Meridian Flip:
- Toggle cards for each option with descriptions
- Trigger method selector with numeric inputs
- "Test Flip Now" button (when safe)
- Preview: "Next flip in: 2h 34m" based on current target

### Preflight Warning

Add to existing preflight validation dialog:
- Yellow warning icon
- Message: "No meridian flip trigger in sequence"
- Detail: "Auto meridian flip will not occur during this sequence"
- Non-blocking (user can proceed)

## Logging Strategy

Verbose logging by default with `[MERIDIAN]` prefix:

```
[MERIDIAN] ══════════════════════════════════════════════════════════
[MERIDIAN] FLIP TRIGGER ACTIVATED
[MERIDIAN]   Target: NGC 7000
[MERIDIAN]   Current RA: 20h 59m 17s, Dec: +44° 31' 44"
[MERIDIAN]   Hour Angle: +0.52h (31.2 minutes past meridian)
[MERIDIAN]   Trigger Method: minutes_past_meridian (threshold: 5.0 min)
[MERIDIAN]   Current Pier Side: WEST
[MERIDIAN]   Expected After Flip: EAST
[MERIDIAN]   Observer: 40.7128°N, -74.0060°W
[MERIDIAN] ──────────────────────────────────────────────────────────
[MERIDIAN] Step 1/8: Pausing guider...
[MERIDIAN]   Guider state before: GUIDING (RMS: 0.8")
[MERIDIAN]   Sent pause command to PHD2
[MERIDIAN]   ✓ Guider paused successfully (took 1.2s)
...
[MERIDIAN] ══════════════════════════════════════════════════════════
[MERIDIAN] FLIP COMPLETED SUCCESSFULLY
[MERIDIAN]   Total duration: 98.4 seconds
[MERIDIAN]   New pier side: EAST
[MERIDIAN]   Resuming sequence...
[MERIDIAN] ══════════════════════════════════════════════════════════
```

**Log Destinations:**
- Console (real-time)
- Session log file (`logs/session_YYYY-MM-DD.log`)
- Dedicated flip log (`logs/meridian_flips.log`)

## Standalone Monitoring Service

```dart
class MeridianMonitorService {
  // Activation conditions (all must be true):
  // 1. standaloneMonitoringEnabled in settings
  // 2. Mount connected with valid coordinates
  // 3. Target coordinates known
  // 4. No sequence currently running

  void startMonitoring() {
    _checkTimer = Timer.periodic(Duration(seconds: 30), (_) => _checkMeridian());
  }

  Future<void> _checkMeridian() async {
    if (sequenceProvider.isRunning) {
      _pauseMonitoring();
      return;
    }

    final shouldFlip = await _backend.checkMeridianFlipNeeded(...);
    if (shouldFlip) {
      await _executeFlipWithDialog();
    }
  }
}
```

**Lifecycle:**
- Starts: App launch + mount connects + standalone enabled
- Pauses: Sequence starts
- Resumes: Sequence completes/stops
- Stops: Mount disconnects OR mode disabled

## Files to Create/Modify

| Layer | File | Changes |
|-------|------|---------|
| Database | `database.dart` | Add `meridian_flip_settings` to `app_settings`, `meridian_flip_overrides` to `equipment_profiles` |
| Models | `meridian_flip_settings.dart` (new) | Settings model with freezed |
| Rust | `sequencer/src/triggers/meridian_flip.rs` (new) | Trigger implementation |
| Rust | `sequencer/src/instructions.rs` | Enhance MeridianFlipConfig |
| Rust | `sequencer/src/events.rs` | Add MeridianFlipEvent variants |
| Rust | `bridge/src/api.rs` | Expose flip events to Dart |
| Service | `meridian_monitor_service.dart` (new) | Standalone monitoring |
| Providers | `meridian_flip_provider.dart` (new) | Settings + state providers |
| UI | `meridian_flip_progress_dialog.dart` (new) | Live progress popup |
| UI | `meridian_flip_settings_screen.dart` (new) | Settings page |
| UI | `preflight_validation_dialog.dart` | Add missing trigger warning |
| Sequencer | Trigger system | Verify/fix trigger execution |

## Testing Strategy

1. **Unit Tests:**
   - Hour angle calculations (verify existing)
   - Trigger activation logic
   - Settings serialization/deserialization

2. **Integration Tests:**
   - Simulated mount flip sequence
   - Event streaming to Dart
   - Retry logic

3. **Manual Testing:**
   - Real mount when available
   - "Dry run" mode (logs without moving mount)

4. **Edge Cases:**
   - Target near celestial pole (no flip needed)
   - Mount already on correct pier side
   - Flip during autofocus
   - Network disconnect during flip
   - User abort mid-flip

## Success Criteria

1. Flip executes reliably when threshold reached
2. All steps complete in correct order
3. Recovery works on transient failures
4. User sees real-time progress
5. Logs provide complete diagnostic information
6. Settings persist correctly
7. No data loss on flip failure (sequence can resume)
