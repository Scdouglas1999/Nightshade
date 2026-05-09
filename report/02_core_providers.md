# 2. Core Providers & State Management Audit

## Scope
- `packages/nightshade_core/lib/src/providers/` -- All 36 Riverpod provider files
- State flow, reactivity, provider dependencies
- Error handling, disposal, mounted checks
- Bug identification with file:line citations

---

## Feature Inventory

### Provider File Catalog

| # | File | Provider Types | Rating |
|---|------|---------------|--------|
| 1 | `backend_provider.dart` | StateNotifierProvider, Provider | **Complete & Solid** |
| 2 | `database_provider.dart` | Provider, StreamProvider, FutureProvider (12+) | **Complete & Solid** |
| 3 | `event_provider.dart` | StreamProvider, StateNotifierProvider (3) | **Complete & Solid** |
| 4 | `equipment_provider.dart` | StateNotifierProvider (10 device types), Provider (3) | **Complete & Solid** |
| 5 | `imaging_provider.dart` | StateNotifierProvider (2), StateProvider (20+), Provider (5+) | **Functional but Needs Polish** |
| 6 | `sequence_provider.dart` | StateNotifierProvider (1), StateProvider (6+), Provider (3+) | **Complete & Solid** |
| 7 | `settings_provider.dart` | AsyncNotifierProvider (1), Provider (10+) | **Complete & Solid** |
| 8 | `profiles_provider.dart` | AsyncNotifierProvider, Provider (5+) | **Complete & Solid** |
| 9 | `guiding_provider.dart` | StateNotifierProvider (7), StateProvider (2) | **Complete & Solid** |
| 10 | `session_provider.dart` | StateNotifierProvider (1), Provider (2) | **Complete & Solid** |
| 11 | `capability_provider.dart` | FutureProvider.family (5), Provider (1) | **Complete & Solid** |
| 12 | `weather_providers.dart` | Provider (4), StateProvider (1) | **Complete & Solid** |
| 13 | `weather_safety_provider.dart` | StateNotifierProvider (1) | **Broken** |
| 14 | `target_suggestion_provider.dart` | Provider (1), FutureProvider (5+) | **Complete & Solid** |
| 15 | `science_provider.dart` | AsyncNotifierProvider (2), StreamProvider.family (10+) | **Complete & Solid** |
| 16 | `flat_wizard_provider.dart` | StateNotifierProvider (1) | **Complete & Solid** |
| 17 | `polar_alignment_provider.dart` | StateNotifierProvider (2), Provider (2) | **Complete & Solid** |
| 18 | `framing_provider.dart` | StateNotifierProvider (1), StateProvider (10+) | **Complete & Solid** |
| 19 | `filter_offset_provider.dart` | StateNotifierProvider (1) | **Complete & Solid** |
| 20 | `meridian_flip_provider.dart` | StateNotifierProvider (1), Provider (3), StateProvider (4), StreamProvider (1) | **Complete & Solid** |
| 21 | `template_snippet_provider.dart` | Provider (1), StateNotifierProvider (1), Provider (2) | **Complete & Solid** |
| 22 | `unified_discovery_provider.dart` | StateNotifierProvider (1), Provider (2+) | **Complete & Solid** |
| 23 | `ui_notification_provider.dart` | StateNotifierProvider (1) | **Complete & Solid** |
| 24 | `suggestion_filter_provider.dart` | StateNotifierProvider (1), Provider (1) | **Complete & Solid** |
| 25 | `operation_progress_provider.dart` | StateNotifierProvider (1) | **Complete & Solid** |
| 26 | `auto_stretch_provider.dart` | StateNotifierProvider (1), Provider (2+) | **Complete & Solid** |
| 27 | `tutorial_provider.dart` | AsyncNotifierProvider (1) | **Complete & Solid** |
| 28 | `current_screen_provider.dart` | StateProvider (1) | **Complete & Solid** |
| 29 | `transient_alert_provider.dart` | AsyncNotifierProvider (2), StateProvider (1), Provider (2) | **Complete & Solid** |
| 30 | `device_backend_selection_provider.dart` | StateNotifierProvider (1) | **Complete & Solid** |
| 31 | `camera_presets_provider.dart` | AsyncNotifierProvider (1) | **Complete & Solid** |
| 32 | `annotation_settings_provider.dart` | AsyncNotifierProvider (2) | **Complete & Solid** |
| 33 | `autofocus_progress_provider.dart` | StateNotifierProvider (1) | **Complete & Solid** |
| 34 | `exoplanet_provider.dart` | Plain class (not Riverpod) | **Half-Baked** |
| 35 | `gaia_provider.dart` | Plain class (not Riverpod) | **Half-Baked** |
| 36 | `simbad_provider.dart` | Plain class (not Riverpod) | **Half-Baked** |

### Summary Statistics
- **Complete & Solid:** 30 files (83%)
- **Functional but Needs Polish:** 1 file (3%)
- **Half-Baked:** 3 files (8%)
- **Broken:** 1 file (3%)
- **Stubbed/Placeholder:** 0
- **Missing:** 0 (see Missing Pieces section for feature gaps)

---

## Implementation Quality

### State Flow & Provider Dependency Chain

The provider architecture follows a clean layered dependency model:

```
Layer 0 (Foundation):
  backendProvider ──> DisconnectedBackend | FfiBackend | NetworkBackend
  databaseProvider ──> NightshadeDatabase (Drift SQLite, schema v14)

Layer 1 (Services):
  deviceServiceProvider ──> backendProvider
  imagingServiceProvider ──> backendProvider
  sessionServiceProvider ──> backendProvider, databaseProvider

Layer 2 (Device State):
  cameraStateProvider ──> backendProvider, deviceServiceProvider
  mountStateProvider ──> backendProvider, deviceServiceProvider
  focuserStateProvider ──> backendProvider, deviceServiceProvider
  filterWheelStateProvider ──> backendProvider, deviceServiceProvider
  guiderStateProvider ──> backendProvider, deviceServiceProvider
  rotatorStateProvider ──> backendProvider
  domeStateProvider ──> backendProvider
  weatherDeviceStateProvider ──> backendProvider
  safetyMonitorStateProvider ──> backendProvider
  coverCalibratorStateProvider ──> backendProvider

Layer 3 (Feature State):
  sequenceProvider ──> backendProvider, databaseProvider
  settingsProvider ──> databaseProvider
  profilesProvider ──> databaseProvider
  guidingProviders ──> backendProvider (event stream)
  sessionProvider ──> backendProvider, databaseProvider
  weatherSafetyProvider ──> weatherDeviceState, safetyMonitorState, settingsProvider

Layer 4 (Derived/UI):
  effectiveMeridianFlipSettingsProvider ──> globalSettings + activeProfile
  filteredSuggestionsProvider ──> tonightSuggestions + filterState
  autoStretchProvider ──> settingsProvider, backendProvider
  operationProgressProvider ──> standalone (event-driven)
```

**Assessment:** The dependency chain is well-structured with clear layering. No circular dependencies detected. Backend provider correctly serves as the single source of truth for hardware communication, with all device providers depending on it. Database provider correctly underpins all persistence.

### Provider Pattern Usage

| Pattern | Count | Usage |
|---------|-------|-------|
| StateNotifierProvider | 25+ | Device state, complex stateful logic |
| AsyncNotifierProvider | 7 | DB-backed settings with async initialization |
| StateProvider | 40+ | Simple UI state (toggles, selections, numeric values) |
| Provider | 25+ | Derived/computed values, service instances |
| StreamProvider | 15+ | Database watches, event streams |
| FutureProvider | 10+ | One-shot async data, suggestions |
| FutureProvider.family | 5 | Per-device capability queries |
| StreamProvider.family | 10+ | Science data by session ID |

**Assessment:** Provider type selection is appropriate throughout. StateNotifier used correctly for complex state machines (devices, sequencer). AsyncNotifier used correctly for DB-backed settings that need async init. StateProvider used for simple UI toggles. No misuse of provider types detected.

### Error Handling Assessment

**Strengths:**
- All device StateNotifiers (equipment_provider.dart) wrap connect/disconnect in try-catch and transition to error states with `DeviceError` messages
- Backend switching (backend_provider.dart) properly disposes old backend before creating new one
- Database loading failures in settings providers log errors and fall back to defaults rather than crashing
- Event stream listeners consistently check `mounted` before updating state
- Sequence provider validates node operations and throws `ArgumentError` for invalid states

**Weaknesses:**
- `imaging_provider.dart:93-94` and `imaging_provider.dart:109-111`: `AutoStretchSettingsNotifier._loadSettings()` and `_saveSettings()` silently swallow all exceptions with empty catch blocks. This violates the project's "errors are a feature" principle.
- `weather_safety_provider.dart:225-249`: Safety mode handling is broken (see Bugs section)
- TAP query classes (`exoplanet_provider.dart`, `gaia_provider.dart`, `simbad_provider.dart`) handle HTTP errors but are not integrated into Riverpod lifecycle

### Disposal & Mounted Check Audit

**Stream Subscription Disposal:**

| Provider | Has Subscription | Disposes in dispose() | Mounted Check |
|----------|-----------------|----------------------|---------------|
| equipment_provider.dart (all 10) | Yes | Yes | Yes |
| guiding_provider.dart (7 notifiers) | Yes | Yes | Yes |
| event_provider.dart (EventHistoryNotifier) | Yes | Yes | Yes |
| event_provider.dart (ErrorNotificationBridge) | Yes | Yes | Yes |
| autofocus_progress_provider.dart | Yes | Yes | Yes |
| polar_alignment_provider.dart | Yes | Yes | Yes |
| session_provider.dart | Yes | Yes | Yes |
| operation_progress_provider.dart | Yes | Yes | Yes |
| weather_safety_provider.dart | Yes (Timer) | Yes | Yes |

**Assessment:** All StateNotifier subclasses that subscribe to event streams properly cancel subscriptions in `dispose()` and check `mounted` before state updates. This is a consistent and well-enforced pattern across the entire codebase. No disposal leaks found.

### Undo/Redo System (sequence_provider.dart)

The `CurrentSequenceNotifier` implements a 50-level undo/redo stack:
- `_pushUndoState()` captures full sequence snapshots before mutations
- `undo()` moves current state to redo stack and pops from undo stack
- `redo()` moves current state to undo stack and pops from redo stack
- Undo stack has hard cap at 50 entries (oldest dropped)
- All mutation methods (`addNode`, `removeNode`, `moveNode`, `updateNodeProperty`, etc.) call `_pushUndoState()` before modifying state

**Assessment:** Complete & Solid. Full undo/redo with proper snapshot isolation.

### Auto-stretch Isolate Pattern (auto_stretch_provider.dart)

All five stretch algorithms (STF, histogram equalization, asinh, log, gamma) run in Dart isolates via `Isolate.run()` to avoid blocking the UI thread. The STF algorithm also has a Rust bridge fallback path. RGBA conversion for display is also isolate-based.

**Assessment:** Complete & Solid. Proper compute isolation for CPU-intensive image processing.

---

## Bugs Found

### BUG 1: Weather Safety Fail Modes All Behave Identically (CRITICAL)

**File:** `weather_safety_provider.dart:225-249`
**Severity:** Critical -- safety-critical logic is broken
**Rating:** Broken

The `_evaluateSafety()` method has three `SafetyFailMode` cases (`failOpen`, `failClosed`, `warnOnly`) that should have distinct behaviors, but all three produce identical results: marking the system as unsafe.

- `failOpen` should treat unknown/error conditions as SAFE (allow operations to continue)
- `failClosed` should treat unknown/error conditions as UNSAFE (current behavior for all cases)
- `warnOnly` should warn but not block operations

All three currently set `_isSafe = false` unconditionally when data sources are unavailable or in error. This means the `failOpen` setting (which users explicitly choose when they want to continue imaging despite sensor issues) has no effect.

**Impact:** Users who configure `failOpen` mode to allow imaging when weather sensors disconnect will still have their sessions interrupted, defeating the purpose of the setting.

### BUG 2: Silent Error Swallowing in AutoStretchSettingsNotifier (MODERATE)

**File:** `imaging_provider.dart:93-94` and `imaging_provider.dart:109-111`
**Severity:** Moderate -- violates project error philosophy

The `_loadSettings()` and `_saveSettings()` methods in `AutoStretchSettingsNotifier` catch all exceptions and silently discard them:

```dart
} catch (e) {
  // silently falls through
}
```

Per project CLAUDE.md: "Errors are a feature. Silent fallbacks hide bugs for months." These should at minimum log the error with `developer.log()` as other providers consistently do.

### BUG 3: TAP Query Classes Not Riverpod-Integrated (LOW)

**Files:** `exoplanet_provider.dart`, `gaia_provider.dart`, `simbad_provider.dart`
**Severity:** Low -- functional but architecturally inconsistent

These three files contain plain Dart classes (`ExoplanetArchiveService`, `GaiaDR3Service`, `SimbadService`) that perform HTTP TAP queries but are NOT wrapped in Riverpod providers. They are the only files in the `providers/` directory that don't participate in the Riverpod dependency graph.

**Impact:** These services are instantiated ad-hoc rather than through the provider system, meaning:
- No lifecycle management (no auto-disposal)
- No dependency injection for testing
- Inconsistent with every other file in the directory

---

## Positive Findings

### Consistent Mounted Checks
Every single `StateNotifier` subclass that subscribes to event streams checks `mounted` before updating state. This is a critical safety pattern that prevents `setState after dispose` errors, and it is enforced without exception across all 25+ StateNotifier implementations.

### Proper Backend Disposal Chain
`BackendNotifier.switchBackend()` correctly disposes the old backend before creating a new one, preventing resource leaks when switching between local/remote/disconnected modes.

### Clean DAO Layer
`database_provider.dart` cleanly separates database concerns into 7 typed DAOs (targets, sessions, images, metadata, sequences, settings, science) and provides StreamProvider wrappers that automatically rebuild when underlying data changes.

### Effective Profile Override Merging
`meridian_flip_provider.dart:164-188` implements a clean JSON-merge strategy for combining global settings with per-profile overrides, with proper error handling and fallback to global defaults.

### Rolling Statistics
`guiding_provider.dart` implements proper rolling RMS calculators for guiding statistics with configurable window sizes, maintaining running sums for efficient O(1) updates rather than recalculating over the full window.

### Flat Wizard Filter Ordering
`flat_wizard_provider.dart` automatically orders filters by restrictiveness (narrowband first) for twilight flat capture, which is a real-world astrophotography best practice.

---

## Missing Pieces

### No Provider for Plate Solve State
While `PlateSolveService` exists in the services layer, there is no dedicated provider tracking plate solve state (running, result, history). Plate solving state appears to be managed ad-hoc in UI widgets.

### No Provider for Scheduler State
`SchedulerService` exists but has no dedicated state provider. Multi-target scheduling state management appears incomplete from the provider perspective.

### No Provider for Backup/AutoSave State
`BackupService` and `AutoSaveService` are referenced in the architecture but have no corresponding state providers for tracking backup progress or auto-save status.

### No Connection Health Monitoring Provider
There is no provider that monitors the health of the backend connection (e.g., heartbeat, latency, reconnection state). The backend provider tracks connection mode but not connection quality.

---

## Recommendations

### Priority 1: Fix Weather Safety Fail Modes (Critical)
`weather_safety_provider.dart:225-249` must differentiate behavior for `failOpen`, `failClosed`, and `warnOnly` modes. This is safety-critical -- users rely on fail mode configuration to control session behavior during sensor failures. Suggested fix:
- `failOpen`: Set `_isSafe = true` when data sources are unavailable
- `failClosed`: Set `_isSafe = false` when data sources are unavailable (current behavior)
- `warnOnly`: Set `_isSafe = true` but emit a warning notification

### Priority 2: Add Error Logging to AutoStretchSettingsNotifier
`imaging_provider.dart:93-94` and `109-111`: Replace empty catch blocks with `developer.log()` calls following the pattern used in every other settings provider (e.g., `meridian_flip_provider.dart:44`, `annotation_settings_provider.dart`).

### Priority 3: Wrap TAP Query Services in Riverpod Providers
Create proper Provider wrappers for `ExoplanetArchiveService`, `GaiaDR3Service`, and `SimbadService` to bring them into the Riverpod lifecycle, enable dependency injection for testing, and maintain architectural consistency.

### Priority 4: Consider Provider File Splitting
Three files are very large: `equipment_provider.dart` (54KB), `settings_provider.dart` (62KB), `framing_provider.dart` (64KB). Consider splitting:
- `equipment_provider.dart` into per-device-type files (camera_provider.dart, mount_provider.dart, etc.)
- `settings_provider.dart` into settings category files
- `framing_provider.dart` into framing model + framing controller

### Priority 5: Add Missing State Providers
Create providers for plate solve state, scheduler state, and backup/auto-save state to complete the provider coverage and maintain the pattern of all stateful operations being tracked through Riverpod.

---

## Overall Assessment

The core provider layer is **strong and well-architected**. 30 of 36 files (83%) are rated Complete & Solid. The codebase demonstrates consistent patterns: proper disposal, mounted checks, clean dependency layering, and appropriate provider type selection. The one critical bug (weather safety fail modes) must be fixed as it affects safety-critical logic. The moderate and low issues are straightforward to address. The provider architecture is production-ready with these targeted fixes.
