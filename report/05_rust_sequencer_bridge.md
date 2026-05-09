# 5. Rust Sequencer & Bridge Audit

**Rating: 8/10 - Strong**

The sequencer is a well-architected behavior tree engine with comprehensive hardware abstraction, robust checkpoint/recovery, and solid FFI boundary safety. A handful of panic-risk patterns and one operator-precedence bug prevent a higher rating.

## Scope
- `native/nightshade_native/sequencer/src/` - Behavior tree engine (~8,500 lines across 10 files)
- `native/nightshade_native/bridge/src/` - FFI entry point, event system, device ops (~9,000+ lines)

---

## Feature Inventory

### Sequencer Engine (`sequencer/src/`)

#### Core Architecture (`lib.rs`, `executor.rs`, `node.rs`)
- **Node types**: `NodeType` enum with 25+ variants spanning instruction, trigger, and logic nodes
- **Execution model**: `SequenceExecutor` loads a `SequenceDefinition`, builds a recursive node tree from `NodeDefinition` map, then spawns a tokio task for execution
- **Node trait**: `execute()`, `reset()`, `abort()`, `children()`, `mark_completed()` -- implemented by `RuntimeNode` which pattern-matches all `NodeType` variants
- **ExecutionContext**: Carries device IDs, target info, cancellation/pause AtomicBools, `device_ops` Arc, trigger state
- **Progress tracking**: Real-time progress callback with node tracking, exposure counting, integration time, ETA calculation via `StdRwLock<SequenceProgress>`
- **Cycle detection**: `calculate_totals()` uses `recursion_guard: HashSet` to prevent infinite recursion in nested loop nodes

#### Instruction Nodes (`instructions.rs`, `autofocus_instructions.rs`) - ~3,000 lines
25+ instruction types fully implemented (no stubs):

| Instruction | Key Details |
|---|---|
| `Slew` | Park check, coordinate validation, cancellation via tokio::select |
| `Center` | Plate solve + sync + slew loop with configurable max_attempts |
| `Expose` | Filter change (index preferred over name), HFR calculation, FITS saving, dithering |
| `Autofocus` | Star crop extraction, V-curve fitting, R-squared quality threshold |
| `AutofocusComplete` | Second implementation using VCurveAutofocus engine with backlash compensation |
| `Dither` | Delegates to guider API |
| `Guide Start/Stop` | PHD2/guider control |
| `Filter Change` | By index or name |
| `Cool/Warm Camera` | Temperature ramp with progress monitoring |
| `Rotator` | Move to position angle |
| `Park/Unpark` | Mount park/unpark |
| `Dome` | Dome operations |
| `Cover Calibrator` | Open/close cover |
| `Flat Wizard` | Automated flat frame acquisition with ADU targeting |
| `Meridian Flip` | Multi-step executor with configurable step sequence |
| `Polar Alignment` | Delegates to polar alignment routine |
| `Mosaic` | Multi-panel mosaic execution |
| `Notification` | User notifications |
| `Script` | External script execution |
| `Delay/Wait` | Time-based and condition-based waits |

Wait helpers: `wait_for_mount_idle`, `wait_for_focuser_idle`, `wait_for_filterwheel_idle`, `wait_for_focuser_stop_after_halt` -- all use polling with cancellation checks.

#### Trigger System (`triggers.rs`) - ~700 lines
12+ trigger types with per-trigger cooldown and consecutive-frame counting:

| Trigger | Details |
|---|---|
| HFR Degraded | Baseline tracking with configurable threshold multiplier |
| Meridian Flip | 4 methods: MinutesPastMeridian, MinutesBeforeLimit, HourAngleThreshold, OnTrackingLimitHit |
| Guiding Failed | RMS threshold monitoring |
| Altitude Limit | Target altitude check with astronomical calculations |
| Weather Unsafe | Safety device polling |
| Temperature Shift | Ambient temperature drift monitoring |
| Filter Change | Filter-specific focus offset tracking |
| Dawn Approaching | Twilight calculation with polar day/night handling |
| Autofocus Interval | Time-based periodic autofocus |
| Dither Interval | Frame-count-based dithering |
| Mount Tracking Lost | Tracking state monitoring |
| Dome Shutter | Dome status checks |

`TriggerState` carries ~40 fields of runtime state for all triggers. The trigger monitor in the executor polls every 1 second.

#### Astronomical Calculations (`node.rs`)
- `julian_day()`, `local_sidereal_time()`, `calculate_altitude()` for real-time target tracking
- `is_dark()` for twilight detection
- `calculate_moon_separation()` for moon avoidance

#### Checkpoint/Recovery System (`checkpoint.rs`)
- `SessionCheckpoint` with version, full sequence definition, node statuses, device IDs, progress snapshot
- Atomic file writes: write to temp file, then rename (prevents corruption on crash)
- Backup file maintained on each save for self-healing
- Corrupt primary checkpoint falls back to backup automatically
- Unit tests verify serialization round-trip and corruption recovery

#### Meridian Flip Executor (`meridian_flip_executor.rs`)
- Multi-step configurable sequence: PausingGuider -> StoppingTracking -> SlewingToTarget -> VerifyingPierSide -> ResumingTracking -> PlateSolvingAndCentering -> Refocusing -> ResumingGuider
- Retry with configurable delays and abort handle
- Steps can be individually enabled/disabled

#### Flat Wizard (`flat_wizard.rs`)
- Automated flat frame acquisition targeting specific ADU values
- Exposure time binary search to hit target ADU range
- Cover calibrator integration

#### Device Abstraction (`device_ops.rs`)
- `DeviceOps` trait defines all hardware operations (mount, camera, focuser, filter wheel, rotator, guider, plate solve, FITS save, notifications, dome, safety, image analysis, cover calibrator)
- `NullDeviceOps` test implementation with simulated delays for offline testing
- Clean abstraction allows sequencer to be tested without real hardware

### Bridge / FFI Layer (`bridge/src/`)

#### Runtime & Safety (`lib.rs`)
- **Tokio runtime**: `ensure_runtime()` with 3 fallback levels (multi-threaded -> single-threaded with reduced features -> minimal single-threaded)
- **Panic safety**: `catch_panic_sync()` and `catch_panic_async()` wrap all FFI boundary calls, converting panics to `NightshadeError::InternalError`
- **`run_async_safe()`**: Combines runtime acquisition + panic catching in a single helper
- **Logging**: `init_native_with_logging()` with file + console logging, log rotation, idempotent panic handler installation

#### Event System (`event.rs`)
- `EventBus` with tokio broadcast channel (4096 buffer), monotonic sequence numbers
- `NightshadeEvent` with event_id, timestamp, severity, category, payload, caused_by, correlation_id, device_id
- Event categories: Equipment (20+ variants), Imaging (12+ variants), Guiding (15+ variants), Sequencer (12+ variants), Safety, System
- `EventContext` for causality tracking with `generate_correlation_id()`
- Publish/subscribe model; Dart subscribes via `NativeBridge.eventStream()`

#### Error System (`error.rs`)
- `NightshadeError` with 25+ variants covering device, timeout, validation, operation, imaging, I/O, sequence, driver-specific (ASCOM, Alpaca, INDI, Native), system errors
- Classification methods: `is_recoverable()`, `is_timeout()`, `needs_reconnect()`, `is_hardware_error()`, `is_not_supported()`, `is_invalid_input()`, `is_cancellation()`
- `ErrorInfo` struct for safe FFI serialization
- `From` implementations for standard error types (io::Error, serde_json::Error, etc.)

#### Sequencer FFI API (`sequencer_api.rs`)
- Full lifecycle: `sequencer_load_plan`, `sequencer_start`, `sequencer_stop`, `sequencer_pause`, `sequencer_resume`, `sequencer_get_status`
- `sequencer_set_simulation_mode` with `#[cfg(debug_assertions)]` guard
- `sequencer_set_safety_fail_mode` coerces FailOpen/WarnOnly to FailClosed in production (defense-in-depth)
- Checkpoint API: set_checkpoint_dir, has_recoverable_checkpoint, get_checkpoint_info, resume_from_checkpoint, save_checkpoint, clear_checkpoint
- Trigger API: set_trigger_enabled, set_all_triggers_enabled, get_triggers, update_guiding_rms, update_hfr, reset_hfr_baseline

#### Bridge Device Ops (`sequencer_ops.rs`)
- `BridgeDeviceOps` implements `DeviceOps` routing to real hardware APIs
- Event emission for mount/camera/focuser/filter/rotator operations
- Plate solving via temp FITS file + nightshade_imaging solver
- Safety check with profile-based device resolution
- Image validation (size mismatch, uniform pixel detection)

#### State Management (`state.rs`)
- `AppState` with event_bus, devices, session, profile, observer_location
- Global storage singletons for profiles and settings

---

## Implementation Quality

### Strengths

1. **No stubs or placeholders**: All 25+ instruction types are fully implemented with real hardware interactions. No TODO markers found in critical paths.

2. **Comprehensive error handling at FFI boundary**: Every public FFI function is wrapped in `catch_panic_sync`/`catch_panic_async`, converting panics to structured errors. This prevents undefined behavior from crossing the Dart-Rust boundary.

3. **Defense-in-depth safety enforcement**: `SafetyFailMode` is enforced at the bridge layer -- `FailOpen` and `WarnOnly` are coerced to `FailClosed` in production, with simulation mode gated behind `#[cfg(debug_assertions)]`.

4. **Atomic checkpoint writes**: Checkpoint saves write to a temp file then rename, preventing corruption if the process crashes mid-write. Backup files provide self-healing when the primary checkpoint is corrupt.

5. **Clean hardware abstraction**: The `DeviceOps` trait cleanly separates sequencer logic from hardware details, enabling offline testing via `NullDeviceOps`.

6. **Robust event system**: Monotonic sequence numbers, correlation IDs, and causality tracking enable reliable event ordering and debugging.

7. **Cancellation support**: Most long-running operations use `tokio::select!` with cancellation checks, allowing responsive abort.

8. **Cycle detection**: Loop node traversal uses a `recursion_guard` HashSet to prevent infinite recursion during total calculation.

### Concerns

1. **`StdRwLock::write().unwrap()` pattern** (executor.rs, multiple locations): Progress state uses `std::sync::RwLock` (required for sync callback closures). If any write panics, the lock poisons and every subsequent `.unwrap()` cascades into panics. While unlikely in normal operation, a single poison event would make the entire progress system unusable until restart.

2. **Mutex lock unwraps in adaptive_polling.rs** (bridge/src/adaptive_polling.rs): Multiple `Mutex::lock().unwrap()` calls that would panic on poison.

3. **Mixed sync/async locking**: The executor uses `StdRwLock` for progress (needed in sync closures) and tokio locks for async state. This is architecturally necessary but requires careful attention to avoid holding sync locks across await points.

---

## Bugs Found

### BUG-01: Operator Precedence Error in Altitude Calculation (HIGH)
**File**: `native/nightshade_native/bridge/src/sequencer_ops.rs` (in `BridgeDeviceOps::calculate_altitude()`)
```rust
let ha_rad = ha * 15.0_f64.to_radians();
```
**Problem**: Due to Rust method call precedence, `.to_radians()` binds to the literal `15.0_f64` first, computing `ha * 0.26179...` instead of the intended `(ha * 15.0).to_radians()`. This produces incorrect altitude values, potentially affecting altitude limit triggers and target visibility calculations used by the sequencer.
**Fix**: `let ha_rad = (ha * 15.0_f64).to_radians();`

### BUG-02: Unchecked Index Access on Switch Vector (HIGH)
**File**: `native/nightshade_native/bridge/src/devices.rs:7609`
```rust
switches.into_iter().nth(idx).unwrap()
```
**Problem**: If the index `idx` exceeds the number of switches returned after filtering, this `.unwrap()` on `None` will panic, crashing the FFI boundary. While `catch_panic` wrappers would convert this to an error, it indicates a logic path where the index is assumed valid without verification.
**Fix**: Replace with `.nth(idx).ok_or_else(|| NightshadeError::InvalidInput(...))?`

### BUG-03: Duplicate Autofocus Implementations (MEDIUM)
**Files**: `sequencer/src/instructions.rs` (`execute_autofocus`) and `sequencer/src/autofocus_instructions.rs` (`execute_autofocus_complete`)
**Problem**: Two separate autofocus implementations exist with different algorithms (simple V-curve in instructions.rs vs. VCurveAutofocus engine with backlash compensation in autofocus_instructions.rs). The `NodeType::Autofocus` dispatches to the simple version. It is unclear when `execute_autofocus_complete` is invoked, creating risk of the more sophisticated implementation being dead code or invoked inconsistently.
**Impact**: Users may get the simpler, less accurate autofocus algorithm when they expect the full implementation.

### BUG-04: No Cancellation During Exposure Capture (MEDIUM)
**File**: `sequencer/src/instructions.rs` (in `execute_exposure()`)
**Problem**: The `camera_start_exposure` call is awaited directly without `tokio::select!` against the cancellation flag. If a user requests abort during a long exposure (e.g., 600s), the sequencer blocks until the exposure completes before checking cancellation. Other instructions (like slew) properly use `tokio::select!` for responsive cancellation.
**Fix**: Wrap the exposure await in `tokio::select!` with a cancellation branch, calling `camera_abort_exposure` on cancel.

### BUG-05: Unwrap After is_none() Check (LOW)
**File**: `sequencer/src/flat_wizard.rs:182`
```rust
if cc_id.is_none() { ... }
// later:
cc_id.unwrap()
```
**Problem**: While logically safe (the `is_none()` branch returns early), this is a fragile pattern. If the early return is ever removed or the control flow changes, the unwrap becomes a panic. Should use `if let Some(device_id) = cc_id` instead.

---

## Missing Pieces

1. **No integration tests for the sequencer**: The checkpoint module has unit tests, but there are no integration tests that exercise a full sequence execution (even with `NullDeviceOps`). A basic smoke test running a simple sequence (slew -> expose -> done) through the executor would catch regressions.

2. **No timeout on trigger monitor polling**: The 1-second trigger poll loop runs indefinitely. If a device call inside a trigger check hangs, the entire trigger monitoring system blocks. Adding a per-check timeout would improve robustness.

3. **No metrics/telemetry on sequencer performance**: No timing data is collected on instruction execution duration, trigger check latency, or checkpoint save/load times. This data would help diagnose performance issues in the field.

4. **Event buffer overflow handling**: The EventBus uses a 4096-element broadcast buffer. If a slow subscriber falls behind, messages are silently dropped (tokio broadcast semantics). There is no logging or metric when this happens, making it invisible.

---

## Recommendations

### Critical (Fix Before Release)
1. **Fix altitude calculation operator precedence** (BUG-01) - One-line fix with significant correctness impact on altitude triggers
2. **Guard the switch index access** (BUG-02) - Replace `.unwrap()` with proper error propagation

### High Priority
3. **Add cancellation to exposure capture** (BUG-04) - Long exposures currently cannot be interrupted
4. **Audit and consolidate autofocus implementations** (BUG-03) - Clarify which is the canonical path and ensure the better algorithm is used
5. **Replace `StdRwLock::write().unwrap()` with `.unwrap_or_else(|e| e.into_inner())`** or use `parking_lot::RwLock` (non-poisoning) for the progress state to prevent cascading panics

### Medium Priority
6. **Add integration test for executor** - Exercise a minimal sequence through `NullDeviceOps` to catch regressions
7. **Add timeout to trigger check calls** - Prevent a single hung device from blocking all trigger monitoring
8. **Log EventBus lag/overflow** - Detect slow subscriber issues in production

### Low Priority
9. **Refactor flat_wizard unwrap pattern** (BUG-05) - Use `if let Some()` for safety
10. **Add sequencer performance metrics** - Track instruction duration and checkpoint timing
