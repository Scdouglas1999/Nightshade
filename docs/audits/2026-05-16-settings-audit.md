# Settings audit — 2026-05-16

Scope: every user-facing setting surface in the desktop + mobile shell.
Method: each UI control was traced through its setter (writer) into the
codebase to identify the *consumer* (reader) that actually changes app
behavior. Findings reflect the state of branch `release/v2.5.0-hardening`
at HEAD `74abe34`.

## Summary

- **Inspected:** ~95 distinct user-facing settings (toggles, dropdowns,
  textfields, sliders, color picker).
- **OK:** 53 — UI ↔ storage ↔ consumer fully wired.
- **NO-OP / DEAD-WRITE:** 31 — UI persists value, but no production code
  reads it (or the only reader is the UI mirroring itself back).
- **PARTIAL:** 5 — wired, but only one of multiple expected effects fires
  (e.g. hardware vs. display).
- **STALE-DEFAULT:** 1 — setter overrides any user choice with a constant.
- **UNTESTABLE-FROM-CODE:** 0.

The dominant pattern: a parallel "real" provider exists for the feature
(e.g. `globalMeridianFlipSettingsProvider`,
`plateSolverPreferenceProvider`, `weatherSettingsProvider`,
`autoSaveServiceProvider`, `calibrationSettingsProvider`) and the matching
`AppSettings` fields are vestigial duplicates left over from earlier
refactors. They still have setters and surface in UI, but nothing on the
execution path reads them.

---

## Critical findings (HIGH)

1. **Park on unsafe weather** — Settings → Sequencer → Safety
   - UI: `packages/nightshade_app/lib/screens/settings/widgets/sequencer_settings.dart:389`
     (and duplicated at `packages/nightshade_app/lib/screens/equipment/tabs/settings_tab.dart:182`)
   - Storage: `setParkOnUnsafeWeather()` at
     `packages/nightshade_core/lib/src/providers/settings_provider.dart:1265-1268`
     (writes `app_settings.park_on_unsafe_weather`)
   - Consumer: **none**
   - Classification: **NO-OP / DEAD-WRITE**
   - Evidence: A grep for `parkOnUnsafeWeather` /
     `park_on_unsafe_weather` outside the settings_provider, model
     freezed, database, and UI widgets yields zero hits. The actual park
     decision in `weather_safety_provider.dart:240,273` uses
     `weatherSettings.autoParkEnabled` (a different setting in the
     `weather_settings` table), which has its own UI in Weather Safety.
   - Fix: Either delete this toggle (and its sibling in Mount Settings)
     to avoid user confusion, or rewrite the safety provider to read
     `appSettings.parkOnUnsafeWeather` as the master gate.

2. **Park before dawn** — Settings → Sequencer → Safety
   - UI: `packages/nightshade_app/lib/screens/settings/widgets/sequencer_settings.dart:404`
   - Storage: `setParkBeforeDawn()` at `settings_provider.dart:1270-1273`
   - Consumer: **none**
   - Classification: **NO-OP / DEAD-WRITE**
   - Evidence: grep `parkBeforeDawn|park_before_dawn` shows database
     seed, model, provider, UI — no scheduler, sequence_executor, or
     mount service reads it. There is no dawn-park watchdog in the
     codebase.
   - Fix: Remove the UI row or implement a dawn watchdog that reads it.

3. **Safety fail mode dropdown** — Settings → Sequencer → Safety
   - UI: `packages/nightshade_app/lib/screens/settings/widgets/sequencer_settings.dart:415-433`
   - Storage: `setSafetyFailMode()` at `settings_provider.dart:1275-1279`
     — note the implementation: it **ignores the `_` argument** and
     unconditionally persists `SafetyFailMode.failClosed`.
   - Consumer: `weather_safety_provider.dart:162` reads
     `appSettings.safetyFailMode` correctly.
   - Classification: **STALE-DEFAULT**
   - Evidence: setter signature is
     `Future<void> setSafetyFailMode(SafetyFailMode _) async`; body
     hardcodes `failClosed`. The UI dropdown's `items: const ['Fail
     Closed (Park)']` only offers a single option, and the helpers
     `_failModeToString` / `_stringToFailMode` (lines 74-84) also ignore
     their input.
   - Fix: This is intentional in v2.5 hardening (single-mode policy),
     but the UI presents a dropdown that suggests choice. Either remove
     the dropdown entirely (replace with a read-only label saying
     "Fail-closed enforced") or enable the other two enum values now
     that the provider supports them.

4. **Auto-focus interval / Auto-focus on filter change / Dither
   enabled / Dither every N frames** — Settings → Sequencer
   - UI: `sequencer_settings.dart:446-516`
   - Storage: setters in `settings_provider.dart:1286-1308`
     (`auto_focus_*`, `dither_*` keys)
   - Consumer: **none** (only `useFilterFocusOffsets` and the per-node
     AF settings in `autofocusSettingsProvider` are read; these
     "global" sequencer toggles are not consulted).
   - Classification: **NO-OP / DEAD-WRITE**
   - Evidence: grep for `autoFocusEveryMinutes`, `autoFocusOnFilterChange`,
     `ditherEnabled`, `ditherEveryFrames` shows usage only in the
     freezed/g.dart, settings_provider, settings widget, and the
     `ffi_backend.dart:2120-2121` stub that just seeds the remote
     `AppSettings` from defaults. The actual sequencer reads dither
     and AF cadence from per-instruction node properties built in
     `nina_sequence_parser.dart` / sequence node defaults, not from
     these globals.
   - Fix: Either delete these four rows, or refactor sequence_executor
     to use them as fallback defaults when nodes don't specify.

5. **Meridian flip — every setting on the panel** — Settings →
   Sequencer → Meridian Flip
   - UI: `sequencer_settings.dart:86-352` (16 rows: standalone
     monitoring, trigger method, minutes past meridian, minutes before
     limit, hour angle threshold, wait-before-flip, pause guiding,
     recenter after flip, refocus after flip, resume guiding, settle
     time, max retries, failure action, sound alert, push
     notification)
   - Storage: `globalMeridianFlipSettingsProvider` (Riverpod
     StateNotifier) at
     `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart`
   - Consumer: **none** (provider is read only by the settings widget
     itself)
   - Classification: **NO-OP**
   - Evidence: `grep "globalMeridianFlipSettingsProvider"` returns 3
     matches — the settings widget, the provider definition, and a
     design doc. Neither the sequencer (`sequence_executor.dart`) nor
     any meridian watchdog reads this provider. The actual meridian
     flip behavior is configured **per-node** on each
     `MeridianFlipNode` inside a sequence (see
     `instruction_node_properties.dart` line 1184/1305 for
     `node.settleTimeout`).
   - Fix: This is a massive surface area. Either (a) make the
     `MeridianFlipNode` and the standalone watchdog actually consume
     `globalMeridianFlipSettingsProvider` as the default template, or
     (b) delete the entire "Meridian Flip" section from the Sequencer
     settings page since it cannot affect behavior.

6. **Exposure Triggers** — Sequencer toolbar → "Exposure Triggers"
   button
   - UI: `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_toolbar.dart:163-169`
     opens `TriggerConfigurationDialog`
     (`trigger_configuration_dialog.dart`)
   - Storage: dialog returns `_triggers` list via
     `Navigator.of(context).pop(_triggers)` (line 150)
   - Consumer: **none**
   - Classification: **NO-OP**
   - Evidence: `sequence_toolbar.dart:166-169` builds the dialog with
     `showDialog(...)` but **does not `await` the result** — the
     returned `_triggers` list is dropped on the floor. The dialog
     has its own `initialTriggers` parameter but `sequence_toolbar`
     passes `const TriggerConfigurationDialog()` so the user starts
     from an empty list every time. A grep for
     `ExposureTriggerConfig` outside its own file finds only
     `sequence_toolbar.dart`.
   - Fix: Persist exposure triggers (probably to the active sequence
     or to a new `app_settings` key), pass them back into the dialog
     on next open, and have the sequence executor consume them in
     `triggers.rs`.

7. **File Paths → Sequences / Database / Logs path** — Settings →
   File Paths
   - UI: `packages/nightshade_app/lib/screens/settings/widgets/file_path_settings.dart:95-141`
   - Storage: `setSequencesPath / setDatabasePath / setLogsPath` at
     `settings_provider.dart:1431-1444`
   - Consumer: **none** (only `imageOutputPath` is consumed; sequences
     live in SQLite, database location is the platform app-data
     folder, logs go to the platform default)
   - Classification: **NO-OP / DEAD-WRITE**
   - Evidence: the only readers of `sequencesPath`, `databasePath`,
     `logsPath` are
     `apps/desktop/lib/headless_api/handlers/filesystem_handlers.dart:219-221`
     (which only reports the value back to a remote client) and the
     settings widget itself. No service uses these to actually
     redirect storage.
   - Fix: Either wire each path through to the corresponding writer
     (DB open, log sink, sequence export), or remove the three rows
     and keep only "Image output".

8. **Standalone meridian monitoring toggle** — Settings →
   Sequencer → Meridian Flip
   - UI: `sequencer_settings.dart:94-106`
   - Storage: `globalMeridianFlipSettingsNotifier.setStandaloneMonitoringEnabled`
     at `meridian_flip_provider.dart:76`
   - Consumer: **none** — no service mounts a watchdog when this is
     true.
   - Classification: **NO-OP**
   - Evidence: grep `standaloneMonitoringEnabled` reaches only the
     settings widget, the model freezed files, the provider's own
     setter, and design docs. No timer, ticker, or scheduler
     subscribes to a state where this is true.
   - Fix: Either implement the standalone watcher (likely in
     `meridian_flip_provider.dart` itself, listening to mount state
     when `standaloneMonitoringEnabled && !sequenceRunning`) or remove
     the toggle.

9. **Temp compensation switch + temp coefficient** — Equipment →
   Settings tab → Focuser
   - UI: `apps/../equipment/tabs/settings_tab.dart:220-238`
   - Storage: `setTempCompensation / setTempCoefficient` at
     `settings_provider.dart:1501-1509`
   - Consumer: read at `status_bar.dart:1004` and
     `focus_model_panel.dart:40` — but only to drive a small UI HUD
     indicator. No service commands the focuser to move when
     temperature changes.
   - Classification: **PARTIAL**
   - Evidence: grep for `tempCompensation` outside model/provider
     returns only the two UI consumers above. There is no
     `FocusCompensationService` or temperature watcher that calls
     `focuserNotifier.move()` when the delta-T × coefficient exceeds
     a threshold. The `tempCoefficient` value is never read at all
     outside the freezed/g.dart.
   - Fix: Implement the compensation loop (subscribe to focuser
     temperature events, multiply by coefficient, command the
     focuser); or label the indicator as informational and remove the
     coefficient input.

10. **Auto dark subtraction + temperature tolerance** — Settings →
    Dark Library
    - UI: `dark_library_settings.dart:47-94`
    - Storage: `settingsDaoProvider.setSetting('dark_library.auto_subtract'…)`
      / `…temp_tolerance` at lines 56, 79
    - Consumer: providers exist
      (`autoDarkSubtractEnabledProvider`,
      `darkTempToleranceProvider` in
      `dark_library_provider.dart:52,62`) but **only the same
      settings widget reads them**. No image-capture pipeline applies
      automatic dark subtraction.
    - Classification: **NO-OP / DEAD-WRITE**
    - Evidence: grep across `packages/` and `native/` for
      `auto_subtract`, `temp_tolerance`, `autoDarkSubtract` finds
      only the writer in the widget and the providers — no
      `imaging_service`, `calibration_service`, or Rust pipeline
      consumes them. `calibrationSettingsProvider` (a different
      provider) is the one that actually controls the pipeline at
      `imaging_service.dart` and `calibration_service.dart`.
    - Fix: Either route dark-subtraction calibration through these
      two settings, or delete the rows.

11. **Mobile companion's mobile preferences UI is absent**
    - File: `apps/mobile/lib/services/mobile_preferences.dart`
    - There are 11 documented preferences (`androidImmersiveSticky`
      and ten `notify*` toggles), each of which has a reader in
      `mobile_event_notifier.dart` / `foreground_service.dart` /
      `notification_service.dart`.
    - However, no Flutter screen in `apps/mobile/lib/screens/`
      surfaces these. The mobile dashboard only shows
      camera/devices/log/mount/sequencer tabs.
    - Classification: **PARTIAL** — readers exist, but the user has
      no way to toggle them; they remain at default (all `true`)
      forever.
    - Fix: Add a "Settings" screen or modal on mobile that surfaces
      these eleven prefs.

---

## Medium findings (MED)

12. **Auto-save sequences toggle (General)** vs **Auto-Save category**
    - UI A: General → "Auto-save sequences" switch at
      `general_settings.dart:106-118`
    - UI B: Auto-Save category at
      `auto_save_settings.dart:142-150` ("Enable sequence auto-save")
    - The General toggle writes
      `app_settings.auto_save_sequences` via `setAutoSaveSequences`.
    - Consumer: **none** — `auto_save_service.dart` has its own
      `AutoSaveConfig.sequenceEnabled` (separate from `app_settings`),
      manipulated only via the Auto-Save category page.
    - Classification: **NO-OP / DEAD-WRITE**
    - Evidence: grep `autoSaveSequences` finds only the settings
      widget, the freezed model, and `_autoSaveSequences()` (a method
      name, not the field).
    - Fix: Remove the General row; the Auto-Save category is the real
      one.

13. **Plate Solving widget vs Plate Solving screen**
    - Two different screens persist plate-solver config.
    - **Widget version** (in the main Settings panel,
      `plate_solving_settings.dart`) writes to `appSettings.astapPath`
      / `astrometryPath` / `plateSolveTimeout` / `plateSolveSearchRadius`
      / `blindSolve` / `plateSolver`. Of these:
      - `astapPath` and `astrometryPath` ARE consumed (centering
        dialog, slew dropdown, mount control, capture tab — many
        sites)
      - `plateSolver`: consumed at
        `default_science_backend.dart:1569` for science backend label
      - `plateSolveTimeout`, `plateSolveSearchRadius`, `blindSolve`:
        **never read** — they remain pure UI state.
    - **Screen version** (`plate_solving_settings_screen.dart`, not
      reachable from the main Settings sidebar) writes to a separate
      `plateSolverPreferenceProvider` which IS consumed by
      `plate_solve_service.dart:447-491`.
    - Classification: **PARTIAL / NO-OP** depending on field
    - Fix: Pick one model. Delete the widget version's
      `plateSolveTimeout` / `searchRadius` / `blindSolve` rows
      because the actual `PlateSolveConfig` in
      `plate_solve_service.dart:36-46` is constructed from the caller,
      not from `AppSettings`.

14. **PHD2 executable path** — Settings → PHD2 Guiding
    - UI: `phd2_guiding_settings.dart:134-147`
    - Storage: `setPhd2Path` writes `app_settings.phd2_path`
    - Consumer: **none** — PHD2 is launched/connected by
      `device_service.dart:1692-1693` using only `phd2Host`/`phd2Port`.
      A grep for `phd2Path` outside its model/UI/database returns no
      hits in services.
    - Classification: **NO-OP / DEAD-WRITE**
    - Fix: Either auto-spawn PHD2 from this path on connect, or
      remove the row.

15. **Bit depth dropdown (16-bit / 32-bit)** — Settings → Imaging
    - UI: `imaging_settings.dart:88-106` and
      `camera_tab.dart:822-834`
    - Storage: `setBitDepth` writes `app_settings.bit_depth`
    - Consumer: only the camera_tab itself reads it back to show in
      the dropdown; no FITS/XISF/TIFF writer or capture path uses
      it. Cameras report bit_depth from sensor SDKs at the FFI level.
    - Classification: **NO-OP / DEAD-WRITE**
    - Fix: Remove. Bit depth is sensor-driven, not user-driven.

16. **Coordinated equipment cards** (Mount/Focuser/Guider/Camera in
    Equipment → Settings tab)
    - The cards write `coolingBehavior`, `defaultGain`,
      `defaultOffset`, `enableMeridianFlip`, `meridianFlipMinutes`,
      `parkOnUnsafeWeather`, `backlashCompensation`, `ditherScale`,
      `settleThreshold`, `settleTimeout` to `app_settings`.
    - **None** of these are consumed for hardware behavior. The
      capture pipeline reads `gain`/`offset` from the active
      equipment profile (`profileService`), the sequence node, or a
      per-frame UI override — never from these `AppSettings` fields.
      Likewise `ditherScale` / `settleThreshold` / `settleTimeout`
      live on the sequence's guiding node, not here.
    - Classification: **NO-OP / DEAD-WRITE** (all of them)
    - Fix: Either repoint the equipment cards to write to the active
      equipment profile / persisted guiding defaults, or delete the
      Equipment → Settings tab entirely (since Equipment Profiles
      already covers gain/offset, and Settings → Sequencer already
      covers dithering).

17. **Timezone dropdown + Use System Time switch** — Settings →
    Location → Time
    - UI: `location_settings.dart:355-396`
    - Storage: `setTimezone`, `setUseSystemTime` write
      `app_settings.timezone` / `use_system_time`
    - Consumer: **none** — grep for either key outside the writer
      shows zero readers. All app time math uses `DateTime.now()`
      directly or the platform TZ.
    - Classification: **NO-OP / DEAD-WRITE**
    - Fix: Remove the Time section, or implement a TZ override layer.

18. **Sound alerts switch (Notifications)** — Settings → Notifications
    - UI: `notification_settings.dart:166-181`
    - Storage: `setSoundEnabled` writes `app_settings.sound_enabled`
    - Consumer: **none** — grep for `soundEnabled|sound_enabled`
      reaches database seed, settings provider, settings widget — no
      `AudioPlayer`, `SystemSound.play`, `playSound`, or push channel
      reads it.
    - Classification: **NO-OP / DEAD-WRITE**
    - Fix: Hook the `NotificationService` to silence sounds when
      false (it currently plays the platform default
      unconditionally), or remove the toggle.

19. **autoResumeEnabled** — Settings → Weather Safety → Actions
    - UI: `weather_safety_settings.dart:120-132`
    - Storage: `weatherSettingsDao.updateSettings(autoResumeEnabled:…)`
    - Consumer: **none** — `weather_safety_provider.dart` evaluates
      `autoParkEnabled` but never `autoResumeEnabled`; resume is
      always manual (snooze + clear alert).
    - Classification: **NO-OP / DEAD-WRITE**
    - Fix: Wire the resume path in `weather_safety_provider` or hide
      the toggle.

20. **indi_auto_connect / alpaca_auto_discover** — exposed via
    setters but no UI surface
    - Both setters exist in `settings_provider.dart:1458, 1473` but
      the main settings screens don't surface them. They only appear
      as in-call defaults of `unified_discovery_provider.dart`.
    - Classification: **NO-OP (no UI)** — listed here as a curiosity:
      writable via API but unreachable from the desktop UI.
    - Fix: either surface them in Connection settings or remove the
      setters.

21. **uiScale string in `AppSettings`** — read but never settable
    - UI: there is **no** UI control to set `uiScale`. The field is
      consumed in `app.dart:143`.
    - Classification: **STALE-DEFAULT** — always `'Auto'`
    - Fix: Either add the dropdown to Appearance Settings (the
      enum strings are already documented in the model
      comment: `Auto, Small (0.8x), Normal (1.0x), Large (1.2x),
      Extra Large (1.4x)`), or remove the field.

---

## Low findings (LOW)

22. **Connect / Disconnect button in Connection settings** — the
    server-connect dialog hardcodes `text: 'localhost'` and `text:
    '8080'` (`connection_settings.dart:206-207`). It does **not**
    pre-fill from the persisted `indiServerHost` / `alpacaServerHost`
    / last-connected address. Minor usability gap.

23. **NotificationSettings duplicate keys** — both Discord webhook
    and Pushover key/user are masked (or not) in the text input — no
    impact on function, but no `obscureText: true` on the input
    means credentials are shown in plaintext.

24. **Mobile preferences are documented as "default ON, opt-out"**
    in `mobile_preferences.dart:48-50`, but the actual mobile app
    never exposes the opt-out UI (see HIGH #11). Documentation and
    behavior are aligned only insofar as nobody can change them.

---

## All settings, by screen (table)

Legend: OK = wired, ND = no-op / dead-write, P = partial, SD =
stale-default.

| Screen | Setting | Class | Evidence |
|---|---|---|---|
| Settings → Connection | (none — informational) | OK | only reads `backendProvider` |
| Settings → General | Start minimized | OK | `desktop_app_bootstrap.dart:317` |
| Settings → General | Auto-connect equipment | OK | `profiles_tab.dart:540` |
| Settings → General | Language (en/es) | OK | `app.dart:155` |
| Settings → General | Auto-save sequences | ND | no consumer (see MED #12) |
| Settings → General | Confirm before closing | OK | `app_shell.dart:66` |
| Settings → Appearance | Theme dark/light | OK | `app.dart:140` |
| Settings → Appearance | Accent color | OK | `app.dart:141` |
| Settings → Appearance | Font size | OK | `app.dart:142` |
| Settings → Appearance | Sidebar collapsed default | OK | `app_shell.dart:388,491` |
| Settings → Appearance | (UI scale — no control) | SD | always `'Auto'` (see LOW #21) |
| Settings → Location | Latitude / Longitude / Elevation | OK | `appObserverLocationProvider`, planetarium, scheduler |
| Settings → Location | Bortle class | OK | `bortleClassProvider` |
| Settings → Location | Horizon mask (8 directions) | OK | `horizonProfileProvider` |
| Settings → Location | Timezone | ND | (LOW: only the writer) |
| Settings → Location | Use system time | ND | (LOW: only the writer) |
| Settings → Equipment Profiles | (list manager) | OK | profile-based |
| Settings → Catalogs | (list manager) | OK | catalog provider |
| Settings → Imaging | Image format (FITS/XISF/TIFF) | OK | `imaging_provider.dart:207`, `camera_tab.dart:786` |
| Settings → Imaging | Bit depth (16/32) | ND | (MED #15) |
| Settings → Imaging | File naming pattern | OK | `namingPatternProvider` |
| Settings → Dark Library | Auto dark subtraction | ND | (HIGH #10) |
| Settings → Dark Library | Temp tolerance | ND | (HIGH #10) |
| Settings → Calibration | Auto-calibrate | OK | `calibration_service.dart`, `imaging_service.dart` |
| Settings → Calibration | Master flat / bias / dark paths | OK | `calibration_service.dart` |
| Settings → Weather Safety | Enable safety | OK | `weather_safety_provider.dart` |
| Settings → Weather Safety | Auto-park enabled | OK | `weather_safety_provider.dart:240,273` |
| Settings → Weather Safety | Auto-resume enabled | ND | (MED #19) |
| Settings → Weather Safety | Max humidity / wind / cloud | OK | `weather_safety_provider.dart:309-320` |
| Settings → Weather Safety | Trigger distance, lead time | OK | `weather_alert_service.dart` |
| Settings → Autofocus | All `af_*` fields | OK | `device_service.dart:2612-2629` (consumed via `appSettings.af*`) |
| Settings → Autofocus | Use filter focus offsets | OK | `filter_offset_provider.dart:85`, `device_service.dart:2878` |
| Settings → Science | Advanced mode / overlay / per-feature | OK | `scienceSettingsProvider` |
| Settings → Annotations | All fields | OK | `annotation_pipeline.dart`, `click_identify_service.dart` |
| Settings → Sequencer → Safety | Park on unsafe weather | ND | **HIGH #1** |
| Settings → Sequencer → Safety | Park before dawn | ND | **HIGH #2** |
| Settings → Sequencer → Safety | Safety fail mode | SD | **HIGH #3** (UI suggests choice, setter forces `failClosed`) |
| Settings → Sequencer → Meridian Flip | All 16 rows | ND | **HIGH #5** |
| Settings → Sequencer → Auto Focus | Auto focus on filter change | ND | **HIGH #4** |
| Settings → Sequencer → Auto Focus | Auto focus interval (min) | ND | **HIGH #4** |
| Settings → Sequencer → Dithering | Enable dithering | ND | **HIGH #4** |
| Settings → Sequencer → Dithering | Dither every N frames | ND | **HIGH #4** |
| Settings → Sequencer → Development | Use native execution | OK | `sequence_executor.dart:65` |
| Settings → Sequencer → Development | Simulation mode | OK | `sequence_executor.dart:82`, `sequence_toolbar.dart:260` |
| Settings → Plate Solving (widget) | Primary solver | OK | `default_science_backend.dart:1569` |
| Settings → Plate Solving (widget) | ASTAP path | OK | many consumers (centering, capture, mount control) |
| Settings → Plate Solving (widget) | Astrometry path | OK | similar |
| Settings → Plate Solving (widget) | Timeout | ND | (MED #13) |
| Settings → Plate Solving (widget) | Search radius | ND | (MED #13) |
| Settings → Plate Solving (widget) | Blind solve | ND | (MED #13) |
| Settings → PHD2 Guiding | Host | OK | `device_service.dart:1692`, `phd2_connection_dialog.dart:32` |
| Settings → PHD2 Guiding | Port | OK | `device_service.dart:1693` |
| Settings → PHD2 Guiding | PHD2 executable path | ND | **MED #14** |
| Settings → Notifications | Enable notifications | OK | `notification_service.dart:82` |
| Settings → Notifications | Sound alerts | ND | **MED #18** |
| Settings → Notifications | Notify on sequence complete | OK | `notification_service.dart:171` |
| Settings → Notifications | Notify on error | OK | `notification_service.dart:173` |
| Settings → Notifications | Notify on meridian flip | OK | `notification_service.dart:175` |
| Settings → Notifications | Discord webhook | OK | `notification_service.dart:190-197` |
| Settings → Notifications | Pushover key / user | OK | `notification_service.dart:246-255` |
| Settings → Notifications | Push to mobile (all sub-toggles) | OK | `push_notification_provider.dart` / `push_notification_service.dart` |
| Settings → File Paths | Image output path | OK | `imaging_service.dart:277,568`, sequence executor, disk space guard |
| Settings → File Paths | Sequences path | ND | **HIGH #7** |
| Settings → File Paths | Database path | ND | **HIGH #7** |
| Settings → File Paths | Logs path | ND | **HIGH #7** |
| Settings → Remote Access | Web server enabled | OK | `desktop_app_bootstrap.dart:158` |
| Settings → Remote Access | Web server port | OK | `desktop_app_bootstrap.dart:164` |
| Settings → Logs | (viewer, not settings) | n/a | — |
| Settings → Auto-Save | Sequence enabled / interval | OK | `autoSaveServiceProvider`, `auto_save_service.dart:131` |
| Settings → Auto-Save | Backup enabled / interval / max backups | OK | `auto_save_service.dart` |
| Settings → Observation Log | (viewer / exporter) | n/a | — |
| Settings → Observing Lists | (list manager) | n/a | — |
| Settings → Help & Tutorials | (action buttons) | OK | tutorial provider |
| Settings → About | (informational) | n/a | — |
| Equipment → Settings (tab) | Cooling behavior | ND | **MED #16** |
| Equipment → Settings (tab) | Default gain | ND | **MED #16** (real source = profile) |
| Equipment → Settings (tab) | Default offset | ND | **MED #16** |
| Equipment → Settings (tab) | Meridian flip enable | ND | **MED #16** |
| Equipment → Settings (tab) | Meridian flip minutes | ND | **MED #16** |
| Equipment → Settings (tab) | Park on unsafe | ND | duplicate of HIGH #1 |
| Equipment → Settings (tab) | Temp compensation | P | **HIGH #9** (UI HUD only, no actuation) |
| Equipment → Settings (tab) | Temp coefficient | P | **HIGH #9** (read nowhere outside model) |
| Equipment → Settings (tab) | Backlash compensation | ND | (AF backlash uses separate `af_backlash_*` keys) |
| Equipment → Settings (tab) | Dither scale | ND | (sequence-node property is the real source) |
| Equipment → Settings (tab) | Settle threshold | ND | (sequence-node property is the real source) |
| Equipment → Settings (tab) | Settle timeout | ND | (sequence-node property is the real source) |
| Sequencer toolbar | "Exposure Triggers" dialog | ND | **HIGH #6** |
| Polar Alignment screen | (config — out of scope) | n/a | — |
| Flat Wizard | (config — out of scope) | n/a | — |
| Mobile companion | androidImmersiveSticky | P | reader exists, no UI (HIGH #11) |
| Mobile companion | 10× `notify*` toggles | P | readers exist, no UI (HIGH #11) |

---

## Notes & recommendations

- The biggest leverage cleanup is **HIGH #5** (Meridian Flip) — it's
  16 rows of UI feeding a 100% dead provider. Deleting it (or
  wiring it through) would significantly de-risk user expectations.
- HIGH #6 (Exposure Triggers) is a one-line bug: the dialog's
  `Navigator.pop(_triggers)` result is discarded. Easy fix
  candidate.
- HIGH #3 (Safety fail mode) is intentional per v2.5 hardening
  (`docs/production-readiness/fail-closed-audit.json`), but the UI
  still presents a dropdown that suggests user choice. Replacing it
  with a read-only "Enforced fail-closed" pill would match user
  expectations.
- Most NO-OPs trace to the same pattern: the `AppSettings` model
  accumulated fields during early development that were superseded
  by dedicated providers but never removed. A model audit could
  shrink `AppSettings` significantly by deleting the obsolete
  fields (and their setters, migrations, default-seed rows, and UI
  controls together).
- `nightshade_app/lib/screens/equipment/tabs/settings_tab.dart` is
  a stronger candidate for deletion: every row except the (also
  no-op) temp-comp pair duplicates fields that are owned elsewhere.
