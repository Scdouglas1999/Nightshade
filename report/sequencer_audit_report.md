# Nightshade 2.0 Sequencer Audit Report

**Generated:** March 15, 2026
**Version Audited:** 2.5.0
**Scope:** Rust engine, Dart UI, bridge data flow, database, UX analysis

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Engine Assessment](#2-engine-assessment)
3. [UI/UX Assessment](#3-uiux-assessment)
4. [Data Flow & Integration Assessment](#4-data-flow--integration-assessment)
5. [Bugs & Edge Cases](#5-bugs--edge-cases)
6. [Half-Baked Features](#6-half-baked-features)
7. [Looks Like It Works But Doesn't](#7-looks-like-it-works-but-doesnt)
8. [UI Layout & Interaction Issues](#8-ui-layout--interaction-issues)
9. [Missing Visual Aids](#9-missing-visual-aids)
10. [Feature Recommendations](#10-feature-recommendations)
11. [Prioritized Action Plan](#11-prioritized-action-plan)

---

## 1. Executive Summary

The Nightshade sequencer is a **production-grade behavior tree engine** with mature safety handling, comprehensive node types, and solid execution logic. The Rust engine is the strongest layer — fail-closed safety, sophisticated meridian flip heuristics, multi-method autofocus, and checkpoint recovery. The UI builder is genuinely good with 16 templates, drag-and-drop, undo/redo, and comprehensive pre-flight validation.

However, the sequencer has **significant UX gaps** that undermine usability: misleading time estimation (shows raw integration only, no overheads), events lost crossing the Rust→Dart bridge, missing cover calibrator nodes, no trigger configuration UI, no checkpoint recovery dialog, and structural interaction problems in the tree builder.

**No critical bugs found in the engine.** The issues are primarily in the UI layer, bridge event pipeline, and missing user-facing features.

### Summary Counts

| Category | Count |
|----------|-------|
| Must Fix (broken/misleading) | 5 |
| Should Fix (significant UX gaps) | 12 |
| UI layout/interaction issues | 11 |
| Missing visual aids | 4 |
| Feature recommendations (differentiators) | 10 |
| Engine edge cases | 4 |
| **Total recommendations** | **46** |

---

## 2. Engine Assessment

### What's Solid

**Node Types (31 total — comprehensive):**

*Container/Logic Nodes:*
- TargetHeader (time/altitude constraints, mosaic panel info)
- Loop (4 trigger methods: Count, UntilTime, AltitudeBelow, AltitudeAbove)
- Parallel (configurable success thresholds)
- Conditional (8 condition types: Always, AltitudeAbove, TimeAfter, GuidingRmsBelow, HfrBelow, WeatherSafe, MoonSeparationAbove, SafetyMonitorSafe)
- Recovery (configurable recovery actions)

*Instruction Nodes (26):*
- Slew, Center, TakeExposure, Autofocus, TemperatureCompensation, Dither
- StartGuiding, StopGuiding, ChangeFilter
- CoolCamera, WarmCamera, MoveRotator, Park, Unpark
- WaitForTime, Delay, Notification, RunScript
- PolarAlignment, MeridianFlip
- OpenDome, CloseDome, ParkDome
- OpenCover, CloseCover, CalibratorOn, CalibratorOff
- Mosaic, FlatWizard

**Execution Model:**
- Pre-order depth-first tree traversal
- Parallel branches spawned separately with configurable success thresholds
- Cancellation via atomic flag
- Pause/resume with notification
- Three concurrent async tasks: execution, command handler, trigger monitor
- No race conditions detected

**Trigger System (12 triggers):**
- HfrDegraded (dual-mode: relative % + absolute threshold, consecutive-frame debouncing)
- MeridianFlip (4 methods: MinutesPastMeridian, MinutesBeforeLimit, HourAngleThreshold, OnTrackingLimitHit)
- GuidingFailed (RMS threshold + duration)
- AltitudeLimit, WeatherUnsafe, TemperatureShift, FilterChange
- DawnApproaching (astronomical twilight with configurable minutes-before)
- AutofocusInterval, DitherInterval (periodic frame-based)
- MountTrackingLost (with heuristic to distinguish limit hits from actual errors)
- DomeShutterNotOpen

**Safety:**
- All safety checks fail-closed (safety read errors → unsafe)
- SafetyFailMode enum enforced at runtime (even if config says FailOpen)
- ParkAndAbort recovery action actually parks the mount (fixed earlier this session)
- Weather abort, altitude limits, dome shutter monitoring

**Autofocus:**
- 3 fitting methods: V-curve, parabolic (quadratic least-squares), hyperbolic
- Outlier rejection via sigma clipping with MAD
- Backlash compensation configurable
- R-squared quality metric
- Filter offset tracking for multi-filter imaging
- Temperature-based focus prediction integration

**Meridian Flip:**
- 4 trigger methods with sophisticated tracking limit detection
- Full flip sequence: pause guiding → stop tracking → slew → verify pier side → resume tracking → plate solve + center → refocus → resume guiding → settle
- Configurable max retries with per-retry delays
- Failure action: PauseAndAlert or AbortAndPark
- Distinguishes between limit hits and tracking loss errors

**Checkpoint/Recovery:**
- Saves after each node completion
- Atomic write with backup file
- Stores: node statuses, completed counts, device IDs, location, full sequence definition
- Resume marks completed nodes and skips them
- Integration time counter restored

**Flat Wizard:**
- Binary search for optimal exposure time
- ADU tolerance configurable (default 5%)
- Auto-brightness adjustment
- Filter support (index-based)
- Twilight timing support

**Mosaic:**
- Panel grid calculation with overlap compensation
- Rotation support with RA/Dec compression accounting
- Correct RA correction factor at each panel's declination
- Overhead time per panel configurable

**Temperature Compensation:**
- Coefficient-based compensation
- Configurable thresholds (min temp change, min step change)
- Two modes: continuous or single-run
- Baseline establishment on first run

**Focus Prediction:**
- Linear regression model (slope + intercept + R²)
- Temperature bucketing (best HFR per 1°C bucket)
- Per-filter offset tracking
- Data point trimming (keeps 100 most recent with smart sampling)
- Reliability check: R² >= 0.7 AND >= 5 data points

**Polar Alignment:**
- Three-point method with plate solving
- Auto-rotation or manual
- Live image feedback with stretch/debayer
- Auto-completion threshold (30 arcsec) with stability check
- Hemisphere-aware

### Engine Edge Cases

| ID | Issue | Severity | Detail |
|----|-------|----------|--------|
| ENG-1 | Trigger monitor crash not propagated | MEDIUM | If trigger monitor task panics, execution continues silently without safety monitoring |
| ENG-2 | Pathological loops hang | LOW | Loop with Forever condition + no children = infinite hang with no safety limit |
| ENG-3 | HFR baseline never resets on AF failure | LOW | If autofocus fails, degradation trigger keeps old (bad) baseline |
| ENG-4 | Checkpoint only on node completion | MEDIUM | If process crashes during 20-minute exposure, progress since last node completion is lost |

### Missing Engine Features

| ID | Feature | Impact | Detail |
|----|---------|--------|--------|
| ENG-F1 | Autofocus timeout | HIGH | AF can hang if camera doesn't respond; needs max-time check (configurable, default 10min) |
| ENG-F2 | Guide star lost trigger | MEDIUM | HFR alone doesn't catch guide star dropout — need separate trigger |
| ENG-F3 | Post-sequence statistics | HIGH | No summary of total integration, downtime, dropped frames, trigger fire count |
| ENG-F4 | Equipment validation at startup | HIGH | No check that all configured devices are reachable before starting |
| ENG-F5 | Streaming checkpoint updates | MEDIUM | Checkpoint every 30 seconds, not just per node — prevents long-exposure data loss |
| ENG-F6 | Focus drift detection | MEDIUM | HFR plateau detection separate from degradation trigger |
| ENG-F7 | Condition-based abort | MEDIUM | Humidity threshold trigger (not just binary weather safe/unsafe) |
| ENG-F8 | Dither pattern selection | LOW | Grid dithering option alongside random offset |
| ENG-F9 | Pre-flip sanity checks | LOW | Verify target is still above horizon post-flip |
| ENG-F10 | Guiding calibration validation | LOW | After StartGuiding, check that calibration succeeded |

---

## 3. UI/UX Assessment

### What's Good

| Aspect | Quality | Detail |
|--------|---------|--------|
| Sequence Builder | Excellent | 3-column desktop layout (toolbox, tree, properties), responsive, drag-and-drop |
| Templates | Excellent | 16 built-in templates (First Light through Unattended All-Night), fallback to built-in if DB empty |
| Running State | Excellent | Current node, target, filter, elapsed, ETA space, frame count, percentage, pause indicator |
| Validation | Excellent | Comprehensive pre-flight checks: structure, targets, exposures, equipment, settings, timing |
| Keyboard Shortcuts | Excellent | Ctrl+Z/Y undo/redo, Delete, Ctrl+D duplicate, Alt+1/2/3 tab switch |
| Undo/Redo | Excellent | 50-item stack |
| Import/Export | Good | JSON format, save/load from file |
| Mobile Layout | Good | Bottom sheets for palette and properties, separate playback bar |
| Equipment Status | Good | Connected device icons with validation |

### Node Configuration Coverage

**28 of 31 Rust node types have UI property panels.**

Missing from UI (exist in Rust but have no Dart models or property editors):

| Node Type | Rust Config | Impact |
|-----------|-------------|--------|
| OpenCover | `CoverCalibratorConfig` | Users with flat panels cannot automate cover open in sequences |
| CloseCover | `CoverCalibratorConfig` | Users cannot automate cover close |
| CalibratorOn | `CalibratorOnConfig` | Users cannot automate flat panel brightness |
| CalibratorOff | `CoverCalibratorConfig` | Users cannot automate flat panel off |

**File:** `packages/nightshade_app/lib/screens/sequencer/widgets/node_properties_panel.dart`

### Time Estimation

**Status: 40% — MISLEADING**

What's shown:
- Total frame count
- Total integration time (light frames only)
- Warning if > 8 hours

What's NOT included:
- Slew time between targets (~30s-2min each)
- Autofocus overhead (~3-5min per run)
- Filter change time (~5-15s each)
- Dither + settle time (~15-30s per dither)
- Guide star acquisition (~30s-1min)
- Meridian flip overhead (~5-10min)
- Camera cooling time (~5-15min)
- Plate solve time (~10-30s each)
- Wait node durations
- Inter-node overhead

**Real impact:** A "6 hour" sequence actually takes 8-10+ hours. Users cannot accurately plan their night.

**File:** `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart` (SequenceEstimate class)

---

## 4. Data Flow & Integration Assessment

### Sequence Building (Dart → Rust)

**Flow:** UI → Provider (`currentSequenceProvider`) → JSON serialization (`_nodeToConfig()`) → Bridge API (`api_sequencer_load_json`) → Rust executor

**Status:** Working for all 28 UI-implemented node types. Serialization handles filter matching, binning, autofocus methods, loop conditions, conditionals, and recovery actions.

**Gaps:**
- No validation layer between Dart and Rust — invalid sequences fail silently at Rust side
- Unknown node types silently become `{'type': 'Unknown'}` with no error
- Filter indices auto-populated from profile if not set (helpful but can mask user errors)

### Execution Events (Rust → Dart)

**Flow:** Rust Executor → Event Bus → Bridge event translation → Dart Backend Stream → Providers → UI

**Critical event loss points:**

| ID | Event | Issue |
|----|-------|-------|
| EVT-1 | NodeCompleted | Sends `bool success` instead of full `NodeStatus` (Success/Failed/Cancelled/Skipped) — UI can't distinguish failure types |
| EVT-2 | TriggerFired | Never transmitted to Dart — UI never shows when triggers fire (HFR exceeded, RMS issues, weather unsafe) |
| EVT-3 | TargetStarted | Rust sends `{name, ra, dec}` but bridge only transmits `target_name` — coordinates lost |
| EVT-4 | StopGuiding, CoolCamera, WarmCamera, Rotator, Park, Unpark, MeridianFlip, WaitTime, Notification, Script, Dome ops, PolarAlignment, Parallel, Conditional, Recovery | No dedicated progress events — UI shows no feedback for these long-running operations |

### Node Type Coverage (Dart → Rust → Events)

| Node Type | Dart Model | Serialization | Rust Execution | Bridge Events |
|-----------|-----------|---------------|----------------|---------------|
| Exposure | Yes | Yes | Yes | Yes |
| Slew | Yes | Yes | Yes | Yes |
| Center | Yes | Yes | Yes | Partial |
| Autofocus | Yes | Yes | Yes | Yes |
| Dither | Yes | Yes | Yes | Yes |
| StartGuiding | Yes | Yes | Yes | Yes |
| StopGuiding | Yes | Yes | Yes | **No event** |
| FilterChange | Yes | Yes | Yes | Yes |
| CoolCamera | Yes | Yes | Yes | **No event** |
| WarmCamera | Yes | Yes | Yes | **No event** |
| Rotator | Yes | Yes | Yes | **No event** |
| Park | Yes | Yes | Yes | **No event** |
| Unpark | Yes | Yes | Yes | **No event** |
| MeridianFlip | Yes | Yes | Yes | **No event** |
| WaitTime | Yes | Yes | Yes | **No event** |
| Delay | Yes | Yes | Yes | Yes |
| Notification | Yes | Yes | Yes | **No event** |
| Script | Yes | Yes | Yes | **No event** |
| Loop | Yes | Yes | Yes | Yes |
| Parallel | Yes | Yes | Yes | **No event** |
| Conditional | Yes | Yes | Yes | **No event** |
| Recovery | Yes | Yes | Yes | **No event** |
| TargetHeader | Yes | Yes | Yes | Yes |
| OpenDome | Yes | Yes | Yes | **No event** |
| CloseDome | Yes | Yes | Yes | **No event** |
| ParkDome | Yes | Yes | Yes | **No event** |
| PolarAlignment | Yes | Yes | Yes | **No event** |
| OpenCover | **No** | **No** | Yes | **No event** |
| CloseCover | **No** | **No** | Yes | **No event** |
| CalibratorOn | **No** | **No** | Yes | **No event** |
| CalibratorOff | **No** | **No** | Yes | **No event** |

### Checkpoint Integration

| Aspect | Status | Detail |
|--------|--------|--------|
| Rust checkpoint save | Working | Saves after each node completion with atomic backup |
| Rust checkpoint resume | Working | Marks completed nodes, skips them |
| Bridge API | Working | set_dir, has_checkpoint, get_info, resume, save, clear |
| **Dart UI for recovery** | **Missing** | No dialog prompts user to resume on startup |
| **Auto-checkpoint interval** | **Missing** | Not configurable from Dart; hardcoded per-node |

### Settings That Don't Propagate

| Setting | Issue |
|---------|-------|
| Dither pixels/settle | Used during serialization but not updateable at runtime — changes mid-sequence have no effect |
| Observer location | Set via `api_sequencer_set_location()` before execution; stale if user changes location post-load |
| Filter focus offsets | Loaded once; no dynamic update during execution |
| Equipment profile | Device IDs baked in at load time; profile switch mid-sequence uses old devices |

### Capabilities Rust Has That Dart Doesn't Expose

| Capability | Detail |
|------------|--------|
| Per-trigger enable/disable | Rust `TriggerManager` supports it; Dart shows triggers as read-only |
| SkipToNode command | Executor has `ExecutorCommand::SkipToNode(id)`; no UI button |
| Safety fail mode configuration | Rust accepts configuration; only called once at startup from Dart |
| Autofocus/centering timeouts | Rust accepts timeout parameters; Dart doesn't expose in node properties |

---

## 5. Bugs & Edge Cases

**No critical bugs found in the engine.**

| ID | Issue | Severity | Detail |
|----|-------|----------|--------|
| BUG-1 | Trigger monitor crash silent | MEDIUM | If trigger monitor task panics, execution continues without safety monitoring |
| BUG-2 | Pathological loop hang | LOW | Loop(Forever) with no children = infinite hang |
| BUG-3 | HFR baseline stale after AF failure | LOW | Degradation trigger keeps old baseline if autofocus fails |
| BUG-4 | Long exposure checkpoint gap | MEDIUM | Crash during 20-min exposure loses all progress since last node completion |
| BUG-5 | No ETA computed | LOW | Progress bar has space for ETA but value is never calculated |

---

## 6. Half-Baked Features

| ID | Feature | What Exists | What's Missing |
|----|---------|-------------|----------------|
| HB-1 | Cover calibrator nodes | Full Rust implementation (4 instructions) | No Dart models, no serialization, no UI property panels — users can't add them to sequences |
| HB-2 | Checkpoint recovery | Backend saves/loads/resumes correctly | No UI dialog prompts user; no "Resume?" on startup |
| HB-3 | Trigger configuration | Rust supports per-trigger enable/disable + thresholds | Dart shows triggers as read-only status; no config UI |
| HB-4 | Skip node command | Executor has SkipToNode(id) | No button in UI to skip to a specific node during execution |
| HB-5 | Snippet system | Tab exists in toolbar, snippet palette widget exists | No obvious way to create/save reusable sub-sequences; unclear documentation |
| HB-6 | Unbounded loop display | "Forever"/"WhileDark" loops work in execution | UI shows no max iteration safety limit, no per-iteration time estimate |
| HB-7 | Equipment status in sequencer | Shows connected/disconnected icons | No live telemetry (camera temp, focuser position, guiding RMS) during execution |

---

## 7. Looks Like It Works But Doesn't

| ID | Feature | Appearance | Reality |
|----|---------|------------|---------|
| FAKE-1 | Time estimation | Shows "6h 30m integration" in toolbar | Only counts raw exposure time — actual duration is 8-10+ hours with overheads |
| FAKE-2 | ETA during execution | Progress bar has space for ETA display | Value is never computed; always empty |
| FAKE-3 | Settings mid-sequence | User can change dither/location settings while running | Changes have no effect — executor keeps stale values from load time |
| FAKE-4 | Unknown node types | Serialization handles all types | Unknown types silently become `{'type': 'Unknown'}` — no error shown to user |

---

## 8. UI Layout & Interaction Issues

| ID | Issue | Severity | Detail | Fix |
|----|-------|----------|--------|-----|
| UI-1 | Drag-and-drop gives no visual feedback | HIGH | No insertion point indicators, no drop zone highlighting — users guess where nodes land | Add dotted-line insertion indicators and highlighted drop zones |
| UI-2 | Node palette disappears on narrow screens | MEDIUM | Auto-collapse when properties panel opens; drag source vanishes mid-drag | Keep palette in overlay during active drag, or use modal approach |
| UI-3 | Tree doesn't auto-scroll to executing node | HIGH | When running, user must manually scroll to find current node in large sequences | Auto-scroll with "follow execution" toggle |
| UI-4 | No execution overlay on tree nodes | HIGH | Running node has no visual indicator in the tree — only in separate progress bar | Add animated border/highlight on currently executing node |
| UI-5 | 50+ if/else chain for node properties | MEDIUM | `node_properties_panel.dart` dispatches with massive conditional — fragile | Refactor to factory pattern or registry map |
| UI-6 | Equipment status shows icons only | MEDIUM | No live values in sequencer view (camera temp, focuser pos, guiding RMS) | Add compact telemetry strip below toolbar |
| UI-7 | Mobile uses different interaction patterns | LOW | Bottom sheets vs panels — switching between phone and desktop is disorienting | Align core patterns; use adaptive layout not separate implementations |
| UI-8 | No batch node operations | MEDIUM | Can't select multiple nodes to copy/paste/delete together | Add multi-select with Ctrl+Click or checkbox mode |
| UI-9 | No inline node comments | LOW | No way to annotate nodes with notes like "Wait for meridian" | Add optional comment field to node model, display as subtitle in tree |
| UI-10 | Snippet creation unclear | MEDIUM | Tab exists but no visible "Save as Snippet" action on selected nodes | Add right-click → "Save as Snippet" on node selection |
| UI-11 | Unbounded loops show no safety info | MEDIUM | "Forever" / "WhileDark" display no max iteration limit or warning | Require explicit safety limit, show warning badge |

---

## 9. Missing Visual Aids

| ID | Feature | Impact | Detail |
|----|---------|--------|--------|
| VIS-1 | Sequence mini-map | MEDIUM | Long sequences require lots of scrolling with no overview — add a thumbnail strip |
| VIS-2 | Color legend | LOW | Nodes are color-coded (target=warning, imaging=primary, mount=info, focus=accent) but nowhere explains what the colors mean |
| VIS-3 | Execution history view | MEDIUM | Can't review past runs from the sequencer screen — no log of previous executions |
| VIS-4 | Conflict highlighting | HIGH | If a filter referenced in an exposure isn't in the wheel, no visual warning until pre-flight validation runs |

---

## 10. Feature Recommendations

### Must Fix (broken or actively misleading)

| ID | Feature | Effort | Detail |
|----|---------|--------|--------|
| MF-1 | Overhead-aware time estimation | Medium | Add configurable per-operation estimates: slew 30s, AF 3min, filter 10s, dither 15s, flip 5min, guide acquire 30s, plate solve 15s. Show "Integration: 6h 30m, Estimated total: 9h 15m" |
| MF-2 | Cover calibrator nodes | Small | Add 4 Dart model classes, 4 serialization handlers, 4 property panels. Simple on/off + brightness operations |
| MF-3 | Fix NodeCompleted event | Small | Change `NodeCompleted { success: bool }` → `NodeCompleted { node_id: String, status: String }` in bridge event.rs. Update Dart handlers |
| MF-4 | Add TriggerFired bridge event | Small | Create new `SequencerEvent::TriggerFired { trigger_id, trigger_name, action }`. Wire executor's trigger events through bridge |
| MF-5 | Checkpoint recovery dialog | Small | On app startup, check `sequencer_has_recoverable_checkpoint()`. If true, show dialog: "Resume sequence [name] from [node]? [Resume] [Discard]" |

### Should Fix (significant UX gaps)

| ID | Feature | Effort | Detail |
|----|---------|--------|--------|
| SF-1 | Real-time validation during editing | Medium | Show validation issues in sidebar as user builds — red/yellow badges on nodes with problems. Don't wait for pre-flight |
| SF-2 | Trigger configuration UI | Medium | Panel showing all available triggers with enable/disable toggles and threshold inputs. Wire to Rust TriggerManager |
| SF-3 | Skip node UI button | Small | Add "Skip" button in execution toolbar. Calls existing `ExecutorCommand::SkipToNode` |
| SF-4 | Progress events for long ops | Medium | Add InstructionProgress events for: CoolCamera (temp progress), WarmCamera, DomeOpen/Close, Rotator (angle progress), PolarAlignment (step progress) |
| SF-5 | Quick-start wizard | Medium | Guided dialog: pick target → select filters → set exposure → configure autofocus → add meridian flip handler → create sequence. Pre-fills based on equipment profile |
| SF-6 | Execution tree overlay | Small | Animated border/highlight on currently executing node. Green = success, red = failed, yellow = running, gray = skipped |
| SF-7 | Auto-scroll to executing node | Small | "Follow execution" toggle that auto-scrolls tree to current node |
| SF-8 | Compute and display ETA | Small | During execution: estimate remaining time from completed frames vs total, adjusted by measured overhead |
| SF-9 | Conflict highlighting during build | Medium | Real-time checks: filter referenced but not in wheel, rotator angle used but no rotator connected, etc. Show warning icon on node |
| SF-10 | Equipment telemetry strip | Small | Compact row below toolbar showing: cam temp, focuser pos, guiding RMS, current filter — live updating during execution |
| SF-11 | Autofocus timeout | Small | Add configurable max-time parameter to autofocus node properties (default 10min) |
| SF-12 | Equipment validation at startup | Small | Before execution starts, poll all configured devices. Fail with descriptive error if any unreachable |

### Would Be Great (differentiators)

| ID | Feature | Effort | Detail |
|----|---------|--------|--------|
| WBG-1 | Visual timeline / Gantt view | Large | Optional view showing sequence as horizontal time blocks. Exposure nodes as bars, slew/AF as gaps. Zoom/scroll. Shows when each phase starts/ends |
| WBG-2 | Dry-run / simulation mode | Large | Execute logic nodes (loops, conditionals, timing) without hardware calls. Shows which branches would be taken, estimated flow. Great for debugging |
| WBG-3 | Post-session statistics | Medium | Summary dialog after sequence completes: total integration, total downtime, frames captured/rejected, trigger fire count, autofocus count, meridian flips, per-target breakdown |
| WBG-4 | Condition-based abort | Small | Add humidity threshold trigger (abort if humidity > X%). Separate from binary weather safe/unsafe. Configurable threshold |
| WBG-5 | Dither pattern selection | Small | Add grid dithering option (N-point grid) alongside random offset. Configurable in dither node properties |
| WBG-6 | Batch node operations | Medium | Multi-select nodes with Ctrl+Click. Copy/paste/delete selection. Paste as children of selected parent |
| WBG-7 | Inline node comments | Small | Optional comment field on every node. Displayed as subtitle in tree view. Helps document sequence logic |
| WBG-8 | Sequence mini-map | Medium | Thumbnail overview of full sequence at bottom of tree panel. Click to navigate. Highlights current execution position |
| WBG-9 | Execution history | Medium | View past sequence runs: date, duration, frames, status. Accessible from sequencer screen. Stored in database |
| WBG-10 | Dynamic target scheduling | Large | During execution, reorder targets based on current altitude/airmass. Pick optimal target when current one sets. Multi-target optimization |

---

## 11. Prioritized Action Plan

### P0 — Fix Immediately (misleading behavior)

| Priority | Action | IDs Addressed |
|----------|--------|---------------|
| P0-1 | Implement overhead-aware time estimation with configurable per-operation estimates | MF-1, FAKE-1 |
| P0-2 | Add 4 cover calibrator node types to Dart + UI | MF-2, HB-1 |
| P0-3 | Fix NodeCompleted event to include full status enum | MF-3, EVT-1 |
| P0-4 | Add TriggerFired bridge event | MF-4, EVT-2 |
| P0-5 | Add checkpoint recovery dialog on app startup | MF-5, HB-2 |

### P1 — Fix This Sprint (significant UX gaps)

| Priority | Action | IDs Addressed |
|----------|--------|---------------|
| P1-1 | Add execution overlay on tree nodes (animated highlight on running node) | SF-6, UI-3, UI-4 |
| P1-2 | Add auto-scroll to executing node | SF-7 |
| P1-3 | Compute and display ETA during execution | SF-8, FAKE-2, BUG-5 |
| P1-4 | Add real-time validation during sequence editing | SF-1, VIS-4, SF-9 |
| P1-5 | Add trigger configuration UI | SF-2, HB-3 |
| P1-6 | Add skip node button | SF-3, HB-4 |
| P1-7 | Add progress events for long-running operations | SF-4 |
| P1-8 | Add quick-start wizard for new users | SF-5 |
| P1-9 | Add equipment telemetry strip | SF-10, UI-6 |
| P1-10 | Add autofocus timeout parameter | SF-11, ENG-F1 |
| P1-11 | Add equipment validation at execution startup | SF-12, ENG-F4 |

### P2 — Fix This Quarter (differentiators)

| Priority | Action | IDs Addressed |
|----------|--------|---------------|
| P2-1 | Visual timeline / Gantt view | WBG-1 |
| P2-2 | Post-session statistics dialog | WBG-3, ENG-F3 |
| P2-3 | Dry-run / simulation mode | WBG-2 |
| P2-4 | Batch node operations (multi-select) | WBG-6, UI-8 |
| P2-5 | Execution history view | WBG-9, VIS-3 |
| P2-6 | Sequence mini-map | WBG-8, VIS-1 |
| P2-7 | Inline node comments | WBG-7, UI-9 |

### P3 — Roadmap (long-term)

| Priority | Action | IDs Addressed |
|----------|--------|---------------|
| P3-1 | Dynamic target scheduling during execution | WBG-10 |
| P3-2 | Condition-based abort (humidity threshold) | WBG-4, ENG-F7 |
| P3-3 | Dither pattern selection (grid dithering) | WBG-5, ENG-F8 |
| P3-4 | Streaming checkpoint updates (every 30s) | ENG-F5 |
| P3-5 | Focus drift detection (HFR plateau) | ENG-F6 |
| P3-6 | Guide star lost trigger | ENG-F2 |
| P3-7 | Guiding calibration validation | ENG-F10 |
| P3-8 | Refactor node property dispatch to factory pattern | UI-5 |
| P3-9 | Improve drag-and-drop with insertion indicators | UI-1 |
| P3-10 | Color legend for node types | VIS-2 |

---

## Appendix: File Locations

### Rust Engine
| File | Lines | Purpose |
|------|-------|---------|
| `native/nightshade_native/sequencer/src/lib.rs` | ~1000 | Types, node definitions, configs |
| `native/nightshade_native/sequencer/src/executor.rs` | ~1900 | Main execution loop, commands, trigger monitor |
| `native/nightshade_native/sequencer/src/node.rs` | ~2200 | Node execution logic, behavior tree traversal |
| `native/nightshade_native/sequencer/src/instructions.rs` | ~3500 | Hardware instruction implementations |
| `native/nightshade_native/sequencer/src/triggers.rs` | ~1000 | Trigger system, state monitoring |
| `native/nightshade_native/sequencer/src/meridian_flip_executor.rs` | ~650 | Meridian flip logic |
| `native/nightshade_native/sequencer/src/checkpoint.rs` | ~350 | Session recovery |
| `native/nightshade_native/sequencer/src/autofocus.rs` | ~550 | Autofocus engine |
| `native/nightshade_native/sequencer/src/flat_wizard.rs` | ~480 | Flat frame automation |
| `native/nightshade_native/sequencer/src/polar_align.rs` | ~400 | Polar alignment |
| `native/nightshade_native/sequencer/src/mosaic.rs` | ~150 | Mosaic panel generation |
| `native/nightshade_native/sequencer/src/temperature_compensation.rs` | ~170 | Focus temp compensation |
| `native/nightshade_native/sequencer/src/focus_prediction.rs` | ~200 | Focus modeling |

### Bridge
| File | Purpose |
|------|---------|
| `native/nightshade_native/bridge/src/sequencer_api.rs` | Sequencer bridge API |
| `native/nightshade_native/bridge/src/sequencer_ops.rs` | Device operations wrapper |
| `native/nightshade_native/bridge/src/real_device_ops.rs` | Real device implementations |
| `native/nightshade_native/bridge/src/event.rs` | Event types including SequencerEvent |

### Dart UI
| File | Lines | Purpose |
|------|-------|---------|
| `packages/nightshade_app/lib/screens/sequencer/sequencer_screen.dart` | ~1471 | Main screen, layout |
| `packages/nightshade_app/lib/screens/sequencer/tabs/templates_tab.dart` | - | 16 built-in templates |
| `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_tree.dart` | - | Tree visualization |
| `packages/nightshade_app/lib/screens/sequencer/widgets/node_properties_panel.dart` | - | Node editor (50+ if/else dispatch) |
| `packages/nightshade_app/lib/screens/sequencer/widgets/instruction_node_properties.dart` | - | 23 property editors |
| `packages/nightshade_app/lib/screens/sequencer/widgets/logic_node_properties.dart` | - | Loop, Conditional, Parallel, Recovery |
| `packages/nightshade_app/lib/screens/sequencer/widgets/target_node_properties.dart` | - | Target Group editor |
| `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_toolbar.dart` | - | Playback controls |
| `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_progress_bar.dart` | - | Running progress display |
| `packages/nightshade_app/lib/screens/sequencer/widgets/equipment_status_widget.dart` | - | Device status icons |
| `packages/nightshade_app/lib/screens/sequencer/widgets/preflight_validation_dialog.dart` | ~593 | Pre-flight checks |

### Dart Core
| File | Purpose |
|------|---------|
| `packages/nightshade_core/lib/src/providers/sequence_provider.dart` | Sequence state management, serialization |
| `packages/nightshade_core/lib/src/services/sequence_repository.dart` | Sequence persistence |
| `packages/nightshade_core/lib/src/services/sequence_file_service.dart` | Import/export |
| `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart` | Data models, estimation |
| `packages/nightshade_core/lib/src/database/daos/sequences_dao.dart` | Database access |
