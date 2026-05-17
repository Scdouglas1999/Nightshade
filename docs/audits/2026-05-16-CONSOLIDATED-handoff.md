# Nightshade v2.5.0 — Consolidated Audit Handoff

**Branch:** `release/v2.5.0-hardening`
**HEAD at audit time:** `74abe34`
**Audit date:** 2026-05-16
**Authoring agents:** A1-SETTINGS, A2-FEATURES, A3-PROVIDERS, A4-NAV, A5-DEAD-UI (all read-only)

This document is **self-contained**. You do not need to read the 5 source audit docs unless you want extra context — every finding here cites concrete file:line evidence and a one-sentence fix direction. Source docs live next to this file (`2026-05-16-{settings,features,providers,nav,dead-ui}-audit.md`).

---

## 0. Read this first

### What's already done (don't re-do)

- 80+ agent commits across audit-driven Waves 0-4 + reviewers landed before this audit ran.
- CQ Roadmap Waves W3-W15 hardened code quality: split god-files, swept ~416 `unwrap_or` sites, ~679 `print` calls, ~2246+ behavioral markers, ASCOM/INDI/Alpaca/8 vendor SDKs SAFETY-commented, sealed-class `SequenceNode`, autoDispose audit, MediaQuery granularization, `-D warnings` + `-D undocumented_unsafe_blocks` + `-D await_holding_lock` + `-D result_unit_err` enforced in CI, audit gates required for PR merge.
- F1-F5 polish features landed: end-of-session report + multi-night campaign roll-up, mobile push notifications, disk-space guard, onboarding wizard, plate-solve catalog overlay.
- A5 dead-UI audit confirmed **0 CLAUDE.md placeholder violations**, **0 user-visible "coming soon" copy**, **0 dead empty handlers**, **10/10 sampled behavioral markers matched**.

This audit was triggered by the user saying "the app works, but there's a lot to track — find what's broken or dead." Findings represent **gaps the prior cycle's static gates couldn't detect** (e.g., a setting is "wired" syntactically because the setter exists, but no reader consumes the persisted value).

### Ground rules (non-negotiable, from `CLAUDE.md`)

- **No stubs/placeholders.** If you start a fix, finish it. Never leave `// TODO` or `unimplemented!()`.
- **Errors propagate.** Silent fallbacks hide bugs. If a fallback is genuinely correct, write a `// Why:` comment.
- **WHY-style comments only.** Don't write WHAT-style comments (the code already says what).
- **No emojis in code.**
- **Don't run FRB codegen** (`flutter_rust_bridge_codegen generate`) unless the work explicitly requires it. Most fixes here are Dart-only.
- **`melos run generate` is allowed** for freezed/drift/json_serializable codegen after Dart model edits.
- **Don't push to remote** unless asked.

### CRITICAL — Fix direction policy

**The default for every finding in this document is to MAKE THE FEATURE WORK, not to delete it.**

Most dead-write settings represent features that were *partially* implemented — UI was built, persistence wired, but the consumer was never written or was later replaced and the old surface was never removed. The user expects these features to work because the UI suggests they do. **Fix the wiring; do not remove the UI.**

Decision tree for each finding:

1. **Is this functionality the user reasonably expects to have?** → Wire it up. The UI is the contract.
2. **Is the UI a duplicate of an already-working feature elsewhere?** → Keep the working surface, remove the duplicate UI (only the duplicate, not the feature). Cite the working surface in the commit message.
3. **Is the feature explicitly deprecated with a citation (audit ID, ADR, or roadmap entry)?** → Then deletion is acceptable. Document the citation in the commit message.
4. **None of the above?** → Default to wiring it up. If unsure, ask. Never delete to make a finding go away.

Where this document offers a choice between "(A) wire it up" and "(B) delete it," **(A) is the default unless explicitly noted otherwise**. The HIGH-severity items at §1.2, §1.4, and the §2.1 cleanup pile are all wire-up work *by default*. Only items explicitly flagged as `DEDUPLICATE` or `DEPRECATED` are safe to delete.

Examples:
- "Park before dawn" — the user expects this to work. The fix is to **implement a dawn watchdog**, not to delete the toggle.
- "PHD2 executable path" — the user expects this to auto-launch PHD2 on connect. The fix is to **implement the auto-launch**, not to delete the textfield.
- "Sound alerts switch" — the user expects notifications to be silenceable. The fix is to **make `NotificationService` honor it**, not to delete the toggle.
- "Equipment → Settings tab" cooling/gain/offset rows — these *are* duplicates of fields owned by `EquipmentProfile`. Safe to remove the duplicate UI here, but cite the canonical surface.

When in doubt: implement the feature. Removing a user-facing surface to clean up code is a regression, not a fix.

### Verification command set

Before claiming a fix complete, run:

```bash
# Dart
melos run analyze:production
melos run audit:placeholders
melos run audit:fail-closed
melos run test       # for the package(s) you touched

# Rust (only if you touched Rust)
cd native/nightshade_native
cargo clippy --all-features --workspace -- -D warnings -D clippy::undocumented_unsafe_blocks -D clippy::await_holding_lock -D clippy::result_unit_err
cargo test --all-features --workspace
```

All four Dart audit gates must exit 0. All Rust gates must exit 0. New tests for any user-visible-bug fix.

### Commit message format

Subject: `[AUDIT-FIX-NN] short description (audit-handoff §N.NN)`
where `NN` is the finding number from this doc (e.g., `[AUDIT-FIX-3] safety_fail_mode dropdown forced (audit-handoff §1.3)`).

### How to claim work

If multiple agents work in parallel:
- Each agent picks a numbered finding and announces "claiming #N".
- Each fix is one commit, atomic, never bundling unrelated findings.
- File-level conflicts are pre-mapped in §6 below; coordinate via the bundling guide.

---

## 1. USER-VISIBLE BUGS (fix before tag)

These eleven findings are **real broken behavior the user would notice**. Priority within section is roughly impact-ranked.

### 1.1 [HIGH] Flat wizard hardcodes `gain: 0, offset: 0`

- **Source:** A2-FEATURES §10
- **Evidence:** `packages/nightshade_core/lib/src/services/flat_wizard_service.dart:137-138`
- **Symptom:** Flats are captured at gain=0 regardless of the camera profile's gain setting. Flats taken at gain=0 will not properly calibrate light frames captured at gain=100 — the master flat will not correct for sensor response at the actual operating gain.
- **Fix:** Read `gain` and `offset` from the active equipment profile (`profileService.activeProfile`) or, if not set there, from the most recent light-frame run for this camera. Never default silently to 0; if neither source has a value, throw.
- **Tests:** Add a unit test that verifies `captureTestFrame` uses the supplied profile's gain/offset and fails loudly when neither is available.
- **Severity:** **HIGH** — astrophotography correctness bug. Users won't notice until they try to calibrate and stars/background show unexpected gradients.

### 1.2 [HIGH] Entire 16-row Meridian Flip settings section is dead

- **Source:** A1-SETTINGS §5 + A3-PROVIDERS Cluster 1
- **Evidence:**
  - UI: `packages/nightshade_app/lib/screens/settings/widgets/sequencer_settings.dart:86-352` (16 rows)
  - Provider: `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart` (`globalMeridianFlipSettingsProvider`)
  - Consumers: zero. `grep "globalMeridianFlipSettingsProvider"` returns only the settings widget, the provider definition, and a design doc.
- **Symptom:** Every meridian-flip setting (standalone monitoring, trigger method, minutes-past/before, wait-before-flip, pause-guiding, recenter-after, refocus-after, resume-guiding, settle time, max retries, failure action, sound alert, push notification) writes to a provider that nobody reads. Actual flip behavior is configured per-`MeridianFlipNode` inside the sequence itself.
- **Fix (WIRE IT UP — this is the policy default; do NOT delete the UI):**
  1. Make `MeridianFlipNode` consume `globalMeridianFlipSettingsProvider` as default template; when a sequence is created or a node added without explicit settings, fill from the global defaults.
  2. Wire `meridianFlipDisconnectGuardProvider` into `app_shell.dart`'s root widget so the disconnect-during-flip safety reset (documented at `meridian_flip_provider.dart:268-301`) actually runs.
  3. Wire `standaloneMonitoringEnabled` (currently a dead toggle): when true and no sequence is running, mount a watcher that triggers an automatic flip when the mount crosses the meridian. This is the documented "monitoring mode" the toggle implies.
  4. Add `melos run test` coverage that toggling each setting actually changes a verifiable downstream behavior (mock executor + assert config propagated).
- **Severity:** **HIGH** — 16 user-facing settings the user reasonably expects to work, plus a documented-but-silent disconnect safety guard. Removing the UI would be a feature regression; the entire section needs to be made functional.

### 1.3 [HIGH] "Safety fail mode" dropdown setter ignores its argument

- **Source:** A1-SETTINGS §3
- **Evidence:** `packages/nightshade_core/lib/src/providers/settings_provider.dart:1275-1279`
  ```dart
  Future<void> setSafetyFailMode(SafetyFailMode _) async {
    // body hardcodes SafetyFailMode.failClosed regardless of input
  }
  ```
  UI: `sequencer_settings.dart:415-433` shows a dropdown with `items: const ['Fail Closed (Park)']` (single option).
- **Symptom:** The UI suggests user choice but the setter forces `failClosed`. The dropdown is decorative — toggling it does nothing.
- **Fix (WIRE IT UP — restore the user's choice):**
  1. The other two `SafetyFailMode` enum values (presumably `failOpen` and `failManual` — confirm from the enum definition) need their behavior implemented in `weather_safety_provider.dart`.
  2. Once implemented, `setSafetyFailMode` should actually persist the argument, and the dropdown should list all three options.
  3. The v2.5 hardening that "forced failClosed" was a guardrail because the other modes were unimplemented — finishing the implementation removes that guardrail correctly.
  4. The fail-closed audit doc (`docs/production-readiness/fail-closed-audit.json`) tracks this — update it after the other modes ship.
- **Alternative ONLY IF** the other modes were intentionally deprecated (cite an ADR or roadmap entry): replace the dropdown with a read-only "Enforced: Fail-closed (park)" pill and document the deprecation. Don't do this without a citation; "easier to lock it down than implement" is not a deprecation.
- **Severity:** **HIGH** — UI suggests choice; user expects choice; choice must be made real.

### 1.4 [HIGH] "Park on unsafe weather" + "Park before dawn" toggles unwired

- **Source:** A1-SETTINGS §1, §2
- **Evidence:**
  - UI: `packages/nightshade_app/lib/screens/settings/widgets/sequencer_settings.dart:389,404` (also duplicated at `equipment/tabs/settings_tab.dart:182`)
  - Setters: `settings_provider.dart:1265-1273` write `app_settings.park_on_unsafe_weather` + `park_before_dawn`
  - Consumers: zero. The actual park decision at `weather_safety_provider.dart:240,273` uses `weatherSettings.autoParkEnabled` (a *different* setting persisted in the `weather_settings` table, surfaced in Weather Safety settings).
- **Symptom:** Users who toggle the Sequencer "Park on unsafe weather" think they've enabled safety park. The flag they actually need to toggle lives under Weather Safety.
- **Fix (WIRE IT UP — make both surfaces work):**
  1. **Park on unsafe weather (Sequencer):** Refactor `weather_safety_provider.dart` to read `appSettings.parkOnUnsafeWeather` as the master "park policy enabled" gate (sequencer scope) AND `weatherSettings.autoParkEnabled` as the weather-feature-also-enabled secondary check (weather scope). Both are real settings — the Sequencer one is "do we park during sequences" and the Weather one is "is the weather feature itself on." Both should be honored. Migrate any existing dual-state forward.
  2. **Park before dawn:** Implement the dawn watchdog. Pick a location:
     - Inside the sequencer as a built-in trigger that fires N minutes before astronomical dawn at the observer's location.
     - OR as a top-level Timer in a session-scoped provider subscribed to observer location + sun ephemeris.
     - When triggered, call the same park path that weather-safety uses.
  3. The duplicate row at `equipment/tabs/settings_tab.dart:182` IS a duplicate — that one can be removed (deduplicate), keeping the Sequencer settings entry as the canonical surface.
- **Severity:** **HIGH** — both toggles look like safety features. They must actually be safety features.

### 1.5 [HIGH] Exposure Triggers dialog throws away its result

- **Source:** A1-SETTINGS §6 + A2-FEATURES cross-cutting #2
- **Evidence:** `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_toolbar.dart:163-169`:
  ```dart
  IconButton(
    icon: const Icon(Icons.notification_important),
    onPressed: () {
      showDialog(...);   // returns Future<List<ExposureTrigger>?>
                         // result is NEVER awaited or assigned
    },
    ...
  )
  ```
- **Symptom:** User opens the Exposure Triggers dialog, configures triggers, clicks Save. The dialog calls `Navigator.pop(_triggers)` returning the list, but the caller drops the result on the floor. The dialog is constructed with `const TriggerConfigurationDialog()` (no `initialTriggers`), so reopening shows an empty list.
- **Fix:** Persist exposure triggers. Two parts:
  1. Store the triggers in either the active sequence (preferred — they're sequence-scoped) or a new `app_settings` key.
  2. `await showDialog(...)`, capture the returned list, write it back to storage, and pass it back into the dialog on next open via `initialTriggers`.
  3. Wire the persisted triggers into the Rust sequencer's `triggers.rs` consumer.
- **Severity:** **HIGH** — one of the more prominent toolbar buttons does nothing visible after dismiss.

### 1.6 [MED] TPPA `autoCompleteThreshold` setting silently ignored

- **Source:** A2-FEATURES §6, recommendation REC-1
- **Evidence:** `packages/nightshade_core/lib/src/services/polar_alignment_service.dart:32-44`
- **Symptom:** The PolarAlignmentConfig's `autoCompleteThreshold` (configurable arcsec acceptance threshold) is forwarded to the all-sky path correctly (line 91) but NOT to the three-point (TPPA) path. Users who set a tighter threshold (e.g., 10″) for TPPA will silently get the 30″ default.
- **Fix:** Pass `config.autoCompleteThreshold` as a parameter to `backend.startPolarAlignment(...)` for TPPA. Verify the Rust side `polar_align.rs` honors it (it should — it already accepts a config struct).
- **Severity:** **MED** — user setting silently dropped; UX confusion but no safety impact.

### 1.7 [MED] Mosaic + Scheduler don't compose — only first panel captured

- **Source:** A2-FEATURES §8
- **Evidence:** `packages/nightshade_core/lib/src/services/scheduler/scheduler_engine.dart:920` (`buildSequenceForCandidate`)
- **Symptom:** A mosaic target added to the scheduler will image only the first panel. The scheduler builds a single-target sequence with no awareness of mosaic panels; subsequent panels are silently dropped.
- **Fix (choose one):**
  - **(A) Teach the scheduler about mosaics:** Iterate panels with proper state restore (sequencer can already navigate panel-to-panel via `MosaicService.createMosaicSequence`'s serpentine ordering).
  - **(B) Refuse at the scheduler boundary:** Throw a clear validation error when a mosaic target is added to the scheduler. Document the limitation.
- **Recommendation:** (A) is the right user experience but a larger change. If time-bound, ship (B) for now and file (A) for v2.5.1.
- **Severity:** **MED** — affects mosaic+scheduler users only, but silently delivers ⅑ to ¼ of the expected data.

### 1.8 [MED] Survey image fetch has no timeout — framing spinner can hang forever

- **Source:** A2-FEATURES §7, recommendation REC-2
- **Evidence:** `packages/nightshade_core/lib/src/providers/framing_provider.dart:665,720,743`
- **Symptom:** `loadSurveyImage` uses bare `http.Client()` with no timeout. If the CDS HiPS2FITS server hangs, `isLoadingImage = true` indefinitely. Catch at line 720 sets `imageError` only on the *first* attempt; SkyView fallback path is only triggered on Aladin HTTP errors, not on Aladin network errors.
- **Fix:** Wrap both HTTP calls in `.timeout(Duration(seconds: 30), onTimeout: () => throw TimeoutException(...))`. Fall through to SkyView on Aladin timeout (not just HTTP error). Surface the timeout to the user as an actionable error state ("Survey image fetch timed out — retry?").
- **Also verify** that the SkyView fallback URL builder at line 747 actually works — A2-FEATURES flags it as "likely broken but masked by Aladin's rarity of failure." Add at least one integration test.
- **Severity:** **MED** — degraded but not unsafe UX; bypassable by canceling the screen.

### 1.9 [MED] Filter focus offset silently skipped on direct `filter_index` exposures

- **Source:** A2-FEATURES §3, recommendation REC-3
- **Evidence:** `native/nightshade_native/sequencer/src/instructions.rs:2038-2079`
- **Symptom:** `apply_filter_focus_offset` only runs when a `ChangeFilter` instruction node fires. If an `ExposureNode` sets `filter_index` directly (the Rust executor allows this), the offset is NOT applied — the exposure runs with whatever focus position the previous filter had. Also, the function returns silently on offset-apply failure (line 2079); the next exposure proceeds at the wrong focus.
- **Fix:**
  1. Detect `filter_index` changes inside `ExposureNode::execute` and call `apply_filter_focus_offset` before the exposure starts (or refuse to set `filter_index` from within ExposureNode and require explicit ChangeFilter).
  2. On offset-apply failure, emit a `FocusOffsetFailed` event so the operator sees it in the live log; do NOT swallow.
- **Severity:** **MED** — affects users mixing filters within a single ExposureNode (common with NINA-imported sequences).

### 1.10 [MED] PHD2 controller event listener mutates state without `mounted` check

- **Source:** A3-PROVIDERS, "Missing mounted check"
- **Evidence:** `packages/nightshade_core/lib/src/providers/guiding_provider.dart:243` (`Phd2Controller._init`)
- **Symptom:** A long-lived `backend.eventStream.listen(...)` block mutates `state = ...` and reads `ref.read(...notifier).state = ...` (30+ lines of writes). The event stream is broadcast and outlives the notifier. If the controller is disposed while a `GuideStep` event is in flight, all writes after line 245 will throw on a disposed notifier or silently update phantom state.
- **Fix:** Add `if (!mounted) return;` immediately after the `if (event.category != EventCategory.guiding) return;` line. This matches the correct pattern at `autofocus_progress_provider.dart:115-117` and `event_provider.dart:64-70` already in the codebase.
- **Note:** Per project memory rules: "Always add `mounted` checks in StateNotifier event listeners." This file was missed by the W13 autoDispose audit.
- **Severity:** **MED** — a real disposal race; very hard to reproduce but the assertion failure tarnishes any sequence that ends with PHD2 still emitting events.

### 1.11 [MED] Planner "Open catalog settings" button routes to non-existent path

- **Source:** A4-NAV §"Dead buttons / broken links"
- **Evidence:** `packages/nightshade_app/lib/screens/planner/planner_screen.dart:2089` — `NightshadeButton(label: 'Open catalog settings', onPressed: () => context.go('/settings/catalogs'))`
- **Symptom:** `/settings/catalogs` is not a defined route. `go_router` silently routes to the nearest match (`/settings`) without auto-selecting the Catalogs tab. The user is dropped on the generic Settings screen with no breadcrumb.
- **Fix:** Either
  - Add `/settings/catalogs` as a sub-route mirroring `/settings/plate-solving` (cleanest), or
  - Change the link to `context.go('/settings?tab=catalogs')` if the Settings screen supports query-param tab selection (check `settings_screen.dart` for `?tab=` handling).
- **Severity:** **MED** — dead button.

---

## 2. PARTIALLY-IMPLEMENTED FEATURES (wire up the dead-write settings)

These items are settings the UI offers but the consumer side was never written or was replaced. **The default fix is to WIRE THEM UP — implement the missing consumer side so the feature works.** Only items explicitly tagged `DEDUPLICATE` below should be removed (and only because a working surface already exists elsewhere).

### 2.1 [MED → some HIGH] ~31 partially-implemented settings

- **Source:** A1-SETTINGS (full audit)
- **Inventory grouped by fix direction:**

#### WIRE-UP (implement the missing consumer)

| Setting | File:line | What needs implementing |
|---|---|---|
| **PHD2 executable path** | `phd2_guiding_settings.dart:134` | When connecting and `phd2Path` is set, auto-spawn `Process.start(phd2Path)` before opening the host:port socket. Add a "PHD2 not running, launching..." UI state. |
| **Sound alerts switch** | `notification_settings.dart:166` | `NotificationService` is using platform default sound unconditionally. Gate the sound playback on `appSettings.soundEnabled`. |
| **autoResumeEnabled (Weather Safety)** | `weather_safety_settings.dart:120` | `weather_safety_provider.dart` evaluates auto-park but not auto-resume; implement the resume path that auto-unparks N minutes after weather returns to safe. |
| **Standalone meridian monitoring toggle** | `sequencer_settings.dart:94` | Implement a top-level watcher that monitors mount HA when `standaloneMonitoringEnabled && !sequenceRunning` and triggers an automatic flip. Already covered in finding 1.2 — bundle there. |
| **Auto-focus interval / on-filter-change** | `sequencer_settings.dart:446` | Make `sequence_executor.dart` consult these as fallback defaults when a sequence's nodes don't specify cadence/trigger conditions. Per-node settings still override. |
| **Dither enabled / dither every N frames** | `sequencer_settings.dart:516` | Same pattern — fallback defaults consulted by `_sequenceToJson` only when per-node values are null/unset. (Note: also fix the inverse bug from A2-features where `_sequenceToJson` *always* overrides per-node values.) |
| **Auto dark subtraction + temp tolerance** | `dark_library_settings.dart:47` | The image-capture pipeline ignores these. Either (a) wire `imaging_service.dart` to read `autoDarkSubtractEnabledProvider` and `darkTempToleranceProvider` and apply dark calibration before publishing the frame, or (b) reconcile with the parallel `calibrationSettingsProvider` so both UIs write to the same underlying flag. **Recommend (b)** — calibrationSettingsProvider is the live one; either repoint the dark-library UI to write into it, or migrate calibrationSettingsProvider readers to consult the dark-library settings. Pick one source of truth; don't delete the dark-library UI. |
| **Temp compensation switch + coefficient** | `equipment/tabs/settings_tab.dart:220` | Currently a HUD-only indicator. Implement the compensation loop: subscribe to focuser temperature events, multiply ΔT × coefficient, command the focuser when delta exceeds 1 step. This is a real feature users expect from any modern astro app. |
| **Park before dawn / Park on unsafe weather** | (handled in §1.4) | Already in §1.4. |
| **Sequences path / Database path / Logs path** | `file_path_settings.dart:95` | Currently only `imageOutputPath` re-routes anything. Implement: (a) sequences path → where `sequence_file_service` exports/imports, (b) database path → migrate DB file (with backup) to the new location on apply, (c) logs path → re-init the file logger sink. Add a restart-required toast if needed. |
| **Timezone dropdown + Use System Time** | `location_settings.dart:355` | Implement a TZ override layer. All app time math currently uses `DateTime.now()` directly; wrap that in a `clockProvider` that consults the user setting. Useful for users in remote-observatory scenarios. |
| **indi_auto_connect / alpaca_auto_discover** | `settings_provider.dart:1458,1473` | Setters exist but no UI surface. Add them to Connection settings so users can opt in/out of auto-discovery. |
| **uiScale dropdown** | (no UI yet) | Add the dropdown to Appearance Settings. Enum values already documented: `Auto, Small (0.8x), Normal (1.0x), Large (1.2x), Extra Large (1.4x)`. The field is already consumed at `app.dart:143`; just needs the picker. |
| **Plate Solving widget's timeout / search-radius / blind-solve** | `plate_solving_settings.dart` | Reconcile with the screen-version writes. Either repoint the widget to `plateSolverPreferenceProvider` (the live one used by `plate_solve_service.dart:447-491`), or have `plate_solve_service` consult both. **Recommend repoint the widget** so there's one source of truth. Don't delete the widget; it's the main-settings entry point users find. |
| **Mobile companion's 11 prefs** | (no mobile UI) | Already in §3.3. |

#### DEDUPLICATE (a working surface already exists; remove the duplicate)

These are the ONLY items in §2.1 that are safe to remove, because removal does not lose functionality:

| Item | Duplicate of | Action |
|---|---|---|
| Auto-save sequences (General toggle, `general_settings.dart:106`) | Auto-Save category page | Remove the General-tab toggle. Document the Auto-Save category as canonical. |
| Equipment → Settings tab: cooling/gain/offset/meridian/parking/backlash/dither/settle (10 rows) | Equipment profiles + sequence-node properties | Remove the duplicate rows. Add a header note in the Equipment → Settings tab pointing to the canonical surfaces (profile for hardware defaults, sequence node for per-sequence overrides). |
| Park on unsafe weather row at `equipment/tabs/settings_tab.dart:182` | The one at `sequencer_settings.dart:389` (which becomes canonical after §1.4) | Remove the duplicate. |

#### NEEDS DECISION (not clearly wire-up or deduplicate)

| Item | Question |
|---|---|
| **Bit depth dropdown (`imaging_settings.dart:88`)** | Sensors report bit depth from SDKs at FFI level; a user toggle is conceptually wrong. Options: (1) Repurpose as "preferred output bit depth" for FITS/XISF writers (real feature), or (2) Make it a read-only display of the sensor's current bit depth. Ask the product owner. Default to (1) — it's the more useful feature. |

- **Effort:** 3-5 days of focused work to wire up the WIRE-UP list. The DEDUPLICATE work is ~2 hours.
- **Severity:** Many of these are MED, not LOW — a "Park before dawn" toggle that doesn't park before dawn is a safety issue, and "Sound alerts" not silencing is a quality-of-life regression. The LOW label was wrong; many of these are user-visible bugs that A1 grouped together.

### 2.2 ~104 unconsumed Riverpod providers (mostly post-wire-up cleanup)

- **Source:** A3-PROVIDERS
- **Reading guide:** Many of these will become *live* once §2.1 wires up their corresponding feature. Don't delete a provider before checking whether it powers a feature you're about to implement.
- **Top clusters and disposition:**
  - **Cluster 1: Meridian flip subsystem** (14 providers) — **DO NOT DELETE.** Becomes live after fix 1.2 wires the section up.
  - **Cluster 2: Imaging-screen state** (13 providers — `imageZoomProvider`, `imagePanOffsetProvider`, `imageFitModeProvider`, `showStatsOverlayProvider`, etc.) — **DEDUPLICATE.** These are superseded by `imagingViewerStateProvider` (`imaging_viewer_state_provider.dart:126`) and `autoStretchSettingsProvider`. The replacements are already live and consumed. Safe to delete the old providers.
  - **Cluster 3: Overlay toggles** (~10 providers) — **DEDUPLICATE.** Superseded by `annotation_settings_provider` and `autoStretchSettingsProvider`. Same pattern as Cluster 2.
  - **Cluster 4: Planetarium catalog/queue** (8 providers) — **DECISION.** `tonightsBestTargetsProvider`, `targetAlertProvider`, `moonProximityProvider`, `altitudeInfoProvider` look like stubs for a never-shipped "tonight overview" card. Either (a) ship the tonight-overview feature (these providers are the backend; just need a UI card), or (b) delete if the feature was deliberately cut. Ask the product owner. **Default to (a)** — these are useful features.
    - **2026-05-16 update (AUDIT-FIX-4):** investigation found that the "Tonight Overview" feature *did* ship, but via a different code path — `targetSuggestionServiceProvider` + `SessionOptimizerService` + `tonightSuggestionsProvider`, consumed by both `TonightCard` (dashboard) and `PlannerScreen.recommendation`. The Cluster 4 providers (`tonightsBestTargetsProvider`, `targetAlertProvider`, `moonProximityProvider`, `altitudeInfoProvider`, `targetScoringServiceProvider`, `selectedTargetScoreProvider`) are a parallel, older scoring stack (`packages/nightshade_planetarium/lib/src/providers/planning_providers.dart`) with zero UI consumers — they're superseded but not yet wired to anything we'd lose by deleting. **Deferred deletion** pending product-owner confirmation that we're committing to the `target_suggestion` stack as the canonical scoring engine. No UI was added; the providers remain in place to avoid silently losing a parallel implementation that may yet be re-wired.
  - **Cluster 5: Device discovery for dome/weather/safety/rotator/filterwheel/guider** (6 providers — `availableDomesProvider`, `availableWeatherProvider`, `availableSafetyMonitorsProvider`, etc.) — **WIRE-UP.** No UI card subscribes. The mobile devices_tab.dart only shows Cameras/Mounts/Focusers. Add the missing device-type cards so users can manage their dome/weather-station/safety-monitor/etc. from the Equipment screen. Don't delete the providers; they're the right backend.
  - **Cluster 6: Capability providers for focuser/filterWheel/rotator** (3) — **WIRE-UP.** Only `cameraCapabilitiesProvider` is consumed (by `disk_space_provider.dart`). The other three were planned for capability badges in the Equipment screen. Implement the badges or document the deferral.
  - **Clusters 7-8: Miscellaneous** (~50 providers) — case-by-case in the source audit doc. Many are likely WIRE-UP candidates (e.g., `polarAlignmentHistoryStreamProvider`, `lastPolarAlignmentProvider` should show in an alignment history widget).
- **Estimated effort:** Most of this work happens *as part of* §2.1's wire-up effort. Pure deletion (deduplicates only) is ~1 day.
- **Severity:** Don't treat as cleanup. Treat as "what features were almost-shipped." Each dead provider is a clue about a partially-implemented feature.

### 2.3 3 unreferenced `GoRoute` definitions — mixed fix direction

- **Source:** A4-NAV §"Dead routes"
- **Findings and disposition:**

| Route | Disposition | Action |
|---|---|---|
| `/mobile-dashboard` (`app_router.dart:55-59`) | **DEDUPLICATE** | Mobile uses a standalone MaterialApp; this route is leftover from an earlier mobile-routing design. Safe to delete; mobile entry path is unchanged. |
| `/diagnostics/dump` (`app_router.dart:263-271`) | **WIRE-UP** | `DiagnosticDumpScreen` is implemented and operationally valuable. Add a "Generate Diagnostic Dump" button to Settings → Help (next to "First Night Walkthrough"). Also fix the missing back affordance (§3.x adjacent). |
| `/scheduler` redirect (`app_router.dart:237-246`) | **KEEP for one more release** | Deprecation shim for external bookmarks. Safe to delete only if release notes call out the breaking change for external integrations. **Default to keeping** until v2.6. |

### 2.4 Orphan screen — `SuggestionsScreen` (~525 lines) — NEEDS DECISION

- **Source:** A4-NAV §"Orphan screens"
- **Evidence:** `packages/nightshade_app/lib/screens/suggestions/suggestions_screen.dart` has no `import` outside the file itself. The `widgets/suggestions/` directory IS still used by the planner.
- **Investigate before acting:**
  1. Check git history for the W8-SCHED-MERGE commit (`28` in the task list) and the suggestions consolidation. Was the screen-level wrapper retired in favor of a planner tab on purpose, or was the suggestions feature partially gutted?
  2. If the screen was deliberately retired (feature now lives inside planner): safe to delete the file. Document the deletion as DEDUPLICATE in the commit message.
  3. If suggestions-as-its-own-page was meant to ship: re-wire it (add a route, sidebar entry, and entry point). Don't delete a feature that was meant to ship.
- **Default:** Investigate first. Default to keeping if uncertain. The widgets are still alive, so the underlying feature isn't gone.

### 2.5 [LOW] Duplicate provider names

- **Source:** A3-PROVIDERS §"Duplicates"
- **Findings:**
  - `sessionImagesProvider` has 3 declarations with 3 different types across `imaging_provider.dart:267`, `analytics_screen.dart:484`, `photometric_calibration_wizard.dart:1193`. Rename two: `dbSessionImagesProvider`, `calibrationSessionImagesProvider`.
  - `targetSearchProvider` has 2 declarations. The core one (`framing_provider.dart:1686`) is only used by `test/providers/dispose_hooks_test.dart`; every importer of `nightshade_core.dart` has to `hide` it. **Delete the core declaration** and migrate the test to import the screen-local provider at `framing_search_provider.dart:173`.
- **Severity:** **LOW** — footgun if a future refactor adds a barrel export.

---

## 3. UX SMOOTHING (small, high-leverage)

### 3.1 [MED] `TransientsScreen` has no back/exit affordance

- **Source:** A4-NAV §"Missing back"
- **Evidence:** `packages/nightshade_app/lib/screens/transients/transients_screen.dart` — no AppBar, no back button, no `context.pop()`. Reached via `TransientAlertBadge` using `context.go`, so there's nothing on the navigator stack to pop. User can only escape via side-nav.
- **Fix:** Add a back affordance using the pattern from `polar_alignment_screen.dart:196-208` (`canPop()` → `context.pop()` else `context.go('/dashboard')`).
- **Severity:** **MED** — usability friction.

### 3.2 [MED] `/settings/plate-solving` back button doesn't work when entered via `context.go`

- **Source:** A4-NAV §"Missing back"
- **Evidence:** `plate_solver_required_banner.dart:33` uses `context.go('/settings/plate-solving')`. The screen has `AppBar(automaticallyImplyLeading: true)`, but `go_router`'s implicit back button on a `go`-entered route calls `Navigator.pop()` on an empty stack — asserts in debug, no-ops in release.
- **Fix:** Either change callers to `context.push('/settings/plate-solving')`, or replace the AppBar's implicit leading with an explicit one that calls `context.go('/settings')`.
- **Severity:** **MED** — assertion failure / silent no-op.

### 3.3 [MED] Mobile companion has 11 prefs but no settings screen

- **Source:** A1-SETTINGS §11
- **Evidence:** `apps/mobile/lib/services/mobile_preferences.dart` declares 11 prefs (`androidImmersiveSticky` + 10 `notify*` toggles); readers exist in `mobile_event_notifier.dart` and `notification_service.dart`. No mobile screen surfaces them. Users stuck on defaults forever.
- **Fix:** Add a Settings screen or modal in `apps/mobile/lib/screens/` that surfaces the 11 prefs. Group them: Display (immersive), Notifications (10 toggles).
- **Severity:** **MED** — invisible features the user can never opt out of.

### 3.4 [LOW] Connection dialog hardcodes `localhost:8080` defaults

- **Source:** A1-SETTINGS §22
- **Evidence:** `packages/nightshade_app/lib/screens/settings/widgets/connection_settings.dart:206-207`
- **Symptom:** Server-connect dialog doesn't pre-fill from persisted `indiServerHost` / `alpacaServerHost` / last-connected address. Users with multiple machines re-type the hostname every time.
- **Fix:** Pre-fill text controllers from `appSettings.indiServerHost` / `alpacaServerHost` (or last successful connection if a history table exists).
- **Severity:** **LOW** — usability.

### 3.5 [LOW] Notification webhook/key fields are not `obscureText`

- **Source:** A1-SETTINGS §23
- **Evidence:** `notification_settings.dart` (Discord webhook, Pushover key/user)
- **Symptom:** Credentials shown in plaintext in the settings UI. Useful in dev, sketchy on a shared screen.
- **Fix:** Add `obscureText: true` + a "show password" icon button (Flutter pattern).
- **Severity:** **LOW** — security best-practice.

---

## 4. CROSS-CUTTING / ARCHITECTURAL

### 4.1 [MED] `AppSettings` model migration after §2.1 wire-up lands

- **Source:** A1-SETTINGS, "Notes & recommendations"
- **Context:** The `AppSettings` model accumulated fields during early development. As features matured, dedicated providers were added (`calibrationSettingsProvider`, `weatherSettingsProvider`, `plateSolverPreferenceProvider`, `autoSaveServiceProvider`, `globalMeridianFlipSettingsProvider`, `scienceSettingsProvider`). The old `AppSettings` fields, setters, and UI controls were never reconciled with the new providers.
- **Fix (after §2.1 wire-up):**
  1. For each field where §2.1 picked "WIRE UP" — confirm the consumer reads the canonical store (either `AppSettings` or the dedicated provider, not both).
  2. For each field where §2.1 picked "DEDUPLICATE" — remove ONLY the duplicate write path; the data layer should still preserve the value (so users don't lose their config).
  3. Add a Drift migration that, for any removed `app_settings` column, copies any non-default value to the canonical provider's table before dropping the column.
  4. Run `melos run generate` to regenerate the freezed/g.dart files.
- **Important:** This is a model-shrink, not a feature-cut. The features the columns represent must be working in the canonical store first (that's what §2.1 does).
- **Severity:** **MED** — schedule this AFTER §2.1 finishes; doing it before risks losing user data.

### 4.2 [LOW] `nightshade_webrtc` package no longer ships WebRTC

- **Source:** A2-FEATURES §12, REC-1
- **Symptom:** The package name implies WebRTC peer-connection / signaling, but those primitives were deleted in W2 (audit §2.3). Live remote control runs over REST + WebSocket via `headless_api_server.dart`. The package still exists as `nightshade_webrtc` housing auth/discovery/token-manager primitives. Header comment acknowledges this, but every downstream that grep-finds the package name still thinks WebRTC is involved.
- **Fix:** Rename the package to `nightshade_remote_protocol` (or `nightshade_remote_api`). Update:
  - `packages/nightshade_webrtc/` → `packages/nightshade_remote_protocol/`
  - Every `import 'package:nightshade_webrtc/...'`
  - `melos.yaml`, `pubspec.yaml` references
  - Test directory paths
- **Severity:** **LOW** — naming debt; creates ongoing confusion in audits and CI logs.

### 4.3 [LOW] Magic-number defaults scattered

- **Source:** A2-FEATURES cross-cutting #1
- **Inventory** (not exhaustive):
  - `MIN_POST_FLIP_ALTITUDE_DEG = 10.0` (`meridian_flip_executor.rs:130`)
  - `SAFETY_ACTION_RETRY_COUNT = 3` / `SAFETY_ACTION_RETRY_DELAY_SECS = 5.0` (lines 40, 43)
  - `FLIP_COORDINATE_TOLERANCE_DEG = 1.0/60.0` (1 arcmin)
  - `maxObjects = 500` (catalog overlay)
  - Focus model: `|slope| > 500 steps/°C`, `rSquared >= 0.7`, `dataPointCount >= 5`, `confidence >= 0.5`, `paddingFraction = 0.05`
  - Flat wizard: `_imageDownloadTimeout = Duration(seconds: 60)`, `minExposure: 0.001`, `maxExposure: 30.0`, `maxIterations: 8`
  - Scheduler `_reevaluationDebounce = 500ms`
  - Mosaic: `overheadPerPanelSecs = 60.0`, dither pixels fallback `3.0`
- **Fix:** Consolidate into a `SequencerDefaults` table or `defaults.toml` config. Promote the most-impactful ones (flat-wizard exposure bounds, flip altitude/tolerance, focus-model thresholds) to user-configurable settings with documented defaults.
- **Severity:** **LOW** — operationally meaningful for advanced users but not currently surfacing as bugs.

### 4.4 [MED] No E2E happy-path integration tests for the Dart↔Rust seam

- **Source:** A2-FEATURES cross-cutting #6
- **Missing:** No end-to-end tests covering: sequencer (Dart-side), meridian flip (mobile-triggered), flat wizard, mobile→desktop sequencer control. Rust-side unit tests are dense, but the Dart↔Rust seam is under-tested.
- **Fix:** Write 3-4 integration tests that exercise full flows. Use the existing fake bridge / fake ASCOM scaffolding. Recommended targets:
  - `flat_wizard_e2e_test.dart` — drive a 3-filter flat-wizard run through the fake bridge, verify ADU convergence and frame counts.
  - `meridian_flip_e2e_test.dart` — schedule a flip with the trigger framework, simulate mount-disconnect, verify safety reset fires (after fix 1.2).
  - `mobile_remote_e2e_test.dart` — boot `HeadlessApiServer` in-process, drive `MobileSequenceHooks`, verify SequenceFailed event reaches mobile notifier.
- **Severity:** **MED** — prevents future regressions in the most fragile seam.

### 4.5 [LOW] Add `.autoDispose` to 3 family providers from F1/F5

- **Source:** A3-PROVIDERS §"Missing-autoDispose"
- **Findings:**
  - `catalogOverlayQueryProvider` (`catalog_overlay_provider.dart:86`) — caches per `(WCS-center, mag, filters)` quadruple as user pans/zooms. Every distinct combo gets a permanent cache entry. **Real leak.**
  - `sessionReportProvider` (`session_report_provider.dart:26`) — `family<SessionReport, int>` keyed by sessionId. Used only by the report dialog. Should free on dialog close.
  - `campaignRollupProvider` (`campaign_rollup_provider.dart:23`) — `family<CampaignRollup, int>` keyed by targetId. Multi-night rollup walks all sessions. Should free on panel close.
- **Fix:** Add `.autoDispose.family` to each. Verify dialog/panel users still work (autoDispose may invalidate state on rebuild — usually fine but worth testing).
- **Severity:** **LOW** — memory pressure on long-running sessions.

### 4.6 [LOW] Document HTTP 501 fail-loud endpoints in audit register

- **Source:** A5-DEAD-UI §"Fail-loud HTTP 501 endpoints"
- **Findings:** 5 headless-API endpoints return `501 Not Implemented` with explanatory JSON (correct fail-loud behavior, NOT a bug):
  - `POST /api/safety/settings` — `safety_monitor_handlers.dart:210`
  - `POST /api/safety/acknowledge` — `safety_monitor_handlers.dart:236`
  - `POST /api/dome/sync` — `dome_handlers.dart:114`
  - `POST /api/dome/home` — `dome_handlers.dart:133`
  - `POST /api/dome/halt` — `dome_handlers.dart:138`
- **Fix:** Add entries to `docs/production-readiness/behavioral-audit-register.md` with disposition `explicit_unsupported` and a one-line rationale (this is the registered-and-tracked pattern from prior CQ waves).
- **Severity:** **LOW** — documentation hygiene.

---

## 5. WHAT WAS CLEAN (don't touch)

These are **positive findings** — the prior cycle did its job. Documenting so a future agent doesn't burn time investigating.

- **0 CLAUDE.md placeholder/stub violations.** No `// TODO: implement X`, no `unimplemented!()` or `todo!()` in hand-written Rust.
- **0 user-visible "coming soon" / "TBD" / "lorem ipsum" / "future update" strings.**
- **0 dead empty-handler buttons in production code.** The single `onTap: () {}` in `scheduler_tab_content.dart:1418` is an intentional event-swallow on a modal backdrop.
- **0 `ref.read` in `build()` anti-patterns.** All 26 raw matches resolved to legitimate callback-bound reads or notifier-method invocations.
- **10/10 behavioral markers spot-checked.** Line numbers occasionally shifted but documented behavior is intact.
- **No hardcoded magic numbers in the UI.** All polling/timeout constants live in services with correct context-driven defaults.
- **No charts with empty/static data sources, no stuck loading indicators, no stale-switch UI anti-patterns.**
- **`-D warnings`, `-D undocumented_unsafe_blocks`, `-D await_holding_lock`, `-D result_unit_err` all enforced in CI** (no violations).

---

## 6. BUNDLING GUIDE (for parallel agents)

If you're dispatching multiple agents to fix this in parallel, the following groupings have **no file overlap** so they can run concurrently in worktrees:

### Bundle A — Sequencer + meridian flip
- Findings: **1.2** (meridian flip wiring), **1.5** (exposure triggers dialog)
- Files: `sequencer_settings.dart`, `meridian_flip_provider.dart`, `app_shell.dart`, `sequence_toolbar.dart`, possibly Rust `triggers.rs`
- Estimated size: M (medium — Rust touch possible)

### Bundle B — Safety + weather
- Findings: **1.3** (safety fail mode), **1.4** (park-on-unsafe + dawn watchdog)
- Files: `settings_provider.dart`, `sequencer_settings.dart`, `weather_safety_provider.dart`, possibly new dawn-watchdog file
- Estimated size: M

### Bundle C — Polar alignment + framing
- Findings: **1.6** (TPPA threshold), **1.8** (survey image timeout)
- Files: `polar_alignment_service.dart`, `framing_provider.dart`
- Estimated size: S

### Bundle D — Imaging pipeline
- Findings: **1.1** (flat wizard gain/offset), **1.9** (filter focus offset)
- Files: `flat_wizard_service.dart`, Rust `instructions.rs`
- Estimated size: M (Rust touch)

### Bundle E — Plumbing + nav
- Findings: **1.7** (mosaic+scheduler), **1.10** (PHD2 mounted check), **1.11** (catalog settings link)
- Files: `scheduler_engine.dart`, `guiding_provider.dart`, `planner_screen.dart`
- Estimated size: M

### Cleanup bundle (do separately, after user-bug bundles land)
- Findings: **2.1-2.5** (dead settings, dead providers, dead routes, orphan screen, duplicates)
- Files: many, but read-mostly-then-delete; conflict risk is low if no other agent is editing the same file
- Estimated size: L (large but mechanical)

---

## 7. APPENDIX — Source audit links

- A1 Settings audit: `docs/audits/2026-05-16-settings-audit.md` (95 settings, ~31 dead-writes)
- A2 Features audit: `docs/audits/2026-05-16-features-audit.md` (12 features, classifications + recommendations)
- A3 Providers audit: `docs/audits/2026-05-16-providers-audit.md` (575 providers, ~104 dead)
- A4 Navigation audit: `docs/audits/2026-05-16-nav-audit.md` (22 routes, 3 dead, 1 broken link, 3 missing-back)
- A5 Dead-UI audit: `docs/audits/2026-05-16-dead-ui-audit.md` (clean — confirms prior CQ cycle worked)

---

## 8. QUICK INDEX — every finding with fix direction

Disposition legend:
- **WIRE-UP** = implement the missing consumer / make the feature work
- **DEDUPLICATE** = working surface exists elsewhere; remove only the redundant code path
- **DECISION** = needs product owner to choose direction before fixing
- **BUG-FIX** = code bug that's not a feature-completeness issue (race, off-by-one, etc.)
- **NEW-FEATURE** = work the audit surfaced but isn't strictly broken (e.g., E2E tests)

| # | Severity | Disposition | Source | Summary | Effort |
|---|---|---|---|---|---|
| 1.1 | HIGH | BUG-FIX | A2 | Flat wizard gain/offset hardcoded 0 | S |
| 1.2 | HIGH | WIRE-UP | A1+A3 | Meridian flip subsystem (16 settings + 14 providers) | M |
| 1.3 | HIGH | WIRE-UP | A1 | Safety fail mode — implement the other 2 modes | M |
| 1.4 | HIGH | WIRE-UP | A1 | Park-on-unsafe + park-before-dawn watchdog | M |
| 1.5 | HIGH | BUG-FIX | A1+A2 | Exposure Triggers dialog result discarded | S |
| 1.6 | MED | BUG-FIX | A2 | TPPA autoCompleteThreshold not forwarded | XS |
| 1.7 | MED | WIRE-UP | A2 | Mosaic + scheduler composition (panel iteration) | M |
| 1.8 | MED | BUG-FIX | A2 | Survey image fetch needs timeout + fallback fix | S |
| 1.9 | MED | BUG-FIX | A2 | Filter focus offset skipped on direct exposures | S |
| 1.10 | MED | BUG-FIX | A3 | PHD2 controller missing `mounted` check | XS |
| 1.11 | MED | BUG-FIX | A4 | `/settings/catalogs` route — add or repath | XS |
| 2.1 | MED/HIGH | WIRE-UP (mostly) | A1 | ~31 partial settings — wire up most, deduplicate ~12 | L |
| 2.2 | MED | WIRE-UP (mostly) | A3 | ~104 unconsumed providers — wire up + decision per cluster | L |
| 2.3 | mixed | mixed | A4 | 3 routes: 1 dedupe, 1 wire-up, 1 keep | S |
| 2.4 | — | DECISION | A4 | Orphan `SuggestionsScreen` — investigate before deleting | XS |
| 2.5 | LOW | DEDUPLICATE | A3 | Rename 3 `sessionImagesProvider`, delete 1 of 2 `targetSearchProvider` | S |
| 3.1 | MED | WIRE-UP | A4 | Add back affordance to `TransientsScreen` | XS |
| 3.2 | MED | BUG-FIX | A4 | `/settings/plate-solving` `context.go` → `context.push` | XS |
| 3.3 | MED | WIRE-UP | A1 | Build mobile Settings screen for 11 prefs | M |
| 3.4 | LOW | WIRE-UP | A1 | Pre-fill connection dialog from persisted hosts | XS |
| 3.5 | LOW | BUG-FIX | A1 | obscureText on credential fields | XS |
| 4.1 | MED | DEDUPLICATE | A1 | AppSettings model shrink — AFTER §2.1 wire-up | L |
| 4.2 | LOW | DEDUPLICATE | A2 | `nightshade_webrtc` package rename | M |
| 4.3 | LOW | WIRE-UP | A2 | Magic-number defaults → user-configurable | M |
| 4.4 | MED | NEW-FEATURE | A2 | Dart↔Rust E2E tests (3-4 flows) | M |
| 4.5 | LOW | BUG-FIX | A3 | `.autoDispose` on 3 F1/F5 family providers | XS |
| 4.6 | LOW | BUG-FIX | A5 | Document 5 HTTP 501 endpoints in audit register | XS |

**Disposition counts:** WIRE-UP: ~14 items · BUG-FIX: ~10 items · DEDUPLICATE: 4 items · DECISION: 2 items · NEW-FEATURE: 1 item.

**The bulk of this work is wiring up features users expect, not removing things.**

**Recommended ship gate for v2.5.0:** at minimum, fix the 5 HIGH-severity items (1.1, 1.2, 1.3, 1.4, 1.5). These are mostly WIRE-UP work — making existing UI actually do what it claims. The 6 MED bug-fixes can ship in v2.5.1 if release timing is tight. The §2.1 partial-settings work is the biggest opportunity to materially improve the app — most users will appreciate having sound alerts, dark subtraction, temp compensation, PHD2 auto-launch, and dawn-park as REAL features rather than removed toggles.

---

*End of handoff document. Final HEAD reviewed: `74abe34`. If your branch HEAD differs significantly, re-run the audit before relying on file:line references.*
