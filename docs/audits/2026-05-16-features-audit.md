# Features audit — 2026-05-16

Scope: Nightshade v2.5.0 (branch `release/v2.5.0-hardening`, HEAD `74abe34`). Read-only trace of 12 major features end-to-end.

## Summary

- 12 features audited.
- **2 SOLID** — Sequencer, Scheduler engine.
- **4 THIN** — Plate solving, Autofocus, Dither, Polar alignment.
- **3 PARTIAL** — Framing assistant, Mosaic, Flat wizard.
- **1 MISSING-DEP** — Mobile remote control (legacy package name lingers; WebRTC primitives removed; functional surface now lives in headless API server, but mobile services still pull in `nightshade_webrtc` exports as if they signal/pair over WebRTC).
- **2 NEEDS-IMPROVEMENT** — Meridian flip, Catalog overlay.

Cross-cutting findings collected at the end.

## Per-feature deep-dive

### 1. Sequencer

- **Entry point**: `packages/nightshade_app/lib/screens/sequencer/sequencer_screen.dart:47` (`SequencerScreen`); transport buttons in `widgets/sequence_toolbar.dart` (`Start`/`Pause`/`Stop`).
- **Service / orchestrator**: `packages/nightshade_core/lib/src/providers/sequence/sequence_executor.dart:45` (Dart `SequenceExecutor`). Always routes to native engine via `_startNativeExecution(...)` at line 617.
- **Rust engine**: `native/nightshade_native/sequencer/src/executor.rs` (2993 lines) + behavior-tree nodes in `node.rs` (2802) + instructions in `instructions.rs` (3731) + triggers in `triggers.rs` (2382).
- **Dependencies**: Riverpod state, native bridge, drift DB (`sequence_runs`), session provider, disk-space guard.
- **Success path**: Dart serializes nodes → `sequencerLoadJson` → `sequencerStart`. Backend emits `NodeStarted`/`ExposureStarted`/`...Completed` events; Dart mirrors them into `sequenceProgressProvider`. Checkpoint every 30 s (`_startCheckpointTimer`, line 1424). Disk-space watchdog pauses run at blocking threshold.
- **Failure paths**: `SequenceFailed` event → `_finalizeRun('failed')` and records error. Disk-space `blocking` event → `pause()` (does NOT stop, so checkpoint preserved — good).
- **Test coverage**: No Dart unit tests for `SequenceExecutor` itself (only sequence import/save tests). Rust side has 18 `#[test]` blocks in `executor.rs`, 15 in `node.rs`, 39 in `triggers.rs`.
- **Classification**: SOLID
- **Issues**:
  - `_useNativeExecution` setting is read but always coerced — line 606–611 logs a warning that the legacy Dart path is deprecated, but the setting still exists in `AppSettings` and the UI lets the user toggle it. Dead toggle in settings.
  - Native simulation mode is gated behind `kReleaseMode` (line 648) but `_useSimulationMode` is still read in non-release builds; the only way to enable simulation in a packaged build is impossible — fine, but the toggle is still visible in settings and may confuse production users.
  - `_handleSequencerEvent` uses ad-hoc string matching for event type (`'NodeStarted'`, `'ExposureCompleted'`); no compile-time enum. A typo on the Rust side would silently drop events.
  - `_fetchAndDisplaySequenceImage` (line 1114) hardcodes `gain: 0`, `offset: 0`, `binningX: 1`, `binningY: 1` in the `ExposureSettings` it constructs for the UI — these no longer match the actually executed exposure once a sequence uses non-default values. The displayed preview metadata is therefore inaccurate.
  - No structural validation that the JSON `_sequenceToJson` produces matches what `instructions::NodeType` expects. Schema is checked only at run time when Rust deserializes.
- **Recommendations**:
  - REC-1 Delete the legacy Dart-path branch and the `useNativeExecution` setting; the warning at line 607 is a maintenance liability.
  - REC-2 Capture the actual `ExposureSettings` used in the run (already known to the backend) inside `ExposureCompleted` payload so the displayed preview metadata is correct.
  - REC-3 Round-trip a representative sequence through `_sequenceToJson` + Rust deserializer in CI to catch schema drift.

### 2. Plate solving

- **Entry point**: Settings → Plate Solving. Internal callers: centering dialog, framing wizard, polar alignment.
- **Service**: `packages/nightshade_core/lib/src/services/plate_solve_service.dart:53` (`PlateSolveService`).
- **Dependencies**: Backend `apiPlatesolveDetect`/`apiPlatesolveVerify`/`apiPlatesolveGetConfig`/`apiPlatesolveSetConfig` (Rust); local ASTAP/astrometry.net/PlateSolve2 binaries.
- **Success path**: `solveWithFallback()` (line 523) honours user `PlateSolverChoice` (astap/astrometry/auto). Backend solver is tried first via `backend.plateSolve(...)` (line 66); falls back to spawning the binary locally on failure.
- **Failure paths**: `SolverNotAvailableError` for explicit-choice misconfiguration. Backend exception → local fallback at `_solveLocally`. Each local solver returns `PlateSolveResult(success: false, ...)` with diagnostic string.
- **Test coverage**: `packages/nightshade_core/test/services/centering_service_test.dart` exercises the consumer side, but no direct test of `PlateSolveService` parsing logic. ASTAP `.wcs` parsing in `_parseWcsFile` (line 335), astrometry.net output regex in `_parseAstrometryOutput` (line 404), and PlateSolve2 `.apm` parsing in `_parsePlateSolve2Output` (line 626) are all untested.
- **Classification**: THIN
- **Issues**:
  - ASTAP fallback always reports `fieldWidth: 0, fieldHeight: 0, solveTimeSecs: 0` (line 356–367). `centering_service.dart` doesn't use these, but `pixel_scale` is the only useful FOV field — anything that calculates FOV from `fieldWidth * fieldHeight` (e.g. catalog overlay if it ever consumes the local fallback) gets zeros silently.
  - `_parseWcsFile` parses CRVAL/CDELT/CROTA2 but ignores CDELT2 sign and assumes isotropic plate scale (uses only `cdelt1.abs() * 3600`). Drift if user has non-square pixels.
  - PlateSolve2 path (line 267) silently invokes the binary; never validated against a real install. Exit code is not checked (`result` is unused, see `# ignore_for_file: unused_local_variable` at top).
  - Astrometry.net output regex `RA,Dec = ([^,]+),([^)]+)` (line 406) returns pixel scale, rotation, fieldWidth, fieldHeight all `0` — no parsing of `pixscale=`, `Field rotation angle: up is...°`, `Field size: ...`. Same FOV-zero problem.
  - Local solver path doesn't pass `catalogPath` to ASTAP — only the backend probe records it. Heavy users running ASTAP with custom catalog dirs lose that.
  - `solve()` catches **any** exception from the backend and silently retries locally — including programmer errors (e.g. backend OOM). Errors-are-a-feature violation.
- **Recommendations**:
  - REC-1 Add parser unit tests fed by fixtures (golden `.wcs`, golden astrometry.net stdout, golden `.apm`).
  - REC-2 Parse FOV / plate scale from all three solvers; the catalog overlay consumes these.
  - REC-3 Narrow the fallback condition in `solve()` to specific exception types so we don't swallow programmer errors.

### 3. Autofocus

- **Entry point**: `Autofocus` instruction node inside a sequence; UI exposed via the sequence node-properties panel. No standalone screen.
- **Engine**: `native/nightshade_native/sequencer/src/autofocus.rs` (`VCurveAutofocus`, 859 lines). Three methods: VCurve, Quadratic, Hyperbolic.
- **Filter offsets**: applied by `apply_filter_focus_offset()` in `instructions.rs:2038` after a filter change.
- **Temperature compensation**: `temperature_compensation.rs` (Rust) + `focus_model_service.dart` (Dart linear regression for the temperature model, stored as JSON in app docs dir).
- **Dependencies**: Connected focuser + camera. Focus temperature read from focuser device.
- **Success path**: Sweep `steps_out * step_size` outward, then inward; fit V-curve/parabola; move with backlash compensation; publish `AutofocusComplete`.
- **Failure paths**: `AutofocusConfig::max_duration_secs` (default 600 s) aborts a stuck run. Outlier rejection at `outlier_rejection_sigma`. Returns synthetic `AutofocusResult` with `curve_fit_quality < threshold`.
- **Test coverage**: 7 `#[test]` blocks in `autofocus.rs`, 3 in `focus_prediction.rs`. Dart side: `test/services/focus_model_service_test.dart`.
- **Classification**: THIN
- **Issues**:
  - `FocusModelService._calculateTemperatureModel` (line 264) rejects models with slope `|m| > 500 steps/°C` (line 305) — magic number, not configurable, undocumented in UI.
  - `FocusModel.isReliable` requires `rSquared >= 0.7 && dataPointCount >= 5` (line 79) — both magic numbers, not surfaced to the user. A user with 4 high-confidence points still sees no auto-focus prediction.
  - `apply_filter_focus_offset` (`instructions.rs:2038`) only fires on `ChangeFilter` instruction — if a filter is set inside an `ExposureNode` (which the Rust executor *does* allow as `filter_index`), the offset is NOT applied. Inconsistent behaviour.
  - Filter-offset *autodetection* (Dart `_updateFilterOffsets`, `focus_model_service.dart:335`) requires `referenceFilter` to be set explicitly; if the user never sets one, no offsets are derived even with hundreds of data points.
  - The `confidence < 0.5` filter-offset gate at `predictFocusPosition` (line 414) silently disables offset application — user sees no UI indication of why their previously-learned offset isn't being used.
  - The 60-poll × 500 ms = 30 s timeout in `apply_filter_focus_offset` (`instructions.rs:2094`) is hardcoded; not configurable for slow USB-Focus-Pro–style motors.
  - `apply_filter_focus_offset` returns silently after `Failed to apply focus offset` (line 2079) — the next exposure proceeds with the wrong focus. Should surface as a warning event at minimum.
- **Recommendations**:
  - REC-1 Move magic thresholds (`|slope| > 500`, `rSquared >= 0.7`, `dataPointCount >= 5`, `confidence >= 0.5`) into `SequencerDefaults`/`AppSettings` with documented defaults.
  - REC-2 Emit `FocusOffsetApplied`/`FocusOffsetFailed` events so the operator can see filter-offset behaviour in the live log.
  - REC-3 Also call `apply_filter_focus_offset` when an `ExposureNode` sets a filter via `filter_index` without an explicit `ChangeFilter` node.

### 4. Dither

- **Entry point**: `DitherNode` in sequencer (UI: `node_properties_panel.dart`), or `ditherEvery` on `ExposureNode`, or `RecoveryAction::Dither` from a trigger.
- **Implementation**: `native/nightshade_native/sequencer/src/instructions.rs:1655` (`execute_dither`). Settings flow through `RuntimeConfig.dither` so a settings change mid-sequence is honoured on the next dither (audit §1.8 backport).
- **Settle parameters**: `settle_pixels`, `settle_time`, `settle_timeout`, `ra_only` plumbed all the way through.
- **Dependencies**: PHD2 (or compatible) reachable via `ctx.device_ops.guider_dither(...)`.
- **Success path**: `Random` pattern picks a magnitude `config.pixels`; `Grid` pattern walks an `NxN` lattice indexed by `TriggerState.next_grid_dither_offset(...)`.
- **Failure paths**: `guider_dither` returns `Err(e)` → `InstructionResult::failure(...)`. Sequence-level recovery is triggered only if a recovery node wraps the dither. Otherwise the run continues to the next exposure.
- **Test coverage**: None in Rust directly. PHD2 simulator integration test exists for the protocol but not for `execute_dither`.
- **Classification**: THIN
- **Issues**:
  - Once `guider_dither` is called, the cancellation token is no longer polled (line 1742 logs "no way to interrupt guider_dither once it's running"). A user-initiated Stop during a 60 s dither settle hangs.
  - Grid pattern collapses to a scalar magnitude before handing to the guider (line 1696) because PHD2's `dither()` API only takes a magnitude — the comment acknowledges this but the resulting random-direction dither defeats the spatial-coverage purpose of grid mode.
  - `Grid dither at center position, skipping` (line 1702) returns a synthetic success — but emits no `TriggerFired`/diagnostic event. The frame following this dither has identical pointing to the previous; if the user wonders why two consecutive frames are bit-identical, there's no breadcrumb.
  - `DitherNode`'s `ditherEvery` interacts with `ExposureNode.ditherEvery` and `defaults.ditherPixels` — three sources of truth. UI-level surface mixes them confusingly: `_sequenceToJson` always overrides per-node settle values with `defaults.*` (lines 165–168) regardless of whether the user customised the node.
- **Recommendations**:
  - REC-1 Add a Tokio `select!` so cancellation can interrupt the in-progress `guider_dither` (PHD2's `stop_capture` is the right API to call).
  - REC-2 Emit `DitherSkipped` event for the grid-center case so the UI log shows it.
  - REC-3 Resolve the per-node vs defaults precedence and surface it in the node properties panel.

### 5. Meridian flip

- **Entry point**: `MeridianFlipNode` in a sequence, or `TriggerType::MeridianFlip` fired automatically from `triggers.rs:206`.
- **Service**: `native/nightshade_native/sequencer/src/meridian_flip_executor.rs:94` (`MeridianFlipExecutor`).
- **Pre-checks**:
  - Target altitude ≥ `MIN_POST_FLIP_ALTITUDE_DEG = 10.0` (constant, line 130).
  - Cover state ≠ closed/moving (audit §1.19 backport, line 197).
  - Capture pre-flip tracking + pier side + coordinates for safe cancel and pier-side-Unknown fallback.
- **Success path**: `build_step_sequence` (line 509) → PausingGuider → StoppingTracking → SlewingToTarget → VerifyingPierSide → ResumingTracking → (PlateSolvingAndCentering) → (Refocusing) → (ResumingGuider) → Settling. Calls `TriggerState::mark_flip_performed` on success.
- **Failure paths**: Up to `max_retries` attempts with delays from `retry_delays_secs`. Then runs `execute_failure_action` which can park, stop tracking, or abort the sequence. Failure-action errors are surfaced (audit §1.10).
- **Test coverage**: 9 `#[test]` blocks in `meridian_flip_executor.rs`, 8 in `meridian.rs`, 8 in `meridian_events.rs`. Good coverage on edge cases (pier-side-Unknown, retry exhaustion, cover-closed refusal).
- **Classification**: NEEDS-IMPROVEMENT
- **Issues**:
  - `MIN_POST_FLIP_ALTITUDE_DEG = 10.0` is a constant; users with a clean horizon or those at high latitudes near circumpolar targets cannot tighten/loosen it.
  - `FLIP_COORDINATE_TOLERANCE_DEG = 1.0/60.0` (1 arcmin) is also a constant; high-precision PMC-Eight users want tighter, low-end star-tracker users may need looser.
  - `SAFETY_ACTION_RETRY_COUNT = 3` and `SAFETY_ACTION_RETRY_DELAY_SECS = 5.0` (lines 40, 43) — both constants.
  - Cover state values are integer-coded `1=Closed, 2=Moving, 3=Open, 0=NotPresent, 4=Unknown, 5=Error` (line 197); the comment hints at this but a typed enum on the Rust side would be safer.
  - Observer location unavailable path (line 186) only logs a warning and proceeds — defeats the altitude pre-check. The pre-flight dialog should refuse to arm meridian flip with no observer location set.
  - The `instruction-path` legacy implementation was unified into this executor (audit §1.6) — verify the legacy `instructions::execute_meridian_flip` is no longer reachable. Did not trace this end-to-end.
- **Recommendations**:
  - REC-1 Move `MIN_POST_FLIP_ALTITUDE_DEG`, `FLIP_COORDINATE_TOLERANCE_DEG`, `SAFETY_ACTION_RETRY_*` into `MeridianFlipConfig` with sane defaults.
  - REC-2 Refuse to arm the trigger when observer location is unset; surface a pre-flight error rather than silently bypassing the altitude check.
  - REC-3 Replace integer cover state with a typed enum mirroring the ASCOM CoverStatus enum.

### 6. Polar alignment

- **Entry point**: `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart:51` (`_startAlignment`). Two modes: TPPA and All-Sky.
- **Service**: `packages/nightshade_core/lib/src/services/polar_alignment_service.dart:16` — thin wrapper around `backend.startPolarAlignment` / `backend.startAllSkyPolarAlignment`.
- **Rust**: `sequencer/src/polar_align.rs` (TPPA, 790 lines), `sequencer/src/all_sky_polar.rs` (All-Sky, 1113 lines).
- **Acceptance**: 30″ default; configurable via `PolarAlignmentConfig.autoCompleteThreshold` (`polar_alignment_config.dart:130`). All-Sky requires 3 consecutive iterations below threshold (`AUTO_COMPLETE_HOLD_SECS`).
- **Iteration cadence**: All-Sky `iterationCadenceSecs` defaults to `3.0` and floor of `0.5` (`polar_alignment_service.dart:78`).
- **Dependencies**: Plate solver (ASTAP) — all-sky errors with `PolarAlignError::SolverUnavailable` if no solver.
- **Test coverage**: 2 `#[test]` blocks in `polar_align.rs`, 12 in `all_sky_polar.rs`. No Dart-side test of the service or screen.
- **Classification**: THIN
- **Issues**:
  - TPPA `PolarAlignConfig::default()` (line 86) sets `auto_complete_threshold: 30.0` — same default as all-sky but UI's `PolarAlignmentConfig.quickStart()` does NOT set it (`polar_alignment_config.dart:193`), so the user's `quickStart()` config inherits the Freezed default of 30.0 — works, but a user customising `highPrecision()` to 10″ may be confused that the rust side reads `auto_complete_threshold` from the JSON, not from a service-level argument.
  - `PolarAlignmentService.threePoint` does **not** forward `autoCompleteThreshold` to the bridge (`polar_alignment_service.dart:32-44`) — only exposure/step/etc. The `autoCompleteThreshold` from the config is therefore silently ignored for TPPA. This is a **bug** — only the all-sky path passes it (line 91).
  - The `mounted` check in the polar alignment screen's listener uses Riverpod's lifecycle; verify the `_pulseController` isn't leaked if the user pops the screen mid-alignment.
  - No retry on transient solve failures during all-sky — `PolarAlignError::SolveFailed` propagates and the run aborts (`all_sky_polar.rs`). A passing cloud would force a restart.
  - `binning.unwrap_or(2)` in TPPA but `binning.unwrap_or(1)` in instructions elsewhere — inconsistent default per the `unwrap_or` policy comment.
  - The Northern/Southern hemisphere flag is captured but no fallback if the user mis-sets it — the alignment proceeds with wrong sign and shows wildly wrong arrows.
- **Recommendations**:
  - REC-1 **Fix**: pipe `autoCompleteThreshold` through to `backend.startPolarAlignment` for TPPA. Currently dead user setting.
  - REC-2 Add transient-solve retry (single retry with shorter exposure) inside the all-sky loop.
  - REC-3 Auto-detect hemisphere from observer latitude rather than rely on a user toggle.

### 7. Framing assistant

- **Entry point**: `packages/nightshade_app/lib/screens/framing/framing_screen.dart:23` (`FramingScreen`).
- **Service / state**: `packages/nightshade_core/lib/src/providers/framing_provider.dart` (`FramingNotifier`).
- **Survey image fetch**: `loadSurveyImage` at framing_provider.dart:616. Primary: Aladin HiPS2FITS (`alasky.cds.unistra.fr`); fallback: NASA SkyView. Both use plain `http.Client()` with default timeout (none).
- **Mosaic panel layout**: deferred to `MosaicService.generatePanels` (see feature 8).
- **Dependencies**: Internet (Aladin/SkyView), SIMBAD resolver for target search, planetarium catalog for suggestions.
- **Test coverage**: `packages/nightshade_app/test/framing/framing_altaz_test.dart` — alt/az math only. No service / provider test, no survey-fetch test (which is hard, but at least URL-builder tests would help).
- **Classification**: PARTIAL
- **Issues**:
  - `_cacheImage` in `framing_screen.dart:495` just shows a snackbar — does NOT save the survey image anywhere. Dead button. Direct quote: `// Would save image to local cache`.
  - `loadSurveyImage` HTTP calls have **no timeout** — a hung CDS server leaves `isLoadingImage = true` forever. The user sees a spinner with no escape.
  - Fallback to SkyView (line 685) is silent on Aladin HTTP errors but not on Aladin network errors (those just throw and skip the fallback path). The `catch (e)` at line 720 sets `imageError` without trying SkyView.
  - Hardcoded image size `width=800` (line 743). Aspect ratio is computed but resolution is fixed regardless of available canvas size — high-DPI displays show a blurry preview.
  - SkyView URL builder (line 747) assumes `runquery.pl` returns an inline JPEG; SkyView normally returns a redirect to a generated FITS/JPEG file. This second-tier fallback is likely **broken** but masked by the rarity of Aladin failure.
  - Equipment FOV branch (lines 633–647) silently changes between "use preview FOV" vs "use equipment * 2.5" based on a `previewFov > equipmentWidth` comparison — opaque to users.
  - `FramingTarget.raDegrees` referenced in `_buildAladinUrl` but `raHours` is in the model — verify the implicit conversion is consistent.
- **Recommendations**:
  - REC-1 Implement `_cacheImage`: write `surveyImageBytes` to a deterministic cache path keyed by `(raHours, decDegrees, surveySource, fov)` and load from cache before fetching on subsequent loads.
  - REC-2 Add a 30 s timeout to both HTTP requests; fall through to SkyView on Aladin failure (network OR HTTP).
  - REC-3 Verify and fix the SkyView fallback URL — it is unlikely to work as-is. At minimum, add a single integration-level test.

### 8. Mosaic

- **Entry point**: Framing screen → Mosaic panel section → "Add to sequence" button. Also `MosaicWizardDialog` in sequencer.
- **Service**: `packages/nightshade_core/lib/src/services/mosaic_service.dart:133` (`MosaicService`).
- **Panel generation**: pure Dart spherical geometry with cos(dec) RA-compression correction (line 187). Validates overlap (5–50% advisory range), grid size (>20 warning), pole proximity (`|dec|>80°` warning).
- **Capture loop integration**: `createMosaicSequence` (line 325) emits a `TargetHeaderNode` per panel with optional `AutofocusNode`, `SlewNode`, `CenterNode`, `LoopNode(ExposureNode + DitherNode)`, and serpentine ordering.
- **Test coverage**: `packages/nightshade_core/test/services/mosaic_service_test.dart` — exists. `packages/nightshade_planetarium/test/mosaic_planner_test.dart` covers a separate planetarium-side planner.
- **Classification**: PARTIAL
- **Issues**:
  - No scheduler integration — the scheduler's `buildSequenceForCandidate` (scheduler_engine.dart:920) builds a *single* target sequence with no awareness of mosaic panels. If the user adds a mosaic target to the scheduler, the scheduler will image only the first panel; subsequent panels are ignored.
  - `MosaicConfig.rotation` is honoured for panel layout but the generated `TargetHeaderNode.rotation` (line 438) is set only when `rotation != 0.0` — non-default rotation is preserved but zero-rotation is dropped (null), which is fine if the sequencer treats null as "don't enforce" but ambiguous.
  - `_intToBinningMode(binning)` (line 145) silently degrades any binning > 4 to `BinningMode.one`. A user passing binning=5 (some QHY cameras support 8) sees their setting silently changed.
  - Dither pixels falls back to `3.0` (line 403) when `options.ditherPixels == null` — hardcoded, not pulled from `SequencerDefaults`.
  - `checkVisibilityConstraints` only checks at `startTime` — no end-of-night check. A mosaic that takes 6 hours but is below horizon at hour 4 is not flagged.
  - Total imaging time estimate (`estimateMosaicTime`, line 249) uses a `overheadPerPanelSecs = 60.0` default — typical real overhead with center-after-slew + autofocus is several minutes per panel.
- **Recommendations**:
  - REC-1 Teach the scheduler to either (a) refuse mosaic targets, or (b) iterate panels with proper state restore.
  - REC-2 Pull dither defaults from `SequencerDefaults` instead of hardcoded `3.0`.
  - REC-3 Replace `overheadPerPanelSecs = 60.0` with a measured estimate from the equipment profile (or actual recent history).
  - REC-4 Throw on unsupported binning rather than silently degrading.

### 9. Scheduler

- **Entry point**: Plan Tonight → Scheduler tab (`scheduler_tab_content.dart` in planner widgets). Old `/scheduler` route redirects to `/planner?tab=scheduler` (`scheduler_screen.dart:7`).
- **Engine**: `packages/nightshade_core/lib/src/services/scheduler/scheduler_engine.dart:110` (`SchedulerEngine`, 1104 lines). Pure-logic core; provider wiring in `scheduler_provider.dart`.
- **Inputs**: `SchedulerCandidate` per target (priority, goals, captured counts, hard constraints, horizon profiles, available filters).
- **Scoring**: altitude (sin² ramp), meridian proximity, moon avoidance, time-remaining, filter coverage, user priority, optional scheduled-window boost. Weights are `SchedulerWeights` in `SchedulerConfig`.
- **Hysteresis**: `_config.hysteresisRatio` (defaults to >1.0) prevents thrashing between similar-scored targets.
- **Constraints**: time window, moon illumination max, custom horizon, scheduled window — all validated per-candidate.
- **Test coverage**: `packages/nightshade_core/test/services/scheduler/scheduler_engine_test.dart` + `sky_calculations_test.dart` + `target_progress_service_test.dart`. Plus `scheduler_service_test.dart` for the static helper. UI: `scheduler_screen_test.dart`, `scheduler_tab_content_test.dart`.
- **Classification**: SOLID
- **Issues**:
  - Lunar ephemeris (`_moonPosition`, line 1031) is the Meeus low-precision formulation — accurate to ~0.5° in RA which is plenty for separation checks but worth documenting at the call sites.
  - `_userPriorityFactor` assumes priority is 0..10 and clamps (line 898). The `targets.user_priority` column accepts wider integers; values like 100 saturate to 1.0, which could surprise users coming from RoboTarget that use 0..100.
  - `_filterCoverageFactor` returns 0.5 for goal-less targets (line 882) — comment says "neutral so they aren't ranked above an actively-incomplete target", but a fully-imaged-but-with-no-goals target also scores 0.5, which feels wrong.
  - The pre-built dispatched sequence (`buildSequenceForCandidate`, line 920) always picks the SINGLE filter with the largest remaining count (line 934). If user goals are L/R/G/B all equal-remaining, the scheduler will only image L this tick, switch to R next tick (after hysteresis), etc. Filter loops within a target (LRGB cycles) are not generated.
  - `tickInterval` default not visible at this site — verify `SchedulerConfig.defaults` ticks at a sane interval; if it's <30 s, frequent re-evaluations can cause thrashing under near-equal scores even with hysteresis.
- **Recommendations**:
  - REC-1 Generate a multi-filter exposure loop in `buildSequenceForCandidate` so a single dispatch cycles through all needed filters instead of one-filter-at-a-time.
  - REC-2 Document the Meeus precision in the moon-separation user setting.
  - REC-3 Distinguish goal-less from goal-complete in `_filterCoverageFactor` (e.g. complete → 0.1, no-goals → 0.5).

### 10. Flat wizard

- **Entry point**: `packages/nightshade_app/lib/screens/flat_wizard/flat_wizard_screen.dart:20`. Three tabs: Quick / Batch / Sky Flats.
- **Service**: `packages/nightshade_core/lib/src/services/flat_wizard_service.dart:51` (`FlatWizardService`). Plus `FlatExposureCalculator` and `SkyBrightnessTracker` helpers.
- **Rust**: `sequencer/src/flat_wizard.rs` exists (831 lines) — provides a sequencer-friendly flat-capture instruction.
- **ADU target / tolerance**: handled in `FlatWizardState.globalSettings` (default histogram target 50%, tolerance 10%).
- **Dependencies**: Connected camera + filter wheel. NO cover/calibrator integration in the service (`Grep` for `calibrator|cover` in `flat_wizard_service.dart`: 0 matches).
- **Test coverage**: NONE for the service directly. UI tests not present either.
- **Classification**: PARTIAL
- **Issues**:
  - **No cover/calibrator integration in the service path**. The Rust sequencer has `CalibratorOnNode`/`OpenCoverNode` instructions (`sequence_executor.dart:395-415`), but `FlatWizardService` does not orchestrate them: a user using the flat wizard on a connected flat panel must manually open the cover and turn on the panel; the wizard does not do it for them.
  - `quickCalibrate` (line 638) hardcodes `minExposure: 0.001, maxExposure: 30.0, maxIterations: 8` — not configurable from UI, not in settings.
  - Frame readout / download timeout `_imageDownloadTimeout = Duration(seconds: 60)` (line 53) — silent timeout; if the image takes longer (full-frame full-well CMOS), the wizard reports "Failed to retrieve test frame" and discards the data.
  - `gain: 0, offset: 0` hardcoded in `captureTestFrame` (line 136). The user's camera-preset gain is **ignored** — flats taken at gain=0 will not calibrate lights taken at gain=100. **Significant correctness issue**.
  - `calibrateMultipleFilters` (line 463) only `developer.log`s when a filter fails — the user gets a warning in the log but the wizard's UI does not surface "Failed to calibrate filter X".
  - No dark-flat support — the `FrameType.darkFlat` enum exists (`imaging_models.dart:12`) but the wizard never produces darkFlat frames; the only output is `FrameType.flat`.
  - `generateFlatSequence` (line 519) — sequence nodes are not wrapped in cover/calibrator open/close instructions, even when a cover is connected. The generated sequence assumes the user manually preps the calibrator.
  - HFR / sky-brightness handling in `calibrateFilterWithRateTracking` is correct in principle but never tested against real twilight data.
- **Recommendations**:
  - REC-1 **Critical fix**: read the user's gain/offset from the active equipment profile or the previous light-frame run, not hardcoded `0`.
  - REC-2 Add cover/calibrator orchestration: if connected, open + set brightness before capture; close after.
  - REC-3 Add dark-flat capture (covered exposures matching each calibrated flat exposure) as a checkbox in the wizard.
  - REC-4 Surface filter-level failures to the UI.
  - REC-5 Add unit tests for `calculateNextExposure` ratio clamping logic and `_lookupFilterIndex`.

### 11. Catalog overlay

- **Entry point**: Imaging tab toolbar → overlay toggle. Provider: `catalogOverlayEnabledProvider` (`catalog_overlay_provider.dart:14`).
- **Service**: `packages/nightshade_core/lib/src/services/catalog_overlay_service.dart:191` (`CatalogOverlayService`).
- **WCS projection**: `packages/nightshade_core/lib/src/services/wcs/gnomonic_projection.dart` (real TAN projection, not small-angle approximation).
- **Sources**: `OpenNgcDsoCatalog` (DSOs) + `HygStarCatalog` (stars), both from `nightshade_planetarium`.
- **FOV bbox**: `GnomonicProjection.computeBoundingBox` with pole-touching detection (line 314).
- **Test coverage**: `packages/nightshade_core/test/services/catalog_overlay_service_test.dart` + `catalog_overlay_perf_test.dart` + widget test in `packages/nightshade_app/test/widgets/catalog_overlay_widget_test.dart`. Reasonable coverage.
- **Classification**: NEEDS-IMPROVEMENT
- **Issues**:
  - `maxObjects = 500` (line 199) is a hard cap; the magnitude downsample cutoff is surfaced in the result (`downsampleMagnitudeCutoff`) but the UI does not auto-decrement the user's magnitude limit when the cap fires — operators see a sudden missing-galaxy when they pan toward Virgo Cluster.
  - `_hitRadiusForArcmin` (line 420) uses `base = 18.0` and `scaled = base + 6.0 * arcmin.clamp(0, 600)` — a 600 arcmin object gets a hit radius of 3618, clamped to 320. The `6.0 *` multiplier appears arbitrary; not justified by typical pixel scales.
  - `_starToObject` hardcodes `hitRadius: 18` (line 381) regardless of magnitude — bright stars deserve a larger click target than 14th-mag stars.
  - DSOs without magnitude are kept iff `dso.isMessier` (line 322). NGC/IC objects with no magnitude are silently dropped — there are ~3500 such objects in OpenNGC (planetary nebulae, dark nebulae) that legitimately have no V-mag. They never appear on the overlay.
  - Catalog availability check (line 220) is per-call, not cached. `PlanetariumCatalogOverlaySource.isAvailable` does an async file-existence check on both DSO and star catalog files for every query.
  - The bounding-box `paddingFraction = 0.05` (5%) is hardcoded — for very large nearby galaxies (Andromeda, LMC) with extents larger than the FOV, the centre may be just off-frame at >5% and miss the catalog hit.
- **Recommendations**:
  - REC-1 Cache the result of `CatalogOverlaySource.isAvailable` after first success.
  - REC-2 When `downsampleMagnitudeCutoff` fires, expose the cutoff in the HUD ("Showing top 500 of 1278 — mag ≤ 11.4").
  - REC-3 Make `_hitRadiusForArcmin` curve and `paddingFraction` configurable; revisit defaults.
  - REC-4 Keep NGC/IC objects of recognised types (nebula, cluster, planetary nebula) even without a magnitude.

### 12. Mobile remote control

- **Entry points**: `apps/mobile/lib/main.dart`. Discovery on `apps/mobile/lib/screens/qr_scanner_screen.dart`. Sequence hooks: `apps/mobile/lib/services/mobile_sequence_hooks.dart`.
- **Services consumed**: `nightshade_webrtc/nightshade_webrtc.dart` re-exports `discovery.dart`, `secure_discovery.dart`, `token_manager.dart`, `channel_encryption.dart`, `paired_devices_table.dart`, `pairing_database.dart`.
- **Header on the package** (`nightshade_webrtc.dart:7-11`): "The package no longer ships WebRTC peer-connection or signaling primitives (deleted in §2.3 audit 2026-05-09); live remote control runs over REST + WebSocket via headless_api_server.dart."
- **Command authority / event mirroring**: actual command surface lives in `apps/desktop/lib/headless_api_server.dart` (3358 lines) + `headless_api/auth/pairing_service.dart` + `headless_api/auth/pairing_attempt_tracker.dart`.
- **Test coverage**: `packages/nightshade_webrtc/test/` has 4 tests: `channel_encryption_test.dart`, `live_collaboration_session_test.dart`, `server_compatibility_test.dart`, `token_manager_test.dart`. No end-to-end test of the mobile→desktop command path. No test of `MobileSequenceHooks`.
- **Classification**: MISSING-DEP (in the sense that the documented stack — WebRTC — no longer exists; the actual stack is REST+WS but lives split across `nightshade_webrtc` (auth/discovery primitives), `apps/mobile/lib/services/network_service.dart` (client), and `apps/desktop/lib/headless_api_server.dart` (server). Cross-cutting concern).
- **Issues**:
  - Package name `nightshade_webrtc` is now misleading. Header comment acknowledges it but every downstream that grep-finds it still thinks WebRTC is involved.
  - The mobile `network_service.dart` checks `connectivityResult is List` to handle both `connectivity_plus 5.x` and `6.x` (line 96–100) — defensive, but probably one of these branches is dead and contributing to confusion.
  - `MobileSequenceHooks._setupEventNotifier` rebuilds the notifier on backend change, but the test pyramid does not cover the case where `disconnect → reconnect → re-subscribe`; if that path silently drops events, a paired phone could miss a critical weather-abort.
  - `PairingDatabase` lives in `nightshade_webrtc/lib/src/database/` but is consumed by `headless_api/auth/pairing_service.dart` in the desktop app — circular naming.
  - There is no documented "command authority" model. If two paired phones connect at once, who has authority to issue `sequencer/start`? Server-side scope is `admin|viewer` (see `HeadlessTokenScope` in `headless_api_server.dart`), but the conflict-resolution policy isn't tested.
  - `_pushNotificationSubscription` in `mobile_sequence_hooks.dart:22` only activates when `backend is NetworkBackend`. A user using the mobile app standalone (FfiBackend on Android — if/when that becomes supported) would silently lose push notifications. Today this is acceptable but flagged.
- **Recommendations**:
  - REC-1 Rename the package to `nightshade_remote_protocol` (or similar) and migrate downstreams. The current name is technical debt that creates ongoing confusion in audits and CI logs.
  - REC-2 Write a single end-to-end test: spin up `HeadlessApiServer` in-process, drive a paired client through the `MobileSequenceHooks` event subscription, verify a `SequenceFailed` desktop event reaches the mobile notifier within X seconds.
  - REC-3 Document the multi-phone command authority model and add a server-side test that two admin clients cannot issue conflicting commands simultaneously (or document explicitly that last-write-wins is the contract).
  - REC-4 Drop the `connectivity_plus 5.x` compatibility branch once the pubspec is pinned to 6.x.

## Cross-cutting findings

1. **Magic-number defaults scattered across the codebase**: `MIN_POST_FLIP_ALTITUDE_DEG=10.0`, `SAFETY_ACTION_RETRY_COUNT=3`, `FLIP_COORDINATE_TOLERANCE_DEG=1/60`, `maxObjects=500` (catalog), `slope > 500 steps/°C` (focus model), `rSquared >= 0.7`, `dataPointCount >= 5`, `confidence >= 0.5`, `paddingFraction = 0.05`, `_imageDownloadTimeout = 60s` (flat wizard), `_reevaluationDebounce = 500ms` (scheduler), `dither pixels fallback = 3.0` (mosaic), `overheadPerPanelSecs = 60.0` (mosaic). Most are not user-configurable and not documented in `RUNBOOK.md`. Consolidate into a `defaults.toml`/`SequencerDefaults` table with provenance comments.

2. **Silent fallback patterns** that violate the project's "errors are a feature" rule, found in:
   - `PlateSolveService.solve` (catches **any** backend exception and retries locally).
   - `FlatWizardService.captureTestFrame` (returns null on timeout instead of throwing).
   - `apply_filter_focus_offset` (logs and returns; next exposure runs without the offset).
   - `MobileSequenceHooks._setupEventNotifier` (DisconnectedBackend → notifier null).
   - Framing `_cacheImage` (snackbars success without doing anything).

3. **Hardcoded gain/offset in calibration paths**: `captureTestFrame` in flat wizard (`gain: 0, offset: 0`) and `_fetchAndDisplaySequenceImage` in sequence executor (`gain: 0, offset: 0, binningX: 1, binningY: 1` for display metadata). The display metadata case is cosmetic; the flat-wizard case is a real correctness bug.

4. **Settings-flow inconsistency**: `SequencerDefaults` (dither pixels, settle params) is read into `_sequenceToJson` and always overrides per-node values. The UI lets users set per-node values that are then silently ignored.

5. **`autoCompleteThreshold` for TPPA is a dead user setting** — the service does not forward it to the backend (`polar_alignment_service.dart:32-44`). The all-sky path correctly forwards it.

6. **No end-to-end "happy path" integration tests** for: sequencer (Dart side), meridian flip (mobile-triggered), flat wizard, mobile→desktop sequencer control. Rust-side unit tests are dense but the Dart↔Rust seam is under-tested.

7. **Naming debt**: `nightshade_webrtc` no longer ships WebRTC. `SchedulerScreen` is reachable in tests but redirects in production. `_useNativeExecution` setting is read but always coerced. These dead toggles and stale package names accumulate.

8. **Hemisphere flag is unverified user input** for polar alignment. The observer location is known; the hemisphere is therefore derivable. Surfacing it as a user toggle is a footgun.

9. **Cover / calibrator integration is incomplete**: meridian flip checks for closed cover (good), but the flat wizard does **not** open the cover or turn on the calibrator. A user with both connected gets the worst of both worlds.

10. **Mosaic + scheduler do not compose**: a mosaic target added to the scheduler images only the first panel. Either compose them or refuse mosaic targets at the scheduler boundary.
