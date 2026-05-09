# Nightshade 2.0 Comprehensive Audit Report

**Generated:** March 13, 2026
**Version Audited:** 2.5.0
**Scope:** Full codebase — UI, business logic, Rust native, database, sequencer, imaging pipeline, supporting systems, test coverage, competitive landscape

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Critical Bugs](#2-critical-bugs)
3. [High-Severity Issues](#3-high-severity-issues)
4. [Medium-Severity Issues](#4-medium-severity-issues)
5. [UI/UX Issues by Screen](#5-uiux-issues-by-screen)
6. [Database & Schema Issues](#6-database--schema-issues)
7. [Test Coverage Gaps](#7-test-coverage-gaps)
8. [Supporting Systems (WebRTC, Plugins, Updater, Planetarium)](#8-supporting-systems)
9. [Feature Additions](#9-feature-additions)
10. [Competitive Landscape & Halo Features](#10-competitive-landscape--halo-features)
11. [Prioritized Action Plan](#11-prioritized-action-plan)

---

## 1. Executive Summary

Nightshade 2.0 is architecturally ambitious and well-structured. The behavior tree sequencer, cross-platform support (including mobile), and Rust performance layer give it genuine competitive advantages over N.I.N.A., SGPro, and Voyager. However, the audit uncovered **~65 bugs** (12 critical, 18 high, 35 medium), significant **test coverage gaps** (only 12 of 30+ services tested, 2 of 39 providers tested, zero widget/screen tests), and several **safety-critical issues** in the sequencer and device control layers that could cause equipment damage or data loss.

The biggest strategic opportunity is Nightshade's **cross-platform mobile + desktop story** — no competitor offers a native mobile companion with P2P WebRTC remote control. The biggest risks are in the **FFI boundary** (multiple panic points that will crash the app) and **sequencer safety** (park-on-error doesn't verify success).

---

## 2. Critical Bugs

### BUG-001: Panicking Unwraps in FFI Boundary
**Files:** `bridge/src/api.rs:4693,4705,9854-9860`, `bridge/src/unified_device_ops.rs:1676`, `bridge/src/ascom_wrapper_mount.rs:882-905`
**Severity:** CRITICAL — App crash

The FFI boundary between Dart and Rust must NEVER panic. Multiple `.unwrap()` and `panic!()` calls exist in production code paths:
- `api.rs:9854-9860` — FITS header calibration file paths panic if None (`dark_path.as_ref().unwrap()`)
- `unified_device_ops.rs:1676` — Explicit `panic!("Expected exposure to complete...")` in production code
- `ascom_wrapper_mount.rs:882-905` — Multiple `.expect()` calls on mutex locks

**Impact:** Any of these trigger an unrecoverable crash of the entire application.

---

### BUG-002: Unsafe Pointer Cast Without Validation
**File:** `bridge/src/api.rs:3574-3576`
**Severity:** CRITICAL — Memory safety violation

```rust
let u16_data = unsafe {
    std::slice::from_raw_parts(image.data.as_ptr() as *const u16, image.data.len() / 2)
};
```

- No check that `image.data.len() % 2 == 0` (odd byte count = invalid memory access)
- No alignment check (u8 buffer may not be u16-aligned)
- Used in color Bayer pattern debayering — corrupted RGB images possible

**Impact:** Undefined behavior, segfaults, or silently corrupted images.

---

### BUG-003: Array Index Out-of-Bounds in Median Calculation
**File:** `bridge/src/api.rs:3596`, `bridge/src/unified_device_ops.rs`
**Severity:** CRITICAL — Panic on empty data

```rust
let median = sorted[sorted.len() / 2]; // Panics if sorted is empty
```

If image data produces an empty pixel vector, this panics during live preview stretch calculation.

---

### BUG-004: Park-on-Error Doesn't Verify Success
**File:** `sequencer/src/executor.rs:1195-1210`
**Severity:** CRITICAL — Equipment damage risk

When `RecoveryAction::ParkAndAbort` fires, the mount park command is issued but:
- No verification that parking actually completed
- No retry logic if park fails
- No fallback to safe position
- Dome/cover calibrator aren't closed on error

**Impact:** Mount remains pointed at arbitrary position with tracking off. Equipment exposed to elements.

---

### BUG-005: Race Condition in Weather Safety Fail-Mode Detection
**File:** `providers/weather_safety_provider.dart:202-206`
**Severity:** CRITICAL — Safety bypass

```dart
if (!isWeatherDeviceConnected && !isSafetyMonitorConnected && currentAlert == null) {
  useFailMode = true;
```

If a weather device IS connected but returning no data, or if alert service is in `AsyncValue.loading` state, the system does NOT enter fail-mode. Imaging continues with no safety monitoring.

**Impact:** Telescope continues operating in unsafe weather conditions.

---

### BUG-006: Plugin Storage Not Persistent
**File:** `nightshade_plugins/lib/src/plugin_context.dart:40-101`
**Severity:** CRITICAL — Data loss on every restart

`InMemoryPluginStorage` is explicitly documented as non-persistent. All plugin settings, cache, and state are lost on app restart. No persistent backend is wired up.

---

### BUG-007: No Update Rollback Mechanism
**File:** `nightshade_updater/lib/src/update_service.dart`
**Severity:** CRITICAL — Bricked installations

- No previous version backup before installation
- No rollback if update fails mid-install
- No boot-time verification
- No "safe mode" fallback

**Impact:** A failed update leaves the app in an unrecoverable state.

---

### BUG-008: Race Condition in Exposure Frame Counting
**File:** `sequencer/src/executor.rs:692-804`
**Severity:** CRITICAL — Incorrect session data

Shared `StdRwLock<HashMap>` for frame progress tracking races when:
- Multiple nodes complete exposures concurrently (Parallel nodes)
- Remove/re-insert pattern loses frame count context
- `saturating_add` hides underflows

**Impact:** Checkpoint saves contain wrong exposure counts. Session recovery resumes from wrong frame.

---

### BUG-009: Image File Naming Collision
**File:** `providers/imaging_provider.dart:171-187`
**Severity:** CRITICAL — Silent data loss

If two exposures generate the same filename, the second silently overwrites the first. No uniqueness check or automatic de-duplication.

---

### BUG-010: Missing Mounted Checks After Async Operations
**Files:** Multiple — `imaging_screen.dart:96-130`, `focus_tab.dart:30-89`, `discovery_panel.dart:82-92`
**Severity:** CRITICAL — Crashes

Missing `if (mounted)` checks before `setState()` / `context.showSnackBar()` after `await` in multiple UI files. Widget may be disposed during async operation.

---

### BUG-011: Memory Leak in Event Subscription
**File:** `providers/event_provider.dart:130-162`
**Severity:** CRITICAL — Resource leak

`errorNotificationBridgeProvider` creates a `StreamSubscription` that may never be disposed if the provider is kept alive by a permanent watcher (e.g., AppShell).

---

### BUG-012: Mutex Poisoning Cascade in Adaptive Polling
**File:** `bridge/src/adaptive_polling.rs:396-420`
**Severity:** CRITICAL — Cascading device failure

All `AdaptivePoller` instances use `Mutex::lock().unwrap()`. If any thread panics while holding a lock:
- Mutex becomes poisoned
- ALL subsequent polling operations panic
- Mount slews freeze, focuser hangs, camera deadlocks

---

## 3. High-Severity Issues

### HIGH-001: Filter Focus Offset Application Fails Silently
**File:** `sequencer/src/instructions.rs:1670-1750`

When `apply_filter_focus_offset()` fails, no error is propagated. When `filter_name` is not in the offset map, the code silently skips with no warning. No bounds validation against focuser min/max position.

### HIGH-002: Autofocus Failure Doesn't Halt Exposure Loop
**File:** `sequencer/src/instructions.rs:1100-1310`

When autofocus fails mid-sequence, all subsequent exposures use the previous (bad) focus position. No "retry autofocus" or "abort if focus fails" option.

### HIGH-003: Incomplete Meridian Flip Recovery
**File:** `sequencer/src/meridian_flip_executor.rs:73-150`

- Guiding state not validated as restored after flip
- No check that mount actually switched pier sides
- If auto-center fails before flip, flip proceeds with mount misaligned

### HIGH-004: Null Dereference in Guiding Event Handler
**File:** `providers/guiding_provider.dart:297`

Direct access to `calibrationStateProvider.notifier._fetchCalibrationData()` without null/dispose check. Crashes if notifier is disposed.

### HIGH-005: Silent Autofocus Progress Parsing Failure
**File:** `providers/autofocus_progress_provider.dart:124-129`

If autofocus progress event is malformed, the overlay freezes at "Initializing autofocus..." with no error indicator. Violates CLAUDE.md: "Errors are a feature."

### HIGH-006: Race Condition in Session Stats (Non-Atomic RMS Read)
**File:** `providers/session_provider.dart:325-347`

`avgGuidingRmsRa` and `avgGuidingRmsDec` can be updated between reads, producing invalid combined RMS in checkpoint saves.

### HIGH-007: Camera Switch Race Condition in Temperature Polling
**File:** `services/device_service.dart:122-139`

When switching cameras, the old timer's final callback can fire after `_connectedCameraId` is updated, polling the wrong camera.

### HIGH-008: Nested Time Unwraps in Twilight Calculations
**Files:** `sequencer/src/instructions.rs:2377`, `sequencer/src/triggers.rs:416`

```rust
today.and_hms_opt(twilight_hour, twilight_minutes, 0)
    .unwrap_or_else(|| today.and_hms_opt(23, 59, 0).unwrap());
```

If both `and_hms_opt` calls fail, this panics during flat wizard twilight calculations.

### HIGH-009: Empty Vector Panic in Autofocus Fitting
**File:** `sequencer/src/autofocus.rs:488,543`

`engine.fit_parabola(&points).unwrap()` — if points is empty or < 3 entries, this panics.

### HIGH-010: WebRTC No Reconnection Logic
**File:** `nightshade_webrtc/lib/src/peer_connection.dart`

If WebRTC connection drops, there's no automatic recovery. User must manually reconnect. `initialize()` doesn't check for existing connections (double-init = leaked resources).

### HIGH-011: Plugin Event Bus Not Thread-Safe
**File:** `nightshade_plugins/lib/src/plugin_context.dart:104-147`

`_namedControllers` map is non-thread-safe. Creating controllers for event names isn't atomic — race condition with multiple plugins subscribing simultaneously.

### HIGH-012: No Plugin Timeout Protection
**File:** `nightshade_plugins/lib/src/plugin_host.dart:149-191`

If a plugin's `onLoad()` hangs, entire app startup blocks forever. No timeout mechanism.

### HIGH-013: Sequence Node Parent-Child No FK Constraint
**File:** `database/tables/sequences.dart:61-62`

`parentNodeId` is a string UUID with NO foreign key constraint. Allows dangling parent references, orphaned nodes, and invalid tree structures.

### HIGH-014: Guiding RMS Baseline Never Reset
**File:** `sequencer/src/triggers.rs:63-112`

HFR degradation trigger has no mechanism to reset baseline on new target, guide star change, or filter change. Bad baseline causes false trigger firing.

### HIGH-015: Cover Calibrator Not Halted on Cancellation
**File:** `sequencer/src/instructions.rs:3438-3500`

When user cancels sequence, focuser and rotator are halted but cover calibrator movement continues until mechanical stop.

### HIGH-016: Binning Change Doesn't Invalidate Autofocus
**File:** `sequencer/src/instructions.rs:838-843`

When binning changes between exposure nodes, previous autofocus data becomes invalid (HFR is binning-dependent). No warning, no re-autofocus trigger.

### HIGH-017: Update Manifest Signature Not Verified
**File:** `nightshade_updater/lib/src/update_verifier.dart:9-12`

Only SHA256 hash checking, no cryptographic signature verification. Updates could be tampered with.

### HIGH-018: Dangling Recovery Action References on Node Deletion
**Files:** `providers/sequence_provider.dart:1046-1079`, `services/sequence_repository.dart:90-134`

When a sequencer node is deleted, child nodes are recursively removed, but recovery actions or triggers that reference the deleted node ID become dangling. No validation prevents this.

---

## 4. Medium-Severity Issues

| ID | Issue | File | Impact |
|----|-------|------|--------|
| MED-001 | Hardcoded weather thresholds (30km/h wind, 90% humidity) not configurable | weather_safety_provider.dart:289-305 | Users can't tune safety limits |
| MED-002 | Focus model accepts unrealistic slopes without warning | focus_model_service.dart:243-260 | Bad thermal predictions |
| MED-003 | Async init race in FilterOffsetNotifier | filter_offset_provider.dart:58-65 | Empty offsets on first render |
| MED-004 | Missing session ID validation | session_provider.dart:158-183 | Invalid session → orphaned images |
| MED-005 | FocusModelService reads before init completes | focus_model_service.dart:186-192 | Focus models appear empty |
| MED-006 | Provider dependency chain too deep | Multiple providers | Cascading slow loads |
| MED-007 | Hardcoded strings in 105+ files | All screens | No i18n support |
| MED-008 | Missing empty states in multiple screens | sequencer, analytics, suggestions | Poor UX for new users |
| MED-009 | Missing loading states during async operations | equipment, analytics, settings | User confusion |
| MED-010 | Missing error feedback to user | equipment, sequencer, planetarium | Silent failures |
| MED-011 | Poor responsive design (no tablet breakpoint) | imaging, dashboard, sequencer | Bad layout 600-1024px |
| MED-012 | Inconsistent styling (padding, borders, button sizes) | Dashboard cards, various | Unprofessional appearance |
| MED-013 | Missing provider invalidation after data changes | imaging, equipment, settings | Stale data in UI |
| MED-014 | Median calculation off-by-one for even lists | api.rs:3596 | Slightly wrong auto-stretch |
| MED-015 | Missing FK on ImagingSessions.sequenceId | imaging_sessions.dart:50 | Can't delete sequences |
| MED-016 | No unique constraint on equipment profile names | equipment_profiles.dart | Duplicate profile names |
| MED-017 | No unique constraint on sequence names | sequences.dart:11-14 | Duplicate sequence names |
| MED-018 | Orphaned polar alignment history on profile delete | polar_alignment_history.dart:16 | Data accumulation |
| MED-019 | Multiple active equipment profiles possible | equipment_profiles.dart:72 | Ambiguous active profile |
| MED-020 | JSON blob schemas unvalidated | equipment_profiles, sequences | Runtime parse failures |
| MED-021 | Settings init race (INSERT OR IGNORE vs REPLACE) | database.dart:1104-1180 | Different defaults fresh vs upgrade |
| MED-022 | Duplicate optical config fields in equipment profile | equipment_profiles.dart:24-27,56-59 | Ambiguous values |
| MED-023 | Focus prediction data biased to recent sessions | sequencer/src/focus_prediction.rs:71-81 | Bad focus model |
| MED-024 | Autofocus V-curve assumes symmetric data | sequencer/src/autofocus.rs:180-210 | Bad focus on asymmetric sweep |
| MED-025 | Filter wheel name matching too fragile | bridge/src/devices.rs | Failed filter changes |
| MED-026 | Sequence import doesn't validate equipment | services/sequence_file_service.dart:35-166 | Fails at first missing filter |
| MED-027 | Mount tracking loss detection heuristic fragile | sequencer/src/triggers.rs:167-210 | False negative on flip trigger |
| MED-028 | Timer not disposed on error in mobile app | apps/mobile/lib/main.dart:97-134 | Memory leak |
| MED-029 | LAN push receiver not atomic (race on `_isReceiving`) | nightshade_updater | Double receive |
| MED-030 | Label layout O(n²) overlap checking | planetarium sky_renderer.dart | UI stalls >100 labels |
| MED-031 | Paint/blur cache unbounded growth | planetarium sky_renderer.dart | Memory leak |
| MED-032 | Missing no-drag-and-drop reorder in sequence tree | sequencer/widgets/sequence_tree.dart | Can't reorder nodes |
| MED-033 | Missing accessibility (semantic labels, focus order) | Multiple screens | Non-usable for impaired |
| MED-034 | Missing undo/redo for destructive operations | equipment, sequencer | Data loss |
| MED-035 | v18 migration is destructive (table recreation) | database.dart:744-1099 | Corruption risk if interrupted |

---

## 5. UI/UX Issues by Screen

### Equipment Screen
- No loading spinner during initial device discovery
- Device deletion shows confirmation but no undo
- Connection errors show generic message — should show device-specific error
- "Connect All" doesn't report individual device failures
- Selection state changes even if deletion fails (database error hidden)

### Imaging Screen
- Missing `mounted` check in `_takeSnapshot()` catch block (line 122-126)
- `_toggleLoop()` doesn't guard final `setState` (lines 166-171)
- No skeleton loader while image loads — blank space
- Auto-stretch fails silently on very dark images
- No retry option for failed captures

### Sequencer Screen
- No drag-and-drop node reordering within tree
- Missing UI for MeridianFlip tracking_limit_wait_minutes
- Missing UI for AutofocusInterval trigger frequency
- Missing UI for DitherInterval configuration
- No template categories or versioning
- No "apply template updates" feature
- Sequence time estimation ignores dither/filter-change/autofocus overhead

### Planetarium Screen
- Initial sync fails silently (line 97)
- `getDsoDisplayInfo()` has no error handling for missing properties
- Missing finder scope overlay
- Missing field rotation indicator
- Missing guiding box size indicator
- Missing observability window calculation

### Polar Alignment Screen
- No phone gyroscope/compass assist for rough alignment (mobile opportunity)
- Missing AR overlay showing pole position

### Dashboard Screen
- Complex breakpoint logic with gaps between 1024-1440px
- Cards use inconsistent padding (24, 16, 12)
- No skeleton loaders while data loads

### Settings Screen
- Settings load without visual feedback
- No search/filter for settings
- No import/export of settings

### Focus Tab
- `_runAutofocus()` calls `context.showSuccessSnackBar()` without `mounted` check (line 68)
- Force-cast `afResult.focusData as List` without type check (line 93)
- `_focuserState.maxPosition ?? 50000` — if focuserState itself is null, crash

### Shell / App Shell
- Catalog check dialog can appear after user navigates away (post-frame timing)

---

## 6. Database & Schema Issues

### Missing Constraints
| Issue | Table | Fix |
|-------|-------|-----|
| No unique on profile names | equipment_profiles | `text().unique()` |
| No unique on sequence names | sequences | `text().unique()` |
| No FK on sequenceId | imaging_sessions | Add `onDelete: setNull` |
| No FK on parentNodeId | sequence_nodes | Add self-referential FK |
| Multiple active profiles | equipment_profiles | Enforce single active via AppSettings |

### Missing Tables
| Table | Purpose |
|-------|---------|
| meridian_flip_events | Record flip history, success rate, timing |
| filter_wheel_positions | Track position history, usage statistics |
| stacked_images | Link raw frames to stacked output |
| equipment_health | Longitudinal tracking of equipment metrics |

### Missing Columns
| Table | Column | Purpose |
|-------|--------|---------|
| captured_images | rejection_timestamp | When was frame rejected |
| captured_images | rejection_category | Quality/focus/guiding/manual |
| captured_images | dither_offset_x/y | Dither applied |
| captured_images | quality_hfr, quality_eccentricity, quality_snr | Granular quality scores |

### Migration Issues
- v3→v17 databases have stale FK cascade constraints (v18 fixes retroactively)
- v18 migration uses destructive table recreation (corruption risk if interrupted)
- Settings initialization uses `INSERT OR IGNORE` — stale values on upgrade
- Default value inconsistency between table definitions and migration SQL

### Data Retention
- No automatic cleanup for old sessions, science data, or dark library
- Dark library pruning exists but is never automatically called
- No compression/archival for large science tables

---

## 7. Test Coverage Gaps

### Coverage Map

| Component | Files Tested | Files Total | Coverage |
|-----------|-------------|-------------|----------|
| Services | 12 | 30+ | ~40% |
| Providers | 2 | 39 | ~5% |
| UI Screens | 0 | 50+ | 0% |
| UI Widgets | 4 | 40+ | ~10% |
| Rust Sequencer | ~16 tests | Large | Low |
| Rust Imaging | ~8 tests | Large | Low |
| Rust Bridge | 0 | Large | 0% |
| Database/DAO | 1 (basic) | 15+ | ~7% |

### Critical Untested Paths
1. **End-to-end sequence execution** — Core app feature, zero integration tests
2. **Calibration frame application** — Flat/dark subtraction accuracy untested
3. **Live stacking algorithm** — No tests
4. **XISF format handling** — No tests
5. **Rust FFI integration** — Dart/Rust interface contract never validated
6. **All 37 untested providers** — State management largely unverified
7. **All UI screens** — No widget tests
8. **Weather safety evaluation** — Safety-critical, untested
9. **Crash recovery** — Checkpoint restore never validated
10. **Device disconnection mid-operation** — No tests

### Test Quality Issues
- No integration tests anywhere — everything is unit tested in isolation
- Backend fully mocked — never tests real FFI calls
- No performance/stress tests
- No test for large image processing or long sequences

---

## 8. Supporting Systems

### WebRTC Remote Control
| Issue | Severity | Detail |
|-------|----------|--------|
| No reconnection logic | HIGH | Connection drop = lost session |
| Double-init leaks resources | HIGH | `initialize()` doesn't check existing connection |
| Discovery vulnerable to malformed packets | MEDIUM | No message format validation |
| No rate limiting on discovery | MEDIUM | DoS via broadcast storms |
| Device ID in plaintext during discovery | MEDIUM | Reveals paired devices to network |
| No bandwidth throttling | LOW | Poor on high-latency connections |
| No command queueing | LOW | Messages dropped if client unavailable |

### Plugin System
| Issue | Severity | Detail |
|-------|----------|--------|
| Storage not persistent | CRITICAL | All data lost on restart |
| No plugin sandboxing | HIGH | One crash = app crash |
| No timeout protection | HIGH | Hung plugin blocks startup forever |
| Event bus not thread-safe | HIGH | Race conditions |
| No permission model | MEDIUM | Unrestricted access |
| No version compatibility checking | MEDIUM | Breaking changes undetected |
| Missing device state API | MEDIUM | Plugins can't access devices |
| Missing sequence execution hooks | MEDIUM | Can't extend automation |

### OTA Updater
| Issue | Severity | Detail |
|-------|----------|--------|
| No rollback mechanism | CRITICAL | Failed updates unrecoverable |
| No signature verification | HIGH | Update tampering possible |
| No disk space check before download | MEDIUM | Download fills disk |
| No cleanup of failed downloads | MEDIUM | Partial files accumulate |
| Version comparison breaks on pre-release tags | MEDIUM | "2.1.0-beta1" not handled |
| No delta/incremental updates | LOW | Full package downloads only |

### Planetarium
| Issue | Severity | Detail |
|-------|----------|--------|
| Paint cache unbounded | MEDIUM | Memory leak |
| Label layout O(n²) | MEDIUM | Stalls with many labels |
| No coordinate range validation | LOW | Invalid RA/Dec accepted |
| Missing astrophotography overlays | LOW | FOV, rotation, guide box |

---

## 9. Feature Additions

### Table Stakes (Must Have for Competitive Parity)

These features exist in ALL major competitors. Verify Nightshade's implementation is complete:

| Feature | Status | Gap |
|---------|--------|-----|
| Dome control and slaving | Needs verification | Ensure dome/shutter state tracking |
| Dynamic file naming with macros | Needs verification | Ensure completeness |
| Dithering between exposures | Needs verification | Ensure integration |
| DSLR/mirrorless camera support | In progress (gPhoto2) | Ship it |
| Email/SMS notifications | Partial (push only) | Add email/SMS options |
| Equipment profile export/import | Missing | Simple high-value add |
| Click-to-center from solved image | Missing | Power user feature |
| Guided beginner wizard | Missing | Critical for adoption |

### Sensible Feature Additions

| Feature | Effort | Impact | Description |
|---------|--------|--------|-------------|
| Intelligent target scheduler | Large | Very High | Auto-select optimal target based on altitude, moon, completion, weather. Multi-night project tracking. |
| Multi-night project tracking | Medium | Very High | Total integration per target across sessions, % complete, remaining time needed |
| Mosaic panel completion tracking | Medium | High | Which panels done, which need data, auto-resume specific panels |
| Configurable weather thresholds | Small | High | User-tunable humidity, wind, cloud limits |
| Session report generation | Medium | High | PDF/HTML report: targets, integration, quality, weather, equipment |
| Narrowband auto-switching | Medium | High | Auto-switch RGB ↔ narrowband based on moon phase |
| Satellite trail detection | Medium | Medium | Detect and reject frames with trails during capture |
| Smart exposure calculator | Medium | Medium | Calculate optimal sub-exposure from sky conditions, camera specs, target brightness |
| Sequence sharing/community templates | Medium | Medium | Share sequence configs with other users |
| Observatory management (power, dew) | Medium | Medium | Integrated roof/dome, power strip, dew heater control |

---

## 10. Competitive Landscape & Halo Features

### Nightshade's Unique Advantages
1. **Cross-platform** — Windows + macOS + Linux + iOS + Android. NINA and SGPro are Windows-only.
2. **Native mobile companion** — No competitor has a native mobile app with P2P WebRTC remote control.
3. **Rust performance** — Image processing, guiding, plate solving can leverage Rust + GPU.
4. **Behavior tree sequencer** — More architecturally powerful than NINA's linear or Voyager's DragScript.
5. **Modern tech stack** — Flutter + Rust vs. C#/WPF (.NET) or Qt (C++).

### Competitor Feature Matrix

| Feature | NINA | SGPro | Voyager | KStars | TheSkyX | Nightshade |
|---------|------|-------|---------|--------|---------|------------|
| Cross-platform | No | No | No | Yes* | Partial | **Yes (all)** |
| Mobile app | 3rd party | No | No | No | No | **Yes (native)** |
| Plugin ecosystem | Rich | No | No | No | No | Framework only |
| Web dashboard | No | No | Yes ($) | No | No | In progress |
| Visual sequencer | Advanced | Basic | DragScript | Basic | Basic | Behavior tree |
| Built-in guider | No (PHD2) | No (PHD2) | No (PHD2) | Yes | No | No (PHD2) |
| Multi-telescope | No | No | Yes (Array) | No | No | Architecture supports |
| Target scheduler | Plugin | No | Yes | Yes | No | Not yet |

### Halo Features (No Competitor Has These)

#### Tier 1 — High Impact, Leverages Existing Architecture

| Feature | Description | Why It Wins |
|---------|-------------|-------------|
| **Seamless session handoff** | Plan on phone → run on desktop → monitor from tablet. Real-time sync across devices. | No competitor is multi-device. Everyone is single-machine. |
| **AI session optimizer** | "What should I image tonight?" — auto-generates optimal plan from equipment, location, moon, weather, existing data, target completion. | NINA Target Scheduler needs manual project setup. No tool auto-plans from scratch. |
| **Real-time frame quality grading** | Every frame gets instant quality scores at capture time. Auto-reject satellite trails, clouds, bad HFR before writing to disk. | Current solutions grade frames only during post-processing. |
| **Native built-in multi-star guider** | Eliminate PHD2. Rust-native guider with multi-star tracking, predictive PEC, differential flexure detection. | Every competitor either uses external PHD2 or has a basic built-in guider. |

#### Tier 2 — Medium Impact, Unique Differentiators

| Feature | Description | Why It Wins |
|---------|-------------|-------------|
| **Optical train diagnostics** | Automated tilt detection, backfocus estimation, collimation assessment from captured frames. | Currently requires separate tools (Hocus Focus, TiltMap Pro). |
| **Predictive maintenance alerts** | Track equipment behavior over time. Alert when focuser backlash increases, guiding degrades, hot pixels evolve. | No competitor tracks equipment health longitudinally. |
| **Live collaborative viewing** | Share your live session via a link. Friends see live preview, stats, chat. "Twitch for astrophotography." | No competitor has social/collaborative features during capture. |
| **Mobile AR polar alignment** | Use phone IMU/compass for rough alignment, then refine with plate solving. AR overlay showing pole position. | No competitor uses phone sensors for alignment. |

#### Tier 3 — Long-Term Vision

| Feature | Description | Why It Wins |
|---------|-------------|-------------|
| **GPU-accelerated plate solving** | Sub-second solving using GPU parallelism for star triangle matching. No external solver dependency. | Current solvers (ASTAP, astrometry.net) are all CPU-bound. |
| **Integrated light pollution model** | Location-aware Bortle/SQM data. Auto-adjust exposure recommendations, suggest narrowband filters, estimate required integration time. | Light pollution maps are separate tools. |
| **Automated pointing model builder** | Like TheSkyX TPoint but automated — slew to N positions, plate solve each, build comprehensive pointing model. | Only TheSkyX has this, and it's expensive. |

---

## 11. Prioritized Action Plan

### Immediate (Block Release)

| Priority | Action | Bugs Addressed |
|----------|--------|----------------|
| P0 | Remove ALL `.unwrap()` / `panic!()` from FFI boundary code | BUG-001, BUG-003, BUG-012 |
| P0 | Add validation to unsafe pointer cast in debayer | BUG-002 |
| P0 | Verify park-on-error with retry and fallback | BUG-004 |
| P0 | Fix weather safety fail-mode detection | BUG-005 |
| P0 | Add `mounted` checks to all async UI operations | BUG-010 |
| P0 | Fix frame counting race condition in sequencer | BUG-008 |
| P0 | Add image filename uniqueness check | BUG-009 |

### Short-Term (Next 2 Sprints)

| Priority | Action | Issues Addressed |
|----------|--------|------------------|
| P1 | Replace Mutex::lock().unwrap() with poison recovery | BUG-012 |
| P1 | Add filter focus offset validation and error propagation | HIGH-001 |
| P1 | Implement autofocus failure → abort option | HIGH-002 |
| P1 | Complete meridian flip recovery | HIGH-003 |
| P1 | Fix event subscription memory leak | BUG-011 |
| P1 | Add plugin persistent storage backend | BUG-006 |
| P1 | Add update rollback mechanism | BUG-007 |
| P1 | Add WebRTC reconnection logic | HIGH-010 |
| P1 | Add FK constraints for parentNodeId, sequenceId | HIGH-013, MED-015 |
| P1 | Add unique constraints for profile/sequence names | MED-016, MED-017 |

### Medium-Term (Next Quarter)

| Priority | Action | Issues Addressed |
|----------|--------|------------------|
| P2 | Ship web dashboard | Competitive gap |
| P2 | Polish mobile companion experience | Biggest differentiator |
| P2 | Build native intelligent target scheduler | Top community request |
| P2 | Add configurable weather thresholds | MED-001 |
| P2 | Add integration tests for sequencer, calibration, recovery | Test gaps |
| P2 | Add session report generation | Feature request |
| P2 | Add multi-night project tracking | Feature request |
| P2 | Implement i18n / localization | MED-007 |
| P2 | Add plugin sandboxing and timeout protection | HIGH-012 |
| P2 | Add update signature verification | HIGH-017 |

### Long-Term (Roadmap)

| Priority | Action | Value |
|----------|--------|-------|
| P3 | Native built-in multi-star guider | Eliminate PHD2 dependency |
| P3 | Real-time frame quality grading with ML | Auto-reject bad frames |
| P3 | AI session optimizer | "What to image tonight" |
| P3 | Optical train diagnostics | Built-in tilt/collimation analysis |
| P3 | GPU-accelerated plate solving | Sub-second, no external dependency |
| P3 | Live collaborative viewing | Social feature, unique in market |
| P3 | Predictive maintenance | Equipment health tracking |
| P3 | Seamless session handoff between devices | Multi-device workflow |

---

---

## 12. Wave 2 Deep-Dive Findings (Exhaustive Line-by-Line Analysis)

The following findings come from exhaustive, line-by-line reads of every file in each subsystem. These supersede or augment the wave 1 findings with higher confidence and more precise line references.

### 12.1 Imaging Pipeline — 4 New Critical Bugs

#### IMG-CRIT-1: LibRaw Parameter Setting Uses Memory Scanning Hack (UB)
**File:** `imaging/src/raw.rs:388-403`

The code scans 32KB of raw memory starting at an arbitrary offset from the LibRaw processor pointer, looking for a floating-point signature (`gamm[0] ≈ 0.45045`) to locate the `output_params` struct. This is:
- Undefined behavior (casting arbitrary memory to struct pointer)
- Will silently fail on different LibRaw versions, build flags, or platforms
- When the scan misses, ALL user-requested processing parameters (white balance, color space, bit depth, gamma, demosaic algorithm) are silently dropped

The correct approach is to use the documented `libraw_data_t` struct layout where `output_params` is a known field.

#### IMG-CRIT-2: LibRaw Processed Image Copy Uses Wrong Size
**File:** `imaging/src/raw.rs:574-603`

`pixel_count` is computed from `width * height * channels`, but the copy uses this instead of LibRaw's actual `data_size` field. If LibRaw pads rows or the bits/colors don't exactly correspond, this over-reads allocated memory — potential segfault or corrupted pixel data.

#### IMG-CRIT-3: FITS Header END Scan Can Loop Forever
**File:** `imaging/src/reader.rs:76-92`

The mmap-based FITS reader scans for the `END` keyword in 80-byte records but has no iteration limit. If the FITS file is malformed (no END keyword), the scan reads past headers into pixel data, potentially "finding" an END sequence in pixel values and producing a wildly wrong `data_offset`.

#### IMG-CRIT-4: Live Stacking Inverse Affine Transform Is Wrong
**File:** `imaging/src/stacking.rs:603-633`

The inverse transform uses `inv_tx = transform.tx` and `inv_ty = transform.ty` directly, but the correct inverse translation for a rotation+translation is `t_inv = -R^T * t`. For any non-zero field rotation, stars are systematically misregistered in the stack. Pure translational drift works correctly, but any mount rotation produces silently misaligned stacks.

### 12.2 Imaging Pipeline — 8 High-Severity Issues

| ID | File:Line | Issue |
|----|-----------|-------|
| IMG-H1 | `fits.rs:302-314` | Duplicate FITS keywords produce duplicate `keyword_order` entries, written twice on output |
| IMG-H2 | `fits.rs:344-347` | Boolean parsing matches any string starting with T/F (e.g., "FLAT" → false, "TRUNCATED" → true) |
| IMG-H3 | `fits.rs:512-522` | Long float keyword values can overflow 80-byte FITS record — index panic |
| IMG-H4 | `processing.rs:213-220` | `flat_map(\|v\| vec![output])` allocates one Vec per pixel — millions of heap allocations for 20MP image |
| IMG-H5 | `stats.rs:573` | Division by zero when `bins == 0` in public histogram API |
| IMG-H6 | `xisf.rs:488-498` | XISF offset convergence not verified after 3rd pass — can write corrupt files PixInsight can't open |
| IMG-H7 | `reader.rs:230-283` | `read_downsampled` silently skips out-of-bounds pixels, producing wrong-length output |
| IMG-H8 | `lib.rs:377-388` | `to_display_u8` for 3-channel U16 returns solid gray — all debayered color images display as gray |

### 12.3 Imaging Pipeline — Medium Issues

| ID | File:Line | Issue |
|----|-----------|-------|
| IMG-M1 | `debayer.rs:207-232` | BGGR green pixel red/blue direction logic incorrect — systematic color error on BGGR sensors |
| IMG-M2 | `stats.rs:314-358` | Mean absolute deviation used instead of true MAD; 1.4826 factor is wrong — background sigma underestimated |
| IMG-M3 | `fits.rs:185` | Missing `NAXIS2` silently treated as height=1 instead of error |
| IMG-M4 | `stacking.rs:339-374` | Population variance (N denominator) used in sigma clipping — over-rejects on small frame counts (3-10) |
| IMG-M5 | `buffer_pool.rs:383-408` | 12 `.expect()` calls panic if `PooledBuffer` used after `into_vec()` |
| IMG-M6 | `naming.rs:497-510` | Frame number scan from end matches camera model numbers in filenames (e.g., ASI2600 → frame 2600) |

---

### 12.4 Panic Audit — Complete Inventory

**Total: 204 `.unwrap()`, 92 `.expect()`, 17 `panic!`, 60 `unreachable!`**

| Category | Count | Risk |
|----------|-------|------|
| In test code | 121 unwrap + 74 expect + 14 panic | Acceptable |
| Auto-generated (FRB) | 22 unwrap + 60 unreachable | Cannot modify |
| **FFI boundary (production)** | **10 Mutex unwraps** | **CRITICAL — cascading poison** |
| **Core logic Mutex/RwLock** | **66 unwraps** | **HIGH — all will cascade on poison** |
| **Core logic non-Mutex** | **4 expect/unwrap** | **HIGH — panics on edge cases** |
| Justified (guarded) | 12 | No action needed |

**Worst offenders by file:**
- `native/src/vendor/moravian.rs` — 22 mutex unwraps
- `native/src/vendor/touptek.rs` — 19 mutex unwraps
- `native/src/vendor/atik.rs` — 17 mutex unwraps
- `bridge/src/adaptive_polling.rs` — 5 mutex unwraps (FFI boundary!)
- `bridge/src/device_id.rs` — 5 mutex unwraps (FFI boundary!)
- `imaging/src/buffer_pool.rs` — 12 `.expect("buffer already taken")` calls

**Recommendation:** Replace ALL `Mutex::lock().unwrap()` with `lock().unwrap_or_else(|e| e.into_inner())` (poison recovery) or switch to `parking_lot::Mutex` (already used in some files, doesn't poison).

---

### 12.5 Device Control (devices.rs) — 3 New Critical Bugs

#### DEV-CRIT-1: ASCOM Rotator Connected But Never Stored
**File:** `devices.rs:885-888`

ASCOM rotator is connected during registration but the object is immediately dropped — never stored in any map. Every subsequent rotator operation (get_position, move_absolute, halt, is_moving) creates a fresh COM object, connects, operates, and disconnects. This makes ASCOM rotators effectively non-functional for sequencer use.

#### DEV-CRIT-2: ASCOM Weather/Safety Monitor Connected But Never Stored
**File:** `devices.rs:905-911`

Same pattern — ASCOM weather and safety monitor objects are connected and immediately dropped. Every poll cycle does a full COM connect/disconnect. **Safety monitors are safety-critical** — unreliable polling due to per-call reconnection is dangerous.

#### DEV-CRIT-3: Empty Debayer Panic (Duplicate of BUG-003)
**File:** `unified_device_ops.rs:502`

`sorted[sorted.len() / 2]` panics on empty vec from debayer output. Confirmed on the main imaging path.

### 12.6 Device Control — 12 High-Severity Issues

| ID | File:Line | Issue |
|----|-----------|-------|
| DEV-H1 | `devices.rs:7415` | Reconnect delay is linear, not exponential, despite backoff config |
| DEV-H2 | `devices.rs:4141,4204,4389` | `tracking_rate` hardcoded to Sidereal for ASCOM/native/INDI mounts |
| DEV-H3 | `devices.rs:4206-4208` | Native mount `can_slew/sync/pulse_guide` hardcoded `true` without querying |
| DEV-H4 | `devices.rs:5378-5396` | Alpaca filter_wheel_get_config creates fresh connection, doesn't use existing |
| DEV-H5 | `devices.rs:6326-6413` | INDI dome status gated `#[cfg(not(windows))]` — broken on Windows despite INDI compiling everywhere |
| DEV-H6 | `devices.rs:7745,7924` | INDI switch set_state/set_value re-parse device ID without bounds check |
| DEV-H7 | `unified_device_ops.rs:793` | Filter-by-name uses 1-based position; ASCOM/Alpaca APIs are 0-based — **wrong filter every time** |
| DEV-H8 | `unified_device_ops.rs:~24 locs` | 24+ stale "Map bayer pattern" placeholder comments in unrelated functions (CLAUDE.md violation) |
| DEV-H9 | `devices.rs:8487-8534` | cover_calibrator_get_status queries hardware 4x instead of 2x per poll |
| DEV-H10 | `devices.rs:7010-7021` | ASCOM mount heartbeat reads AtomicBool flag, never pings actual hardware — will never detect USB/driver disconnect |
| DEV-H11 | `ascom_wrapper_mount.rs:219` | `can_set_tracking` inferred from tracking read, not ASCOM `CanSetTracking` property |
| DEV-H12 | `ascom_wrapper_mount.rs:484-503` | `disconnect()` returns stop() error even when disconnect succeeded |

---

### 12.7 Database Deep-Dive — 1 New Critical Bug

#### DB-CRIT-1: `_normalizeDegrees` Corrupts LST, Breaking All Target Altitude Calculations
**File:** `targets_dao.dart:194-198`

```dart
double _normalizeDegrees(double value) {
  var normalized = value % 360.0;
  if (normalized < 0) normalized += 360.0;
  if (normalized > 180.0) normalized -= 360.0;  // Maps to [-180, 180]
  return normalized;
}
```

This function is used for BOTH LST normalization AND hour angle calculation, but they require different ranges. LST must be [0, 360); this function maps it to [-180, 180]. When `gmstDeg + longitudeDeg > 180°` (which happens ~50% of the time), LST becomes negative, producing completely wrong hour angles and altitudes. **`getObservableTargets` and the scheduler/suggestion system are fundamentally broken** — targets are incorrectly shown as observable or non-observable.

### 12.8 Database Deep-Dive — 8 High-Severity Issues

| ID | File:Line | Issue |
|----|-----------|-------|
| DB-H1 | `sequences_dao.dart:92-108` | `duplicateSequence` copies source `nodeId` UUIDs verbatim — both sequences share identical node UUIDs |
| DB-H2 | `images_dao.dart:205-216` | `getFilterCountsForTarget` loads ALL images into memory instead of SQL GROUP BY |
| DB-H3 | `dark_library_dao.dart:188-208` | `getDistinctGroups` loads entire dark library into memory for Dart-side dedup |
| DB-H4 | `dark_library_dao.dart:163-185` | `getStats` loads entire dark library for 3 simple counts |
| DB-H5 | `sessions_dao.dart:135-214` | `getTotalStatistics`/`getTargetStatistics` load all sessions for summation |
| DB-H6 | `flat_history_dao.dart:78-102` | `pruneHistory` — no transaction wrapper, crash leaves inconsistent state |
| DB-H7 | `polar_alignment_history_dao.dart:127-162` | `pruneHistory` — same no-transaction issue |
| DB-H8 | `imaging_sessions.dart:50` | `sequence_id` FK has no ON DELETE action — deleting sequence with sessions throws FK violation |

### 12.9 Database Deep-Dive — Medium Issues

| ID | File:Line | Issue |
|----|-----------|-------|
| DB-M1 | `science.dart:8-35` | No UNIQUE(session_id) on ScienceSessionConfig — race condition creates duplicates |
| DB-M2 | `dark_library.dart:21` | filePath has no unique constraint — duplicates accumulate |
| DB-M3 | `dark_library_dao.dart:68` | findBestMatch uses float equality for exposureTime — won't match due to FP precision |
| DB-M4 | `dark_library_dao.dart:57-113` | findBestMatch doesn't filter on `offset` — wrong darks matched to light frames |
| DB-M5 | `targets_dao.dart:72-79` | toggleFavorite is read-then-write without transaction — race condition |
| DB-M6 | `science_dao.dart:25-56` | upsertSessionConfig is read-then-write without transaction |
| DB-M7 | `imaging_sessions.dart:50` | Missing index on sequence_id |
| DB-M8 | `weather_settings.dart` | No single-row enforcement — multiple settings rows coexist |

---

### 12.10 Providers Deep-Dive — 4 New Critical Bugs

#### PROV-CRIT-1: Side-Effect Mutations Inside Provider Build Function
**File:** `meridian_flip_provider.dart:276-298`

`meridianFlipDisconnectGuardProvider` is a `Provider<void>` that mutates 5 other providers synchronously inside its build function. Riverpod forbids this — it runs during the widget build phase and will throw assertion errors in debug mode. In release mode, behavior is undefined and can cause rebuild loops.

#### PROV-CRIT-2: FilterOffsetNotifier Never Reacts to Profile Changes
**File:** `filter_offset_provider.dart:58-65`

`_loadOffsetsForActiveProfile()` is called once at construction. No `ref.listen` on `activeEquipmentProfileProvider`. If the user switches equipment profiles, offsets remain from the previous profile. Calling `setFilterOffset` persists offsets under the old profile ID, silently corrupting per-profile focus data.

#### PROV-CRIT-3: focusSettingsProvider Resets User Edits on Any Settings Save
**File:** `imaging_provider.dart`

`focusSettingsProvider` is a `StateProvider` that calls `ref.watch(appSettingsProvider)`. Any write to `appSettingsProvider` (exposure count change, filter selection, any toggle) causes the provider to re-initialize from persisted defaults, silently wiping any mid-session user adjustments to step size or HFR threshold.

#### PROV-CRIT-4: reorderNodes Null-Bang on Missing Node ID
**File:** `sequence_provider.dart`

`newNodes[children[i]]!` throws unhandled null check error if `children[i]` refers to a node ID not present in `newNodes`. Can occur during concurrent drag-and-drop + sequencer execution.

### 12.11 Providers Deep-Dive — 7 High-Severity Issues

| ID | File | Issue |
|----|------|-------|
| PROV-H1 | `template_snippet_provider.dart:113` | Unawaited `saveToDisk()` — disk errors silently swallowed, data lost on restart |
| PROV-H2 | `session_provider.dart:240` | Unawaited checkpoint persistence — database errors invisible, stale checkpoint on crash |
| PROV-H3 | `polar_alignment_provider.dart:341` | Void setters discard `updateConfig()` Future — persistence errors lost |
| PROV-H4 | `framing_provider.dart:25` | Module-level HTTP client never disposed — connection pool leak |
| PROV-H5 | `framing_provider.dart:676` | Missing `mounted` check after await before state assignment |
| PROV-H6 | `weather_safety_provider.dart:244` | Notifier mutation during synchronous state computation — re-entrancy violation |
| PROV-H7 | `auto_stretch_provider.dart:47` | `ref.read(backendProvider)` in FutureProvider doesn't track backend changes |

---

### 12.12 Services Deep-Dive — 3 New Critical Bugs

#### SVC-CRIT-1: Session Checkpoint Timer Interval Never Updates
**File:** `session_service.dart:385-399`

`_config` is reassigned to `config` before comparing `_config.checkpointTimeInterval != config.checkpointTimeInterval`. Since they're now the same reference, this is ALWAYS false. Changing checkpoint interval from 5 min to 1 min has zero effect.

#### SVC-CRIT-2: ErrorService Has Two Incompatible Singleton Instances
**File:** `error_service.dart:~361-381`

A top-level `final errorService = ErrorService()` creates a global instance at import time — before `setLoggingService` and `setUiNotificationNotifier` are called. Code using this global directly has a fully uninitialized error service that silently swallows all errors.

#### SVC-CRIT-3: Flat Wizard Uses Placeholder Delay for Filter Wheel Movement
**File:** `flat_wizard_service.dart:~107-110`

```dart
await Future.delayed(const Duration(milliseconds: 500));
```

Explicit stub with comment "Filter change would be handled by caller." CLAUDE.md: "You are not to EVER use stubs or placeholders." The flat wizard appears to succeed on filter changes without actually moving the filter wheel.

### 12.13 Services Deep-Dive — 13 High-Severity Issues

| ID | File | Issue |
|----|------|-------|
| SVC-H1 | `sequence_repository.dart:~714` | Unknown node types silently dropped on load — sequence corrupted with no warning |
| SVC-H2 | `calibration_service.dart:~316` | Empty catch block swallows calibration settings save failures (CLAUDE.md) |
| SVC-H3 | `plate_solve_service.dart:~99` | Backend exception swallowed before fallback — hides FFI/network errors |
| SVC-H4 | `auto_save_service.dart:155` | `stop()` calls async save without awaiting — data loss on shutdown |
| SVC-H5 | `device_service.dart:~484` | `_reconnectionTimers` never cancelled on disposal — fires into dead providers |
| SVC-H6 | `logging_service.dart:~241` | Provider creates uninitialized service with no enforced init ordering |
| SVC-H7 | `backup_service.dart:~190` | Backup failure logged at `debug` level instead of `error` |
| SVC-H8 | `backup_service.dart:~501` | Unsafe `as String` cast on arbitrary JSON — crashes on int/bool values from older backups |
| SVC-H9 | `profile_service.dart:~562` | JSON `.cast<String, int>()` throws for float values from older backups |
| SVC-H10 | `annotation_service.dart:~157` | `_ref.listen` in constructor with no dispose — permanent reference leak |
| SVC-H11 | `centering_service.dart` | No overall timeout on `centerOnTarget` — can hang indefinitely |
| SVC-H12 | `imaging_service.dart:~411` | `startLoopCapture` loops infinitely on persistent hardware errors (no circuit breaker) |
| SVC-H13 | `error_service.dart:~366` | Silent catch blocks in provider swallow provider read failures |

### 12.14 Services Deep-Dive — Medium Issues

| ID | File | Issue |
|----|------|-------|
| SVC-M1 | `session_export_service.dart:250` | Division by zero when totalExposures == 0 |
| SVC-M2 | `catalog_service.dart:~196` | Offset double-counted in paginated search, results skipped |
| SVC-M3 | `focus_model_service.dart:~278` | Division by zero when all temperature readings are identical |
| SVC-M4 | `dark_library_service.dart:~395` | Off-by-one in `_parseFitsPixels` skips final pixel |
| SVC-M5 | `notification_service.dart` | No timeout on HTTP requests to Discord/Pushover — can block indefinitely |
| SVC-M6 | `flat_wizard_service.dart:~423` | Iteration count off by one in FlatResult |
| SVC-M7 | `quick_start_service.dart:~545` | Broad catch swallows DB corruption errors, returns empty |
| SVC-M8 | `paginated_image_loader.dart:63` | `loadPage` doesn't update hasMore/currentPage state |
| SVC-M9 | `science_processing_service.dart:~394` | Top-level catch logs at warning instead of error |
| SVC-M10 | `mosaic_service.dart` | RA values not normalized to [0, 24) after offset |

---

### 12.15 Bridge API Deep-Dive — New Findings

#### FFI-CRIT-1: FITS Calibration Path Unwraps Not Individually Guarded
**File:** `bridge/src/api.rs:9854-9860`

The `if dark_path.is_some() || flat_path.is_some() || bias_path.is_some()` guard enters the block if ANY path is Some, but then unconditionally unwraps ALL three. If only `flat_path` is set, `dark_path.as_ref().unwrap()` panics across the FFI boundary.

#### FFI-HIGH-1: Polar Alignment Double-Wait — Each Capture Takes 2x Duration
**File:** `bridge/src/api.rs:7825-7837, 8025-8033`

`api_camera_start_exposure` is async and blocks until exposure completes. The code then `sleep(exposure_time + 2.0)` — waiting a second full exposure duration doing nothing. For 60-second exposures, this wastes 3+ minutes across a 3-point polar alignment.

#### FFI-HIGH-2: Silent Node Serialization Failures (21 Sites)
**File:** `bridge/src/api.rs:6305-7426`

Every node factory uses `serde_json::to_string(&node).unwrap_or_default()` — serialization failure silently produces empty string. When passed back to `api_build_sequence`, the empty string fails to deserialize and the node is silently dropped (FFI-HIGH-3).

#### FFI-HIGH-3: Silent Node Dropping in api_build_sequence
**File:** `bridge/src/api.rs:7414`

`filter_map(|json| serde_json::from_str(json).ok())` silently drops nodes that fail to deserialize. Sequence runs with missing nodes — missing loop bounds, filter changes, or exposures — with no error returned.

#### FFI-HIGH-4: Fixed Temp Filename for Plate Solve — Race Condition
**File:** `bridge/src/sequencer_ops.rs:627`

`temp_dir.join("nightshade_platesolve_temp.fits")` — global fixed filename. Concurrent plate-solves (mosaic centering + polar alignment) overwrite each other's FITS data.

#### FFI-HIGH-5: sequencer_clear_checkpoint Silently Succeeds When Lock Contended
**File:** `bridge/src/sequencer_api.rs:267-275`

When executor RwLock is contended, returns `Ok(())` without clearing checkpoint. On next launch, app offers to resume a completed sequence.

#### FFI-MED-1: Hardcoded "60 seconds" in Plate Solve Timeout Message
**File:** `bridge/src/api.rs:7884`

Error message says "60 seconds" but actual timeout is the caller-supplied `solve_timeout_secs` parameter.

#### FFI-MED-2: Filter Wheel Position Failure Silently Uses 0
**File:** `bridge/src/sequencer_ops.rs:422-424`

`filter_wheel_get_position(...).await.unwrap_or(0)` — corrupts filter change history in UI/logging.

---

### 12.16 Sequencer Deep-Dive — DEVASTATING Astronomical Bugs

#### SEQ-CRIT-1 through SEQ-CRIT-4: Hour Angle Conversion Is INVERTED (4 Locations)
**Files:** `node.rs:229`, `node.rs:274,276`, `node.rs:316`, `meridian.rs:169`

```rust
// WRONG (current code - 4 locations):
let ha_rad = ha.to_radians() * 15.0;

// CORRECT (only in device_ops.rs:645):
let ha_rad = (ha * 15.0).to_radians();
```

`ha` is in hours. The code calls `.to_radians()` first (treating hours as degrees), then multiplies by 15. The result is **15x too large**. Since `cos()` is applied to this inflated radian value, **every altitude calculation, twilight detection, moon separation check, and meridian calculation in the sequencer produces garbage results**.

This affects:
- All `min_altitude` / `max_altitude` constraints
- All `WhileDark` / `AltitudeBelow` / `AltitudeAbove` loop conditions
- All `MoonSeparationAbove` conditional checks
- All start-time scheduling based on target altitude
- All `is_dark()` twilight calculations

**This is the single most impactful bug in the entire codebase.**

#### SEQ-CRIT-5: GMST Used as LST Without Longitude Correction
**File:** `meridian_flip_executor.rs:572-574`

```rust
let gmst = greenwich_mean_sidereal_time(jd);
let lst = gmst; // WRONG: LST = GMST + longitude/15.0
let ha = lst - ra_hours;
```

The meridian flip trigger's hour angle is wrong by `longitude/15.0` hours for every observer not at Greenwich. At 90°W longitude, the flip triggers **6 hours too early or late** — it may never trigger during a session.

#### SEQ-CRIT-6: TriggerState Initializes `weather_safe: true` — Fail-Open Default
**File:** `triggers.rs:510`

Before any weather data is received, the system assumes safe. If the safety monitor fails to connect, the sequence runs indefinitely without safety monitoring. Directly contradicts the project's fail-closed policy.

#### SEQ-HIGH-1: progress_callback Called Twice Per Frame — Doubles Exposure Counter
**File:** `instructions.rs:885,983`

`progress_callback(frame, config.count)` is called before AND after each exposure. The trigger system sees 2x the actual frame count, corrupting `AutofocusInterval`, `DitherInterval`, and HFR trigger logic.

#### SEQ-HIGH-2: Mount Sync Errors Silently Discarded
**File:** `instructions.rs:763-771`

`let _ = ctx.device_ops.mount_sync(...).await;` — if sync fails, the correction slew uses the wrong pointing model.

#### SEQ-HIGH-3,4: Fixed 5-Second Slew Waits (Flat Wizard + Polar Alignment)
**Files:** `flat_wizard.rs:408,464`, `polar_align.rs:147`

GEM mounts can take 30-90+ seconds for large slews. Flat frames captured during slew are blurred. Polar alignment measurement points plate-solved during slew are wrong.

#### SEQ-HIGH-5,6: No Slew Timeout in Meridian Flip — Infinite Hang
**File:** `meridian_flip_executor.rs:296-332,410-416`

If mount gets stuck in slewing state (hardware failure), executor loops infinitely with no timeout or cancellation check.

#### SEQ-HIGH-7: verify_pier_side_changed Doesn't Actually Verify
**File:** `meridian_flip_executor.rs:334-344`

Function reads current pier side but never compares against pre-flip side. A failed flip is reported as "verified."

#### SEQ-HIGH-8: Dither Parameters Hardcoded (5.0px, 1.5px settle, 30s, 120s)
**File:** `instructions.rs:991`

Not read from any config. Different imaging rigs need completely different dither parameters.

#### SEQ-HIGH-9: Parallel Branches Get `trigger_state: None`
**File:** `node.rs:~1839`

HFR measurements, exposure counts, and dither tracking inside parallel branches are all discarded. Triggers never fire for parallel work.

#### SEQ-HIGH-10: Warm Camera Hardcoded to 10°C
**File:** `instructions.rs:~2037`

In summer at 35°C ambient, cooler runs at 100% indefinitely trying to reach 10°C.

#### Sequencer Medium Issues (15 total)

| ID | File | Issue |
|----|------|-------|
| SEQ-M1 | `node.rs:~1477` | `start_after` wait has no cancellation — can't stop 3-hour wait |
| SEQ-M2 | `node.rs:~2153` | Recovery autofocus uses `AutofocusConfig::default()`, not user config |
| SEQ-M3 | `executor.rs:~1291` | Trigger-fired flip has `focuser_id: None` — skips post-flip refocus |
| SEQ-M4 | `executor.rs:~1205` | Trigger-fired autofocus missing lat/lon/save_path |
| SEQ-M5 | `temperature_compensation.rs:78-164` | Write lock held across device I/O — blocks trigger monitor |
| SEQ-M6 | `instructions.rs:~1816` | Filter offset poll breaks on error without verifying offset applied |
| SEQ-M7 | `node.rs:308` | Sun RA formula wrong — can produce NaN from acos(>1) |
| SEQ-M8 | `lib.rs` | FlatWizardConfig default flat_count: 0 — silent no-op |
| SEQ-M9 | `polar_align.rs:386` | Azimuth error uses pole_ra=0.0 — physically meaningless |
| SEQ-M10 | `triggers.rs:~300` | u32 underflow after checkpoint resume |
| SEQ-M11 | `executor.rs:~919` | Start/SkipToNode silently swallowed while running |
| SEQ-M12 | `executor.rs:~1387` | Cancelled maps to Idle — state conflation |
| SEQ-M13 | `mosaic.rs:102` | 60s overhead hardcoded for panel time estimate |
| SEQ-M14 | `mosaic.rs:62-70` | RA correction uses center dec, not panel dec |
| SEQ-M15 | `checkpoint.rs:270,306` | Checkpoint file loaded twice per query |

---

### 12.17 Device Drivers Deep-Dive — 7 New Critical Bugs

#### DRV-CRIT-1: INDI Safety Monitor Fail-Open — Returns `true` for Unknown State
**File:** `indi/src/weather.rs`

`is_safe()` returns `true` for the `Unknown` variant. If INDI weather device goes offline or hasn't sent data yet, safety monitor reports "safe." Equipment can be damaged.

#### DRV-CRIT-2: Blocking `std::thread::sleep` in Async Discovery
**File:** `native/src/discovery.rs:534,558`

`std::thread::sleep(200ms)` called from async context. With 50 parallel discovery tasks, blocks all Tokio worker threads.

#### DRV-CRIT-3: Mutex Poison Cascade in Vendor SDKs (58 Sites)
**Files:** `vendor/touptek.rs` (19), `vendor/atik.rs` (17), `vendor/moravian.rs` (22)

All vendor SDK operations use `handle.lock().unwrap()`. One SDK crash poisons the mutex, making the entire camera permanently unusable. Touptek's global SDK HashMap mutex is shared across ALL cameras — one crash takes down all Touptek cameras.

#### DRV-CRIT-4: TOCTOU Race in Touptek connect()
**File:** `vendor/touptek.rs:672-692`

`connect()` opens camera by index, releases mutex, then re-enumerates USB to get model flags. If a camera is plugged/unplugged between, wrong capability flags are used — cooler commands sent to uncooled cameras.

#### DRV-CRIT-5: Alpaca HTTP Client Panics on TLS Failure
**File:** `alpaca/src/client.rs:~380`

`.expect("Failed to create HTTP client")` panics across FFI boundary. Fails on systems with missing TLS certificates.

#### DRV-CRIT-6: INDI Mount Left in SLEW Mode on Partial Failure
**File:** `indi/src/mount.rs:~76`

If coordinate set fails after ON_COORD_SET was set to SLEW, subsequent SYNC operations will cause unexpected slews. Creates infinite correction loops in plate-solve-and-center.

#### DRV-CRIT-7: `block_in_place` Panics on Single-Thread Runtime (Mobile)
**Files:** `indi/src/camera.rs:~441`, `indi/src/filterwheel.rs:~70`

`tokio::task::block_in_place()` panics with "cannot call from current_thread runtime." Flutter on mobile uses single-thread runtime. INDI camera/filterwheel crashes the app on iOS/Android.

#### Driver High-Severity Issues (10 total)

| ID | File | Issue |
|----|------|-------|
| DRV-H1 | `indi/src/client.rs:~298` | Broadcast channel(100) — BLOB events silently dropped when 100 behind |
| DRV-H2 | `vendor/zwo.rs:~240` | Developer's personal path `C:\Users\scdou\...` hardcoded in SDK loader |
| DRV-H3 | `indi/src/client.rs:239-246` | rand_simple() has only 1000 possible values — reconnect jitter collisions |
| DRV-H4 | `indi/src/client.rs:1058-1065` | XML parse error continues silently — parser in indeterminate state |
| DRV-H5 | `vendor/touptek.rs:~812` | exposure_remaining reports total duration, not actual remaining |
| DRV-H6 | `indi/src/discovery.rs:270-317` | Blocking TCP connect from async — starves Tokio thread pool |
| DRV-H7 | `vendor/zwo.rs:297-484` | SDK load code duplicated verbatim — divergence risk |
| DRV-H8 | `vendor/moravian.rs:226-262` | Enumerate callback race with global HashMap |
| DRV-H9 | `indi/src/autofocus.rs:354-390` | FITS header parser assumes single 2880-byte block — fails on extended headers |
| DRV-H10 | `ascom/src/windows_impl.rs:~175` | Timeout config returns defaults on poisoned lock — silent config loss |

#### Driver Medium-Severity Issues (8 total)

| ID | File | Issue |
|----|------|-------|
| DRV-M1 | `indi/src/lib.rs` | `is_available()` always returns true even on Windows |
| DRV-M2 | `indi/src/camera.rs:~391` | Hardcoded 30s exposure timeout buffer ignores config |
| DRV-M3 | `indi/src/covercalibrator.rs:505` | Max brightness hardcoded 255 — wrong for many flat panels |
| DRV-M4 | `indi/src/autofocus.rs:332` | Hardcoded 60s autofocus buffer inconsistent with camera's 30s |
| DRV-M5 | `indi/src/discovery.rs:418-430` | Subnet list hardcoded (192.168.0, 192.168.1, 10.0.0) |
| DRV-M6 | `vendor/lx200.rs:304-322` | Serial port busy-polls with no sleep on Ok(0) |
| DRV-M7 | `alpaca/src/telescope.rs:503` | Query param embedded in URL path string |
| DRV-M8 | `vendor/lx200.rs:160` | Dec arcseconds parse failure silently defaults to 0.0 |

---

### 12.19 Revised Bug Count Summary

| Severity | Wave 1 | Wave 2 New | **Total** |
|----------|--------|------------|-----------|
| CRITICAL | 12 | 29 | **41** |
| HIGH | 18 | 65 | **83** |
| MEDIUM | 35 | 49 | **84** |
| **Total** | **65** | **143** | **208** |

*Note: 1 deep-dive agent (screens) is still completing. Final count may be slightly higher.*

---

### 12.20 Updated Priority Actions

#### P0 — Fix Immediately (Blocks Any Real-World Use)

**Astronomical Calculations (affects ALL sequencer logic):**
- Fix HA conversion in 4 locations: `(ha * 15.0).to_radians()` not `ha.to_radians() * 15.0` (SEQ-CRIT-1-4)
- Fix GMST→LST: add longitude correction for meridian flip (SEQ-CRIT-5)
- Fix `_normalizeDegrees` in TargetsDao — **all target scheduling is broken** (DB-CRIT-1)

**Safety-Critical:**
- Fix TriggerState `weather_safe: true` default → `false` (SEQ-CRIT-6)
- Fix INDI `is_safe()` returning `true` for Unknown state (DRV-CRIT-1)
- Store ASCOM rotator/weather/safety objects persistently (DEV-CRIT-1, DEV-CRIT-2)

**Memory Safety / Crashes:**
- Fix unsafe pointer cast alignment in debayer (BUG-002)
- Fix FITS calibration path individual guarding (FFI-CRIT-1)
- Fix `block_in_place` panics on mobile single-thread runtime (DRV-CRIT-7)
- Fix Alpaca HTTP client panic on TLS failure (DRV-CRIT-5)
- Fix LibRaw memory scan UB and copy size (IMG-CRIT-1, IMG-CRIT-2)

**Data Corruption:**
- Fix live stacking inverse transform math (IMG-CRIT-4)
- Fix filter-by-name 0-based vs 1-based position (DEV-H7)
- Fix progress_callback double-call doubling exposure counter (SEQ-HIGH-1)
- Fix INDI mount SLEW mode stuck on partial failure (DRV-CRIT-6)
- Fix image filename collision — silent data loss (BUG-009)

**Silent Failures:**
- Fix flat wizard filter wheel 500ms placeholder (SVC-CRIT-3)
- Fix session checkpoint timer self-comparison (SVC-CRIT-1)
- Fix `focusSettingsProvider` reset-on-any-save (PROV-CRIT-3)
- Fix `FilterOffsetNotifier` profile change listener (PROV-CRIT-2)
- Remove polar alignment double-wait (FFI-HIGH-1)

#### P1 — Fix This Sprint

- Replace ALL 124+ Mutex unwraps with poison recovery or parking_lot
- Fix blocking std::thread::sleep in async discovery (DRV-CRIT-2)
- Fix Touptek TOCTOU race in connect() (DRV-CRIT-4)
- Fix FITS header END scan infinite loop (IMG-CRIT-3)
- Fix flat wizard/polar alignment fixed slew waits → poll is_slewing (SEQ-HIGH-3,4)
- Fix meridian flip slew timeout (infinite hang) (SEQ-HIGH-5,6)
- Fix verify_pier_side_changed to actually compare (SEQ-HIGH-7)
- Fix parallel branches trigger_state: None (SEQ-HIGH-9)
- Fix node serialization/dropping — sequences silently lose nodes (FFI-HIGH-2,3)
- Fix N+1 query patterns in DAOs
- Add transaction wrappers to prune operations
- Fix ASCOM mount heartbeat to ping hardware
- Add `await` to all unawaited persistence Futures
- Add circuit breaker to `startLoopCapture`
- Fix plugin persistent storage
- Fix update rollback mechanism
- Remove hardcoded developer path from ZWO SDK loader (DRV-H2)

#### P2 — Fix This Quarter

- Fix all FITS parsing issues (boolean, keywords, record overflow)
- Fix BGGR debayer direction logic
- Fix MAD calculation in stats
- Fix dither parameters hardcoding
- Fix warm camera temperature hardcoding
- Fix WebRTC reconnection logic
- Add plugin sandboxing and timeout protection
- Add update signature verification
- Ship web dashboard
- Polish mobile companion
- Build native target scheduler
- Add configurable weather thresholds
- Add integration tests for critical paths
