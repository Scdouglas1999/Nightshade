# Providers / state audit — 2026-05-16

Branch: `release/v2.5.0-hardening` | HEAD: `74abe34`

## Summary

- **575** unique provider names declared across `packages/` and `apps/` (excludes `*.g.dart` / `*.freezed.dart` / generated).
- **~104 DEAD** (declared but only the declaration site itself references the name globally).
- **3 DUPLICATE name collisions** (multiple files declare a provider with the same identifier; all three are `sessionImagesProvider`/`targetSearchProvider` cases).
- **6 REPLACED-BY-NEWER** (older providers superseded by Notifier-based equivalents but never deleted).
- **~36 WRITE-ONLY** (write paths exist but nothing watches; concentrated in `meridian_flip_provider.dart`).
- **45 family providers without autoDispose** — most are intentional (capabilities, session DAO), but two new F4/F5 additions are real leaks (see below).
- **1 confirmed missing-mounted-check** in a backend event listener (`Phd2Controller`).
- Longest provider-dependency chain depth: **6** (`targetAlertProvider`, `hasUnsavedChangesProvider`, `altitudeInfoProvider`, etc.). No 5+ hot path is itself a UI-bound rebuild storm.

The DEAD count dominates everything else. The repository is carrying ~104 unused providers; one major dead cluster (`meridian_flip_provider.dart`) totals 14 inter-referenced but externally-unreachable providers. F5 (`catalogOverlayQueryProvider`) and F1 (`sessionReportProvider`/`campaignRollupProvider`) have real missing-autoDispose leaks on family providers.

---

## Dead providers (no external consumer)

These are 1-reference providers (the declaration site only) confirmed by `grep -rn '\bname\b' packages/ apps/`. They have no `ref.watch`, `ref.read`, `ref.listen`, `.notifier`, `.future`, `.select`, or `ref.invalidate` consumer anywhere in the tree.

### Cluster 1 — Meridian Flip subsystem (14 dead providers, internal references only)

The entire `meridian_flip_provider.dart` module updates state from `MeridianFlipDisconnectGuard` but nothing in the UI watches the resulting providers. The actual flip-progress dialog uses a `Stream<MeridianFlipEvent>` passed directly to its constructor, bypassing the provider layer.

- `meridianFlipEventStreamProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:196`
- `flipExecutionStateProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:240` — only written by the disconnect guard
- `flipCurrentAttemptProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:248`
- `flipCurrentStepProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:254`
- `flipProgressProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:257`
- `flipLastErrorProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:260`
- `isFlipInProgressProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:263`
- `meridianFlipDisconnectGuardProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:307` — doc says "must be watched (e.g., by the app shell) so it stays alive" but the app shell never watches it. **The mount-disconnect safety reset documented in lines 268–301 never runs.**
- `isMeridianFlipEnabledProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:316`
- `effectiveMeridianFlipSettingsProvider` at `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart:166` — only referenced by other dead providers in the same file
- Fix: either wire `meridianFlipDisconnectGuardProvider` into `app_shell.dart` (it has a real safety purpose) and delete the rest, or delete the whole module if meridian flip uses its own internal stream pathway.

### Cluster 2 — Imaging-screen StateProviders superseded by `imagingViewerStateProvider`

- `imageZoomProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:299`
- `imagePanOffsetProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:302`
- `imageFitModeProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:313`
- Fix: delete; replaced by `imagingViewerStateProvider` at `packages/nightshade_core/lib/src/providers/imaging_viewer_state_provider.dart:126`. `imaging_screen.dart:301` already documents the replacement.

### Cluster 3 — Overlay toggles superseded by `annotation_settings_provider`

- `showStatsOverlayProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:250`
- `showStarOverlayProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:244`
- `showHistogramOverlayProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:247`
- `showGridOverlayProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:320`
- `showCrosshairProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:317`
- `previewStretchProvider` at `packages/nightshade_core/lib/src/providers/auto_stretch_provider.dart:766`
- `stretchedImageInfoProvider` at `packages/nightshade_core/lib/src/providers/auto_stretch_provider.dart:733`
- `stretchParamsProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:57`
- `autoStretchProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:62` — superseded by `autoStretchSettingsProvider` at line 67
- `captureModeProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:227`
- `frameCountTargetProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:232`
- `starDetectionConfigProvider` at `packages/nightshade_core/lib/src/providers/imaging_provider.dart:235`

### Cluster 4 — Planetarium catalog/queue (8 dead providers)

- `visibleSatellitesProvider` at `packages/nightshade_planetarium/lib/src/providers/satellite_providers.dart:149`
- `visibleMinorPlanetsProvider` at `packages/nightshade_planetarium/lib/src/providers/minor_planet_providers.dart:120`
- `visibleDsosProvider` at `packages/nightshade_planetarium/lib/src/providers/catalog_providers.dart:219`
- `brightVariableStarsProvider` at `packages/nightshade_planetarium/lib/src/providers/variable_star_providers.dart:24`
- `brightStarsProvider` / `messierObjectsProvider` / `starSearchProvider` / `dsoSearchProvider` / `starCountProvider` / `dsoCountProvider` / `catalogsNeedDownloadProvider` at `packages/nightshade_planetarium/lib/src/providers/catalog_providers.dart`
- `tonightsBestTargetsProvider`, `targetAlertProvider`, `moonProximityProvider`, `altitudeInfoProvider` at `packages/nightshade_planetarium/lib/src/providers/planning_providers.dart` — likely intended for a tonight-card overlay that never shipped.
- `queueProgressProvider`, `pendingTargetsCountProvider`, `activeTargetProvider` at `packages/nightshade_planetarium/lib/src/providers/target_queue_provider.dart`
- `isTouchDeviceProvider`, `hasContextMenuProvider` at `packages/nightshade_planetarium/lib/src/providers/platform_providers.dart`

### Cluster 5 — Device discovery siblings (3 of 9 dead)

- `availableDomesProvider` at `packages/nightshade_core/lib/src/services/device_service.dart:3130`
- `availableWeatherProvider` at `packages/nightshade_core/lib/src/services/device_service.dart:3135`
- `availableSafetyMonitorsProvider` at `packages/nightshade_core/lib/src/services/device_service.dart:3140`
- `availableFilterWheelsProvider`, `availableGuidersProvider`, `availableRotatorsProvider` (rows 3113/3120/3125) also dead despite siblings being live (mobile devices_tab.dart consumes only Cameras/Mounts/Focusers).
- `unifiedDomesProvider`, `unifiedWeatherProvider`, `unifiedSafetyMonitorsProvider` at `packages/nightshade_core/lib/src/providers/unified_discovery_provider.dart:400/406/412`. The six live siblings (`unifiedCameras/Mounts/Focusers/FilterWheels/Guiders/Rotators`) are wired to per-device-type cards under `screens/equipment/tabs/connections/`. The three dead ones have no card and no other consumer.

### Cluster 6 — Capability providers for non-camera/mount devices

- `focuserCapabilitiesProvider` at `packages/nightshade_core/lib/src/providers/capability_provider.dart:23`
- `filterWheelCapabilitiesProvider` at `packages/nightshade_core/lib/src/providers/capability_provider.dart:31`
- `rotatorCapabilitiesProvider` at `packages/nightshade_core/lib/src/providers/capability_provider.dart:39`
- Likely capability inspection that was planned per-device but only wired for `cameraCapabilitiesProvider` (used by `disk_space_provider.dart`).

### Cluster 7 — Polar alignment / database / settings (declared but never consumed)

- `polarAlignmentHistoryStreamProvider` at `packages/nightshade_core/lib/src/providers/polar_alignment_provider.dart:556`
- `lastPolarAlignmentProvider` at `packages/nightshade_core/lib/src/providers/polar_alignment_provider.dart:548`
- `allDbSequencesProvider` at `packages/nightshade_core/lib/src/providers/database_provider.dart:94`
- `allDbTemplatesProvider` at `packages/nightshade_core/lib/src/providers/database_provider.dart:99`
- `favoriteDbTargetsProvider` at `packages/nightshade_core/lib/src/providers/database_provider.dart:84`
- `capturedImageByIdProvider` at `packages/nightshade_core/lib/src/providers/database_provider.dart:122`
- `themeSettingsProvider` at `packages/nightshade_core/lib/src/providers/settings_provider.dart:2027`
- `locationSettingsProvider` at `packages/nightshade_core/lib/src/providers/settings_provider.dart:1797`
- `plateSolveSettingsProvider` at `packages/nightshade_core/lib/src/providers/settings_provider.dart:2003`
- `darkFrameEntriesProvider` / `biasFrameEntriesProvider` at `packages/nightshade_core/lib/src/providers/dark_library_provider.dart:25/31`
- `activeListCatalogIdsProvider` at `packages/nightshade_core/lib/src/providers/observing_list_provider.dart:29`
- `eventHistoryProvider` at `packages/nightshade_core/lib/src/providers/event_provider.dart:77`
- `lastEventProvider` at `packages/nightshade_core/lib/src/providers/event_provider.dart:49`
- `errorServiceProvider` at `packages/nightshade_core/lib/src/services/error_service.dart:365`
- `loggingInitializerProvider` at `packages/nightshade_core/lib/src/services/logging_service.dart:366` — explicitly named "initializer" but main.dart never awaits it.

### Cluster 8 — Science / transient / suggestion module orphans

- `transientAlertByIdProvider`, `queuedAlertsProvider` at `packages/nightshade_core/lib/src/providers/transient_alert_provider.dart:647/484`
- `transformForFilterProvider`, `allPhotometricTransformsProvider` at `packages/nightshade_core/lib/src/providers/photometric_transform_provider.dart:41/13`
- `topSuggestionsProvider`, `suggestionsByTypeProvider`, `bestSuggestionProvider`, `incompleteSuggestionsProvider` at `packages/nightshade_core/lib/src/providers/target_suggestion_provider.dart:292/307/385/369`
- `sessionMovingObjectTrendProvider`, `currentScienceFrameProductsProvider` at `packages/nightshade_core/lib/src/providers/science_provider.dart:722/930`
- `quickStartAvailableProvider`, `quickStartContextsProvider` at `packages/nightshade_core/lib/src/services/quick_start_service.dart:761/767`
- `targetProgressProvider` at `packages/nightshade_core/lib/src/providers/target_progress_provider.dart:24` — added in `[W8-SCHED-HISTORY]` but never wired to a UI consumer.
- `sessionHandoffServiceProvider` at `packages/nightshade_core/lib/src/providers/session_handoff_provider.dart:6`
- `sessionServiceStatusProvider` at `packages/nightshade_core/lib/src/providers/session_provider.dart:392`
- `isSessionActiveProvider` at `packages/nightshade_core/lib/src/providers/session_provider.dart:403`
- `liveStackingFrameCountProvider` at `packages/nightshade_core/lib/src/providers/live_stacking_provider.dart:237`
- `filteredObservationLogsProvider` at `packages/nightshade_core/lib/src/providers/observation_log_provider.dart:197`
- `filterOffsetForFilterProvider` at `packages/nightshade_core/lib/src/providers/filter_offset_provider.dart:275`
- `hasExplicitBackendSelectionProvider` at `packages/nightshade_core/lib/src/providers/device_backend_selection_provider.dart:62`
- `paginatedSessionImagesProvider` at `packages/nightshade_core/lib/src/services/paginated_image_loader.dart:249`
- `mobilePreferencesProvider` at `apps/mobile/lib/services/mobile_preferences.dart:101`
- `pushNotificationStreamProvider` at `packages/nightshade_core/lib/src/providers/push_notification_provider.dart:176` (F2 feature — see below; the **service** provider _is_ used but the **stream** provider isn't)
- `qualityAdjustmentSuggestionProvider` at `packages/nightshade_planetarium/lib/src/providers/performance_providers.dart:131`
- `sequenceRunsForSequenceProvider` at `packages/nightshade_core/lib/src/providers/sequence_stats_provider.dart:248`
- `plateSolveStateProvider` at `packages/nightshade_core/lib/src/services/plate_solve_service.dart:736`
- `sequencerExpandedPanelProvider` at `packages/nightshade_app/lib/screens/sequencer/sequencer_screen.dart:35` — declared next to live sibling `sequencerTabProvider`; never read.
- `weatherProviders.dart`: `currentAlertLevelProvider` (line 239), `isWeatherSafeProvider` at `weather_safety_provider.dart:398`
- `appThemeModeProvider` at `packages/nightshade_ui/lib/src/theme/nightshade_theme.dart:24`
- `annotationOpacityProvider` at `packages/nightshade_core/lib/src/providers/annotation_settings_provider.dart:58`
- `uiExtensionPointsProvider` at `packages/nightshade_plugins/lib/src/plugin_host.dart:359`

Full file-level breakdown of dead-provider counts:

| File | Dead |
|---|---:|
| `packages/nightshade_core/lib/src/providers/imaging_provider.dart` | 13 |
| `packages/nightshade_planetarium/lib/src/providers/catalog_providers.dart` | 8 |
| `packages/nightshade_core/lib/src/providers/meridian_flip_provider.dart` | 4 + 10 internal-only (see cluster 1) |
| `packages/nightshade_core/lib/src/services/device_service.dart` | 6 |
| `packages/nightshade_planetarium/lib/src/providers/planning_providers.dart` | 4 |
| `packages/nightshade_core/lib/src/providers/target_suggestion_provider.dart` | 4 |
| `packages/nightshade_core/lib/src/providers/database_provider.dart` | 4 |
| `packages/nightshade_planetarium/lib/src/providers/target_queue_provider.dart` | 3 |
| `packages/nightshade_core/lib/src/providers/unified_discovery_provider.dart` | 3 |
| `packages/nightshade_core/lib/src/providers/transient_alert_provider.dart` | 3 |
| `packages/nightshade_core/lib/src/providers/settings_provider.dart` | 3 |
| `packages/nightshade_core/lib/src/providers/capability_provider.dart` | 3 |

---

## Duplicates (same identifier in multiple files)

### `sessionImagesProvider` — three independent declarations, three different types

1. `packages/nightshade_core/lib/src/providers/imaging_provider.dart:267` — `StateNotifierProvider<SessionImagesNotifier, List<CapturedImage>>` (in-memory list, written by `ImagingService.addImage`, read by `capture_panel.dart` and `live_preview_area.dart`).
2. `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart:484` — `StreamProvider.family<List<DbCapturedImage>, int>` (DB-backed live stream).
3. `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard.dart:1193` — `FutureProvider.family<List<DbCapturedImage>, int>` (one-shot DB fetch).

All three are imported by name at different sites without conflicting because they live in unrelated import scopes. This is a footgun: a future refactor that adds a barrel export would collide, and intent ("which session-images do I mean?") is non-obvious to readers. Rename two of them (e.g., `dbSessionImagesProvider`, `calibrationSessionImagesProvider`).

### `targetSearchProvider` — duplicate name across screen vs core

1. `packages/nightshade_app/lib/screens/framing/framing_search_provider.dart:173` — `StateNotifierProvider.autoDispose<TargetSearchNotifier, TargetSearchState>` — actively used by the Framing screen.
2. `packages/nightshade_core/lib/src/providers/framing_provider.dart:1686` — `StateNotifierProvider<TargetSearchNotifier, TargetSearchState>` (no `autoDispose`) — referenced **only by `test/providers/dispose_hooks_test.dart`**; every importer of `nightshade_core.dart` has to `hide TargetSearchState, targetSearchProvider` (8 files do exactly that, see `framing_screen.dart:7`).
3. The CQ-W15-CLEANUP commit (`4963ff3`) removed `apps/desktop/lib/screens/framing/framing_search_provider.dart` but the core duplicate survived. **Action: delete `packages/nightshade_core/lib/src/providers/framing_provider.dart:1686`** and update `dispose_hooks_test.dart` to import the screen-local provider.

---

## Replaced-by-newer (effective duplicates)

| Old (dead) | New (live) |
|---|---|
| `autoStretchProvider` (`imaging_provider.dart:62`) | `autoStretchSettingsProvider` (`imaging_provider.dart:67`) |
| `stretchParamsProvider`, `previewStretchProvider`, `stretchedImageInfoProvider` | `autoStretchSettingsProvider` + `stretchedImageProvider` (live) |
| `imageZoomProvider`, `imagePanOffsetProvider`, `imageFitModeProvider` (3) | `imagingViewerStateProvider` (`imaging_viewer_state_provider.dart:126`) |
| `targetSearchProvider` (core, `framing_provider.dart:1686`) | `targetSearchProvider` (screen-local, `framing_search_provider.dart:173`) |

---

## Write-only providers (state changes but UI never observes)

The biggest write-only cluster is the meridian-flip set (cluster 1 above). The disconnect guard writes `flipExecutionState`, `flipCurrentStep`, `flipProgress`, `flipCurrentAttempt`, `flipLastError` on mount-disconnect, but nothing watches them, so the writes are no-ops. Other small examples:

- `sequencerExpandedPanelProvider` — only declared, no consumer.
- `errorServiceProvider` — `ErrorService` is reachable via `loggingServiceProvider` in practice; this top-level wrapper has no caller.
- `_tonightOptimizationPlanProvider` and similar private dialog providers all checked out OK.

---

## Missing-autoDispose (focused on W14/W15/F1-F5 polish work)

W13 added `.autoDispose` broadly. The following providers added during W14/W15/F1-F5 lack it and have real memory-leak potential:

### F5 — `catalogOverlayQueryProvider`

`packages/nightshade_core/lib/src/providers/catalog_overlay_provider.dart:86`

```dart
final catalogOverlayQueryProvider =
    FutureProvider.family<CatalogOverlayResult, CatalogOverlayQuery>(...)
```

`CatalogOverlayQuery` has value-equality on `(wcs.raHours, wcs.decDegrees, wcs.rotationDeg, wcs.pixelScaleArcsec, wcs.imageWidth, wcs.imageHeight, magnitudeLimit, includeStars, includeDsos)`. Consumer is `packages/nightshade_app/lib/widgets/catalog_overlay_widget.dart:85`, which constructs a new `CatalogOverlayQuery` on every build pass that includes the live WCS. As the user pans/zooms a plate-solved frame, the WCS center drifts and every distinct combination gets a permanent cache entry holding the full `CatalogOverlayResult` (star + DSO lists). **Fix: `.autoDispose.family`**.

### F1 — `sessionReportProvider`, `campaignRollupProvider`

- `packages/nightshade_core/lib/src/providers/session_report_provider.dart:26` — `FutureProvider.family<SessionReport, int>` keyed by `sessionId`. Used by `session_report_dialog.dart:37` (dialog scope). Should be `.autoDispose.family` so closing the dialog frees the report.
- `packages/nightshade_core/lib/src/providers/campaign_rollup_provider.dart:23` — `FutureProvider.family<CampaignRollup, int>` keyed by `targetId`. Builds multi-night rollups by walking all sessions; consumed only by the analytics rollup panel. Should be `.autoDispose.family`.

### Other family providers without autoDispose (45 total)

Most are intentional caches that survive page navigation (capability lookups, science-session DAO queries). The ones potentially worth re-examining:

- `imagingHistoryProvider` (`imaging_history_provider.dart:90`)
- `observingListItemsProvider` (`observing_list_provider.dart:18`)
- `polarAlignmentHistoryProvider` (`polar_alignment_provider.dart:537`)
- `integrationGoalProgressProvider` (`scheduler_provider.dart:382`)
- `defectMapStatusProvider` (`defect_map_provider.dart:46`)
- `selectedBackendForDeviceProvider` (`device_backend_selection_provider.dart:55`)
- Most `science_provider.dart` per-session families (lines 558-722) — large payloads, family-keyed by `sessionId`; user may open many sessions in one app run.

---

## Anti-patterns

### Missing `mounted` check in StateNotifier event listener

**`packages/nightshade_core/lib/src/providers/guiding_provider.dart:243`** (`Phd2Controller._init`)

```dart
_eventSub = backend.eventStream.listen((event) {
  if (event.category != EventCategory.guiding) return;
  // ... 30+ lines of `state =` / `ref.read(...notifier).state =` ...
});
```

Despite the project memory rule ("Always add `mounted` checks in StateNotifier event listeners"), this controller does not gate any of its state mutations behind `if (!mounted) return;`. The event stream is broadcast and survives the notifier — if the controller is disposed while a `GuideStep` event is in flight, all 10+ writes after line 245 will throw on a disposed notifier or silently update phantom state.

Compare with the correct pattern at `packages/nightshade_core/lib/src/providers/autofocus_progress_provider.dart:115-117` and `packages/nightshade_core/lib/src/providers/event_provider.dart:64-70` which both guard with `if (!mounted) return;`.

### `state = ...` after `await` without `mounted` check

Concentrated in two **`autoDispose`** notifiers (highest risk because they can be disposed between awaits):

- `packages/nightshade_app/lib/screens/framing/framing_search_provider.dart` — `TargetSearchNotifier.search()` does `state = TargetSearchState(...)` on lines 152 and 158 after `await catalog.search(...)`. Provider is `.autoDispose` (line 173). If user navigates away during a slow search, the dispatch fires on a disposed notifier.
- `packages/nightshade_core/lib/src/providers/framing_provider.dart` — same pattern in `MosaicNotifier` (lines 952, 1011).

Lower-risk (non-autoDispose) post-await assignments in 25+ other notifiers exist but only matter if a user-action path can outlive the screen (e.g. session-scoped notifiers re-mount).

### `ref.read` in `build()` of a value provider (anti-pattern check)

After filtering out callbacks (`onTap`, `onPressed`, etc.) and service/notifier reads, the heuristic scan returned **0 confirmed cases** at top-level of `build`. The 26 raw hits in the scan all resolve to: (a) inside callback closures (legitimate `ref.read`), (b) `ref.read(...notifier)` to invoke methods, or (c) sync helpers called from callbacks.

---

## Provider dependency hot spots (chain depth ≥ 5)

Computed by recursively resolving `ref.watch(...Provider)` inside each provider's body (capped at depth, cycle-safe).

| Depth | Provider | Direct deps |
|---:|---|---|
| 6 | `targetAlertProvider` (`planning_providers.dart:69`) | `selectedTargetScoreProvider` → `selectedObjectProvider` + `targetScoringServiceProvider` |
| 6 | `hasUnsavedChangesProvider` (`auto_save_service.dart:419`) | `autoSaveServiceProvider` |
| 6 | `densityHotspotsProvider` (`planetarium_providers.dart:1957`) | `densityHotspotsDataProvider`, `skyViewStateProvider` |
| 6 | `altitudeInfoProvider` (`planning_providers.dart:164`) | `observationTimeProvider`, `selectedTargetScoreProvider` |
| 5 | `weatherStatusProvider` (`weather_providers.dart:255`) | `evaluateWeatherConditionsProvider`, `weatherAlertStreamProvider`, `weatherRadarFramesProvider` |
| 5 | `fovFilteredStarsProvider` / `fovFilteredDsosProvider` (`planetarium_providers.dart:779/798`) | `dynamicMagnitudeLimitsProvider`, `skyViewStateProvider`, spatial-index providers |
| 5 | `unacknowledgedAlertCountProvider` (`transient_alert_provider.dart:467`) | `activeTransientAlertsProvider`, `transientAlertStatesProvider` |
| 5 | suggestion-filter chain: `filteredSuggestionsProvider`, `plannerFilteredSuggestionsProvider`, `plannerFilterExclusionProvider`, `availableSizeRangeProvider` | all watch `suggestionFilterProvider` + `tonightSuggestionsProvider` |

**Notes:** Most depth-6 chains terminate at a small set of root providers (`backendProvider`, `appSettingsProvider`, `skyViewStateProvider`, `selectedObjectProvider`). The planetarium FOV chain (`fovFilteredStarsProvider` watches `skyViewStateProvider`) is the only one that updates on every camera pan; the depth is fine but `skyViewStateProvider` mutations propagate through 5 providers per frame. This is not new in W14/W15.

Half of the depth-5 chain providers are themselves **dead** (`targetAlertProvider`, `altitudeInfoProvider`, `moonProximityProvider`, `topSuggestionsProvider`, `bestSuggestionProvider`, etc.) — deleting the dead ones will collapse much of the dependency graph.

---

## Recommended cleanup order

1. **Delete the 14-provider meridian-flip cluster** in `meridian_flip_provider.dart` (after deciding whether `meridianFlipDisconnectGuardProvider` should be wired into the app shell — its safety purpose is real).
2. **Delete the 13 stale imaging-screen providers** in `imaging_provider.dart` superseded by `imagingViewerStateProvider` and `autoStretchSettingsProvider`.
3. **Delete one of the two `targetSearchProvider`s** (the core one, after migrating `dispose_hooks_test.dart`).
4. **Add `.autoDispose` to F5/F1 family providers**: `catalogOverlayQueryProvider`, `sessionReportProvider`, `campaignRollupProvider`.
5. **Add `if (!mounted) return;` to `Phd2Controller._init` event listener** in `guiding_provider.dart`.
6. **Rename `sessionImagesProvider` ×3** so the three flavors are distinguishable.
7. **Delete the 8 dead planetarium catalog/queue providers** (cluster 4) — these look like they were stubs for a never-shipped "tonight overview" feature.
8. **Delete the 6 dead device discovery providers** (cluster 5) or wire the missing dome/weather/safety device cards.

After these cuts, the live provider count should drop from ~575 to ~470 (-18%).
