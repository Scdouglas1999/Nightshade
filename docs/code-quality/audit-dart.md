# CQ-AUDIT-DART: Dart/Flutter Code Quality Audit

**Branch:** `worktree-agent-a4e790e3a2f1f73f5`
**HEAD:** `bbdee9b` — "fixed a ton of bugs"
**Note:** Target commit `0c88691` is newer than HEAD; audit performed on HEAD as-is.
**Read-only:** only file written is this report.

---

## 1. Riverpod patterns

### a) Provider inventory (across `packages/` + `apps/`)

| Type | Count |
|---|---:|
| Generic `Provider<…>` | 120 |
| `FutureProvider` | 41 |
| `StreamProvider` | 16 |
| `StateProvider` | 76 |
| `StateNotifierProvider` | 13 |
| `AsyncNotifierProvider` | 8 |
| `NotifierProvider` | 0 |
| `ChangeNotifierProvider` | 1 |
| **Total `final …Provider =` definitions** | **407** |

Concentrated in `packages/nightshade_core/lib/src/providers/` (32 files, 248 providers). Top files: `science_provider.dart` (34), `imaging_provider.dart` (32), `database_provider.dart` (19), `equipment_provider.dart` (13), `weather_providers.dart` (13), `guiding_provider.dart` (13).

### b) `autoDispose` discipline

- **19 occurrences** across 6 files — almost entirely in `suggestion_filter_provider.dart`, `target_suggestion_provider.dart`, `transient_alert_provider.dart`, `auto_stretch_provider.dart`, `weather_providers.dart`.
- **Missing where it should be present** (page-scoped state held by global providers):
  - `packages/nightshade_app/lib/screens/framing/framing_search_provider.dart:1` — search results survive after leaving Framing screen.
  - `packages/nightshade_app/lib/screens/imaging/imaging_science_state.dart:1` — only used while Imaging screen mounted.
  - `packages/nightshade_app/lib/screens/dashboard/dashboard_layout_provider.dart:1` — kept across navigation; defensible but consider `keepAlive` semantics.
  - `packages/nightshade_app/lib/screens/sequencer/tabs/sequence_library_tab.dart:3` (3 page-scoped providers, none auto-dispose).
  - `packages/nightshade_app/lib/screens/sequencer/tabs/templates_tab.dart:3` (same).
  - `packages/nightshade_app/lib/screens/sequencer/tabs/targets_tab.dart:3`.
  - `packages/nightshade_app/lib/screens/equipment/widgets/discovery_panel.dart:1` — discovery scan results hang around.
  - `packages/nightshade_app/lib/screens/sequencer/widgets/preflight_validation_dialog.dart:1` — dialog-scoped.
  - `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_tree.dart:1`.
  - `packages/nightshade_app/lib/screens/sequencer/widgets/target_preview_tooltip.dart:1` — tooltip-scoped.

### c) `ref.watch` in callbacks (anti-pattern)

Scanned for `onPressed:/onTap: { … ref.watch(…) }`. **No violations found** — discipline is good; callbacks consistently use `ref.read`. Example correct pattern: `packages/nightshade_app/lib/screens/guiding/guiding_screen.dart:217` (`onPressed: () => ref.read(starImageProvider.notifier).refresh()`).

### d) `ref.listen` lifecycle

9 files use `ref.listen`. All checked are called inside `build()` (correct) or in `Provider` ctors (correct). Examples:

- `packages/nightshade_updater/lib/src/widgets/update_manager_widget.dart:227` — inside `build()`, fine.
- `packages/nightshade_app/lib/widgets/tutorial_overlay.dart:222` — inside `build()`, fine.
- `packages/nightshade_app/lib/widgets/contextual_tour_prompt.dart:146, 480` — inside `build()`, fine.
- `packages/nightshade_core/lib/src/providers/event_provider.dart:52, 80` — inside `Provider` ctor, fine.

No leaks identified.

### e) Provider files >300 lines (top 5)

| File | LOC | Refactor suggestion |
|---|---:|---|
| `packages/nightshade_core/lib/src/providers/sequence_provider.dart` | 3 533 | Split into `sequence_state_provider.dart` (notifier + state), `sequence_execution_provider.dart` (progress/checkpoint timers from lines 1549–1553), `sequence_library_provider.dart` (CRUD list), `sequence_validation_provider.dart`. |
| `packages/nightshade_core/lib/src/providers/framing_provider.dart` | 1 753 | Split `framing_search_provider.dart` (debouncer at 1515), `framing_overlay_provider.dart`, `framing_target_provider.dart`. |
| `packages/nightshade_core/lib/src/providers/equipment_provider.dart` | 1 540 | Split per device type (already 11 notifiers in one file): `mount_state_provider.dart`, `camera_state_provider.dart`, `focuser_state_provider.dart`, `filter_wheel_state_provider.dart`, `guider_state_provider.dart`, `rotator_state_provider.dart`, `dome_state_provider.dart`, `weather_state_provider.dart`, `safety_monitor_state_provider.dart`, `cover_calibrator_state_provider.dart`. |
| `packages/nightshade_core/lib/src/providers/settings_provider.dart` | 1 183 | Split per concern: `app_settings_provider.dart`, `notification_settings_provider.dart`, `theme_settings_provider.dart`. |
| `packages/nightshade_core/lib/src/providers/guiding_provider.dart` | 877 | Split `phd2_state_provider.dart`, `guide_stats_provider.dart`, `calibration_provider.dart`, `lock_position_provider.dart`. |

### f) `StateNotifier` missing `dispose()` when holding resources

62 `StateNotifier` subclasses; resource-holding ones audited:

- `packages/nightshade_core/lib/src/providers/equipment_provider.dart:24` (`CameraStateNotifier`) — holds `_retryAttempts` only; no resources; OK.
- `packages/nightshade_core/lib/src/providers/equipment_provider.dart:167` (`MountStateNotifier`) — holds `_positionPollTimer` (line 170); has `dispose()` at line 182. OK.
- `packages/nightshade_core/lib/src/providers/equipment_provider.dart:384, 550, 705, 825, 933, 1048, 1168, 1296, 1408` — **none** override `dispose()`. They subscribe to `backend.eventStream` only via constructor (no StreamSubscription field stored), so closure references the notifier even after `state` becomes unused. Verify: if `eventStream` is broadcast and notifier disappears, GC frees it, but explicit subscription cancellation is safer. **Recommend: each device notifier store a `StreamSubscription? _sub` and cancel in `dispose()`** (parallel to `weather_safety_provider.dart:128–130`).
- `packages/nightshade_core/lib/src/providers/guiding_provider.dart:614` (`BrainParamsNotifier`) — uses `ref.listen` (auto-cleaned by Ref). OK.
- `packages/nightshade_core/lib/src/providers/sequence_provider.dart:1549, 1552, 1553` — `_progressTimer`, `_nativeEventSubscription`, `_checkpointTimer`. Cancellation at 2771–2773 / 2925; **no `@override dispose()`** that calls all three. Risk: notifier replaced without `stopSequence()` invoked first leaks timers. **Add explicit `dispose()` override.**
- `packages/nightshade_core/lib/src/providers/framing_provider.dart:1515` (debounce timer) — cancelled in two paths (1521, 1652, 1658), no `dispose()` override. Same risk.
- `packages/nightshade_core/lib/src/providers/weather_safety_provider.dart:126` — properly disposed at 364–369. **Reference implementation.**

---

## 2. Widget hygiene

### a) Largest `build` methods / monolithic widgets

Screen files with one or two top-level classes containing build methods >1 000 lines each:

| File | LOC | Top-level classes |
|---|---:|---|
| `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` | 7 079 | 1 entry class at L36 + many private widgets |
| `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` | 5 847 | `PlanetariumScreen` at L55 |
| `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` | 5 751 | `DashboardScreen` at L134 |
| `packages/nightshade_app/lib/screens/sequencer/widgets/node_properties_panel.dart` | 4 871 | Single panel switching per node type |
| `packages/nightshade_app/lib/screens/settings/settings_screen.dart` | 4 814 | One settings root + many private sections |
| `packages/nightshade_app/lib/screens/framing/framing_screen.dart` | 4 688 | One screen |
| `packages/nightshade_app/lib/screens/sequencer/tabs/templates_tab.dart` | 3 900 | One tab |
| `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart` | 2 981 | One screen |
| `packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart` | 2 723 | One tab |
| `packages/nightshade_app/lib/screens/settings/equipment_profiles_screen.dart` | 2 296 | One screen |

### b) Missing `const` constructors

`flutter_lints: ^3.0.1` does **not** enable `prefer_const_constructors`. Only **1** info appears in the app analyzer output (in `altitude_plot.dart:102`). The real population is large but invisible. **Recommend enabling `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `prefer_const_declarations` in shared `analysis_options.yaml`.**

### c) `StatefulWidget` missing `dispose()` for held resources

Sample audit of `TextEditingController` (59 occurrences across 14 files, plus `AnimationController` in 43 files):

- `packages/nightshade_app/lib/screens/settings/settings_screen.dart` — 18 controllers, **all 18 disposed** at L1168–3288. Clean.
- `packages/nightshade_app/lib/screens/equipment/dialogs/profile_editor_dialog.dart` — 15 controllers; spot-check shows dispose pattern present.
- `packages/nightshade_app/lib/screens/sequencer/sequencer_screen.dart` — 1 controller; dispose covered.

Pattern is generally good. Spot-check `apps/desktop/lib/screens/sequencer/tabs/targets_tab.dart` (1 controller) to confirm.

### d) `Future.delayed` in `initState` / unprotected delays

25 occurrences in `packages/nightshade_app/lib/`. Risky ones:

- `packages/nightshade_app/lib/screens/flat_wizard/widgets/flat_preview_panel.dart:566` — `Future.delayed(100ms, () { … setState(…) })` inside `_startCountdownTimer()` called from `initState` L562. No cancellation, no `mounted` guard around the delayed callback. **Leak/late-setState risk.**
- `packages/nightshade_app/lib/widgets/contextual_tour_prompt.dart:111, 404` — same pattern; uses `mounted` guard inside but no timer handle to cancel.
- `packages/nightshade_app/lib/widgets/notification_toast_overlay.dart:57` — toast 300 ms delay; `mounted` guard present.
- `packages/nightshade_app/lib/widgets/transient_alert_badge.dart:75` — `Future.delayed(3600ms)`.
- `packages/nightshade_app/lib/screens/sequencer/widgets/meridian_flip_progress_dialog.dart:122` — 2 s delay; needs cancellation on dispose.
- `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_tree.dart:591` — `_panelPersistDuration` delay; appears unguarded.

**Recommend: replace `Future.delayed` + `setState` with `Timer` stored on the State, cancelled in `dispose()` — same fix template as `W7-TIMER-LEAK`.**

### e) `setState` after `await` without `if (mounted)`

Manual sampling of grep hits:

- `packages/nightshade_app/lib/screens/analytics/widgets/science_analytics_tab.dart:1393–1405` — `await … generateLineRatios(…)` then `setState(…)`; no `mounted` check in between.
- `packages/nightshade_app/lib/screens/settings/equipment_profiles_screen.dart:66–67, 141–142, 313–314` — `await … updateProfile(updatedProfile)` then `setState(…)`; **three sites without mounted guard** (analyzer also flagged 4 unrelated-mounted-check hits in same file at L339–375).

### f) Dynamic-list keys

Not exhaustively grepped; sampling sequencer trees (`sequence_tree.dart`) shows widgets are reordered without explicit `Key()` — investigate if drag-and-drop state corruption was ever reported.

---

## 3. Build performance

### a) `MediaQuery.of(context).<accessor>` vs `MediaQuery.sizeOf(context)`

- **26 violations** across 15 files of `MediaQuery.of(context).size / padding / viewInsets / orientation` (forces full rebuild on any MQ change).
- Only **16 uses** of the finer `MediaQuery.sizeOf` / `paddingOf` / `viewInsetsOf` API (mostly in `packages/nightshade_ui/lib/src/utils/responsive_utils.dart`).
- Worst offenders: `packages/nightshade_app/lib/screens/framing/framing_screen.dart` (4), `packages/nightshade_planetarium/lib/src/widgets/framing_view.dart` (4), `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` (3), `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` (2), `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (2).

### b) `Theme.of(context).extension<NightshadeColors>()` reads

235 calls across 113 files. Sampling (`packages/nightshade_app/lib/screens/imaging/tabs/camera_tab.dart` L82, 263, 298, 450) confirms **one read per build at top of method** — pattern is correct. No nested re-reads observed in spot checks.

### c) `ListView` without `itemExtent`

Not enumerated end-to-end; recommend a follow-up grep on long lists in sequence_tree, image_thumbnail_strip, transients_screen.

### d) `setState` inside `build`

No matches in grep — clean.

---

## 4. Lint debt analysis

### `packages/nightshade_core` (185 issues after pub get)

| Count | Rule | Example |
|---:|---|---|
| 144 | `deprecated_member_use_from_same_package` | `lib/src/models/equipment/discovery_state.dart:23` — `DriverBackend` deprecated, use `DriverType` |
| 16 | `undefined_identifier` | Stale `nightshade_core.dart:35` export of removed `target_models.dart` |
| 9 | `unnecessary_import` | `test/services/target_suggestion_service_test.dart:6` |
| 5 | `undefined_class` | Stale references after model rename |
| 3 | `uri_does_not_exist` | `lib/nightshade_core.dart:35` |
| 3 | `unnecessary_null_comparison` | – |
| 3 | `unnecessary_non_null_assertion` | – |
| 1 | `undefined_function` | – |
| 1 | `non_type_as_type_argument` | – |

**Fix strategy:** delete the deprecated `DriverBackend` / `AvailableDevice` shims (used 144× from same-package; safe to migrate all callers to `DriverType` / `DeviceInfo` in one sweep, then remove the deprecated names from `lib/src/models/equipment/discovery_state.dart`). Update `lib/nightshade_core.dart:35` to remove dead export of `target_models.dart`.

### `packages/nightshade_app` (67 issues)

| Count | Rule | Example | Fix |
|---:|---|---|---|
| 19 | `deprecated_member_use` | `node_properties_panel.dart:2613` `activeColor` → `activeThumbColor` | Rename per Flutter 3.31 migration |
| 14 | `curly_braces_in_flow_control_structures` | – | Add braces around single-line `if` bodies |
| 10 | `undefined_identifier` | Stale references (mostly test-fixture types) | Delete/repair fixtures |
| 9 | `implementation_imports` | `analytics_screen.dart:8` imports `package:nightshade_core/src/…` | Promote needed items to public barrel `nightshade_core.dart` |
| 7 | `use_build_context_synchronously` | `connections_tab.dart:183` (no mounted check); `equipment_profiles_screen.dart:339` (unrelated mounted check) | Capture `Navigator/ScaffoldMessenger` before await, or add `if (!context.mounted) return;` |
| 2 | `unused_element` | – | Delete |
| 2 | `undefined_class` | Stale test fixtures | Delete/repair |
| 2 | `prefer_const_declarations` | – | Add `const` |
| 1 | `unnecessary_getters_setters` | – | Use field directly |
| 1 | `prefer_const_constructors` | `altitude_plot.dart:102` | Add `const` |

### `apps/desktop` (157 issues)

| Count | Rule | Notable |
|---:|---|---|
| **143** | `avoid_print` | **134 in `apps/desktop/lib/main.dart`**, 8 in `widgets/update_manager.dart`, 1 in `screens/framing/framing_search_provider.dart`. Use `LoggingService` (`packages/nightshade_core/lib/src/services/logging_service.dart`). |
| 8 | `deprecated_member_use` | – |
| 5 | `undefined_identifier` | – |
| 1 | `undefined_class` | – |

### `packages/nightshade_planetarium` (4 issues)

3× `deprecated_member_use` — `Color.value` deprecated. Use `.toARGB32()` or component accessors `.r/.g/.b`. Files: `lib/src/rendering/sky_renderer.dart:485`, `lib/src/rendering/star_psf_cache.dart:25`.

### `packages/nightshade_ui` — **0 issues**.

### Analyzer config gap

All 10 packages pin `flutter_lints: ^3.0.1` (current is 5.x). The 3.x ruleset omits `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `unawaited_futures`, `use_super_parameters`, `library_private_types_in_public_api`. Migrating to `flutter_lints: ^5.0.0` would surface hundreds of additional improvements.

---

## 5. Async pattern hygiene

- **`unawaited(...)`** appears only **7 times** across 3 files (`packages/nightshade_bridge/lib/src/frb_generated.dart:1`, `packages/nightshade_core/lib/src/services/imaging_service.dart:1`, `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart:5`). With `unawaited_futures` disabled by `flutter_lints` 3.x there is no analyzer signal here. Likely many silent dropped futures.
- **`Timer` / `Timer.periodic`** usage in 113 files; sampled providers all cancel in `dispose()` (good: `weather_safety_provider.dart:364`, `auto_save_service.dart:333`). Sequence provider should add explicit `dispose()` (see §1f).
- **`StreamSubscription`** held in `Timer?`/`StreamSubscription?` fields across 12 audited providers — all cancel correctly except confirm `equipment_provider.dart` device notifiers (§1f).

---

## 6. Dart 3 idiom under-utilization

### a) Pattern matching

- 0 `sealed class`, 0 `final class`, 0 `base class`, 0 `interface class` declarations in production code (1 in `packages/nightshade_updater/lib/nightshade_updater.dart`, 1 in `packages/nightshade_bridge` per-file). Wide opportunity.
- `if (x is XNode)` chains in 12 files for `SequenceNode` subclasses: `node_properties_panel.dart`, `node_progress_panels.dart`, `sequence_tree.dart`, `sequence_timeline.dart`, `target_header_card.dart`, `sequence_repository.dart`, `sequence_file_service.dart`, `backup_service.dart`, `sequence_provider.dart`, `template_snippet_provider.dart`, `sequence_time_estimator.dart`, `sequence_models.dart` itself. All would benefit from `sealed class SequenceNode` + `switch (node)` exhaustiveness.

### b) Records

- 0 `Tuple2` / `Pair<` usage (good — not bloated with old packages).
- 978 `Map<String, dynamic>` usages — most are JSON, but several `Map<String,dynamic>`-typed return values in services could be records when the keys are known/closed. Spot 5:
  - `packages/nightshade_core/lib/src/providers/profiles_provider.dart:1` (1 use)
  - `packages/nightshade_core/lib/src/providers/template_snippet_provider.dart:4` (4 uses)
  - `packages/nightshade_core/lib/src/providers/science_provider.dart:2`
  - `packages/nightshade_core/lib/src/providers/imaging_provider.dart:1`
  - `packages/nightshade_core/lib/src/services/sequence_repository.dart:2`

### c) Sealed classes

- `abstract class SequenceNode extends Equatable` at `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart:151` — **prime candidate** for `sealed class` (12 downstream `is`-chains). Same for `enum NodeCategory` consumers in `node_properties_panel.dart`.
- `enum DeviceConnectionState` (`equipment_models.dart:10`) + each `class XState extends Equatable` — could become a Dart 3 `sealed` state hierarchy with `Connected` / `Connecting` / `Disconnected` / `Error` variants instead of mutable `connectionState` field.

### d) Class modifiers (`final`/`base`)

Top candidates to mark `final class` (no intended subclasses, would catch accidental extension):

- `packages/nightshade_core/lib/src/models/equipment/equipment_models.dart:225` `CameraState` (and L345 `MountState`, L436 `FocuserState`, L512 `FilterWheelState`, L575 `GuiderState`, L641 `RotatorState`, L705 `DomeState`, L776 `WeatherState`, L872 `SafetyMonitorState`, L946 `CoverCalibratorState`).
- `packages/nightshade_core/lib/src/models/autofocus_progress.dart:5` `AutofocusProgressData`.
- `packages/nightshade_core/lib/src/models/equipment/equipment_models.dart:43` `DeviceError`.

---

## 7. Package dependency hygiene

### Direct dependency counts

| Package | Direct deps |
|---|---:|
| `packages/nightshade_app` | 30 |
| `packages/nightshade_ui` | 10 |
| `packages/nightshade_planetarium` | 13 |
| `packages/nightshade_bridge` | 15 |
| `packages/nightshade_webrtc` | 17 |
| `packages/nightshade_updater` | 22 |
| `packages/nightshade_plugins` | 4 |
| `apps/desktop` | 42 |
| `apps/mobile` | 34 |

### Issues

- **`flutter_lints: ^3.0.1`** in all 10 packages — two major versions behind (5.x current). Upgrading enables `prefer_const_constructors`, `unawaited_futures`, etc.
- **Riverpod version drift**: `packages/nightshade_app` uses `^2.5.1`; everywhere else `^2.4.9`. Pin to one version (CLAUDE.md states 2.5.1 is canonical).
- **Floating-only** `^` constraints throughout — no `=` pins observed. `pub get` reports "63 packages have newer versions incompatible with dependency constraints" in core alone — significant stale-dep surface.
- **`dependency_overrides: build_resolvers: 2.4.2`** in `packages/nightshade_core/pubspec.yaml:55` — workaround for `build_runner` bug; flagged as tech debt to revisit on next build_runner upgrade.
- **No deprecated packages** found in direct deps (verified `path_provider: ^2.1.2`, `package_info_plus` absent, `flutter_secure_storage` absent). Clean here.
- **`dev_dependencies` leakage** — none observed; clean separation.

---

## 8. Generated vs hand-written LOC

| Package | Total | Generated | Hand | % gen |
|---|---:|---:|---:|---:|
| `packages/nightshade_app` | 119 610 | 0 | 119 610 | 0 % |
| `packages/nightshade_core` | 115 205 | 48 587 | 66 618 | 42 % |
| `packages/nightshade_ui` | 10 788 | 0 | 10 788 | 0 % |
| `packages/nightshade_planetarium` | 20 032 | 0 | 20 032 | 0 % |
| `packages/nightshade_bridge` | 89 183 | 76 882 | 12 301 | **86 %** |
| `packages/nightshade_webrtc` | 6 539 | 1 199 | 5 340 | 18 % |
| `packages/nightshade_updater` | 3 883 | 1 901 | 1 982 | **49 %** |
| `packages/nightshade_plugins` | 1 096 | 0 | 1 096 | 0 % |
| `apps/desktop` | 14 366 | 0 | 14 366 | 0 % |
| `apps/mobile` | 2 723 | 0 | 2 723 | 0 % |

**Flagged:** `nightshade_bridge` at 86 % generated is expected (FRB), but the `12 301` hand-written lines should be re-checked to be sure they aren't duplicating things the FRB layer already gives us. `nightshade_updater` at 49 % is borderline — review whether the freezed model count there is justified.

---

## 9. Large screens deep-dive

### `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (7 079 LOC)

- Top-level `class ImagingScreen extends ConsumerStatefulWidget` at L36; `_buildMobileLayout` L285, `_buildDesktopLayout` L359, `_buildControlPanel` L458. Several private widget classes (L780, L1825, L1875, L1931, L2038, …).
- **Decomposition:**
  - `imaging_screen.dart` → root only (≤200 LOC).
  - `imaging_layout_mobile.dart`, `imaging_layout_desktop.dart`.
  - `imaging_control_panel.dart` (current `_buildControlPanel`).
  - `imaging_annotation_banner.dart` (current `_AnnotationCatalogBanner`).
  - Move tab content to existing `tabs/`.
  - Each private state class (≥7) → its own file.

### `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` (5 847 LOC)

- Single `PlanetariumScreen` (L55) handles HUD, controls, time scrubber, search, settings drawer, framing overlay.
- **Decomposition:** `planetarium_screen.dart` (shell), `planetarium_hud.dart`, `planetarium_search_dialog.dart`, `planetarium_settings_drawer.dart`, `planetarium_object_panel.dart`, `planetarium_time_controls.dart`, `planetarium_framing_overlay.dart`.

### `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` (5 751 LOC)

- `DashboardScreen` at L134. Two `Future.delayed` at L3521, L5616, L5619 (countdown/refresh) — convert to cancellable Timers (see §2d).
- **Decomposition:** `dashboard_screen.dart` (layout grid), `widgets/` folder for each card type (capture, equipment, weather, sequence, science, alerts).

### `packages/nightshade_app/lib/screens/sequencer/sequencer_screen.dart` (1 471 LOC) + sister files

- Existing `widgets/` directory; six widget files >1 000 LOC each (`node_properties_panel.dart` 4 871, `snippet_palette.dart` 1 334, `sequence_tree.dart` 1 329, `node_progress_panels.dart` 1 318) — these duplicate the screen's complexity instead of taming it.
- **Decomposition for `node_properties_panel.dart`:** one file per node-type editor (`expose_node_editor.dart`, `slew_node_editor.dart`, `autofocus_node_editor.dart`, etc.) selected by a dispatcher widget. Already 12 places do `node is …Node` checks — convert to a sealed-class visitor (§6c).

### `packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart` (2 723 LOC)

- One `_ConnectionsTabState`. Three `use_build_context_synchronously` violations at L183/221/283. Decompose by device type into per-device panels.

### `packages/nightshade_app/lib/screens/equipment/dialogs/profile_editor_dialog.dart` (2 012 LOC, 15 controllers)

- One dialog handling all device profile fields. Split into per-device sub-forms; share via a `ProfileEditorFormController`.

### `apps/desktop/lib/headless_api_server.dart` (1 352 LOC)

- Single `class HeadlessApiServer` (L16). Already has handler modules in `lib/headless_api/handlers/*`. The shell file should be ≤300 LOC of routing wiring; current size indicates request-shape parsing is happening in the shell — move to handler files or a `request_parser.dart`.

### `apps/desktop/lib/main.dart` (1 406 LOC)

- Houses the 134 `avoid_print` violations. Split into `main.dart` (≤100 LOC bootstrapping), `desktop_app_bootstrap.dart` (window manager, FFI init), `desktop_logging_init.dart` (replace prints with `LoggingService`).

---

## 10. Quick-win punch list

Sorted by impact-per-effort, highest first.

| # | Item | Type | Effort | Impact | Reasoning |
|---:|---|---|:-:|:-:|---|
| 1 | Replace 134× `print()` in `apps/desktop/lib/main.dart` with `LoggingService` | lint-fix | S | High | Clears 85 % of all desktop lint debt; production logs become structured/filterable |
| 2 | Delete deprecated `DriverBackend` / `AvailableDevice` shims in `packages/nightshade_core/lib/src/models/equipment/discovery_state.dart`, migrate 144 same-package call sites to `DriverType` / `DeviceInfo` | delete-deprecated | M | High | 78 % of all core lint debt; removes naming ambiguity flagged in CLAUDE memory |
| 3 | Upgrade `flutter_lints: ^3.0.1` → `^5.0.0` across all 10 packages, enable `prefer_const_constructors`, `unawaited_futures`, `use_super_parameters` | lint-rule-enable | S | High | Surfaces silently-dropped futures and missing `const`s across 250 k LOC at near-zero cost |
| 4 | Align Riverpod to `^2.5.1` in 8 packages (currently `^2.4.9`); only `nightshade_app` is on 2.5.1 | dep-pin | S | Med | Eliminates duplicate-class FFI risk; CLAUDE.md says 2.5.1 is canonical |
| 5 | Add explicit `dispose()` override to `SequenceExecutionNotifier` (`sequence_provider.dart:1549–1553`) and 9 device notifiers in `equipment_provider.dart` (mirror `weather_safety_provider.dart:364`) | dispose-hook | M | High | Prevents Timer/StreamSubscription leaks on notifier replacement — silent bug class |
| 6 | Add `autoDispose` to 10 page-scoped providers (framing/search, imaging/science, sequencer/tabs, equipment/discovery, sequencer/dialogs) | autodispose | S | Med | Drops memory after navigation; recovers fresh state on revisit |
| 7 | Replace 25 `Future.delayed`+`setState` patterns with cancellable `Timer` fields disposed on widget tear-down | dispose-hook | M | High | Same root cause as `W7-TIMER-LEAK`; eliminates "setState after dispose" exceptions class-wide |
| 8 | Migrate `abstract class SequenceNode` → `sealed class` + convert 12 `is`-chain sites to exhaustive `switch (node)` | refactor-sealed | M | Med | Compile-time exhaustiveness; future node types can't be missed in panels/repos |
| 9 | Split `equipment_provider.dart` (1 540 LOC, 11 notifiers) into 10 per-device files | extract-widget | M | Med | Each device team can iterate independently; cuts file lock contention |
| 10 | Convert 26 `MediaQuery.of(context).<accessor>` calls to `MediaQuery.sizeOf` / `paddingOf` / `viewInsetsOf` | perf-rebuild | S | Low-Med | Reduces frame rebuilds during keyboard show/orientation change |

### Top 3 highest-impact (inline)

1. Replace 134 `print()` in `apps/desktop/lib/main.dart` with `LoggingService` — clears 85 % of desktop lint debt.
2. Delete deprecated `DriverBackend`/`AvailableDevice` in `discovery_state.dart`, migrate 144 call sites — clears 78 % of core lint debt.
3. Add `dispose()` overrides to `SequenceExecutionNotifier` and 9 device notifiers — closes silent Timer/Stream leak class.

